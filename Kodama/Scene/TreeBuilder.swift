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

// swiftlint:disable type_body_length
enum TreeBuilder {
    private struct TrunkLayout {
        let pathIndices: [Int]

        var topIndex: Int {
            pathIndices[pathIndices.count - 1]
        }
    }

    enum GrowthStage: Equatable {
        case sapling
        case young
        case mature
    }

    private struct StageProfile {
        let branchCountRange: ClosedRange<Int>
        let branchLengthRange: ClosedRange<Int>
        let branchStartHeightBias: Int
        let intermediateFoliageDensity: FoliageDensity
        let terminalFoliageDensity: FoliageDensity
        let crownDensity: FoliageDensity
        let prefersOuterCanopy: Bool
        let secondaryBranchChance: UInt64
        let canopyOpenSlots: Int
        let canopyLiftChance: UInt64
    }

    // MARK: - Color Palettes

    static let trunkColors = ["#4A3520", "#3D2E1C", "#553D28"]
    static let branchColors = ["#5A4530", "#4D3B28"]
    static let leafColors = ["#7AB648", "#5A9E3A", "#68B040"]

    nonisolated static func growthStage(for blocks: [VoxelBlockData]) -> GrowthStage {
        let structuralCount = blocks.count(where: { $0.blockType == .trunk || $0.blockType == .branch })
        let foliageCount = blocks.count(where: { $0.blockType == .leaf || $0.blockType == .flower })
        let heightInBlocks = Int((blocks.map(\.y).max() ?? 0) / VoxelConstants.blockSize)

        if structuralCount < 16 || heightInBlocks <= 6 {
            return .sapling
        }
        if structuralCount < 28 || foliageCount < 18 {
            return .young
        }
        return .mature
    }

    private static func stageProfile(for stage: GrowthStage) -> StageProfile {
        switch stage {
        case .sapling:
            StageProfile(
                branchCountRange: 2 ... 2,
                branchLengthRange: 5 ... 6,
                branchStartHeightBias: 0,
                intermediateFoliageDensity: .barelyThere,
                terminalFoliageDensity: .sparse,
                crownDensity: .sparse,
                prefersOuterCanopy: false,
                secondaryBranchChance: 0,
                canopyOpenSlots: 0,
                canopyLiftChance: 0
            )
        case .young:
            StageProfile(
                branchCountRange: 2 ... 3,
                branchLengthRange: 5 ... 7,
                branchStartHeightBias: 1,
                intermediateFoliageDensity: .sparse,
                terminalFoliageDensity: .medium,
                crownDensity: .medium,
                prefersOuterCanopy: false,
                secondaryBranchChance: 3,
                canopyOpenSlots: 0,
                canopyLiftChance: 7
            )
        case .mature:
            StageProfile(
                branchCountRange: 3 ... 3,
                branchLengthRange: 6 ... 8,
                branchStartHeightBias: 1,
                intermediateFoliageDensity: .medium,
                terminalFoliageDensity: .lush,
                crownDensity: .medium,
                prefersOuterCanopy: true,
                secondaryBranchChance: 2,
                canopyOpenSlots: 1,
                canopyLiftChance: 5
            )
        }
    }

    // MARK: - Sapling Generation

    static func buildSapling(seed: UInt64) -> [VoxelBlockData] {
        var rng = SeededRandom(seed: seed)
        var blocks: [VoxelBlockData] = []
        var occupiedPositions: Set<PositionKey> = []
        let profile = stageProfile(for: .sapling)

        let trunkLayout = buildTrunk(
            blocks: &blocks,
            occupiedPositions: &occupiedPositions,
            rng: &rng
        )
        buildBranches(
            blocks: &blocks,
            occupiedPositions: &occupiedPositions,
            rng: &rng,
            trunkLayout: trunkLayout,
            profile: profile
        )
        buildCrownLeaf(
            blocks: &blocks,
            occupiedPositions: &occupiedPositions,
            rng: &rng,
            topIndex: trunkLayout.topIndex,
            density: profile.crownDensity
        )

        return blocks
    }

