//
//  KodamaTests.swift
//  KodamaTests
//

import Foundation
import SceneKit
import Testing
@testable import Kodama

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

        let newBlocks = GrowthEngine.calculateGrowth(
            tree: tree,
            existingBlocks: initial,
            since: start,
            currentDate: end,
            maxElapsedHours: 24 * 180
        )

        #expect(!newBlocks.isEmpty)
        #expect(initial.count + newBlocks.count <= VoxelConstants.maxBlocks)
    }

    @Test func growthHasNoDuplicateCellsPerLayer() {
        let tree = BonsaiTree(seed: 77)
        let initial = TreeBuilder.buildSapling(seed: 77)
        tree.totalBlocks = initial.count

        let start = makeDate(year: 2026, month: 4, day: 1)
        let end = makeDate(year: 2026, month: 5, day: 1)

        let newBlocks = GrowthEngine.calculateGrowth(
            tree: tree,
            existingBlocks: initial,
            since: start,
            currentDate: end,
            maxElapsedHours: 24 * 30
        )

        let all = initial + newBlocks
        var keys = Set<LayerPositionKey>()

        for block in all {
            let key = LayerPositionKey(
                layer: GridMapper.layer(for: block.blockType),
                pos: GridMapper.int3(from: block)
            )
            #expect(!keys.contains(key))
            keys.insert(key)
        }
    }

    @Test func growthParentReferenceIsAlwaysValidAndAcyclic() {
        let tree = BonsaiTree(seed: 123)
        let initial = TreeBuilder.buildSapling(seed: 123)
        tree.totalBlocks = initial.count

        let start = makeDate(year: 2026, month: 3, day: 1)
        let end = makeDate(year: 2026, month: 8, day: 1)

        let newBlocks = GrowthEngine.calculateGrowth(
            tree: tree,
            existingBlocks: initial,
            since: start,
            currentDate: end,
            maxElapsedHours: 24 * 153
        )

        let all = initial + newBlocks

        for (index, block) in all.enumerated() {
            guard let parentID = block.parentID else { continue }
            let parentIndex = all.firstIndex(where: { $0.id == parentID })
            #expect(parentIndex != nil)
            #expect(parentIndex != index)

            var visited = Set<Int>()
            var cursor: Int? = index
            var hops = 0
            while let c = cursor {
                #expect(c >= 0)
                #expect(c < all.count)
                #expect(!visited.contains(c))
                visited.insert(c)
                if let nextParentID = all[c].parentID {
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

        let newBlocks = GrowthEngine.calculateGrowth(
            tree: tree,
            existingBlocks: initial,
            since: start,
            currentDate: end,
            maxElapsedHours: 24 * 91
        )

        let all = initial + newBlocks
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

        #expect(node.position.x == Float(blocks[0].pos.x) * VoxelConstants.renderScale)
        #expect(node.position.y == Float(blocks[0].pos.y) * VoxelConstants.renderScale)
        #expect(node.position.z == Float(blocks[0].pos.z) * VoxelConstants.renderScale)
    }
}

private struct LayerPositionKey: Hashable {
    let layer: GridLayer
    let pos: Int3
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
