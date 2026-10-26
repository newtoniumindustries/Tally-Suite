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
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            GameType.self,
            Team.self,
            Match.self,
            MatchScoreEntry.self
        ])
    }
}
