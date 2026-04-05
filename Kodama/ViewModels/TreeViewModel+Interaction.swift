//
//  TreeViewModel+Interaction.swift
//  Kodama
//

import Foundation
import OSLog
import SceneKit
import SwiftData

private let logger = Logger(subsystem: "com.daisuke.Kodama", category: "Interaction")

// MARK: - User Interaction

@MainActor extension TreeViewModel {
    func handleTouch(position: SCNVector3, scene: BonsaiScene, context: ModelContext) {
        guard let tree = currentTree else { return }
        let local = scene.treeAnchor.convertPosition(position, from: nil)
        let logicalTouch = Int3(
            x: Int((local.x / VoxelConstants.renderScale).rounded()),
            y: Int((local.y / VoxelConstants.renderScale).rounded()),
            z: Int((local.z / VoxelConstants.renderScale).rounded())
        )
        let interaction = Interaction(
            type: .touch,
            touchX: logicalTouch.x,
            touchY: logicalTouch.y,
            touchZ: logicalTouch.z
        )
        interaction.tree = tree
        context.insert(interaction)
        do {
            try context.save()
        } catch {
            logger.error("Failed to save touch interaction: \(error)")
        }
    }

    func handleColor(hex: String, context: ModelContext) {
        guard let tree = currentTree else { return }
        let interaction = Interaction(type: .color, value: hex)
        interaction.tree = tree
        context.insert(interaction)
        do {
            try context.save()
        } catch {
            logger.error("Failed to save color interaction: \(error)")
        }
    }

    func handleWord(text: String, context: ModelContext) {
        guard let tree = currentTree else { return }
        let interaction = Interaction(type: .word, value: text)
        interaction.tree = tree
        context.insert(interaction)
        do {
            try context.save()
        } catch {
            logger.error("Failed to save word interaction: \(error)")
        }
    }
}
