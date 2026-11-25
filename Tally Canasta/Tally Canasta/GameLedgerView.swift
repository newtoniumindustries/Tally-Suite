import SwiftData
import SwiftUI
import TallyCore

// MARK: - 4. The Ledger

struct GameLedgerView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var game: CanastaGame

    @State private var showingNewRoundEntry = false
    @State private var roundToEdit: Round?
    @State private var saveErrorMessage: String?

    private var roundsDescending: [Round] {
        game.sortedRounds.reversed()
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if let winner = game.winner {
                    Text("\(winner) WINS!")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green)
                } else if game.isTiedAtOrAboveTarget {
                    Text("Tied at Target — Play Another Round to Break Tie")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                }

                HStack(spacing: 0) {
                    TeamHeaderView(
                        name: game.team1Name,
                        total: game.team1Total,
                        meldReq: game.openingMeld(for: game.team1Total),
                        color: .blue
                    )
                    Divider().frame(height: 80)
                    TeamHeaderView(
                        name: game.team2Name,
                        total: game.team2Total,
                        meldReq: game.openingMeld(for: game.team2Total),
                        color: .red
                    )

                    if game.isThreeTeams {
                        Divider().frame(height: 80)
                        TeamHeaderView(
                            name: game.team3Name,
                            total: game.team3Total,
                            meldReq: game.openingMeld(for: game.team3Total),
                            color: .green
                        )
                    }
                }
                Divider()
            }

            List {
                if roundsDescending.isEmpty {
                    Text("No rounds recorded yet. Tap Record Round below to begin.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(roundsDescending) { round in
                        Button(action: { roundToEdit = round }) {
                            HStack {
                                Text("R\(round.roundNumber)")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 28, alignment: .leading)

                                Text(formattedRoundScore(round.team1RoundTotal))
                                    .font(.system(.body, design: .rounded).weight(.bold))
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity, alignment: .center)

                                Text(formattedRoundScore(round.team2RoundTotal))
                                    .font(.system(.body, design: .rounded).weight(.bold))
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity, alignment: .center)

                                if game.isThreeTeams {
                                    Text(formattedRoundScore(round.team3RoundTotal))
                                        .font(.system(.body, design: .rounded).weight(.bold))
                                        .monospacedDigit()
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                        .accessibilityLabel(roundAccessibilityLabel(round))
                    }
                    .onDelete(perform: deleteRounds)
                }
            }

            let gameFinished = game.winner != nil
            Button(action: { showingNewRoundEntry = true }) {
                Text(gameFinished ? "Game Complete" : "Record Round")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(gameFinished ? Color.secondary.opacity(0.35) : Color.accentColor)
                    .foregroundStyle(gameFinished ? Color.secondary : Color.white)
                    .clipShape(.rect(cornerRadius: 10))
            }
            .padding()
            .disabled(gameFinished)
        }
        .navigationTitle("Scoreboard")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingNewRoundEntry) { RoundEntrySheet(game: game, editingRound: nil) }
        .sheet(item: $roundToEdit) { round in RoundEntrySheet(game: game, editingRound: round) }
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

    private func formattedRoundScore(_ score: Int) -> String {
        score >= 0 ? "+\(score)" : "\(score)"
    }

    private func roundAccessibilityLabel(_ round: Round) -> String {
        var parts = [
            "Round \(round.roundNumber)",
            "\(game.team1Name) \(formattedRoundScore(round.team1RoundTotal))",
            "\(game.team2Name) \(formattedRoundScore(round.team2RoundTotal))"
        ]
        if game.isThreeTeams {
            parts.append("\(game.team3Name) \(formattedRoundScore(round.team3RoundTotal))")
        }
        parts.append("Tap to edit")
        return parts.joined(separator: ", ")
    }

    private func deleteRounds(offsets: IndexSet) {
        let snapshot = roundsDescending
        let toDelete = offsets.compactMap { snapshot.indices.contains($0) ? snapshot[$0] : nil }
        for round in toDelete {
            game.rounds.removeAll(where: { $0.persistentModelID == round.persistentModelID })
            modelContext.delete(round)
        }
        game.renumberRounds()
        if let error = modelContext.saveReportingError() {
            saveErrorMessage = error
        }
    }
}

struct TeamHeaderView: View {
    let name: String
    let total: Int
    let meldReq: Int
    let color: Color

    @ScaledMetric(relativeTo: .largeTitle) private var scoreFontSize: CGFloat = 34

    var body: some View {
        VStack(spacing: 4) {
            Text(name)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text("\(total)")
                .font(.system(size: min(scoreFontSize, 46), weight: .heavy, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text("Meld req: \(meldReq)")
                .font(.caption2)
                .fontWeight(.medium)
                .monospacedDigit()
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(color.opacity(0.15))
                .foregroundStyle(color)
                .clipShape(.rect(cornerRadius: 6))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
        .padding(.vertical)
        .background(color.opacity(0.04))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), total \(total) points, opening meld requirement \(meldReq)")
    }
}
