//
//  VoxelConstants.swift
//  Kodama
//

import CoreGraphics

enum VoxelConstants {
    static let blockSize: Float = 0.5
    static let halfBlock: Float = blockSize / 2
    static let cgBlockSize = CGFloat(blockSize)
    static let chamferRadius: CGFloat = cgBlockSize * 0.04
    static let maxBlocks = 5000
    static let outerTrunkColors = ["#6B5035", "#7A5C40", "#5E4830"]
}
