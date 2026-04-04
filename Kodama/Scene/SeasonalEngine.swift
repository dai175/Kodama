//
//  SeasonalEngine.swift
//  Kodama
//

import Foundation

// MARK: - SeasonalResult

struct SeasonalResult {
    var colorChanges: [(blockIndex: Int, newColor: String)]
    var fallenLeaves: Set<Int>
    var newSnowBlocks: [VoxelBlockData]
    var removedSnow: Set<Int>
    var newMossBlocks: [VoxelBlockData]
    var expiredFlowers: Set<Int>

    static let empty = SeasonalResult(
        colorChanges: [],
        fallenLeaves: [],
        newSnowBlocks: [],
        removedSnow: [],
        newMossBlocks: [],
        expiredFlowers: []
    )
}

// MARK: - SeasonalEngine

enum SeasonalEngine {
    // MARK: - Color Palettes

    static let springLeafColors = ["#7AB648", "#5A9E3A", "#8BC96A"]
    static let springFlowerColor = "#E8A0BF"
    static let summerLeafColors = ["#2D5A1E", "#3E7A2A"]
    static let summerMossColor = "#2A4A1E"
    static let snowColor = "#E8E4DC"

    /// Autumn transition sequence: green -> yellow-green -> yellow -> orange -> red -> brown
    static let autumnSequence = [
        "#7AB648", // green
        "#A8C44A", // yellow-green
        "#D4C830", // yellow
        "#E8A020", // orange
        "#CC4422", // red
        "#8B6914" // brown
    ]

    // MARK: - Leaf Color

    /// Returns an appropriate leaf color for the given season, optionally blending with a user color.
    static func leafColor(for season: Season, rng: inout SeededRandom, userColor: String? = nil) -> String {
        let baseColor: String = switch season {
        case .spring:
            springLeafColors[Int(rng.next() % UInt64(springLeafColors.count))]
        case .summer:
            summerLeafColors[Int(rng.next() % UInt64(summerLeafColors.count))]
        case .autumn:
            autumnSequence[0] // New leaves in autumn start green
        case .winter:
            TreeBuilder.leafColors[Int(rng.next() % UInt64(TreeBuilder.leafColors.count))]
        }

        if let userColor {
            return blendColors(base: baseColor, overlay: userColor, factor: 0.2)
        }
        return baseColor
    }

    // MARK: - Seasonal Effects

    /// Applies seasonal effects to existing blocks, returning changes to be applied.
    static func applySeasonalEffects(
        to blocks: [VoxelBlockData],
        season: Season,
        rng: inout SeededRandom,
        elapsedDays: Int,
        blockDates: [Date?] = []
    ) -> SeasonalResult {
        var result = SeasonalResult.empty

        switch season {
        case .spring:
            applySpringEffects(to: blocks, result: &result)
        case .summer:
            applySummerEffects(to: blocks, rng: &rng, elapsedDays: elapsedDays, result: &result)
        case .autumn:
            applyAutumnEffects(to: blocks, rng: &rng, result: &result, blockDates: blockDates)
        case .winter:
            applyWinterEffects(to: blocks, rng: &rng, elapsedDays: elapsedDays, result: &result)
        }

        // Expire flowers older than 14 days regardless of season
        expireOldFlowers(blocks: blocks, blockDates: blockDates, maxDays: 14, result: &result)

        return result
    }

    // MARK: - Color Blending

    /// Blends two hex colors with a given factor (0 = all base, 1 = all overlay).
    static func blendColors(base: String, overlay: String, factor: Float) -> String {
        let (bR, bG, bB) = hexToRGB(base)
        let (oR, oG, oB) = hexToRGB(overlay)

        let r = Int(Float(bR) * (1 - factor) + Float(oR) * factor)
        let g = Int(Float(bG) * (1 - factor) + Float(oG) * factor)
        let b = Int(Float(bB) * (1 - factor) + Float(oB) * factor)

        return rgbToHex(r: min(255, max(0, r)), g: min(255, max(0, g)), b: min(255, max(0, b)))
    }

    // MARK: - Autumn Color Progression

