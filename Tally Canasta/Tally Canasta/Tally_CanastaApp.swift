import SwiftData
import SwiftUI
import TallyCore

@main
struct Tally_CanastaApp: App {
    private let containerResult: TallyContainerResult

    init() {
        self.containerResult = TallyDataConfig.makeContainer(for: [
            CanastaGame.self,
            Round.self,
            RuleSet.self,
            TallyPlayer.self
        ])
    }

    var body: some Scene {
        WindowGroup {
            TallyAppContainerView(result: containerResult, appDisplayName: "Tally: Canasta") {
                ContentView()
            }
        }
    }
}
