//
//  GridTypes.swift
//  Kodama
//

import Foundation

/// Integer voxel grid coordinate. Used by the voxel cache produced by the
/// `VoxelRasterizer` and by touch → grid conversion in the interaction layer.
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
