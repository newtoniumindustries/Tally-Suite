//
//  Tally_ItApp.swift
//  Tally It
//
//  Created by Eamon Newton on 10/25/26.
//

import SwiftData
import SwiftUI
import TallyCore
import UIKit

@main
struct Tally_ItApp: App {
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
        self.containerResult = TallyItAppGroup.makeContainerResult()
    }

    var body: some Scene {
        WindowGroup {
            TallyAppContainerView(result: containerResult, appDisplayName: "Tally: It") {
                ContentView()
            }
        }
    }
}
