//
//  GrowthEngine+Helpers.swift
//  Kodama
//

import Foundation

extension GrowthEngine {
    // MARK: - Growth Stage

    nonisolated static func growthStage(for nodes: [GrowthNode]) -> TreeBuilder.GrowthStage {
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

    nonisolated static func blocksPerTick(
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

    nonisolated static func structuralTips(in nodes: [GrowthNode]) -> [Int] {
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

    nonisolated static func logicalTouch(from interaction: InteractionPayload?) -> Int3? {
        guard let interaction,
              let x = interaction.touchX,
              let y = interaction.touchY,
              let z = interaction.touchZ
        else { return nil }
        return Int3(x: x, y: y, z: z)
    }

    nonisolated static func shuffledDirections<T>(_ values: [T], rng: inout SeededRandom) -> [T] {
        var copy = values
        guard copy.count > 1 else { return copy }
        for i in 0 ..< (copy.count - 1) {
            let j = i + Int(rng.next() % UInt64(copy.count - i))
            copy.swapAt(i, j)
        }
        return copy
    }

    nonisolated static func cardinalOffsets() -> [Int3] {
        [
            Int3(x: 1, y: 0, z: 0), Int3(x: -1, y: 0, z: 0),
            Int3(x: 0, y: 1, z: 0), Int3(x: 0, y: -1, z: 0),
            Int3(x: 0, y: 0, z: 1), Int3(x: 0, y: 0, z: -1)
        ]
    }

    nonisolated static func manhattanDistance(_ lhs: Int3, _ rhs: Int3) -> Int {
        abs(lhs.x - rhs.x) + abs(lhs.y - rhs.y) + abs(lhs.z - rhs.z)
    }

    // MARK: - Branch Distance

    nonisolated static func branchDistanceFromTrunk(startingAt index: Int, allBlocks: [VoxelBlockData]) -> Int {
        guard index >= 0, index < allBlocks.count else { return 0 }

        var distance = 0
        var currentIndex: Int? = index

        while let resolvedIndex = currentIndex {
            guard resolvedIndex >= 0, resolvedIndex < allBlocks.count else { break }
            let block = allBlocks[resolvedIndex]
            if block.blockType == .trunk { return distance }
            if block.blockType == .branch { distance += 1 }
            guard let parentID = block.parentID else {
                currentIndex = nil
                continue
            }
            currentIndex = allBlocks.firstIndex(where: { $0.id == parentID })
        }

        return distance
    }
}
