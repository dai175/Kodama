//
//  TreeBuilder.swift
//  Kodama
//

import SceneKit
import SwiftUI
import UIKit

// MARK: - VoxelBlockData

struct VoxelBlockData {
    let x: Float
    let y: Float
    let z: Float
    let blockType: BlockType
    let colorHex: String
    let parentIndex: Int?

    func overlaps(x ox: Float, y oy: Float, z oz: Float) -> Bool {
        abs(x - ox) < VoxelConstants.halfBlock && abs(y - oy) < VoxelConstants.halfBlock && abs(z - oz) < VoxelConstants
            .halfBlock
    }

    var positionKey: PositionKey {
        PositionKey(x: x, y: y, z: z)
    }
}

// MARK: - PositionKey

struct PositionKey: Hashable {
    let x: Float
    let y: Float
    let z: Float

    static let faceOffsets: [(Float, Float, Float)] = [
        (0, -VoxelConstants.blockSize, 0), (0, VoxelConstants.blockSize, 0),
        (VoxelConstants.blockSize, 0, 0), (-VoxelConstants.blockSize, 0, 0),
        (0, 0, VoxelConstants.blockSize), (0, 0, -VoxelConstants.blockSize)
    ]
}

// MARK: - SeededRandom

nonisolated struct SeededRandom: RandomNumberGenerator {
    // MARK: Internal

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    // MARK: Private

    private var state: UInt64

    // MARK: - Initialization

    init(seed: UInt64) {
        state = seed == 0 ? 1 : seed
    }
}

// MARK: - TreeBuilder

enum TreeBuilder {
    // MARK: - Color Palettes

    static let trunkColors = ["#4A3520", "#3D2E1C", "#553D28"]
    static let branchColors = ["#5A4530", "#4D3B28"]
    static let leafColors = ["#7AB648", "#5A9E3A", "#68B040"]

    // MARK: - Sapling Generation

    static func buildSapling(seed: UInt64) -> [VoxelBlockData] {
        var rng = SeededRandom(seed: seed)
        var blocks: [VoxelBlockData] = []

        let topCenterIndex = buildTrunk(blocks: &blocks, rng: &rng)
        buildBranches(blocks: &blocks, rng: &rng, topIndex: topCenterIndex)
        buildCrownLeaf(blocks: &blocks, rng: &rng, topIndex: topCenterIndex)

        return blocks
    }

    @discardableResult
    private static func buildTrunk(blocks: inout [VoxelBlockData], rng: inout SeededRandom) -> Int {
        let blockSize = VoxelConstants.blockSize

        // Radius per yIdx layer (in block-grid units)
        // yIdx 0-1: radius 2.5, yIdx 2-3: radius 1.5, yIdx 4-5: radius 1.0, yIdx 6-7: radius 0.0 (center only)
        let radii: [Float] = [2.5, 2.5, 1.5, 1.5, 1.0, 1.0, 0.0, 0.0]

        var topCenterIndex = 0

        for yIdx in 0 ..< 8 {
            let radius = radii[yIdx]
            let yWorld = Float(yIdx) * blockSize
            let iRadius = Int(ceil(radius))

            // Collect positions for this layer, sorted for deterministic ordering
            var layerPositions: [(bx: Int, bz: Int)] = []
            for bx in -iRadius ... iRadius {
                for bz in -iRadius ... iRadius where sqrt(Float(bx * bx + bz * bz)) <= radius {
                    layerPositions.append((bx, bz))
                }
            }
            layerPositions.sort { lhs, rhs in
                lhs.bx == rhs.bx ? lhs.bz < rhs.bz : lhs.bx < rhs.bx
            }

            for pos in layerPositions {
                let xWorld = Float(pos.bx) * blockSize
                let zWorld = Float(pos.bz) * blockSize

                var parentIdx: Int?
                if yIdx > 0 {
                    var bestDist = Float.greatestFiniteMagnitude
                    for (i, candidate) in blocks.enumerated() {
                        // Only consider blocks from the layer just below (yIdx-1)
                        let expectedY = Float(yIdx - 1) * blockSize
                        guard abs(candidate.y - expectedY) < 0.001 else { continue }
                        let dx = candidate.x - xWorld
                        let dz = candidate.z - zWorld
                        let dist = dx * dx + dz * dz
                        if dist < bestDist {
                            bestDist = dist
                            parentIdx = i
                        }
                    }
                }

                let color = trunkColors[Int(rng.next() % UInt64(trunkColors.count))]
                let idx = blocks.count

                blocks.append(VoxelBlockData(
                    x: xWorld,
                    y: yWorld,
                    z: zWorld,
                    blockType: .trunk,
                    colorHex: color,
                    parentIndex: parentIdx
                ))

                // Track the top center block (x=0, z=0 at highest yIdx)
                if pos.bx == 0, pos.bz == 0 {
                    topCenterIndex = idx
                }
            }
        }

        return topCenterIndex
    }

