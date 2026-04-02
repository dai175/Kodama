//
//  ColorPaletteView.swift
//  Kodama
//

import SwiftUI

// MARK: - ColorPaletteView

struct ColorPaletteView: View {
    var onColorSelected: (String) -> Void

    private let colors: [(hex: String, color: Color)] = [
        ("#CC4444", Color(red: 204 / 255, green: 68 / 255, blue: 68 / 255)),
        ("#E8A020", Color(red: 232 / 255, green: 160 / 255, blue: 32 / 255)),
        ("#D4C830", Color(red: 212 / 255, green: 200 / 255, blue: 48 / 255)),
        ("#5A9E3A", Color(red: 90 / 255, green: 158 / 255, blue: 58 / 255)),
        ("#4A7DB8", Color(red: 74 / 255, green: 125 / 255, blue: 184 / 255)),
        ("#8B5AA0", Color(red: 139 / 255, green: 90 / 255, blue: 160 / 255)),
        ("#E8E4DC", Color(red: 232 / 255, green: 228 / 255, blue: 220 / 255))
    ]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(colors.enumerated()), id: \.offset) { index, item in
                Circle()
                    .fill(item.color)
                    .frame(width: 36, height: 36)
                    .opacity(0.7)
                    .offset(y: arcOffset(for: index, total: colors.count))
                    .onTapGesture {
                        onColorSelected(item.hex)
                    }
            }
        }
    }

    private func arcOffset(for index: Int, total: Int) -> CGFloat {
        let mid = CGFloat(total - 1) / 2.0
        let normalized = (CGFloat(index) - mid) / mid
        return normalized * normalized * 12
    }
}
