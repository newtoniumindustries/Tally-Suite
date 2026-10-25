
import Foundation
import SwiftData

public struct TallyDataConfig {
    // Changed 'var' to 'let' to make it concurrency-safe
    public static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TallyPlayer.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create Tally ModelContainer: \(error)")
        }
    }()
}
