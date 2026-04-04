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
    private struct StorageKey: Hashable {
        let positionKey: PositionKey
        let layer: GridLayer
    }

    // MARK: Internal

    private(set) var blocks: [VoxelBlockData] = []
    private(set) var currentTree: BonsaiTree?
    private let engineSchemaVersion = 2
    private let engineSchemaVersionKey = "kodama.engineSchemaVersion"

    var isFirstLaunch: Bool {
        currentTree == nil
    }

    // MARK: - User Interaction

    func handleTouch(position: SCNVector3, context: ModelContext) {
        guard let tree = currentTree else { return }
        let logicalTouch = SCNVector3(
            (position.x / VoxelConstants.renderScale).rounded(),
            (position.y / VoxelConstants.renderScale).rounded(),
            (position.z / VoxelConstants.renderScale).rounded()
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
        ensureEngineCompatibility(context: context)

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
                UserDefaults.standard.set(engineSchemaVersion, forKey: engineSchemaVersionKey)
            } catch {
                print("Failed to save new tree: \(error)")
            }
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
        var treeBlockLookup: [StorageKey: [VoxelBlock]] = [:]
        for block in treeBlocks {
            let key = StorageKey(positionKey: block.positionKey, layer: GridMapper.layer(for: block.blockType))
            treeBlockLookup[key, default: []].append(block)
        }
        let blockDates: [Date?] = blocks.map { block in
            let key = StorageKey(positionKey: block.positionKey, layer: GridMapper.layer(for: block.blockType))
            return treeBlockLookup[key]?.first?.placedAt
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

        persistBlocks(growthResult.newBlocks, tree: tree, context: context)
        applySeasonalColorChanges(seasonal.colorChanges, treeBlockLookup: treeBlockLookup)
        let removedIndices = removeSeasonalBlocks(seasonal, treeBlockLookup: treeBlockLookup, context: context)

        persistBlocks(seasonal.newSnowBlocks + seasonal.newMossBlocks, tree: tree, context: context)
        updateTreeState(
            tree: tree,
            added: growthResult.newBlocks,
            seasonal: seasonal,
            removedCount: removedIndices.count,
            currentDate: currentDate
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
        let existing = tree.blocks
        var existingByLayer: [StorageKey: VoxelBlock] = [:]
        for block in existing {
            let key = StorageKey(positionKey: block.positionKey, layer: GridMapper.layer(for: block.blockType))
            existingByLayer[key] = block
        }

        for blockData in blocks {
            let key = StorageKey(positionKey: blockData.positionKey, layer: GridMapper.layer(for: blockData.blockType))
            if let existingBlock = existingByLayer[key] {
                existingBlock.blockType = blockData.blockType
                existingBlock.colorHex = blockData.colorHex
                existingBlock.placedAt = Date()
            } else {
                let voxelBlock = VoxelBlock(
                    x: blockData.x, y: blockData.y, z: blockData.z,
                    blockType: blockData.blockType, colorHex: blockData.colorHex, source: .autonomous
                )
                voxelBlock.tree = tree
                context.insert(voxelBlock)
                existingByLayer[key] = voxelBlock
            }
        }
    }

    private func applySeasonalColorChanges(
        _ changes: [(blockIndex: Int, newColor: String)],
        treeBlockLookup: [StorageKey: [VoxelBlock]]
    ) {
        // DB entities only — in-memory update happens in updateInMemoryBlocks after save
        for change in changes {
            guard change.blockIndex < blocks.count else { continue }
            let old = blocks[change.blockIndex]
            let key = StorageKey(positionKey: old.positionKey, layer: GridMapper.layer(for: old.blockType))
            if let treeBlock = treeBlockLookup[key]?.first {
                treeBlock.colorHex = change.newColor
            }
        }
    }

    private func removeSeasonalBlocks(
        _ seasonal: SeasonalResult,
        treeBlockLookup: [StorageKey: [VoxelBlock]],
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

    private func findTreeBlock(at index: Int, treeBlockLookup: [StorageKey: [VoxelBlock]]) -> VoxelBlock? {
        guard index < blocks.count else { return nil }
        let block = blocks[index]
        let key = StorageKey(positionKey: block.positionKey, layer: GridMapper.layer(for: block.blockType))
        return treeBlockLookup[key]?.first
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
        blocks = reconstructParentIndices(blocks)
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

        private func timeTravelStepSize(for component: Calendar.Component) -> Int {
            switch component {
            case .month:
                1
            case .day:
                7
            default:
                1
            }
        }

        private func maxElapsedHours(for component: Calendar.Component, stepValue: Int) -> Int {
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

// MARK: - Block Data Helpers

private extension TreeViewModel {
    /// Precomputed once: face offsets + diagonal-up offsets for parent reconstruction.
    static let parentSearchOffsets: [(Float, Float, Float)] = PositionKey.faceOffsets + [
        (VoxelConstants.blockSize, VoxelConstants.blockSize, 0),
        (-VoxelConstants.blockSize, VoxelConstants.blockSize, 0),
        (0, VoxelConstants.blockSize, VoxelConstants.blockSize),
        (0, VoxelConstants.blockSize, -VoxelConstants.blockSize)
    ]

    func voxelBlockToData(_ block: VoxelBlock) -> VoxelBlockData {
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
    /// Includes diagonal-up neighbors so downward-sloping branches keep their parent link.
    func reconstructParentIndices(_ inputBlocks: [VoxelBlockData]) -> [VoxelBlockData] {
        var woodPositionToIndex = [PositionKey: Int](minimumCapacity: inputBlocks.count)
        for (i, block) in inputBlocks.enumerated() {
            if GridMapper.layer(for: block.blockType) == .wood {
                woodPositionToIndex[block.positionKey] = i
            }
        }

        return inputBlocks.enumerated().map { i, block in
            if block.blockType == .trunk, block.y == 0 {
                return block
            }

            var bestIndex: Int?
            for offset in Self.parentSearchOffsets {
                let neighborKey = PositionKey(x: block.x + offset.0, y: block.y + offset.1, z: block.z + offset.2)
                guard let neighborIndex = woodPositionToIndex[neighborKey], neighborIndex != i else { continue }
                let neighbor = inputBlocks[neighborIndex]
                if neighbor.blockType == .trunk || neighbor.blockType == .branch {
                    bestIndex = neighborIndex
                    break
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
