//
//  TreeViewModel.swift
//  Kodama
//

import Foundation
import SceneKit
import SwiftData

// MARK: - TreeViewModel

@MainActor
@Observable
final class TreeViewModel {
    // MARK: Internal

    private(set) var blocks: [VoxelBlockData] = []
    private(set) var currentTree: BonsaiTree?

    var isFirstLaunch: Bool {
        currentTree == nil
    }

    // MARK: - User Interaction

    func handleTouch(position: SCNVector3, context: ModelContext) {
        guard let tree = currentTree else { return }
        let interaction = Interaction(
            type: .touch,
            touchX: position.x,
            touchY: position.y,
            touchZ: position.z
        )
        interaction.tree = tree
        context.insert(interaction)
        do {
            try context.save()
        } catch {
            print("Failed to save touch interaction: \(error)")
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
            print("Failed to save color interaction: \(error)")
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
            print("Failed to save word interaction: \(error)")
        }
    }

    func resetTree(context: ModelContext) {
        do {
            try context.delete(model: VoxelBlock.self)
            try context.delete(model: Interaction.self)
            try context.delete(model: BonsaiTree.self)
            try context.save()
            blocks = []
            currentTree = nil
            loadOrCreateTree(context: context)
        } catch {
            print("Failed to reset tree: \(error)")
        }
    }

    func loadOrCreateTree(context: ModelContext) {
        let descriptor = FetchDescriptor<BonsaiTree>()
        let trees = (try? context.fetch(descriptor)) ?? []

        if let existing = trees.first {
            currentTree = existing
            blocks = reconstructParentIndices(existing.blocks.map { voxelBlockToData($0) })
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
            do {
                try context.save()
                currentTree = tree
                blocks = saplingBlocks
            } catch {
                print("Failed to save new tree: \(error)")
            }
        }
    }

