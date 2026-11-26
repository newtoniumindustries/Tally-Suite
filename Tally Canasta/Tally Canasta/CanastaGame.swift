import Foundation
import SwiftData
import TallyCore

// MARK: - Pure Canasta Scoring Domain Types

enum CanastaTeamSlot: Int, CaseIterable, Sendable {
    case team1 = 0
    case team2 = 1
    case team3 = 2
}

struct CanastaScoringRules: Sendable, Equatable {
    var targetScore: Int = 5000
    var red3Pts: Int = 100
    var mixedPts: Int = 300
    var purePts: Int = 500
    var outPts: Int = 100
    var outConcealedPts: Int = 200

    var jokerPts: Int = 50
    var deucePts: Int = 20
    var acePts: Int = 20
    var highCardPts: Int = 10
    var lowCardPts: Int = 5
    var black3Pts: Int = 5

    // Configurable opening meld thresholds (defaults match Classic Canasta)
    var meldBelowZero: Int = 15
    var meldTier1Threshold: Int = 1500
    var meldTier1Requirement: Int = 50
    var meldTier2Threshold: Int = 3000
    var meldTier2Requirement: Int = 90
    var meldTier3Requirement: Int = 120

    nonisolated func openingMeldRequirement(for score: Int) -> Int {
        if score < 0 { return meldBelowZero }
        if score < meldTier1Threshold { return meldTier1Requirement }
        if score < meldTier2Threshold { return meldTier2Requirement }
        return meldTier3Requirement
    }
}

struct CanastaTeamRoundInput: Sendable, Equatable {
    var red3s: Int = 0
    var mixedCanastas: Int = 0
    var pureCanastas: Int = 0
    var wentOut: Bool = false
    var wentOutConcealed: Bool = false

    var jokers: Int = 0
    var deuces: Int = 0
    var aces: Int = 0
    var highCards: Int = 0
    var lowCards: Int = 0
    var black3s: Int = 0

    var jokersInHand: Int = 0
    var deucesInHand: Int = 0
    var acesInHand: Int = 0
    var highCardsInHand: Int = 0
    var lowCardsInHand: Int = 0
    var black3sInHand: Int = 0
}

enum CanastaScorer: Sendable {
    nonisolated static let minRed3Count = -12
    nonisolated static let maxRed3Count = 12

    nonisolated static func roundTotal(
        for input: CanastaTeamRoundInput,
        rules: CanastaScoringRules
    ) -> Int {
        // 4 (or more) Red 3s score double (e.g. 4 * 100 * 2 = 800; -4 * 100 * 2 = -800 if penalized)
        let red3Base = TallyMath.multiply(input.red3s, rules.red3Pts)
        let red3Score = abs(input.red3s) >= 4 ? TallyMath.multiply(red3Base, 2) : red3Base

        // Concealed going out replaces the standard going-out bonus rather than stacking
        let goingOutBonus = input.wentOutConcealed
            ? rules.outConcealedPts
            : (input.wentOut ? rules.outPts : 0)

        let base = TallyMath.sum([
            red3Score,
            TallyMath.multiply(input.mixedCanastas, rules.mixedPts),
            TallyMath.multiply(input.pureCanastas, rules.purePts),
            goingOutBonus
        ])

        let cards = TallyMath.sum([
            TallyMath.multiply(input.jokers, rules.jokerPts),
            TallyMath.multiply(input.deuces, rules.deucePts),
            TallyMath.multiply(input.aces, rules.acePts),
            TallyMath.multiply(input.highCards, rules.highCardPts),
            TallyMath.multiply(input.lowCards, rules.lowCardPts),
            TallyMath.multiply(input.black3s, rules.black3Pts)
        ])

        let penalty = TallyMath.sum([
            TallyMath.multiply(input.jokersInHand, rules.jokerPts),
            TallyMath.multiply(input.deucesInHand, rules.deucePts),
            TallyMath.multiply(input.acesInHand, rules.acePts),
            TallyMath.multiply(input.highCardsInHand, rules.highCardPts),
            TallyMath.multiply(input.lowCardsInHand, rules.lowCardPts),
            TallyMath.multiply(input.black3sInHand, rules.black3Pts)
        ])

        let gross = TallyMath.add(base, cards)
        return TallyMath.subtract(gross, penalty)
    }
}

