//
//  TreeViewModel+Growth.swift
//  Kodama
//

import Foundation
import OSLog
import SceneKit
import SwiftData

private let logger = Logger(subsystem: "com.daisuke.Kodama", category: "Growth")

// MARK: - Growth

@MainActor extension TreeViewModel {
    func loadOrCreateTree(context: ModelContext) {
        ensureEngineCompatibility(context: context)

        let descriptor = FetchDescriptor<BonsaiTree>()
        let trees = (try? context.fetch(descriptor)) ?? []

        if let existing = trees.first {
            currentTree = existing
            refreshBlockCache(tree: existing, context: context)
        } else {
            createNewTree(context: context)
        }
    }

    func resetTree(context: ModelContext) {
        do {
            // Delete existing trees via instance-level deletion so cascade
            // relationships (blocks / segments / leafClusters / interactions)
            // are flushed cleanly. Batch `context.delete(model:)` has been
            // observed to leave zombie instances that a subsequent fetch
            // can still return, which caused Reset Tree to appear inert.
            let existing = (try? context.fetch(FetchDescriptor<BonsaiTree>())) ?? []
            for tree in existing {
                context.delete(tree)
            }
            try context.save()

            blocks = []
            currentTree = nil

            // Skip loadOrCreateTree to avoid re-fetching from a context that
            // may still hold references to just-deleted objects. Create a new
            // tree directly.
            createNewTree(context: context)
        } catch {
            logger.error("Failed to reset tree: \(error)")
            assertionFailure("Failed to reset tree: \(error)")
        }
    }

    func evaluateGrowth(
        context: ModelContext,
        renderer: BonsaiRenderer,
        force: Bool = false,
        currentDate: Date = Date(),
        maxElapsedHours: Int = 168
    ) async {
        guard let tree = currentTree else { return }
        guard force || currentDate.timeIntervalSince(tree.lastGrowthEval) >= 60 else { return }

        let openInteraction = Interaction(type: .open)
        openInteraction.timestamp = currentDate
        openInteraction.tree = tree
        context.insert(openInteraction)

        let pendingInteractions = tree.interactions
            .filter { $0.timestamp > tree.lastGrowthEval && $0.timestamp <= currentDate }
            .sorted { $0.timestamp < $1.timestamp }
        let interactionPayloads = pendingInteractions.map {
            InteractionPayload(
                timestamp: $0.timestamp,
                type: $0.type,
                value: $0.value,
                touchX: $0.touchX,
                touchY: $0.touchY,
                touchZ: $0.touchZ
            )
        }

        let segmentSnapshots = tree.segments.map { segmentSnapshot(from: $0) }
        let clusterSnapshots = tree.leafClusters.map { clusterSnapshot(from: $0) }

        let input = VectorGrowthInput(
            seed: tree.seed,
            segments: segmentSnapshots,
            leafClusters: clusterSnapshots,
            lastEval: tree.lastGrowthEval,
            currentDate: currentDate,
            interactions: interactionPayloads,
            maxElapsedHours: maxElapsedHours
        )

        let result = await Task.detached(priority: .userInitiated) {
            VectorGrowthEngine.calculate(input)
        }.value

        guard hasChanges(result) else {
            tree.lastGrowthEval = currentDate
            try? context.save()
            return
        }

        do {
            try applyVectorGrowthResult(
                result,
                tree: tree,
                currentDate: currentDate,
                context: context,
                renderer: renderer
            )
        } catch {
            logger.error("Failed to save vector growth changes: \(error)")
        }
    }

    // MARK: - Snapshot Conversion

    func segmentSnapshot(from segment: BranchSegment) -> SegmentSnapshot {
        SegmentSnapshot(
            id: segment.id,
            kind: segment.kind,
            start: segment.start,
            end: segment.end,
            thickness: segment.thickness,
            colorHex: segment.colorHex,
            parentID: segment.parent?.id,
            createdAt: segment.createdAt
        )
    }

    func clusterSnapshot(from cluster: LeafCluster) -> LeafClusterSnapshot {
        LeafClusterSnapshot(
            id: cluster.id,
            segmentID: cluster.segment?.id,
            center: cluster.center,
            radius: cluster.radius,
            density: cluster.density,
            colorHex: cluster.colorHex,
            scatterSeed: cluster.scatterSeed
        )
    }

    // MARK: - Private

    private func hasChanges(_ result: VectorGrowthResult) -> Bool {
        !result.newSegments.isEmpty
            || !result.segmentThicknessUpdates.isEmpty
            || !result.newClusters.isEmpty
            || !result.clusterUpdates.isEmpty
            || !result.removedClusterIDs.isEmpty
    }

