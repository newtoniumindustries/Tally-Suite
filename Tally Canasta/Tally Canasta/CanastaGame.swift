import Foundation
import SwiftData

// MARK: - Reusable Scoring Templates
@Model
class RuleSet {
    var name: String
    var targetScore: Int
    var red3Pts: Int
    var mixedPts: Int
    var purePts: Int
    var outPts: Int
    var outConcealedPts: Int
    
    var jokerPts: Int
    var deucePts: Int
    var acePts: Int
    var highCardPts: Int
    var lowCardPts: Int
    var black3Pts: Int
    
    var isBuiltIn: Bool

    init(name: String, targetScore: Int, red3Pts: Int = 100, mixedPts: Int = 300, purePts: Int = 500, outPts: Int = 100, outConcealedPts: Int = 200, jokerPts: Int = 50, deucePts: Int = 20, acePts: Int = 20, highCardPts: Int = 10, lowCardPts: Int = 5, black3Pts: Int = 5, isBuiltIn: Bool = false) {
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
class CanastaGame {
    var team1Name: String
    var team2Name: String
    var team3Name: String // Added for 3-team support (Empty string means 2 teams)
    var date: Date
    
    var targetScore: Int
    var red3Pts: Int; var mixedPts: Int; var purePts: Int; var outPts: Int; var outConcealedPts: Int
    var jokerPts: Int; var deucePts: Int; var acePts: Int; var highCardPts: Int; var lowCardPts: Int; var black3Pts: Int
    
    @Relationship(deleteRule: .cascade, inverse: \Round.game) var rounds: [Round] = []

    init(team1Name: String = "Team 1", team2Name: String = "Team 2", team3Name: String = "", rules: RuleSet) {
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
    
    @Transient var isThreeTeams: Bool { !team3Name.isEmpty }
    @Transient var team1Total: Int { rounds.reduce(0) { $0 + $1.team1RoundTotal } }
    @Transient var team2Total: Int { rounds.reduce(0) { $0 + $1.team2RoundTotal } }
    @Transient var team3Total: Int { rounds.reduce(0) { $0 + $1.team3RoundTotal } }
    
    @Transient var winner: String? {
        if team1Total >= targetScore && team1Total > team2Total && team1Total > team3Total { return team1Name }
        if team2Total >= targetScore && team2Total > team1Total && team2Total > team3Total { return team2Name }
        if isThreeTeams && team3Total >= targetScore && team3Total > team1Total && team3Total > team2Total { return team3Name }
        return nil
    }
}

// MARK: - Round Model
@Model
class Round {
    var roundNumber: Int
    var game: CanastaGame?
    var t1WentOutConcealed: Bool = false
    var t2WentOutConcealed: Bool = false
    var t3WentOutConcealed: Bool = false
    
    var t1Red3s: Int = 0; var t1MixedCanastas: Int = 0; var t1PureCanastas: Int = 0; var t1WentOut: Bool = false
    var t2Red3s: Int = 0; var t2MixedCanastas: Int = 0; var t2PureCanastas: Int = 0; var t2WentOut: Bool = false
    var t3Red3s: Int = 0; var t3MixedCanastas: Int = 0; var t3PureCanastas: Int = 0; var t3WentOut: Bool = false
    
    var t1Jokers: Int = 0; var t1Deuces: Int = 0; var t1Aces: Int = 0; var t1HighCards: Int = 0; var t1LowCards: Int = 0; var t1Black3s: Int = 0
    var t2Jokers: Int = 0; var t2Deuces: Int = 0; var t2Aces: Int = 0; var t2HighCards: Int = 0; var t2LowCards: Int = 0; var t2Black3s: Int = 0
    var t3Jokers: Int = 0; var t3Deuces: Int = 0; var t3Aces: Int = 0; var t3HighCards: Int = 0; var t3LowCards: Int = 0; var t3Black3s: Int = 0
    
    // NEW: "Cards In Hand" variables for subtraction penalties
    var t1JokersInHand: Int = 0; var t1DeucesInHand: Int = 0; var t1AcesInHand: Int = 0; var t1HighCardsInHand: Int = 0; var t1LowCardsInHand: Int = 0; var t1Black3sInHand: Int = 0
    var t2JokersInHand: Int = 0; var t2DeucesInHand: Int = 0; var t2AcesInHand: Int = 0; var t2HighCardsInHand: Int = 0; var t2LowCardsInHand: Int = 0; var t2Black3sInHand: Int = 0
    var t3JokersInHand: Int = 0; var t3DeucesInHand: Int = 0; var t3AcesInHand: Int = 0; var t3HighCardsInHand: Int = 0; var t3LowCardsInHand: Int = 0; var t3Black3sInHand: Int = 0
    
    init(roundNumber: Int) {
        self.roundNumber = roundNumber
    }
    
    @Transient var team1RoundTotal: Int {
        guard let g = game else { return 0 }
        let base = (t1Red3s * g.red3Pts) + (t1MixedCanastas * g.mixedPts) + (t1PureCanastas * g.purePts) + (t1WentOut ? g.outPts : 0) + (t1WentOutConcealed ? g.outConcealedPts : 0)
        let cards = (t1Jokers * g.jokerPts) + (t1Deuces * g.deucePts) + (t1Aces * g.acePts) + (t1HighCards * g.highCardPts) + (t1LowCards * g.lowCardPts) + (t1Black3s * g.black3Pts)
        let penalty = (t1JokersInHand * g.jokerPts) + (t1DeucesInHand * g.deucePts) + (t1AcesInHand * g.acePts) + (t1HighCardsInHand * g.highCardPts) + (t1LowCardsInHand * g.lowCardPts) + (t1Black3sInHand * g.black3Pts)
        return base + cards - penalty
    }
    
    @Transient var team2RoundTotal: Int {
        guard let g = game else { return 0 }
        let base = (t2Red3s * g.red3Pts) + (t2MixedCanastas * g.mixedPts) + (t2PureCanastas * g.purePts) + (t2WentOut ? g.outPts : 0) + (t2WentOutConcealed ? g.outConcealedPts : 0)
        let cards = (t2Jokers * g.jokerPts) + (t2Deuces * g.deucePts) + (t2Aces * g.acePts) + (t2HighCards * g.highCardPts) + (t2LowCards * g.lowCardPts) + (t2Black3s * g.black3Pts)
        let penalty = (t2JokersInHand * g.jokerPts) + (t2DeucesInHand * g.deucePts) + (t2AcesInHand * g.acePts) + (t2HighCardsInHand * g.highCardPts) + (t2LowCardsInHand * g.lowCardPts) + (t2Black3sInHand * g.black3Pts)
        return base + cards - penalty
    }
    
    @Transient var team3RoundTotal: Int {
        guard let g = game else { return 0 }
        let base = (t3Red3s * g.red3Pts) + (t3MixedCanastas * g.mixedPts) + (t3PureCanastas * g.purePts) + (t3WentOut ? g.outPts : 0) + (t3WentOutConcealed ? g.outConcealedPts : 0)
        let cards = (t3Jokers * g.jokerPts) + (t3Deuces * g.deucePts) + (t3Aces * g.acePts) + (t3HighCards * g.highCardPts) + (t3LowCards * g.lowCardPts) + (t3Black3s * g.black3Pts)
        let penalty = (t3JokersInHand * g.jokerPts) + (t3DeucesInHand * g.deucePts) + (t3AcesInHand * g.acePts) + (t3HighCardsInHand * g.highCardPts) + (t3LowCardsInHand * g.lowCardPts) + (t3Black3sInHand * g.black3Pts)
        return base + cards - penalty
    }
}
