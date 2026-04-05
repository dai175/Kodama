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

    // swiftlint:disable function_body_length cyclomatic_complexity
    private func setupPot() {
        let bs = VoxelConstants.renderScale
        let cs = CGFloat(VoxelConstants.renderScale)
        let potParent = SCNNode()

        // 5色木目パレット
        let woodShadowMat = SCNMaterial()
        woodShadowMat.diffuse.contents = UIColor(hex: "#6B3F20")
        woodShadowMat.roughness.contents = 0.85

        let woodDarkMat = SCNMaterial()
        woodDarkMat.diffuse.contents = UIColor(hex: "#8C5830")
        woodDarkMat.roughness.contents = 0.85

        let woodBaseMat = SCNMaterial()
        woodBaseMat.diffuse.contents = UIColor(hex: "#A07040")
        woodBaseMat.roughness.contents = 0.85

        let woodWarmMat = SCNMaterial()
        woodWarmMat.diffuse.contents = UIColor(hex: "#B07548")
        woodWarmMat.roughness.contents = 0.85

        let woodLightMat = SCNMaterial()
        woodLightMat.diffuse.contents = UIColor(hex: "#C69060")
        woodLightMat.roughness.contents = 0.85

        let woodShadowGeom = SCNBox(width: cs, height: cs, length: cs, chamferRadius: 0)
        woodShadowGeom.materials = [woodShadowMat]

        let woodDarkGeom = SCNBox(width: cs, height: cs, length: cs, chamferRadius: 0)
        woodDarkGeom.materials = [woodDarkMat]

        let woodBaseGeom = SCNBox(width: cs, height: cs, length: cs, chamferRadius: 0)
        woodBaseGeom.materials = [woodBaseMat]

        let woodWarmGeom = SCNBox(width: cs, height: cs, length: cs, chamferRadius: 0)
        woodWarmGeom.materials = [woodWarmMat]

        let woodLightGeom = SCNBox(width: cs, height: cs, length: cs, chamferRadius: 0)
        woodLightGeom.materials = [woodLightMat]

        // 決定論的 0..<1 乱数（seed = 座標）— 視覚チューニング値
        let jitter: (Int, Int, Int) -> Float = { x, y, z in
            // swiftlint:disable:next identifier_name
            var h =
                UInt32(bitPattern: Int32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263 &+ z &*
                        2_246_822_519))
            h = (h ^ (h >> 13)) &* 1_274_126_177
            h = h ^ (h >> 16)
            return Float(h) / Float(UInt32.max)
        }

        // 半球ボウル: 底は小さな footprint、側面が外側に膨らんで上端リムへ
        let layers: [(Float, Float)] = [
            (2.8, 0.0), // y=0  底: 半径 2.8 のソリッド円盤
            (5.0, 3.4), // y=1  曲率の立ち上がり
            (6.3, 4.8), // y=2  側面ふくらみ
            (6.9, 5.6), // y=3  土を受ける層
            (7.2, 6.0) // y=4  リム（上端）
        ]
        let maxGridRange = Int(ceil(layers.map(\.0).max() ?? 0))

        for (yLayer, (outerRadius, innerRadius)) in layers.enumerated() {
            let yPos = Float(yLayer) * bs
            let isRim = yLayer == layers.count - 1
            let isBottom = yLayer == 0

            for bx in -maxGridRange ... maxGridRange {
                for bz in -maxGridRange ... maxGridRange {
                    let dist = sqrt(Float(bx * bx + bz * bz))
                    let inOuter = dist <= outerRadius
                    let inInner = dist <= innerRadius
                    guard inOuter, isBottom || !inInner else { continue }

                    let j = jitter(bx, yLayer, bz)

                    // リムの欠け: 最上層外周の一部をスキップ
                    if isRim, dist > outerRadius - 1.0, j > 0.9 { continue }
                    // 側面シルエットの微小凹凸: リム以外の外周一部をスキップ
                    if !isRim, dist > outerRadius - 1.0, j > 0.95 { continue }

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
                        if j < 0.30 {
                            node.geometry = woodDarkGeom
                        } else {
                            node.geometry = woodShadowGeom
                        }
                    } else if dist > outerRadius - 1.0 {
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

        let pot = potParent.flattenedClone()
        pot.name = "pot"
        rotationNode.addChildNode(pot)

        // 土（ソイル）: リムの1層下
        let soilY = Float(layers.count - 2) * bs // = 3 * 0.25 = 0.75
        let soilInnerRadius = layers[layers.count - 2].1 // = 5.6
        let soilGridRange = Int(ceil(soilInnerRadius))

        let soilDeepMat = SCNMaterial()
        soilDeepMat.diffuse.contents = UIColor(
            red: 35 / 255, green: 25 / 255, blue: 18 / 255, alpha: 1
        )
        soilDeepMat.roughness.contents = 0.9

        let soilBaseMat = SCNMaterial()
        soilBaseMat.diffuse.contents = UIColor(
            red: 50 / 255, green: 38 / 255, blue: 27 / 255, alpha: 1
        )
        soilBaseMat.roughness.contents = 0.9

        let soilWarmMat = SCNMaterial()
        soilWarmMat.diffuse.contents = UIColor(
            red: 65 / 255, green: 48 / 255, blue: 32 / 255, alpha: 1
        )
        soilWarmMat.roughness.contents = 0.9

        let soilDeepGeom = SCNBox(width: cs, height: cs, length: cs, chamferRadius: 0)
        soilDeepGeom.materials = [soilDeepMat]

        let soilBaseGeom = SCNBox(width: cs, height: cs, length: cs, chamferRadius: 0)
        soilBaseGeom.materials = [soilBaseMat]

        let soilWarmGeom = SCNBox(width: cs, height: cs, length: cs, chamferRadius: 0)
        soilWarmGeom.materials = [soilWarmMat]

        let soilParent = SCNNode()
        for bx in -soilGridRange ... soilGridRange {
            for bz in -soilGridRange ... soilGridRange {
                let dist = sqrt(Float(bx * bx + bz * bz))
                guard dist <= soilInnerRadius else { continue }

                let j = jitter(bx, 0, bz)
                // 外周凹凸: 一部voxelを1段下げる
                let actualY: Float = if dist > soilInnerRadius - 1.2, j > 0.7 {
                    Float(layers.count - 3) * bs
                } else {
                    soilY
                }

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
        let soil = soilParent.flattenedClone()
        soil.name = "soil"
        rotationNode.addChildNode(soil)

        treeAnchor.position = SCNVector3(0, soilY + bs, 0)
        treeAnchor.name = "treeAnchor"
        rotationNode.addChildNode(treeAnchor)
    }

    // swiftlint:enable function_body_length cyclomatic_complexity

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
