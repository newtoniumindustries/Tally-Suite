import SwiftData
import SwiftUI
import TallyCore

// MARK: - 2. Standings by Game Type

private struct GameTypeFilterOption: Identifiable, Equatable {
    let id: UUID
    let name: String
    let lowestScoreWins: Bool
}

struct StandingsView: View {
    @Query(
        filter: #Predicate<Match> { $0.isCompleted },
        sort: \Match.completedAt,
        order: .reverse
    ) private var allCompletedMatches: [Match]
    @Query(sort: \GameType.name) private var gameTypes: [GameType]

    @Binding var selectedGameTypeID: UUID?

    /// Union of saved game types plus any deleted game types that still have completed matches.
    private var filterOptions: [GameTypeFilterOption] {
        var byID: [UUID: GameTypeFilterOption] = [:]
        for game in gameTypes {
            byID[game.id] = GameTypeFilterOption(
                id: game.id,
                name: game.name,
                lowestScoreWins: game.lowestScoreWins
            )
        }
        for match in allCompletedMatches where byID[match.gameTypeID] == nil {
            byID[match.gameTypeID] = GameTypeFilterOption(
                id: match.gameTypeID,
                name: match.gameTypeName,
                lowestScoreWins: match.lowestScoreWins
            )
        }
        return byID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var selectedOption: GameTypeFilterOption? {
        guard let id = selectedGameTypeID else { return nil }
        return filterOptions.first(where: { $0.id == id })
    }

    private var selectedGameName: String {
        selectedOption?.name ?? "All Games"
    }

    private var filteredMatches: [Match] {
        guard let filterID = selectedOption?.id else {
            return allCompletedMatches
        }
        return allCompletedMatches.filter { $0.gameTypeID == filterID }
    }

    private var standings: [TeamStandingRow] {
        StandingsCalculator.compute(
            from: filteredMatches,
            preferLowerPointsOnTie: selectedOption?.lowestScoreWins ?? false
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterPillButton(
                            title: "All Games",
                            isSelected: selectedOption == nil
                        ) {
                            selectedGameTypeID = nil
                        }

                        ForEach(filterOptions) { option in
                            FilterPillButton(
                                title: option.name,
                                isSelected: selectedOption?.id == option.id
                            ) {
                                selectedGameTypeID = option.id
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .background(Color(.systemGroupedBackground))

                if standings.isEmpty {
                    ContentUnavailableView(
                        "No Standings for \(selectedGameName)",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Finish a match to see team win/loss records.")
                    )
                } else {
                    List {
                        Section {
                            HStack {
                                StatSummaryBox(title: "Category", value: selectedGameName)
                                Divider()
                                StatSummaryBox(title: "Matches", value: "\(filteredMatches.count)")
                                Divider()
                                StatSummaryBox(title: "Top Team", value: standings.first?.teamName ?? "-")
                            }
                            .padding(.vertical, 4)
                        }

                        Section("Leaderboard") {
                            ForEach(Array(standings.enumerated()), id: \.element.id) { index, row in
                                let winPct = Int((row.winPercentage * 100).rounded())
                                HStack(spacing: 12) {
                                    Text("#\(index + 1)")
                                        .font(.subheadline.weight(.heavy))
                                        .foregroundStyle(index == 0 ? Color.orange : Color.secondary)
                                        .frame(minWidth: 32, alignment: .leading)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(row.teamName)
                                            .font(.headline)
                                        Text("\(row.gamesPlayed) Played  |  \(row.totalPoints) Total Pts")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text("\(row.wins)W - \(row.losses)L" + (row.ties > 0 ? " - \(row.ties)T" : ""))
                                            .font(.subheadline.bold())
                                        Text("\(winPct)% Win")
                                            .font(.caption.bold())
                                            .foregroundStyle(row.winPercentage >= 0.5 ? Color.green : Color.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Standings")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("All Games") { selectedGameTypeID = nil }
                        Divider()
                        ForEach(filterOptions) { option in
                            Button(option.name) { selectedGameTypeID = option.id }
                        }
                    } label: {
                        Label("Filter Game", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }
}

struct FilterPillButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .bold : .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground), in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct StatSummaryBox: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.subheadline.bold())
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
