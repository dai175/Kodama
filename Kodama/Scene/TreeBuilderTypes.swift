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

// MARK: - TreeBuilder Supporting Types

extension TreeBuilder {
    struct BuildContext {
        var blocks: [VoxelBlockData]
        var occupiedPositions: Set<Int3>
        var rng: SeededRandom
    }

    enum FoliageDensity {
        case barelyThere
        case sparse
        case medium
        case lush
    }

    struct StageProfile {
        let branchCountRange: ClosedRange<Int>
        let branchLengthRange: ClosedRange<Int>
        let branchStartHeightBias: Int
        let intermediateFoliageDensity: FoliageDensity
        let terminalFoliageDensity: FoliageDensity
        let crownDensity: FoliageDensity
        let prefersOuterCanopy: Bool
        let secondaryBranchChance: UInt64
        let canopyOpenSlots: Int
        let canopyLiftChance: UInt64
    }
}
