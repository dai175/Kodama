//
//  LeafCluster.swift
//  Kodama
//

import Foundation
import SwiftData

// MARK: - LeafCluster

/// A spherical cluster of leaves attached to a branch tip.
///
/// The rasterizer scatters voxels inside the sphere using `scatterSeed` for
/// deterministic, reproducible placement. Voxels directly below a branch are
/// excluded so the underside of the canopy doesn't lose all depth.
@Model
final class LeafCluster {
    var id: UUID

    // Center in sub-voxel precision grid coordinates.
    var centerX: Float
    var centerY: Float
    var centerZ: Float

    /// Radius of the cluster in voxel units.
    var radius: Float

    /// Probability [0, 1] that a candidate grid cell inside the sphere is filled.
    var density: Float

    var colorHex: String

    /// Deterministic seed for scatter placement. Stable across rasterizations.
    var scatterSeed: Int64

    var createdAt: Date

    var segment: BranchSegment?
    var tree: BonsaiTree?

    // MARK: Computed

    var center: Float3 {
        Float3(x: centerX, y: centerY, z: centerZ)
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        center: Float3,
        radius: Float,
        density: Float,
        colorHex: String,
        scatterSeed: Int64,
        createdAt: Date = Date(),
        segment: BranchSegment? = nil
    ) {
        self.id = id
        centerX = center.x
        centerY = center.y
        centerZ = center.z
        self.radius = radius
        self.density = density
        self.colorHex = colorHex
        self.scatterSeed = scatterSeed
        self.createdAt = createdAt
        self.segment = segment
    }
}
