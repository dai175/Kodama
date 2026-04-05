//
//  KodamaTests.swift
//  KodamaTests
//

import Foundation
@testable import Kodama
import SceneKit
import Testing

struct KodamaTests {
    // MARK: - Interaction Model

    @Test func interactionTouchCoordinatesUseIntegers() {
        let interaction = Interaction(type: .touch, touchX: 2, touchY: -1, touchZ: 5)

        #expect(interaction.touchX == 2)
        #expect(interaction.touchY == -1)
        #expect(interaction.touchZ == 5)
    }

    // MARK: - Sapling Generation

    @Test func saplingProducesTrunkAndCluster() {
        let sapling = SkeletonBuilder.buildSapling(seed: 42)
        #expect(!sapling.segments.isEmpty)
        #expect(sapling.segments.first?.kind == .trunk)
        #expect(!sapling.leafClusters.isEmpty)
    }

    @Test func saplingGenerationIsDeterministic() {
        let first = SkeletonBuilder.buildSapling(seed: 7)
        let second = SkeletonBuilder.buildSapling(seed: 7)
        #expect(first.segments.count == second.segments.count)
        #expect(first.segments[0].start == second.segments[0].start)
        #expect(first.segments[0].end == second.segments[0].end)
    }

    // MARK: - End-to-End: Skeleton → Growth → Rasterize

    @Test func fullPipelineProducesRenderableVoxels() {
        let sapling = SkeletonBuilder.buildSapling(seed: 123)
        let start = makeDate(year: 2026, month: 5, day: 1)
        let end = makeDate(year: 2026, month: 7, day: 1)
        var ages: [UUID: Date] = [:]
        for segment in sapling.segments {
            ages[segment.id] = start
        }

        let input = VectorGrowthInput(
            seed: 123,
            segments: sapling.segments,
            leafClusters: sapling.leafClusters,
            segmentAges: ages,
            lastEval: start,
            currentDate: end,
            interactions: [],
            maxElapsedHours: 24 * 62
        )

        let result = VectorGrowthEngine.calculate(input)

        // Apply results into a mutable skeleton, then rasterize.
        var segments = sapling.segments + result.newSegments
        for i in segments.indices {
            if let newThickness = result.segmentThicknessUpdates[segments[i].id] {
                segments[i] = SegmentSnapshot(
                    id: segments[i].id,
                    kind: segments[i].kind,
                    start: segments[i].start,
                    end: segments[i].end,
                    thickness: newThickness,
                    colorHex: segments[i].colorHex,
                    parentID: segments[i].parentID
                )
            }
        }

        var clusters = sapling.leafClusters
        let removed = Set(result.removedClusterIDs)
        clusters = clusters.filter { !removed.contains($0.id) }
        for i in clusters.indices {
            if let update = result.clusterUpdates[clusters[i].id] {
                clusters[i] = LeafClusterSnapshot(
                    id: clusters[i].id,
                    segmentID: clusters[i].segmentID,
                    center: clusters[i].center,
                    radius: update.radius,
                    density: update.density,
                    colorHex: update.colorHex,
                    scatterSeed: clusters[i].scatterSeed
                )
            }
        }
        clusters += result.newClusters

        let blocks = VoxelRasterizer.rasterize(segments: segments, leafClusters: clusters)

        #expect(!blocks.isEmpty)
        #expect(blocks.count <= VoxelConstants.maxBlocks)
        #expect(blocks.contains { $0.blockType == .trunk })
        #expect(blocks.contains { $0.blockType == .leaf })
    }

    @Test func rasterizedOutputHasNoDuplicatePositions() {
        let sapling = SkeletonBuilder.buildSapling(seed: 77)
        let blocks = VoxelRasterizer.rasterize(
            segments: sapling.segments,
            leafClusters: sapling.leafClusters
        )

        var positions = Set<Int3>()
        for block in blocks {
            #expect(!positions.contains(block.pos), "duplicate position \(block.pos) for \(block.blockType)")
            positions.insert(block.pos)
        }
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

    // MARK: - Segment Hierarchy Integrity

    @Test func segmentHierarchyIsValidAndAcyclic() {
        let sapling = SkeletonBuilder.buildSapling(seed: 5)
        let start = makeDate(year: 2026, month: 3, day: 1)
        let end = makeDate(year: 2026, month: 8, day: 1)
        var ages: [UUID: Date] = [:]
        for segment in sapling.segments {
            ages[segment.id] = start
        }

        let input = VectorGrowthInput(
            seed: 5,
            segments: sapling.segments,
            leafClusters: sapling.leafClusters,
            segmentAges: ages,
            lastEval: start,
            currentDate: end,
            interactions: [],
            maxElapsedHours: 24 * 153
        )
        let result = VectorGrowthEngine.calculate(input)
        let allSegments = sapling.segments + result.newSegments
        let idSet = Set(allSegments.map(\.id))

        for segment in allSegments {
            guard let parentID = segment.parentID else { continue }
            #expect(idSet.contains(parentID), "segment \(segment.id) references unknown parent")
            #expect(parentID != segment.id, "segment cannot be its own parent")
        }

        // Walk each parent chain to ensure acyclicity.
        let byID = Dictionary(uniqueKeysWithValues: allSegments.map { ($0.id, $0) })
        for segment in allSegments {
            var visited = Set<UUID>()
            var cursor: UUID? = segment.id
            var hops = 0
            while let current = cursor {
                #expect(!visited.contains(current))
                visited.insert(current)
                cursor = byID[current]?.parentID
                hops += 1
                #expect(hops <= allSegments.count)
            }
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
    components.minute = 0
    components.second = 0
    return components.date ?? Date(timeIntervalSince1970: 0)
}
