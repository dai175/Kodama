//
//  Season.swift
//  Kodama
//

import Foundation

// MARK: - Season

enum Season: String, CaseIterable {
    case spring
    case summer
    case autumn
    case winter

    #if DEBUG
        /// Debug-only override for testing seasonal effects.
        nonisolated(unsafe) static var debugOverride: Season?
    #endif

    static func current(from date: Date = Date()) -> Season {
        #if DEBUG
            if let override = debugOverride {
                return override
            }
        #endif

        let month = Calendar.current.component(.month, from: date)
        switch month {
        case 3 ... 5: return .spring
        case 6 ... 8: return .summer
        case 9 ... 11: return .autumn
        default: return .winter
        }
    }
}
