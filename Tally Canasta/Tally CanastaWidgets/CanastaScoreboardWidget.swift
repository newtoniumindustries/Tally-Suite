import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Snapshot Models

struct CanastaTeamSnapshot: Identifiable, Sendable {
    let id: Int
    let name: String
    let total: Int
    let openingMeld: Int
    let lastRoundDelta: Int?
    let colorToken: String

    var color: Color {
        switch colorToken {
        case "blue": return .blue
        case "red": return .red
        case "green": return .green
        default: return .blue
        }
    }

    func progress(targetScore: Int) -> Double {
        guard targetScore > 0 else { return 0 }
        return min(max(Double(total) / Double(targetScore), 0), 1)
    }

    func percent(targetScore: Int) -> Int {
        Int((progress(targetScore: targetScore) * 100).rounded())
    }
}

struct CanastaRoundSnapshot: Identifiable, Sendable {
    let id: Int
    let roundNumber: Int
    let team1Score: Int
    let team2Score: Int
    let team3Score: Int?
}

struct CanastaScoreboardSnapshot: Sendable {
    let gameID: UUID
    let targetScore: Int
    let isThreeTeams: Bool
    let teams: [CanastaTeamSnapshot]
    let recentRounds: [CanastaRoundSnapshot]
    let totalRoundsPlayed: Int
    let winner: String?
    let isTiedAtOrAboveTarget: Bool

    var lastRoundNumber: Int? {
        recentRounds.first?.roundNumber
    }

    @MainActor
    static func from(_ game: CanastaGame) -> CanastaScoreboardSnapshot {
        let descending = Array(game.sortedRounds.reversed())
        let latestRound = descending.first

        var teams: [CanastaTeamSnapshot] = [
            CanastaTeamSnapshot(
                id: 1,
                name: game.team1Name,
                total: game.team1Total,
                openingMeld: game.openingMeld(for: game.team1Total),
                lastRoundDelta: latestRound?.team1RoundTotal,
                colorToken: "blue"
            ),
            CanastaTeamSnapshot(
                id: 2,
                name: game.team2Name,
                total: game.team2Total,
                openingMeld: game.openingMeld(for: game.team2Total),
                lastRoundDelta: latestRound?.team2RoundTotal,
                colorToken: "red"
            )
        ]

        if game.isThreeTeams {
            teams.append(
                CanastaTeamSnapshot(
                    id: 3,
                    name: game.team3Name,
                    total: game.team3Total,
                    openingMeld: game.openingMeld(for: game.team3Total),
                    lastRoundDelta: latestRound?.team3RoundTotal,
                    colorToken: "green"
                )
            )
        }

        let roundSnapshots = descending.prefix(5).map { round in
            CanastaRoundSnapshot(
                id: round.roundNumber,
                roundNumber: round.roundNumber,
                team1Score: round.team1RoundTotal,
                team2Score: round.team2RoundTotal,
                team3Score: game.isThreeTeams ? round.team3RoundTotal : nil
            )
        }

        return CanastaScoreboardSnapshot(
            gameID: game.gameID,
            targetScore: game.targetScore,
            isThreeTeams: game.isThreeTeams,
            teams: teams,
            recentRounds: roundSnapshots,
            totalRoundsPlayed: descending.count,
            winner: game.winner,
            isTiedAtOrAboveTarget: game.isTiedAtOrAboveTarget
        )
    }

    static let preview = CanastaScoreboardSnapshot(
        gameID: UUID(),
        targetScore: 5000,
        isThreeTeams: false,
        teams: [
            CanastaTeamSnapshot(id: 1, name: "Team 1", total: 2450, openingMeld: 90, lastRoundDelta: 850, colorToken: "blue"),
            CanastaTeamSnapshot(id: 2, name: "Team 2", total: 1800, openingMeld: 90, lastRoundDelta: 420, colorToken: "red")
        ],
        recentRounds: [
            CanastaRoundSnapshot(id: 4, roundNumber: 4, team1Score: 850, team2Score: 420, team3Score: nil),
            CanastaRoundSnapshot(id: 3, roundNumber: 3, team1Score: 600, team2Score: 510, team3Score: nil),
            CanastaRoundSnapshot(id: 2, roundNumber: 2, team1Score: 450, team2Score: 590, team3Score: nil),
            CanastaRoundSnapshot(id: 1, roundNumber: 1, team1Score: 550, team2Score: 280, team3Score: nil)
        ],
        totalRoundsPlayed: 4,
        winner: nil,
        isTiedAtOrAboveTarget: false
    )
}