// MARK: - Reusable Scoring Templates

@Model
final class RuleSet {
    var name: String = ""
    var targetScore: Int = 5000
    var red3Pts: Int = 100
    var mixedPts: Int = 300
    var purePts: Int = 500
    var outPts: Int = 100
    var outConcealedPts: Int = 200

    var jokerPts: Int = 50
    var deucePts: Int = 20
    var acePts: Int = 20
    var highCardPts: Int = 10
    var lowCardPts: Int = 5
    var black3Pts: Int = 5

    // Opening meld thresholds (Classic defaults for lightweight migration)
    var meldBelowZero: Int = 15
    var meldTier1Threshold: Int = 1500
    var meldTier1Requirement: Int = 50
    var meldTier2Threshold: Int = 3000
    var meldTier2Requirement: Int = 90
    var meldTier3Requirement: Int = 120

    var isBuiltIn: Bool = false

    init(
        name: String,
        targetScore: Int,
        red3Pts: Int = 100,
        mixedPts: Int = 300,
        purePts: Int = 500,
        outPts: Int = 100,
        outConcealedPts: Int = 200,
        jokerPts: Int = 50,
        deucePts: Int = 20,
        acePts: Int = 20,
        highCardPts: Int = 10,
        lowCardPts: Int = 5,
        black3Pts: Int = 5,
        meldBelowZero: Int = 15,
        meldTier1Threshold: Int = 1500,
        meldTier1Requirement: Int = 50,
        meldTier2Threshold: Int = 3000,
        meldTier2Requirement: Int = 90,
        meldTier3Requirement: Int = 120,
        isBuiltIn: Bool = false
    ) {
        self.name = name
        self.targetScore = targetScore
        self.red3Pts = red3Pts
        self.mixedPts = mixedPts
        self.purePts = purePts
        self.outPts = outPts
        self.outConcealedPts = outConcealedPts
        self.jokerPts = jokerPts
        self.deucePts = deucePts
        self.acePts = acePts
        self.highCardPts = highCardPts
        self.lowCardPts = lowCardPts
        self.black3Pts = black3Pts
        self.meldBelowZero = meldBelowZero
        self.meldTier1Threshold = meldTier1Threshold
        self.meldTier1Requirement = meldTier1Requirement
        self.meldTier2Threshold = meldTier2Threshold
        self.meldTier2Requirement = meldTier2Requirement
        self.meldTier3Requirement = meldTier3Requirement
        self.isBuiltIn = isBuiltIn
    }

    var scoringRules: CanastaScoringRules {
        CanastaScoringRules(
            targetScore: targetScore,
            red3Pts: red3Pts,
            mixedPts: mixedPts,
            purePts: purePts,
            outPts: outPts,
            outConcealedPts: outConcealedPts,
            jokerPts: jokerPts,
            deucePts: deucePts,
            acePts: acePts,
            highCardPts: highCardPts,
            lowCardPts: lowCardPts,
            black3Pts: black3Pts,
            meldBelowZero: meldBelowZero,
            meldTier1Threshold: meldTier1Threshold,
            meldTier1Requirement: meldTier1Requirement,
            meldTier2Threshold: meldTier2Threshold,
            meldTier2Requirement: meldTier2Requirement,
            meldTier3Requirement: meldTier3Requirement
        )
    }

    static func makeClassicPreset() -> RuleSet {
        RuleSet(
            name: "Classic",
            targetScore: 5000,
            red3Pts: 100,
            mixedPts: 300,
            purePts: 500,
            outPts: 100,
            outConcealedPts: 200,
            jokerPts: 50,
            deucePts: 20,
            acePts: 20,
            highCardPts: 10,
            lowCardPts: 5,
            black3Pts: 5,
            meldBelowZero: 15,
            meldTier1Threshold: 1500,
            meldTier1Requirement: 50,
            meldTier2Threshold: 3000,
            meldTier2Requirement: 90,
            meldTier3Requirement: 120,
            isBuiltIn: true
        )
    }

    static func makeModernAmericanPreset() -> RuleSet {
        RuleSet(
            name: "Modern American",
            targetScore: 8500,
            red3Pts: 100,
            mixedPts: 300,
            purePts: 500,
            outPts: 100,
            outConcealedPts: 200,
            jokerPts: 50,
            deucePts: 20,
            acePts: 20,
            highCardPts: 10,
            lowCardPts: 5,
            black3Pts: 5,
            meldBelowZero: 125,
            meldTier1Threshold: 3000,
            meldTier1Requirement: 125,
            meldTier2Threshold: 5000,
            meldTier2Requirement: 155,
            meldTier3Requirement: 180,
            isBuiltIn: true
        )
    }
}

