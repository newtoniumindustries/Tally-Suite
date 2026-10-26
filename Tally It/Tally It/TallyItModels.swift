import Foundation
import SwiftData

@Model
final class GameType {
    var id: UUID = UUID()
    var name: String = ""
    var incrementsRaw: String = "1, 5, 10, -1"
    var targetScore: Int? = nil
    var lowestScoreWins: Bool = false
    var trackRounds: Bool = true
    var createdAt: Date = Date()

    init(
        name: String,
        incrementsRaw: String = "1, 5, 10, -1",
        targetScore: Int? = nil,
        lowestScoreWins: Bool = false,
        trackRounds: Bool = true
    ) {
        self.id = UUID()
        self.name = name
        self.incrementsRaw = incrementsRaw
        self.targetScore = targetScore
        self.lowestScoreWins = lowestScoreWins
        self.trackRounds = trackRounds
        self.createdAt = Date()
    }

    var increments: [Int] {
        let parsed = incrementsRaw
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return parsed.isEmpty ? [1, 5, -1] : parsed
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

    init(teamID: UUID, teamName: String, score: Int = 0, sortOrder: Int = 0) {
        self.id = UUID()
        self.teamID = teamID
        self.teamName = teamName
        self.score = score
        self.currentRoundDelta = 0
        self.roundHistory = []
        self.sortOrder = sortOrder
    }
}

@Model
final class Match {
    var id: UUID = UUID()
    var gameTypeID: UUID = UUID()
    var gameTypeName: String = ""
    var incrementsRaw: String = "1, 5, 10, -1"
    var targetScore: Int? = nil
    var lowestScoreWins: Bool = false
    var trackRounds: Bool = true
    var currentRound: Int = 1
    var startedAt: Date = Date()
    var completedAt: Date? = nil
    var isCompleted: Bool = false
    var winnerTeamID: UUID? = nil

    @Relationship(deleteRule: .cascade)
    var entries: [MatchScoreEntry] = []

    init(gameType: GameType, entries: [MatchScoreEntry]) {
        self.id = UUID()
        self.gameTypeID = gameType.id
        self.gameTypeName = gameType.name
        self.incrementsRaw = gameType.incrementsRaw
        self.targetScore = gameType.targetScore
        self.lowestScoreWins = gameType.lowestScoreWins
        self.trackRounds = gameType.trackRounds
        self.currentRound = 1
        self.startedAt = Date()
        self.isCompleted = false
        self.entries = entries
    }

    var increments: [Int] {
        let parsed = incrementsRaw
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return parsed.isEmpty ? [1, 5, -1] : parsed
    }

    var sortedEntries: [MatchScoreEntry] {
        entries.sorted { $0.sortOrder < $1.sortOrder }
    }

    func isTargetWinner(_ entry: MatchScoreEntry) -> Bool {
        guard let target = targetScore, !entries.isEmpty else { return false }
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