    func evaluateGrowth(context: ModelContext, renderer: BonsaiRenderer) {
        guard let tree = currentTree else { return }
        guard Date().timeIntervalSince(tree.lastGrowthEval) >= 60 else { return }

        // Log an open interaction
        let openInteraction = Interaction(type: .open)
        openInteraction.tree = tree
        context.insert(openInteraction)

        let pendingInteractions = tree.interactions.filter { $0.timestamp > tree.lastGrowthEval }
        let treeBlocks = tree.blocks
        let treeBlockLookup: [PositionKey: VoxelBlock] = Dictionary(
            treeBlocks.map { ($0.positionKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let blockDates: [Date?] = blocks.map { treeBlockLookup[$0.positionKey]?.placedAt }

        let growthResult = GrowthEngine.calculateGrowthWithSeasons(
            tree: tree,
            existingBlocks: blocks,
            since: tree.lastGrowthEval,
            pendingInteractions: pendingInteractions,
            blockDates: blockDates
        )

        let seasonal = growthResult.seasonalEffects
        guard hasSeasonalChanges(newBlocks: growthResult.newBlocks, seasonal: seasonal) else {
            tree.lastGrowthEval = Date()
            try? context.save()
            return
        }

        persistBlocks(growthResult.newBlocks, tree: tree, context: context)
        applySeasonalColorChanges(seasonal.colorChanges, treeBlockLookup: treeBlockLookup)
        let removedIndices = removeSeasonalBlocks(seasonal, treeBlockLookup: treeBlockLookup, context: context)

        persistBlocks(seasonal.newSnowBlocks + seasonal.newMossBlocks, tree: tree, context: context)
        updateTreeState(
            tree: tree,
            added: growthResult.newBlocks,
            seasonal: seasonal,
            removedCount: removedIndices.count
        )
        do {
            try context.save()
            updateInMemoryBlocks(newBlocks: growthResult.newBlocks, seasonal: seasonal, removedIndices: removedIndices)
            renderer.renderTree(from: blocks)
            animateNewNodes(
                renderer: renderer,
                count: growthResult.newBlocks.count + seasonal.newSnowBlocks.count + seasonal.newMossBlocks.count
            )
        } catch {
            print("Failed to save growth changes: \(error)")
        }
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

    private func persistBlocks(_ blocks: [VoxelBlockData], tree: BonsaiTree, context: ModelContext) {
        for blockData in blocks {
            let voxelBlock = VoxelBlock(
                x: blockData.x, y: blockData.y, z: blockData.z,
                blockType: blockData.blockType, colorHex: blockData.colorHex, source: .autonomous
            )
            voxelBlock.tree = tree
            context.insert(voxelBlock)
        }
    }

    private func applySeasonalColorChanges(
        _ changes: [(blockIndex: Int, newColor: String)],
        treeBlockLookup: [PositionKey: VoxelBlock]
    ) {
        // DB entities only — in-memory update happens in updateInMemoryBlocks after save
        for change in changes {
            guard change.blockIndex < blocks.count else { continue }
            let old = blocks[change.blockIndex]
            if let treeBlock = treeBlockLookup[old.positionKey] {
                treeBlock.colorHex = change.newColor
            }
        }
    }

    private func removeSeasonalBlocks(
        _ seasonal: SeasonalResult,
        treeBlockLookup: [PositionKey: VoxelBlock],
        context: ModelContext
    ) -> Set<Int> {
        let fallenIndices = seasonal.fallenLeaves
        for index in fallenIndices {
            if let treeBlock = findTreeBlock(at: index, treeBlockLookup: treeBlockLookup) {
                context.delete(treeBlock)
            }
        }

        let expiredFlowerIndices = seasonal.expiredFlowers
        for index in expiredFlowerIndices where !fallenIndices.contains(index) {
            if let treeBlock = findTreeBlock(at: index, treeBlockLookup: treeBlockLookup) {
                context.delete(treeBlock)
            }
        }

        let removedSnowIndices = seasonal.removedSnow
        for index in removedSnowIndices {
            if let treeBlock = findTreeBlock(at: index, treeBlockLookup: treeBlockLookup) {
                context.delete(treeBlock)
            }
        }

        return fallenIndices.union(expiredFlowerIndices).union(removedSnowIndices)
    }

    private func findTreeBlock(at index: Int, treeBlockLookup: [PositionKey: VoxelBlock]) -> VoxelBlock? {
        guard index < blocks.count else { return nil }
        return treeBlockLookup[blocks[index].positionKey]
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
        // Apply color changes first — indices reference the pre-removal array
        for change in seasonal.colorChanges {
            guard change.blockIndex < blocks.count else { continue }
            let old = blocks[change.blockIndex]
            blocks[change.blockIndex] = VoxelBlockData(
                x: old.x, y: old.y, z: old.z,
                blockType: old.blockType, colorHex: change.newColor, parentIndex: old.parentIndex
            )
        }
        if !removedIndices.isEmpty {
            blocks = blocks.enumerated().compactMap { index, block in
                removedIndices.contains(index) ? nil : block
            }
        }
        blocks += newBlocks + seasonal.newSnowBlocks + seasonal.newMossBlocks
        if !removedIndices.isEmpty {
            blocks = reconstructParentIndices(blocks)
        }
    }

    private func animateNewNodes(renderer: BonsaiRenderer, count: Int) {
        guard count > 0 else { return }
        let treeRoot = renderer.bonsaiScene.treeAnchor.childNodes.first { $0.name == "treeRoot" }
        guard let root = treeRoot else { return }

        let allChildren = root.childNodes.flatMap { node -> [SCNNode] in
            node.name == "treeDynamic" || node.name == "treeRoot" ? Array(node.childNodes) : [node]
        }
        let newNodes = Array(allChildren.suffix(count))
        GrowthAnimator.animateNewBlocks(nodes: newNodes)
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

    /// Reconstructs parentIndex relationships from spatial adjacency after DB load.
    /// Down direction is searched first; trunk/branch neighbors are preferred as parents.
    private func reconstructParentIndices(_ inputBlocks: [VoxelBlockData]) -> [VoxelBlockData] {
        var positionToIndex = [PositionKey: Int](minimumCapacity: inputBlocks.count)
        for (i, block) in inputBlocks.enumerated() {
            positionToIndex[block.positionKey] = i
        }

        return inputBlocks.enumerated().map { i, block in
            if block.blockType == .trunk, block.y == 0 {
                return block
            }

            var bestIndex: Int?
            for offset in PositionKey.faceOffsets {
                let neighborKey = PositionKey(x: block.x + offset.0, y: block.y + offset.1, z: block.z + offset.2)
                guard let neighborIndex = positionToIndex[neighborKey], neighborIndex != i else { continue }
                let neighbor = inputBlocks[neighborIndex]
                if neighbor.blockType == .trunk || neighbor.blockType == .branch {
                    bestIndex = neighborIndex
                    break
                } else if bestIndex == nil {
                    bestIndex = neighborIndex
                }
            }

            guard let parentIndex = bestIndex else { return block }
            return VoxelBlockData(
                x: block.x, y: block.y, z: block.z,
                blockType: block.blockType, colorHex: block.colorHex,
                parentIndex: parentIndex
            )
        }
    }
}
