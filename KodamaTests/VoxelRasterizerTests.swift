//
//  VoxelRasterizerTests.swift
//  KodamaTests
//

import Foundation
@testable import Kodama
import Testing

struct VoxelRasterizerTests {
    // MARK: - Helpers

    /// Deterministic UUID builder for tests — avoids force-unwrapping a
    /// string literal constructor.
    private func fixedUUID(_ index: Int) -> UUID {
        let suffix = String(format: "%012d", index)
        return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)") ?? UUID()
    }

    private func trunkSegment(
        start: Float3 = Float3(x: 0, y: 0, z: 0),
        end: Float3 = Float3(x: 0, y: 4, z: 0),
        thickness: Float = 0.6
    ) -> SegmentSnapshot {
        SegmentSnapshot(
            id: UUID(),
            kind: .trunk,
            start: start,
            end: end,
            thickness: thickness,
            colorHex: "#4A3520",
            parentID: nil,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func cluster(
        center: Float3,
        radius: Float = 2.0,
        density: Float = 1.0,
        seed: Int64 = 7,
        color: String = "#7AB648"
    ) -> LeafClusterSnapshot {
        LeafClusterSnapshot(
            id: fixedUUID(1),
            segmentID: nil,
            center: center,
            radius: radius,
            density: density,
            colorHex: color,
            scatterSeed: seed
        )
    }

    // MARK: - Tests

    @Test func emptyInputProducesNoBlocks() {
        let blocks = VoxelRasterizer.rasterize(segments: [], leafClusters: [])
        #expect(blocks.isEmpty)
    }

    @Test func verticalTrunkProducesConnectedWoodVoxels() {
        let segment = trunkSegment()
        let blocks = VoxelRasterizer.rasterize(segments: [segment], leafClusters: [])

        #expect(blocks.allSatisfy { $0.blockType == .trunk })
        // With thickness 0.6 and a 4-unit vertical segment, we expect at least
        // one voxel per integer y from 0 to 4.
        let heights = Set(blocks.map(\.pos.y))
        for y in 0 ... 4 {
            #expect(heights.contains(y), "missing trunk voxel at y=\(y)")
        }
    }

    @Test func rasterizationIsDeterministic() {
        let segment = trunkSegment()
        let leafCluster = cluster(center: Float3(x: 0, y: 5, z: 0), density: 0.5)

        let first = VoxelRasterizer.rasterize(segments: [segment], leafClusters: [leafCluster])
        let second = VoxelRasterizer.rasterize(segments: [segment], leafClusters: [leafCluster])

        let firstPositions = first.map(\.pos)
        let secondPositions = second.map(\.pos)
        #expect(firstPositions == secondPositions)
    }

    @Test func thickerSegmentProducesMoreVoxels() {
        let thin = trunkSegment(thickness: 0.5)
        let thick = trunkSegment(thickness: 1.5)
        let thinBlocks = VoxelRasterizer.rasterize(segments: [thin], leafClusters: [])
        let thickBlocks = VoxelRasterizer.rasterize(segments: [thick], leafClusters: [])
        #expect(thickBlocks.count > thinBlocks.count)
    }

    @Test func leafClusterProducesLeafVoxels() {
        let leafCluster = cluster(center: Float3(x: 0, y: 5, z: 0))
        let blocks = VoxelRasterizer.rasterize(segments: [], leafClusters: [leafCluster])
        #expect(!blocks.isEmpty)
        #expect(blocks.allSatisfy { $0.blockType == .leaf })
    }

    @Test func leafClusterExcludesVoxelsDirectlyBelowBranches() {
        // Horizontal branch at y = 5, with leaves surrounding it.
        let branch = SegmentSnapshot(
            id: UUID(),
            kind: .branch,
            start: Float3(x: -2, y: 5, z: 0),
            end: Float3(x: 2, y: 5, z: 0),
            thickness: 0.6,
            colorHex: "#5A4530",
            parentID: nil,
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let leafCluster = cluster(center: Float3(x: 0, y: 5, z: 0), radius: 3)
        let blocks = VoxelRasterizer.rasterize(segments: [branch], leafClusters: [leafCluster])

        let woodPositions = Set(blocks.filter { $0.blockType == .branch }.map(\.pos))
        let leafPositions = blocks.filter { $0.blockType == .leaf }.map(\.pos)

        // No leaf should sit directly beneath (y - 1) a wood voxel.
        for leafPos in leafPositions {
            let above = Int3(x: leafPos.x, y: leafPos.y + 1, z: leafPos.z)
            #expect(!woodPositions.contains(above), "leaf at \(leafPos) lies directly under wood at \(above)")
        }
    }

    @Test func densityZeroYieldsNoLeaves() {
        let leafCluster = cluster(center: Float3(x: 0, y: 5, z: 0), density: 0)
        let blocks = VoxelRasterizer.rasterize(segments: [], leafClusters: [leafCluster])
        #expect(blocks.isEmpty)
    }

    @Test func leavesDoNotOverlapWood() {
        let trunk = trunkSegment()
        let leafCluster = cluster(center: Float3(x: 0, y: 2, z: 0), radius: 2)
        let blocks = VoxelRasterizer.rasterize(segments: [trunk], leafClusters: [leafCluster])

        let woodPositions = Set(blocks.filter { $0.blockType == .trunk || $0.blockType == .branch }.map(\.pos))
        for leaf in blocks where leaf.blockType == .leaf {
            #expect(!woodPositions.contains(leaf.pos))
        }
    }

    @Test func outputIsIndependentOfInputOrder() {
        // Regression guard for the rasterizer's internal segment/cluster
        // sort: shuffling the input arrays must not change the output.
        let trunk = trunkSegment()
        let branch = SegmentSnapshot(
            id: fixedUUID(3),
            kind: .branch,
            start: Float3(x: 0, y: 3, z: 0),
            end: Float3(x: 2, y: 4, z: 0),
            thickness: 0.6,
            colorHex: "#5A4530",
            parentID: nil,
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let clusterA = cluster(center: Float3(x: 1, y: 5, z: 0), seed: 11)
        let clusterB = LeafClusterSnapshot(
            id: fixedUUID(2),
            segmentID: nil,
            center: Float3(x: -1, y: 5, z: 0),
            radius: 2,
            density: 1,
            colorHex: "#7AB648",
            scatterSeed: 22
        )

        let canonical = VoxelRasterizer.rasterize(
            segments: [trunk, branch],
            leafClusters: [clusterA, clusterB]
        )
        let shuffled = VoxelRasterizer.rasterize(
            segments: [branch, trunk],
            leafClusters: [clusterB, clusterA]
        )

        // Sort by position for comparison — the output array order itself is
        // also deterministic, but positional equality is the property we
        // actually care about for rendering.
        let canonicalPositions = canonical.map(\.pos).sorted {
            ($0.x, $0.y, $0.z) < ($1.x, $1.y, $1.z)
        }
        let shuffledPositions = shuffled.map(\.pos).sorted {
            ($0.x, $0.y, $0.z) < ($1.x, $1.y, $1.z)
        }
        #expect(canonicalPositions == shuffledPositions)
    }

    @Test func noDuplicatePositionsInOutput() {
        let trunk = trunkSegment()
        let leafA = cluster(center: Float3(x: 1, y: 5, z: 0), radius: 2, density: 0.7, seed: 1)
        let leafB = LeafClusterSnapshot(
            id: fixedUUID(2),
            segmentID: nil,
            center: Float3(x: -1, y: 5, z: 0),
            radius: 2,
            density: 0.7,
            colorHex: "#7AB648",
            scatterSeed: 2
        )
        let blocks = VoxelRasterizer.rasterize(segments: [trunk], leafClusters: [leafA, leafB])
        var seen = Set<Int3>()
        for block in blocks {
            #expect(!seen.contains(block.pos))
            seen.insert(block.pos)
        }
    }
}
