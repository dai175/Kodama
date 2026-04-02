//
//  KodamaApp.swift
//  Kodama
//
//  Created by Daisuke Ooba on 2026/04/02.
//

import SwiftData
import SwiftUI

@main
struct KodamaApp: App {
    @State private var appState = AppState()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            BonsaiTree.self,
            VoxelBlock.self,
            Interaction.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
        .modelContainer(sharedModelContainer)
    }
}
