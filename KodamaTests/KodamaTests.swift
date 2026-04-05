//
//  KodamaTests.swift
//  KodamaTests
//

import Foundation
@testable import Kodama
import SceneKit
import Testing

struct KodamaTests {
    @Test func interactionTouchCoordinatesUseIntegers() {
        let interaction = Interaction(type: .touch, touchX: 2, touchY: -1, touchZ: 5)

        #expect(interaction.touchX == 2)
        #expect(interaction.touchY == -1)
        #expect(interaction.touchZ == 5)
    }

    @Test func growthLongRunDoesNotStallAndRespectsUpperBound() {
        let tree = BonsaiTree(seed: 42)
        let initial = TreeBuilder.buildSapling(seed: 42)
        tree.totalBlocks = initial.count

        let start = makeDate(year: 2026, month: 1, day: 1)
        let end = makeDate(year: 2026, month: 7, day: 1)

        let result = GrowthEngine.calculateGrowth(
            tree: tree,
            existingBlocks: initial,
            since: start,
            currentDate: end,
            maxElapsedHours: 24 * 180
        )

        #expect(!result.newBlocks.isEmpty)
        #expect(initial.count + result.newBlocks.count <= VoxelConstants.maxBlocks)
    }

    @Test func growthHasNoDuplicatePositions() {
        let tree = BonsaiTree(seed: 77)
        let initial = TreeBuilder.buildSapling(seed: 77)
        tree.totalBlocks = initial.count

        let start = makeDate(year: 2026, month: 4, day: 1)
        let end = makeDate(year: 2026, month: 5, day: 1)

        let result = GrowthEngine.calculateGrowthWithSeasons(
            tree: tree,
            existingBlocks: initial,
            since: start,
            currentDate: end,
            maxElapsedHours: 24 * 30
        )

        // Exclude foliage blocks evicted by branch-over-foliage replacement
        let evictedIDs = Set(result.removedBlockIDs)
        let all = initial.filter { !evictedIDs.contains($0.id) }
            + result.newBlocks
            + result.seasonalEffects.newSnowBlocks
            + result.seasonalEffects.newMossBlocks
        var positions = Set<Int3>()

        for block in all {
            let pos = GridMapper.int3(from: block)
            #expect(!positions.contains(pos), "duplicate position \(pos) for \(block.blockType)")
            positions.insert(pos)
        }
    }