// MARK: - Game Model

@Model
final class CanastaGame {
    var team1Name: String = "Team 1"
    var team2Name: String = "Team 2"
    var team3Name: String = ""
    var date: Date = Date()

    var targetScore: Int = 5000
    var red3Pts: Int = 100
    var mixedPts: Int = 300
    var purePts: Int = 500
    var outPts: Int = 100
    var outConcealedPts: Int = 200
    var jokerPts: Int = 50
    var deucePts: Int = 20
    var acePts: Int = 20
    var highCardPts: Int = 10
    var lowCardPts: Int = 5
    var black3Pts: Int = 5

    var meldBelowZero: Int = 15
    var meldTier1Threshold: Int = 1500
    var meldTier1Requirement: Int = 50
    var meldTier2Threshold: Int = 3000
    var meldTier2Requirement: Int = 90
    var meldTier3Requirement: Int = 120

    @Relationship(deleteRule: .cascade, inverse: \Round.game)
    var rounds: [Round] = []

    init(
        team1Name: String = "Team 1",
        team2Name: String = "Team 2",
        team3Name: String = "",
        rules: RuleSet
    ) {
        self.team1Name = team1Name
        self.team2Name = team2Name
        self.team3Name = team3Name
        self.date = Date()

        self.targetScore = rules.targetScore
        self.red3Pts = rules.red3Pts
        self.mixedPts = rules.mixedPts
        self.purePts = rules.purePts
        self.outPts = rules.outPts
        self.outConcealedPts = rules.outConcealedPts
        self.jokerPts = rules.jokerPts
        self.deucePts = rules.deucePts
        self.acePts = rules.acePts
        self.highCardPts = rules.highCardPts
        self.lowCardPts = rules.lowCardPts
        self.black3Pts = rules.black3Pts

        self.meldBelowZero = rules.meldBelowZero
        self.meldTier1Threshold = rules.meldTier1Threshold
        self.meldTier1Requirement = rules.meldTier1Requirement
        self.meldTier2Threshold = rules.meldTier2Threshold
        self.meldTier2Requirement = rules.meldTier2Requirement
        self.meldTier3Requirement = rules.meldTier3Requirement
    }

    var scoringRules: CanastaScoringRules {
        CanastaScoringRules(
            targetScore: targetScore,
            red3Pts: red3Pts,
            mixedPts: mixedPts,
            purePts: purePts,
            outPts: outPts,
            outConcealedPts: outConcealedPts,
            jokerPts: jokerPts,
            deucePts: deucePts,
            acePts: acePts,
            highCardPts: highCardPts,
            lowCardPts: lowCardPts,
            black3Pts: black3Pts,
            meldBelowZero: meldBelowZero,
            meldTier1Threshold: meldTier1Threshold,
            meldTier1Requirement: meldTier1Requirement,
            meldTier2Threshold: meldTier2Threshold,
            meldTier2Requirement: meldTier2Requirement,
            meldTier3Requirement: meldTier3Requirement
        )
    }

    func openingMeld(for score: Int) -> Int {
        scoringRules.openingMeldRequirement(for: score)
    }

    var isThreeTeams: Bool {
        !team3Name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var sortedRounds: [Round] {
        rounds.sorted { $0.roundNumber < $1.roundNumber }
    }

    var team1Total: Int {
        rounds.reduce(0) { TallyMath.add($0, $1.team1RoundTotal) }
    }

    var team2Total: Int {
        rounds.reduce(0) { TallyMath.add($0, $1.team2RoundTotal) }
    }

    var team3Total: Int {
        rounds.reduce(0) { TallyMath.add($0, $1.team3RoundTotal) }
    }

    private var activeTeamScores: [(name: String, score: Int)] {
        if isThreeTeams {
            return [(team1Name, team1Total), (team2Name, team2Total), (team3Name, team3Total)]
        }
        return [(team1Name, team1Total), (team2Name, team2Total)]
    }

    var winner: String? {
        guard targetScore > 0 else { return nil }
        let scores = activeTeamScores
        guard let highest = scores.map(\.score).max(), highest >= targetScore else { return nil }
        let leaders = scores.filter { $0.score == highest }
        return leaders.count == 1 ? leaders[0].name : nil
    }

    var isTiedAtOrAboveTarget: Bool {
        guard targetScore > 0 else { return false }
        let scores = activeTeamScores
        guard let highest = scores.map(\.score).max(), highest >= targetScore else { return false }
        return scores.filter { $0.score == highest }.count > 1
    }

    func renumberRounds() {
        for (index, round) in sortedRounds.enumerated() {
            round.roundNumber = index + 1
        }
    }
}

// MARK: - Round Model

@Model
final class Round {
    var roundNumber: Int = 1
    var game: CanastaGame? = nil