// MARK: - Timeline Entry & Provider

struct CanastaScoreboardEntry: TimelineEntry {
    let date: Date
    let snapshot: CanastaScoreboardSnapshot?
}

struct CanastaScoreboardProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CanastaScoreboardEntry {
        CanastaScoreboardEntry(date: .now, snapshot: .preview)
    }

    func snapshot(for configuration: SelectCanastaGameIntent, in context: Context) async -> CanastaScoreboardEntry {
        if context.isPreview {
            return CanastaScoreboardEntry(date: .now, snapshot: .preview)
        }
        return await loadEntry(for: configuration)
    }

    func timeline(for configuration: SelectCanastaGameIntent, in context: Context) async -> Timeline<CanastaScoreboardEntry> {
        let entry = await loadEntry(for: configuration)
        let refresh = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now.addingTimeInterval(3600)
        return Timeline(entries: [entry], policy: .after(refresh))
    }

    private func loadEntry(for configuration: SelectCanastaGameIntent) async -> CanastaScoreboardEntry {
        let snapshot: CanastaScoreboardSnapshot? = await MainActor.run {
            guard let game = TallyCanastaWidgetStore.resolveGame(id: configuration.game?.id) else {
                return nil
            }
            return CanastaScoreboardSnapshot.from(game)
        }
        return CanastaScoreboardEntry(date: .now, snapshot: snapshot)
    }
}

// MARK: - Widget Definition