    @Test func noFoliageOverlapsBranchAfterFullGrowth() {
        let tree = BonsaiTree(seed: 42)
        let initial = TreeBuilder.buildSapling(seed: 42)
        tree.totalBlocks = initial.count

        let start = makeDate(year: 2026, month: 1, day: 1)
        let end = makeDate(year: 2027, month: 1, day: 1)

        let result = GrowthEngine.calculateGrowthWithSeasons(
            tree: tree,
            existingBlocks: initial,
            since: start,
            currentDate: end,
            maxElapsedHours: 24 * 365
        )

        // Exclude foliage blocks evicted by branch-over-foliage replacement
        let evictedIDs = Set(result.removedBlockIDs)
        let all = initial.filter { !evictedIDs.contains($0.id) }
            + result.newBlocks
            + result.seasonalEffects.newSnowBlocks
            + result.seasonalEffects.newMossBlocks
        var woodPositions = Set<Int3>()
        for block in all where GridMapper.layer(for: block.blockType) == .wood {
            woodPositions.insert(block.pos)
        }
        for block in all where GridMapper.layer(for: block.blockType) == .foliage {
            #expect(
                !woodPositions.contains(block.pos),
                "foliage \(block.blockType) at \(block.pos) overlaps branch/trunk"
            )
        }
    }

    @Test func newLeafDoesNotOverlapExistingBranch() {
        let tree = BonsaiTree(seed: 123)
        let initial = TreeBuilder.buildSapling(seed: 123)
        tree.totalBlocks = initial.count

        let start = makeDate(year: 2026, month: 3, day: 1)
        let end = makeDate(year: 2026, month: 9, day: 1)

        let result = GrowthEngine.calculateGrowth(
            tree: tree,
            existingBlocks: initial,
            since: start,
            currentDate: end,
            maxElapsedHours: 24 * 180
        )

        // Build the full picture: existing (minus evicted) + newly grown
        let evictedIDs = Set(result.removedBlockIDs)
        let all = initial.filter { !evictedIDs.contains($0.id) } + result.newBlocks
        var woodPositions = Set<Int3>()
        for block in all where GridMapper.layer(for: block.blockType) == .wood {
            woodPositions.insert(block.pos)
        }
        let newFoliage = result.newBlocks.filter { GridMapper.layer(for: $0.blockType) == .foliage }
        for block in newFoliage {
            #expect(
                !woodPositions.contains(block.pos),
                "new leaf/foliage placed on top of existing branch at \(block.pos)"
            )
        }
    }

    @Test func growthParentReferenceIsAlwaysValidAndAcyclic() {
        let tree = BonsaiTree(seed: 123)
        let initial = TreeBuilder.buildSapling(seed: 123)
        tree.totalBlocks = initial.count

        let start = makeDate(year: 2026, month: 3, day: 1)
        let end = makeDate(year: 2026, month: 8, day: 1)

        let result = GrowthEngine.calculateGrowth(
            tree: tree,
            existingBlocks: initial,
            since: start,
            currentDate: end,
            maxElapsedHours: 24 * 153
        )

        let evictedIDs = Set(result.removedBlockIDs)
        let all = initial.filter { !evictedIDs.contains($0.id) } + result.newBlocks

        for (index, block) in all.enumerated() {
            guard let parentID = block.parentID else { continue }
            let parentIndex = all.firstIndex(where: { $0.id == parentID })
            #expect(parentIndex != nil)
            #expect(parentIndex != index)

            var visited = Set<Int>()
            var cursor: Int? = index
            var hops = 0
            while let current = cursor {
                #expect(current >= 0)
                #expect(current < all.count)
                #expect(!visited.contains(current))
                visited.insert(current)
                if let nextParentID = all[current].parentID {
                    cursor = all.firstIndex(where: { $0.id == nextParentID })
                } else {
                    cursor = nil
                }
                hops += 1
                #expect(hops <= all.count)
            }
        }
    }

    @Test func trunkBranchAndFoliageAllAppearOverTime() {
        let tree = BonsaiTree(seed: 999)
        let initial = TreeBuilder.buildSapling(seed: 999)
        tree.totalBlocks = initial.count

        let start = makeDate(year: 2026, month: 4, day: 1)
        let end = makeDate(year: 2026, month: 7, day: 1)

        let result = GrowthEngine.calculateGrowth(
            tree: tree,
            existingBlocks: initial,
            since: start,
            currentDate: end,
            maxElapsedHours: 24 * 91
        )

        let evictedIDs = Set(result.removedBlockIDs)
        let all = initial.filter { !evictedIDs.contains($0.id) } + result.newBlocks
        #expect(all.contains { $0.blockType == .trunk })
        #expect(all.contains { $0.blockType == .branch })
        #expect(all.contains { $0.blockType == .leaf || $0.blockType == .flower })
    }

    @Test func rendererAppliesRenderScaleOnlyAtSceneBuildTime() throws {
        let blocks = [
            VoxelBlockData(pos: Int3(x: 2, y: 4, z: -3), blockType: .trunk, colorHex: "#4A3520", parentID: nil)
        ]

        let root = TreeBuilder.buildSCNNodes(from: blocks)
        let node = try #require(root.childNodes.first)

        let tolerance: Float = 1e-5
        #expect(abs(node.position.x - Float(blocks[0].pos.x) * VoxelConstants.renderScale) < tolerance)
        #expect(abs(node.position.y - Float(blocks[0].pos.y) * VoxelConstants.renderScale) < tolerance)
        #expect(abs(node.position.z - Float(blocks[0].pos.z) * VoxelConstants.renderScale) < tolerance)
    }
}


private func makeDate(year: Int, month: Int, day: Int) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.year = year
    components.month = month
    components.day = day
    components.hour = 12
    components.minute = 0
    components.second = 0
    return components.date ?? Date(timeIntervalSince1970: 0)
}
