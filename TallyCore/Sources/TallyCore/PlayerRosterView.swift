import SwiftUI
import SwiftData

public struct PlayerRosterView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TallyPlayer.name) private var players: [TallyPlayer]

    @State private var newPlayerName = ""

    public init() {}

    private var trimmedName: String {
        newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicateName: Bool {
        !trimmedName.isEmpty && players.contains {
            $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Add New Player") {
                    HStack {
                        TextField("Player Name", text: $newPlayerName)
                            .submitLabel(.done)
                            .onSubmit(addPlayer)

                        Button("Add", action: addPlayer)
                            .disabled(trimmedName.isEmpty || isDuplicateName)
                    }

                    if isDuplicateName {
                        Text("A player with this name is already in the roster.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Master Roster") {
                    if players.isEmpty {
                        Text("No players added yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(players) { player in
                            Text(player.name)
                        }
                        .onDelete(perform: deletePlayers)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Player Roster")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func addPlayer() {
        let name = trimmedName
        guard !name.isEmpty, !isDuplicateName else { return }
        let player = TallyPlayer(name: name)
        modelContext.insert(player)
        try? modelContext.save()
        newPlayerName = ""
    }

    private func deletePlayers(offsets: IndexSet) {
        let snapshot = players
        let toDelete = offsets.compactMap { snapshot.indices.contains($0) ? snapshot[$0] : nil }
        for player in toDelete {
            modelContext.delete(player)
        }
        try? modelContext.save()
    }
}
