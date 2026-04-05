//
//  VoxelRasterizer.swift
//  Kodama
//

import Foundation

// MARK: - Snapshots

/// Immutable snapshot of a `BranchSegment` for use in `nonisolated` contexts
/// (the rasterizer and growth engine run off the main actor).
nonisolated struct SegmentSnapshot: Sendable {
    let id: UUID
    let kind: BranchKind
    let start: Float3
    let end: Float3
    let thickness: Float
    let colorHex: String
    let parentID: UUID?
    let createdAt: Date
}

/// Immutable snapshot of a `LeafCluster`.
nonisolated struct LeafClusterSnapshot: Sendable {
    let id: UUID
    let segmentID: UUID?
    let center: Float3
    let radius: Float
    let density: Float
    let colorHex: String
    let scatterSeed: Int64
}

// MARK: - VoxelRasterizer

/// Converts the vector tree skeleton into a flat array of voxel blocks.
///
/// Segments are rasterized first (so their wood voxels form the occupation map),
/// then leaf clusters scatter on top of / around the wood while respecting the
/// "no voxel directly below a branch" rule — i.e. a leaf candidate is dropped
/// if the cell immediately above it (y + 1) is wood.
nonisolated enum VoxelRasterizer {
    static func rasterize(
        segments: [SegmentSnapshot],
        leafClusters: [LeafClusterSnapshot]
    ) -> [VoxelBlockData] {
        var occupied: [Int3: BlockType] = [:]
        var result: [VoxelBlockData] = []

        // Sort segments deterministically so SwiftData fetch order and the
        // insertion order inside the growth engine cannot change the output.
        // Trunk segments are processed before branches so the trunk-overrides-
        // branch rule below behaves consistently.
        let sortedSegments = segments.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind == .trunk
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        for segment in sortedSegments {
            rasterize(segment: segment, occupied: &occupied, into: &result)
        }

        // Sort clusters deterministically (by id) so output is stable.
        let sortedClusters = leafClusters.sorted { $0.id.uuidString < $1.id.uuidString }
        for cluster in sortedClusters {
            rasterize(cluster: cluster, occupied: &occupied, into: &result)
        }

        return result
    }

    // MARK: - Segment Rasterization

    nonisolated private static func rasterize(
        segment: SegmentSnapshot,
        occupied: inout [Int3: BlockType],
        into result: inout [VoxelBlockData]
    ) {
        let thick = max(segment.thickness, 0.5)
        let (minCell, maxCell) = aabb(around: segment, padding: thick)
        let blockType: BlockType = segment.kind == .trunk ? .trunk : .branch

        for x in minCell.x ... maxCell.x {
            for y in minCell.y ... maxCell.y {
                for z in minCell.z ... maxCell.z {
                    let cellCenter = Float3(x: Float(x), y: Float(y), z: Float(z))
                    let dist = distanceFromPointToSegment(
                        point: cellCenter,
                        start: segment.start,
                        end: segment.end
                    )
                    guard dist <= thick else { continue }
                    let pos = Int3(x: x, y: y, z: z)
                    guard pos.y >= 0 else { continue }
                    // First-write wins. Because rasterize() sorts trunks ahead
                    // of branches, any collision between trunk and branch at
                    // the same cell correctly resolves to trunk.
                    if occupied[pos] != nil { continue }
                    occupied[pos] = blockType
                    result.append(VoxelBlockData(
                        pos: pos,
                        blockType: blockType,
                        colorHex: segment.colorHex,
                        parentID: nil
                    ))
                }
            }
        }
    }

    // MARK: - Cluster Rasterization

    nonisolated private static func rasterize(
        cluster: LeafClusterSnapshot,
        occupied: inout [Int3: BlockType],
        into result: inout [VoxelBlockData]
    ) {
        guard cluster.radius > 0, cluster.density > 0 else { return }
        let radius = cluster.radius
        let minX = Int(floor(cluster.center.x - radius))
        let maxX = Int(ceil(cluster.center.x + radius))
        let minY = Int(floor(cluster.center.y - radius))
        let maxY = Int(ceil(cluster.center.y + radius))
        let minZ = Int(floor(cluster.center.z - radius))
        let maxZ = Int(ceil(cluster.center.z + radius))

        var rng = SeededRandom(seed: UInt64(bitPattern: cluster.scatterSeed))
        let density = max(0, min(cluster.density, 1))
        let threshold = UInt64(density * 10_000)

        for x in minX ... maxX {
            for y in minY ... maxY {
                for z in minZ ... maxZ {
                    let pos = Int3(x: x, y: y, z: z)
                    guard pos.y >= 0 else { continue }
                    let cellCenter = Float3(x: Float(x), y: Float(y), z: Float(z))
                    let dist = cellCenter.distance(to: cluster.center)
                    guard dist <= radius else { continue }

                    // Consume rng for every candidate cell to keep placement
                    // stable regardless of which cells are excluded.
                    let roll = rng.next() % 10_000

                    // Skip cells already occupied by wood.
                    if occupied[pos] != nil { continue }

                    // Exclude voxels directly beneath a branch (one block).
                    let above = Int3(x: x, y: y + 1, z: z)
                    if let aboveType = occupied[above], aboveType == .trunk || aboveType == .branch {
                        continue
                    }

                    guard roll < threshold else { continue }

                    occupied[pos] = .leaf
                    result.append(VoxelBlockData(
                        pos: pos,
                        blockType: .leaf,
                        colorHex: cluster.colorHex,
                        parentID: nil
                    ))
                }
            }
        }
    }

    // MARK: - Geometry Helpers

    nonisolated private static func aabb(
        around segment: SegmentSnapshot,
        padding: Float
    ) -> (min: Int3, max: Int3) {
        let minX = min(segment.start.x, segment.end.x) - padding
        let maxX = max(segment.start.x, segment.end.x) + padding
        let minY = min(segment.start.y, segment.end.y) - padding
        let maxY = max(segment.start.y, segment.end.y) + padding
        let minZ = min(segment.start.z, segment.end.z) - padding
        let maxZ = max(segment.start.z, segment.end.z) + padding
        return (
            Int3(x: Int(floor(minX)), y: Int(floor(minY)), z: Int(floor(minZ))),
            Int3(x: Int(ceil(maxX)), y: Int(ceil(maxY)), z: Int(ceil(maxZ)))
        )
    }

    /// Shortest distance from `point` to the line segment `start`–`end`.
    nonisolated static func distanceFromPointToSegment(
        point: Float3,
        start: Float3,
        end: Float3
    ) -> Float {
        let ab = end.subtracting(start)
        let ap = point.subtracting(start)
        let abLenSq = ab.lengthSquared
        guard abLenSq > 1e-6 else { return point.distance(to: start) }
        let dot = ap.x * ab.x + ap.y * ab.y + ap.z * ab.z
        let t = max(0, min(1, dot / abLenSq))
        let closest = start.adding(ab.scaled(by: t))
        return point.distance(to: closest)
    }
}
