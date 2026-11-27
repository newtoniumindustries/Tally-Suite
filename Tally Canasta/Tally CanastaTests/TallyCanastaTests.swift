import Foundation
import SwiftData
import TallyCore
import Testing
@testable import Tally_Canasta

@Suite("CanastaScorer & Rules Tests")
struct CanastaScorerTests {
    @Test("Scores melds, canastas, going out, and in-hand penalties accurately")
    func standardRoundScoring() {
        let rules = RuleSet.makeClassicPreset().scoringRules
        let input = CanastaTeamRoundInput(
            red3s: 2,
            mixedCanastas: 1,
            pureCanastas: 1,
            wentOut: true,
            wentOutConcealed: false,
            jokers: 2,      // 100
            deuces: 3,      // 60
            aces: 4,        // 80
            highCards: 5,   // 50
            lowCards: 4,    // 20
            black3s: 2,     // 10
            jokersInHand: 1, // -50
            deucesInHand: 1  // -20
        )
        // Base: 200 (red3) + 300 (mixed) + 500 (pure) + 100 (out) = 1100
        // Cards: 100 + 60 + 80 + 50 + 20 + 10 = 320
        // Penalty: 50 + 20 = 70
        // Total: 1100 + 320 - 70 = 1350
        #expect(CanastaScorer.roundTotal(for: input, rules: rules) == 1350)
    }

    @Test("Red 3s double at 4+ for both positive and negative penalty counts")
    func red3DoublingPositiveAndNegative() {
        let rules = RuleSet.makeClassicPreset().scoringRules

        #expect(CanastaScorer.roundTotal(for: CanastaTeamRoundInput(red3s: 3), rules: rules) == 300)
        #expect(CanastaScorer.roundTotal(for: CanastaTeamRoundInput(red3s: 4), rules: rules) == 800)
        #expect(CanastaScorer.roundTotal(for: CanastaTeamRoundInput(red3s: -3), rules: rules) == -300)
        #expect(CanastaScorer.roundTotal(for: CanastaTeamRoundInput(red3s: -4), rules: rules) == -800)
    }

    @Test("Concealed going out replaces standard going out bonus rather than stacking")
    func concealedReplacesStandardOut() {
        let rules = RuleSet.makeClassicPreset().scoringRules
        let input = CanastaTeamRoundInput(wentOut: true, wentOutConcealed: true)
        #expect(CanastaScorer.roundTotal(for: input, rules: rules) == 200)
    }

    @Test("Supports custom rule bonuses above 999 points without truncation")
    func highValueCustomRules() {
        var rules = RuleSet.makeClassicPreset().scoringRules
        rules.purePts = 1500
        rules.outConcealedPts = 2000
        let input = CanastaTeamRoundInput(pureCanastas: 2, wentOutConcealed: true)
        #expect(CanastaScorer.roundTotal(for: input, rules: rules) == 5000)
    }

    @Test("Opening meld requirements match Classic and Modern American presets")
    func openingMeldThresholds() {
        let classic = RuleSet.makeClassicPreset().scoringRules
        #expect(classic.openingMeldRequirement(for: -100) == 15)
        #expect(classic.openingMeldRequirement(for: 0) == 50)
        #expect(classic.openingMeldRequirement(for: 1499) == 50)
        #expect(classic.openingMeldRequirement(for: 1500) == 90)
        #expect(classic.openingMeldRequirement(for: 3000) == 120)

        let modern = RuleSet.makeModernAmericanPreset().scoringRules
        #expect(modern.openingMeldRequirement(for: -50) == 125)
        #expect(modern.openingMeldRequirement(for: 0) == 125)
        #expect(modern.openingMeldRequirement(for: 2999) == 125)
        #expect(modern.openingMeldRequirement(for: 3000) == 155)
        #expect(modern.openingMeldRequirement(for: 5000) == 180)
    }
}

@Suite("Canasta Game & Draft Lifecycle Tests")
@MainActor
struct CanastaGameTests {
    @Test("DraftRoundData enforces cross-team mutual exclusion for going out")
    func crossTeamGoingOutMutualExclusion() {
        var draft = DraftRoundData()
        draft.setWentOut(true, concealed: false, for: .team1)
        #expect(draft.team1.wentOut)
        #expect(!draft.team2.wentOut)

        draft.setWentOut(true, concealed: true, for: .team2)
        #expect(!draft.team1.wentOut)
        #expect(!draft.team1.wentOutConcealed)
        #expect(!draft.team2.wentOut)
        #expect(draft.team2.wentOutConcealed)
    }

    @Test("Winner and tie detection work for 2-team and 3-team games")
    func winnerAndTieDetection() throws {
        let schema = Schema([CanastaGame.self, Round.self, RuleSet.self, TallyPlayer.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let rules = RuleSet.makeClassicPreset()
        rules.targetScore = 1000
        context.insert(rules)

        let game = CanastaGame(team1Name: "North", team2Name: "South", team3Name: "East", rules: rules)
        context.insert(game)

        // Round 1: North = 1000 (2 pure), South = 1000 (2 pure), East = 500 (1 pure) -> Tied at target
        let r1 = Round(roundNumber: 1)
        r1.apply(CanastaTeamRoundInput(pureCanastas: 2), for: .team1)
        r1.apply(CanastaTeamRoundInput(pureCanastas: 2), for: .team2)
        r1.apply(CanastaTeamRoundInput(pureCanastas: 1), for: .team3)
        context.insert(r1)
        game.rounds.append(r1)
        #expect(context.saveReportingError() == nil)

        #expect(game.winner == nil)
        #expect(game.isTiedAtOrAboveTarget)

        // Round 2: East scores 1000 -> East = 1500 wins
        let r2 = Round(roundNumber: 2)
        r2.apply(CanastaTeamRoundInput(pureCanastas: 2), for: .team3)
        context.insert(r2)
        game.rounds.append(r2)
        #expect(context.saveReportingError() == nil)

        #expect(game.winner == "East")
        #expect(!game.isTiedAtOrAboveTarget)

        // Delete Round 1 and verify renumbering
        game.rounds.removeAll(where: { $0.persistentModelID == r1.persistentModelID })
        context.delete(r1)
        game.renumberRounds()
        #expect(context.saveReportingError() == nil)
        #expect(game.sortedRounds.map(\.roundNumber) == [1])

        // Cascade delete removes remaining rounds
        context.delete(game)
        #expect(context.saveReportingError() == nil)
        #expect(try context.fetch(FetchDescriptor<Round>()).isEmpty)
    }

    @Test("TallyCanastaDeepLink builds and parses game, new-round, new-game, and how-to-play URLs cleanly")
    func deepLinkRoundTrip() {
        let gameID = UUID()

        #expect(TallyCanastaDeepLink.parse(TallyCanastaDeepLink.game(gameID).url) == .game(gameID))
        #expect(TallyCanastaDeepLink.parse(TallyCanastaDeepLink.newRound(gameID: gameID).url) == .newRound(gameID: gameID))
        #expect(TallyCanastaDeepLink.parse(TallyCanastaDeepLink.newGame.url) == .newGame)
        #expect(TallyCanastaDeepLink.parse(TallyCanastaDeepLink.howToPlay.url) == .howToPlay)
        #expect(TallyCanastaDeepLink.parse(URL(string: "https://example.com")!) == nil)
        #expect(TallyCanastaDeepLink.parse(URL(string: "tallycanasta://game/invalid-id")!) == nil)
    }
}