    private func applyVectorGrowthResult(
        _ result: VectorGrowthResult,
        tree: BonsaiTree,
        currentDate: Date,
        context: ModelContext,
        renderer: BonsaiRenderer
    ) throws {
        let segmentsByID = Dictionary(uniqueKeysWithValues: tree.segments.map { ($0.id, $0) })
        var mutableSegmentsByID = segmentsByID

        // Insert new segments. Preserve each snapshot's tick-level createdAt
        // so multi-day catch-up growth doesn't collapse all timestamps onto
        // the final evaluation date — thickness aging on subsequent evals
        // depends on the true per-segment birth time.
        for snapshot in result.newSegments {
            let parent = snapshot.parentID.flatMap { mutableSegmentsByID[$0] }
            let segment = BranchSegment(
                id: snapshot.id,
                kind: snapshot.kind,
                start: snapshot.start,
                end: snapshot.end,
                thickness: snapshot.thickness,
                colorHex: snapshot.colorHex,
                createdAt: snapshot.createdAt,
                parent: parent
            )
            segment.tree = tree
            context.insert(segment)
            mutableSegmentsByID[snapshot.id] = segment
        }

        // Apply thickness updates.
        for (segmentID, thickness) in result.segmentThicknessUpdates {
            mutableSegmentsByID[segmentID]?.thickness = thickness
        }
        for (segmentID, count) in result.segmentDescendantCountUpdates {
            mutableSegmentsByID[segmentID]?.descendantCount = count
        }

        // Apply cluster updates.
        let clustersByID = Dictionary(uniqueKeysWithValues: tree.leafClusters.map { ($0.id, $0) })
        var mutableClustersByID = clustersByID
        for (clusterID, update) in result.clusterUpdates {
            guard let cluster = mutableClustersByID[clusterID] else { continue }
            cluster.radius = update.radius
            cluster.density = update.density
            cluster.colorHex = update.colorHex
        }

        // Remove clusters.
        for clusterID in result.removedClusterIDs {
            if let cluster = mutableClustersByID.removeValue(forKey: clusterID) {
                context.delete(cluster)
            }
        }

        // Insert new clusters.
        for snapshot in result.newClusters {
            let segment = snapshot.segmentID.flatMap { mutableSegmentsByID[$0] }
            let cluster = LeafCluster(
                id: snapshot.id,
                center: snapshot.center,
                radius: snapshot.radius,
                density: snapshot.density,
                colorHex: snapshot.colorHex,
                scatterSeed: snapshot.scatterSeed,
                createdAt: currentDate,
                segment: segment
            )
            cluster.tree = tree
            context.insert(cluster)
            mutableClustersByID[snapshot.id] = cluster
        }

        tree.lastGrowthEval = currentDate

        // Regenerate voxel cache from the updated vector skeleton before
        // saving so totalBlocks (also persisted below) reflects the new
        // cache in a single transaction.
        regenerateVoxelCache(tree: tree, context: context)
        tree.totalBlocks = blocks.count
        try context.save()

        renderer.renderTree(from: blocks)
    }

    // MARK: - New Tree Creation

    private func createNewTree(context: ModelContext) {
        let seed = Int.random(in: 1 ... 999_999)
        let tree = BonsaiTree(seed: seed)
        context.insert(tree)

        let sapling = SkeletonBuilder.buildSapling(seed: UInt64(seed))
        var segmentsByID: [UUID: BranchSegment] = [:]
        for snapshot in sapling.segments {
            let parent = snapshot.parentID.flatMap { segmentsByID[$0] }
            let segment = BranchSegment(
                id: snapshot.id,
                kind: snapshot.kind,
                start: snapshot.start,
                end: snapshot.end,
                thickness: snapshot.thickness,
                colorHex: snapshot.colorHex,
                createdAt: snapshot.createdAt,
                parent: parent
            )
            segment.tree = tree
            context.insert(segment)
            segmentsByID[snapshot.id] = segment
        }
        for snapshot in sapling.leafClusters {
            let segment = snapshot.segmentID.flatMap { segmentsByID[$0] }
            let cluster = LeafCluster(
                id: snapshot.id,
                center: snapshot.center,
                radius: snapshot.radius,
                density: snapshot.density,
                colorHex: snapshot.colorHex,
                scatterSeed: snapshot.scatterSeed,
                segment: segment
            )
            cluster.tree = tree
            context.insert(cluster)
        }

        do {
            currentTree = tree
            regenerateVoxelCache(tree: tree, context: context)
            tree.totalBlocks = blocks.count
            try context.save()
            UserDefaults.standard.set(engineSchemaVersion, forKey: engineSchemaVersionKey)
        } catch {
            logger.error("Failed to save new tree: \(error)")
        }
    }

    // MARK: - Voxel Cache

    private func refreshBlockCache(tree: BonsaiTree, context: ModelContext) {
        if tree.blocks.isEmpty {
            regenerateVoxelCache(tree: tree, context: context)
            try? context.save()
        } else {
            blocks = tree.blocks.map { voxelBlockToData($0) }
        }
    }

    private func regenerateVoxelCache(tree: BonsaiTree, context: ModelContext) {
        let segmentSnapshots = tree.segments.map { segmentSnapshot(from: $0) }
        let clusterSnapshots = tree.leafClusters.map { clusterSnapshot(from: $0) }
        let newBlocks = VoxelRasterizer.rasterize(
            segments: segmentSnapshots,
            leafClusters: clusterSnapshots
        )

        // Delete existing cached VoxelBlock entities.
        for block in tree.blocks {
            context.delete(block)
        }

        // Insert fresh cache.
        for blockData in newBlocks {
            let voxelBlock = VoxelBlock(
                id: blockData.id,
                pos: blockData.pos,
                blockType: blockData.blockType,
                colorHex: blockData.colorHex,
                source: .autonomous,
                parentBlockID: nil
            )
            voxelBlock.tree = tree
            context.insert(voxelBlock)
        }

        blocks = newBlocks
    }

    private func ensureEngineCompatibility(context: ModelContext) {
        let savedVersion = UserDefaults.standard.integer(forKey: engineSchemaVersionKey)
        if savedVersion == 0 {
            UserDefaults.standard.set(engineSchemaVersion, forKey: engineSchemaVersionKey)
            return
        }
        if savedVersion == engineSchemaVersion { return }
        do {
            try context.delete(model: VoxelBlock.self)
            try context.delete(model: LeafCluster.self)
            try context.delete(model: BranchSegment.self)
            try context.delete(model: Interaction.self)
            try context.delete(model: BonsaiTree.self)
            try context.save()
            UserDefaults.standard.set(engineSchemaVersion, forKey: engineSchemaVersionKey)
        } catch {
            logger.error("Failed to reset incompatible engine data: \(error)")
        }
    }
}
