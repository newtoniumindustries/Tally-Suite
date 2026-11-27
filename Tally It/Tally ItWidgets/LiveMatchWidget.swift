import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Snapshot Models

struct LiveMatchTeamSnapshot: Identifiable, Sendable {
    let id: UUID
    let teamName: String
    let score: Int
    let currentRoundDelta: Int
    let isWinner: Bool
    let roundHistory: [Int]
}

struct LiveMatchSnapshot: Sendable {
    let id: UUID
    let gameTypeName: String
    let currentRound: Int
    let maxRounds: Int?
    let targetScore: Int?
    let lowestScoreWins: Bool
    let trackRounds: Bool
    let isCompleted: Bool
    let winnerBannerText: String?
    let quickIncrements: [Int]
    let teams: [LiveMatchTeamSnapshot]
    let completedRoundCount: Int

    var isFinalRound: Bool {
        guard let maxRounds, maxRounds > 0 else { return false }
        return currentRound >= maxRounds
    }

    var roundBadge: String {
        if isCompleted { return "Final" }
        if !trackRounds { return "Live" }
        if let maxRounds, maxRounds > 0 {
            return "R\(min(currentRound, maxRounds))/\(maxRounds)"
        }
        return "R\(currentRound)"
    }

    var goalLabel: String? {
        if let targetScore, targetScore > 0 {
            return "Goal: \(targetScore) pts"
        }
        if let maxRounds, maxRounds > 0 {
            return "\(maxRounds) Rounds"
        }
        return lowestScoreWins ? "Lowest Wins" : nil
    }

    /// Selects up to 3 compact increment buttons: prefers 1 negative + up to 2 positive values.
    static func selectQuickIncrements(from raw: [Int]) -> [Int] {
        let negatives = raw.filter { $0 < 0 }.sorted(by: >) // closest to 0 first (e.g. -1)
        let positives = raw.filter { $0 > 0 }.sorted()      // smallest positives first (e.g. +1, +3)

        var chosen: [Int] = []
        if let neg = negatives.first {
            chosen.append(neg)
        }
        for pos in positives where chosen.count < 3 {
            chosen.append(pos)
        }
        if chosen.count < 3 {
            for neg in negatives.dropFirst() where chosen.count < 3 {
                chosen.insert(neg, at: 0)
            }
        }
        return chosen.isEmpty ? [-1, 1, 5] : chosen
    }

    @MainActor
    static func from(_ match: Match) -> LiveMatchSnapshot {
        let sorted = match.sortedEntries
        return LiveMatchSnapshot(
            id: match.id,
            gameTypeName: match.gameTypeName,
            currentRound: match.currentRound,
            maxRounds: match.activeMaxRounds,
            targetScore: match.targetScore,
            lowestScoreWins: match.lowestScoreWins,
            trackRounds: match.trackRounds,
            isCompleted: match.isCompleted,
            winnerBannerText: match.winnerBannerText,
            quickIncrements: selectQuickIncrements(from: match.increments),
            teams: sorted.map { entry in
                LiveMatchTeamSnapshot(
                    id: entry.id,
                    teamName: entry.teamName,
                    score: entry.score,
                    currentRoundDelta: entry.currentRoundDelta,
                    isWinner: match.isHighlightedWinner(entry),
                    roundHistory: entry.roundHistory
                )
            },
            completedRoundCount: match.completedRoundCount
        )
    }

    static let preview = LiveMatchSnapshot(
        id: UUID(),
        gameTypeName: "Cornhole",
        currentRound: 3,
        maxRounds: nil,
        targetScore: 21,
        lowestScoreWins: false,
        trackRounds: true,
        isCompleted: false,
        winnerBannerText: nil,
        quickIncrements: [-1, 1, 3],
        teams: [
            LiveMatchTeamSnapshot(id: UUID(), teamName: "Team Alpha", score: 14, currentRoundDelta: 3, isWinner: false, roundHistory: [6, 5]),
            LiveMatchTeamSnapshot(id: UUID(), teamName: "Team Bravo", score: 11, currentRoundDelta: 1, isWinner: false, roundHistory: [4, 6])
        ],
        completedRoundCount: 2
    )
}

// MARK: - Timeline Entry & Provider

struct LiveMatchWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: LiveMatchSnapshot?
}

