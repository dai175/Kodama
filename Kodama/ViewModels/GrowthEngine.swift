//
//  GrowthEngine.swift
//  Kodama
//

import Foundation

// MARK: - GrowthEngine

nonisolated enum GrowthEngine {
    private struct GrowthState {
        var allNodes: [GrowthNode]
        var newNodes: [GrowthNode] = []
        var woodOccupied: Set<Int3>
        var foliageOccupied: Set<Int3>
        var nextNodeID: Int
        var removedBlockIDs: [UUID] = []
        let initialNodeCount: Int
    }

    private static let growthAttemptsPerTick = 8

    private static let trunkDirections: [Int3] = [
        Int3(x: 0, y: 1, z: 0)
    ]

    private static let branchDirections: [Int3] = [
        Int3(x: 1, y: 0, z: 0),
        Int3(x: -1, y: 0, z: 0),
        Int3(x: 0, y: 0, z: 1),
        Int3(x: 0, y: 0, z: -1),
        Int3(x: 0, y: 1, z: 0)
    ]

    private static let foliageClusterOffsets: [Int3] = [
        Int3(x: 0, y: 1, z: 0),
        Int3(x: 1, y: 0, z: 0),
        Int3(x: -1, y: 0, z: 0),
        Int3(x: 0, y: 0, z: 1),
        Int3(x: 0, y: 0, z: -1),
        Int3(x: 0, y: 1, z: 1),
        Int3(x: 0, y: 1, z: -1),
        Int3(x: 1, y: 1, z: 0),
        Int3(x: -1, y: 1, z: 0)
    ]

    // MARK: - Growth Calculation

    nonisolated static func calculateGrowthWithSeasons(
        tree: BonsaiTree,
        existingBlocks: [VoxelBlockData],
        since lastEval: Date,
        currentDate: Date = Date(),
        pendingInteractions: [Interaction] = [],
        blockDates: [Date?] = [],
        maxElapsedHours: Int = 168
    ) -> GrowthResult {
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
        return calculateGrowthWithSeasons(
            tree: treeState,
            existingBlocks: existingBlocks,
            since: lastEval,
            currentDate: currentDate,
            pendingInteractions: interactionPayloads,
            blockDates: blockDates,
            maxElapsedHours: maxElapsedHours
        )
    }

    nonisolated static func calculateGrowthWithSeasons(
        tree: GrowthTreeState,
        existingBlocks: [VoxelBlockData],
        since lastEval: Date,
        currentDate: Date = Date(),
        pendingInteractions: [InteractionPayload] = [],
        blockDates: [Date?] = [],
        maxElapsedHours: Int = 168
    ) -> GrowthResult {
        let input = GrowthInput(
            tree: tree, existingBlocks: existingBlocks, lastEval: lastEval,
            currentDate: currentDate, pendingInteractions: pendingInteractions,
            maxElapsedHours: maxElapsedHours
        )
        let state = runGrowthTicks(input)
        let newBlocks = toVoxelBlocks(newNodes: state.newNodes, allNodes: state.allNodes)

        let allBlocks = existingBlocks + newBlocks
        let season = Season.current(from: currentDate)
        let elapsedDays = max(1, Int(currentDate.timeIntervalSince(lastEval) / 86400))
        var rng = SeededRandom(seed: UInt64(tree.seed) &+ UInt64(currentDate.timeIntervalSince1970))

        let seasonalEffects = SeasonalEngine.applySeasonalEffects(
            to: allBlocks,
            season: season,
            rng: &rng,
            elapsedDays: elapsedDays,
            blockDates: blockDates + Array(repeating: currentDate, count: newBlocks.count)
        )

        return GrowthResult(
            newBlocks: newBlocks,
            removedBlockIDs: state.removedBlockIDs,
            seasonalEffects: seasonalEffects
        )
    }

    nonisolated static func calculateGrowth(
        tree: BonsaiTree,
        existingBlocks: [VoxelBlockData],
        since lastEval: Date,
        currentDate: Date = Date(),
        pendingInteractions: [Interaction] = [],
        maxElapsedHours: Int = 168
    ) -> GrowthResult {
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
        return calculateGrowth(
            tree: treeState,
            existingBlocks: existingBlocks,
            since: lastEval,
            currentDate: currentDate,
            pendingInteractions: interactionPayloads,
            maxElapsedHours: maxElapsedHours
        )
    }

    private struct GrowthInput {
        let tree: GrowthTreeState
        let existingBlocks: [VoxelBlockData]
        let lastEval: Date
        let currentDate: Date
        let pendingInteractions: [InteractionPayload]
        let maxElapsedHours: Int
    }

    nonisolated static func calculateGrowth(
        tree: GrowthTreeState,
        existingBlocks: [VoxelBlockData],
        since lastEval: Date,
        currentDate: Date = Date(),
        pendingInteractions: [InteractionPayload] = [],
        maxElapsedHours: Int = 168
    ) -> GrowthResult {
        let input = GrowthInput(
            tree: tree, existingBlocks: existingBlocks, lastEval: lastEval,
            currentDate: currentDate, pendingInteractions: pendingInteractions,
            maxElapsedHours: maxElapsedHours
        )
        let state = runGrowthTicks(input)
        let newBlocks = toVoxelBlocks(newNodes: state.newNodes, allNodes: state.allNodes)
        return GrowthResult(
            newBlocks: newBlocks,
            removedBlockIDs: state.removedBlockIDs,
            seasonalEffects: .empty
        )
    }

    nonisolated private static func runGrowthTicks(_ input: GrowthInput) -> GrowthState {
        let elapsed = input.currentDate.timeIntervalSince(input.lastEval)
        let elapsedHours = min(Int(elapsed / 3600), input.maxElapsedHours)

        let existingNodes = toGrowthNodes(input.existingBlocks)
        var state = GrowthState(
            allNodes: existingNodes,
            woodOccupied: Set(existingNodes.filter { $0.layer == .wood }.map(\.pos)),
            foliageOccupied: Set(existingNodes.filter { $0.layer == .foliage }.map(\.pos)),
            nextNodeID: existingNodes.count,
            initialNodeCount: existingNodes.count
        )
        guard elapsedHours > 0 else { return state }

        var rng = SeededRandom(seed: UInt64(input.tree.seed) &+ UInt64(max(0, input.tree.totalBlocks)))

        for tick in 0 ..< elapsedHours {
            guard state.allNodes.count < VoxelConstants.maxBlocks else { break }
            let tickDate = input.lastEval.addingTimeInterval(Double(tick) * 3600)
            let season = Season.current(from: tickDate)
            let growthCount = blocksPerTick(
                season: season, growthStage: growthStage(for: state.allNodes), rng: &rng
            )
            guard growthCount > 0 else { continue }
            for _ in 0 ..< growthCount {
                guard state.allNodes.count < VoxelConstants.maxBlocks else { break }
                attemptGrowthUnit(
                    state: &state,
                    rng: &rng,
                    season: season,
                    pendingInteractions: input.pendingInteractions
                )
            }
            if Int(rng.next() % 100) < 18 {
                attemptBonusFoliage(state: &state, rng: &rng, season: season)
            }
        }

        return state
    }

    // MARK: - Growth Modes

    nonisolated private static func growTrunk(
        allNodes: [GrowthNode],
        woodOccupied: Set<Int3>,
        rng: inout SeededRandom
    ) -> GrowthNode? {
        let woodTips = structuralTips(in: allNodes).filter { allNodes[$0].blockType == .trunk }
        guard !woodTips.isEmpty else { return nil }

        let selectedIndex = woodTips[Int(rng.next() % UInt64(woodTips.count))]
        let parent = allNodes[selectedIndex]

        for direction in shuffledDirections(trunkDirections, rng: &rng) {
            let pos = parent.pos.adding(direction)
            guard !woodOccupied.contains(pos) else { continue }
            return GrowthNode(
                nodeID: -1, blockID: UUID(), pos: pos,
                layer: .wood, blockType: .trunk, parentNodeID: parent.nodeID
            )
        }
        return nil
    }

    nonisolated private static func growBranch(
        allNodes: [GrowthNode],
        woodOccupied: Set<Int3>,
        touchTarget: Int3?,
        rng: inout SeededRandom
    ) -> GrowthNode? {
        let woodTips = structuralTips(in: allNodes)
        guard !woodTips.isEmpty else { return nil }

        let selectedTipID: Int
        if let touchTarget {
            let scored = woodTips.min { lhs, rhs in
                let lhsDist = manhattanDistance(allNodes[lhs].pos, touchTarget)
                let rhsDist = manhattanDistance(allNodes[rhs].pos, touchTarget)
                return lhsDist < rhsDist
            }
            selectedTipID = scored ?? woodTips[Int(rng.next() % UInt64(woodTips.count))]
        } else {
            selectedTipID = woodTips[Int(rng.next() % UInt64(woodTips.count))]
        }

        let parent = allNodes[selectedTipID]
        for direction in shuffledDirections(branchDirections, rng: &rng) {
            let pos = parent.pos.adding(direction)
            guard !woodOccupied.contains(pos), pos.y >= 0 else { continue }
            return GrowthNode(
                nodeID: -1, blockID: UUID(), pos: pos,
                layer: .wood, blockType: .branch, parentNodeID: parent.nodeID
            )
        }
        return nil
    }

    nonisolated private static func growFoliageCluster(
        state: GrowthState,
        season: Season,
        rng: inout SeededRandom
    ) -> [GrowthNode]? {
        let branchTips = structuralTips(in: state.allNodes).filter { state.allNodes[$0].blockType == .branch }
        guard !branchTips.isEmpty else { return nil }

        let tipID = branchTips[Int(rng.next() % UInt64(branchTips.count))]
        let parent = state.allNodes[tipID]
        let clusterCount = Int(rng.next() % 3) + 1
        let offsets = shuffledDirections(foliageClusterOffsets, rng: &rng)

        var result: [GrowthNode] = []
        var localFoliage = state.foliageOccupied

        for offset in offsets.prefix(clusterCount) {
            let pos = parent.pos.adding(offset)
            guard pos.y >= 0, !localFoliage.contains(pos), !state.woodOccupied.contains(pos) else { continue }
            let crowding = cardinalOffsets().reduce(into: 0) { count, cardinal in
                if state.woodOccupied.contains(pos.adding(cardinal)) || localFoliage.contains(pos.adding(cardinal)) {
                    count += 1
                }
            }
            guard crowding < 5 else { continue }
            let blockType: BlockType = if season == .spring, Int(rng.next() % 100) < 14 { .flower } else { .leaf }
            result.append(GrowthNode(
                nodeID: -1, blockID: UUID(), pos: pos,
                layer: .foliage, blockType: blockType, parentNodeID: parent.nodeID
            ))
            localFoliage.insert(pos)
        }

        return result.isEmpty ? nil : result
    }

    // MARK: - Tick Helpers

    nonisolated private static func attemptGrowthUnit(
        state: inout GrowthState,
        rng: inout SeededRandom,
        season: Season,
        pendingInteractions: [InteractionPayload]
    ) {
        let touchTarget = logicalTouch(from: pendingInteractions.first { $0.type == .touch })
        for _ in 0 ..< growthAttemptsPerTick {
            let modeRoll = Int(rng.next() % 100)
            let newNode: GrowthNode? = if modeRoll < 30 {
                growTrunk(allNodes: state.allNodes, woodOccupied: state.woodOccupied, rng: &rng)
                    .map { raw in
                        GrowthNode(nodeID: state.nextNodeID, blockID: raw.blockID, pos: raw.pos,
                                   layer: raw.layer, blockType: raw.blockType, parentNodeID: raw.parentNodeID)
                    }
            } else if modeRoll < 68 {
                growBranch(allNodes: state.allNodes, woodOccupied: state.woodOccupied,
                           touchTarget: touchTarget, rng: &rng)
                    .map { raw in
                        GrowthNode(nodeID: state.nextNodeID, blockID: raw.blockID, pos: raw.pos,
                                   layer: raw.layer, blockType: raw.blockType, parentNodeID: raw.parentNodeID)
                    }
            } else {
                growFoliageCluster(state: state, season: season, rng: &rng)?.first
                    .map { raw in
                        GrowthNode(nodeID: state.nextNodeID, blockID: raw.blockID, pos: raw.pos,
                                   layer: raw.layer, blockType: raw.blockType, parentNodeID: raw.parentNodeID)
                    }
            }
            guard let node = newNode, node.pos.y >= 0 else { continue }
            if node.layer == .wood {
                guard !state.woodOccupied.contains(node.pos) else { continue }
                if state.foliageOccupied.contains(node.pos),
                   let idx = state.allNodes.firstIndex(where: { $0.pos == node.pos && $0.layer == .foliage }) {
                    let evicted = state.allNodes[idx]
                    if evicted.nodeID < state.initialNodeCount {
                        state.removedBlockIDs.append(evicted.blockID)
                    } else {
                        state.newNodes.removeAll { $0.nodeID == evicted.nodeID }
                    }
                    // allNodes retains the entry to preserve index-based nodeID lookups
                    state.foliageOccupied.remove(node.pos)
                }
                state.woodOccupied.insert(node.pos)
            } else {
                guard !state.foliageOccupied.contains(node.pos),
                      !state.woodOccupied.contains(node.pos) else { continue }
                state.foliageOccupied.insert(node.pos)
            }
            state.allNodes.append(node)
            state.newNodes.append(node)
            state.nextNodeID += 1
            break
        }
    }

    nonisolated private static func attemptBonusFoliage(
        state: inout GrowthState,
        rng: inout SeededRandom,
        season: Season
    ) {
        let cluster = growFoliageCluster(state: state, season: season, rng: &rng) ?? []
        for raw in cluster {
            guard state.allNodes.count < VoxelConstants.maxBlocks else { break }
            guard !state.foliageOccupied.contains(raw.pos),
                  !state.woodOccupied.contains(raw.pos),
                  raw.pos.y >= 0 else { continue }
            let node = GrowthNode(nodeID: state.nextNodeID, blockID: raw.blockID, pos: raw.pos,
                                  layer: raw.layer, blockType: raw.blockType, parentNodeID: raw.parentNodeID)
            state.foliageOccupied.insert(node.pos)
            state.allNodes.append(node)
            state.newNodes.append(node)
            state.nextNodeID += 1
        }
    }
}
