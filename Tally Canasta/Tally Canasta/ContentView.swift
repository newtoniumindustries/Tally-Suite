import SwiftData
import SwiftUI
import TallyCore

// MARK: - 1. Dashboard

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CanastaGame.date, order: .reverse) private var games: [CanastaGame]

    @State private var showingNewGameSheet = false
    @State private var showingHowToPlay = false
    @State private var showingRoster = false
    @State private var gamePendingDelete: CanastaGame?
    @State private var saveErrorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if games.isEmpty {
                    ContentUnavailableView(
                        "No Canasta Games Yet",
                        systemImage: "suit.club.fill",
                        description: Text("Tap + to start a new game and track rounds, melds, and canastas.")
                    )
                } else {
                    List {
                        ForEach(games) { game in
                            NavigationLink(value: game) {
                                GameDashboardRow(game: game)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    gamePendingDelete = game
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Button(action: { showingHowToPlay = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "book.pages")
                            .accessibilityHidden(true)
                        Text("How to Play Canasta")
                            .fontWeight(.medium)
                    }
                    .font(.footnote)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground))
                    .foregroundStyle(.tint)
                }
            }
            .navigationTitle("Tally: Canasta")
            .navigationDestination(for: CanastaGame.self) { game in
                GameLedgerView(game: game)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        Button("Roster", systemImage: "person.3") { showingRoster = true }
                        Button("New Game", systemImage: "plus") { showingNewGameSheet = true }
                    }
                }
            }
            .sheet(isPresented: $showingNewGameSheet) { NewGameSheet() }
            .sheet(isPresented: $showingHowToPlay) { HowToPlaySheet() }
            .sheet(isPresented: $showingRoster) {
                PlayerRosterView()
                    .presentationDetents([.medium, .large])
            }
            .alert(
                "Delete Game?",
                isPresented: Binding(
                    get: { gamePendingDelete != nil },
                    set: { if !$0 { gamePendingDelete = nil } }
                ),
                presenting: gamePendingDelete
            ) { game in
                Button("Delete Game", role: .destructive) {
                    deleteGame(game)
                    gamePendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    gamePendingDelete = nil
                }
            } message: { game in
                let matchup = game.isThreeTeams
                    ? "\(game.team1Name) vs \(game.team2Name) vs \(game.team3Name)"
                    : "\(game.team1Name) vs \(game.team2Name)"
                let roundLabel = game.rounds.count == 1 ? "1 round" : "\(game.rounds.count) rounds"
                Text("This permanently deletes \(matchup) and its \(roundLabel).")
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

    private func deleteGame(_ game: CanastaGame) {
        modelContext.delete(game)
        if let error = modelContext.saveReportingError() {
            saveErrorMessage = error
        }
    }
}

private struct GameDashboardRow: View {
    let game: CanastaGame

    private var matchupTitle: String {
        game.isThreeTeams
            ? "\(game.team1Name) vs \(game.team2Name) vs \(game.team3Name)"
            : "\(game.team1Name) vs \(game.team2Name)"
    }

    private var scoreLine: String {
        game.isThreeTeams
            ? "\(game.team1Total) / \(game.team2Total) / \(game.team3Total)"
            : "\(game.team1Total) / \(game.team2Total)"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(matchupTitle)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("Target: \(game.targetScore)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let winner = game.winner {
                        Text("• Winner: \(winner)")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            Text(scoreLine)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.primary)
        }
    }
}
