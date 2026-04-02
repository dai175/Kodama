//
//  TreeViewModel.swift
//  Kodama
//

import Foundation
import SceneKit
import SwiftData

// MARK: - TreeViewModel

@Observable
final class TreeViewModel {
    // MARK: Internal

    private(set) var blocks: [VoxelBlockData] = []
    private(set) var currentTree: BonsaiTree?

    var isFirstLaunch: Bool {
        currentTree == nil
    }

    func loadOrCreateTree(context: ModelContext) {
        let descriptor = FetchDescriptor<BonsaiTree>()
        let trees = (try? context.fetch(descriptor)) ?? []

        if let existing = trees.first {
            currentTree = existing
            blocks = existing.blocks.map { voxelBlockToData($0) }
        } else {
            let seed = Int.random(in: 1 ... 999_999)
            let tree = BonsaiTree(seed: seed)
            context.insert(tree)

            let saplingBlocks = TreeBuilder.buildSapling(seed: UInt64(seed))
            for blockData in saplingBlocks {
                let voxelBlock = VoxelBlock(
                    x: blockData.x,
                    y: blockData.y,
                    z: blockData.z,
                    blockType: blockData.blockType,
                    colorHex: blockData.colorHex,
                    source: .autonomous
                )
                voxelBlock.tree = tree
                context.insert(voxelBlock)
            }

            tree.totalBlocks = saplingBlocks.count
            try? context.save()

            currentTree = tree
            blocks = saplingBlocks
        }
    }

    func evaluateGrowth(context: ModelContext, renderer: BonsaiRenderer) {
        guard let tree = currentTree else { return }

        // Log an open interaction
        let openInteraction = Interaction(type: .open)
        openInteraction.tree = tree
        context.insert(openInteraction)

        // Gather pending interactions since last growth eval
        let pendingInteractions = tree.interactions.filter {
            $0.timestamp > tree.lastGrowthEval
        }

        let newBlocks = GrowthEngine.calculateGrowth(
            tree: tree,
            existingBlocks: blocks,
            since: tree.lastGrowthEval,
            pendingInteractions: pendingInteractions
        )

        guard !newBlocks.isEmpty else {
            try? context.save()
            return
        }

        // Persist new blocks to SwiftData
        for blockData in newBlocks {
            let voxelBlock = VoxelBlock(
                x: blockData.x,
                y: blockData.y,
                z: blockData.z,
                blockType: blockData.blockType,
                colorHex: blockData.colorHex,
                source: .autonomous
            )
            voxelBlock.tree = tree
            context.insert(voxelBlock)
        }

        tree.totalBlocks += newBlocks.count
        tree.lastGrowthEval = Date()
        try? context.save()

        // Update in-memory state
        blocks += newBlocks

        // Render and animate new blocks
        renderer.addBlocks(newBlocks)

        // Collect newly added nodes for animation
        let treeRoot = renderer.bonsaiScene.treeAnchor.childNodes.first { $0.name == "treeRoot" }
        if let root = treeRoot {
            let allChildren = root.childNodes.flatMap { node -> [SCNNode] in
                if node.name == "treeDynamic" || node.name == "treeRoot" {
                    return Array(node.childNodes)
                }
                return [node]
            }
            // Animate the last N nodes that were just added
            let newNodes = Array(allChildren.suffix(newBlocks.count))
            GrowthAnimator.animateNewBlocks(nodes: newNodes, in: renderer.bonsaiScene.scene)
        }
    }

    // MARK: Private

    private func voxelBlockToData(_ block: VoxelBlock) -> VoxelBlockData {
        VoxelBlockData(
            x: block.x,
            y: block.y,
            z: block.z,
            blockType: block.blockType,
            colorHex: block.colorHex,
            parentIndex: nil
        )
    }
}