struct LiveMatchWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LiveMatchWidgetEntry {
        LiveMatchWidgetEntry(date: .now, snapshot: .preview)
    }

    func snapshot(for configuration: SelectMatchWidgetIntent, in context: Context) async -> LiveMatchWidgetEntry {
        if context.isPreview {
            return LiveMatchWidgetEntry(date: .now, snapshot: .preview)
        }
        return await loadEntry(for: configuration)
    }

    func timeline(for configuration: SelectMatchWidgetIntent, in context: Context) async -> Timeline<LiveMatchWidgetEntry> {
        let entry = await loadEntry(for: configuration)
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        return Timeline(entries: [entry], policy: .after(refresh))
    }

    private func loadEntry(for configuration: SelectMatchWidgetIntent) async -> LiveMatchWidgetEntry {
        let snapshot: LiveMatchSnapshot? = await MainActor.run {
            guard let match = TallyItWidgetStore.resolveMatch(id: configuration.match?.id) else {
                return nil
            }
            return LiveMatchSnapshot.from(match)
        }
        return LiveMatchWidgetEntry(date: .now, snapshot: snapshot)
    }
}

// MARK: - Widget Definition

struct LiveMatchWidget: Widget {
    let kind = "TallyItLiveMatchWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectMatchWidgetIntent.self,
            provider: LiveMatchWidgetProvider()
        ) { entry in
            LiveMatchWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Live Scoreboard")
        .description("Score your active match right from the Home Screen with quick point buttons and round controls.")
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

struct LiveMatchWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LiveMatchWidgetEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            contentView(for: snapshot)
                .widgetURL(TallyItDeepLink.match(snapshot.id).url)
        } else {
            emptyState
                .widgetURL(TallyItDeepLink.newMatch.url)
        }
    }

    @ViewBuilder
    private func contentView(for snapshot: LiveMatchSnapshot) -> some View {
        switch family {
        case .systemSmall:
            SmallLiveMatchView(snapshot: snapshot)
        case .systemMedium:
            MediumLiveMatchView(snapshot: snapshot)
        case .systemLarge:
            LargeLiveMatchView(snapshot: snapshot)
        case .accessoryRectangular:
            AccessoryRectangularMatchView(snapshot: snapshot)
        case .accessoryInline:
            AccessoryInlineMatchView(snapshot: snapshot)
        default:
            SmallLiveMatchView(snapshot: snapshot)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "sportscourt.fill")
                .font(.title2)
                .foregroundStyle(.blue)
            Text("Tally: It")
                .font(.headline)
            Text("Tap to start a match")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct QuickIncrementRow: View {
    let matchID: UUID
    let entryID: UUID
    let increments: [Int]
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(increments, id: \.self) { delta in
                Button(intent: AdjustTeamScoreIntent(matchID: matchID, entryID: entryID, delta: delta)) {
                    Text(delta > 0 ? "+\(delta)" : "\(delta)")
                        .font(.system(size: compact ? 11 : 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(maxWidth: compact ? .infinity : nil)
                        .padding(.horizontal, compact ? 4 : 9)
                        .padding(.vertical, compact ? 4 : 5)
                        .background(
                            delta >= 0 ? Color.blue.opacity(0.16) : Color.red.opacity(0.15),
                            in: Capsule()
                        )
                        .foregroundStyle(delta >= 0 ? Color.blue : Color.red)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct SmallLiveMatchView: View {
    let snapshot: LiveMatchSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(snapshot.gameTypeName)
                    .font(.caption.bold())
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(snapshot.roundBadge)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        snapshot.isCompleted ? Color.green.opacity(0.16) : Color.blue.opacity(0.15),
                        in: Capsule()
                    )
                    .foregroundStyle(snapshot.isCompleted ? Color.green : Color.blue)
            }

            if let goal = snapshot.goalLabel {
                Text(goal)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            ForEach(snapshot.teams.prefix(2)) { team in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        if team.isWinner {
                            Image(systemName: "crown.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        Text(team.teamName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text("\(team.score)")
                            .font(.system(.headline, design: .rounded).weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(team.isWinner ? Color.green : Color.primary)
                    }

                    if !snapshot.isCompleted {
                        QuickIncrementRow(
                            matchID: snapshot.id,
                            entryID: team.id,
                            increments: snapshot.quickIncrements,
                            compact: true
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct MediumLiveMatchView: View {
    let snapshot: LiveMatchSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(snapshot.gameTypeName)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(snapshot.trackRounds ? "Round \(snapshot.currentRound)" : "Total")
                            .font(.caption.bold())
                            .foregroundStyle(.blue)
                        if let target = snapshot.targetScore, target > 0 {
                            Text("(Goal: \(target))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 4)

                if snapshot.trackRounds && !snapshot.isCompleted {
                    Button(intent: AdvanceRoundIntent(matchID: snapshot.id)) {
                        HStack(spacing: 3) {
                            Text(snapshot.isFinalRound ? "Finish" : "Next Round")
                            Image(systemName: snapshot.isFinalRound ? "checkmark" : "arrow.right")
                        }
                        .font(.caption2.bold())
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(snapshot.isFinalRound ? Color.green : Color.blue, in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                } else if snapshot.isCompleted {
                    Text("Completed")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.16), in: Capsule())
                        .foregroundStyle(.green)
                }
            }

            Divider()

            VStack(spacing: 6) {
                ForEach(snapshot.teams.prefix(3)) { team in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                if team.isWinner {
                                    Image(systemName: "crown.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                                Text(team.teamName)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                            }
                            if snapshot.trackRounds && !snapshot.isCompleted {
                                let sign = team.currentRoundDelta >= 0 ? "+" : ""
                                Text("R\(snapshot.currentRound): \(sign)\(team.currentRoundDelta)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }

                        Spacer(minLength: 4)

                        Text("\(team.score)")
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(team.isWinner ? Color.green : Color.primary)
                            .frame(minWidth: 34, alignment: .trailing)

                        if !snapshot.isCompleted {
                            QuickIncrementRow(
                                matchID: snapshot.id,
                                entryID: team.id,
                                increments: snapshot.quickIncrements,
                                compact: false
                            )
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct LargeLiveMatchView: View {
    let snapshot: LiveMatchSnapshot

    private var recentRoundIndices: [Int] {
        let total = snapshot.completedRoundCount
        guard total > 0 else { return [] }
        return Array(max(0, total - 3)..<total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.gameTypeName)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(snapshot.isCompleted ? "Final Results" : (snapshot.trackRounds ? "Round \(snapshot.currentRound)" : "Total Score"))
                            .font(.caption.bold())
                            .foregroundStyle(snapshot.isCompleted ? Color.green : Color.blue)
                        if let goal = snapshot.goalLabel {
                            Text("• \(goal)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer(minLength: 4)

                if snapshot.trackRounds && !snapshot.isCompleted {
                    Button(intent: AdvanceRoundIntent(matchID: snapshot.id)) {
                        Label(
                            snapshot.isFinalRound ? "Finish Game" : "Next Round",
                            systemImage: snapshot.isFinalRound ? "checkmark.circle.fill" : "arrow.right.circle.fill"
                        )
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(snapshot.isFinalRound ? Color.green : Color.blue, in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let banner = snapshot.winnerBannerText {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(banner)
                        .font(.caption.bold())
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            VStack(spacing: 8) {
                ForEach(snapshot.teams.prefix(4)) { team in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                if team.isWinner {
                                    Image(systemName: "crown.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                                Text(team.teamName)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                            }
                            if snapshot.trackRounds && !snapshot.isCompleted {
                                let sign = team.currentRoundDelta >= 0 ? "+" : ""
                                Text("R\(snapshot.currentRound): \(sign)\(team.currentRoundDelta)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }

                        Spacer(minLength: 4)

                        Text("\(team.score)")
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(team.isWinner ? Color.green : Color.primary)
                            .frame(minWidth: 36, alignment: .trailing)

                        if !snapshot.isCompleted {
                            QuickIncrementRow(
                                matchID: snapshot.id,
                                entryID: team.id,
                                increments: snapshot.quickIncrements,
                                compact: false
                            )
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            if !recentRoundIndices.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recent Rounds")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        ForEach(recentRoundIndices, id: \.self) { idx in
                            let scores = snapshot.teams.prefix(4).map { team in
                                idx < team.roundHistory.count ? "\(team.roundHistory[idx])" : "0"
                            }.joined(separator: " | ")
                            Text("R\(idx + 1): \(scores)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Link(destination: TallyItDeepLink.match(snapshot.id).url) {
                    Label("Open Scoreboard", systemImage: "sportscourt")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                }

                Link(destination: TallyItDeepLink.newMatch.url) {
                    Label("New Match", systemImage: "plus")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.blue)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct AccessoryRectangularMatchView: View {
    let snapshot: LiveMatchSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(snapshot.gameTypeName) • \(snapshot.roundBadge)")
                .font(.caption.bold())
                .lineLimit(1)

            let summary = snapshot.teams.prefix(2)
                .map { "\($0.teamName): \($0.score)" }
                .joined(separator: "  |  ")
            Text(summary)
                .font(.caption2.monospacedDigit())
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AccessoryInlineMatchView: View {
    let snapshot: LiveMatchSnapshot

    var body: some View {
        let scores = snapshot.teams.prefix(2).map { "\($0.score)" }.joined(separator: "–")
        Text("\(snapshot.gameTypeName): \(scores) (\(snapshot.roundBadge))")
    }
}
