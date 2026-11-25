//
//  Tally_ItApp.swift
//  Tally It
//
//  Created by Eamon Newton on 10/25/26.
//

import SwiftUI
import SwiftData

@main
struct Tally_ItApp: App {
    private let container: ModelContainer?
    private let isUsingFallbackStore: Bool
    private let startupErrorDescription: String?

    init() {
        let schema = Schema([
            GameType.self,
            Team.self,
            Match.self,
            MatchScoreEntry.self
        ])

        let persistentConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            self.container = try ModelContainer(for: schema, configurations: [persistentConfig])
            self.isUsingFallbackStore = false
            self.startupErrorDescription = nil
        } catch {
            let fallbackConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            if let fallbackContainer = try? ModelContainer(for: schema, configurations: [fallbackConfig]) {
                self.container = fallbackContainer
                self.isUsingFallbackStore = true
                self.startupErrorDescription = "Saved data could not be loaded. Changes in this session are temporary."
            } else {
                self.container = nil
                self.isUsingFallbackStore = false
                self.startupErrorDescription = "Unable to initialize local storage. Please restart the app or check available device storage."
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                VStack(spacing: 0) {
                    if isUsingFallbackStore, let warning = startupErrorDescription {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(warning)
                                .font(.caption.bold())
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange)
                    }

                    ContentView()
                }
                .modelContainer(container)
            } else {
                ContentUnavailableView(
                    "Storage Unavailable",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(startupErrorDescription ?? "Please restart Tally: It to try again.")
                )
            }
        }
    }
}
