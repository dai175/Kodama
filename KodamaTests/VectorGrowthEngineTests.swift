//
//  VectorGrowthEngineTests.swift
//  KodamaTests
//

import Foundation
@testable import Kodama
import Testing

struct VectorGrowthEngineTests {
    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return components.date ?? Date(timeIntervalSince1970: 0)
    }

    private func saplingInput(
        seed: UInt64 = 42,
        start: Date,
        end: Date,
        maxHours: Int = 24 * 30
    ) -> VectorGrowthInput {
        let sapling = SkeletonBuilder.buildSapling(seed: seed, createdAt: start)
        return VectorGrowthInput(
            seed: Int(seed),
            segments: sapling.segments,
            leafClusters: sapling.leafClusters,
            lastEval: start,
            currentDate: end,
            interactions: [],
            maxElapsedHours: maxHours
        )
    }

    // MARK: - Tests

    @Test func growthProducesNewSegmentsOverTime() {
        let start = makeDate(year: 2026, month: 5, day: 1)
        let end = makeDate(year: 2026, month: 6, day: 1)
        let input = saplingInput(start: start, end: end)

        let result = VectorGrowthEngine.calculate(input)
        #expect(!result.newSegments.isEmpty)
    }

    @Test func newSegmentsHaveValidParentReferences() {
        let start = makeDate(year: 2026, month: 5, day: 1)
        let end = makeDate(year: 2026, month: 6, day: 1)
        let input = saplingInput(start: start, end: end)

        let result = VectorGrowthEngine.calculate(input)
        let allSegmentIDs = Set(input.segments.map(\.id) + result.newSegments.map(\.id))

        for segment in result.newSegments {
            guard let parentID = segment.parentID else { continue }
            #expect(allSegmentIDs.contains(parentID), "segment \(segment.id) references unknown parent")
        }
    }

    @Test func segmentCountDoesNotExceedMax() {
        let start = makeDate(year: 2026, month: 1, day: 1)
        let end = makeDate(year: 2027, month: 1, day: 1)
        let input = saplingInput(seed: 777, start: start, end: end, maxHours: 24 * 365)

        let result = VectorGrowthEngine.calculate(input)
        let total = input.segments.count + result.newSegments.count
        #expect(total <= VectorGrowthEngine.maxSegments)
    }

    @Test func thicknessIncreasesWithAge() throws {
        let start = makeDate(year: 2026, month: 1, day: 1)
        let end = makeDate(year: 2026, month: 4, day: 1)
        let input = saplingInput(start: start, end: end)

        let result = VectorGrowthEngine.calculate(input)
        // The initial trunk segment is ~90 days old; age alone should push
        // its thickness above the starting value regardless of descendants.
        let trunkID = input.segments[0].id
        let newThickness = try #require(
            result.segmentThicknessUpdates[trunkID],
            "trunk thickness should be updated after a quarter of aging"
        )
        #expect(newThickness > input.segments[0].thickness)
    }

    @Test func leafClustersAttachOnlyToTips() {
        let start = makeDate(year: 2026, month: 5, day: 1)
        let end = makeDate(year: 2026, month: 7, day: 1)
        let input = saplingInput(start: start, end: end)

        let result = VectorGrowthEngine.calculate(input)
        let allSegments = input.segments + result.newSegments
        let tipIDs = Set(VectorGrowthEngine.findTipSegmentIDs(in: allSegments))

        for cluster in result.newClusters {
            guard let segID = cluster.segmentID else { continue }
            #expect(tipIDs.contains(segID), "new cluster attached to non-tip segment \(segID)")
        }
    }

    @Test func winterReducesClusterDensity() {
        let start = makeDate(year: 2026, month: 11, day: 1)
        let end = makeDate(year: 2026, month: 12, day: 15)
        let input = saplingInput(start: start, end: end)

        let result = VectorGrowthEngine.calculate(input)
        for update in result.clusterUpdates.values {
            #expect(update.density <= 0.3, "winter cluster density should be reduced")
        }
    }
}
