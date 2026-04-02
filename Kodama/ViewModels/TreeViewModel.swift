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

        let pendingInteractions = tree.interactions.filter { $0.timestamp > tree.lastGrowthEval }
        let blockDates: [Date?] = tree.blocks.map(\.placedAt)

        let growthResult = GrowthEngine.calculateGrowthWithSeasons(
            tree: tree,
            existingBlocks: blocks,
            since: tree.lastGrowthEval,
            pendingInteractions: pendingInteractions,
            blockDates: blockDates
        )

        let seasonal = growthResult.seasonalEffects
        guard hasSeasonalChanges(newBlocks: growthResult.newBlocks, seasonal: seasonal) else {
            try? context.save()
            return
        }

        persistNewBlocks(growthResult.newBlocks, tree: tree, context: context)
        applySeasonalColorChanges(seasonal.colorChanges, tree: tree)
        let removedIndices = removeSeasonalBlocks(seasonal, tree: tree, context: context)

        persistSeasonalBlocks(snow: seasonal.newSnowBlocks, moss: seasonal.newMossBlocks, tree: tree, context: context)
        updateTreeState(
            tree: tree,
            added: growthResult.newBlocks,
            seasonal: seasonal,
            removedCount: removedIndices.count
        )
        try? context.save()

        updateInMemoryBlocks(newBlocks: growthResult.newBlocks, seasonal: seasonal, removedIndices: removedIndices)
        renderer.renderTree(from: blocks)
        animateNewNodes(
            renderer: renderer,
            count: growthResult.newBlocks.count + seasonal.newSnowBlocks.count + seasonal.newMossBlocks.count
        )
    }

    // MARK: Private

    private func hasSeasonalChanges(newBlocks: [VoxelBlockData], seasonal: SeasonalResult) -> Bool {
        !newBlocks.isEmpty
            || !seasonal.colorChanges.isEmpty
            || !seasonal.fallenLeaves.isEmpty
            || !seasonal.newSnowBlocks.isEmpty
            || !seasonal.removedSnow.isEmpty
            || !seasonal.newMossBlocks.isEmpty
            || !seasonal.expiredFlowers.isEmpty
    }

    private func persistNewBlocks(_ newBlocks: [VoxelBlockData], tree: BonsaiTree, context: ModelContext) {
        for blockData in newBlocks {
            let voxelBlock = VoxelBlock(
                x: blockData.x, y: blockData.y, z: blockData.z,
                blockType: blockData.blockType, colorHex: blockData.colorHex, source: .autonomous
            )
            voxelBlock.tree = tree
            context.insert(voxelBlock)
        }
    }

    private func applySeasonalColorChanges(_ changes: [(blockIndex: Int, newColor: String)], tree: BonsaiTree) {
        for change in changes {
            guard change.blockIndex < tree.blocks.count else { continue }
            tree.blocks[change.blockIndex].colorHex = change.newColor
            guard change.blockIndex < blocks.count else { continue }
            let old = blocks[change.blockIndex]
            blocks[change.blockIndex] = VoxelBlockData(
                x: old.x, y: old.y, z: old.z,
                blockType: old.blockType, colorHex: change.newColor, parentIndex: old.parentIndex
            )
        }
    }

    private func removeSeasonalBlocks(
        _ seasonal: SeasonalResult,
        tree: BonsaiTree,
        context: ModelContext
    ) -> Set<Int> {
        let fallenIndices = Set(seasonal.fallenLeaves)
        for index in seasonal.fallenLeaves where index < tree.blocks.count {
            context.delete(tree.blocks[index])
        }

        let expiredFlowerIndices = Set(seasonal.expiredFlowers)
        for index in seasonal.expiredFlowers where index < tree.blocks.count && !fallenIndices.contains(index) {
            context.delete(tree.blocks[index])
        }

        let removedSnowIndices = Set(seasonal.removedSnow)
        for index in seasonal.removedSnow where index < tree.blocks.count {
            context.delete(tree.blocks[index])
        }

        return fallenIndices.union(expiredFlowerIndices).union(removedSnowIndices)
    }

    private func persistSeasonalBlocks(
        snow: [VoxelBlockData],
        moss: [VoxelBlockData],
        tree: BonsaiTree,
        context: ModelContext
    ) {
        for blockData in snow + moss {
            let voxelBlock = VoxelBlock(
                x: blockData.x, y: blockData.y, z: blockData.z,
                blockType: blockData.blockType, colorHex: blockData.colorHex, source: .autonomous
            )
            voxelBlock.tree = tree
            context.insert(voxelBlock)
        }
    }

    private func updateTreeState(
        tree: BonsaiTree,
        added: [VoxelBlockData],
        seasonal: SeasonalResult,
        removedCount: Int
    ) {
        let addedCount = added.count + seasonal.newSnowBlocks.count + seasonal.newMossBlocks.count
        tree.totalBlocks += addedCount - removedCount
        tree.lastGrowthEval = Date()
    }

    private func updateInMemoryBlocks(
        newBlocks: [VoxelBlockData],
        seasonal: SeasonalResult,
        removedIndices: Set<Int>
    ) {
        if !removedIndices.isEmpty {
            blocks = blocks.enumerated().compactMap { index, block in
                removedIndices.contains(index) ? nil : block
            }
        }
        blocks += newBlocks + seasonal.newSnowBlocks + seasonal.newMossBlocks
    }

    private func animateNewNodes(renderer: BonsaiRenderer, count: Int) {
        guard count > 0 else { return }
        let treeRoot = renderer.bonsaiScene.treeAnchor.childNodes.first { $0.name == "treeRoot" }
        guard let root = treeRoot else { return }

        let allChildren = root.childNodes.flatMap { node -> [SCNNode] in
            node.name == "treeDynamic" || node.name == "treeRoot" ? Array(node.childNodes) : [node]
        }
        let newNodes = Array(allChildren.suffix(count))
        GrowthAnimator.animateNewBlocks(nodes: newNodes, in: renderer.bonsaiScene.scene)
    }

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