    private static func buildBranches(blocks: inout [VoxelBlockData], rng: inout SeededRandom, topIndex: Int) {
        let blockSize = VoxelConstants.blockSize
        let branchCount = Int(rng.next() % 3) + 2
        let directions: [(Float, Float)] = [
            (blockSize, 0), (-blockSize, 0), (0, blockSize), (0, -blockSize)
        ]
        var usedDirections: Set<Int> = []

        for _ in 0 ..< branchCount {
            var dirIndex: Int
            repeat {
                dirIndex = Int(rng.next() % UInt64(directions.count))
            } while usedDirections.contains(dirIndex) && usedDirections.count < directions.count
            usedDirections.insert(dirIndex)

            let dir = directions[dirIndex]
            let branchColor = branchColors[Int(rng.next() % UInt64(branchColors.count))]
            let branchLength = Int(rng.next() % 4) + 2

            // Choose branch origin: center column block at yIdx 5 or 6 (60-80% of trunk height)
            let originYIdx = 5 + Int(rng.next() % 2)
            let originY = Float(originYIdx) * blockSize

            // Find the center column block at originY as the branch origin parent
            var originParentIdx = topIndex
            for (i, candidate) in blocks.enumerated() {
                if abs(candidate.x) < 0.001, abs(candidate.z) < 0.001, abs(candidate.y - originY) < 0.001 {
                    originParentIdx = i
                    break
                }
            }

            // Build branch steps from trunk surface outward
            var curX = Float(0)
            var curY = originY
            var curZ = Float(0)
            var prevIdx = originParentIdx

            for step in 0 ..< branchLength {
                curX += dir.0
                curZ += dir.1
                // Add upward curve every other step
                if step % 2 == 1 {
                    curY += blockSize
                }

                // Reuse existing trunk block at this position to avoid z-fighting
                if let existingIdx = blocks.indices.first(where: {
                    abs(blocks[$0].x - curX) < 0.001 &&
                        abs(blocks[$0].y - curY) < 0.001 &&
                        abs(blocks[$0].z - curZ) < 0.001
                }) {
                    prevIdx = existingIdx
                    continue
                }

                let stepIdx = blocks.count
                blocks.append(VoxelBlockData(
                    x: curX,
                    y: curY,
                    z: curZ,
                    blockType: .branch,
                    colorHex: branchColor,
                    parentIndex: prevIdx
                ))
                prevIdx = stepIdx
            }

            buildBranchLeaves(blocks: &blocks, rng: &rng, dir: dir, topIndex: prevIdx)
        }
    }

    private static func buildBranchLeaves(
        blocks: inout [VoxelBlockData],
        rng: inout SeededRandom,
        dir: (Float, Float),
        topIndex: Int
    ) {
        let blockSize = VoxelConstants.blockSize
        let tipY = blocks[topIndex].y
        let tipX = blocks[topIndex].x
        let tipZ = blocks[topIndex].z

        let leafColor = leafColors[Int(rng.next() % UInt64(leafColors.count))]
        blocks.append(VoxelBlockData(
            x: tipX,
            y: tipY + blockSize,
            z: tipZ,
            blockType: .leaf,
            colorHex: leafColor,
            parentIndex: topIndex
        ))

        // 50% chance of a second leaf adjacent
        if rng.next() % 2 == 0 {
            let secondLeafColor = leafColors[Int(rng.next() % UInt64(leafColors.count))]
            let offsetX = dir.0 == 0 ? (Int(rng.next() % 2) == 0 ? blockSize : -blockSize) : dir.0
            let offsetZ = dir.1 == 0 ? (Int(rng.next() % 2) == 0 ? blockSize : -blockSize) : dir.1
            blocks.append(VoxelBlockData(
                x: tipX + offsetX,
                y: tipY + blockSize,
                z: tipZ + offsetZ,
                blockType: .leaf,
                colorHex: secondLeafColor,
                parentIndex: topIndex
            ))
        }
    }

    private static func buildCrownLeaf(blocks: inout [VoxelBlockData], rng: inout SeededRandom, topIndex: Int) {
        let crownColor = leafColors[Int(rng.next() % UInt64(leafColors.count))]
        blocks.append(VoxelBlockData(
            x: 0,
            y: blocks[topIndex].y + VoxelConstants.blockSize,
            z: 0,
            blockType: .leaf,
            colorHex: crownColor,
            parentIndex: topIndex
        ))
    }

    // MARK: - SCNNode Construction

    static func buildSCNNodes(from blocks: [VoxelBlockData]) -> SCNNode {
        let root = SCNNode()
        root.name = "treeRoot"

        var geometryCache: [String: SCNGeometry] = [:]

        for block in blocks {
            let geometry = cachedGeometry(for: block.colorHex, cache: &geometryCache)
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(block.x, block.y, block.z)
            root.addChildNode(node)
        }

        return root
    }

    // MARK: - Geometry Cache

    private static func cachedGeometry(for colorHex: String, cache: inout [String: SCNGeometry]) -> SCNGeometry {
        if let cached = cache[colorHex] {
            return cached
        }

        let box = SCNBox(
            width: VoxelConstants.cgBlockSize,
            height: VoxelConstants.cgBlockSize,
            length: VoxelConstants.cgBlockSize,
            chamferRadius: VoxelConstants.chamferRadius
        )
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(hex: colorHex)
        material.roughness.contents = 0.8
        box.materials = [material]

        cache[colorHex] = box
        return box
    }
}

// MARK: - Color Extension

extension Color {
    static let softWhite = Color(red: 232 / 255, green: 228 / 255, blue: 220 / 255)
}

// MARK: - UIColor Hex Extension

extension UIColor {
    static let darkForest = UIColor(red: 10 / 255, green: 26 / 255, blue: 18 / 255, alpha: 1)

    convenience init(hex: String) {
        let hexString = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard hexString.count == 6,
              hexString.allSatisfy(\.isHexDigit),
              let hexNumber = UInt64(hexString, radix: 16)
        else {
            assertionFailure("Invalid hex color string: \(hexString)")
            self.init(red: 0, green: 0, blue: 0, alpha: 1)
            return
        }
        let red = CGFloat((hexNumber & 0xFF0000) >> 16) / 255
        let green = CGFloat((hexNumber & 0x00FF00) >> 8) / 255
        let blue = CGFloat(hexNumber & 0x0000FF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}
