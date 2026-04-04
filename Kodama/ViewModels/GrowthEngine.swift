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

struct GrowthTreeState {
    let seed: Int
    let totalBlocks: Int
}

struct InteractionPayload {
    let timestamp: Date
    let type: InteractionType
    let value: String?
    let touchX: Float?
    let touchY: Float?
    let touchZ: Float?
}

// MARK: - GrowthEngine

// swiftlint:disable type_body_length
enum GrowthEngine {
    private static let growthAttemptsPerBlock = 8

    // MARK: - Growth Calculation

    /// Pure function: takes existing state, returns new blocks and seasonal effects.
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

    /// Pure function: takes existing state, returns new blocks to add.
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
            let growthStage = TreeBuilder.growthStage(for: allBlocks)

            let growthCount = blocksPerTick(season: season, growthStage: growthStage, rng: &rng)
            let prevCount = allBlocks.count

            for _ in 0 ..< growthCount {
                guard allBlocks.count < VoxelConstants.maxBlocks else { return newBlocks }

                for _ in 0 ..< growthAttemptsPerBlock {
                    if let (block, usedTipIndex) = growBlock(
                        allBlocks: allBlocks,
                        tipIndices: tipIndices,
                        occupiedPositions: &occupiedPositions,
                        trunkTopY: trunkTopY,
                        growthStage: growthStage,
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

    private nonisolated static func isGrowableTip(_ blockType: BlockType) -> Bool {
        isStructuralBlock(blockType)
    }

    private nonisolated static func isStructuralBlock(_ blockType: BlockType) -> Bool {
        blockType == .branch || blockType == .trunk
    }

    // MARK: - Growth Rate

    private nonisolated static func blocksPerTick(
        season: Season,
        growthStage: TreeBuilder.GrowthStage,
        rng: inout SeededRandom
    ) -> Int {
        let roll = Int(rng.next() % 100)

        switch season {
        case .spring:
            return roll < 20 ? 1 : 0
        case .summer:
            let threshold = switch growthStage {
            case .sapling:
                12
            case .young:
                14
            case .mature:
                17
            }
            return roll < threshold ? 1 : 0
        case .autumn:
            return roll < 4 ? 1 : 0
        case .winter:
            return 0
        }
    }

    // MARK: - Block Growth

    // swiftlint:disable:next function_parameter_count
    private nonisolated static func growBlock(
        allBlocks: [VoxelBlockData],
        tipIndices: Set<Int>,
        occupiedPositions: inout Set<PositionKey>,
        trunkTopY: Float,
        growthStage: TreeBuilder.GrowthStage,
        season: Season,
        rng: inout SeededRandom,
        pendingInteractions: [InteractionPayload]
    ) -> (VoxelBlockData, Int)? {
        guard !tipIndices.isEmpty else { return nil }

        var remainingTipIndices = prioritizedTipIndices(from: allBlocks, tipIndices: tipIndices)
        guard !remainingTipIndices.isEmpty else { return nil }

        // Weight tips by proximity to touch interactions
        let touchInteraction = pendingInteractions.first { $0.type == .touch && $0.touchX != nil }
        let trunkHeight = max(trunkTopY + VoxelConstants.blockSize, VoxelConstants.blockSize)
        let canopyLimitY = trunkTopY + trunkHeight * 0.8

        while !remainingTipIndices.isEmpty {
            let selectedTipIndex: Int

            if let touch = touchInteraction, let tx = touch.touchX, let ty = touch.touchY, let tz = touch.touchZ {
                let weights: [Double] = remainingTipIndices.map { i in
                    let block = allBlocks[i]
                    let dx = Double(block.x - tx)
                    let dy = Double(block.y - ty)
                    let dz = Double(block.z - tz)
                    let dist = sqrt(dx * dx + dy * dy + dz * dz)
                    return 1.0 / (dist + 1.0)
                }
                selectedTipIndex = weightedSelect(indices: remainingTipIndices, weights: weights, rng: &rng)
            } else {
                selectedTipIndex = remainingTipIndices[Int(rng.next() % UInt64(remainingTipIndices.count))]
            }

            let tip = allBlocks[selectedTipIndex]
            let isHighUp = tip.y >= canopyLimitY
            let branchDepth = branchDistanceFromTrunk(startingAt: selectedTipIndex, allBlocks: allBlocks)
            let radialDistance = radialDistanceFromCenter(of: tip)
            let straightRunLength = straightRunLength(startingAt: selectedTipIndex, allBlocks: allBlocks)
            let canGrowFoliage = tip.blockType == .branch && branchDepth >= 2
            let crowdedNeighborCount = localCrowding(around: tip, occupiedPositions: occupiedPositions)
            let availableStructuralOpenings = availableStructuralOpeningCount(
                from: tip,
                isHighUp: isHighUp,
                growthStage: growthStage,
                occupiedPositions: occupiedPositions
            )

            let blockType = determineBlockType(
                tip: tip,
                canGrowFoliage: canGrowFoliage,
                isHighUp: isHighUp,
                branchDepth: branchDepth,
                radialDistance: radialDistance,
                straightRunLength: straightRunLength,
                crowdedNeighborCount: crowdedNeighborCount,
                availableStructuralOpenings: availableStructuralOpenings,
                growthStage: growthStage,
                season: season,
                rng: &rng
            )

            let direction = growthDirection(
                from: tip,
                blockType: blockType,
                isHighUp: isHighUp,
                branchDepth: branchDepth,
                radialDistance: radialDistance,
                straightRunLength: straightRunLength,
                growthStage: growthStage,
                rng: &rng,
                pendingInteractions: pendingInteractions
            )

            let newX = tip.x + direction.0
            let newY = tip.y + direction.1
            let newZ = tip.z + direction.2
            let newPosition = PositionKey(x: newX, y: newY, z: newZ)

            if newY >= 0, !occupiedPositions.contains(newPosition) {
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

            remainingTipIndices.removeAll { $0 == selectedTipIndex }
        }

        return nil
    }

    // MARK: - Block Type Determination

    // swiftlint:disable:next function_parameter_count
    private nonisolated static func determineBlockType(
        tip: VoxelBlockData,
        canGrowFoliage: Bool,
        isHighUp: Bool,
        branchDepth: Int,
        radialDistance: Float,
        straightRunLength: Int,
        crowdedNeighborCount: Int,
        availableStructuralOpenings: Int,
        growthStage: TreeBuilder.GrowthStage,
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

        var leafThreshold: Int
        var flowerThreshold: Int
        switch growthStage {
        case .sapling:
            leafThreshold = isHighUp ? 42 : 22
            flowerThreshold = 2
        case .young:
            leafThreshold = isHighUp ? 66 : 42
            flowerThreshold = 4
        case .mature:
            leafThreshold = isHighUp ? 70 : 50
            flowerThreshold = 3
        }

        if growthStage == .mature {
            if branchDepth >= 6 {
                leafThreshold += 10
            }
            if radialDistance >= VoxelConstants.blockSize * 5.5 {
                leafThreshold += 12
                flowerThreshold = max(0, flowerThreshold - 1)
            }
            if straightRunLength >= 3 {
                leafThreshold += 14
                flowerThreshold = 0
            }
            if season == .summer {
                leafThreshold -= isHighUp ? 16 : 10
                flowerThreshold = 0
            }
            if crowdedNeighborCount >= 3 {
                leafThreshold -= 18
                flowerThreshold = 0
            }
            if availableStructuralOpenings <= 1 {
                leafThreshold -= 20
                flowerThreshold = 0
            }
        }

        if availableStructuralOpenings == 0 {
            return .branch
        }

        let adjustedLeafThreshold = max(0, leafThreshold)
        let adjustedFlowerThreshold = max(0, flowerThreshold)

        if isHighUp {
            if season == .spring, roll < adjustedFlowerThreshold {
                return .flower
            } else if roll < adjustedLeafThreshold {
                return .leaf
            } else {
                return .branch
            }
        }

        if season == .spring, roll < adjustedFlowerThreshold {
            return .flower
        }

        if roll < adjustedLeafThreshold {
            return .leaf
        }

        return .branch
    }

    // MARK: - Growth Direction

    // swiftlint:disable:next function_parameter_count
    private nonisolated static func growthDirection(
        from tip: VoxelBlockData,
        blockType: BlockType,
        isHighUp: Bool,
        branchDepth: Int,
        radialDistance: Float,
        straightRunLength: Int,
        growthStage: TreeBuilder.GrowthStage,
        rng: inout SeededRandom,
        pendingInteractions: [InteractionPayload]
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
            weights = foliageDirectionWeights(for: growthStage)
        } else {
            directions = [
                (bs, 0, 0), (-bs, 0, 0),
                (0, 0, bs), (0, 0, -bs),
                (0, bs, 0),
                (bs, -bs, 0), (-bs, -bs, 0),
                (0, -bs, bs), (0, -bs, -bs)
            ]
            weights = structuralDirectionWeights(
                for: growthStage,
                isHighUp: isHighUp,
                tip: tip,
                branchDepth: branchDepth,
                radialDistance: radialDistance,
                straightRunLength: straightRunLength
            )
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

    private nonisolated static func foliageDirectionWeights(for stage: TreeBuilder.GrowthStage) -> [Double] {
        switch stage {
        case .sapling:
            [26.0, 14.0, 14.0, 14.0, 14.0]
        case .young:
            [18.0, 18.0, 18.0, 18.0, 18.0]
        case .mature:
            [9.0, 21.0, 21.0, 21.0, 21.0]
        }
    }

    private nonisolated static func structuralDirectionWeights(
        for stage: TreeBuilder.GrowthStage,
        isHighUp: Bool,
        tip: VoxelBlockData,
        branchDepth: Int,
        radialDistance: Float,
        straightRunLength: Int
    ) -> [Double] {
        let weights: [Double] = switch stage {
        case .sapling:
            [
                15.0, 15.0,
                15.0, 15.0,
                isHighUp || tip.blockType == .trunk ? 18.0 : 28.0,
                2.0, 2.0,
                3.0, 3.0
            ]
        case .young:
            [
                17.0, 17.0,
                17.0, 17.0,
                isHighUp || tip.blockType == .trunk ? 10.0 : 22.0,
                2.0, 2.0,
                3.0, 3.0
            ]
        case .mature:
            [
                18.0, 18.0,
                18.0, 18.0,
                isHighUp || tip.blockType == .trunk ? 11.0 : 18.0,
                1.5, 1.5,
                0.0, 0.0
            ]
        }

        guard stage == .mature else {
            return weights
        }

        var adjustedWeights = weights
        let branchIsExtended = branchDepth >= 6 || radialDistance >= VoxelConstants.blockSize * 5.5

        if branchIsExtended {
            adjustedWeights[0] = 11.0
            adjustedWeights[1] = 11.0
            adjustedWeights[2] = 11.0
            adjustedWeights[3] = 11.0
            adjustedWeights[4] = max(adjustedWeights[4], 12.0)
        }

        if straightRunLength >= 3 {
            adjustedWeights[0] = 8.0
            adjustedWeights[1] = 8.0
            adjustedWeights[2] = 8.0
            adjustedWeights[3] = 8.0
            adjustedWeights[4] = max(adjustedWeights[4], 14.0)
        }

        return adjustedWeights
    }

    private nonisolated static func prioritizedTipIndices(from allBlocks: [VoxelBlockData],
                                                          tipIndices: Set<Int>) -> [Int] {
        let branchTips = tipIndices.filter { allBlocks[$0].blockType == .branch }
        if !branchTips.isEmpty {
            return Array(branchTips)
        }

        let trunkTips = tipIndices.filter { allBlocks[$0].blockType == .trunk }
        return Array(trunkTips)
    }

    nonisolated static func branchDistanceFromTrunk(startingAt index: Int, allBlocks: [VoxelBlockData]) -> Int {
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

    private nonisolated static func localCrowding(
        around block: VoxelBlockData,
        occupiedPositions: Set<PositionKey>
    ) -> Int {
        PositionKey.faceOffsets.reduce(into: 0) { count, offset in
            let neighbor = PositionKey(
                x: block.x + offset.0,
                y: block.y + offset.1,
                z: block.z + offset.2
            )
            if occupiedPositions.contains(neighbor) {
                count += 1
            }
        }
    }

    private nonisolated static func availableStructuralOpeningCount(
        from tip: VoxelBlockData,
        isHighUp: Bool,
        growthStage: TreeBuilder.GrowthStage,
        occupiedPositions: Set<PositionKey>
    ) -> Int {
        let bs = VoxelConstants.blockSize
        let directions: [(Float, Float, Float)] = [
            (bs, 0, 0), (-bs, 0, 0),
            (0, 0, bs), (0, 0, -bs),
            (0, bs, 0),
            (bs, -bs, 0), (-bs, -bs, 0),
            (0, -bs, bs), (0, -bs, -bs)
        ]

        return directions.reduce(into: 0) { count, direction in
            let position = PositionKey(
                x: tip.x + direction.0,
                y: tip.y + direction.1,
                z: tip.z + direction.2
            )
            guard position.y >= 0 else { return }
            guard !occupiedPositions.contains(position) else { return }

            if direction.1 > 0 {
                count += 1
                return
            }

            let weights = structuralDirectionWeights(
                for: growthStage,
                isHighUp: isHighUp,
                tip: tip,
                branchDepth: 0,
                radialDistance: radialDistanceFromCenter(of: tip),
                straightRunLength: 0
            )
            let directionIndex = directions.firstIndex(where: { $0 == direction }) ?? 0
            if weights[directionIndex] > 0 {
                count += 1
            }
        }
    }

    private nonisolated static func radialDistanceFromCenter(of block: VoxelBlockData) -> Float {
        sqrt((block.x * block.x) + (block.z * block.z))
    }

    private nonisolated static func straightRunLength(startingAt index: Int, allBlocks: [VoxelBlockData]) -> Int {
        guard let parentIndex = allBlocks[index].parentIndex else { return 0 }

        let currentDelta = normalizedStructuralDelta(
            from: allBlocks[parentIndex],
            to: allBlocks[index]
        )
        guard currentDelta != (0, 0, 0) else { return 0 }

        var runLength = 1
        var childIndex = parentIndex

        while let grandParentIndex = allBlocks[childIndex].parentIndex {
            let previousDelta = normalizedStructuralDelta(
                from: allBlocks[grandParentIndex],
                to: allBlocks[childIndex]
            )
            guard previousDelta == currentDelta else { break }
            runLength += 1
            childIndex = grandParentIndex
        }

        return runLength
    }

    private nonisolated static func normalizedStructuralDelta(
        from parent: VoxelBlockData,
        to child: VoxelBlockData
    ) -> (Int, Int, Int) {
        let dx = child.x - parent.x
        let dy = child.y - parent.y
        let dz = child.z - parent.z
        let unit = VoxelConstants.blockSize

        func normalize(_ value: Float) -> Int {
            if abs(value) < 0.0001 { return 0 }
            return Int((value / unit).rounded())
        }

        return (normalize(dx), normalize(dy), normalize(dz))
    }

    // MARK: - Color

    private nonisolated static func blockColor(for blockType: BlockType, season: Season,
                                               rng: inout SeededRandom) -> String {
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

// swiftlint:enable type_body_length
