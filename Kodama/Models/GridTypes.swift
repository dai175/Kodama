//
//  GridTypes.swift
//  Kodama
//

import Foundation

nonisolated struct Int3: Hashable {
    let x: Int
    let y: Int
    let z: Int

    func adding(_ other: Int3) -> Int3 {
        Int3(x: x + other.x, y: y + other.y, z: z + other.z)
    }

    var asSceneCoordinates: (Float, Float, Float) {
        (Float(x), Float(y), Float(z))
    }
}

nonisolated enum GridLayer: Hashable {
    case wood
    case foliage
}

nonisolated struct GrowthNode {
    typealias NodeID = Int

    let nodeID: NodeID
    let blockID: UUID
    let pos: Int3
    let layer: GridLayer
    let blockType: BlockType
    let parentNodeID: NodeID?
}

nonisolated enum GridMapper {
    static func layer(for blockType: BlockType) -> GridLayer {
        switch blockType {
        case .trunk, .branch:
            .wood
        case .leaf, .flower, .moss, .snow:
            .foliage
        }
    }

    static func int3(from block: VoxelBlockData) -> Int3 {
        block.pos
    }
}
