import Foundation
import SwiftData
import TallyCore

enum ScoreIncrementParser {
    nonisolated static let defaultRaw = "1, 5, 10, -1"
    nonisolated static let defaultValues = [1, 5, 10, -1]

    /// Parses comma-separated non-zero integers, clamping each to `TallyMath.maxMagnitude` and deduplicating.
    /// Returns an empty array if no valid increments are found.
    nonisolated static func parseStrict(_ raw: String) -> [Int] {
        var seen = Set<Int>()
        return raw
            .split(separator: ",")
            .compactMap { TallyMath.parseInt(String($0)) }
            .filter { $0 != 0 && seen.insert($0).inserted }
    }

    /// Parses comma-separated increments, falling back to `defaultValues` if none are valid.
    nonisolated static func parse(_ raw: String) -> [Int] {
        let parsed = parseStrict(raw)
        return parsed.isEmpty ? defaultValues : parsed
    }

    /// Normalizes a raw increment string into canonical comma-separated form.
    nonisolated static func canonicalString(from raw: String) -> String {
        parse(raw).map(String.init).joined(separator: ", ")
    }
}

@Model
final class GameType {
    var id: UUID = UUID()
    var name: String = ""
    var incrementsRaw: String = ScoreIncrementParser.defaultRaw
    var targetScore: Int? = nil
    var maxRounds: Int? = nil
    var lowestScoreWins: Bool = false
    var trackRounds: Bool = true
    var useCondensedView: Bool = true
    var createdAt: Date = Date()

    init(
        name: String,
        incrementsRaw: String = ScoreIncrementParser.defaultRaw,
        targetScore: Int? = nil,
        maxRounds: Int? = nil,
        lowestScoreWins: Bool = false,
        trackRounds: Bool = true,
        useCondensedView: Bool = true
    ) {
        self.id = UUID()
        self.name = name
        self.incrementsRaw = ScoreIncrementParser.canonicalString(from: incrementsRaw)
        self.targetScore = targetScore
        self.maxRounds = maxRounds
        self.lowestScoreWins = lowestScoreWins
        self.trackRounds = trackRounds
        self.useCondensedView = useCondensedView
        self.createdAt = Date()
    }

    var increments: [Int] {
        ScoreIncrementParser.parse(incrementsRaw)
    }
}

@Model
final class Team {
    var id: UUID = UUID()
    var name: String = ""
    var rosterNotes: String = ""
    var createdAt: Date = Date()

    init(name: String, rosterNotes: String = "") {
        self.id = UUID()
        self.name = name
        self.rosterNotes = rosterNotes
        self.createdAt = Date()
    }
}

@Model
final class MatchScoreEntry {
    var id: UUID = UUID()
    var teamID: UUID = UUID()
    var teamName: String = ""
    var score: Int = 0
    var currentRoundDelta: Int = 0
    var roundHistory: [Int] = []
    var sortOrder: Int = 0
    var match: Match? = nil

    init(teamID: UUID, teamName: String, score: Int = 0, sortOrder: Int = 0) {
        self.id = UUID()
        self.teamID = teamID
        self.teamName = teamName
        self.score = TallyMath.clamp(score)
        self.currentRoundDelta = 0
        self.roundHistory = []
        self.sortOrder = sortOrder
    }

    /// Recomputes `score` from `roundHistory` + `currentRoundDelta` using consistent `TallyMath` clamping.
    func recalculateTotalScore() {
        let historySum = TallyMath.sum(roundHistory)
        self.score = TallyMath.add(historySum, currentRoundDelta)
    }

    /// Applies a score increment while keeping `score` and `currentRoundDelta` synchronized even at clamp boundaries.
    func applyDelta(_ delta: Int, trackRounds: Bool) {
        let previousScore = score
        let nextScore = TallyMath.add(previousScore, delta)
        score = nextScore
        if trackRounds {
            let appliedDelta = TallyMath.subtract(nextScore, previousScore)
            currentRoundDelta = TallyMath.add(currentRoundDelta, appliedDelta)
        }
    }

    /// Sets the total score directly while keeping `currentRoundDelta` synchronized when tracking rounds.
    func setScore(_ newScore: Int, trackRounds: Bool) {
        let clamped = TallyMath.clamp(newScore)
        let diff = TallyMath.subtract(clamped, score)
        score = clamped
        if trackRounds {
            currentRoundDelta = TallyMath.add(currentRoundDelta, diff)
        }
    }
}

