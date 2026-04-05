//
//  GrowthSource.swift
//  Kodama
//

// MARK: - GrowthSource

enum GrowthSource: String, Codable {
    case autonomous
    case touch
    case color
    case word
}

// MARK: - InteractionType

enum InteractionType: String, Codable {
    case open
    case touch
    case color
    case word
}
