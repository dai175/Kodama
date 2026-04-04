//
//  GrowthEngine+Conversion.swift
//  Kodama
//

import Foundation

extension GrowthEngine {
    // MARK: - Block↔Node Conversion

    nonisolated static func toGrowthNodes(_ blocks: [VoxelBlockData]) -> [GrowthNode] {
        let ids = nodeIDsByBlockID(blocks)
        return blocks.enumerated().map { index, block in
            GrowthNode(
                nodeID: index,
                blockID: block.id,
                pos: GridMapper.int3(from: block),
                layer: GridMapper.layer(for: block.blockType),
                blockType: block.blockType,
                parentNodeID: parentNodeID(for: block, nodeIDsByBlockID: ids)
            )
        }
    }

    nonisolated static func toVoxelBlocks(newNodes: [GrowthNode], allNodes: [GrowthNode]) -> [VoxelBlockData] {
        let blockIDsByNodeID = Dictionary(uniqueKeysWithValues: allNodes.map { ($0.nodeID, $0.blockID) })
        return newNodes.map { node in
            let parentID = node.parentNodeID.flatMap { blockIDsByNodeID[$0] }
            return VoxelBlockData(
                id: node.blockID,
                pos: node.pos,
                blockType: node.blockType,
                colorHex: blockColor(for: node.blockType),
                parentID: parentID
            )
        }
    }

    // MARK: - Private

    nonisolated private static func nodeIDsByBlockID(_ blocks: [VoxelBlockData]) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for (index, block) in blocks.enumerated() {
            result[block.id] = index
        }
        return result
    }

    nonisolated private static func parentNodeID(for block: VoxelBlockData, nodeIDsByBlockID: [UUID: Int]) -> Int? {
        guard let parentID = block.parentID else { return nil }
        return nodeIDsByBlockID[parentID]
    }

    nonisolated private static func blockColor(for blockType: BlockType) -> String {
        switch blockType {
        case .trunk:
            TreeBuilder.trunkColors.first ?? "#4A3520"
        case .branch:
            TreeBuilder.branchColors.first ?? "#5A4530"
        case .leaf:
            TreeBuilder.leafColors.first ?? "#7AB648"
        case .flower:
            SeasonalEngine.springFlowerColor
        case .moss:
            SeasonalEngine.summerMossColor
        case .snow:
            SeasonalEngine.snowColor
        }
    }
}
