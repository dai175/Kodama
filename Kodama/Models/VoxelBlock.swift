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
        get { BlockType(rawValue: blockTypeRaw) ?? .trunk }
        set { blockTypeRaw = newValue.rawValue }
    }

    var source: GrowthSource {
        get { GrowthSource(rawValue: sourceRaw) ?? .autonomous }
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
