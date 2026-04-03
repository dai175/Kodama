//
//  GrowthAnimator.swift
//  Kodama
//

import SceneKit

// MARK: - GrowthAnimator

enum GrowthAnimator {
    /// Animates new blocks appearing with a scale-in effect, sorted by Y position (lower first).
    static func animateNewBlocks(nodes: [SCNNode]) {
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
}
