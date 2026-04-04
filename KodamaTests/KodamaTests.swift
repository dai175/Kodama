//
//  KodamaTests.swift
//  KodamaTests
//
//  Created by Daisuke Ooba on 2026/04/02.
//

import Foundation
import Testing
@testable import Kodama

struct KodamaTests {
    @Test func saplingGenerationProducesShapedNonOverlappingSeedlings() {
        for seed in 1 ... 8 {
            let blocks = TreeBuilder.buildSapling(seed: UInt64(seed))
            let trunkBlocks = blocks.filter { $0.blockType == .trunk }
            let branchBlocks = blocks.filter { $0.blockType == .branch }
            let foliageBlocks = blocks.filter { $0.blockType == .leaf || $0.blockType == .flower }
            let branchParentIndices = Set(branchBlocks.compactMap(\.parentIndex))
            let foliageParentIndices = Set(foliageBlocks.compactMap(\.parentIndex))
            let branchParents = foliageParentIndices.compactMap { parentIndex in
                blocks.indices.contains(parentIndex) ? blocks[parentIndex] : nil
            }
            let branchVectors = branchBlocks.compactMap { block -> (Float, Float, Float)? in
                guard let parentIndex = block.parentIndex, blocks.indices.contains(parentIndex) else { return nil }
                let parent = blocks[parentIndex]
                return (block.x - parent.x, block.y - parent.y, block.z - parent.z)
            }
            let foliageVectors = foliageBlocks.compactMap { block -> (Float, Float, Float)? in
                guard let parentIndex = block.parentIndex, blocks.indices.contains(parentIndex) else { return nil }
                let parent = blocks[parentIndex]
                return (block.x - parent.x, block.y - parent.y, block.z - parent.z)
            }

            #expect((6 ... 8).contains(trunkBlocks.count))
            #expect(branchBlocks.count >= 6)
            #expect(foliageBlocks.count >= 10)
            #expect(Set(blocks.map(\.positionKey)).count == blocks.count)
            #expect(foliageParentIndices.intersection(branchParentIndices).count >= 2)
            #expect(Set(trunkBlocks.map(\.x)).count > 1 || Set(trunkBlocks.map(\.z)).count > 1)
            #expect(branchVectors.allSatisfy(isFaceAdjacent))
            #expect(foliageVectors.allSatisfy(isFaceAdjacent))
            #expect(branchVectors.contains { $0.1 > 0 })
            #expect(branchVectors.contains { abs($0.0) > 0 || abs($0.2) > 0 })
            #expect(branchParents.contains { branchParent in
                guard let parentIndex = branchParent.parentIndex,
                      blocks.indices.contains(parentIndex)
                else { return false }
                return blocks[parentIndex].blockType == .branch
            })
        }
    }

    @Test func springGrowthRemainsSlowOverOneDay() {
        let start = makeDate(year: 2026, month: 4, day: 1)
        let end = makeDate(year: 2026, month: 4, day: 2)
        let tree = BonsaiTree(seed: 42)
        let blocks = TreeBuilder.buildSapling(seed: 42)
        tree.totalBlocks = blocks.count

        let newBlocks = GrowthEngine.calculateGrowth(
            tree: tree,
            existingBlocks: blocks,
            since: start,
            currentDate: end,
            maxElapsedHours: 48
        )

        #expect(!newBlocks.isEmpty)
        #expect(newBlocks.count <= 8)
    }

    @Test func growthStageClassifiesSaplingYoungAndMatureStructures() {
        let saplingBlocks = TreeBuilder.buildSapling(seed: 11)
        let youngBlocks = makeYoungTree()
        let matureBlocks = makeMatureTree()

        #expect(TreeBuilder.growthStage(for: saplingBlocks) == .sapling)
        #expect(TreeBuilder.growthStage(for: youngBlocks) == .young)
        #expect(TreeBuilder.growthStage(for: matureBlocks) == .mature)
    }

    @Test func springGrowthAddsDenserFoliageOnMatureTreesThanSaplings() {
        let start = makeDate(year: 2026, month: 4, day: 1)
        let end = makeDate(year: 2026, month: 4, day: 21)

        let sapling = TreeBuilder.buildSapling(seed: 21)
        let mature = makeMatureTree()

        let saplingTree = BonsaiTree(seed: 21)
        saplingTree.totalBlocks = sapling.count
        let matureTree = BonsaiTree(seed: 21)
        matureTree.totalBlocks = mature.count

        let saplingGrowth = GrowthEngine.calculateGrowth(
            tree: saplingTree,
            existingBlocks: sapling,
            since: start,
            currentDate: end,
            maxElapsedHours: 24 * 21
        )
        let matureGrowth = GrowthEngine.calculateGrowth(
            tree: matureTree,
            existingBlocks: mature,
            since: start,
            currentDate: end,
            maxElapsedHours: 24 * 21
        )

        let saplingFoliage = saplingGrowth.filter { $0.blockType == .leaf || $0.blockType == .flower }.count
        let matureFoliage = matureGrowth.filter { $0.blockType == .leaf || $0.blockType == .flower }.count
        let saplingOuterSpread = averageRadialSpread(of: saplingGrowth)
        let matureOuterSpread = averageRadialSpread(of: matureGrowth)

        #expect(!saplingGrowth.isEmpty)
        #expect(!matureGrowth.isEmpty)
        #expect(matureFoliage > saplingFoliage)
        #expect(matureOuterSpread > saplingOuterSpread)
    }

    @Test func growthStartsFromBranchTipsWhenBranchesExist() {
        let start = makeDate(year: 2026, month: 4, day: 1)
        let end = makeDate(year: 2026, month: 4, day: 4)
        let tree = BonsaiTree(seed: 7)
        let blocks = makeBranchingTree()
        tree.totalBlocks = blocks.count

        let newBlocks = GrowthEngine.calculateGrowth(
            tree: tree,
            existingBlocks: blocks,
            since: start,
            currentDate: end,
            maxElapsedHours: 96
        )

        #expect(!newBlocks.isEmpty)
        for block in newBlocks {
            guard let parentIndex = block.parentIndex else {
                Issue.record("Expected all grown blocks to have a parent")
                continue
            }
            let parent = (blocks + newBlocks)[parentIndex]
            #expect(parent.blockType == .branch)
        }
    }

    @Test func foliageOnlyAppearsOnOuterBranchTips() {
        let start = makeDate(year: 2026, month: 4, day: 1)
        let end = makeDate(year: 2026, month: 4, day: 14)
        let tree = BonsaiTree(seed: 99)
        let blocks = makeBranchingTree()
        tree.totalBlocks = blocks.count

        let newBlocks = GrowthEngine.calculateGrowth(
            tree: tree,
            existingBlocks: blocks,
            since: start,
            currentDate: end,
            maxElapsedHours: 24 * 14
        )
        let allBlocks = blocks + newBlocks
        let foliage = newBlocks.filter { $0.blockType == .leaf || $0.blockType == .flower }

        #expect(!foliage.isEmpty)

        for block in foliage {
            guard let parentIndex = block.parentIndex else {
                Issue.record("Expected foliage to attach to a parent branch")
                continue
            }
            let parent = allBlocks[parentIndex]
            #expect(parent.blockType == .branch)
            #expect(GrowthEngine.branchDistanceFromTrunk(startingAt: parentIndex, allBlocks: allBlocks) >= 2)
            #expect(block.y >= parent.y)
        }
    }
}

