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

    @Relationship(deleteRule: .cascade, inverse: \VoxelBlock.tree)
    var blocks: [VoxelBlock]

    @Relationship(deleteRule: .cascade, inverse: \Interaction.tree)
    var interactions: [Interaction]

    init(seed: Int) {
        id = UUID()
        self.seed = seed
        createdAt = Date()
        lastGrowthEval = Date()
        totalBlocks = 0
        blocks = []
        interactions = []
    }
}
