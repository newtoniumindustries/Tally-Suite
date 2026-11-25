import Foundation
import SwiftData

enum ScoreIncrementParser {
    static let defaultRaw = "1, 5, 10, -1"
    static let defaultValues = [1, 5, 10, -1]

    static func parse(_ raw: String) -> [Int] {
        var seen = Set<Int>()
        let parsed = raw
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0 != 0 && seen.insert($0).inserted }
        return parsed.isEmpty ? defaultValues : parsed
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
        self.incrementsRaw = incrementsRaw
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
        self.score = score
        self.currentRoundDelta = 0
        self.roundHistory = []
        self.sortOrder = sortOrder
    }

    func recalculateTotalScore() {
        let historySum = roundHistory.reduce(0) { partialResult, value in
            let (sum, overflow) = partialResult.addingReportingOverflow(value)
            return overflow ? (value > 0 ? Int.max : Int.min) : sum
        }
        let (total, overflow) = historySum.addingReportingOverflow(currentRoundDelta)
        self.score = overflow ? (currentRoundDelta > 0 ? Int.max : Int.min) : total
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

    @Relationship(deleteRule: .cascade, inverse: \MatchScoreEntry.match)
    var entries: [MatchScoreEntry] = []

    init(gameType: GameType, entries: [MatchScoreEntry]) {
        self.id = UUID()
        self.gameTypeID = gameType.id
        self.gameTypeName = gameType.name
        self.incrementsRaw = gameType.incrementsRaw
        self.targetScore = gameType.targetScore
        self.maxRounds = gameType.maxRounds
        self.lowestScoreWins = gameType.lowestScoreWins
        self.trackRounds = gameType.trackRounds
        self.useCondensedView = gameType.useCondensedView
        self.currentRound = 1
        self.startedAt = Date()
        self.isCompleted = false
        self.entries = entries
    }

    var increments: [Int] {
        ScoreIncrementParser.parse(incrementsRaw)
    }

    var sortedEntries: [MatchScoreEntry] {
        entries.sorted { $0.sortOrder < $1.sortOrder }
    }

    func isTargetWinner(_ entry: MatchScoreEntry) -> Bool {
        guard !entries.isEmpty else { return false }

        if let max = maxRounds, max > 0, currentRound > max {
            if lowestScoreWins {
                guard let minScore = entries.map(\.score).min() else { return false }
                return entry.score == minScore
            } else {
                guard let maxScore = entries.map(\.score).max() else { return false }
                return entry.score == maxScore
            }
        }

        guard let target = targetScore, target > 0 else { return false }
        let someoneReachedTarget = entries.contains { $0.score >= target }
        guard someoneReachedTarget else { return false }

        if lowestScoreWins {
            guard let minScore = entries.map(\.score).min() else { return false }
            return entry.score == minScore
        } else {
            guard let maxScore = entries.map(\.score).max() else { return false }
            return entry.score >= target && entry.score == maxScore
        }
    }

    var winningEntries: [MatchScoreEntry] {
        sortedEntries.filter { isTargetWinner($0) }
    }
}
