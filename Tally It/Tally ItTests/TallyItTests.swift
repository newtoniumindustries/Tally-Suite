import Foundation
import SwiftData
import TallyCore
import Testing
@testable import Tally_It

@Suite("ScoreIncrementParser Tests")
struct ScoreIncrementParserTests {
    @Test("Parses, deduplicates, filters zeros, and falls back on invalid input")
    func parsingAndCanonicalization() {
        #expect(ScoreIncrementParser.parse("1, 5, 10, -1, 5, 0") == [1, 5, 10, -1])
        #expect(ScoreIncrementParser.parseStrict("abc, 0, ,").isEmpty)
        #expect(ScoreIncrementParser.parse("abc, 0") == ScoreIncrementParser.defaultValues)
        #expect(ScoreIncrementParser.canonicalString(from: " 3 , 1 , 3 , -1 ") == "3, 1, -1")
        #expect(ScoreIncrementParser.canonicalString(from: "invalid") == ScoreIncrementParser.defaultRaw)
    }
}

@Suite("Tally It Scoring & Match Lifecycle Tests")
@MainActor
struct TallyItMatchTests {
    private func makeEntries(scores: [Int] = [0, 0]) -> [MatchScoreEntry] {
        scores.enumerated().map { idx, score in
            MatchScoreEntry(
                teamID: UUID(),
                teamName: "Team \(idx + 1)",
                score: score,
                sortOrder: idx
            )
        }
    }

    @Test("MatchScoreEntry clamps consistently and preserves round delta invariant")
    func scoreClampingInvariant() {
        let entry = MatchScoreEntry(teamID: UUID(), teamName: "Alpha", score: TallyMath.maxMagnitude - 5)
        entry.applyDelta(20, trackRounds: true)
        #expect(entry.score == TallyMath.maxMagnitude)
        // Applied delta should only reflect +5 (the actual change before saturation)
        #expect(entry.currentRoundDelta == 5)

        entry.roundHistory = [TallyMath.maxMagnitude, TallyMath.maxMagnitude]
        entry.currentRoundDelta = 100
        entry.recalculateTotalScore()
        #expect(entry.score == TallyMath.maxMagnitude)
    }

    @Test("setScore synchronizes currentRoundDelta when tracking rounds")
    func setScoreSync() {
        let entry = MatchScoreEntry(teamID: UUID(), teamName: "Alpha", score: 10)
        entry.roundHistory = [10]
        entry.setScore(25, trackRounds: true)
        #expect(entry.score == 25)
        #expect(entry.currentRoundDelta == 15)
        entry.recalculateTotalScore()
        #expect(entry.score == 25)
    }

    @Test("Completed match without target score still highlights winner and displays banner")
    func completedMatchWinnerDisplay() {
        let gameType = GameType(name: "Freeform", targetScore: nil, maxRounds: nil, lowestScoreWins: false)
        let entries = makeEntries(scores: [40, 25])
        let match = Match(gameType: gameType, entries: entries)

        #expect(match.winningEntries.isEmpty)
        #expect(match.winnerBannerText == nil)

        match.completeMatch()
        #expect(match.isCompleted)
        #expect(match.winnerTeamID == entries[0].teamID)
        #expect(match.isHighlightedWinner(entries[0]))
        #expect(!match.isHighlightedWinner(entries[1]))
        #expect(match.winnerBannerText == "Team 1 wins!")
    }

    @Test("Completed tie highlights tied teams and reports tie banner")
    func completedTieBanner() {
        let gameType = GameType(name: "Tied Game")
        let entries = makeEntries(scores: [30, 30, 10])
        let match = Match(gameType: gameType, entries: entries)
        match.completeMatch()

        #expect(match.winnerTeamID == nil)
        #expect(match.highlightedWinners.count == 2)
        #expect(match.winnerBannerText == "Match ended in a tie: Team 1 & Team 2")
    }

    @Test("Lowest score wins highlights minimum score once any team hits target limit")
    func lowestScoreWinsLimit() {
        let gameType = GameType(name: "Hearts", targetScore: 100, lowestScoreWins: true)
        let entries = makeEntries(scores: [45, 102])
        let match = Match(gameType: gameType, entries: entries)

        #expect(match.isTargetWinner(entries[0]))
        #expect(!match.isTargetWinner(entries[1]))
    }

