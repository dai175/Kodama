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

        assert(
            blocks.count == treeNode.childNodes.count,
            "Block count (\(blocks.count)) must match child node count (\(treeNode.childNodes.count))"
        )

        // Separate static (trunk/branch) and dynamic (leaf/flower/moss/snow) blocks
        // Use index-based matching — buildSCNNodes preserves block array order
        let staticNode = SCNNode()
        let dynamicNode = SCNNode()
        dynamicNode.name = "treeDynamic"

        for (block, child) in zip(blocks, treeNode.childNodes) {
            switch block.blockType {
            case .trunk, .branch:
                staticNode.addChildNode(child)
            case .leaf, .flower, .moss, .snow:
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

    // MARK: Private

    private var currentTreeNode: SCNNode?

    private func clearTree() {
        currentTreeNode?.removeFromParentNode()
        currentTreeNode = nil
    }

    // MARK: - Initialization

    init(bonsaiScene: BonsaiScene) {
        self.bonsaiScene = bonsaiScene
    }
}