    var t1WentOutConcealed: Bool = false
    var t2WentOutConcealed: Bool = false
    var t3WentOutConcealed: Bool = false

    var t1Red3s: Int = 0
    var t1MixedCanastas: Int = 0
    var t1PureCanastas: Int = 0
    var t1WentOut: Bool = false

    var t2Red3s: Int = 0
    var t2MixedCanastas: Int = 0
    var t2PureCanastas: Int = 0
    var t2WentOut: Bool = false

    var t3Red3s: Int = 0
    var t3MixedCanastas: Int = 0
    var t3PureCanastas: Int = 0
    var t3WentOut: Bool = false

    var t1Jokers: Int = 0
    var t1Deuces: Int = 0
    var t1Aces: Int = 0
    var t1HighCards: Int = 0
    var t1LowCards: Int = 0
    var t1Black3s: Int = 0

    var t2Jokers: Int = 0
    var t2Deuces: Int = 0
    var t2Aces: Int = 0
    var t2HighCards: Int = 0
    var t2LowCards: Int = 0
    var t2Black3s: Int = 0

    var t3Jokers: Int = 0
    var t3Deuces: Int = 0
    var t3Aces: Int = 0
    var t3HighCards: Int = 0
    var t3LowCards: Int = 0
    var t3Black3s: Int = 0

    // Cards remaining in hand (subtracted as penalties)
    var t1JokersInHand: Int = 0
    var t1DeucesInHand: Int = 0
    var t1AcesInHand: Int = 0
    var t1HighCardsInHand: Int = 0
    var t1LowCardsInHand: Int = 0
    var t1Black3sInHand: Int = 0

    var t2JokersInHand: Int = 0
    var t2DeucesInHand: Int = 0
    var t2AcesInHand: Int = 0
    var t2HighCardsInHand: Int = 0
    var t2LowCardsInHand: Int = 0
    var t2Black3sInHand: Int = 0

    var t3JokersInHand: Int = 0
    var t3DeucesInHand: Int = 0
    var t3AcesInHand: Int = 0
    var t3HighCardsInHand: Int = 0
    var t3LowCardsInHand: Int = 0
    var t3Black3sInHand: Int = 0

    init(roundNumber: Int) {
        self.roundNumber = roundNumber
    }