private func makeDate(year: Int, month: Int, day: Int) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.year = year
    components.month = month
    components.day = day
    components.hour = 12
    return components.date!
}

private func makeBranchingTree() -> [VoxelBlockData] {
    let bs = VoxelConstants.blockSize
    return [
        VoxelBlockData(x: 0, y: 0, z: 0, blockType: .trunk, colorHex: "#4A3520", parentIndex: nil),
        VoxelBlockData(x: 0, y: bs, z: 0, blockType: .trunk, colorHex: "#4A3520", parentIndex: 0),
        VoxelBlockData(x: 0, y: bs * 2, z: 0, blockType: .trunk, colorHex: "#4A3520", parentIndex: 1),
        VoxelBlockData(x: bs, y: bs, z: 0, blockType: .branch, colorHex: "#5A4530", parentIndex: 1),
        VoxelBlockData(x: bs * 2, y: bs, z: 0, blockType: .branch, colorHex: "#5A4530", parentIndex: 3)
    ]
}

private func makeYoungTree() -> [VoxelBlockData] {
    var blocks: [VoxelBlockData] = []
    let bs = VoxelConstants.blockSize

    blocks.append(VoxelBlockData(x: 0, y: 0, z: 0, blockType: .trunk, colorHex: "#4A3520", parentIndex: nil))
    for level in 1 ... 5 {
        blocks.append(
            VoxelBlockData(
                x: level >= 3 ? bs : 0,
                y: Float(level) * bs,
                z: 0,
                blockType: .trunk,
                colorHex: "#4A3520",
                parentIndex: blocks.count - 1
            )
        )
    }

    let firstBranchOrigin = 3
    blocks.append(VoxelBlockData(x: bs * 2, y: bs * 3, z: 0, blockType: .branch, colorHex: "#5A4530", parentIndex: firstBranchOrigin))
    blocks.append(VoxelBlockData(x: bs * 3, y: bs * 3, z: 0, blockType: .branch, colorHex: "#5A4530", parentIndex: blocks.count - 1))
    blocks.append(VoxelBlockData(x: bs * 3, y: bs * 4, z: 0, blockType: .branch, colorHex: "#5A4530", parentIndex: blocks.count - 1))
    blocks.append(VoxelBlockData(x: bs * 3, y: bs * 5, z: 0, blockType: .leaf, colorHex: "#7AB648", parentIndex: blocks.count - 1))
    blocks.append(VoxelBlockData(x: bs * 4, y: bs * 4, z: 0, blockType: .leaf, colorHex: "#7AB648", parentIndex: blocks.count - 2))

    let secondBranchOrigin = 4
    blocks.append(VoxelBlockData(x: 0, y: bs * 4, z: bs, blockType: .branch, colorHex: "#5A4530", parentIndex: secondBranchOrigin))
    blocks.append(VoxelBlockData(x: 0, y: bs * 5, z: bs, blockType: .branch, colorHex: "#5A4530", parentIndex: blocks.count - 1))
    blocks.append(VoxelBlockData(x: 0, y: bs * 6, z: bs, blockType: .leaf, colorHex: "#7AB648", parentIndex: blocks.count - 1))

    return blocks
}

