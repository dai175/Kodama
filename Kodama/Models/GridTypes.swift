//
//  GridTypes.swift
//  Kodama
//

import Foundation

struct Int3: Hashable {
    let x: Int
    let y: Int
    let z: Int

    func adding(_ other: Int3) -> Int3 {
        Int3(x: x + other.x, y: y + other.y, z: z + other.z)
    }

    var asVoxelCoordinates: (Float, Float, Float) {
        (Float(x), Float(y), Float(z))
    }
}

enum GridLayer: Hashable {
    case wood
    case foliage
}

struct GrowthNode {
    typealias NodeID = Int

    let id: NodeID
    let pos: Int3
    let layer: GridLayer
    let blockType: BlockType
    let parentID: NodeID?
}

enum GridMapper {
    static func layer(for blockType: BlockType) -> GridLayer {
        switch blockType {
        case .trunk, .branch:
            .wood
        case .leaf, .flower, .moss, .snow:
            .foliage
        }
    }

    static func int3(from block: VoxelBlockData) -> Int3 {
        Int3(
            x: Int(block.x.rounded()),
            y: Int(block.y.rounded()),
            z: Int(block.z.rounded())
        )
    }
}
