//
//  TreeBuilderTypes.swift
//  Kodama
//

import Foundation

// MARK: - VoxelBlockData

/// Flat, thread-safe block record used by the voxel cache. Produced by the
/// `VoxelRasterizer` and consumed by `BonsaiRenderer`.
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

/// Deterministic xorshift generator shared by the vector growth engine and
/// the rasterizer so output is reproducible for a given seed.
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
