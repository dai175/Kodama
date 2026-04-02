//
//  RootView.swift
//  Kodama
//

import SwiftUI

// MARK: - RootView

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.hasCompletedOnboarding {
                TreeView()
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut(duration: 0.5), value: appState.hasCompletedOnboarding)
        .preferredColorScheme(.dark)
    }
}