    /// Returns the next color in the autumn transition sequence, or nil if already brown.
    static func autumnColorProgression(currentHex: String) -> String? {
        let normalized = currentHex.uppercased()
        guard let index = autumnSequence.firstIndex(where: { $0.uppercased() == normalized }) else {
            // If not in sequence, check if it's a leaf-like green and start transitioning
            let (r, g, b) = hexToRGB(currentHex)
            if g > r, g > b {
                return autumnSequence[1] // Start transitioning green leaves
            }
            return nil
        }
        let nextIndex = index + 1
        guard nextIndex < autumnSequence.count else { return nil }
        return autumnSequence[nextIndex]
    }

    // MARK: - Private

    private static func applySpringEffects(
        to blocks: [VoxelBlockData],
        result: inout SeasonalResult
    ) {
        // Remove snow blocks in spring
        for (index, block) in blocks.enumerated() where block.blockType == .snow {
            result.removedSnow.insert(index)
        }
    }

    private static func applySummerEffects(
        to blocks: [VoxelBlockData],
        rng: inout SeededRandom,
        elapsedDays: Int,
        result: inout SeasonalResult
    ) {
        // Add moss on trunk base blocks (1 per week)
        let mossCount = max(1, elapsedDays / 7)
        let trunkBaseBlocks = blocks.enumerated()
            .filter { $0.element.blockType == .trunk && $0.element.y <= VoxelConstants.blockSize }

        guard !trunkBaseBlocks.isEmpty else { return }

        for _ in 0 ..< mossCount {
            let (_, trunkBlock) = trunkBaseBlocks[Int(rng.next() % UInt64(trunkBaseBlocks.count))]

            // Place moss adjacent to trunk base
            let offsets: [(Float, Float)] = [
                (VoxelConstants.blockSize, 0), (-VoxelConstants.blockSize, 0),
                (0, VoxelConstants.blockSize), (0, -VoxelConstants.blockSize)
            ]
            let offset = offsets[Int(rng.next() % UInt64(offsets.count))]
            let mossX = trunkBlock.x + offset.0
            let mossZ = trunkBlock.z + offset.1

            // Check no block already exists there (including blocks added in this pass)
            let alreadyExists = blocks.contains(where: { $0.overlaps(x: mossX, y: trunkBlock.y, z: mossZ) })
                || result.newMossBlocks.contains(where: { $0.overlaps(x: mossX, y: trunkBlock.y, z: mossZ) })
            if !alreadyExists {
                result.newMossBlocks.append(VoxelBlockData(
                    x: mossX,
                    y: trunkBlock.y,
                    z: mossZ,
                    blockType: .moss,
                    colorHex: summerMossColor,
                    parentIndex: nil
                ))
            }
        }
    }

    private static func applyAutumnEffects(
        to blocks: [VoxelBlockData],
        rng: inout SeededRandom,
        result: inout SeasonalResult,
        blockDates: [Date?]
    ) {
        transitionLeafColors(blocks: blocks, rng: &rng, result: &result)
        cleanupGroundLeaves(blocks: blocks, blockDates: blockDates, maxDays: 7, result: &result)
    }

    private static func transitionLeafColors(
        blocks: [VoxelBlockData],
        rng: inout SeededRandom,
        result: inout SeasonalResult
    ) {
        let leafIndices = blocks.indices.filter { blocks[$0].blockType == .leaf }
        guard !leafIndices.isEmpty else { return }

        let transitionCount = min(leafIndices.count, Int(rng.next() % 4) + 2) // 2-5
        var shuffled = leafIndices

        for i in 0 ..< min(transitionCount, shuffled.count) {
            let j = i + Int(rng.next() % UInt64(shuffled.count - i))
            shuffled.swapAt(i, j)
        }

        for i in 0 ..< min(transitionCount, shuffled.count) {
            let blockIndex = shuffled[i]
            let currentColor = blocks[blockIndex].colorHex

            if let nextColor = autumnColorProgression(currentHex: currentColor) {
                result.colorChanges.append((blockIndex: blockIndex, newColor: nextColor))
            } else if currentColor.uppercased() == "#8B6914", rng.next() % 100 < 30 {
                result.fallenLeaves.insert(blockIndex)
            }
        }
    }

