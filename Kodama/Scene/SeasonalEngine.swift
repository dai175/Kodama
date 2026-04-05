//
//  SeasonalEngine.swift
//  Kodama
//

import Foundation

// MARK: - SeasonalEngine

/// Color helpers shared by the vector growth engine. Previously this type
/// drove per-voxel seasonal mutations; in the vector architecture it simply
/// provides the palette that `VectorGrowthEngine` assigns to leaf clusters.
nonisolated enum SeasonalEngine {
    // MARK: - Color Palettes

    static let springLeafColors = ["#7AB648", "#5A9E3A", "#8BC96A"]
    static let summerLeafColors = ["#2D5A1E", "#3E7A2A"]
    static let autumnLeafColors = ["#D4C830", "#E8A020", "#CC4422", "#8B6914"]
    static let winterLeafColors = ["#8B6914", "#A88B60"]

    // MARK: - Leaf Color Selection

    /// Returns an appropriate leaf color for the given season, optionally
    /// blending with a user-selected color from a color interaction.
    nonisolated static func leafColor(
        for season: Season,
        rng: inout SeededRandom,
        userColor: String? = nil
    ) -> String {
        let palette: [String] = switch season {
        case .spring:
            springLeafColors
        case .summer:
            summerLeafColors
        case .autumn:
            autumnLeafColors
        case .winter:
            winterLeafColors
        }
        let baseColor = palette[Int(rng.next() % UInt64(palette.count))]

        if let userColor {
            return blendColors(base: baseColor, overlay: userColor, factor: 0.2)
        }
        return baseColor
    }

    // MARK: - Color Blending

    /// Blends two hex colors (0 = all base, 1 = all overlay).
    nonisolated static func blendColors(base: String, overlay: String, factor: Float) -> String {
        let (bR, bG, bB) = hexToRGB(base)
        let (oR, oG, oB) = hexToRGB(overlay)

        let r = Int(Float(bR) * (1 - factor) + Float(oR) * factor)
        let g = Int(Float(bG) * (1 - factor) + Float(oG) * factor)
        let b = Int(Float(bB) * (1 - factor) + Float(oB) * factor)

        return rgbToHex(
            r: min(255, max(0, r)),
            g: min(255, max(0, g)),
            b: min(255, max(0, b))
        )
    }

    // MARK: - Hex Utilities

    nonisolated private static func hexToRGB(_ hex: String) -> (Int, Int, Int) {
        let hexString = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard hexString.count == 6,
              hexString.allSatisfy(\.isHexDigit),
              let hexNumber = UInt64(hexString, radix: 16)
        else {
            assertionFailure("Invalid hex color string: \(hexString)")
            return (0, 0, 0)
        }
        let r = Int((hexNumber & 0xFF0000) >> 16)
        let g = Int((hexNumber & 0x00FF00) >> 8)
        let b = Int(hexNumber & 0x0000FF)
        return (r, g, b)
    }

    nonisolated private static func rgbToHex(r: Int, g: Int, b: Int) -> String {
        String(format: "#%02X%02X%02X", r, g, b)
    }
}
