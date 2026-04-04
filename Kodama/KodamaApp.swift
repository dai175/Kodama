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

        do {
            let appSupportURL = try Self.persistentStoreDirectory()
            let storeURL = appSupportURL.appendingPathComponent("default.store")
            let modelConfiguration = ModelConfiguration(
                "default",
                schema: schema,
                url: storeURL
            )
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                // Destructive fallback for incompatible local schema during prototyping.
                try? FileManager.default.removeItem(at: storeURL)
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            }
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

    private static func persistentStoreDirectory() throws -> URL {
        let appSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        try FileManager.default.createDirectory(
            at: appSupportURL,
            withIntermediateDirectories: true
        )
        return appSupportURL
    }
}
