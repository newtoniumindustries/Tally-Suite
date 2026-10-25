import SwiftUI
import SwiftData
import TallyCore

@main
struct Tally_CanastaApp: App {
    var sharedModelContainer: ModelContainer = {
        // We must explicitly list ALL of our root SwiftData models here
        let schema = Schema([
            CanastaGame.self,
            RuleSet.self // <--- This was missing!
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
            ContentView()
        }
        .modelContainer(for: [CanastaGame.self, RuleSet.self, TallyPlayer.self])
    }
}


