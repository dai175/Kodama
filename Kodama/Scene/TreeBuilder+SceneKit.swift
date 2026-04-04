//
//  TreeBuilder+SceneKit.swift
//  Kodama
//

import SceneKit
import SwiftUI
import UIKit

// MARK: - SCNNode Construction

extension TreeBuilder {
    nonisolated static func buildSCNNodes(from blocks: [VoxelBlockData]) -> SCNNode {
        let root = SCNNode()
        root.name = "treeRoot"

        var geometryCache: [String: SCNGeometry] = [:]

        for block in blocks {
            let geometry = cachedGeometry(for: block.colorHex, cache: &geometryCache)
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(
                Float(block.pos.x) * VoxelConstants.renderScale,
                Float(block.pos.y) * VoxelConstants.renderScale,
                Float(block.pos.z) * VoxelConstants.renderScale
            )
            root.addChildNode(node)
        }

        return root
    }

    // MARK: - Geometry Cache

    nonisolated private static func cachedGeometry(
        for colorHex: String,
        cache: inout [String: SCNGeometry]
    ) -> SCNGeometry {
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

    nonisolated convenience init(hex: String) {
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