@Model
final class Match {
    var id: UUID = UUID()
    var gameTypeID: UUID = UUID()
    var gameTypeName: String = ""
    var incrementsRaw: String = ScoreIncrementParser.defaultRaw
    var targetScore: Int? = nil
    var maxRounds: Int? = nil
    var lowestScoreWins: Bool = false
    var trackRounds: Bool = true
    var useCondensedView: Bool = true
    var currentRound: Int = 1
    var startedAt: Date = Date()
    var completedAt: Date? = nil
    var isCompleted: Bool = false
    var winnerTeamID: UUID? = nil
    var didCommitFinalRoundOnCompletion: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \MatchScoreEntry.match)
    var entries: [MatchScoreEntry] = []

    init(gameType: GameType, entries: [MatchScoreEntry]) {
        self.id = UUID()
        self.gameTypeID = gameType.id
        self.gameTypeName = gameType.name
        self.incrementsRaw = ScoreIncrementParser.canonicalString(from: gameType.incrementsRaw)
        self.targetScore = gameType.targetScore
        self.maxRounds = gameType.maxRounds
        self.lowestScoreWins = gameType.lowestScoreWins
        self.trackRounds = gameType.trackRounds
        self.useCondensedView = gameType.useCondensedView
        self.currentRound = 1
        self.startedAt = Date()
        self.isCompleted = false
        self.didCommitFinalRoundOnCompletion = false
        self.entries = entries
    }

    var increments: [Int] {
        ScoreIncrementParser.parse(incrementsRaw)
    }

    var sortedEntries: [MatchScoreEntry] {
        entries.sorted { $0.sortOrder < $1.sortOrder }
    }

    var activeMaxRounds: Int? {
        guard let maxR = maxRounds, maxR > 0 else { return nil }
        return maxR
    }

    var completedRoundCount: Int {
        entries.map(\.roundHistory.count).max() ?? 0
    }

    var roundHistoryEmpty: Bool {
        entries.allSatisfy { $0.roundHistory.isEmpty }
    }

    var bestScore: Int? {
        lowestScoreWins ? entries.map(\.score).min() : entries.map(\.score).max()
    }

    /// Evaluates whether `entry` meets the live winning condition (max rounds exceeded or target reached).
    func isTargetWinner(_ entry: MatchScoreEntry) -> Bool {
        guard !entries.isEmpty else { return false }

        if let maxR = activeMaxRounds, currentRound > maxR {
            guard let best = bestScore else { return false }
            return entry.score == best
        }

        guard let target = targetScore, target > 0 else { return false }
        let someoneReachedTarget = entries.contains { $0.score >= target }
        guard someoneReachedTarget else { return false }

        guard let best = bestScore else { return false }
        if lowestScoreWins {
            return entry.score == best
        } else {
            return entry.score >= target && entry.score == best
        }
    }

    /// Evaluates whether `entry` should be highlighted as the winner (handles both completed and active matches).
    func isHighlightedWinner(_ entry: MatchScoreEntry) -> Bool {
        if isCompleted {
            if let winnerTeamID {
                return entry.teamID == winnerTeamID
            }
            guard let best = bestScore else { return false }
            return entry.score == best
        }
        return isTargetWinner(entry)
    }

    var winningEntries: [MatchScoreEntry] {
        sortedEntries.filter { isTargetWinner($0) }
    }

    var highlightedWinners: [MatchScoreEntry] {
        sortedEntries.filter { isHighlightedWinner($0) }
    }

    /// Human-readable winner/tie banner text for both live and completed matches.
    var winnerBannerText: String? {
        let winners = highlightedWinners
        guard !winners.isEmpty else { return nil }

        let names = winners.map(\.teamName).joined(separator: " & ")
        if isCompleted {
            if winnerTeamID != nil, winners.count == 1 {
                return "\(names) wins!"
            }
            return "Match ended in a tie: \(names)"
        } else {
            if winners.count == 1 {
                return "\(names) leads / wins!"
            }
            return "\(names) are tied for the lead!"
        }
    }

    /// Advances to the next round, committing current round deltas to history.
    /// Automatically completes the match when `maxRounds` is reached.
    /// Returns `true` if advancing the round completed the match.
    @discardableResult
    func advanceRound(at date: Date = Date()) -> Bool {
        for entry in entries {
            entry.roundHistory.append(entry.currentRoundDelta)
            entry.currentRoundDelta = 0
            entry.recalculateTotalScore()
        }

        if let maxR = activeMaxRounds, currentRound >= maxR {
            currentRound += 1
            completeMatch(at: date, finalRoundAlreadyCommitted: true)
            return true
        } else {
            currentRound += 1
            return false
        }
    }

    /// Finalizes the match, committing any pending round deltas and recording the winner.
    func completeMatch(at date: Date = Date(), finalRoundAlreadyCommitted: Bool = false) {
        if finalRoundAlreadyCommitted {
            didCommitFinalRoundOnCompletion = true
        } else if trackRounds && entries.contains(where: { $0.currentRoundDelta != 0 }) {
            for entry in entries {
                entry.roundHistory.append(entry.currentRoundDelta)
                entry.currentRoundDelta = 0
                entry.recalculateTotalScore()
            }
            didCommitFinalRoundOnCompletion = true
        } else {
            didCommitFinalRoundOnCompletion = false
        }

        let sorted = entries.sorted { a, b in
            lowestScoreWins ? (a.score < b.score) : (a.score > b.score)
        }
        if sorted.count >= 2, sorted[0].score != sorted[1].score {
            winnerTeamID = sorted[0].teamID
        } else {
            winnerTeamID = nil
        }
        isCompleted = true
        completedAt = date
    }

    /// Un-submits a completed match and restores the final active round without merging multiple rounds.
    func reopenMatch() {
        let recordedRounds = completedRoundCount
        if let maxR = activeMaxRounds, currentRound > maxR {
            currentRound = max(maxR, recordedRounds)
        }

        if trackRounds {
            let shouldRestoreLastRound = didCommitFinalRoundOnCompletion
                || (recordedRounds > 0 && entries.allSatisfy { $0.roundHistory.count >= currentRound })

            if shouldRestoreLastRound {
                for entry in entries where !entry.roundHistory.isEmpty {
                    let restoredDelta = entry.roundHistory.removeLast()
                    entry.currentRoundDelta = TallyMath.add(entry.currentRoundDelta, restoredDelta)
                    entry.recalculateTotalScore()
                }
            } else {
                for entry in entries {
                    entry.recalculateTotalScore()
                }
            }
        }

        didCommitFinalRoundOnCompletion = false
        isCompleted = false
        completedAt = nil
        winnerTeamID = nil
    }

    /// Resets a match back to Round 1 with 0 points for all teams.
    func restartMatchFromZero() {
        currentRound = 1
        for entry in entries {
            entry.score = 0
            entry.currentRoundDelta = 0
            entry.roundHistory = []
        }
        didCommitFinalRoundOnCompletion = false
        isCompleted = false
        completedAt = nil
        winnerTeamID = nil
    }
}

