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
    // MARK: - Growth Calculation

    /// Pure function: takes existing state, returns new blocks and seasonal effects.
    static func calculateGrowthWithSeasons(
        tree: BonsaiTree,
        existingBlocks: [VoxelBlockData],
        since lastEval: Date,
        currentDate: Date = Date(),
        pendingInteractions: [Interaction] = [],
        blockDates: [Date?] = []
    ) -> GrowthResult {
        let newBlocks = calculateGrowth(
            tree: tree,
            existingBlocks: existingBlocks,
            since: lastEval,
            currentDate: currentDate,
            pendingInteractions: pendingInteractions
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
        pendingInteractions: [Interaction] = []
    ) -> [VoxelBlockData] {
        let elapsed = currentDate.timeIntervalSince(lastEval)
        let elapsedHours = min(Int(elapsed / 3600), 168)

        guard elapsedHours > 0 else { return [] }

        var allBlocks = existingBlocks
        var newBlocks: [VoxelBlockData] = []
        var rng = SeededRandom(seed: UInt64(tree.seed) &+ UInt64(tree.totalBlocks))

        // Pre-compute tip sets; updated incrementally to avoid O(n) per growBlock call
        var parentIndices = Set(allBlocks.compactMap(\.parentIndex))
        var tipIndices = Set(allBlocks.indices.filter {
            !parentIndices.contains($0) && isGrowableTip(allBlocks[$0].blockType)
        })

        for tick in 0 ..< elapsedHours {
            let tickDate = lastEval.addingTimeInterval(Double(tick) * 3600)
            let season = Season.current(from: tickDate)

            let growthCount = blocksPerTick(season: season, rng: &rng)

            for _ in 0 ..< growthCount {
                guard allBlocks.count < 2000 else { return newBlocks }

                if let (block, usedTipIndex) = growBlock(
                    allBlocks: allBlocks,
                    tipIndices: tipIndices,
                    season: season,
                    rng: &rng,
                    pendingInteractions: pendingInteractions
                ) {
                    let newIndex = allBlocks.count
                    parentIndices.insert(usedTipIndex)
                    tipIndices.remove(usedTipIndex)
                    if isGrowableTip(block.blockType) { tipIndices.insert(newIndex) }
                    allBlocks.append(block)
                    newBlocks.append(block)
                }
            }

            // Trigger thickening near every 50-block milestone; window accounts for multi-block ticks
            if allBlocks.count >= 50, allBlocks.count % 50 < growthCount + 1 {
                let thickenBlocks = thickenTrunk(allBlocks: allBlocks, rng: &rng)
                for block in thickenBlocks {
                    guard allBlocks.count < 2000 else { break }
                    let newIndex = allBlocks.count
                    if let pi = block.parentIndex {
                        parentIndices.insert(pi)
                        tipIndices.remove(pi)
                    }
                    if isGrowableTip(block.blockType) { tipIndices.insert(newIndex) }
                    allBlocks.append(block)
                    newBlocks.append(block)
                }
            }
        }

        return newBlocks
    }

    private static func isGrowableTip(_ blockType: BlockType) -> Bool {
        blockType == .branch || blockType == .leaf || blockType == .trunk
    }

    // MARK: - Growth Rate

    private static func blocksPerTick(season: Season, rng: inout SeededRandom) -> Int {
        switch season {
        case .spring:
            Int(rng.next() % 3) + 1 // 1-3
        case .summer:
            Int(rng.next() % 2) + 1 // 1-2
        case .autumn:
            Int(rng.next() % 2) // 0-1
        case .winter:
            0
        }
    }

    // MARK: - Block Growth

    private static func growBlock(
        allBlocks: [VoxelBlockData],
        tipIndices: Set<Int>,
        season: Season,
        rng: inout SeededRandom,
        pendingInteractions: [Interaction]
    ) -> (VoxelBlockData, Int)? {
        guard !tipIndices.isEmpty else { return nil }

        let tipArray = Array(tipIndices)

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
        let maxY = allBlocks.map(\.y).max() ?? 0
        let isHighUp = tip.y > maxY * 0.6

        // Determine block type
        let blockType = determineBlockType(
            nearTrunk: tip.blockType == .trunk,
            isHighUp: isHighUp,
            season: season,
            rng: &rng
        )

        // Determine direction with upward bias
        let direction = growthDirection(rng: &rng, pendingInteractions: pendingInteractions)

        let newX = tip.x + direction.0
        let newY = tip.y + direction.1
        let newZ = tip.z + direction.2

        // Avoid overlapping existing blocks
        guard !allBlocks.contains(where: { $0.overlaps(x: newX, y: newY, z: newZ) }) else { return nil }

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
        nearTrunk: Bool,
        isHighUp: Bool,
        season: Season,
        rng: inout SeededRandom
    ) -> BlockType {
        let roll = Int(rng.next() % 100)

        if nearTrunk {
            // Near trunk: branch(70%) / leaf(30%)
            return roll < 70 ? .branch : .leaf
        }

        if isHighUp {
            // High up: flower(10% in spring) / leaf(50% in spring, 60% otherwise) / branch(40% in spring, 40%
            // otherwise)
            if season == .spring, roll < 10 {
                return .flower
            } else if roll < 60 {
                return .leaf
            } else {
                return .branch
            }
        }

        // Default: branch(50%) / leaf(50%)
        return roll < 50 ? .branch : .leaf
    }

    // MARK: - Growth Direction

    private static func growthDirection(
        rng: inout SeededRandom,
        pendingInteractions: [Interaction]
    ) -> (Float, Float, Float) {
        // Upward bias + random lateral
        let directions: [(Float, Float, Float)] = [
            (0, 1, 0), // up
            (1, 1, 0), (-1, 1, 0), // up-lateral X
            (0, 1, 1), (0, 1, -1), // up-lateral Z
            (1, 0, 0), (-1, 0, 0), // lateral X
            (0, 0, 1), (0, 0, -1) // lateral Z
        ]

        // Weight upward directions more heavily
        let weights: [Double] = [
            3.0, // up
            2.0, 2.0, // up-lateral
            2.0, 2.0, // up-lateral
            1.0, 1.0, // lateral
            1.0, 1.0 // lateral
        ]

        var adjustedWeights = weights

        // Word influence on direction
        let wordInteraction = pendingInteractions.first { $0.type == .word }
        if let word = wordInteraction?.value {
            let wordLength = word.count
            if wordLength > 5 {
                // Longer words = more horizontal
                adjustedWeights[5] += Double(wordLength) * 0.3
                adjustedWeights[6] += Double(wordLength) * 0.3
                adjustedWeights[7] += Double(wordLength) * 0.3
                adjustedWeights[8] += Double(wordLength) * 0.3
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

    private static func thickenTrunk(allBlocks: [VoxelBlockData], rng: inout SeededRandom) -> [VoxelBlockData] {
        let trunkBlocks = allBlocks.enumerated().filter { $0.element.blockType == .trunk }
        guard !trunkBlocks.isEmpty else { return [] }

        var newBlocks: [VoxelBlockData] = []
        let adjacentOffsets: [(Float, Float)] = [(1, 0), (-1, 0), (0, 1), (0, -1)]

        // Pick a random trunk block to thicken
        let (trunkIndex, trunkBlock) = trunkBlocks[Int(rng.next() % UInt64(trunkBlocks.count))]

        for offset in adjacentOffsets {
            let newX = trunkBlock.x + offset.0
            let newZ = trunkBlock.z + offset.1

            if !allBlocks.contains(where: { $0.overlaps(x: newX, y: trunkBlock.y, z: newZ) }) {
                let color = TreeBuilder.trunkColors[Int(rng.next() % UInt64(TreeBuilder.trunkColors.count))]
                newBlocks.append(VoxelBlockData(
                    x: newX,
                    y: trunkBlock.y,
                    z: newZ,
                    blockType: .trunk,
                    colorHex: color,
                    parentIndex: trunkIndex
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
