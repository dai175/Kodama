//
//  VectorGrowthEngine.swift
//  Kodama
//

import Foundation

// MARK: - VectorGrowthEngine

/// Operates on the vector tree skeleton (segments + leaf clusters). Never
/// touches voxels — voxel rasterization is a separate, downstream step.
nonisolated enum VectorGrowthEngine {
    // Growth tuning constants.
    static let maxSegments = 400
    static let branchChancePerTick = 10 // percent
    static let segmentLengthMin: Float = 1.2
    static let segmentLengthMax: Float = 2.0
    static let newSegmentThickness: Float = 0.5

    // Direction distribution (spec: 70% horizontal, 20% up, 10% slightly down).
    static let horizontalChance = 70
    static let upwardChance = 20 // 70..89
    // (90..99 → slight downward)

    // Thickness model: thickness = base + ageDays*ageFactor + descendants*descendantFactor
    static let ageFactor: Float = 0.015
    static let descendantFactor: Float = 0.08
    static let trunkThicknessMax: Float = 2.6
    static let branchThicknessMax: Float = 1.6

    // Cluster defaults.
    static let clusterRadiusBase: Float = 1.2
    static let clusterDensityBase: Float = 0.55

    // MARK: - Entry Point

    static func calculate(_ input: VectorGrowthInput) -> VectorGrowthResult {
        let elapsedSeconds = input.currentDate.timeIntervalSince(input.lastEval)
        let elapsedHours = max(0, min(Int(elapsedSeconds / 3600), input.maxElapsedHours))

        var state = VectorGrowthState(
            segments: input.segments,
            leafClusters: input.leafClusters,
            result: .empty
        )

        var rng = SeededRandom(seed: UInt64(input.seed) &+ UInt64(max(0, input.segments.count)))

        let touchHint = input.interactions.first { $0.type == .touch }
            .map { Float3(x: Float($0.touchX ?? 0), y: Float($0.touchY ?? 0), z: Float($0.touchZ ?? 0)) }
        let colorHint = input.interactions.last { $0.type == .color }?.value
        let wordHint = input.interactions.first { $0.type == .word }?.value

        for tick in 0 ..< elapsedHours {
            guard state.liveSegmentCount < maxSegments else { break }
            let tickDate = input.lastEval.addingTimeInterval(Double(tick) * 3600)
            let season = Season.current(from: tickDate)
            let stage = stageForSegments(state.segments)
            let growthCount = GrowthEngine.growthActionsPerTick(season: season, growthStage: stage, rng: &rng)
            guard growthCount > 0 else { continue }

            for _ in 0 ..< growthCount {
                guard state.liveSegmentCount < maxSegments else { break }
                attemptGrowthAction(
                    state: &state,
                    rng: &rng,
                    touchHint: touchHint,
                    wordHint: wordHint,
                    tickDate: tickDate
                )
            }
        }

        updateThicknessAndDescendants(
            state: &state,
            currentDate: input.currentDate
        )
        updateLeafClusters(
            state: &state,
            rng: &rng,
            season: Season.current(from: input.currentDate),
            colorHint: colorHint
        )

        return state.result
    }

    // MARK: - Growth Actions

    private static func attemptGrowthAction(
        state: inout VectorGrowthState,
        rng: inout SeededRandom,
        touchHint: Float3?,
        wordHint _: String?,
        tickDate: Date
    ) {
        let isBranching = Int(rng.next() % 100) < branchChancePerTick
        let tipIDs = findTipSegmentIDs(in: state.segments)
        guard !tipIDs.isEmpty else { return }

        let parent: SegmentSnapshot
        if let touchHint {
            parent = nearestSegment(in: tipIDs, to: touchHint, segments: state.segments)
                ?? state.segments[Int(rng.next() % UInt64(state.segments.count))]
        } else if isBranching {
            // Branching: pick any segment (not just tips) to fork from.
            parent = state.segments[Int(rng.next() % UInt64(state.segments.count))]
        } else {
            let id = tipIDs[Int(rng.next() % UInt64(tipIDs.count))]
            parent = state.segments.first { $0.id == id } ?? state.segments[0]
        }

        let direction = pickDirection(rng: &rng, biasTowards: parent.direction)
        let length = segmentLengthMin + (segmentLengthMax - segmentLengthMin)
            * Float(rng.next() % 1000) / 1000.0

        let origin = isBranching ? pickMidPoint(on: parent, rng: &rng) : parent.end
        let end = origin.adding(direction.scaled(by: length))

        let color = parent.kind == .trunk && !isBranching
            ? TreeBuilder.trunkColors[Int(rng.next() % UInt64(TreeBuilder.trunkColors.count))]
            : TreeBuilder.branchColors[Int(rng.next() % UInt64(TreeBuilder.branchColors.count))]

        let newSegment = SegmentSnapshot(
            id: UUID(),
            kind: (!isBranching && parent.kind == .trunk && direction.y > 0.5) ? .trunk : .branch,
            start: origin,
            end: end,
            thickness: newSegmentThickness,
            colorHex: color,
            parentID: parent.id,
            createdAt: tickDate
        )

        state.segments.append(newSegment)
        state.result.newSegments.append(newSegment)
        state.liveSegmentCount += 1
    }

    private static func pickDirection(rng: inout SeededRandom, biasTowards hint: Float3) -> Float3 {
        let roll = Int(rng.next() % 100)
        let base: Float3
        if roll < horizontalChance {
            let angle = Float(rng.next() % 1000) / 1000.0 * 2 * .pi
            base = Float3(x: cos(angle), y: 0, z: sin(angle))
        } else if roll < horizontalChance + upwardChance {
            base = Float3(x: 0, y: 1, z: 0)
        } else {
            let angle = Float(rng.next() % 1000) / 1000.0 * 2 * .pi
            base = Float3(x: cos(angle) * 0.7, y: -0.3, z: sin(angle) * 0.7).normalized
        }
        // Blend slightly with the parent direction so growth flows naturally.
        let blended = Float3(
            x: base.x * 0.8 + hint.x * 0.2,
            y: base.y * 0.8 + hint.y * 0.2,
            z: base.z * 0.8 + hint.z * 0.2
        )
        return blended.normalized
    }

    private static func pickMidPoint(on segment: SegmentSnapshot, rng: inout SeededRandom) -> Float3 {
        let progress = 0.4 + Float(rng.next() % 1000) / 1000.0 * 0.5 // 0.4..0.9
        return Float3(
            x: segment.start.x + (segment.end.x - segment.start.x) * progress,
            y: segment.start.y + (segment.end.y - segment.start.y) * progress,
            z: segment.start.z + (segment.end.z - segment.start.z) * progress
        )
    }

    // MARK: - Thickness & Descendants

    private static func updateThicknessAndDescendants(
        state: inout VectorGrowthState,
        currentDate: Date
    ) {
        // Build parent → children adjacency to count descendants.
        var children: [UUID: [UUID]] = [:]
        for segment in state.segments {
            if let parentID = segment.parentID {
                children[parentID, default: []].append(segment.id)
            }
        }

        var descendantCounts: [UUID: Int] = [:]
        for segment in state.segments {
            descendantCounts[segment.id] = countDescendants(of: segment.id, children: children)
        }

        for segment in state.segments {
            let descendants = descendantCounts[segment.id] ?? 0
            let ageDays = max(0, Float(currentDate.timeIntervalSince(segment.createdAt) / 86400))
            let maxThickness = segment.kind == .trunk ? trunkThicknessMax : branchThicknessMax
            let computed = min(
                maxThickness,
                newSegmentThickness + ageDays * ageFactor + Float(descendants) * descendantFactor
            )
            // Thickness is monotonic — branches harden over time, they never
            // thin out. This also guards against an initial trunk (created
            // with a bespoke starting thickness) being rewritten below its
            // starting value before aging catches up.
            let thickness = max(segment.thickness, computed)
            if thickness - segment.thickness > 0.001 {
                state.result.segmentThicknessUpdates[segment.id] = thickness
            }
            state.result.segmentDescendantCountUpdates[segment.id] = descendants
        }
    }

    private static func countDescendants(of id: UUID, children: [UUID: [UUID]]) -> Int {
        var count = 0
        var stack: [UUID] = children[id] ?? []
        while let next = stack.popLast() {
            count += 1
            if let nextChildren = children[next] {
                stack.append(contentsOf: nextChildren)
            }
        }
        return count
    }

    // MARK: - Leaf Clusters

    private static func updateLeafClusters(
        state: inout VectorGrowthState,
        rng: inout SeededRandom,
        season: Season,
        colorHint: String?
    ) {
        // Iterate tips in sorted order so rng consumption (scatter seeds,
        // color rolls) is deterministic regardless of insertion order.
        let tipIDs = findTipSegmentIDs(in: state.segments)
            .sorted { $0.uuidString < $1.uuidString }
        let tipIDSet = Set(tipIDs)
        let existingClustersBySegment = Dictionary(
            grouping: state.leafClusters.compactMap { cluster -> (UUID, LeafClusterSnapshot)? in
                guard let segID = cluster.segmentID else { return nil }
                return (segID, cluster)
            },
            by: \.0
        )

        // Drop clusters whose parent segment is no longer a tip.
        for cluster in state.leafClusters {
            if let segID = cluster.segmentID, !tipIDSet.contains(segID) {
                state.result.removedClusterIDs.append(cluster.id)
            }
        }

        // Create / update clusters on tips.
        let (radius, density) = clusterSize(for: season)
        for tipID in tipIDs {
            guard let tip = state.segments.first(where: { $0.id == tipID }) else { continue }
            let seasonalColor = SeasonalEngine.leafColor(for: season, rng: &rng, userColor: colorHint)

            if let existing = existingClustersBySegment[tipID]?.first?.1 {
                // Only emit an update when a visible property actually changes.
                let radiusChanged = abs(existing.radius - radius) > 0.001
                let densityChanged = abs(existing.density - density) > 0.001
                let colorChanged = existing.colorHex != seasonalColor
                if radiusChanged || densityChanged || colorChanged {
                    state.result.clusterUpdates[existing.id] = ClusterUpdate(
                        radius: radius,
                        density: density,
                        colorHex: seasonalColor
                    )
                }
            } else {
                let newCluster = LeafClusterSnapshot(
                    id: UUID(),
                    segmentID: tipID,
                    center: tip.end,
                    radius: radius,
                    density: density,
                    colorHex: seasonalColor,
                    scatterSeed: Int64(bitPattern: rng.next())
                )
                state.result.newClusters.append(newCluster)
            }
        }
    }

    private static func clusterSize(for season: Season) -> (radius: Float, density: Float) {
        switch season {
        case .spring:
            (clusterRadiusBase, 0.55)
        case .summer:
            (clusterRadiusBase + 0.4, 0.7)
        case .autumn:
            (clusterRadiusBase + 0.1, 0.45)
        case .winter:
            (clusterRadiusBase - 0.3, 0.2)
        }
    }

    // MARK: - Helpers

    static func findTipSegmentIDs(in segments: [SegmentSnapshot]) -> [UUID] {
        var hasChild = Set<UUID>()
        for segment in segments {
            if let parentID = segment.parentID {
                hasChild.insert(parentID)
            }
        }
        return segments.compactMap { hasChild.contains($0.id) ? nil : $0.id }
    }

    static func nearestSegment(
        in segmentIDs: [UUID],
        to point: Float3,
        segments: [SegmentSnapshot]
    ) -> SegmentSnapshot? {
        let lookup = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })
        var best: (SegmentSnapshot, Float)?
        for id in segmentIDs {
            guard let segment = lookup[id] else { continue }
            let dist = VoxelRasterizer.distanceFromPointToSegment(
                point: point,
                start: segment.start,
                end: segment.end
            )
            if let current = best {
                if dist < current.1 {
                    best = (segment, dist)
                }
            } else {
                best = (segment, dist)
            }
        }
        return best?.0
    }

    private static func stageForSegments(_ segments: [SegmentSnapshot]) -> TreeBuilder.GrowthStage {
        let count = segments.count
        if count < 8 {
            return .sapling
        }
        if count < 24 {
            return .young
        }
        return .mature
    }
}

// MARK: - Working State

private struct VectorGrowthState {
    var segments: [SegmentSnapshot]
    var leafClusters: [LeafClusterSnapshot]
    var result: VectorGrowthResult
    var liveSegmentCount: Int

    init(
        segments: [SegmentSnapshot],
        leafClusters: [LeafClusterSnapshot],
        result: VectorGrowthResult
    ) {
        self.segments = segments
        self.leafClusters = leafClusters
        self.result = result
        liveSegmentCount = segments.count
    }
}
