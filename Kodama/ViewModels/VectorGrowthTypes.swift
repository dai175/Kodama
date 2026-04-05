//
//  VectorGrowthTypes.swift
//  Kodama
//

import Foundation

// MARK: - VectorGrowthInput

nonisolated struct VectorGrowthInput {
    let seed: Int
    let segments: [SegmentSnapshot]
    let leafClusters: [LeafClusterSnapshot]
    let segmentAges: [UUID: Date]
    let lastEval: Date
    let currentDate: Date
    let interactions: [InteractionPayload]
    let maxElapsedHours: Int
}

// MARK: - VectorGrowthResult

nonisolated struct VectorGrowthResult {
    var newSegments: [SegmentSnapshot]
    var segmentThicknessUpdates: [UUID: Float]
    var segmentDescendantCountUpdates: [UUID: Int]
    var newClusters: [LeafClusterSnapshot]
    var clusterUpdates: [UUID: ClusterUpdate]
    var removedClusterIDs: [UUID]

    static let empty = VectorGrowthResult(
        newSegments: [],
        segmentThicknessUpdates: [:],
        segmentDescendantCountUpdates: [:],
        newClusters: [],
        clusterUpdates: [:],
        removedClusterIDs: []
    )
}

// MARK: - ClusterUpdate

nonisolated struct ClusterUpdate {
    let radius: Float
    let density: Float
    let colorHex: String
}
