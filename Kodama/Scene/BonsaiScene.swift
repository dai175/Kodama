//
//  BonsaiScene.swift
//  Kodama
//
//  Created by Daisuke Ooba on 2026/04/02.
//

import SceneKit
import UIKit

// MARK: - BonsaiScene

final class BonsaiScene {
    // MARK: Internal

    let scene: SCNScene
    let cameraNode: SCNNode
    let treeAnchor: SCNNode

    private(set) var isAutoRotating = true

    // MARK: Private

    private let rotationNode: SCNNode
    private let rotationAction: SCNAction
    private let cameraTargetNode: SCNNode
    private var idleTimer: Timer?

    // MARK: - Initialization

    init() {
        scene = SCNScene()
        cameraNode = SCNNode()
        treeAnchor = SCNNode()
        rotationNode = SCNNode()
        cameraTargetNode = SCNNode()
        rotationAction = SCNAction.repeatForever(
            SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 1080)
        )

        setupBackground()
        setupCamera()
        setupLights()
        setupPot()
        setupRotation()
    }

    // MARK: - Auto-Rotation Control

    func stopAutoRotation() {
        guard isAutoRotating else { return }
        isAutoRotating = false
        rotationNode.removeAction(forKey: "autoRotate")
        idleTimer?.invalidate()
        idleTimer = nil
    }

    func scheduleAutoRotationResume() {
        idleTimer?.invalidate()
        DispatchQueue.main.async { [weak self] in
            self?.idleTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                self?.resumeAutoRotation()
            }
        }
    }

    // MARK: - Private Setup

    private func setupBackground() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 256))
        let gradientImage = renderer.image { context in
            let colors = [
                UIColor(red: 10 / 255, green: 26 / 255, blue: 18 / 255, alpha: 1).cgColor,
                UIColor(red: 13 / 255, green: 40 / 255, blue: 24 / 255, alpha: 1).cgColor
            ]
            // swiftlint:disable force_unwrapping
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: [0, 1]
            )! // CGGradient with valid colorspace and locations never returns nil
            // swiftlint:enable force_unwrapping
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: 256),
                options: []
            )
        }
        scene.background.contents = gradientImage
    }

    private func setupCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 40
        camera.zNear = 0.1
        camera.zFar = 100

        cameraNode.camera = camera
        cameraNode.position = defaultCameraPosition

        let lookAtConstraint = SCNLookAtConstraint(target: nil)
        lookAtConstraint.isGimbalLockEnabled = true

        cameraTargetNode.position = SCNVector3(0, 2.1, 0)
        scene.rootNode.addChildNode(cameraTargetNode)

        lookAtConstraint.target = cameraTargetNode
        cameraNode.constraints = [lookAtConstraint]

        scene.rootNode.addChildNode(cameraNode)
    }

    private func setupLights() {
        let directionalLight = SCNLight()
        directionalLight.type = .directional
        directionalLight.intensity = 800
        directionalLight.castsShadow = true
        directionalLight.shadowMode = .deferred
        directionalLight.shadowSampleCount = 4

        let directionalNode = SCNNode()
        directionalNode.light = directionalLight
        directionalNode.position = SCNVector3(-3, 6, 3)
        directionalNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(directionalNode)

        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 200
        ambientLight.color = UIColor(red: 255 / 255, green: 244 / 255, blue: 229 / 255, alpha: 1)

        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)
    }

    private func setupPot() {
        // 半球ボウル: 底は小さな footprint、側面が外側に膨らんで上端リムへ
        // y=3 の inner が土を受けるリム直下の開口半径
        let layers: [(outer: Float, inner: Float)] = [
            (outer: 2.8, inner: 0.0), // y=0  底: 半径 2.8 のソリッド円盤
            (outer: 5.0, inner: 3.4), // y=1  曲率の立ち上がり
            (outer: 6.3, inner: 4.8), // y=2  側面ふくらみ
            (outer: 6.9, inner: 5.6), // y=3  土を受けるリム直下層
            (outer: 7.2, inner: 6.0) // y=4  リム（上端）
        ]

        let pot = buildPotNode(layers: layers)
        pot.name = "pot"
        rotationNode.addChildNode(pot)

        let soilLayerIndex = layers.count - 2
        let soilY = Float(soilLayerIndex) * VoxelConstants.renderScale
        let soil = buildSoilNode(
            y: soilY,
            innerRadius: layers[soilLayerIndex].inner,
            lowerInnerRadius: layers[soilLayerIndex - 1].inner
        )
        soil.name = "soil"
        rotationNode.addChildNode(soil)

        treeAnchor.position = SCNVector3(0, soilY + VoxelConstants.renderScale, 0)
        treeAnchor.name = "treeAnchor"
        rotationNode.addChildNode(treeAnchor)
    }

    private func buildPotNode(layers: [(outer: Float, inner: Float)]) -> SCNNode {
        let bs = VoxelConstants.renderScale

        // 5色木目パレット
        let woodShadowGeom = voxelGeom("#6B3F20", roughness: 0.85)
        let woodDarkGeom = voxelGeom("#8C5830", roughness: 0.85)
        let woodBaseGeom = voxelGeom("#A07040", roughness: 0.85)
        let woodWarmGeom = voxelGeom("#B07548", roughness: 0.85)
        let woodLightGeom = voxelGeom("#C69060", roughness: 0.85)

        let maxGridRange = Int(ceil(layers.map(\.outer).max() ?? 0))
        let potParent = SCNNode()

        for (yLayer, layer) in layers.enumerated() {
            let yPos = Float(yLayer) * bs
            let isRim = yLayer == layers.count - 1
            let isBottom = yLayer == 0

            for bx in -maxGridRange ... maxGridRange {
                for bz in -maxGridRange ... maxGridRange {
                    let dist = sqrt(Float(bx * bx + bz * bz))
                    guard dist <= layer.outer, isBottom || dist > layer.inner else { continue }

                    let j = potVoxelJitter(x: bx, y: yLayer, z: bz)

                    // リム欠け・側面凹凸: 外周一部をスキップ（リムは確率高め）
                    if dist > layer.outer - 1.0, j > (isRim ? 0.9 : 0.95) { continue }

                    let node = SCNNode()
                    if isRim {
                        if j < 0.10 {
                            node.geometry = woodDarkGeom
                        } else if j < 0.35 {
                            node.geometry = woodWarmGeom
                        } else {
                            node.geometry = woodLightGeom
                        }
                    } else if isBottom {
                        node.geometry = j < 0.30 ? woodDarkGeom : woodShadowGeom
                    } else if dist > layer.outer - 1.0 {
                        // 側面外周
                        if j < 0.20 {
                            node.geometry = woodShadowGeom
                        } else if j < 0.35 {
                            node.geometry = woodBaseGeom
                        } else {
                            node.geometry = woodDarkGeom
                        }
                    } else {
                        // 側面本体
                        if j < 0.05 {
                            node.geometry = woodShadowGeom
                        } else if j < 0.15 {
                            node.geometry = woodDarkGeom
                        } else if j < 0.30 {
                            node.geometry = woodWarmGeom
                        } else {
                            node.geometry = woodBaseGeom
                        }
                    }
                    node.position = SCNVector3(Float(bx) * bs, yPos, Float(bz) * bs)
                    potParent.addChildNode(node)
                }
            }
        }
        return potParent.flattenedClone()
    }

    private func buildSoilNode(y: Float, innerRadius: Float, lowerInnerRadius: Float) -> SCNNode {
        let bs = VoxelConstants.renderScale

        // 3色ソイルパレット
        let soilDeepGeom = voxelGeom("#231912", roughness: 0.9)
        let soilBaseGeom = voxelGeom("#32261B", roughness: 0.9)
        let soilWarmGeom = voxelGeom("#413020", roughness: 0.9)

        let soilParent = SCNNode()
        let gridRange = Int(ceil(innerRadius))
        for bx in -gridRange ... gridRange {
            for bz in -gridRange ... gridRange {
                let dist = sqrt(Float(bx * bx + bz * bz))
                guard dist <= innerRadius else { continue }

                let j = potVoxelJitter(x: bx, y: 0, z: bz)
                // 外周凹凸: 一部voxelを1段下げる（下げた先の内半径を超える場合はスキップ）
                let lowered = dist > innerRadius - 1.2 && j > 0.7
                guard !lowered || dist <= lowerInnerRadius else { continue }
                let actualY = lowered ? y - bs : y

                let soilNode = SCNNode()
                if j < 0.15 {
                    soilNode.geometry = soilDeepGeom
                } else if j < 0.35 {
                    soilNode.geometry = soilWarmGeom
                } else {
                    soilNode.geometry = soilBaseGeom
                }
                soilNode.position = SCNVector3(Float(bx) * bs, actualY, Float(bz) * bs)
                soilParent.addChildNode(soilNode)
            }
        }
        return soilParent.flattenedClone()
    }

    /// カラーと roughness を受け取り、共有可能な voxel ジオメトリを返す。
    /// 同色の voxel は同じインスタンスを使いまわすこと（呼び出し元で保持）。
    private func voxelGeom(_ hex: String, roughness: CGFloat) -> SCNGeometry {
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        mat.diffuse.contents = UIColor(hex: hex)
        mat.roughness.contents = roughness
        let geom = SCNBox(
            width: VoxelConstants.cgBlockSize,
            height: VoxelConstants.cgBlockSize,
            length: VoxelConstants.cgBlockSize,
            chamferRadius: 0
        )
        geom.materials = [mat]
        return geom
    }

    private func setupRotation() {
        rotationNode.name = "rotationRoot"
        scene.rootNode.addChildNode(rotationNode)
        rotationNode.runAction(rotationAction, forKey: "autoRotate")
    }

    private func resumeAutoRotation() {
        guard !isAutoRotating else { return }
        isAutoRotating = true
        rotationNode.runAction(rotationAction, forKey: "autoRotate")
    }

    var defaultCameraPosition: SCNVector3 {
        SCNVector3(0, 4.6, 12.5)
    }
}

// MARK: - File-private helpers

/// 座標から決定論的な 0..<1 の値を返す。木目・凹凸のランダム配置に使用。
/// 視覚ロック済み — 式を変えると木目配置が変わるため変更しないこと。
private func potVoxelJitter(x: Int, y: Int, z: Int) -> Float {
    var hash = UInt32(bitPattern: Int32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263 &+ z &* 2_246_822_519))
    hash = (hash ^ (hash >> 13)) &* 1_274_126_177
    hash = hash ^ (hash >> 16)
    return Float(hash) / Float(UInt32.max)
}