    private static func buildTrunk(
        blocks: inout [VoxelBlockData],
        occupiedPositions: inout Set<PositionKey>,
        rng: inout SeededRandom
    ) -> TrunkLayout {
        let blockSize = VoxelConstants.blockSize
        let height = 5 + Int(rng.next() % 2)
        let bendDirections = shuffledDirections(using: &rng)
        let bendStart = 2 + Int(rng.next() % 2)
        let secondBendStart = bendStart + 1 + Int(rng.next() % 2)

        var currentX: Float = 0
        var currentZ: Float = 0
        var pathIndices: [Int] = []

        for yIdx in 0 ..< height {
            let parentIdx = yIdx > 0 ? blocks.count - 1 : nil
            if yIdx == bendStart {
                currentX += bendDirections[0].0
                currentZ += bendDirections[0].1
            } else if yIdx == secondBendStart {
                currentX += bendDirections[1].0
                currentZ += bendDirections[1].1
            }
            let color = trunkColors[Int(rng.next() % UInt64(trunkColors.count))]
            let block = VoxelBlockData(
                x: currentX,
                y: Float(yIdx) * blockSize,
                z: currentZ,
                blockType: .trunk,
                colorHex: color,
                parentIndex: parentIdx
            )
            blocks.append(block)
            occupiedPositions.insert(block.positionKey)
            pathIndices.append(blocks.count - 1)

            if yIdx == 0 {
                addTrunkSupports(
                    around: block,
                    parentIndex: blocks.count - 1,
                    directions: Array(bendDirections.prefix(2)),
                    blocks: &blocks,
                    occupiedPositions: &occupiedPositions,
                    rng: &rng
                )
            }
        }

        return TrunkLayout(pathIndices: pathIndices)
    }

    private static func buildBranches(
        blocks: inout [VoxelBlockData],
        occupiedPositions: inout Set<PositionKey>,
        rng: inout SeededRandom,
        trunkLayout: TrunkLayout,
        profile: StageProfile
    ) {
        let blockSize = VoxelConstants.blockSize
        let startRange = max(1, (trunkLayout.pathIndices.count / 2) + profile.branchStartHeightBias)
        var availableDirections = shuffledDirections(using: &rng)
        let branchCount = min(randomInt(in: profile.branchCountRange, using: &rng), availableDirections.count)

        for branchIndex in 0 ..< branchCount {
            let dir = availableDirections.removeFirst()
            let branchColor = branchColors[Int(rng.next() % UInt64(branchColors.count))]
            let branchLength = randomInt(in: profile.branchLengthRange, using: &rng)
            let trunkPathIndex = min(
                startRange + branchIndex + Int(rng.next() % 2),
                trunkLayout.pathIndices.count - 1
            )
            let originParentIdx = trunkLayout.pathIndices[trunkPathIndex]
            let lateralDirection = availableDirections.first ?? (-dir.1, dir.0)

            var curX = blocks[originParentIdx].x
            var curY = blocks[originParentIdx].y
            var curZ = blocks[originParentIdx].z
            var prevIdx = originParentIdx

            for step in 0 ..< branchLength {
                let movement: (Float, Float, Float) = switch step {
                case 0:
                    (dir.0, 0, dir.1)
                case 1:
                    (0, blockSize, 0)
                case 2:
                    (dir.0, 0, dir.1)
                default:
                    step.isMultiple(of: 2)
                        ? (0, blockSize, 0)
                        : (lateralDirection.0, 0, lateralDirection.1)
                }
                curX += movement.0
                curY += movement.1
                curZ += movement.2

                let block = VoxelBlockData(
                    x: curX,
                    y: curY,
                    z: curZ,
                    blockType: .branch,
                    colorHex: branchColor,
                    parentIndex: prevIdx
                )
                guard insert(block, into: &blocks, occupiedPositions: &occupiedPositions) else { continue }
                prevIdx = blocks.count - 1

                addIntermediateFoliage(
                    around: prevIdx,
                    branchDirection: movement.1 > 0 ? dir : (movement.0, movement.2),
                    blocks: &blocks,
                    occupiedPositions: &occupiedPositions,
                    rng: &rng,
                    density: step == branchLength - 1 ? profile.terminalFoliageDensity : profile
                        .intermediateFoliageDensity,
                    upwardBias: step >= branchLength - 2,
                    isTerminal: false,
                    profile: profile
                )
            }

            maybeAddSecondaryBranch(
                from: prevIdx,
                primaryDirection: dir,
                profile: profile,
                blocks: &blocks,
                occupiedPositions: &occupiedPositions,
                rng: &rng
            )
            buildBranchLeaves(
                blocks: &blocks,
                occupiedPositions: &occupiedPositions,
                rng: &rng,
                topIndex: prevIdx,
                branchDirection: dir,
                density: profile.terminalFoliageDensity,
                profile: profile
            )
        }
    }

    private static func buildBranchLeaves(
        blocks: inout [VoxelBlockData],
        occupiedPositions: inout Set<PositionKey>,
        rng: inout SeededRandom,
        topIndex: Int,
        branchDirection: (Float, Float),
        density: FoliageDensity,
        profile: StageProfile
    ) {
        addIntermediateFoliage(
            around: topIndex,
            branchDirection: branchDirection,
            blocks: &blocks,
            occupiedPositions: &occupiedPositions,
            rng: &rng,
            density: density,
            upwardBias: true,
            isTerminal: true,
            profile: profile
        )
    }

