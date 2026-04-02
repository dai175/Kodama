//
//  WordInputView.swift
//  Kodama
//

import SwiftUI

// MARK: - WordInputView

struct WordInputView: View {
    var onSubmit: (String) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $text)
            .font(.system(size: 18, weight: .light, design: .default))
            .foregroundStyle(Color(red: 232 / 255, green: 228 / 255, blue: 220 / 255))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 240)
            .focused($isFocused)
            .colorScheme(.dark)
            .onChange(of: text) {
                if text.count > 20 {
                    text = String(text.prefix(20))
                }
            }
            .onSubmit {
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                onSubmit(trimmed)
            }
            .onAppear {
                isFocused = true
            }
    }
}
