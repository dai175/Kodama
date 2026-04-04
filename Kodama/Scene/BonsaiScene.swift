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
    private var idleTimer: Timer?

    // MARK: - Initialization

    init() {
        scene = SCNScene()
        cameraNode = SCNNode()
        treeAnchor = SCNNode()
        rotationNode = SCNNode()
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
        camera.fieldOfView = 45
        camera.zNear = 0.1
        camera.zFar = 100

        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 3, 7)

        let lookAtConstraint = SCNLookAtConstraint(target: nil)
        lookAtConstraint.isGimbalLockEnabled = true

        let targetNode = SCNNode()
        targetNode.position = SCNVector3(0, 2, 0)
        scene.rootNode.addChildNode(targetNode)

        lookAtConstraint.target = targetNode
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

    // swiftlint:disable:next function_body_length
    private func setupPot() {
        let bs = VoxelConstants.blockSize
        let cs = VoxelConstants.cgBlockSize
        let potParent = SCNNode()

        // Materials
        let darkMaterial = SCNMaterial()
        darkMaterial.diffuse.contents = UIColor(red: 60 / 255, green: 44 / 255, blue: 32 / 255, alpha: 1)
        darkMaterial.roughness.contents = 0.8

        let baseMaterial = SCNMaterial()
        baseMaterial.diffuse.contents = UIColor(red: 74 / 255, green: 55 / 255, blue: 40 / 255, alpha: 1)
        baseMaterial.roughness.contents = 0.8

        let rimMaterial = SCNMaterial()
        rimMaterial.diffuse.contents = UIColor(red: 88 / 255, green: 66 / 255, blue: 48 / 255, alpha: 1)
        rimMaterial.roughness.contents = 0.8

        let darkGeom = SCNBox(width: cs, height: cs, length: cs, chamferRadius: 0)
        darkGeom.materials = [darkMaterial]

        let baseGeom = SCNBox(width: cs, height: cs, length: cs, chamferRadius: 0)
        baseGeom.materials = [baseMaterial]

        let rimGeom = SCNBox(width: cs, height: cs, length: cs, chamferRadius: 0)
        rimGeom.materials = [rimMaterial]

        // Layer definitions: (outerRadius, innerRadius)
        let layers: [(Float, Float)] = [
            (1.5, 0.0), // Y=0 bottom, solid
            (2.0, 1.0), // Y=1
            (2.5, 1.5), // Y=2
            (3.0, 2.0), // Y=3
            (3.5, 2.5) // Y=4 rim
        ]

        for (yLayer, (outerRadius, innerRadius)) in layers.enumerated() {
            let yPos = Float(yLayer) * bs
            let isRim = yLayer == layers.count - 1
            let isBottom = yLayer == 0

            for bx in -4 ... 4 {
                for bz in -4 ... 4 {
                    let dist = sqrt(Float(bx * bx + bz * bz))
                    let inOuter = dist <= outerRadius
                    let inInner = dist <= innerRadius
                    guard inOuter && (isBottom || !inInner) else { continue }

                    let node = SCNNode()
                    if isRim {
                        node.geometry = rimGeom
                    } else if isBottom || dist > outerRadius - 1.0 {
                        node.geometry = darkGeom
                    } else {
                        node.geometry = baseGeom
                    }
                    node.position = SCNVector3(Float(bx) * bs, yPos, Float(bz) * bs)
                    potParent.addChildNode(node)
                }
            }
        }

        let pot = potParent.flattenedClone()
        pot.name = "pot"
        rotationNode.addChildNode(pot)

        let soilMaterial = SCNMaterial()
        soilMaterial.diffuse.contents = UIColor(red: 45 / 255, green: 35 / 255, blue: 25 / 255, alpha: 1)
        soilMaterial.roughness.contents = 0.9
        let soilGeom = SCNBox(width: cs, height: cs, length: cs, chamferRadius: 0)
        soilGeom.materials = [soilMaterial]

        let soilParent = SCNNode()
        let rimLayer = layers[layers.count - 1]
        let rimY = Float(layers.count - 1) * bs
        let soilRadius = rimLayer.1
        let soilGridRange = Int(ceil(soilRadius))
        for bx in -soilGridRange ... soilGridRange {
            for bz in -soilGridRange ... soilGridRange {
                let dist = sqrt(Float(bx * bx + bz * bz))
                guard dist <= soilRadius else { continue }
                let soilNode = SCNNode(geometry: soilGeom)
                soilNode.position = SCNVector3(Float(bx) * bs, rimY, Float(bz) * bs)
                soilParent.addChildNode(soilNode)
            }
        }
        let soil = soilParent.flattenedClone()
        soil.name = "soil"
        rotationNode.addChildNode(soil)

        treeAnchor.position = SCNVector3(0, Float(layers.count) * bs, 0)
        treeAnchor.name = "treeAnchor"
        rotationNode.addChildNode(treeAnchor)
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
}