private func makeMatureTree() -> [VoxelBlockData] {
    var blocks = makeYoungTree()
    let bs = VoxelConstants.blockSize

    let trunkTopIndex = blocks.firstIndex { $0.blockType == .trunk && $0.y == bs * 5 } ?? 5
    blocks.append(VoxelBlockData(x: bs, y: bs * 6, z: 0, blockType: .trunk, colorHex: "#4A3520", parentIndex: trunkTopIndex))
    blocks.append(VoxelBlockData(x: bs, y: bs * 7, z: 0, blockType: .trunk, colorHex: "#4A3520", parentIndex: blocks.count - 1))

    let crownOrigin = blocks.count - 1
    let matureExtensions: [(Float, Float, Float, BlockType, Int)] = [
        (bs * 2, bs * 7, 0, .branch, crownOrigin),
        (bs * 3, bs * 7, 0, .branch, blocks.count),
        (bs * 3, bs * 8, 0, .leaf, blocks.count + 1),
        (bs * 3, bs * 7, bs, .leaf, blocks.count + 1),
        (bs * 2, bs * 7, bs, .leaf, blocks.count),
        (-bs, bs * 6, bs, .branch, crownOrigin),
        (-bs * 2, bs * 6, bs, .branch, blocks.count + 4),
        (-bs * 2, bs * 7, bs, .leaf, blocks.count + 5),
        (-bs * 2, bs * 6, bs * 2, .leaf, blocks.count + 5),
        (bs, bs * 6, -bs, .branch, crownOrigin),
        (bs * 2, bs * 6, -bs, .branch, blocks.count + 8),
        (bs * 2, bs * 7, -bs, .leaf, blocks.count + 9),
        (bs * 2, bs * 6, -bs * 2, .leaf, blocks.count + 9),
        (0, bs * 7, 0, .leaf, crownOrigin)
    ]

    for extensionBlock in matureExtensions {
        blocks.append(
            VoxelBlockData(
                x: extensionBlock.0,
                y: extensionBlock.1,
                z: extensionBlock.2,
                blockType: extensionBlock.3,
                colorHex: extensionBlock.3 == .branch || extensionBlock.3 == .trunk ? "#5A4530" : "#7AB648",
                parentIndex: extensionBlock.4
            )
        )
    }

    return blocks
}

private func isFaceAdjacent(_ vector: (Float, Float, Float)) -> Bool {
    let unit = VoxelConstants.blockSize
    let components = [abs(vector.0), abs(vector.1), abs(vector.2)]
    let movedComponents = components.filter { abs($0 - unit) < 0.0001 }
    let zeroComponents = components.filter { $0 < 0.0001 }
    return movedComponents.count == 1 && zeroComponents.count == 2
}

private func averageRadialSpread(of blocks: [VoxelBlockData]) -> Float {
    let foliage = blocks.filter { $0.blockType == .leaf || $0.blockType == .flower }
    guard !foliage.isEmpty else { return 0 }

    let total = foliage.reduce(Float.zero) { partialResult, block in
        partialResult + abs(block.x) + abs(block.z)
    }
    return total / Float(foliage.count)
}
