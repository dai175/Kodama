//
//  GrowthTypes.swift
//  Kodama
//

import Foundation

// MARK: - InteractionPayload

/// Pure value snapshot of an Interaction that can cross actor boundaries
/// into the nonisolated vector growth engine.
nonisolated struct InteractionPayload {
    let timestamp: Date
    let type: InteractionType
    let value: String?
    let touchX: Int?
    let touchY: Int?
    let touchZ: Int?
}
