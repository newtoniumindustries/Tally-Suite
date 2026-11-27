import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Snapshot & Timeline

struct StandingsWidgetSnapshot: Sendable {
    let categoryName: String
    let gameTypeID: UUID?
    let matchCount: Int
    let rows: [TeamStandingRow]

    static let preview = StandingsWidgetSnapshot(
        categoryName: "Cornhole",
        gameTypeID: nil,
        matchCount: 8,
        rows: [
            TeamStandingRow(id: UUID(), teamName: "Team Alpha", wins: 6, losses: 2, ties: 0, totalPoints: 158),
            TeamStandingRow(id: UUID(), teamName: "Team Bravo", wins: 4, losses: 4, ties: 0, totalPoints: 136),
            TeamStandingRow(id: UUID(), teamName: "Team Delta", wins: 2, losses: 5, ties: 1, totalPoints: 112)
        ]
    )
}

struct StandingsWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: StandingsWidgetSnapshot
}

struct StandingsWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StandingsWidgetEntry {
        StandingsWidgetEntry(date: .now, snapshot: .preview)
    }

    func snapshot(for configuration: SelectStandingsFilterIntent, in context: Context) async -> StandingsWidgetEntry {
        if context.isPreview {
            return StandingsWidgetEntry(date: .now, snapshot: .preview)
        }
        return await loadEntry(for: configuration)
    }

    func timeline(for configuration: SelectStandingsFilterIntent, in context: Context) async -> Timeline<StandingsWidgetEntry> {
        let entry = await loadEntry(for: configuration)
        let refresh = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now.addingTimeInterval(3600)
        return Timeline(entries: [entry], policy: .after(refresh))
    }

    private func loadEntry(for configuration: SelectStandingsFilterIntent) async -> StandingsWidgetEntry {
        let filterID = configuration.gameType?.id
        let fallbackName = configuration.gameType?.name
        let snapshot: StandingsWidgetSnapshot = await MainActor.run {
            let completedMatches = TallyItWidgetStore.fetchMatches().filter { $0.isCompleted }
            let gameTypes = TallyItWidgetStore.fetchGameTypes()

            let filtered: [Match]
            let categoryName: String
            let preferLower: Bool

            if let filterID {
                filtered = completedMatches.filter { $0.gameTypeID == filterID }
                let matchedType = gameTypes.first(where: { $0.id == filterID })
                categoryName = matchedType?.name ?? filtered.first?.gameTypeName ?? fallbackName ?? "Game"
                preferLower = matchedType?.lowestScoreWins ?? filtered.first?.lowestScoreWins ?? false
            } else {
                filtered = completedMatches
                categoryName = "All Games"
                preferLower = false
            }

            let rows = StandingsCalculator.compute(
                from: filtered,
                preferLowerPointsOnTie: preferLower
            )
            return StandingsWidgetSnapshot(
                categoryName: categoryName,
                gameTypeID: filterID,
                matchCount: filtered.count,
                rows: rows
            )
        }
        return StandingsWidgetEntry(date: .now, snapshot: snapshot)
    }
}

// MARK: - Widget Definition

struct StandingsWidget: Widget {
    let kind = "TallyItStandingsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectStandingsFilterIntent.self,
            provider: StandingsWidgetProvider()
        ) { entry in
            StandingsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Standings Leaderboard")
        .description("View top team win/loss rankings for all games or a specific game type.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Views

struct StandingsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StandingsWidgetEntry

    private var maxRows: Int {
        family == .systemSmall ? 3 : 5
    }

    var body: some View {
        let snapshot = entry.snapshot
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "trophy.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                Text(family == .systemSmall ? snapshot.categoryName : "Standings • \(snapshot.categoryName)")
                    .font(.caption.bold())
                    .lineLimit(1)
                Spacer(minLength: 4)
                if family != .systemSmall {
                    Text("\(snapshot.matchCount) \(snapshot.matchCount == 1 ? "Match" : "Matches")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Divider()

            if snapshot.rows.isEmpty {
                Spacer(minLength: 0)
                VStack(spacing: 4) {
                    Text("No Completed Matches")
                        .font(.caption.bold())
                    Text("Finish a match to see rankings.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                VStack(spacing: family == .systemSmall ? 6 : 5) {
                    ForEach(Array(snapshot.rows.prefix(maxRows).enumerated()), id: \.element.id) { index, row in
                        let winPct = Int((row.winPercentage * 100).rounded())
                        let record = "\(row.wins)W-\(row.losses)L" + (row.ties > 0 ? "-\(row.ties)T" : "")
                        HStack(spacing: 6) {
                            Text("#\(index + 1)")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(index == 0 ? Color.orange : Color.secondary)
                                .frame(width: 20, alignment: .leading)

                            Text(row.teamName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)

                            Spacer(minLength: 4)

                            Text(record)
                                .font(.caption2.bold().monospacedDigit())
                                .foregroundStyle(.secondary)

                            if family != .systemSmall {
                                Text("\(winPct)% Win")
                                    .font(.caption2.bold().monospacedDigit())
                                    .foregroundStyle(row.winPercentage >= 0.5 ? Color.green : Color.secondary)
                                    .frame(width: 54, alignment: .trailing)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(TallyItDeepLink.standings(gameTypeID: snapshot.gameTypeID).url)
    }
}
