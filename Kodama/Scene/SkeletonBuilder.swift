//
//  SkeletonBuilder.swift
//  Kodama
//

import Foundation

// MARK: - SkeletonBuilder

/// Builds the initial sapling skeleton for a newly created tree.
///
/// The vector-tree engine replaces the old voxel-first `TreeBuilder.buildSapling`:
/// instead of manually placing voxels we emit a short trunk line segment and a
/// small leaf cluster at its tip. The rasterizer converts them to voxels at
/// render time.
nonisolated enum SkeletonBuilder {
    struct Sapling {
        let segments: [SegmentSnapshot]
        let leafClusters: [LeafClusterSnapshot]
    }

    static let initialTrunkHeight: Float = 4.0
    static let initialTrunkThickness: Float = 0.6

    static func buildSapling(seed: UInt64) -> Sapling {
        var rng = SeededRandom(seed: seed)

        let trunkColor = TreeBuilder.trunkColors[Int(rng.next() % UInt64(TreeBuilder.trunkColors.count))]
        let leafColor = TreeBuilder.leafColors[Int(rng.next() % UInt64(TreeBuilder.leafColors.count))]

        let trunk = SegmentSnapshot(
            id: UUID(),
            kind: .trunk,
            start: Float3(x: 0, y: 0, z: 0),
            end: Float3(x: 0, y: initialTrunkHeight, z: 0),
            thickness: initialTrunkThickness,
            colorHex: trunkColor,
            parentID: nil
        )

        let clusterCenter = Float3(x: 0, y: initialTrunkHeight + 0.5, z: 0)
        let cluster = LeafClusterSnapshot(
            id: UUID(),
            segmentID: trunk.id,
            center: clusterCenter,
            radius: 1.6,
            density: 0.55,
            colorHex: leafColor,
            scatterSeed: Int64(bitPattern: rng.next())
        )

        return Sapling(segments: [trunk], leafClusters: [cluster])
    }
}
