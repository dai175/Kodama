//
//  TreeViewModel+TimeTravel.swift
//  Kodama
//

import Foundation
import SceneKit
import SwiftData

#if DEBUG

    // MARK: - Time Travel (Debug)

    @MainActor extension TreeViewModel {
        func timeTravel(
            component: Calendar.Component,
            value: Int,
            context: ModelContext,
            renderer: BonsaiRenderer
        ) async {
            guard currentTree != nil else {
                print("[TimeTravel] ABORT: currentTree is nil")
                return
            }
            let savedOverride = Season.debugOverride
            defer { Season.debugOverride = savedOverride }
            Season.debugOverride = nil
            var remainingValue = value

            while remainingValue > 0, let currentTree {
                let stepValue = min(timeTravelStepSize(for: component), remainingValue)
                let blocksBefore = blocks.count
                let targetDate = Calendar.current.date(
                    byAdding: component,
                    value: stepValue,
                    to: currentTree.lastGrowthEval
                ) ?? currentTree.lastGrowthEval

                print("[TimeTravel] Advancing growth evaluation by \(stepValue) \(component) to \(targetDate)")
                await evaluateGrowth(
                    context: context,
                    renderer: renderer,
                    force: true,
                    currentDate: targetDate,
                    maxElapsedHours: maxElapsedHours(for: component, stepValue: stepValue)
                )
                print("[TimeTravel] Blocks: \(blocksBefore) → \(blocks.count)")

                remainingValue -= stepValue
                await Task.yield()
            }
        }

        nonisolated func timeTravelStepSize(for component: Calendar.Component) -> Int {
            switch component {
            case .month:
                1
            case .day:
                7
            default:
                1
            }
        }

        nonisolated func maxElapsedHours(for component: Calendar.Component, stepValue: Int) -> Int {
            switch component {
            case .month:
                24 * 31 * max(1, stepValue)
            case .day:
                24 * max(1, stepValue)
            default:
                24 * 31
            }
        }
    }

#endif
