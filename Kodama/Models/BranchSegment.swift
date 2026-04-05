//
//  BranchSegment.swift
//  Kodama
//

import Foundation
import SwiftData

// MARK: - BranchKind

nonisolated enum BranchKind: String, Codable {
    case trunk
    case branch
}

// MARK: - BranchSegment

/// A single line segment in the vector tree skeleton.
///
/// The skeleton is authoritative: voxels are generated from segments by the
/// `VoxelRasterizer` and cached in `BonsaiTree.blocks`.
@Model
final class BranchSegment {
    var id: UUID
    var kindRaw: String

    // Start / end in sub-voxel precision grid coordinates (Float3).
    var startX: Float
    var startY: Float
    var startZ: Float
    var endX: Float
    var endY: Float
    var endZ: Float

    /// Radius in voxel units. 0.5 ≈ single voxel wide; 1.0 ≈ 3-wide stem.
    var thickness: Float

    /// Used by the growth engine to determine thickness and age.
    var createdAt: Date

    /// Cached count of transitive children. Drives thickness scaling.
    var descendantCount: Int

    var colorHex: String

    // Self-referential parent/children — children are declared on the parent
    // via an inverse relationship below.
    var parent: BranchSegment?

    @Relationship(deleteRule: .nullify, inverse: \BranchSegment.parent)
    var children: [BranchSegment]

    var tree: BonsaiTree?

    // MARK: Computed

    var kind: BranchKind {
        get { BranchKind(rawValue: kindRaw) ?? .branch }
        set { kindRaw = newValue.rawValue }
    }

    var start: Float3 {
        Float3(x: startX, y: startY, z: startZ)
    }

    var end: Float3 {
        Float3(x: endX, y: endY, z: endZ)
    }

    var direction: Float3 {
        end.subtracting(start).normalized
    }

    var length: Float {
        end.subtracting(start).length
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        kind: BranchKind,
        start: Float3,
        end: Float3,
        thickness: Float,
        colorHex: String,
        createdAt: Date = Date(),
        parent: BranchSegment? = nil
    ) {
        self.id = id
        kindRaw = kind.rawValue
        startX = start.x
        startY = start.y
        startZ = start.z
        endX = end.x
        endY = end.y
        endZ = end.z
        self.thickness = thickness
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.parent = parent
        descendantCount = 0
        children = []
    }
}
