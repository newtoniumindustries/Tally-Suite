import Foundation
import SwiftData

private enum CanastaScoreMath {
    nonisolated static let maxMagnitude = 999_999_999

    nonisolated static func clamp(_ value: Int) -> Int {
        min(max(value, -maxMagnitude), maxMagnitude)
    }

    nonisolated static func add(_ lhs: Int, _ rhs: Int) -> Int {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        if overflow {
            return rhs > 0 ? maxMagnitude : -maxMagnitude
        }
        return clamp(result)
    }

    nonisolated static func subtract(_ lhs: Int, _ rhs: Int) -> Int {
        let (result, overflow) = lhs.subtractingReportingOverflow(rhs)
        if overflow {
            return rhs > 0 ? -maxMagnitude : maxMagnitude
        }
        return clamp(result)
    }

    nonisolated static func multiply(_ lhs: Int, _ rhs: Int) -> Int {
        let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        if overflow {
            return (lhs >= 0) == (rhs >= 0) ? maxMagnitude : -maxMagnitude
        }
        return clamp(result)
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
        self.isBuiltIn = isBuiltIn
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
    }

    var isThreeTeams: Bool {
        !team3Name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var sortedRounds: [Round] {
        rounds.sorted { $0.roundNumber < $1.roundNumber }
    }

    var team1Total: Int {
        rounds.reduce(0) { CanastaScoreMath.add($0, $1.team1RoundTotal) }
    }

    var team2Total: Int {
        rounds.reduce(0) { CanastaScoreMath.add($0, $1.team2RoundTotal) }
    }

    var team3Total: Int {
        rounds.reduce(0) { CanastaScoreMath.add($0, $1.team3RoundTotal) }
    }

    var winner: String? {
        guard targetScore > 0 else { return nil }

        if isThreeTeams {
            if team1Total >= targetScore && team1Total > team2Total && team1Total > team3Total {
                return team1Name
            }
            if team2Total >= targetScore && team2Total > team1Total && team2Total > team3Total {
                return team2Name
            }
            if team3Total >= targetScore && team3Total > team1Total && team3Total > team2Total {
                return team3Name
            }
            return nil
        } else {
            if team1Total >= targetScore && team1Total > team2Total {
                return team1Name
            }
            if team2Total >= targetScore && team2Total > team1Total {
                return team2Name
            }
            return nil
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

    var team1RoundTotal: Int {
        calculateRoundTotal(
            red3s: t1Red3s,
            mixedCanastas: t1MixedCanastas,
            pureCanastas: t1PureCanastas,
            wentOut: t1WentOut,
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
    }

    var team2RoundTotal: Int {
        calculateRoundTotal(
            red3s: t2Red3s,
            mixedCanastas: t2MixedCanastas,
            pureCanastas: t2PureCanastas,
            wentOut: t2WentOut,
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
    }

    var team3RoundTotal: Int {
        calculateRoundTotal(
            red3s: t3Red3s,
            mixedCanastas: t3MixedCanastas,
            pureCanastas: t3PureCanastas,
            wentOut: t3WentOut,
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

    private func calculateRoundTotal(
        red3s: Int,
        mixedCanastas: Int,
        pureCanastas: Int,
        wentOut: Bool,
        wentOutConcealed: Bool,
        jokers: Int,
        deuces: Int,
        aces: Int,
        highCards: Int,
        lowCards: Int,
        black3s: Int,
        jokersInHand: Int,
        deucesInHand: Int,
        acesInHand: Int,
        highCardsInHand: Int,
        lowCardsInHand: Int,
        black3sInHand: Int
    ) -> Int {
        guard let g = game else { return 0 }

        // 4 (or more) Red 3s score double (e.g. 4 * 100 * 2 = 800; also doubles negative -4 to -800 if entered as penalty)
        let red3Base = CanastaScoreMath.multiply(red3s, g.red3Pts)
        let red3Score = abs(red3s) >= 4 ? CanastaScoreMath.multiply(red3Base, 2) : red3Base

        // Concealed going out replaces the standard going-out bonus rather than stacking
        let goingOutBonus = wentOutConcealed ? g.outConcealedPts : (wentOut ? g.outPts : 0)

        let base = [
            red3Score,
            CanastaScoreMath.multiply(mixedCanastas, g.mixedPts),
            CanastaScoreMath.multiply(pureCanastas, g.purePts),
            goingOutBonus
        ].reduce(0, CanastaScoreMath.add)

        let cards = [
            CanastaScoreMath.multiply(jokers, g.jokerPts),
            CanastaScoreMath.multiply(deuces, g.deucePts),
            CanastaScoreMath.multiply(aces, g.acePts),
            CanastaScoreMath.multiply(highCards, g.highCardPts),
            CanastaScoreMath.multiply(lowCards, g.lowCardPts),
            CanastaScoreMath.multiply(black3s, g.black3Pts)
        ].reduce(0, CanastaScoreMath.add)

        let penalty = [
            CanastaScoreMath.multiply(jokersInHand, g.jokerPts),
            CanastaScoreMath.multiply(deucesInHand, g.deucePts),
            CanastaScoreMath.multiply(acesInHand, g.acePts),
            CanastaScoreMath.multiply(highCardsInHand, g.highCardPts),
            CanastaScoreMath.multiply(lowCardsInHand, g.lowCardPts),
            CanastaScoreMath.multiply(black3sInHand, g.black3Pts)
        ].reduce(0, CanastaScoreMath.add)

        let gross = CanastaScoreMath.add(base, cards)
        return CanastaScoreMath.subtract(gross, penalty)
    }
}
