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
        cameraNode.position = SCNVector3(0, 5, 12)

        let lookAtConstraint = SCNLookAtConstraint(target: nil)
        lookAtConstraint.isGimbalLockEnabled = true

        let targetNode = SCNNode()
        targetNode.position = SCNVector3(0, 3, 0)
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
        directionalNode.position = SCNVector3(-5, 10, 5)
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
        let potParent = SCNNode()
        let voxelSize: CGFloat = 1.0

        let potColor = UIColor(red: 74 / 255, green: 55 / 255, blue: 40 / 255, alpha: 1)
        let potDarkColor = UIColor(red: 60 / 255, green: 44 / 255, blue: 32 / 255, alpha: 1)
        let potLightColor = UIColor(red: 88 / 255, green: 66 / 255, blue: 48 / 255, alpha: 1)

        let baseMaterial = SCNMaterial()
        baseMaterial.diffuse.contents = potColor
        baseMaterial.roughness.contents = 0.8

        let darkMaterial = SCNMaterial()
        darkMaterial.diffuse.contents = potDarkColor
        darkMaterial.roughness.contents = 0.8

        let lightMaterial = SCNMaterial()
        lightMaterial.diffuse.contents = potLightColor
        lightMaterial.roughness.contents = 0.8

        let baseGeometry = SCNBox(width: voxelSize, height: voxelSize, length: voxelSize, chamferRadius: 0)
        baseGeometry.materials = [baseMaterial]

        let darkGeometry = SCNBox(width: voxelSize, height: voxelSize, length: voxelSize, chamferRadius: 0)
        darkGeometry.materials = [darkMaterial]

        let lightGeometry = SCNBox(width: voxelSize, height: voxelSize, length: voxelSize, chamferRadius: 0)
        lightGeometry.materials = [lightMaterial]

        // Build a 3x2x3 pot
        for x in -1 ... 1 {
            for y in 0 ... 1 {
                for z in -1 ... 1 {
                    let node = SCNNode()
                    // Use different shades for visual interest
                    if y == 0, x == 0 || z == 0 {
                        node.geometry = darkGeometry
                    } else if y == 1, x == 0, z == 0 {
                        // Top center is empty (soil area / tree anchor)
                        continue
                    } else if y == 1 {
                        node.geometry = lightGeometry
                    } else {
                        node.geometry = baseGeometry
                    }
                    node.position = SCNVector3(Float(x), Float(y), Float(z))
                    potParent.addChildNode(node)
                }
            }
        }

        let pot = potParent.flattenedClone()
        pot.name = "pot"
        rotationNode.addChildNode(pot)

        // Add soil on top center
        let soilGeometry = SCNBox(width: voxelSize, height: voxelSize, length: voxelSize, chamferRadius: 0)
        let soilMaterial = SCNMaterial()
        soilMaterial.diffuse.contents = UIColor(red: 45 / 255, green: 35 / 255, blue: 25 / 255, alpha: 1)
        soilMaterial.roughness.contents = 0.9
        soilGeometry.materials = [soilMaterial]

        let soilNode = SCNNode(geometry: soilGeometry)
        soilNode.position = SCNVector3(0, 1, 0)
        soilNode.name = "soil"
        rotationNode.addChildNode(soilNode)

        // Tree anchor sits above the pot
        treeAnchor.position = SCNVector3(0, 2, 0)
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