    func input(for slot: CanastaTeamSlot) -> CanastaTeamRoundInput {
        switch slot {
        case .team1:
            return CanastaTeamRoundInput(
                red3s: t1Red3s,
                mixedCanastas: t1MixedCanastas,
                pureCanastas: t1PureCanastas,
                wentOut: t1WentOutConcealed ? false : t1WentOut,
                wentOutConcealed: t1WentOutConcealed,
                jokers: t1Jokers,
                deuces: t1Deuces,
                aces: t1Aces,
                highCards: t1HighCards,
                lowCards: t1LowCards,
                black3s: t1Black3s,
                jokersInHand: t1JokersInHand,
                deucesInHand: t1DeucesInHand,
                acesInHand: t1AcesInHand,
                highCardsInHand: t1HighCardsInHand,
                lowCardsInHand: t1LowCardsInHand,
                black3sInHand: t1Black3sInHand
            )
        case .team2:
            return CanastaTeamRoundInput(
                red3s: t2Red3s,
                mixedCanastas: t2MixedCanastas,
                pureCanastas: t2PureCanastas,
                wentOut: t2WentOutConcealed ? false : t2WentOut,
                wentOutConcealed: t2WentOutConcealed,
                jokers: t2Jokers,
                deuces: t2Deuces,
                aces: t2Aces,
                highCards: t2HighCards,
                lowCards: t2LowCards,
                black3s: t2Black3s,
                jokersInHand: t2JokersInHand,
                deucesInHand: t2DeucesInHand,
                acesInHand: t2AcesInHand,
                highCardsInHand: t2HighCardsInHand,
                lowCardsInHand: t2LowCardsInHand,
                black3sInHand: t2Black3sInHand
            )
        case .team3:
            return CanastaTeamRoundInput(
                red3s: t3Red3s,
                mixedCanastas: t3MixedCanastas,
                pureCanastas: t3PureCanastas,
                wentOut: t3WentOutConcealed ? false : t3WentOut,
                wentOutConcealed: t3WentOutConcealed,
                jokers: t3Jokers,
                deuces: t3Deuces,
                aces: t3Aces,
                highCards: t3HighCards,
                lowCards: t3LowCards,
                black3s: t3Black3s,
                jokersInHand: t3JokersInHand,
                deucesInHand: t3DeucesInHand,
                acesInHand: t3AcesInHand,
                highCardsInHand: t3HighCardsInHand,
                lowCardsInHand: t3LowCardsInHand,
                black3sInHand: t3Black3sInHand
            )
        }
    }

    func apply(_ input: CanastaTeamRoundInput, for slot: CanastaTeamSlot) {
        let normalizedWentOut = input.wentOutConcealed ? false : input.wentOut
        switch slot {
        case .team1:
            t1Red3s = input.red3s
            t1MixedCanastas = input.mixedCanastas
            t1PureCanastas = input.pureCanastas
            t1WentOutConcealed = input.wentOutConcealed
            t1WentOut = normalizedWentOut
            t1Jokers = input.jokers
            t1Deuces = input.deuces
            t1Aces = input.aces
            t1HighCards = input.highCards
            t1LowCards = input.lowCards
            t1Black3s = input.black3s
            t1JokersInHand = input.jokersInHand
            t1DeucesInHand = input.deucesInHand
            t1AcesInHand = input.acesInHand
            t1HighCardsInHand = input.highCardsInHand
            t1LowCardsInHand = input.lowCardsInHand
            t1Black3sInHand = input.black3sInHand
        case .team2:
            t2Red3s = input.red3s
            t2MixedCanastas = input.mixedCanastas
            t2PureCanastas = input.pureCanastas
            t2WentOutConcealed = input.wentOutConcealed
            t2WentOut = normalizedWentOut
            t2Jokers = input.jokers
            t2Deuces = input.deuces
            t2Aces = input.aces
            t2HighCards = input.highCards
            t2LowCards = input.lowCards
            t2Black3s = input.black3s
            t2JokersInHand = input.jokersInHand
            t2DeucesInHand = input.deucesInHand
            t2AcesInHand = input.acesInHand
            t2HighCardsInHand = input.highCardsInHand
            t2LowCardsInHand = input.lowCardsInHand
            t2Black3sInHand = input.black3sInHand
        case .team3:
            t3Red3s = input.red3s
            t3MixedCanastas = input.mixedCanastas
            t3PureCanastas = input.pureCanastas
            t3WentOutConcealed = input.wentOutConcealed
            t3WentOut = normalizedWentOut
            t3Jokers = input.jokers
            t3Deuces = input.deuces
            t3Aces = input.aces
            t3HighCards = input.highCards
            t3LowCards = input.lowCards
            t3Black3s = input.black3s
            t3JokersInHand = input.jokersInHand
            t3DeucesInHand = input.deucesInHand
            t3AcesInHand = input.acesInHand
            t3HighCardsInHand = input.highCardsInHand
            t3LowCardsInHand = input.lowCardsInHand
            t3Black3sInHand = input.black3sInHand
        }
    }

    var team1RoundTotal: Int {
        guard let game else { return 0 }
        return CanastaScorer.roundTotal(for: input(for: .team1), rules: game.scoringRules)
    }

    var team2RoundTotal: Int {
        guard let game else { return 0 }
        return CanastaScorer.roundTotal(for: input(for: .team2), rules: game.scoringRules)
    }

    var team3RoundTotal: Int {
        guard let game else { return 0 }
        return CanastaScorer.roundTotal(for: input(for: .team3), rules: game.scoringRules)
    }
}
