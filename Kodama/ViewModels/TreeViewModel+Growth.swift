//
//  TreeViewModel+Growth.swift
//  Kodama
//

import Foundation
import SceneKit
import SwiftData

// MARK: - Growth

@MainActor extension TreeViewModel {
    func loadOrCreateTree(context: ModelContext) {
        ensureEngineCompatibility(context: context)

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
                    id: blockData.id,
                    pos: blockData.pos,
                    blockType: blockData.blockType,
                    colorHex: blockData.colorHex,
                    source: .autonomous,
                    parentBlockID: blockData.parentID
                )
                voxelBlock.tree = tree
                context.insert(voxelBlock)
            }

            tree.totalBlocks = saplingBlocks.count
            do {
                try context.save()
                currentTree = tree
                blocks = saplingBlocks
                UserDefaults.standard.set(engineSchemaVersion, forKey: engineSchemaVersionKey)
            } catch {
                print("Failed to save new tree: \(error)")
            }
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

    func evaluateGrowth(
        context: ModelContext,
        renderer: BonsaiRenderer,
        force: Bool = false,
        currentDate: Date = Date(),
        maxElapsedHours: Int = 168
    ) async {
        guard let tree = currentTree else { return }
        guard force || currentDate.timeIntervalSince(tree.lastGrowthEval) >= 60 else { return }

        let openInteraction = Interaction(type: .open)
        openInteraction.timestamp = currentDate
        openInteraction.tree = tree
        context.insert(openInteraction)

        let pendingInteractions = tree.interactions.filter {
            $0.timestamp > tree.lastGrowthEval && $0.timestamp <= currentDate
        }
        let treeBlocks = tree.blocks
        let treeBlocksByID = Dictionary(uniqueKeysWithValues: treeBlocks.map { ($0.id, $0) })
        let blockDates: [Date?] = blocks.map { block in
            treeBlocksByID[block.id]?.placedAt
        }
        let interactionPayloads = pendingInteractions.map {
            InteractionPayload(
                timestamp: $0.timestamp,
                type: $0.type,
                value: $0.value,
                touchX: $0.touchX,
                touchY: $0.touchY,
                touchZ: $0.touchZ
            )
        }
        let treeState = GrowthTreeState(seed: tree.seed, totalBlocks: tree.totalBlocks)
        let existingBlocks = blocks
        let lastGrowthEval = tree.lastGrowthEval

        let growthResult = await Task.detached(priority: .userInitiated) {
            GrowthEngine.calculateGrowthWithSeasons(
                tree: treeState,
                existingBlocks: existingBlocks,
                since: lastGrowthEval,
                currentDate: currentDate,
                pendingInteractions: interactionPayloads,
                blockDates: blockDates,
                maxElapsedHours: maxElapsedHours
            )
        }.value

        let seasonal = growthResult.seasonalEffects
        guard hasSeasonalChanges(newBlocks: growthResult.newBlocks, seasonal: seasonal) else {
            tree.lastGrowthEval = currentDate
            try? context.save()
            return
        }

        do {
            try applyGrowthResult(
                growthResult,
                tree: tree,
                currentDate: currentDate,
                context: context,
                renderer: renderer
            )
        } catch {
            print("Failed to save growth changes: \(error)")
        }
    }

    // MARK: Private

    nonisolated private func hasSeasonalChanges(newBlocks: [VoxelBlockData], seasonal: SeasonalResult) -> Bool {
        !newBlocks.isEmpty
            || !seasonal.colorChanges.isEmpty
            || !seasonal.fallenLeaves.isEmpty
            || !seasonal.newSnowBlocks.isEmpty
            || !seasonal.removedSnow.isEmpty
            || !seasonal.newMossBlocks.isEmpty
            || !seasonal.expiredFlowers.isEmpty
    }

    private func applyGrowthResult(
        _ growthResult: GrowthResult,
        tree: BonsaiTree,
        currentDate: Date,
        context: ModelContext,
        renderer: BonsaiRenderer
    ) throws {
        let treeBlocksByID = Dictionary(uniqueKeysWithValues: tree.blocks.map { ($0.id, $0) })
        let seasonal = growthResult.seasonalEffects
        persistBlocks(growthResult.newBlocks, tree: tree, context: context)
        applySeasonalColorChanges(seasonal.colorChanges, treeBlocksByID: treeBlocksByID)
        let removedIndices = removeSeasonalBlocks(seasonal, treeBlocksByID: treeBlocksByID, context: context)

        persistBlocks(seasonal.newSnowBlocks + seasonal.newMossBlocks, tree: tree, context: context)
        updateTreeState(
            tree: tree,
            added: growthResult.newBlocks,
            seasonal: seasonal,
            removedCount: removedIndices.count,
            currentDate: currentDate
        )
        try context.save()
        updateInMemoryBlocks(newBlocks: growthResult.newBlocks, seasonal: seasonal, removedIndices: removedIndices)
        renderer.renderTree(from: blocks)
        animateNewNodes(
            renderer: renderer,
            count: growthResult.newBlocks.count + seasonal.newSnowBlocks.count + seasonal.newMossBlocks.count
        )
    }

    private func persistBlocks(_ blocks: [VoxelBlockData], tree: BonsaiTree, context: ModelContext) {
        let existing = tree.blocks
        var existingByLayer: [StorageKey: VoxelBlock] = [:]
        for block in existing {
            let key = StorageKey(position: block.pos, layer: GridMapper.layer(for: block.blockType))
            existingByLayer[key] = block
        }

        for blockData in blocks {
            let key = StorageKey(position: blockData.pos, layer: GridMapper.layer(for: blockData.blockType))
            if let existingBlock = existingByLayer[key] {
                existingBlock.id = blockData.id
                existingBlock.blockType = blockData.blockType
                existingBlock.colorHex = blockData.colorHex
                existingBlock.parentBlockID = blockData.parentID
                existingBlock.placedAt = Date()
            } else {
                let voxelBlock = VoxelBlock(
                    id: blockData.id,
                    pos: blockData.pos,
                    blockType: blockData.blockType,
                    colorHex: blockData.colorHex,
                    source: .autonomous,
                    parentBlockID: blockData.parentID
                )
                voxelBlock.tree = tree
                context.insert(voxelBlock)
                existingByLayer[key] = voxelBlock
            }
        }
    }

    private func applySeasonalColorChanges(
        _ changes: [(blockIndex: Int, newColor: String)],
        treeBlocksByID: [UUID: VoxelBlock]
    ) {
        // DB entities only — in-memory update happens in updateInMemoryBlocks after save
        for change in changes {
            guard change.blockIndex < blocks.count else { continue }
            let old = blocks[change.blockIndex]
            if let treeBlock = treeBlocksByID[old.id] {
                treeBlock.colorHex = change.newColor
            }
        }
    }

    private func removeSeasonalBlocks(
        _ seasonal: SeasonalResult,
        treeBlocksByID: [UUID: VoxelBlock],
        context: ModelContext
    ) -> Set<Int> {
        let fallenIndices = seasonal.fallenLeaves
        for index in fallenIndices {
            if let treeBlock = findTreeBlock(at: index, treeBlocksByID: treeBlocksByID) {
                context.delete(treeBlock)
            }
        }

        let expiredFlowerIndices = seasonal.expiredFlowers
        for index in expiredFlowerIndices where !fallenIndices.contains(index) {
            if let treeBlock = findTreeBlock(at: index, treeBlocksByID: treeBlocksByID) {
                context.delete(treeBlock)
            }
        }

        let removedSnowIndices = seasonal.removedSnow
        for index in removedSnowIndices {
            if let treeBlock = findTreeBlock(at: index, treeBlocksByID: treeBlocksByID) {
                context.delete(treeBlock)
            }
        }

        return fallenIndices.union(expiredFlowerIndices).union(removedSnowIndices)
    }

    private func findTreeBlock(at index: Int, treeBlocksByID: [UUID: VoxelBlock]) -> VoxelBlock? {
        guard index < blocks.count else { return nil }
        return treeBlocksByID[blocks[index].id]
    }

    private func updateTreeState(
        tree: BonsaiTree,
        added: [VoxelBlockData],
        seasonal: SeasonalResult,
        removedCount: Int,
        currentDate: Date
    ) {
        let addedCount = added.count + seasonal.newSnowBlocks.count + seasonal.newMossBlocks.count
        tree.totalBlocks += addedCount - removedCount
        tree.lastGrowthEval = currentDate
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
                id: old.id,
                pos: old.pos,
                blockType: old.blockType,
                colorHex: change.newColor,
                parentID: old.parentID
            )
        }
        if !removedIndices.isEmpty {
            blocks = blocks.enumerated().compactMap { index, block in
                removedIndices.contains(index) ? nil : block
            }
        }
        blocks += newBlocks + seasonal.newSnowBlocks + seasonal.newMossBlocks
    }

    private func ensureEngineCompatibility(context: ModelContext) {
        let savedVersion = UserDefaults.standard.integer(forKey: engineSchemaVersionKey)
        guard savedVersion != 0, savedVersion == engineSchemaVersion else {
            do {
                try context.delete(model: VoxelBlock.self)
                try context.delete(model: Interaction.self)
                try context.delete(model: BonsaiTree.self)
                try context.save()
                UserDefaults.standard.set(engineSchemaVersion, forKey: engineSchemaVersionKey)
            } catch {
                print("Failed to reset incompatible engine data: \(error)")
            }
            return
        }
    }

    #if DEBUG
        func timeTravel(
            component: Calendar.Component,
            value: Int,
            context: ModelContext,
            renderer: BonsaiRenderer
        ) async {
            guard currentTree != nil else {
                print("[TimeTravel] ABORT: currentTree is nil")
                return
            }
            let savedOverride = Season.debugOverride
            defer { Season.debugOverride = savedOverride }
            Season.debugOverride = nil
            var remainingValue = value

            while remainingValue > 0, let currentTree {
                let stepValue = min(timeTravelStepSize(for: component), remainingValue)
                let blocksBefore = blocks.count
                let targetDate = Calendar.current.date(
                    byAdding: component,
                    value: stepValue,
                    to: currentTree.lastGrowthEval
                ) ?? currentTree.lastGrowthEval

                print("[TimeTravel] Advancing growth evaluation by \(stepValue) \(component) to \(targetDate)")
                await evaluateGrowth(
                    context: context,
                    renderer: renderer,
                    force: true,
                    currentDate: targetDate,
                    maxElapsedHours: maxElapsedHours(for: component, stepValue: stepValue)
                )
                print("[TimeTravel] Blocks: \(blocksBefore) → \(blocks.count)")

                remainingValue -= stepValue
                await Task.yield()
            }
        }

        nonisolated private func timeTravelStepSize(for component: Calendar.Component) -> Int {
            switch component {
            case .month:
                1
            case .day:
                7
            default:
                1
            }
        }

        nonisolated private func maxElapsedHours(for component: Calendar.Component, stepValue: Int) -> Int {
            switch component {
            case .month:
                24 * 31 * max(1, stepValue)
            case .day:
                24 * max(1, stepValue)
            default:
                24 * 31
            }
        }
    #endif

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
}
