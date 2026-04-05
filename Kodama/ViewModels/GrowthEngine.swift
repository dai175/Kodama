//
//  GrowthEngine.swift
//  Kodama
//

import Foundation

// MARK: - GrowthEngine

/// Legacy namespace retained for small nonisolated helpers shared by the
/// `VectorGrowthEngine`. All voxel-first growth logic has been removed; the
/// vector engine is the authoritative implementation.
nonisolated enum GrowthEngine {
    /// Returns the number of growth actions to perform this tick (one hour).
    /// Growth rate varies by season and growth stage, as in the previous
    /// voxel-first engine — the vector engine reuses the same cadence so
    /// seasonal pacing stays consistent.
    nonisolated static func blocksPerTick(
        season: Season,
        growthStage: TreeBuilder.GrowthStage,
        rng: inout SeededRandom
    ) -> Int {
        let roll = Int(rng.next() % 100)

        switch season {
        case .spring:
            return roll < 22 ? 1 : 0
        case .summer:
            let threshold = switch growthStage {
            case .sapling:
                14
            case .young:
                16
            case .mature:
                18
            }
            return roll < threshold ? 1 : 0
        case .autumn:
            return roll < 6 ? 1 : 0
        case .winter:
            return 0
        }
    }
}