    private enum FoliageDensity {
        case barelyThere
        case sparse
        case medium
        case lush
    }

    // swiftlint:disable:next function_parameter_count
    private static func addIntermediateFoliage(
        around index: Int,
        branchDirection: (Float, Float),
        blocks: inout [VoxelBlockData],
        occupiedPositions: inout Set<PositionKey>,
        rng: inout SeededRandom,
        density: FoliageDensity,
        upwardBias: Bool,
        isTerminal: Bool,
        profile: StageProfile
    ) {
        let blockSize = VoxelConstants.blockSize
        let anchor = blocks[index]
        let lateralDirection = (-branchDirection.1, branchDirection.0)

        if density == .barelyThere, !isTerminal {
            return
        }
        if density == .sparse, !isTerminal, !rng.next().isMultiple(of: 5) {
            return
        }

        var candidateOffsets: [(Float, Float, Float)] = [
            (0, blockSize, 0),
            (branchDirection.0, 0, branchDirection.1),
            (lateralDirection.0, 0, lateralDirection.1),
            (-lateralDirection.0, 0, -lateralDirection.1),
            (-branchDirection.0, 0, -branchDirection.1)
        ]
        if upwardBias {
            let upwardOffsets: [(Float, Float, Float)] = [
                (0, blockSize, 0),
                (branchDirection.0, 0, branchDirection.1),
                (lateralDirection.0, 0, lateralDirection.1)
            ]
            candidateOffsets.append(contentsOf: upwardOffsets)
        }
        if isTerminal {
            let terminalOffsets: [(Float, Float, Float)] = [
                (branchDirection.0, blockSize, branchDirection.1),
                (lateralDirection.0, blockSize, lateralDirection.1),
                (-lateralDirection.0, blockSize, -lateralDirection.1)
            ]
            candidateOffsets.append(contentsOf: terminalOffsets)
        }
        if profile.prefersOuterCanopy {
            candidateOffsets.removeAll { offset in
                offset.0 == -branchDirection.0 && offset.2 == -branchDirection.1 && offset.1 == 0
            }
        }
        let clusterSize = if isTerminal {
            switch density {
            case .lush:
                4
            case .medium:
                2 + Int(rng.next() % 2)
            case .sparse:
                2
            case .barelyThere:
                1
            }
        } else if upwardBias {
            density == .medium || density == .lush ? 1 + Int(rng.next() % 2) : 1
        } else {
            1
        }

        let orderedOffsets = orderedFoliageOffsets(
            candidateOffsets,
            prefersOuterCanopy: profile.prefersOuterCanopy,
            using: &rng
        )
        let filteredOffsets = applyCanopyOpenSlots(
            to: orderedOffsets,
            openSlots: isTerminal ? profile.canopyOpenSlots : min(profile.canopyOpenSlots, 1),
            using: &rng
        )

        for offset in filteredOffsets.prefix(clusterSize) {
            let leafColor = leafColors[Int(rng.next() % UInt64(leafColors.count))]
            let adjustedOffset = liftedCanopyOffset(
                from: offset,
                blockSize: blockSize,
                shouldLift: profile.canopyLiftChance > 0 && rng.next() % profile.canopyLiftChance == 0,
                prefersOuterCanopy: profile.prefersOuterCanopy
            )
            let block = VoxelBlockData(
                x: anchor.x + adjustedOffset.0,
                y: anchor.y + adjustedOffset.1,
                z: anchor.z + adjustedOffset.2,
                blockType: .leaf,
                colorHex: leafColor,
                parentIndex: index
            )
            _ = insert(block, into: &blocks, occupiedPositions: &occupiedPositions)
        }
    }

    private static func buildCrownLeaf(
        blocks: inout [VoxelBlockData],
        occupiedPositions: inout Set<PositionKey>,
        rng: inout SeededRandom,
        topIndex: Int,
        density: FoliageDensity
    ) {
        let crownProfile = stageProfile(for: .sapling)
        buildBranchLeaves(
            blocks: &blocks,
            occupiedPositions: &occupiedPositions,
            rng: &rng,
            topIndex: topIndex,
            branchDirection: (0, VoxelConstants.blockSize),
            density: density,
            profile: crownProfile
        )
    }

