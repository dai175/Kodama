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
    var touchX: Float?
    var touchY: Float?
    var touchZ: Float?
    var tree: BonsaiTree?

    var type: InteractionType {
        get { InteractionType(rawValue: typeRaw) ?? .open }
        set { typeRaw = newValue.rawValue }
    }

    // MARK: - Initialization

    init(
        type: InteractionType,
        value: String? = nil,
        touchX: Float? = nil,
        touchY: Float? = nil,
        touchZ: Float? = nil
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