struct CanastaScoreboardWidget: Widget {
    let kind = "TallyCanastaScoreboardWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectCanastaGameIntent.self,
            provider: CanastaScoreboardProvider()
        ) { entry in
            CanastaScoreboardWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Canasta Scoreboard")
        .description("Track live Canasta scores, opening meld requirements, and recent rounds with 1-tap round entry.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

// MARK: - Views

struct CanastaScoreboardWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CanastaScoreboardEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            contentView(for: snapshot)
                .widgetURL(TallyCanastaDeepLink.game(snapshot.gameID).url)
        } else {
            emptyState
                .widgetURL(TallyCanastaDeepLink.newGame.url)
        }
    }

    @ViewBuilder
    private func contentView(for snapshot: CanastaScoreboardSnapshot) -> some View {
        switch family {
        case .systemSmall:
            SmallCanastaView(snapshot: snapshot)
        case .systemMedium:
            MediumCanastaView(snapshot: snapshot)
        case .systemLarge:
            LargeCanastaView(snapshot: snapshot)
        case .accessoryRectangular:
            AccessoryRectangularCanastaView(snapshot: snapshot)
        case .accessoryInline:
            AccessoryInlineCanastaView(snapshot: snapshot)
        default:
            SmallCanastaView(snapshot: snapshot)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "suit.club.fill")
                .font(.title2)
                .foregroundStyle(.red)
            Text("Tally: Canasta")
                .font(.headline)
            Text("Tap to start a new game")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private func formattedDelta(_ score: Int) -> String {
    score >= 0 ? "+\(score)" : "\(score)"
}

private struct SmallCanastaView: View {
    let snapshot: CanastaScoreboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text("Canasta")
                    .font(.caption.bold())
                Spacer(minLength: 2)
                Text("Target \(snapshot.targetScore)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Divider()

            VStack(spacing: snapshot.isThreeTeams ? 4 : 6) {
                ForEach(snapshot.teams) { team in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(team.color)
                                .frame(width: 6, height: 6)
                            Text(team.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text("\(team.total)")
                                .font(.system(snapshot.isThreeTeams ? .subheadline : .headline, design: .rounded).weight(.heavy))
                                .monospacedDigit()
                        }
                        Text("Meld req: \(team.openingMeld)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(team.color)
                            .monospacedDigit()
                    }
                }
            }

            Spacer(minLength: 0)

            if let winner = snapshot.winner {
                Text("\(winner) Wins!")
                    .font(.caption2.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.18), in: Capsule())
                    .foregroundStyle(.green)
            } else {
                Link(destination: TallyCanastaDeepLink.newRound(gameID: snapshot.gameID).url) {
                    Label("Record Round", systemImage: "plus")
                        .font(.caption2.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct TeamColumnCard: View {
    let team: CanastaTeamSnapshot
    let targetScore: Int
    let lastRoundNumber: Int?
    let showLastRound: Bool
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 3 : 4) {
            Text(team.name)
                .font(compact ? .caption2.bold() : .caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text("\(team.total)")
                .font(.system(compact ? .title3 : .title2, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text("Meld req: \(team.openingMeld)")
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(team.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(team.color)

            HStack(spacing: 4) {
                ProgressView(value: team.progress(targetScore: targetScore))
                    .tint(team.color)
                Text("\(team.percent(targetScore: targetScore))%")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if showLastRound, let delta = team.lastRoundDelta, let roundNum = lastRoundNumber {
                Text("R\(roundNum): \(formattedDelta(delta))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .padding(.vertical, compact ? 5 : 6)
        .background(team.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct MediumCanastaView: View {
    let snapshot: CanastaScoreboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Tally: Canasta • Target \(snapshot.targetScore)")
                    .font(.caption.bold())
                    .lineLimit(1)
                    .monospacedDigit()
                Spacer(minLength: 4)
                if let winner = snapshot.winner {
                    Text("\(winner) Wins!")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.18), in: Capsule())
                        .foregroundStyle(.green)
                } else {
                    Link(destination: TallyCanastaDeepLink.newRound(gameID: snapshot.gameID).url) {
                        Label("Record Round", systemImage: "plus")
                            .font(.caption2.bold())
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
            }

            HStack(spacing: 6) {
                ForEach(snapshot.teams) { team in
                    TeamColumnCard(
                        team: team,
                        targetScore: snapshot.targetScore,
                        lastRoundNumber: snapshot.lastRoundNumber,
                        showLastRound: true,
                        compact: snapshot.isThreeTeams
                    )
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct LargeCanastaView: View {
    let snapshot: CanastaScoreboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Tally: Canasta • Target \(snapshot.targetScore)")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .monospacedDigit()
                Spacer(minLength: 4)
                Text(snapshot.totalRoundsPlayed == 0 ? "New Game" : "Round \(snapshot.totalRoundsPlayed) Played")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if let winner = snapshot.winner {
                Text("\(winner) WINS!")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Color.green, in: RoundedRectangle(cornerRadius: 7))
            } else if snapshot.isTiedAtOrAboveTarget {
                Text("Tied at Target — Play Another Round")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 7))
            }

            HStack(spacing: 6) {
                ForEach(snapshot.teams) { team in
                    TeamColumnCard(
                        team: team,
                        targetScore: snapshot.targetScore,
                        lastRoundNumber: snapshot.lastRoundNumber,
                        showLastRound: false,
                        compact: snapshot.isThreeTeams
                    )
                }
            }

            Divider()

            if snapshot.recentRounds.isEmpty {
                Spacer(minLength: 0)
                Text("No rounds recorded yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 5) {
                    ForEach(snapshot.recentRounds.prefix(4)) { round in
                        HStack(spacing: 6) {
                            Text("R\(round.roundNumber)")
                                .font(.caption2.bold().monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 26, alignment: .leading)

                            Text(formattedDelta(round.team1Score))
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)

                            Text(formattedDelta(round.team2Score))
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)

                            if let t3 = round.team3Score {
                                Text(formattedDelta(t3))
                                    .font(.system(.caption, design: .rounded).weight(.bold))
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            Divider()

            HStack(spacing: 6) {
                if snapshot.winner == nil {
                    Link(destination: TallyCanastaDeepLink.newRound(gameID: snapshot.gameID).url) {
                        Label("Record Round", systemImage: "plus")
                            .font(.caption2.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.white)
                    }
                }

                Link(destination: TallyCanastaDeepLink.howToPlay.url) {
                    Label("Rules", systemImage: "book.pages")
                        .font(.caption2.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                }

                Link(destination: TallyCanastaDeepLink.newGame.url) {
                    Label("New Game", systemImage: "plus.circle")
                        .font(.caption2.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct AccessoryRectangularCanastaView: View {
    let snapshot: CanastaScoreboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Canasta • Target \(snapshot.targetScore)")
                .font(.caption.bold())
                .lineLimit(1)
                .monospacedDigit()

            let line = snapshot.teams.prefix(2)
                .map { "\($0.name): \($0.total) (M\($0.openingMeld))" }
                .joined(separator: " ")
            Text(line)
                .font(.caption2.monospacedDigit())
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AccessoryInlineCanastaView: View {
    let snapshot: CanastaScoreboardSnapshot

    var body: some View {
        let scores = snapshot.teams.prefix(2).map { "\($0.total)" }.joined(separator: "–")
        let meld = snapshot.teams.first?.openingMeld ?? 50
        Text("Canasta: \(scores) (Meld \(meld))")
    }
}
