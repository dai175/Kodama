//
//  GrowthEngine.swift
//  Kodama
//

import Foundation

// MARK: - GrowthResult

nonisolated struct GrowthResult {
    let newBlocks: [VoxelBlockData]
    let seasonalEffects: SeasonalResult
}

nonisolated struct GrowthTreeState {
    let seed: Int
    let totalBlocks: Int
}

nonisolated struct InteractionPayload {
    let timestamp: Date
    let type: InteractionType
    let value: String?
    let touchX: Float?
    let touchY: Float?
    let touchZ: Float?
}

// MARK: - GrowthEngine

// swiftlint:disable type_body_length
nonisolated enum GrowthEngine {
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
        let newBlocks = calculateGrowth(
            tree: tree,
            existingBlocks: existingBlocks,
            since: lastEval,
            currentDate: currentDate,
            pendingInteractions: pendingInteractions,
            maxElapsedHours: maxElapsedHours
        )

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

        return GrowthResult(newBlocks: newBlocks, seasonalEffects: seasonalEffects)
    }

    nonisolated static func calculateGrowth(
        tree: BonsaiTree,
        existingBlocks: [VoxelBlockData],
        since lastEval: Date,
        currentDate: Date = Date(),
        pendingInteractions: [Interaction] = [],
        maxElapsedHours: Int = 168
    ) -> [VoxelBlockData] {
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

    nonisolated static func calculateGrowth(
        tree: GrowthTreeState,
        existingBlocks: [VoxelBlockData],
        since lastEval: Date,
        currentDate: Date = Date(),
        pendingInteractions: [InteractionPayload] = [],
        maxElapsedHours: Int = 168
    ) -> [VoxelBlockData] {
        let elapsed = currentDate.timeIntervalSince(lastEval)
        let elapsedHours = min(Int(elapsed / 3600), maxElapsedHours)
        guard elapsedHours > 0 else { return [] }

        let existingNodes = toGrowthNodes(existingBlocks)
        var allNodes = existingNodes
        var nextNodeID = allNodes.count
        var newNodes: [GrowthNode] = []

        var woodOccupied = Set(allNodes.filter { $0.layer == .wood }.map(\.pos))
        var foliageOccupied = Set(allNodes.filter { $0.layer == .foliage }.map(\.pos))

        var rng = SeededRandom(seed: UInt64(tree.seed) &+ UInt64(max(0, tree.totalBlocks)))

        for tick in 0 ..< elapsedHours {
            guard allNodes.count < VoxelConstants.maxBlocks else { break }

            let tickDate = lastEval.addingTimeInterval(Double(tick) * 3600)
            let season = Season.current(from: tickDate)
            let stage = growthStage(for: allNodes)
            let growthCount = blocksPerTick(season: season, growthStage: stage, rng: &rng)

            if growthCount == 0 { continue }

            for _ in 0 ..< growthCount {
                guard allNodes.count < VoxelConstants.maxBlocks else { break }

                for _ in 0 ..< growthAttemptsPerTick {
                    let modeRoll = Int(rng.next() % 100)
                    let newNode: GrowthNode? = if modeRoll < 30 {
                        growTrunk(
                            allNodes: allNodes,
                            woodOccupied: woodOccupied,
                            rng: &rng
                        ).map { node in
                            GrowthNode(
                                nodeID: nextNodeID,
                                blockID: node.blockID,
                                pos: node.pos,
                                layer: node.layer,
                                blockType: node.blockType,
                                parentNodeID: node.parentNodeID
                            )
                        }
                    } else if modeRoll < 68 {
                        growBranch(
                            allNodes: allNodes,
                            woodOccupied: woodOccupied,
                            touchTarget: logicalTouch(from: pendingInteractions.first { $0.type == .touch }),
                            rng: &rng
                        ).map { node in
                            GrowthNode(
                                nodeID: nextNodeID,
                                blockID: node.blockID,
                                pos: node.pos,
                                layer: node.layer,
                                blockType: node.blockType,
                                parentNodeID: node.parentNodeID
                            )
                        }
                    } else {
                        growFoliageCluster(
                            allNodes: allNodes,
                            woodOccupied: woodOccupied,
                            foliageOccupied: foliageOccupied,
                            season: season,
                            rng: &rng,
                            startID: nextNodeID
                        )?.first
                    }

                    guard let node = newNode else { continue }
                    guard node.pos.y >= 0 else { continue }

                    if node.layer == .wood {
                        guard !woodOccupied.contains(node.pos) else { continue }
                        woodOccupied.insert(node.pos)
                    } else {
                        guard !foliageOccupied.contains(node.pos) else { continue }
                        foliageOccupied.insert(node.pos)
                    }

                    allNodes.append(node)
                    newNodes.append(node)
                    nextNodeID += 1
                    break
                }
            }

            if Int(rng.next() % 100) < 18 {
                let cluster = growFoliageCluster(
                    allNodes: allNodes,
                    woodOccupied: woodOccupied,
                    foliageOccupied: foliageOccupied,
                    season: season,
                    rng: &rng,
                    startID: nextNodeID
                ) ?? []

                for node in cluster {
                    guard allNodes.count < VoxelConstants.maxBlocks else { break }
                    guard !foliageOccupied.contains(node.pos), node.pos.y >= 0 else { continue }
                    foliageOccupied.insert(node.pos)
                    allNodes.append(node)
                    newNodes.append(node)
                    nextNodeID += 1
                }
            }
        }

        return toVoxelBlocks(newNodes: newNodes, allNodes: allNodes)
    }

    // MARK: - Growth Modes

    private nonisolated static func growTrunk(
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
                nodeID: -1,
                blockID: UUID(),
                pos: pos,
                layer: .wood,
                blockType: .trunk,
                parentNodeID: parent.nodeID
            )
        }

        return nil
    }

    private nonisolated static func growBranch(
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
                let l = manhattanDistance(allNodes[lhs].pos, touchTarget)
                let r = manhattanDistance(allNodes[rhs].pos, touchTarget)
                return l < r
            }
            selectedTipID = scored ?? woodTips[Int(rng.next() % UInt64(woodTips.count))]
        } else {
            selectedTipID = woodTips[Int(rng.next() % UInt64(woodTips.count))]
        }

        let parent = allNodes[selectedTipID]
        let directions = shuffledDirections(branchDirections, rng: &rng)
        for direction in directions {
            let pos = parent.pos.adding(direction)
            guard !woodOccupied.contains(pos), pos.y >= 0 else { continue }
            return GrowthNode(
                nodeID: -1,
                blockID: UUID(),
                pos: pos,
                layer: .wood,
                blockType: .branch,
                parentNodeID: parent.nodeID
            )
        }

        return nil
    }

    private nonisolated static func growFoliageCluster(
        allNodes: [GrowthNode],
        woodOccupied: Set<Int3>,
        foliageOccupied: Set<Int3>,
        season: Season,
        rng: inout SeededRandom,
        startID: Int
    ) -> [GrowthNode]? {
        let branchTips = structuralTips(in: allNodes).filter { allNodes[$0].blockType == .branch }
        guard !branchTips.isEmpty else { return nil }

        let tipID = branchTips[Int(rng.next() % UInt64(branchTips.count))]
        let parent = allNodes[tipID]

        let clusterCount = Int(rng.next() % 3) + 1
        let offsets = shuffledDirections(foliageClusterOffsets, rng: &rng)

        var result: [GrowthNode] = []
        var localFoliage = foliageOccupied
        var nextID = startID

        for offset in offsets.prefix(clusterCount) {
            let pos = parent.pos.adding(offset)
            guard pos.y >= 0 else { continue }
            guard !localFoliage.contains(pos) else { continue }

            let crowding = cardinalOffsets().reduce(into: 0) { count, cardinal in
                if woodOccupied.contains(pos.adding(cardinal)) || localFoliage.contains(pos.adding(cardinal)) {
                    count += 1
                }
            }
            guard crowding < 5 else { continue }

            let blockType: BlockType = if season == .spring, Int(rng.next() % 100) < 14 {
                .flower
            } else {
                .leaf
            }

            result.append(
                GrowthNode(
                    nodeID: nextID,
                    blockID: UUID(),
                    pos: pos,
                    layer: .foliage,
                    blockType: blockType,
                    parentNodeID: parent.nodeID
                )
            )
            localFoliage.insert(pos)
            nextID += 1
        }

        return result.isEmpty ? nil : result
    }

    // MARK: - Helpers

    private nonisolated static func toGrowthNodes(_ blocks: [VoxelBlockData]) -> [GrowthNode] {
        let nodeIDsByBlockID = nodeIDsByBlockID(blocks)
        return blocks.enumerated().map { index, block in
            GrowthNode(
                nodeID: index,
                blockID: block.id,
                pos: GridMapper.int3(from: block),
                layer: GridMapper.layer(for: block.blockType),
                blockType: block.blockType,
                parentNodeID: parentNodeID(for: block, nodeIDsByBlockID: nodeIDsByBlockID)
            )
        }
    }

    private nonisolated static func nodeIDsByBlockID(_ blocks: [VoxelBlockData]) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for (index, block) in blocks.enumerated() {
            result[block.id] = index
        }
        return result
    }

    private nonisolated static func parentNodeID(for block: VoxelBlockData, nodeIDsByBlockID: [UUID: Int]) -> Int? {
        guard let parentID = block.parentID else { return nil }
        return nodeIDsByBlockID[parentID]
    }

    private nonisolated static func toVoxelBlocks(newNodes: [GrowthNode], allNodes: [GrowthNode]) -> [VoxelBlockData] {
        let blockIDsByNodeID = Dictionary(uniqueKeysWithValues: allNodes.map { ($0.nodeID, $0.blockID) })
        return newNodes.map { node in
            let parentID = node.parentNodeID.flatMap { blockIDsByNodeID[$0] }
            return VoxelBlockData(
                id: node.blockID,
                pos: node.pos,
                blockType: node.blockType,
                colorHex: blockColor(for: node.blockType),
                parentID: parentID
            )
        }
    }

    private nonisolated static func blockColor(for blockType: BlockType) -> String {
        switch blockType {
        case .trunk:
            TreeBuilder.trunkColors.first ?? "#4A3520"
        case .branch:
            TreeBuilder.branchColors.first ?? "#5A4530"
        case .leaf:
            TreeBuilder.leafColors.first ?? "#7AB648"
        case .flower:
            SeasonalEngine.springFlowerColor
        case .moss:
            SeasonalEngine.summerMossColor
        case .snow:
            SeasonalEngine.snowColor
        }
    }

    private nonisolated static func growthStage(for nodes: [GrowthNode]) -> TreeBuilder.GrowthStage {
        let woodCount = nodes.count(where: { $0.layer == .wood })
        let foliageCount = nodes.count(where: { $0.layer == .foliage })
        let maxY = nodes.map(\.pos.y).max() ?? 0

        if woodCount < 16 || maxY <= 6 {
            return .sapling
        }
        if woodCount < 28 || foliageCount < 18 {
            return .young
        }
        return .mature
    }

    private nonisolated static func blocksPerTick(
        season: Season,
        growthStage: TreeBuilder.GrowthStage,
        rng: inout SeededRandom
    ) -> Int {
        let roll = Int(rng.next() % 100)

        switch season {
        case .spring:
            return roll < 22 ? 1 : 0
        case .summer:
            let threshold = switch growthStage {
            case .sapling:
                14
            case .young:
                16
            case .mature:
                18
            }
            return roll < threshold ? 1 : 0
        case .autumn:
            return roll < 6 ? 1 : 0
        case .winter:
            return 0
        }
    }

    private nonisolated static func structuralTips(in nodes: [GrowthNode]) -> [Int] {
        var parentHasWoodChild = Set<Int>()
        for node in nodes where node.layer == .wood {
            if let parentNodeID = node.parentNodeID {
                parentHasWoodChild.insert(parentNodeID)
            }
        }

        return nodes.enumerated().compactMap { index, node in
            guard node.layer == .wood else { return nil }
            return parentHasWoodChild.contains(node.nodeID) ? nil : index
        }
    }

    private nonisolated static func logicalTouch(from interaction: InteractionPayload?) -> Int3? {
        guard let interaction,
              let x = interaction.touchX,
              let y = interaction.touchY,
              let z = interaction.touchZ
        else { return nil }

        return Int3(x: Int(x.rounded()), y: Int(y.rounded()), z: Int(z.rounded()))
    }

    private nonisolated static func shuffledDirections<T>(_ values: [T], rng: inout SeededRandom) -> [T] {
        var copy = values
        guard copy.count > 1 else { return copy }
        for i in 0 ..< (copy.count - 1) {
            let j = i + Int(rng.next() % UInt64(copy.count - i))
            copy.swapAt(i, j)
        }
        return copy
    }

    private nonisolated static func cardinalOffsets() -> [Int3] {
        [
            Int3(x: 1, y: 0, z: 0), Int3(x: -1, y: 0, z: 0),
            Int3(x: 0, y: 1, z: 0), Int3(x: 0, y: -1, z: 0),
            Int3(x: 0, y: 0, z: 1), Int3(x: 0, y: 0, z: -1)
        ]
    }

    private nonisolated static func manhattanDistance(_ lhs: Int3, _ rhs: Int3) -> Int {
        abs(lhs.x - rhs.x) + abs(lhs.y - rhs.y) + abs(lhs.z - rhs.z)
    }

    nonisolated static func branchDistanceFromTrunk(startingAt index: Int, allBlocks: [VoxelBlockData]) -> Int {
        guard index >= 0, index < allBlocks.count else { return 0 }

        var distance = 0
        var currentIndex: Int? = index

        while let resolvedIndex = currentIndex {
            guard resolvedIndex >= 0, resolvedIndex < allBlocks.count else { break }

            let block = allBlocks[resolvedIndex]
            if block.blockType == .trunk {
                return distance
            }
            if block.blockType == .branch {
                distance += 1
            }
            guard let parentID = block.parentID else {
                currentIndex = nil
                continue
            }
            currentIndex = allBlocks.firstIndex(where: { $0.id == parentID })
        }

        return distance
    }
}

// swiftlint:enable type_body_length
