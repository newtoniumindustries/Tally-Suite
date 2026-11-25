import SwiftData
import SwiftUI

public struct PlayerRosterView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TallyPlayer.name) private var players: [TallyPlayer]

    @State private var newPlayerName = ""
    @State private var saveErrorMessage: String?

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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                "Could Not Save",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "")
            }
        }
    }

    private func addPlayer() {
        let name = trimmedName
        guard !name.isEmpty, !isDuplicateName else { return }
        let player = TallyPlayer(name: name)
        modelContext.insert(player)
        if let error = modelContext.saveReportingError() {
            saveErrorMessage = error
        } else {
            newPlayerName = ""
        }
    }

    private func deletePlayers(offsets: IndexSet) {
        let snapshot = players
        let toDelete = offsets.compactMap { snapshot.indices.contains($0) ? snapshot[$0] : nil }
        for player in toDelete {
            modelContext.delete(player)
        }
        if let error = modelContext.saveReportingError() {
            saveErrorMessage = error
        }
    }
}
