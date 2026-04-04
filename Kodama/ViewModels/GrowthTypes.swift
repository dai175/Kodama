//
//  GrowthTypes.swift
//  Kodama
//

import Foundation

// MARK: - GrowthResult

nonisolated struct GrowthResult {
    let newBlocks: [VoxelBlockData]
    let seasonalEffects: SeasonalResult
}

nonisolated struct GrowthTreeState {
    let seed: Int
    let totalBlocks: Int
}

nonisolated struct InteractionPayload {
    let timestamp: Date
    let type: InteractionType
    let value: String?
    let touchX: Int?
    let touchY: Int?
    let touchZ: Int?
}
