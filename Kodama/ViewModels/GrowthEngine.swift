//
//  GrowthEngine.swift
//  Kodama
//

import Foundation

// MARK: - GrowthResult

struct GrowthResult {
    let newBlocks: [VoxelBlockData]
    let seasonalEffects: SeasonalResult
}

// MARK: - GrowthEngine

enum GrowthEngine {
    private static let growthAttemptsPerBlock = 8

    // MARK: - Growth Calculation

    /// Pure function: takes existing state, returns new blocks and seasonal effects.
    static func calculateGrowthWithSeasons(
        tree: BonsaiTree,
        existingBlocks: [VoxelBlockData],
        since lastEval: Date,
        currentDate: Date = Date(),
        pendingInteractions: [Interaction] = [],
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

    /// Pure function: takes existing state, returns new blocks to add.
    static func calculateGrowth(
        tree: BonsaiTree,
        existingBlocks: [VoxelBlockData],
        since lastEval: Date,
        currentDate: Date = Date(),
        pendingInteractions: [Interaction] = [],
        maxElapsedHours: Int = 168
    ) -> [VoxelBlockData] {
        let elapsed = currentDate.timeIntervalSince(lastEval)
        let elapsedHours = min(Int(elapsed / 3600), maxElapsedHours)

        guard elapsedHours > 0 else { return [] }

        var allBlocks = existingBlocks
        var newBlocks: [VoxelBlockData] = []
        var rng = SeededRandom(seed: UInt64(tree.seed) &+ UInt64(tree.totalBlocks))

        // Structural tips ignore foliage children so a branch can keep growing after sprouting leaves.
        // Reverse-index: one pass over allBlocks to collect structural parents (O(n) vs O(n²)).
        var parentIndices: Set<Int> = []
        for block in allBlocks where isStructuralBlock(block.blockType) {
            if let pi = block.parentIndex { parentIndices.insert(pi) }
        }
        var tipIndices = Set(allBlocks.indices.filter {
            !parentIndices.contains($0) && isGrowableTip(allBlocks[$0].blockType)
        })

        var occupiedPositions = Set(allBlocks.map(\.positionKey))
        var currentMaxY = allBlocks.map(\.y).max() ?? 0
        // trunkTopY is constant during the loop: growBlock only adds branches/leaves,
        // and thickenTrunk adds trunk blocks laterally (same Y level).
        let trunkTopY = allBlocks.filter { $0.blockType == .trunk }.map(\.y).max() ?? currentMaxY

        for tick in 0 ..< elapsedHours {
            let tickDate = lastEval.addingTimeInterval(Double(tick) * 3600)
            let season = Season.current(from: tickDate)

            let growthCount = blocksPerTick(season: season, rng: &rng)
            let prevCount = allBlocks.count

            for _ in 0 ..< growthCount {
                guard allBlocks.count < VoxelConstants.maxBlocks else { return newBlocks }

                for _ in 0 ..< growthAttemptsPerBlock {
                    if let (block, usedTipIndex) = growBlock(
                        allBlocks: allBlocks,
                        tipIndices: tipIndices,
                        occupiedPositions: &occupiedPositions,
                        trunkTopY: trunkTopY,
                        season: season,
                        rng: &rng,
                        pendingInteractions: pendingInteractions
                    ) {
                        let newIndex = allBlocks.count
                        if isStructuralBlock(block.blockType) {
                            parentIndices.insert(usedTipIndex)
                            tipIndices.remove(usedTipIndex)
                        }
                        if isGrowableTip(block.blockType) { tipIndices.insert(newIndex) }
                        occupiedPositions.insert(block.positionKey)
                        currentMaxY = max(currentMaxY, block.y)
                        allBlocks.append(block)
                        newBlocks.append(block)
                        break
                    }
                }
            }

            // Trigger thickening only when the 30-block milestone was actually crossed this tick
            if allBlocks.count / 30 > prevCount / 30 {
                let thickenBlocks = thickenTrunk(allBlocks: allBlocks, occupiedPositions: &occupiedPositions, rng: &rng)
                for block in thickenBlocks {
                    guard allBlocks.count < VoxelConstants.maxBlocks else { break }
                    let newIndex = allBlocks.count
                    if let pi = block.parentIndex, isStructuralBlock(block.blockType) {
                        parentIndices.insert(pi)
                        tipIndices.remove(pi)
                    }
                    if isGrowableTip(block.blockType) { tipIndices.insert(newIndex) }
                    occupiedPositions.insert(block.positionKey)
                    currentMaxY = max(currentMaxY, block.y)
                    allBlocks.append(block)
                    newBlocks.append(block)
                }
            }
        }

        return newBlocks
    }

    private static func isGrowableTip(_ blockType: BlockType) -> Bool {
        isStructuralBlock(blockType)
    }

    private static func isStructuralBlock(_ blockType: BlockType) -> Bool {
        blockType == .branch || blockType == .trunk
    }

    // MARK: - Growth Rate

    private static func blocksPerTick(season: Season, rng: inout SeededRandom) -> Int {
        let roll = Int(rng.next() % 100)

        switch season {
        case .spring:
            return roll < 20 ? 1 : 0
        case .summer:
            return roll < 12 ? 1 : 0
        case .autumn:
            return roll < 4 ? 1 : 0
        case .winter:
            return 0
        }
    }

    // MARK: - Block Growth

    // swiftlint:disable:next function_parameter_count
    private static func growBlock(
        allBlocks: [VoxelBlockData],
        tipIndices: Set<Int>,
        occupiedPositions: inout Set<PositionKey>,
        trunkTopY: Float,
        season: Season,
        rng: inout SeededRandom,
        pendingInteractions: [Interaction]
    ) -> (VoxelBlockData, Int)? {
        guard !tipIndices.isEmpty else { return nil }

        let tipArray = prioritizedTipIndices(from: allBlocks, tipIndices: tipIndices)
        guard !tipArray.isEmpty else { return nil }

        // Weight tips by proximity to touch interactions
        let touchInteraction = pendingInteractions.first { $0.type == .touch && $0.touchX != nil }
        let selectedTipIndex: Int

        if let touch = touchInteraction, let tx = touch.touchX, let ty = touch.touchY, let tz = touch.touchZ {
            let weights: [Double] = tipArray.map { i in
                let block = allBlocks[i]
                let dx = Double(block.x - tx)
                let dy = Double(block.y - ty)
                let dz = Double(block.z - tz)
                let dist = sqrt(dx * dx + dy * dy + dz * dz)
                return 1.0 / (dist + 1.0)
            }
            selectedTipIndex = weightedSelect(indices: tipArray, weights: weights, rng: &rng)
        } else {
            selectedTipIndex = tipArray[Int(rng.next() % UInt64(tipArray.count))]
        }

        let tip = allBlocks[selectedTipIndex]
        let trunkHeight = max(trunkTopY + VoxelConstants.blockSize, VoxelConstants.blockSize)
        let canopyLimitY = trunkTopY + trunkHeight * 0.8
        let isHighUp = tip.y >= canopyLimitY
        let branchDepth = branchDistanceFromTrunk(startingAt: selectedTipIndex, allBlocks: allBlocks)
        let canGrowFoliage = tip.blockType == .branch && branchDepth >= 2

        // Determine block type
        let blockType = determineBlockType(
            tip: tip,
            canGrowFoliage: canGrowFoliage,
            isHighUp: isHighUp,
            season: season,
            rng: &rng
        )

        let direction = growthDirection(
            from: tip,
            blockType: blockType,
            isHighUp: isHighUp,
            rng: &rng,
            pendingInteractions: pendingInteractions
        )

        let newX = tip.x + direction.0
        let newY = tip.y + direction.1
        let newZ = tip.z + direction.2

        // Avoid overlapping existing blocks
        guard !occupiedPositions.contains(PositionKey(x: newX, y: newY, z: newZ)) else { return nil }

        // Don't grow below ground
        guard newY >= 0 else { return nil }

        let color = blockColor(for: blockType, season: season, rng: &rng)

        let block = VoxelBlockData(
            x: newX,
            y: newY,
            z: newZ,
            blockType: blockType,
            colorHex: color,
            parentIndex: selectedTipIndex
        )
        return (block, selectedTipIndex)
    }

    // MARK: - Block Type Determination

    private static func determineBlockType(
        tip: VoxelBlockData,
        canGrowFoliage: Bool,
        isHighUp: Bool,
        season: Season,
        rng: inout SeededRandom
    ) -> BlockType {
        let roll = Int(rng.next() % 100)

        if tip.blockType == .trunk {
            return .branch
        }

        guard canGrowFoliage else {
            return .branch
        }

        if isHighUp {
            if season == .spring, roll < 10 {
                return .flower
            } else if roll < 75 {
                return .leaf
            } else {
                return .branch
            }
        }

        if season == .spring, roll < 10 {
            return .flower
        }

        if roll < 55 {
            return .leaf
        }

        return .branch
    }

    // MARK: - Growth Direction

    private static func growthDirection(
        from tip: VoxelBlockData,
        blockType: BlockType,
        isHighUp: Bool,
        rng: inout SeededRandom,
        pendingInteractions: [Interaction]
    ) -> (Float, Float, Float) {
        let bs = VoxelConstants.blockSize
        let directions: [(Float, Float, Float)]
        let weights: [Double]

        if blockType == .leaf || blockType == .flower {
            directions = [
                (0, bs, 0),
                (bs, 0, 0), (-bs, 0, 0),
                (0, 0, bs), (0, 0, -bs)
            ]
            weights = [
                20.0,
                17.5, 17.5,
                17.5, 17.5
            ]
        } else {
            directions = [
                (bs, 0, 0), (-bs, 0, 0),
                (0, 0, bs), (0, 0, -bs),
                (0, bs, 0),
                (bs, -bs, 0), (-bs, -bs, 0),
                (0, -bs, bs), (0, -bs, -bs)
            ]
            weights = [
                17.5, 17.5,
                17.5, 17.5,
                isHighUp || tip.blockType == .trunk ? 8.0 : 20.0,
                2.5, 2.5,
                2.5, 2.5
            ]
        }

        var adjustedWeights = weights

        // Word influence on direction
        let wordInteraction = pendingInteractions.first { $0.type == .word }
        if let word = wordInteraction?.value {
            let wordLength = word.count
            if wordLength > 5 {
                for (index, direction) in directions.enumerated()
                    where abs(direction.1) < VoxelConstants.halfBlock {
                    adjustedWeights[index] += Double(wordLength) * 0.3
                }
            }

            // First letter ASCII influences direction
            if let firstChar = word.first {
                let ascii = Int(firstChar.asciiValue ?? 0)
                let dirBias = ascii % directions.count
                adjustedWeights[dirBias] += 2.0
            }
        }

        let indices = Array(directions.indices)
        let selectedIndex = weightedSelect(indices: indices, weights: adjustedWeights, rng: &rng)
        return directions[selectedIndex]
    }

    private static func prioritizedTipIndices(from allBlocks: [VoxelBlockData], tipIndices: Set<Int>) -> [Int] {
        let branchTips = tipIndices.filter { allBlocks[$0].blockType == .branch }
        if !branchTips.isEmpty {
            return Array(branchTips)
        }

        let trunkTips = tipIndices.filter { allBlocks[$0].blockType == .trunk }
        return Array(trunkTips)
    }

    static func branchDistanceFromTrunk(startingAt index: Int, allBlocks: [VoxelBlockData]) -> Int {
        var distance = 0
        var currentIndex: Int? = index

        while let resolvedIndex = currentIndex {
            let block = allBlocks[resolvedIndex]
            if block.blockType == .trunk {
                return distance
            }
            if block.blockType == .branch {
                distance += 1
            }
            currentIndex = block.parentIndex
        }

        return distance
    }

    // MARK: - Color

    private static func blockColor(for blockType: BlockType, season: Season, rng: inout SeededRandom) -> String {
        switch blockType {
        case .trunk:
            TreeBuilder.trunkColors[Int(rng.next() % UInt64(TreeBuilder.trunkColors.count))]
        case .branch:
            TreeBuilder.branchColors[Int(rng.next() % UInt64(TreeBuilder.branchColors.count))]
        case .leaf:
            SeasonalEngine.leafColor(for: season, rng: &rng)
        case .flower:
            SeasonalEngine.springFlowerColor
        case .moss:
            SeasonalEngine.summerMossColor
        case .snow:
            SeasonalEngine.snowColor
        }
    }

    // MARK: - Trunk Thickening

    private static func thickenTrunk(
        allBlocks: [VoxelBlockData],
        occupiedPositions: inout Set<PositionKey>,
        rng: inout SeededRandom
    ) -> [VoxelBlockData] {
        let bs = VoxelConstants.blockSize
        let thickenableBlocks = allBlocks.enumerated().filter {
            $0.element.blockType == .trunk || $0.element.blockType == .branch
        }
        guard !thickenableBlocks.isEmpty else { return [] }

        let maxY = thickenableBlocks.map(\.element.y).max() ?? 1

        // Weight lower blocks higher (lower normalized height = higher weight)
        // Branch blocks get 0.3x the weight of trunk blocks
        let weights: [Double] = thickenableBlocks.map { _, block in
            let normalizedHeight = maxY > 0 ? Double(block.y / maxY) : 0
            let baseWeight = 1.0 - normalizedHeight
            return block.blockType == .trunk ? baseWeight : baseWeight * 0.3
        }

        let selectedLocalIndex = weightedSelect(indices: Array(thickenableBlocks.indices), weights: weights, rng: &rng)
        let (blockIndex, selectedBlock) = thickenableBlocks[selectedLocalIndex]

        var newBlocks: [VoxelBlockData] = []
        let adjacentOffsets: [(Float, Float)] = [(bs, 0), (-bs, 0), (0, bs), (0, -bs)]

        for offset in adjacentOffsets {
            let newX = selectedBlock.x + offset.0
            let newZ = selectedBlock.z + offset.1

            if !occupiedPositions.contains(PositionKey(x: newX, y: selectedBlock.y, z: newZ)) {
                // Outer blocks use outerTrunkColors for year-ring effect
                let color = VoxelConstants
                    .outerTrunkColors[Int(rng.next() % UInt64(VoxelConstants.outerTrunkColors.count))]
                newBlocks.append(VoxelBlockData(
                    x: newX,
                    y: selectedBlock.y,
                    z: newZ,
                    blockType: .trunk,
                    colorHex: color,
                    parentIndex: blockIndex
                ))
                break // Only add one thickening block per cycle
            }
        }

        return newBlocks
    }

    // MARK: - Weighted Random Selection

    private static func weightedSelect(indices: [Int], weights: [Double], rng: inout SeededRandom) -> Int {
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return indices[Int(rng.next() % UInt64(indices.count))] }

        let roll = Double(rng.next() % 10000) / 10000.0 * totalWeight
        var cumulative = 0.0

        for (i, weight) in weights.enumerated() {
            cumulative += weight
            if roll < cumulative {
                return indices[i]
            }
        }

        return indices[indices.count - 1]
    }
}
