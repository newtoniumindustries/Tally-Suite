import SwiftUI
import SwiftData

public struct PlayerRosterView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TallyPlayer.name) private var players: [TallyPlayer]
    
    @State private var newPlayerName = ""
    
    public init() {} // Required for Swift Packages!
    
    public var body: some View {
        NavigationStack {
            List {
                Section("Add New Player") {
                    HStack {
                        TextField("Player Name", text: $newPlayerName)
                        Button("Add") {
                            let player = TallyPlayer(name: newPlayerName)
                            modelContext.insert(player)
                            newPlayerName = ""
                        }
                        .disabled(newPlayerName.isEmpty)
                    }
                }
                
                Section("Master Roster") {
                    if players.isEmpty {
                        Text("No players added yet.").foregroundColor(.secondary)
                    } else {
                        ForEach(players) { player in
                            Text(player.name)
                        }
                        .onDelete(perform: deletePlayers)
                    }
                }
            }
            .navigationTitle("Player Roster")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func deletePlayers(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(players[index])
        }
    }
}
