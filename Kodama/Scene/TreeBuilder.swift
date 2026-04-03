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
        abs(x - ox) < 0.5 && abs(y - oy) < 0.5 && abs(z - oz) < 0.5
    }
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

        buildTrunk(blocks: &blocks, rng: &rng)
        buildBranches(blocks: &blocks, rng: &rng, topIndex: 3)
        buildCrownLeaf(blocks: &blocks, rng: &rng, topIndex: 3)

        return blocks
    }

    private static func buildTrunk(blocks: inout [VoxelBlockData], rng: inout SeededRandom) {
        for y in 0 ..< 4 {
            let color = trunkColors[Int(rng.next() % UInt64(trunkColors.count))]
            blocks.append(VoxelBlockData(
                x: 0,
                y: Float(y),
                z: 0,
                blockType: .trunk,
                colorHex: color,
                parentIndex: y > 0 ? y - 1 : nil
            ))
        }
    }

    private static func buildBranches(blocks: inout [VoxelBlockData], rng: inout SeededRandom, topIndex: Int) {
        let branchCount = Int(rng.next() % 2) + 1
        let directions: [(Float, Float)] = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        var usedDirections: Set<Int> = []

        for _ in 0 ..< branchCount {
            var dirIndex: Int
            repeat {
                dirIndex = Int(rng.next() % UInt64(directions.count))
            } while usedDirections.contains(dirIndex) && usedDirections.count < directions.count
            usedDirections.insert(dirIndex)

            let dir = directions[dirIndex]
            let branchColor = branchColors[Int(rng.next() % UInt64(branchColors.count))]
            let branchIndex = blocks.count

            blocks.append(VoxelBlockData(
                x: dir.0, y: Float(topIndex), z: dir.1,
                blockType: .branch, colorHex: branchColor, parentIndex: topIndex
            ))

            buildBranchLeaves(blocks: &blocks, rng: &rng, dir: dir, topIndex: topIndex, branchIndex: branchIndex)
        }
    }

    private static func buildBranchLeaves(
        blocks: inout [VoxelBlockData],
        rng: inout SeededRandom,
        dir: (Float, Float),
        topIndex: Int,
        branchIndex: Int
    ) {
        let leafColor = leafColors[Int(rng.next() % UInt64(leafColors.count))]
        blocks.append(VoxelBlockData(
            x: dir.0, y: Float(topIndex + 1), z: dir.1,
            blockType: .leaf, colorHex: leafColor, parentIndex: branchIndex
        ))

        // 50% chance of a second leaf adjacent
        if rng.next() % 2 == 0 {
            let secondLeafColor = leafColors[Int(rng.next() % UInt64(leafColors.count))]
            let offsetX = dir.0 == 0 ? Float(Int(rng.next() % 2) == 0 ? 1 : -1) : dir.0
            let offsetZ = dir.1 == 0 ? Float(Int(rng.next() % 2) == 0 ? 1 : -1) : dir.1
            blocks.append(VoxelBlockData(
                x: offsetX, y: Float(topIndex + 1), z: offsetZ,
                blockType: .leaf, colorHex: secondLeafColor, parentIndex: branchIndex
            ))
        }
    }

    private static func buildCrownLeaf(blocks: inout [VoxelBlockData], rng: inout SeededRandom, topIndex: Int) {
        let crownColor = leafColors[Int(rng.next() % UInt64(leafColors.count))]
        blocks.append(VoxelBlockData(
            x: 0, y: Float(topIndex + 1), z: 0,
            blockType: .leaf, colorHex: crownColor, parentIndex: topIndex
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

        let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.02)
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
