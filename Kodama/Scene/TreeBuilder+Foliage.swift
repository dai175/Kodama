//
//  TreeBuilder+Foliage.swift
//  Kodama
//

import Foundation

// MARK: - Foliage Building

extension TreeBuilder {
    nonisolated static func buildBranchLeaves(
        context: inout BuildContext,
        topIndex: Int,
        branchDirection: Int3,
        density: FoliageDensity,
        profile: StageProfile
    ) {
        addIntermediateFoliage(
            around: topIndex,
            branchDirection: branchDirection,
            context: &context,
            density: density,
            upwardBias: true,
            isTerminal: true,
            profile: profile
        )
    }

    // swiftlint:disable:next function_parameter_count function_body_length
    nonisolated static func addIntermediateFoliage(
        around index: Int,
        branchDirection: Int3,
        context: inout BuildContext,
        density: FoliageDensity,
        upwardBias: Bool,
        isTerminal: Bool,
        profile: StageProfile
    ) {
        let anchor = context.blocks[index]
        let lateralDirection = Int3(x: -branchDirection.z, y: 0, z: branchDirection.x)

        if density == .barelyThere, !isTerminal {
            return
        }
        if density == .sparse, !isTerminal, !context.rng.next().isMultiple(of: 5) {
            return
        }

        var candidateOffsets: [Int3] = [
            Int3(x: 0, y: 1, z: 0),
            Int3(x: branchDirection.x, y: 0, z: branchDirection.z),
            Int3(x: lateralDirection.x, y: 0, z: lateralDirection.z),
            Int3(x: -lateralDirection.x, y: 0, z: -lateralDirection.z),
            Int3(x: -branchDirection.x, y: 0, z: -branchDirection.z)
        ]
        if upwardBias {
            let upwardOffsets: [Int3] = [
                Int3(x: 0, y: 1, z: 0),
                Int3(x: branchDirection.x, y: 0, z: branchDirection.z),
                Int3(x: lateralDirection.x, y: 0, z: lateralDirection.z)
            ]
            candidateOffsets.append(contentsOf: upwardOffsets)
        }
        if isTerminal {
            let terminalOffsets: [Int3] = [
                Int3(x: branchDirection.x, y: 1, z: branchDirection.z),
                Int3(x: lateralDirection.x, y: 1, z: lateralDirection.z),
                Int3(x: -lateralDirection.x, y: 1, z: -lateralDirection.z)
            ]
            candidateOffsets.append(contentsOf: terminalOffsets)
        }
        if profile.prefersOuterCanopy {
            candidateOffsets.removeAll { offset in
                offset.x == -branchDirection.x && offset.z == -branchDirection.z && offset.y == 0
            }
        }
        let clusterSize = if isTerminal {
            switch density {
            case .lush:
                4
            case .medium:
                2 + Int(context.rng.next() % 2)
            case .sparse:
                2
            case .barelyThere:
                1
            }
        } else if upwardBias {
            density == .medium || density == .lush ? 1 + Int(context.rng.next() % 2) : 1
        } else {
            1
        }

        let orderedOffsets = orderedFoliageOffsets(
            candidateOffsets,
            prefersOuterCanopy: profile.prefersOuterCanopy,
            using: &context.rng
        )
        let filteredOffsets = applyCanopyOpenSlots(
            to: orderedOffsets,
            openSlots: isTerminal ? profile.canopyOpenSlots : min(profile.canopyOpenSlots, 1),
            using: &context.rng
        )

        for offset in filteredOffsets.prefix(clusterSize) {
            let leafColor = leafColors[Int(context.rng.next() % UInt64(leafColors.count))]
            let adjustedOffset = liftedCanopyOffset(
                from: offset,
                shouldLift: profile.canopyLiftChance > 0 && context.rng.next() % profile.canopyLiftChance == 0,
                prefersOuterCanopy: profile.prefersOuterCanopy
            )
            let block = VoxelBlockData(
                pos: anchor.pos.adding(adjustedOffset),
                blockType: .leaf,
                colorHex: leafColor,
                parentID: anchor.id
            )
            _ = insert(block, into: &context.blocks, occupiedPositions: &context.occupiedPositions)
        }
    }

    nonisolated static func buildCrownLeaf(
        context: inout BuildContext,
        topIndex: Int,
        density: FoliageDensity
    ) {
        let crownProfile = stageProfile(for: .sapling)
        buildBranchLeaves(
            context: &context,
            topIndex: topIndex,
            branchDirection: Int3(x: 0, y: 0, z: 1),
            density: density,
            profile: crownProfile
        )
    }

    nonisolated private static func orderedFoliageOffsets(
        _ offsets: [Int3],
        prefersOuterCanopy: Bool,
        using rng: inout SeededRandom
    ) -> [Int3] {
        let shuffled = offsets.shuffled(using: &rng)
        guard prefersOuterCanopy else { return shuffled }

        return shuffled.sorted { lhs, rhs in
            canopyPriority(of: lhs) > canopyPriority(of: rhs)
        }
    }

    nonisolated private static func applyCanopyOpenSlots(
        to offsets: [Int3],
        openSlots: Int,
        using rng: inout SeededRandom
    ) -> [Int3] {
        guard openSlots > 0, offsets.count > 3 else { return offsets }

        var filteredOffsets = offsets
        for _ in 0 ..< openSlots where filteredOffsets.count > 3 {
            let removeIndex = 1 + Int(rng.next() % UInt64(filteredOffsets.count - 1))
            filteredOffsets.remove(at: removeIndex)
        }
        return filteredOffsets
    }

    nonisolated private static func liftedCanopyOffset(
        from offset: Int3,
        shouldLift: Bool,
        prefersOuterCanopy: Bool
    ) -> Int3 {
        guard shouldLift else { return offset }
        guard prefersOuterCanopy || offset.y == 0 else { return offset }
        return Int3(x: offset.x, y: max(offset.y, 1), z: offset.z)
    }

    nonisolated private static func canopyPriority(of offset: Int3) -> Int {
        var score = 0
        if offset.y > 0 { score += 3 }
        if abs(offset.x) + abs(offset.z) > 0 { score += 2 }
        if offset.x != 0, offset.z != 0 { score += 1 }
        return score
    }
}
