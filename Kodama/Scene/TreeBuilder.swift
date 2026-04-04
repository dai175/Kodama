//
//  TreeBuilder.swift
//  Kodama
//

import SceneKit
import SwiftUI
import UIKit

// MARK: - VoxelBlockData

nonisolated struct VoxelBlockData {
    let id: UUID
    let pos: Int3
    let blockType: BlockType
    let colorHex: String
    let parentID: UUID?

    init(
        id: UUID = UUID(),
        pos: Int3,
        blockType: BlockType,
        colorHex: String,
        parentID: UUID?
    ) {
        self.id = id
        self.pos = pos
        self.blockType = blockType
        self.colorHex = colorHex
        self.parentID = parentID
    }
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
nonisolated enum TreeBuilder {
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
        let heightInBlocks = blocks.map(\.pos.y).max() ?? 0

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
        var occupiedPositions: Set<Int3> = []
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
        occupiedPositions: inout Set<Int3>,
        rng: inout SeededRandom
    ) -> TrunkLayout {
        let height = 5 + Int(rng.next() % 2)
        let bendDirections = shuffledDirections(using: &rng)
        let bendStart = 2 + Int(rng.next() % 2)
        let secondBendStart = bendStart + 1 + Int(rng.next() % 2)

        var currentX = 0
        var currentZ = 0
        var pathIndices: [Int] = []

        for yIdx in 0 ..< height {
            let parentIdx = yIdx > 0 ? blocks.count - 1 : nil
            if yIdx == bendStart {
                currentX += bendDirections[0].x
                currentZ += bendDirections[0].z
            } else if yIdx == secondBendStart {
                currentX += bendDirections[1].x
                currentZ += bendDirections[1].z
            }
            let color = trunkColors[Int(rng.next() % UInt64(trunkColors.count))]
            let block = VoxelBlockData(
                pos: Int3(x: currentX, y: yIdx, z: currentZ),
                blockType: .trunk,
                colorHex: color,
                parentID: parentIdx.map { blocks[$0].id }
            )
            blocks.append(block)
            occupiedPositions.insert(block.pos)
            pathIndices.append(blocks.count - 1)

            if yIdx == 0 {
                addTrunkSupports(
                    around: block,
                    parentID: block.id,
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
        occupiedPositions: inout Set<Int3>,
        rng: inout SeededRandom,
        trunkLayout: TrunkLayout,
        profile: StageProfile
    ) {
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
            let lateralDirection = availableDirections.first ?? Int3(x: -dir.z, y: 0, z: dir.x)

            var curPos = blocks[originParentIdx].pos
            var prevIdx = originParentIdx

            for step in 0 ..< branchLength {
                let movement: Int3 = switch step {
                case 0:
                    Int3(x: dir.x, y: 0, z: dir.z)
                case 1:
                    Int3(x: 0, y: 1, z: 0)
                case 2:
                    Int3(x: dir.x, y: 0, z: dir.z)
                default:
                    step.isMultiple(of: 2)
                        ? Int3(x: 0, y: 1, z: 0)
                        : Int3(x: lateralDirection.x, y: 0, z: lateralDirection.z)
                }
                curPos = curPos.adding(movement)

                let block = VoxelBlockData(
                    pos: curPos,
                    blockType: .branch,
                    colorHex: branchColor,
                    parentID: blocks[prevIdx].id
                )
                guard insert(block, into: &blocks, occupiedPositions: &occupiedPositions) else { continue }
                prevIdx = blocks.count - 1

                addIntermediateFoliage(
                    around: prevIdx,
                    branchDirection: movement.y > 0 ? dir : Int3(x: movement.x, y: 0, z: movement.z),
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
        occupiedPositions: inout Set<Int3>,
        rng: inout SeededRandom,
        topIndex: Int,
        branchDirection: Int3,
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
        branchDirection: Int3,
        blocks: inout [VoxelBlockData],
        occupiedPositions: inout Set<Int3>,
        rng: inout SeededRandom,
        density: FoliageDensity,
        upwardBias: Bool,
        isTerminal: Bool,
        profile: StageProfile
    ) {
        let anchor = blocks[index]
        let lateralDirection = Int3(x: -branchDirection.z, y: 0, z: branchDirection.x)

        if density == .barelyThere, !isTerminal {
            return
        }
        if density == .sparse, !isTerminal, !rng.next().isMultiple(of: 5) {
            return
        }

        var candidateOffsets: [Int3] = [
            Int3(x: 0, y: 1, z: 0),
            Int3(x: branchDirection.x, y: 0, z: branchDirection.z),
            Int3(x: lateralDirection.x, y: 0, z: lateralDirection.z),
            Int3(x: -lateralDirection.x, y: 0, z: -lateralDirection.z),
            Int3(x: -branchDirection.x, y: 0, z: -branchDirection.z)
        ]
        if upwardBias {
            let upwardOffsets: [Int3] = [
                Int3(x: 0, y: 1, z: 0),
                Int3(x: branchDirection.x, y: 0, z: branchDirection.z),
                Int3(x: lateralDirection.x, y: 0, z: lateralDirection.z)
            ]
            candidateOffsets.append(contentsOf: upwardOffsets)
        }
        if isTerminal {
            let terminalOffsets: [Int3] = [
                Int3(x: branchDirection.x, y: 1, z: branchDirection.z),
                Int3(x: lateralDirection.x, y: 1, z: lateralDirection.z),
                Int3(x: -lateralDirection.x, y: 1, z: -lateralDirection.z)
            ]
            candidateOffsets.append(contentsOf: terminalOffsets)
        }
        if profile.prefersOuterCanopy {
            candidateOffsets.removeAll { offset in
                offset.x == -branchDirection.x && offset.z == -branchDirection.z && offset.y == 0
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
                shouldLift: profile.canopyLiftChance > 0 && rng.next() % profile.canopyLiftChance == 0,
                prefersOuterCanopy: profile.prefersOuterCanopy
            )
            let block = VoxelBlockData(
                pos: anchor.pos.adding(adjustedOffset),
                blockType: .leaf,
                colorHex: leafColor,
                parentID: anchor.id
            )
            _ = insert(block, into: &blocks, occupiedPositions: &occupiedPositions)
        }
    }

    private static func buildCrownLeaf(
        blocks: inout [VoxelBlockData],
        occupiedPositions: inout Set<Int3>,
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
            branchDirection: Int3(x: 0, y: 0, z: 1),
            density: density,
            profile: crownProfile
        )
    }

    private static func maybeAddSecondaryBranch(
        from tipIndex: Int,
        primaryDirection: Int3,
        profile: StageProfile,
        blocks: inout [VoxelBlockData],
        occupiedPositions: inout Set<Int3>,
        rng: inout SeededRandom
    ) {
        guard profile.secondaryBranchChance > 0, rng.next() % profile.secondaryBranchChance == 0 else { return }

        let lateralDirection = Int3(x: primaryDirection.z, y: 0, z: -primaryDirection.x)
        let secondaryDirection = rng.next().isMultiple(of: 2) ? lateralDirection : Int3(
            x: -lateralDirection.x, y: 0, z: -lateralDirection.z
        )
        let branchColor = branchColors[Int(rng.next() % UInt64(branchColors.count))]
        var parentIndex = tipIndex

        let steps = profile.prefersOuterCanopy ? 2 : 1
        for step in 0 ..< steps {
            let offset: Int3 = step == 0
                ? Int3(x: secondaryDirection.x, y: 0, z: secondaryDirection.z)
                : Int3(x: 0, y: 1, z: 0)
            let block = VoxelBlockData(
                pos: blocks[parentIndex].pos.adding(offset),
                blockType: .branch,
                colorHex: branchColor,
                parentID: blocks[parentIndex].id
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
        _ offsets: [Int3],
        prefersOuterCanopy: Bool,
        using rng: inout SeededRandom
    ) -> [Int3] {
        let shuffled = offsets.shuffled(using: &rng)
        guard prefersOuterCanopy else { return shuffled }

        return shuffled.sorted { lhs, rhs in
            canopyPriority(of: lhs) > canopyPriority(of: rhs)
        }
    }

    private static func applyCanopyOpenSlots(
        to offsets: [Int3],
        openSlots: Int,
        using rng: inout SeededRandom
    ) -> [Int3] {
        guard openSlots > 0, offsets.count > 3 else { return offsets }

        var filteredOffsets = offsets
        for _ in 0 ..< openSlots where filteredOffsets.count > 3 {
            let removeIndex = 1 + Int(rng.next() % UInt64(filteredOffsets.count - 1))
            filteredOffsets.remove(at: removeIndex)
        }
        return filteredOffsets
    }

    private static func liftedCanopyOffset(
        from offset: Int3,
        shouldLift: Bool,
        prefersOuterCanopy: Bool
    ) -> Int3 {
        guard shouldLift else { return offset }
        guard prefersOuterCanopy || offset.y == 0 else { return offset }
        return Int3(x: offset.x, y: max(offset.y, 1), z: offset.z)
    }

    private static func canopyPriority(of offset: Int3) -> Int {
        var score = 0
        if offset.y > 0 { score += 3 }
        if abs(offset.x) + abs(offset.z) > 0 { score += 2 }
        if offset.x != 0, offset.z != 0 { score += 1 }
        return score
    }

    private static func addTrunkSupports(
        around anchor: VoxelBlockData,
        parentID: UUID,
        directions: [Int3],
        blocks: inout [VoxelBlockData],
        occupiedPositions: inout Set<Int3>,
        rng: inout SeededRandom
    ) {
        let supportCount = 1 + Int(rng.next() % 2)

        for direction in directions.prefix(supportCount) {
            let block = VoxelBlockData(
                pos: anchor.pos.adding(Int3(x: direction.x, y: 0, z: direction.z)),
                blockType: .trunk,
                colorHex: trunkColors[Int(rng.next() % UInt64(trunkColors.count))],
                parentID: parentID
            )
            _ = insert(block, into: &blocks, occupiedPositions: &occupiedPositions)
        }
    }

    private static func shuffledDirections(using rng: inout SeededRandom) -> [Int3] {
        let directions: [Int3] = [
            Int3(x: 1, y: 0, z: 0), Int3(x: -1, y: 0, z: 0),
            Int3(x: 0, y: 0, z: 1), Int3(x: 0, y: 0, z: -1)
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
        occupiedPositions: inout Set<Int3>
    ) -> Bool {
        guard !occupiedPositions.contains(block.pos) else { return false }
        blocks.append(block)
        occupiedPositions.insert(block.pos)
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

    convenience nonisolated init(hex: String) {
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
