//
//  GrowthSource.swift
//  Kodama
//

// MARK: - GrowthSource

enum GrowthSource: String, Codable, Sendable {
    case autonomous
    case touch
    case color
    case word
}

// MARK: - InteractionType

enum InteractionType: String, Codable, Sendable {
    case open
    case touch
    case color
    case word
}
