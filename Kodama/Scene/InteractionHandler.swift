//
//  InteractionHandler.swift
//  Kodama
//

import SceneKit
import UIKit

// MARK: - InteractionHandler

enum InteractionHandler {
    // MARK: - Touch Glow

    /// Hit tests from a screen point to find the nearest tree block node.
    /// If a hit is found, creates a temporary omni light at the hit position
    /// that fades out over 2 seconds.
    /// - Returns: The 3D world position of the hit, or nil if nothing was hit.
    static func handleTouch(at point: CGPoint, in scnView: SCNView, scene: BonsaiScene) -> SCNVector3? {
        let hitResults = scnView.hitTest(point, options: [
            .searchMode: SCNHitTestSearchMode.closest.rawValue,
            .rootNode: scene.treeAnchor
        ])

        guard let hit = hitResults.first else { return nil }

        let hitPosition = hit.worldCoordinates

        let lightNode = SCNNode()
        let light = SCNLight()
        light.type = .omni
        light.color = UIColor(red: 1.0, green: 0.83, blue: 0.63, alpha: 1.0) // #FFD4A0
        light.intensity = 500
        light.attenuationStartDistance = 0
        light.attenuationEndDistance = 5
        lightNode.light = light
        lightNode.position = hitPosition
        scene.scene.rootNode.addChildNode(lightNode)

        let fadeOut = SCNAction.customAction(duration: 2.0) { node, elapsed in
            let progress = elapsed / 2.0
            node.light?.intensity = 500 * CGFloat(1.0 - progress)
        }
        let remove = SCNAction.removeFromParentNode()
        lightNode.runAction(SCNAction.sequence([fadeOut, remove]))

        return hitPosition
    }

    // MARK: - Particle Flow

    /// Creates a simple particle system that flows toward the tree center.
    static func createParticleFlow(
        from point: CGPoint,
        color: UIColor,
        in scnView: SCNView,
        toward target: SCNVector3
    ) {
        let particleSystem = SCNParticleSystem()
        particleSystem.birthRate = 50
        particleSystem.particleLifeSpan = 0.5
        particleSystem.particleSize = 0.08
        particleSystem.particleColor = color
        particleSystem.emitterShape = SCNSphere(radius: 0.1)
        particleSystem.spreadingAngle = 15
        particleSystem.particleVelocity = 3
        particleSystem.particleVelocityVariation = 1
        particleSystem.blendMode = .additive
        particleSystem.isAffectedByGravity = false

        guard let scene = scnView.scene else { return }

        // Unproject the screen point to get a 3D position near the camera
        let nearPoint = scnView.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 0.9))

        let emitterNode = SCNNode()
        emitterNode.position = nearPoint
        emitterNode.addParticleSystem(particleSystem)

        // Orient toward target
        emitterNode.look(at: target)

        scene.rootNode.addChildNode(emitterNode)

        // Stop emitting after a short burst, then remove
        let stopEmitting = SCNAction.run { node in
            node.particleSystems?.first?.birthRate = 0
        }
        let wait = SCNAction.wait(duration: 1.0)
        let remove = SCNAction.removeFromParentNode()
        emitterNode.runAction(SCNAction.sequence([
            SCNAction.wait(duration: 0.3),
            stopEmitting,
            wait,
            remove
        ]))
    }

    // MARK: - Word Dissolve

    /// Creates a 3D text node that animates toward the tree and dissolves.
    static func createWordDissolve(
        text: String,
        from point: CGPoint,
        in scnView: SCNView,
        toward target: SCNVector3
    ) {
        let textGeometry = SCNText(string: text, extrusionDepth: 0.05)
        textGeometry.font = UIFont.systemFont(ofSize: 0.5, weight: .light)
        textGeometry.flatness = 0.3

        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 232 / 255, green: 228 / 255, blue: 220 / 255, alpha: 1) // #E8E4DC
        material.isDoubleSided = true
        textGeometry.materials = [material]

        let textNode = SCNNode(geometry: textGeometry)

        // Center the text geometry
        let boundingMin = textNode.boundingBox.min
        let boundingMax = textNode.boundingBox.max
        let centerX = (boundingMin.x + boundingMax.x) / 2
        let centerY = (boundingMin.y + boundingMax.y) / 2
        textNode.pivot = SCNMatrix4MakeTranslation(centerX, centerY, 0)

        // Position at screen point in 3D space
        let startPosition = scnView.unprojectPoint(SCNVector3(Float(point.x), Float(point.y), 0.85))
        textNode.position = startPosition

        // Face the camera
        let constraint = SCNBillboardConstraint()
        constraint.freeAxes = .all
        textNode.constraints = [constraint]

        guard let scene = scnView.scene else { return }
        scene.rootNode.addChildNode(textNode)

        // Animate: scale down + move toward tree + fade out
        let duration = 0.8
        let moveAction = SCNAction.move(to: target, duration: duration)
        moveAction.timingMode = .easeInEaseOut
        let scaleAction = SCNAction.scale(to: 0.1, duration: duration)
        scaleAction.timingMode = .easeInEaseOut
        let fadeAction = SCNAction.fadeOut(duration: duration)
        fadeAction.timingMode = .easeInEaseOut
        let group = SCNAction.group([moveAction, scaleAction, fadeAction])
        let remove = SCNAction.removeFromParentNode()

        textNode.runAction(SCNAction.sequence([group, remove]))
    }
}
