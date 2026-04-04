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
        let height = 2 + Int(rng.next() % 2) // 2-3 blocks tall

        for yIdx in 0 ..< height {
            let parentIdx = yIdx > 0 ? blocks.count - 1 : nil
            let color = trunkColors[Int(rng.next() % UInt64(trunkColors.count))]
            blocks.append(VoxelBlockData(
                x: 0,
                y: Float(yIdx) * blockSize,
                z: 0,
                blockType: .trunk,
                colorHex: color,
                parentIndex: parentIdx
            ))
        }

        return blocks.count - 1
    }

    private static func buildBranches(blocks: inout [VoxelBlockData], rng: inout SeededRandom, topIndex: Int) {
        // 50% chance of a single short branch
        guard rng.next() % 2 == 0 else { return }

        let blockSize = VoxelConstants.blockSize
        let directions: [(Float, Float)] = [
            (blockSize, 0), (-blockSize, 0), (0, blockSize), (0, -blockSize)
        ]
        let dir = directions[Int(rng.next() % UInt64(directions.count))]
        let branchColor = branchColors[Int(rng.next() % UInt64(branchColors.count))]
        let branchLength = 1 + Int(rng.next() % 2) // 1-2 blocks

        // Branch origin: yIdx 1 (middle of a 2-3 block trunk)
        let originY = blockSize

        var originParentIdx = topIndex
        for (i, candidate) in blocks.enumerated() {
            if candidate.overlaps(x: 0, y: originY, z: 0) {
                originParentIdx = i
                break
            }
        }

        var curX = Float(0)
        var curY = originY
        var curZ = Float(0)
        var prevIdx = originParentIdx

        for step in 0 ..< branchLength {
            curX += dir.0
            curZ += dir.1
            // Second block curves upward
            if step == 1 {
                curY += blockSize
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

        buildBranchLeaves(blocks: &blocks, rng: &rng, topIndex: prevIdx)
    }

    private static func buildBranchLeaves(
        blocks: inout [VoxelBlockData],
        rng: inout SeededRandom,
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
