//
//  SettingsView.swift
//  Kodama
//

import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    var onTreeReset: () -> Void = {}

    @State private var showResetFirstAlert = false
    @State private var showResetSecondAlert = false

    #if DEBUG
        @State private var seasonOverride: Season? = Season.debugOverride
    #endif

    var body: some View {
        NavigationStack {
            List {
                aboutSection
                resetSection
                #if DEBUG
                    debugSection
                #endif
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 10 / 255, green: 26 / 255, blue: 18 / 255))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.softWhite.opacity(0.7))
                }
            }
            .preferredColorScheme(.dark)
        }
        .alert("Reset Tree?", isPresented: $showResetFirstAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                showResetSecondAlert = true
            }
        } message: {
            Text("This will remove your tree permanently.")
        }
        .alert("Are you absolutely sure?", isPresented: $showResetSecondAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Forever", role: .destructive) {
                performReset()
            }
        } message: {
            Text("Your tree and all its history will be lost forever.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Kodama")
                    .foregroundStyle(Color.softWhite.opacity(0.8))
                Spacer()
                Text("v1.0")
                    .foregroundStyle(Color.softWhite.opacity(0.4))
            }
            .listRowBackground(Color.white.opacity(0.05))

            HStack {
                Text("by focuswave")
                    .foregroundStyle(Color.softWhite.opacity(0.5))
                    .font(.system(size: 14, weight: .light))
            }
            .listRowBackground(Color.white.opacity(0.05))
        } header: {
            Text("About")
                .foregroundStyle(Color.softWhite.opacity(0.4))
        }
    }

    // MARK: - Reset

    private var resetSection: some View {
        Section {
            Button {
                showResetFirstAlert = true
            } label: {
                Text("Reset Tree")
                    .foregroundStyle(.red.opacity(0.8))
            }
            .listRowBackground(Color.white.opacity(0.05))
        } header: {
            Text("Data")
                .foregroundStyle(Color.softWhite.opacity(0.4))
        }
    }

    // MARK: - Debug

    #if DEBUG
        private var debugSection: some View {
            Section {
                HStack {
                    Text("Current Season")
                        .foregroundStyle(Color.softWhite.opacity(0.8))
                    Spacer()
                    Text(Season.current().rawValue.capitalized)
                        .foregroundStyle(Color.softWhite.opacity(0.5))
                }
                .listRowBackground(Color.white.opacity(0.05))

                Picker("Override Season", selection: $seasonOverride) {
                    Text("None").tag(Season?.none)
                    ForEach(Season.allCases, id: \.self) { season in
                        Text(season.rawValue.capitalized).tag(Season?.some(season))
                    }
                }
                .foregroundStyle(Color.softWhite.opacity(0.8))
                .listRowBackground(Color.white.opacity(0.05))
                .onChange(of: seasonOverride) {
                    Season.debugOverride = seasonOverride
                }
            } header: {
                Text("Debug")
                    .foregroundStyle(Color.softWhite.opacity(0.4))
            }
        }
    #endif

    // MARK: - Reset Action

    private func performReset() {
        onTreeReset()
        dismiss()
    }
}
