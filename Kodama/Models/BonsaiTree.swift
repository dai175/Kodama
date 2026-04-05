//
//  BonsaiTree.swift
//  Kodama
//

import Foundation
import SwiftData

// MARK: - BonsaiTree

@Model
final class BonsaiTree {
    var id: UUID
    var seed: Int
    var createdAt: Date
    var lastGrowthEval: Date
    var totalBlocks: Int

    /// Voxel blocks. Authoritative in the legacy engine; treated as a render
    /// cache once the vector-tree engine takes over.
    @Relationship(deleteRule: .cascade, inverse: \VoxelBlock.tree)
    var blocks: [VoxelBlock]

    /// Vector skeleton segments — authoritative tree structure.
    @Relationship(deleteRule: .cascade, inverse: \BranchSegment.tree)
    var segments: [BranchSegment]

    /// Leaf clusters attached to branch tips.
    @Relationship(deleteRule: .cascade, inverse: \LeafCluster.tree)
    var leafClusters: [LeafCluster]

    @Relationship(deleteRule: .cascade, inverse: \Interaction.tree)
    var interactions: [Interaction]

    init(seed: Int) {
        id = UUID()
        self.seed = seed
        createdAt = Date()
        lastGrowthEval = Date()
        totalBlocks = 0
        blocks = []
        segments = []
        leafClusters = []
        interactions = []
    }
}
