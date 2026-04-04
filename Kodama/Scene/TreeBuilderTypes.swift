//
//  TreeBuilderTypes.swift
//  Kodama
//

import Foundation

// MARK: - VoxelBlockData

nonisolated struct VoxelBlockData {
    let id: UUID
    let pos: Int3
    let blockType: BlockType
    let colorHex: String
    let parentID: UUID?

    init(
        id: UUID = UUID(),
        pos: Int3,
        blockType: BlockType,
        colorHex: String,
        parentID: UUID?
    ) {
        self.id = id
        self.pos = pos
        self.blockType = blockType
        self.colorHex = colorHex
        self.parentID = parentID
    }
}

// MARK: - Stage Profiles

extension TreeBuilder {
    nonisolated static func stageProfile(for stage: GrowthStage) -> StageProfile {
        switch stage {
        case .sapling:
            StageProfile(
                branchCountRange: 2 ... 2,
                branchLengthRange: 5 ... 6,
                branchStartHeightBias: 0,
                intermediateFoliageDensity: .barelyThere,
                terminalFoliageDensity: .sparse,
                crownDensity: .sparse,
                prefersOuterCanopy: false,
                secondaryBranchChance: 0,
                canopyOpenSlots: 0,
                canopyLiftChance: 0
            )
        case .young:
            StageProfile(
                branchCountRange: 2 ... 3,
                branchLengthRange: 5 ... 7,
                branchStartHeightBias: 1,
                intermediateFoliageDensity: .sparse,
                terminalFoliageDensity: .medium,
                crownDensity: .medium,
                prefersOuterCanopy: false,
                secondaryBranchChance: 3,
                canopyOpenSlots: 0,
                canopyLiftChance: 7
            )
        case .mature:
            StageProfile(
                branchCountRange: 3 ... 3,
                branchLengthRange: 6 ... 8,
                branchStartHeightBias: 1,
                intermediateFoliageDensity: .medium,
                terminalFoliageDensity: .lush,
                crownDensity: .medium,
                prefersOuterCanopy: true,
                secondaryBranchChance: 2,
                canopyOpenSlots: 1,
                canopyLiftChance: 5
            )
        }
    }
}

// MARK: - SeededRandom

nonisolated struct SeededRandom: RandomNumberGenerator {
    // MARK: Internal

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    // MARK: Private

    private var state: UInt64

    // MARK: - Initialization

    init(seed: UInt64) {
        state = seed == 0 ? 1 : seed
    }
}
