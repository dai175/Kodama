//
//  TreeViewModel.swift
//  Kodama
//

import Foundation
import SwiftData

// MARK: - TreeViewModel

@Observable
final class TreeViewModel {
    // MARK: Internal

    private(set) var blocks: [VoxelBlockData] = []
    private(set) var currentTree: BonsaiTree?

    var isFirstLaunch: Bool {
        currentTree == nil
    }

    func loadOrCreateTree(context: ModelContext) {
        let descriptor = FetchDescriptor<BonsaiTree>()
        let trees = (try? context.fetch(descriptor)) ?? []

        if let existing = trees.first {
            currentTree = existing
            blocks = existing.blocks.map { voxelBlockToData($0) }
        } else {
            let seed = Int.random(in: 1 ... 999_999)
            let tree = BonsaiTree(seed: seed)
            context.insert(tree)

            let saplingBlocks = TreeBuilder.buildSapling(seed: UInt64(seed))
            for blockData in saplingBlocks {
                let voxelBlock = VoxelBlock(
                    x: blockData.x,
                    y: blockData.y,
                    z: blockData.z,
                    blockType: blockData.blockType,
                    colorHex: blockData.colorHex,
                    source: .autonomous
                )
                voxelBlock.tree = tree
                context.insert(voxelBlock)
            }

            tree.totalBlocks = saplingBlocks.count
            try? context.save()

            currentTree = tree
            blocks = saplingBlocks
        }
    }

    // MARK: Private

    private func voxelBlockToData(_ block: VoxelBlock) -> VoxelBlockData {
        VoxelBlockData(
            x: block.x,
            y: block.y,
            z: block.z,
            blockType: block.blockType,
            colorHex: block.colorHex,
            parentIndex: nil
        )
    }
}