    private static func cleanupGroundLeaves(
        blocks: [VoxelBlockData],
        blockDates: [Date?],
        maxDays: Int,
        result: inout SeasonalResult
    ) {
        let now = Date()
        for (index, block) in blocks.enumerated()
            where block.blockType == .leaf && abs(block.y) < VoxelConstants.halfBlock {
            guard index < blockDates.count, let placedAt = blockDates[index] else { continue }
            let daysSincePlaced = Calendar.current.dateComponents([.day], from: placedAt, to: now).day ?? 0
            guard daysSincePlaced > maxDays, !result.fallenLeaves.contains(index) else { continue }
            result.fallenLeaves.insert(index)
        }
    }

    private static func expireOldFlowers(
        blocks: [VoxelBlockData],
        blockDates: [Date?],
        maxDays: Int,
        result: inout SeasonalResult
    ) {
        let now = Date()
        for (index, block) in blocks.enumerated() where block.blockType == .flower {
            guard index < blockDates.count, let placedAt = blockDates[index] else { continue }
            let daysSincePlaced = Calendar.current.dateComponents([.day], from: placedAt, to: now).day ?? 0
            guard daysSincePlaced > maxDays else { continue }
            result.expiredFlowers.insert(index)
        }
    }

    private static func applyWinterEffects(
        to blocks: [VoxelBlockData],
        rng: inout SeededRandom,
        elapsedDays: Int,
        result: inout SeasonalResult
    ) {
        // Remaining leaves fall (20% chance per tick)
        for index in blocks.indices where blocks[index].blockType == .leaf {
            guard rng.next() % 100 < 20 else { continue }
            result.fallenLeaves.insert(index)
        }

        // Add snow on top surfaces (1-3 per day, scaled by elapsed days)
        let perDay = Int(rng.next() % 3) + 1 // 1-3 per day
        let snowCount = min(perDay * max(1, elapsedDays), 20)

        // Find topmost block at each (x, z) position
        var topBlocks: [String: (index: Int, block: VoxelBlockData)] = [:]
        for (index, block) in blocks.enumerated()
            where block.blockType != .snow && !result.fallenLeaves.contains(index) {
            let key = "\(block.x),\(block.z)"
            if let existing = topBlocks[key] {
                if block.y > existing.block.y {
                    topBlocks[key] = (index, block)
                }
            } else {
                topBlocks[key] = (index, block)
            }
        }

        let topEntries = Array(topBlocks.values)
        guard !topEntries.isEmpty else { return }

        for _ in 0 ..< snowCount {
            let entry = topEntries[Int(rng.next() % UInt64(topEntries.count))]
            let snowY = entry.block.y + VoxelConstants.blockSize

            // Check no snow block already exists at this position (including blocks added in this pass)
            let alreadyHasSnow = blocks.contains { b in
                b.blockType == .snow && b.overlaps(x: entry.block.x, y: snowY, z: entry.block.z)
            } || result.newSnowBlocks.contains { b in
                b.overlaps(x: entry.block.x, y: snowY, z: entry.block.z)
            }

            if !alreadyHasSnow {
                result.newSnowBlocks.append(VoxelBlockData(
                    x: entry.block.x,
                    y: snowY,
                    z: entry.block.z,
                    blockType: .snow,
                    colorHex: snowColor,
                    parentIndex: entry.index
                ))
            }
        }
    }

    // MARK: - Hex Color Utilities

    private static func hexToRGB(_ hex: String) -> (Int, Int, Int) {
        let hexString = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard hexString.count == 6,
              hexString.allSatisfy(\.isHexDigit),
              let hexNumber = UInt64(hexString, radix: 16)
        else {
            assertionFailure("Invalid hex color string: \(hexString)")
            return (0, 0, 0)
        }
        let r = Int((hexNumber & 0xFF0000) >> 16)
        let g = Int((hexNumber & 0x00FF00) >> 8)
        let b = Int(hexNumber & 0x0000FF)
        return (r, g, b)
    }

    private static func rgbToHex(r: Int, g: Int, b: Int) -> String {
        String(format: "#%02X%02X%02X", r, g, b)
    }
}
