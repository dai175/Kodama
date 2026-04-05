//
//  TreeBuilder.swift
//  Kodama
//

import Foundation

// MARK: - TreeBuilder

/// Legacy namespace retaining the color palettes, growth stage enum and the
/// SceneKit node construction used by the renderer. All voxel-first sapling
/// generation lives in `SkeletonBuilder` now.
nonisolated enum TreeBuilder {
    enum GrowthStage: Equatable {
        case sapling
        case young
        case mature
    }

    // MARK: - Color Palettes

    static let trunkColors = ["#4A3520", "#3D2E1C", "#553D28"]
    static let branchColors = ["#5A4530", "#4D3B28"]
    static let leafColors = ["#7AB648", "#5A9E3A", "#68B040"]
}
