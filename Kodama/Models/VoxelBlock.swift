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
    var ix: Int
    var iy: Int
    var iz: Int
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

    var pos: Int3 {
        Int3(x: ix, y: iy, z: iz)
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
        id: UUID = UUID(),
        pos: Int3,
        blockType: BlockType,
        colorHex: String,
        source: GrowthSource,
        parentBlockID: UUID? = nil
    ) {
        self.id = id
        ix = pos.x
        iy = pos.y
        iz = pos.z
        blockTypeRaw = blockType.rawValue
        self.colorHex = colorHex
        placedAt = Date()
        sourceRaw = source.rawValue
        self.parentBlockID = parentBlockID
    }
}
