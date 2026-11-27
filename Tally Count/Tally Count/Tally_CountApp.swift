import SwiftData
import SwiftUI
import TallyCore

@main
struct Tally_CountApp: App {
    private let containerResult: TallyContainerResult

    init() {
        self.containerResult = TallyCountAppGroup.makeContainerResult()
    }

    var body: some Scene {
        WindowGroup {
            TallyAppContainerView(result: containerResult, appDisplayName: "Tally: Count") {
                ContentView()
            }
        }
    }
}
