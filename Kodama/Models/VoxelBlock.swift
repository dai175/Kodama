//
//  VoxelBlock.swift
//  Kodama
//

import Foundation
import SwiftData

// MARK: - VoxelBlock

@Model
final class VoxelBlock {
    // MARK: Internal

    var id: UUID
    var x: Float
    var y: Float
    var z: Float
    var blockTypeRaw: String
    var colorHex: String
    var placedAt: Date
    var sourceRaw: String
    var parentBlockID: UUID?
    var tree: BonsaiTree?

    var blockType: BlockType {
        get {
            guard let type = BlockType(rawValue: blockTypeRaw) else {
                assertionFailure("Unknown blockTypeRaw: \(blockTypeRaw)")
                return .trunk
            }
            return type
        }
        set { blockTypeRaw = newValue.rawValue }
    }

    var positionKey: PositionKey {
        PositionKey(x: x, y: y, z: z)
    }

    var source: GrowthSource {
        get {
            guard let type = GrowthSource(rawValue: sourceRaw) else {
                assertionFailure("Unknown sourceRaw: \(sourceRaw)")
                return .autonomous
            }
            return type
        }
        set { sourceRaw = newValue.rawValue }
    }

    // MARK: - Initialization

    init(
        x: Float,
        y: Float,
        z: Float,
        blockType: BlockType,
        colorHex: String,
        source: GrowthSource,
        parentBlockID: UUID? = nil
    ) {
        id = UUID()
        self.x = x
        self.y = y
        self.z = z
        blockTypeRaw = blockType.rawValue
        self.colorHex = colorHex
        placedAt = Date()
        sourceRaw = source.rawValue
        self.parentBlockID = parentBlockID
    }
}
