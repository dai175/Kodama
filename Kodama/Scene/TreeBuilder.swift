//
//  TreeBuilder.swift
//  Kodama
//

import Foundation

// MARK: - TreeBuilder

nonisolated enum TreeBuilder {
    private struct TrunkLayout {
        let pathIndices: [Int]

        var topIndex: Int {
            guard let last = pathIndices.last else {
                preconditionFailure("TrunkLayout must have at least one path index")
            }
            return last
        }
    }

    enum GrowthStage: Equatable {
        case sapling
        case young
        case mature
    }

    struct BuildContext {
        var blocks: [VoxelBlockData]
        var occupiedPositions: Set<Int3>
        var rng: SeededRandom
    }

    enum FoliageDensity {
        case barelyThere
        case sparse
        case medium
        case lush
    }

    struct StageProfile {
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

    // MARK: - Sapling Generation

    static func buildSapling(seed: UInt64) -> [VoxelBlockData] {
        var context = BuildContext(
            blocks: [],
            occupiedPositions: [],
            rng: SeededRandom(seed: seed)
        )
        let profile = stageProfile(for: .sapling)

        let trunkLayout = buildTrunk(context: &context)
        buildBranches(context: &context, trunkLayout: trunkLayout, profile: profile)
        buildCrownLeaf(
            context: &context,
            topIndex: trunkLayout.topIndex,
            density: profile.crownDensity
        )

        return context.blocks
    }

    private static func buildTrunk(context: inout BuildContext) -> TrunkLayout {
        let height = 5 + Int(context.rng.next() % 2)
        let bendDirections = shuffledDirections(using: &context.rng)
        let bendStart = 2 + Int(context.rng.next() % 2)
        let secondBendStart = bendStart + 1 + Int(context.rng.next() % 2)

        var currentX = 0
        var currentZ = 0
        var pathIndices: [Int] = []

        for yIdx in 0 ..< height {
            let parentIdx = yIdx > 0 ? context.blocks.count - 1 : nil
            if yIdx == bendStart {
                currentX += bendDirections[0].x
                currentZ += bendDirections[0].z
            } else if yIdx == secondBendStart {
                currentX += bendDirections[1].x
                currentZ += bendDirections[1].z
            }
            let color = trunkColors[Int(context.rng.next() % UInt64(trunkColors.count))]
            let block = VoxelBlockData(
                pos: Int3(x: currentX, y: yIdx, z: currentZ),
                blockType: .trunk,
                colorHex: color,
                parentID: parentIdx.map { context.blocks[$0].id }
            )
            context.blocks.append(block)
            context.occupiedPositions.insert(block.pos)
            pathIndices.append(context.blocks.count - 1)

            if yIdx == 0 {
                addTrunkSupports(
                    around: block,
                    parentID: block.id,
                    directions: Array(bendDirections.prefix(2)),
                    context: &context
                )
            }
        }

        return TrunkLayout(pathIndices: pathIndices)
    }

    private static func buildBranches(
        context: inout BuildContext,
        trunkLayout: TrunkLayout,
        profile: StageProfile
    ) {
        let startRange = max(1, (trunkLayout.pathIndices.count / 2) + profile.branchStartHeightBias)
        var availableDirections = shuffledDirections(using: &context.rng)
        let branchCount = min(randomInt(in: profile.branchCountRange, using: &context.rng), availableDirections.count)

        for branchIndex in 0 ..< branchCount {
            let dir = availableDirections.removeFirst()
            let branchColor = branchColors[Int(context.rng.next() % UInt64(branchColors.count))]
            let branchLength = randomInt(in: profile.branchLengthRange, using: &context.rng)
            let trunkPathIndex = min(
                startRange + branchIndex + Int(context.rng.next() % 2),
                trunkLayout.pathIndices.count - 1
            )
            let originParentIdx = trunkLayout.pathIndices[trunkPathIndex]
            let lateralDirection = availableDirections.first ?? Int3(x: -dir.z, y: 0, z: dir.x)

            let spec = BranchSpec(
                dir: dir,
                originParentIdx: originParentIdx,
                lateralDirection: lateralDirection,
                branchLength: branchLength,
                branchColor: branchColor,
                profile: profile
            )
            let prevIdx = buildSingleBranch(context: &context, spec: spec)

            maybeAddSecondaryBranch(from: prevIdx, primaryDirection: dir, profile: profile, context: &context)
            buildBranchLeaves(
                context: &context,
                topIndex: prevIdx,
                branchDirection: dir,
                density: profile.terminalFoliageDensity,
                profile: profile
            )
        }
    }

    private struct BranchSpec {
        let dir: Int3
        let originParentIdx: Int
        let lateralDirection: Int3
        let branchLength: Int
        let branchColor: String
        let profile: StageProfile
    }

    private static func buildSingleBranch(
        context: inout BuildContext,
        spec: BranchSpec
    ) -> Int {
        let dir = spec.dir
        let branchLength = spec.branchLength
        let profile = spec.profile
        var curPos = context.blocks[spec.originParentIdx].pos
        var prevIdx = spec.originParentIdx

        for step in 0 ..< branchLength {
            let movement = switch step {
            case 0:
                Int3(x: dir.x, y: 0, z: dir.z)
            case 1:
                Int3(x: 0, y: 1, z: 0)
            case 2:
                Int3(x: dir.x, y: 0, z: dir.z)
            default:
                if step.isMultiple(of: 2) {
                    Int3(x: 0, y: 1, z: 0)
                } else {
                    Int3(x: spec.lateralDirection.x, y: 0, z: spec.lateralDirection.z)
                }
            }
            curPos = curPos.adding(movement)

            let block = VoxelBlockData(
                pos: curPos,
                blockType: .branch,
                colorHex: spec.branchColor,
                parentID: context.blocks[prevIdx].id
            )
            guard insert(block, into: &context.blocks, occupiedPositions: &context.occupiedPositions) else { continue }
            prevIdx = context.blocks.count - 1

            addIntermediateFoliage(
                around: prevIdx,
                branchDirection: movement.y > 0 ? dir : Int3(x: movement.x, y: 0, z: movement.z),
                context: &context,
                density: step == branchLength - 1 ? profile.terminalFoliageDensity : profile
                    .intermediateFoliageDensity,
                upwardBias: step >= branchLength - 2,
                isTerminal: false,
                profile: profile
            )
        }

        return prevIdx
    }

    private static func maybeAddSecondaryBranch(
        from tipIndex: Int,
        primaryDirection: Int3,
        profile: StageProfile,
        context: inout BuildContext
    ) {
        guard profile.secondaryBranchChance > 0, context.rng.next() % profile.secondaryBranchChance == 0 else { return }

        let lateralDirection = Int3(x: primaryDirection.z, y: 0, z: -primaryDirection.x)
        let secondaryDirection = context.rng.next().isMultiple(of: 2) ? lateralDirection : Int3(
            x: -lateralDirection.x, y: 0, z: -lateralDirection.z
        )
        let branchColor = branchColors[Int(context.rng.next() % UInt64(branchColors.count))]
        var parentIndex = tipIndex

        let steps = profile.prefersOuterCanopy ? 2 : 1
        for step in 0 ..< steps {
            let offset: Int3 = step == 0
                ? Int3(x: secondaryDirection.x, y: 0, z: secondaryDirection.z)
                : Int3(x: 0, y: 1, z: 0)
            let block = VoxelBlockData(
                pos: context.blocks[parentIndex].pos.adding(offset),
                blockType: .branch,
                colorHex: branchColor,
                parentID: context.blocks[parentIndex].id
            )
            guard insert(block, into: &context.blocks, occupiedPositions: &context.occupiedPositions) else { continue }
            parentIndex = context.blocks.count - 1
        }

        addIntermediateFoliage(
            around: parentIndex,
            branchDirection: secondaryDirection,
            context: &context,
            density: profile.terminalFoliageDensity,
            upwardBias: true,
            isTerminal: true,
            profile: profile
        )
    }

    private static func addTrunkSupports(
        around anchor: VoxelBlockData,
        parentID: UUID,
        directions: [Int3],
        context: inout BuildContext
    ) {
        let supportCount = 1 + Int(context.rng.next() % 2)

        for direction in directions.prefix(supportCount) {
            let block = VoxelBlockData(
                pos: anchor.pos.adding(Int3(x: direction.x, y: 0, z: direction.z)),
                blockType: .trunk,
                colorHex: trunkColors[Int(context.rng.next() % UInt64(trunkColors.count))],
                parentID: parentID
            )
            _ = insert(block, into: &context.blocks, occupiedPositions: &context.occupiedPositions)
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

    static func insert(
        _ block: VoxelBlockData,
        into blocks: inout [VoxelBlockData],
        occupiedPositions: inout Set<Int3>
    ) -> Bool {
        guard !occupiedPositions.contains(block.pos) else { return false }
        blocks.append(block)
        occupiedPositions.insert(block.pos)
        return true
    }
}
