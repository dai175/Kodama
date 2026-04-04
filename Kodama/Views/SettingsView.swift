//
//  SettingsView.swift
//  Kodama
//

import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var onTreeReset: () -> Void = {}
    #if DEBUG
        var onTimeTravel: ((Int) -> Void)?
        var debugTreeInfo: (totalBlocks: Int, createdAt: Date)?
    #endif

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
            .background(Color(uiColor: .darkForest))
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

    private var appVersionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return "v\(version)"
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Kodama")
                    .foregroundStyle(Color.softWhite.opacity(0.8))
                Spacer()
                Text(appVersionLabel)
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
        @ViewBuilder
        private var debugSection: some View {
            Section {
                if let info = debugTreeInfo {
                    HStack {
                        Text("Total Blocks")
                            .foregroundStyle(Color.softWhite.opacity(0.8))
                        Spacer()
                        Text("\(info.totalBlocks)")
                            .foregroundStyle(Color.softWhite.opacity(0.5))
                    }
                    .listRowBackground(Color.white.opacity(0.05))

                    HStack {
                        Text("Days Since Planted")
                            .foregroundStyle(Color.softWhite.opacity(0.8))
                        Spacer()
                        Text(
                            "\(Calendar.current.dateComponents([.day], from: info.createdAt, to: Date()).day ?? 0) days"
                        )
                        .foregroundStyle(Color.softWhite.opacity(0.5))
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                }

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

            Section {
                ForEach([
                    (label: "+1 Day", days: 1),
                    (label: "+1 Week", days: 7),
                    (label: "+1 Month", days: 30),
                    (label: "+3 Months", days: 90),
                    (label: "+6 Months", days: 180)
                ], id: \.days) { item in
                    Button {
                        onTimeTravel?(item.days)
                        dismiss()
                    } label: {
                        Text(item.label)
                            .foregroundStyle(Color.softWhite.opacity(0.8))
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                }
            } header: {
                Text("Time Travel")
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
