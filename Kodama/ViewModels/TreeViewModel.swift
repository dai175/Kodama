//
//  TreeViewModel.swift
//  Kodama
//

import Foundation
import SceneKit
import SwiftData

// MARK: - TreeViewModel

@MainActor
@Observable
final class TreeViewModel {
    struct StorageKey: Hashable {
        let position: Int3
    }

    // MARK: Internal

    var blocks: [VoxelBlockData] = []
    var currentTree: BonsaiTree?
    let engineSchemaVersion = 6
    let engineSchemaVersionKey = "kodama.engineSchemaVersion"

    var isFirstLaunch: Bool {
        currentTree == nil
    }
}

// MARK: - Block Data Helpers

extension TreeViewModel {
    func voxelBlockToData(_ block: VoxelBlock) -> VoxelBlockData {
        VoxelBlockData(
            id: block.id,
            pos: block.pos,
            blockType: block.blockType,
            colorHex: block.colorHex,
            parentID: block.parentBlockID
        )
    }
}