    @Test("Advance round, complete on maxRounds, and reopen restore exact round history without merging")
    func roundLifecycleAndReopen() {
        let gameType = GameType(name: "3-Round", maxRounds: 3, trackRounds: true)
        let entries = makeEntries()
        let match = Match(gameType: gameType, entries: entries)

        // Round 1
        entries[0].applyDelta(10, trackRounds: true)
        entries[1].applyDelta(5, trackRounds: true)
        #expect(!match.advanceRound())
        #expect(match.currentRound == 2)
        #expect(entries[0].roundHistory == [10])

        // Round 2
        entries[0].applyDelta(7, trackRounds: true)
        entries[1].applyDelta(12, trackRounds: true)
        #expect(!match.advanceRound())
        #expect(match.currentRound == 3)
        #expect(entries[0].roundHistory == [10, 7])

        // Round 3 (final)
        entries[0].applyDelta(8, trackRounds: true)
        entries[1].applyDelta(2, trackRounds: true)
        #expect(match.advanceRound())
        #expect(match.isCompleted)
        #expect(entries[0].roundHistory == [10, 7, 8])
        #expect(entries[0].score == 25)

        // Reopen restores only Round 3 delta, leaving Rounds 1 & 2 intact
        match.reopenMatch()
        #expect(!match.isCompleted)
        #expect(match.currentRound == 3)
        #expect(entries[0].roundHistory == [10, 7])
        #expect(entries[0].currentRoundDelta == 8)
        #expect(entries[0].score == 25)

        // Reset clears everything
        match.restartMatchFromZero()
        #expect(match.currentRound == 1)
        #expect(entries[0].score == 0)
        #expect(entries[0].roundHistory.isEmpty)
    }

    @Test("Standings respects lowestScoreWins tiebreaker and deterministic alphabetical ordering")
    func standingsCalculation() {
        let lowWinsGame = GameType(name: "Golf", lowestScoreWins: true)
        let teamA = UUID()
        let teamB = UUID()
        let teamC = UUID()

        // Match 1: A=10 (win), B=20 (loss)
        let m1 = Match(
            gameType: lowWinsGame,
            entries: [
                MatchScoreEntry(teamID: teamA, teamName: "Alpha", score: 10, sortOrder: 0),
                MatchScoreEntry(teamID: teamB, teamName: "Bravo", score: 20, sortOrder: 1)
            ]
        )
        m1.completeMatch()

        // Match 2: B=5 (win), A=25 (loss) -> Both have 1W-1L, B has 25 total pts vs A's 35 total pts
        let m2 = Match(
            gameType: lowWinsGame,
            entries: [
                MatchScoreEntry(teamID: teamA, teamName: "Alpha", score: 25, sortOrder: 0),
                MatchScoreEntry(teamID: teamB, teamName: "Bravo", score: 5, sortOrder: 1)
            ]
        )
        m2.completeMatch()

        let lowStandings = StandingsCalculator.compute(from: [m1, m2], preferLowerPointsOnTie: true)
        #expect(lowStandings.map(\.teamName) == ["Bravo", "Alpha"])

        let highStandings = StandingsCalculator.compute(from: [m1, m2], preferLowerPointsOnTie: false)
        #expect(highStandings.map(\.teamName) == ["Alpha", "Bravo"])

        // 3-team tie for 1st: A=10, B=10, C=50 -> A & B tie, C loses; alphabetical order A before B
        let m3 = Match(
            gameType: lowWinsGame,
            entries: [
                MatchScoreEntry(teamID: teamB, teamName: "Bravo", score: 10, sortOrder: 0),
                MatchScoreEntry(teamID: teamA, teamName: "Alpha", score: 10, sortOrder: 1),
                MatchScoreEntry(teamID: teamC, teamName: "Charlie", score: 50, sortOrder: 2)
            ]
        )
        m3.completeMatch()

        let tieStandings = StandingsCalculator.compute(from: [m3], preferLowerPointsOnTie: true)
        #expect(tieStandings.map(\.teamName) == ["Alpha", "Bravo", "Charlie"])
        #expect(tieStandings[0].ties == 1 && tieStandings[0].losses == 0)
        #expect(tieStandings[2].ties == 0 && tieStandings[2].losses == 1)
    }

    @Test("SwiftData cascade deletes MatchScoreEntry children when Match is deleted")
    func swiftDataCascadeDelete() throws {
        let schema = Schema([GameType.self, Team.self, Match.self, MatchScoreEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let gameType = GameType(name: "Cornhole", targetScore: 21)
        context.insert(gameType)
        let match = Match(gameType: gameType, entries: makeEntries(scores: [12, 9]))
        context.insert(match)
        #expect(context.saveReportingError() == nil)

        #expect(try context.fetch(FetchDescriptor<MatchScoreEntry>()).count == 2)

        context.delete(match)
        #expect(context.saveReportingError() == nil)
        #expect(try context.fetch(FetchDescriptor<MatchScoreEntry>()).isEmpty)
    }
}
