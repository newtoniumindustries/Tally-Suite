import SwiftData
import SwiftUI
import TallyCore
import UIKit

@main
struct Tally_CountApp: App {
    private let containerResult: TallyContainerResult

    init() {
        TallyKeyboard.dismissHandler = {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
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
