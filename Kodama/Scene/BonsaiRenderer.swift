//
//  BonsaiRenderer.swift
//  Kodama
//

import SceneKit

// MARK: - BonsaiRenderer

final class BonsaiRenderer {
    // MARK: Internal

    let bonsaiScene: BonsaiScene

    /// Clears the existing tree and renders a new one from the given blocks.
    func renderTree(from blocks: [VoxelBlockData]) {
        clearTree()

        let treeNode = TreeBuilder.buildSCNNodes(from: blocks)

        // Separate static (trunk/branch) and dynamic (leaf/flower/moss/snow) blocks
        let staticNode = SCNNode()
        let dynamicNode = SCNNode()
        dynamicNode.name = "treeDynamic"

        for child in treeNode.childNodes {
            // Determine block type by position matching
            let position = child.position
            let matchingBlock = blocks.first { block in
                block.x == position.x && block.y == position.y && block.z == position.z
            }

            if let block = matchingBlock, block.blockType == .trunk || block.blockType == .branch {
                staticNode.addChildNode(child)
            } else {
                dynamicNode.addChildNode(child)
            }
        }

        let rootNode = SCNNode()
        rootNode.name = "treeRoot"

        // Flatten static parts for performance
        if !staticNode.childNodes.isEmpty {
            let flattened = staticNode.flattenedClone()
            flattened.name = "treeStatic"
            rootNode.addChildNode(flattened)
        }

        if !dynamicNode.childNodes.isEmpty {
            rootNode.addChildNode(dynamicNode)
        }

        currentTreeNode = rootNode
        bonsaiScene.treeAnchor.addChildNode(rootNode)
    }

    /// Adds new blocks incrementally without rebuilding the entire tree.
    func addBlocks(_ blocks: [VoxelBlockData]) {
        guard let treeRoot = currentTreeNode else {
            renderTree(from: blocks)
            return
        }

        var geometryCache: [String: SCNGeometry] = [:]

        for block in blocks {
            let geometry = cachedGeometry(for: block.colorHex, cache: &geometryCache)
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(block.x, block.y, block.z)
            treeRoot.addChildNode(node)
        }
    }

    // MARK: Private

    private var currentTreeNode: SCNNode?

    private func clearTree() {
        currentTreeNode?.removeFromParentNode()
        currentTreeNode = nil
    }

    private func cachedGeometry(for colorHex: String, cache: inout [String: SCNGeometry]) -> SCNGeometry {
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

    // MARK: - Initialization

    init(bonsaiScene: BonsaiScene) {
        self.bonsaiScene = bonsaiScene
    }
}
