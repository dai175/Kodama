//
//  Float3.swift
//  Kodama
//

import Foundation

/// Sub-voxel precision 3D vector used by the vector-tree model.
/// Coordinates are expressed in logical voxel units; the rasterizer snaps
/// them to the integer grid when producing `VoxelBlockData`.
nonisolated struct Float3: Hashable, Sendable {
    var x: Float
    var y: Float
    var z: Float

    static let zero = Float3(x: 0, y: 0, z: 0)

    func adding(_ other: Float3) -> Float3 {
        Float3(x: x + other.x, y: y + other.y, z: z + other.z)
    }

    func subtracting(_ other: Float3) -> Float3 {
        Float3(x: x - other.x, y: y - other.y, z: z - other.z)
    }

    func scaled(by scalar: Float) -> Float3 {
        Float3(x: x * scalar, y: y * scalar, z: z * scalar)
    }

    var lengthSquared: Float {
        x * x + y * y + z * z
    }

    var length: Float {
        lengthSquared.squareRoot()
    }

    var normalized: Float3 {
        let len = length
        guard len > 0 else { return .zero }
        return Float3(x: x / len, y: y / len, z: z / len)
    }

    func distance(to other: Float3) -> Float {
        subtracting(other).length
    }

    /// Snaps a floating point coordinate to the nearest integer voxel grid cell.
    var snappedToGrid: Int3 {
        Int3(x: Int(x.rounded()), y: Int(y.rounded()), z: Int(z.rounded()))
    }
}