// MARK: - Standings Calculation

struct TeamStandingRow: Identifiable, Equatable {
    let id: UUID
    let teamName: String
    var wins: Int = 0
    var losses: Int = 0
    var ties: Int = 0
    var totalPoints: Int = 0

    var gamesPlayed: Int { wins + losses + ties }
    var winPercentage: Double {
        gamesPlayed > 0 ? Double(wins) / Double(gamesPlayed) : 0.0
    }
}

enum StandingsCalculator {
    static func compute(
        from completedMatches: [Match],
        preferLowerPointsOnTie: Bool
    ) -> [TeamStandingRow] {
        var map: [UUID: TeamStandingRow] = [:]

        for match in completedMatches where match.isCompleted {
            let bestScore = match.bestScore

            for entry in match.entries {
                var row = map[entry.teamID] ?? TeamStandingRow(id: entry.teamID, teamName: entry.teamName)
                row.totalPoints = TallyMath.add(row.totalPoints, entry.score)

                if let winnerID = match.winnerTeamID {
                    if winnerID == entry.teamID {
                        row.wins += 1
                    } else {
                        row.losses += 1
                    }
                } else if let bestScore, entry.score == bestScore {
                    row.ties += 1
                } else {
                    row.losses += 1
                }
                map[entry.teamID] = row
            }
        }

        return map.values.sorted { lhs, rhs in
            if lhs.wins != rhs.wins { return lhs.wins > rhs.wins }
            if lhs.winPercentage != rhs.winPercentage { return lhs.winPercentage > rhs.winPercentage }
            if lhs.totalPoints != rhs.totalPoints {
                return preferLowerPointsOnTie
                    ? (lhs.totalPoints < rhs.totalPoints)
                    : (lhs.totalPoints > rhs.totalPoints)
            }
            let nameOrder = lhs.teamName.localizedCaseInsensitiveCompare(rhs.teamName)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
