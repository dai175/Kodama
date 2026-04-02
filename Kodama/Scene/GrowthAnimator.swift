//
//  GrowthAnimator.swift
//  Kodama
//

import SceneKit

// MARK: - GrowthAnimator

enum GrowthAnimator {
    /// Animates new blocks appearing with a scale-in effect, sorted by Y position (lower first).
    static func animateNewBlocks(nodes: [SCNNode], in _: SCNScene) {
        guard !nodes.isEmpty else { return }

        let sorted = nodes.sorted { $0.position.y < $1.position.y }
        let interval = min(0.1, 10.0 / Double(sorted.count))

        for (index, node) in sorted.enumerated() {
            node.scale = SCNVector3(0, 0, 0)
            node.opacity = 0

            let delay = Double(index) * interval
            let scaleUp = SCNAction.scale(to: 1.0, duration: 0.15)
            scaleUp.timingMode = .easeOut
            let fadeIn = SCNAction.fadeIn(duration: 0.15)
            let appear = SCNAction.group([scaleUp, fadeIn])
            let sequence = SCNAction.sequence([SCNAction.wait(duration: delay), appear])

            node.runAction(sequence)
        }
    }

    /// Animates a leaf falling and fading out, then removes it.
    static func animateLeafFall(node: SCNNode) {
        let fall = SCNAction.moveBy(x: 0, y: -3, z: 0, duration: 1.5)
        fall.timingMode = .easeIn
        let fadeOut = SCNAction.fadeOut(duration: 1.5)
        let group = SCNAction.group([fall, fadeOut])
        let remove = SCNAction.removeFromParentNode()
        let sequence = SCNAction.sequence([group, remove])

        node.runAction(sequence)
    }

    /// Animates snow melting by shrinking and fading.
    static func animateSnowMelt(node: SCNNode) {
        let shrink = SCNAction.scale(to: 0, duration: 1.0)
        shrink.timingMode = .easeIn
        let fadeOut = SCNAction.fadeOut(duration: 1.0)
        let group = SCNAction.group([shrink, fadeOut])
        let remove = SCNAction.removeFromParentNode()
        let sequence = SCNAction.sequence([group, remove])

        node.runAction(sequence)
    }
}
