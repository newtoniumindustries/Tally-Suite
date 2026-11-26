import SwiftData
import SwiftUI
import TallyCore

@main
struct Tally_CountdownApp: App {
    private let containerResult: TallyContainerResult

    init() {
        self.containerResult = TallyDataConfig.makeContainer(for: [
            CountdownItem.self
        ])
    }

    var body: some Scene {
        WindowGroup {
            TallyAppContainerView(result: containerResult, appDisplayName: "Tally: Countdown") {
                ContentView()
            }
        }
    }
}
