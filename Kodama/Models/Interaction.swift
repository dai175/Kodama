//
//  Interaction.swift
//  Kodama
//

import Foundation
import SwiftData

// MARK: - Interaction

@Model
final class Interaction {
    // MARK: Internal

    var id: UUID
    var timestamp: Date
    var typeRaw: String
    var value: String?
    var touchX: Int?
    var touchY: Int?
    var touchZ: Int?
    var tree: BonsaiTree?

    var type: InteractionType {
        get {
            guard let interactionType = InteractionType(rawValue: typeRaw) else {
                assertionFailure("Invalid typeRaw value: \(typeRaw). Defaulting to .open")
                return .open
            }
            return interactionType
        }
        set { typeRaw = newValue.rawValue }
    }

    // MARK: - Initialization

    init(
        type: InteractionType,
        value: String? = nil,
        touchX: Int? = nil,
        touchY: Int? = nil,
        touchZ: Int? = nil
    ) {
        id = UUID()
        timestamp = Date()
        typeRaw = type.rawValue
        self.value = value
        self.touchX = touchX
        self.touchY = touchY
        self.touchZ = touchZ
    }
}