    private static func maybeAddSecondaryBranch(
        from tipIndex: Int,
        primaryDirection: (Float, Float),
        profile: StageProfile,
        blocks: inout [VoxelBlockData],
        occupiedPositions: inout Set<PositionKey>,
        rng: inout SeededRandom
    ) {
        guard profile.secondaryBranchChance > 0, rng.next() % profile.secondaryBranchChance == 0 else { return }

        let blockSize = VoxelConstants.blockSize
        let lateralDirection = (primaryDirection.1, -primaryDirection.0)
        let secondaryDirection = rng.next().isMultiple(of: 2) ? lateralDirection : (
            -lateralDirection.0,
            -lateralDirection.1
        )
        let branchColor = branchColors[Int(rng.next() % UInt64(branchColors.count))]
        var parentIndex = tipIndex

        let steps = profile.prefersOuterCanopy ? 2 : 1
        for step in 0 ..< steps {
            let offset: (Float, Float, Float) = step == 0
                ? (secondaryDirection.0, 0, secondaryDirection.1)
                : (0, blockSize, 0)
            let block = VoxelBlockData(
                x: blocks[parentIndex].x + offset.0,
                y: blocks[parentIndex].y + offset.1,
                z: blocks[parentIndex].z + offset.2,
                blockType: .branch,
                colorHex: branchColor,
                parentIndex: parentIndex
            )
            guard insert(block, into: &blocks, occupiedPositions: &occupiedPositions) else { continue }
            parentIndex = blocks.count - 1
        }

        addIntermediateFoliage(
            around: parentIndex,
            branchDirection: secondaryDirection,
            blocks: &blocks,
            occupiedPositions: &occupiedPositions,
            rng: &rng,
            density: profile.terminalFoliageDensity,
            upwardBias: true,
            isTerminal: true,
            profile: profile
        )
    }

    private static func orderedFoliageOffsets(
        _ offsets: [(Float, Float, Float)],
        prefersOuterCanopy: Bool,
        using rng: inout SeededRandom
    ) -> [(Float, Float, Float)] {
        let shuffled = offsets.shuffled(using: &rng)
        guard prefersOuterCanopy else { return shuffled }

        return shuffled.sorted { lhs, rhs in
            canopyPriority(of: lhs) > canopyPriority(of: rhs)
        }
    }

    private static func applyCanopyOpenSlots(
        to offsets: [(Float, Float, Float)],
        openSlots: Int,
        using rng: inout SeededRandom
    ) -> [(Float, Float, Float)] {
        guard openSlots > 0, offsets.count > 3 else { return offsets }

        var filteredOffsets = offsets
        for _ in 0 ..< openSlots where filteredOffsets.count > 3 {
            let removeIndex = 1 + Int(rng.next() % UInt64(filteredOffsets.count - 1))
            filteredOffsets.remove(at: removeIndex)
        }
        return filteredOffsets
    }

    private static func liftedCanopyOffset(
        from offset: (Float, Float, Float),
        blockSize: Float,
        shouldLift: Bool,
        prefersOuterCanopy: Bool
    ) -> (Float, Float, Float) {
        guard shouldLift else { return offset }
        guard prefersOuterCanopy || offset.1 == 0 else { return offset }
        return (offset.0, max(offset.1, blockSize), offset.2)
    }

    private static func canopyPriority(of offset: (Float, Float, Float)) -> Int {
        var score = 0
        if offset.1 > 0 { score += 3 }
        if abs(offset.0) + abs(offset.2) > VoxelConstants.halfBlock { score += 2 }
        if offset.0 != 0, offset.2 != 0 { score += 1 }
        return score
    }

    private static func addTrunkSupports(
        around anchor: VoxelBlockData,
        parentIndex: Int,
        directions: [(Float, Float)],
        blocks: inout [VoxelBlockData],
        occupiedPositions: inout Set<PositionKey>,
        rng: inout SeededRandom
    ) {
        let supportCount = 1 + Int(rng.next() % 2)

        for direction in directions.prefix(supportCount) {
            let block = VoxelBlockData(
                x: anchor.x + direction.0,
                y: anchor.y,
                z: anchor.z + direction.1,
                blockType: .trunk,
                colorHex: trunkColors[Int(rng.next() % UInt64(trunkColors.count))],
                parentIndex: parentIndex
            )
            _ = insert(block, into: &blocks, occupiedPositions: &occupiedPositions)
        }
    }

    private static func shuffledDirections(using rng: inout SeededRandom) -> [(Float, Float)] {
        let blockSize = VoxelConstants.blockSize
        let directions: [(Float, Float)] = [
            (blockSize, 0), (-blockSize, 0), (0, blockSize), (0, -blockSize)
        ]
        return directions.shuffled(using: &rng)
    }

    private static func randomInt(in range: ClosedRange<Int>, using rng: inout SeededRandom) -> Int {
        let width = range.upperBound - range.lowerBound + 1
        return range.lowerBound + Int(rng.next() % UInt64(width))
    }

    private static func insert(
        _ block: VoxelBlockData,
        into blocks: inout [VoxelBlockData],
        occupiedPositions: inout Set<PositionKey>
    ) -> Bool {
        guard !occupiedPositions.contains(block.positionKey) else { return false }
        blocks.append(block)
        occupiedPositions.insert(block.positionKey)
        return true
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

// swiftlint:enable type_body_length

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
