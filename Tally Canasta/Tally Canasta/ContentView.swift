import SwiftUI
import SwiftData
import UIKit
import TallyCore

// MARK: - 1. Dashboard
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CanastaGame.date, order: .reverse) private var games: [CanastaGame]
    @State private var showingNewGameSheet = false
    @State private var showingHowToPlay = false
    @State private var showingRoster = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    ForEach(games) { game in
                        NavigationLink(destination: GameLedgerView(game: game)) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(game.isThreeTeams ? "\(game.team1Name) vs \(game.team2Name) vs \(game.team3Name)" : "\(game.team1Name) vs \(game.team2Name)")
                                        .font(.headline)
                                    Text("Target: \(game.targetScore)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(game.isThreeTeams ? "\(game.team1Total) / \(game.team2Total) / \(game.team3Total)" : "\(game.team1Total) / \(game.team2Total)")
                                    .font(.system(.title3, design: .rounded).weight(.bold))
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .onDelete(perform: deleteGames)
                }
                
                Button(action: { showingHowToPlay = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "book.pages")
                        Text("How to Play Canasta")
                            .fontWeight(.medium)
                    }
                    .font(.footnote)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color(UIColor.secondarySystemBackground))
                    .foregroundColor(.blue)
                }
            }
            .navigationTitle("Tally: Canasta")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        Button("Roster", systemImage: "person.3") { showingRoster = true }
                        Button("New Game", systemImage: "plus") { showingNewGameSheet = true }
                    }
                }
            }
            .sheet(isPresented: $showingNewGameSheet) { NewGameSheet() }
            .sheet(isPresented: $showingHowToPlay) { HowToPlaySheet() }
            .sheet(isPresented: $showingRoster) {
                PlayerRosterView()
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func deleteGames(offsets: IndexSet) {
        for index in offsets { modelContext.delete(games[index]) }
    }
}

// MARK: - 2. New Game Setup
struct NewGameSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query private var ruleSets: [RuleSet]
    @Query(sort: \TallyPlayer.name) private var players: [TallyPlayer]
    @State private var selectedRuleSetName: String = "Classic"
    
    @State private var showingCustomRuleSheet = false
    @State private var showingRuleDetails = false
    
    @State private var team1 = "Team 1"
    @State private var team2 = "Team 2"
    @State private var team3 = ""
    @State private var customWinningScore = "5000"

    var body: some View {
        NavigationStack {
            Form {
                Section("Teams") {
                    HStack {
                        TextField("Team 1 Name", text: $team1)
                        if !players.isEmpty {
                            Menu {
                                ForEach(players) { player in
                                    Button(player.name) { team1 = player.name }
                                }
                            } label: { Image(systemName: "person.crop.circle.badge.plus").foregroundColor(.blue) }
                        }
                    }
                    
                    HStack {
                        TextField("Team 2 Name", text: $team2)
                        if !players.isEmpty {
                            Menu {
                                ForEach(players) { player in
                                    Button(player.name) { team2 = player.name }
                                }
                            } label: { Image(systemName: "person.crop.circle.badge.plus").foregroundColor(.blue) }
                        }
                    }
                    
                    HStack {
                        TextField("Team 3 Name (Optional)", text: $team3)
                        if !players.isEmpty {
                            Menu {
                                ForEach(players) { player in
                                    Button(player.name) { team3 = player.name }
                                }
                            } label: { Image(systemName: "person.crop.circle.badge.plus").foregroundColor(.blue) }
                        }
                    }
                }
                
                Section("Scoring Rules") {
                    if !ruleSets.isEmpty {
                        Picker("Ruleset", selection: $selectedRuleSetName) {
                            ForEach(ruleSets) { rules in
                                Text(rules.name).tag(rules.name)
                            }
                        }
                        .onChange(of: selectedRuleSetName) { oldValue, newValue in
                            if let matchedRule = ruleSets.first(where: { $0.name == newValue }) {
                                customWinningScore = String(matchedRule.targetScore)
                            }
                        }
                        
                        if let _ = ruleSets.first(where: { $0.name == selectedRuleSetName }) {
                            Button(action: { showingRuleDetails = true }) {
                                HStack {
                                    Text("View Ruleset Details").foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "info.circle").foregroundColor(.blue)
                                }
                            }
                        }
                    } else {
                        Text("Loading defaults...").foregroundColor(.secondary)
                    }
                    
                    Button("Create Custom Rule Set...") { showingCustomRuleSheet = true }
                }
                
                Section(header: Text("Winning Score"), footer: Text("You can manually adjust the winning score for this specific game without changing the saved ruleset.")) {
                    TextField("Winning Score", text: $customWinningScore).keyboardType(.numberPad)
                }
            }
            .navigationTitle("New Game")
            .onAppear(perform: seedDefaultRules)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        guard let rules = ruleSets.first(where: { $0.name == selectedRuleSetName }) else { return }
                        let newGame = CanastaGame(team1Name: team1, team2Name: team2, team3Name: team3, rules: rules)
                        newGame.targetScore = Int(customWinningScore) ?? rules.targetScore
                        modelContext.insert(newGame)
                        dismiss()
                    }
                }
                // Global keyboard dismiss for New Game form
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .sheet(isPresented: $showingCustomRuleSheet) {
                CustomRuleSheet(selectedRuleSetName: $selectedRuleSetName)
                    .onDisappear {
                        if let updatedTarget = ruleSets.first(where: { $0.name == selectedRuleSetName })?.targetScore {
                            customWinningScore = String(updatedTarget)
                        }
                    }
            }
            .sheet(isPresented: $showingRuleDetails) {
                if let rules = ruleSets.first(where: { $0.name == selectedRuleSetName }) {
                    RuleDetailsSheet(rules: rules)
                }
            }
        }
    }
    
    private func seedDefaultRules() {
        if ruleSets.isEmpty {
            let classic = RuleSet(name: "Classic", targetScore: 5000, isBuiltIn: true)
            let modern = RuleSet(name: "Modern American", targetScore: 8500, isBuiltIn: true)
            modelContext.insert(classic)
            modelContext.insert(modern)
            selectedRuleSetName = "Classic"
            customWinningScore = "5000"
        } else if selectedRuleSetName.isEmpty, let first = ruleSets.first {
            selectedRuleSetName = first.name
            customWinningScore = String(first.targetScore)
        }
    }
}

// MARK: - 3. Custom Rule Creator
struct CustomRuleSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Binding var selectedRuleSetName: String
    
    @State private var name = ""; @State private var target = "5000"
    @State private var red3 = "100"; @State private var mixed = "300"; @State private var pure = "500"; @State private var out = "100"
    @State private var outConcealed = "200"; @State private var joker = "50"; @State private var deuce = "20"; @State private var high = "10"; @State private var low = "5"; @State private var black3 = "5"
    
    // Extracted save function to keep toolbar clean
    private func saveRules() {
        let safeName = name.isEmpty ? "Custom" : name
        let newRules = RuleSet(name: safeName, targetScore: Int(target) ?? 5000, red3Pts: Int(red3) ?? 100, mixedPts: Int(mixed) ?? 300, purePts: Int(pure) ?? 500, outPts: Int(out) ?? 100, outConcealedPts: Int(outConcealed) ?? 200, jokerPts: Int(joker) ?? 50, deucePts: Int(deuce) ?? 20, acePts: Int(deuce) ?? 20, highCardPts: Int(high) ?? 10, lowCardPts: Int(low) ?? 5, black3Pts: Int(black3) ?? 5, isBuiltIn: false)
        modelContext.insert(newRules)
        selectedRuleSetName = safeName
        dismiss()
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Settings") {
                    TextField("Configuration Name (e.g., 'House Rules')", text: $name)
                    CustomRuleInputRow(title: "Winning Score", value: $target)
                }
                
                Section("Bonus & Melds") {
                    CustomRuleInputRow(title: "Red 3 Points", value: $red3)
                    CustomRuleInputRow(title: "Mixed Canasta Points", value: $mixed)
                    CustomRuleInputRow(title: "Pure Canasta Points", value: $pure)
                    CustomRuleInputRow(title: "Going Out Bonus", value: $out)
                    CustomRuleInputRow(title: "Going Out Concealed", value: $outConcealed)
                }
                
                Section("Individual Card Values") {
                    CustomRuleInputRow(title: "Jokers", value: $joker)
                    CustomRuleInputRow(title: "Deuces (2s) & Aces", value: $deuce)
                    CustomRuleInputRow(title: "8 through King", value: $high)
                    CustomRuleInputRow(title: "4 through 7", value: $low)
                    CustomRuleInputRow(title: "Black 3s", value: $black3)
                }
            }
            .navigationTitle("Custom Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveRules() }
                }
                // Global keyboard dismiss for Rules Form
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
    }
}

// MARK: - 4. The Ledger
struct GameLedgerView: View {
    @Bindable var game: CanastaGame
    @State private var showingNewRoundEntry = false
    @State private var roundToEdit: Round?
    
    private func openingMeld(for score: Int) -> Int {
        if score < 0 { return 15 }
        if score < 1500 { return 50 }
        if score < 3000 { return 90 }
        return 120
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if let winner = game.winner {
                    Text("🎉 \(winner) WINS! 🎉")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green)
                }
                
                HStack(spacing: 0) {
                    TeamHeaderView(name: game.team1Name, total: game.team1Total, meldReq: openingMeld(for: game.team1Total), color: .blue)
                    Divider().frame(height: 80)
                    TeamHeaderView(name: game.team2Name, total: game.team2Total, meldReq: openingMeld(for: game.team2Total), color: .red)
                    
                    if game.isThreeTeams {
                        Divider().frame(height: 80)
                        TeamHeaderView(name: game.team3Name, total: game.team3Total, meldReq: openingMeld(for: game.team3Total), color: .green)
                    }
                }
                Divider()
            }
            
            List {
                ForEach(game.rounds.sorted(by: { $0.roundNumber > $1.roundNumber })) { round in
                    Button(action: { roundToEdit = round }) {
                        HStack {
                            Text("R\(round.roundNumber)")
                                .font(.caption).foregroundColor(.secondary).frame(width: 25, alignment: .leading)
                            
                            Text(round.team1RoundTotal >= 0 ? "+\(round.team1RoundTotal)" : "\(round.team1RoundTotal)")
                                .font(.system(.body, design: .rounded).weight(.bold))
                                .frame(maxWidth: .infinity, alignment: .center)
                            
                            Text(round.team2RoundTotal >= 0 ? "+\(round.team2RoundTotal)" : "\(round.team2RoundTotal)")
                                .font(.system(.body, design: .rounded).weight(.bold))
                                .frame(maxWidth: .infinity, alignment: .center)
                                
                            if game.isThreeTeams {
                                Text(round.team3RoundTotal >= 0 ? "+\(round.team3RoundTotal)" : "\(round.team3RoundTotal)")
                                    .font(.system(.body, design: .rounded).weight(.bold))
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }
                .onDelete { indexSet in
                    let sortedRounds = game.rounds.sorted(by: { $0.roundNumber > $1.roundNumber })
                    for index in indexSet { game.rounds.removeAll(where: { $0.id == sortedRounds[index].id }) }
                    let remainingRounds = game.rounds.sorted(by: { $0.roundNumber < $1.roundNumber })
                    for (i, round) in remainingRounds.enumerated() { round.roundNumber = i + 1 }
                }
            }
            
            Button(action: { showingNewRoundEntry = true }) {
                Text("Record Round")
                    .font(.headline).frame(maxWidth: .infinity).padding()
                    .background(Color.blue).foregroundColor(.white).cornerRadius(10)
            }
            .padding()
            .disabled(game.winner != nil)
        }
        .navigationTitle("Scoreboard")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingNewRoundEntry) { RoundEntrySheet(game: game, editingRound: nil) }
        .sheet(item: $roundToEdit) { round in RoundEntrySheet(game: game, editingRound: round) }
    }
}

struct TeamHeaderView: View {
    let name: String
    let total: Int
    let meldReq: Int
    let color: Color
    
    var body: some View {
        VStack {
            Text(name).font(.headline).lineLimit(1)
            Text("\(total)")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
            
            Text("Meld req: \(meldReq)")
                .font(.caption2).fontWeight(.medium)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(color.opacity(0.15))
                .foregroundColor(color)
                .cornerRadius(6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
        .background(color.opacity(0.04))
    }
}

// MARK: - Temporary Form State
struct DraftRoundData {
    var t1Red3s = 0, t1MixedCanastas = 0, t1PureCanastas = 0, t1WentOut = false, t1WentOutConcealed = false
    var t2Red3s = 0, t2MixedCanastas = 0, t2PureCanastas = 0, t2WentOut = false, t2WentOutConcealed = false
    var t3Red3s = 0, t3MixedCanastas = 0, t3PureCanastas = 0, t3WentOut = false, t3WentOutConcealed = false
    
    var t1Jokers = 0, t1Deuces = 0, t1Aces = 0, t1HighCards = 0, t1LowCards = 0, t1Black3s = 0
    var t2Jokers = 0, t2Deuces = 0, t2Aces = 0, t2HighCards = 0, t2LowCards = 0, t2Black3s = 0
    var t3Jokers = 0, t3Deuces = 0, t3Aces = 0, t3HighCards = 0, t3LowCards = 0, t3Black3s = 0
    
    var t1JokersInHand = 0, t1DeucesInHand = 0, t1AcesInHand = 0, t1HighCardsInHand = 0, t1LowCardsInHand = 0, t1Black3sInHand = 0
    var t2JokersInHand = 0, t2DeucesInHand = 0, t2AcesInHand = 0, t2HighCardsInHand = 0, t2LowCardsInHand = 0, t2Black3sInHand = 0
    var t3JokersInHand = 0, t3DeucesInHand = 0, t3AcesInHand = 0, t3HighCardsInHand = 0, t3LowCardsInHand = 0, t3Black3sInHand = 0
    
    func team1Total(game: CanastaGame) -> Int {
        let base = (t1Red3s * game.red3Pts) + (t1MixedCanastas * game.mixedPts) + (t1PureCanastas * game.purePts) + (t1WentOut ? game.outPts : 0) + (t1WentOutConcealed ? game.outConcealedPts : 0)
        let cards = (t1Jokers * game.jokerPts) + (t1Deuces * game.deucePts) + (t1Aces * game.acePts) + (t1HighCards * game.highCardPts) + (t1LowCards * game.lowCardPts) + (t1Black3s * game.black3Pts)
        let penalty = (t1JokersInHand * game.jokerPts) + (t1DeucesInHand * game.deucePts) + (t1AcesInHand * game.acePts) + (t1HighCardsInHand * game.highCardPts) + (t1LowCardsInHand * game.lowCardPts) + (t1Black3sInHand * game.black3Pts)
        return base + cards - penalty
    }
    
    func team2Total(game: CanastaGame) -> Int {
        let base = (t2Red3s * game.red3Pts) + (t2MixedCanastas * game.mixedPts) + (t2PureCanastas * game.purePts) + (t2WentOut ? game.outPts : 0) + (t2WentOutConcealed ? game.outConcealedPts : 0)
        let cards = (t2Jokers * game.jokerPts) + (t2Deuces * game.deucePts) + (t2Aces * game.acePts) + (t2HighCards * game.highCardPts) + (t2LowCards * game.lowCardPts) + (t2Black3s * game.black3Pts)
        let penalty = (t2JokersInHand * game.jokerPts) + (t2DeucesInHand * game.deucePts) + (t2AcesInHand * game.acePts) + (t2HighCardsInHand * game.highCardPts) + (t2LowCardsInHand * game.lowCardPts) + (t2Black3sInHand * game.black3Pts)
        return base + cards - penalty
    }
    
    func team3Total(game: CanastaGame) -> Int {
        let base = (t3Red3s * game.red3Pts) + (t3MixedCanastas * game.mixedPts) + (t3PureCanastas * game.purePts) + (t3WentOut ? game.outPts : 0) + (t3WentOutConcealed ? game.outConcealedPts : 0)
        let cards = (t3Jokers * game.jokerPts) + (t3Deuces * game.deucePts) + (t3Aces * game.acePts) + (t3HighCards * game.highCardPts) + (t3LowCards * game.lowCardPts) + (t3Black3s * game.black3Pts)
        let penalty = (t3JokersInHand * game.jokerPts) + (t3DeucesInHand * game.deucePts) + (t3AcesInHand * game.acePts) + (t3HighCardsInHand * game.highCardPts) + (t3LowCardsInHand * game.lowCardPts) + (t3Black3sInHand * game.black3Pts)
        return base + cards - penalty
    }
}

// MARK: - 5. Round Entry Form (Sliding Pages)
struct RoundEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    var game: CanastaGame
    var editingRound: Round?
    @State private var draft = DraftRoundData()
    @State private var selectedTab = 0
    @State private var currentDetent: PresentationDetent = .large

    // Extracted save function to keep toolbar clean
    private func saveRound() {
        if let round = editingRound {
            round.t1Red3s = draft.t1Red3s; round.t1MixedCanastas = draft.t1MixedCanastas; round.t1PureCanastas = draft.t1PureCanastas; round.t1WentOut = draft.t1WentOut; round.t1WentOutConcealed = draft.t1WentOutConcealed
            round.t2Red3s = draft.t2Red3s; round.t2MixedCanastas = draft.t2MixedCanastas; round.t2PureCanastas = draft.t2PureCanastas; round.t2WentOut = draft.t2WentOut; round.t2WentOutConcealed = draft.t2WentOutConcealed
            round.t3Red3s = draft.t3Red3s; round.t3MixedCanastas = draft.t3MixedCanastas; round.t3PureCanastas = draft.t3PureCanastas; round.t3WentOut = draft.t3WentOut; round.t3WentOutConcealed = draft.t3WentOutConcealed
            
            round.t1Jokers = draft.t1Jokers; round.t1Deuces = draft.t1Deuces; round.t1Aces = draft.t1Aces; round.t1HighCards = draft.t1HighCards; round.t1LowCards = draft.t1LowCards; round.t1Black3s = draft.t1Black3s
            round.t2Jokers = draft.t2Jokers; round.t2Deuces = draft.t2Deuces; round.t2Aces = draft.t2Aces; round.t2HighCards = draft.t2HighCards; round.t2LowCards = draft.t2LowCards; round.t2Black3s = draft.t2Black3s
            round.t3Jokers = draft.t3Jokers; round.t3Deuces = draft.t3Deuces; round.t3Aces = draft.t3Aces; round.t3HighCards = draft.t3HighCards; round.t3LowCards = draft.t3LowCards; round.t3Black3s = draft.t3Black3s
            
            round.t1JokersInHand = draft.t1JokersInHand; round.t1DeucesInHand = draft.t1DeucesInHand; round.t1AcesInHand = draft.t1AcesInHand; round.t1HighCardsInHand = draft.t1HighCardsInHand; round.t1LowCardsInHand = draft.t1LowCardsInHand; round.t1Black3sInHand = draft.t1Black3sInHand
            round.t2JokersInHand = draft.t2JokersInHand; round.t2DeucesInHand = draft.t2DeucesInHand; round.t2AcesInHand = draft.t2AcesInHand; round.t2HighCardsInHand = draft.t2HighCardsInHand; round.t2LowCardsInHand = draft.t2LowCardsInHand; round.t2Black3sInHand = draft.t2Black3sInHand
            round.t3JokersInHand = draft.t3JokersInHand; round.t3DeucesInHand = draft.t3DeucesInHand; round.t3AcesInHand = draft.t3AcesInHand; round.t3HighCardsInHand = draft.t3HighCardsInHand; round.t3LowCardsInHand = draft.t3LowCardsInHand; round.t3Black3sInHand = draft.t3Black3sInHand
        } else {
            let newRound = Round(roundNumber: (game.rounds.map { $0.roundNumber }.max() ?? 0) + 1)
            newRound.t1Red3s = draft.t1Red3s; newRound.t1MixedCanastas = draft.t1MixedCanastas; newRound.t1PureCanastas = draft.t1PureCanastas; newRound.t1WentOut = draft.t1WentOut; newRound.t1WentOutConcealed = draft.t1WentOutConcealed
            newRound.t2Red3s = draft.t2Red3s; newRound.t2MixedCanastas = draft.t2MixedCanastas; newRound.t2PureCanastas = draft.t2PureCanastas; newRound.t2WentOut = draft.t2WentOut; newRound.t2WentOutConcealed = draft.t2WentOutConcealed
            newRound.t3Red3s = draft.t3Red3s; newRound.t3MixedCanastas = draft.t3MixedCanastas; newRound.t3PureCanastas = draft.t3PureCanastas; newRound.t3WentOut = draft.t3WentOut; newRound.t3WentOutConcealed = draft.t3WentOutConcealed
            
            newRound.t1Jokers = draft.t1Jokers; newRound.t1Deuces = draft.t1Deuces; newRound.t1Aces = draft.t1Aces; newRound.t1HighCards = draft.t1HighCards; newRound.t1LowCards = draft.t1LowCards; newRound.t1Black3s = draft.t1Black3s
            newRound.t2Jokers = draft.t2Jokers; newRound.t2Deuces = draft.t2Deuces; newRound.t2Aces = draft.t2Aces; newRound.t2HighCards = draft.t2HighCards; newRound.t2LowCards = draft.t2LowCards; newRound.t2Black3s = draft.t2Black3s
            newRound.t3Jokers = draft.t3Jokers; newRound.t3Deuces = draft.t3Deuces; newRound.t3Aces = draft.t3Aces; newRound.t3HighCards = draft.t3HighCards; newRound.t3LowCards = draft.t3LowCards; newRound.t3Black3s = draft.t3Black3s
            
            newRound.t1JokersInHand = draft.t1JokersInHand; newRound.t1DeucesInHand = draft.t1DeucesInHand; newRound.t1AcesInHand = draft.t1AcesInHand; newRound.t1HighCardsInHand = draft.t1HighCardsInHand; newRound.t1LowCardsInHand = draft.t1LowCardsInHand; newRound.t1Black3sInHand = draft.t1Black3sInHand
            newRound.t2JokersInHand = draft.t2JokersInHand; newRound.t2DeucesInHand = draft.t2DeucesInHand; newRound.t2AcesInHand = draft.t2AcesInHand; newRound.t2HighCardsInHand = draft.t2HighCardsInHand; newRound.t2LowCardsInHand = draft.t2LowCardsInHand; newRound.t2Black3sInHand = draft.t2Black3sInHand
            newRound.t3JokersInHand = draft.t3JokersInHand; newRound.t3DeucesInHand = draft.t3DeucesInHand; newRound.t3AcesInHand = draft.t3AcesInHand; newRound.t3HighCardsInHand = draft.t3HighCardsInHand; newRound.t3LowCardsInHand = draft.t3LowCardsInHand; newRound.t3Black3sInHand = draft.t3Black3sInHand
            
            game.rounds.append(newRound)
        }
        dismiss()
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                // PAGE 1: Teams 1 & 2
                Form {
                    HStack {
                        if game.isThreeTeams { Image(systemName: "chevron.left.circle.fill").opacity(0) }
                        Text(game.team1Name).bold().frame(maxWidth: .infinity)
                        Text(game.team2Name).bold().frame(maxWidth: .infinity)
                        if game.isThreeTeams {
                            Button(action: { withAnimation { selectedTab = 1 } }) {
                                Image(systemName: "chevron.right.circle.fill").foregroundColor(.blue).imageScale(.large)
                            }.buttonStyle(.borderless)
                        }
                    }
                    
                    Section(header: Text("Canastas & Bonuses")) {
                        TwoTeamScoreRow(title: "Pure", subtitle: "Canasta", count1: $draft.t1PureCanastas, count2: $draft.t2PureCanastas)
                        TwoTeamScoreRow(title: "Mixed", subtitle: "Canasta", count1: $draft.t1MixedCanastas, count2: $draft.t2MixedCanastas)
                        TwoTeamScoreRow(title: "Red 3s", subtitle: nil, count1: $draft.t1Red3s, count2: $draft.t2Red3s)
                        
                        HStack {
                            Text("Went Out").frame(width: 80, alignment: .leading)
                            Toggle("", isOn: $draft.t1WentOut).labelsHidden().frame(maxWidth: .infinity)
                            Toggle("", isOn: $draft.t2WentOut).labelsHidden().frame(maxWidth: .infinity)
                        }
                        HStack {
                            Text("Concealed").frame(width: 80, alignment: .leading)
                            Toggle("", isOn: $draft.t1WentOutConcealed).labelsHidden().frame(maxWidth: .infinity)
                            Toggle("", isOn: $draft.t2WentOutConcealed).labelsHidden().frame(maxWidth: .infinity)
                        }
                    }
                    
                    Section(header: Text("Melded Cards (Positive Points)"), footer: Text("Enter the total number of each card type melded on the table.")) {
                        TwoTeamScoreRow(title: "Jokers", subtitle: "\(game.jokerPts) pts/ea", count1: $draft.t1Jokers, count2: $draft.t2Jokers)
                        TwoTeamScoreRow(title: "Deuces (2s)", subtitle: "\(game.deucePts) pts/ea", count1: $draft.t1Deuces, count2: $draft.t2Deuces)
                        TwoTeamScoreRow(title: "Aces", subtitle: "\(game.acePts) pts/ea", count1: $draft.t1Aces, count2: $draft.t2Aces)
                        TwoTeamScoreRow(title: "8 thru King", subtitle: "\(game.highCardPts) pts/ea", count1: $draft.t1HighCards, count2: $draft.t2HighCards)
                        TwoTeamScoreRow(title: "4 thru 7", subtitle: "\(game.lowCardPts) pts/ea", count1: $draft.t1LowCards, count2: $draft.t2LowCards)
                        TwoTeamScoreRow(title: "Black 3s", subtitle: "\(game.black3Pts) pts/ea", count1: $draft.t1Black3s, count2: $draft.t2Black3s)
                    }
                    
                    Section(header: Text("Cards In Hand (Penalty)"), footer: Text("Points for these cards will be automatically subtracted from the total.")) {
                        TwoTeamScoreRow(title: "Jokers", subtitle: "-\(game.jokerPts) pts/ea", count1: $draft.t1JokersInHand, count2: $draft.t2JokersInHand)
                        TwoTeamScoreRow(title: "Deuces (2s)", subtitle: "-\(game.deucePts) pts/ea", count1: $draft.t1DeucesInHand, count2: $draft.t2DeucesInHand)
                        TwoTeamScoreRow(title: "Aces", subtitle: "-\(game.acePts) pts/ea", count1: $draft.t1AcesInHand, count2: $draft.t2AcesInHand)
                        TwoTeamScoreRow(title: "8 thru King", subtitle: "-\(game.highCardPts) pts/ea", count1: $draft.t1HighCardsInHand, count2: $draft.t2HighCardsInHand)
                        TwoTeamScoreRow(title: "4 thru 7", subtitle: "-\(game.lowCardPts) pts/ea", count1: $draft.t1LowCardsInHand, count2: $draft.t2LowCardsInHand)
                        TwoTeamScoreRow(title: "Black 3s", subtitle: "-\(game.black3Pts) pts/ea", count1: $draft.t1Black3sInHand, count2: $draft.t2Black3sInHand)
                    }
                    
                    Section(header: Text("Live Round Totals")) {
                        HStack {
                            Text("\(draft.team1Total(game: game))").bold().frame(maxWidth: .infinity)
                            Text("\(draft.team2Total(game: game))").bold().frame(maxWidth: .infinity)
                        }
                    }
                }
                .scrollDismissesKeyboard(.immediately) // Swiping drops keyboard
                .tag(0)
                
                // PAGE 2: Team 3
                if game.isThreeTeams {
                    Form {
                        HStack {
                            Button(action: { withAnimation { selectedTab = 0 } }) {
                                Image(systemName: "chevron.left.circle.fill").foregroundColor(.blue).imageScale(.large)
                            }.buttonStyle(.borderless)
                            Text(game.team3Name).bold().frame(maxWidth: .infinity)
                            Image(systemName: "chevron.right.circle.fill").opacity(0)
                        }
                        
                        Section(header: Text("Canastas & Bonuses")) {
                            OneTeamScoreRow(title: "Pure", subtitle: "Canasta", count: $draft.t3PureCanastas)
                            OneTeamScoreRow(title: "Mixed", subtitle: "Canasta", count: $draft.t3MixedCanastas)
                            OneTeamScoreRow(title: "Red 3s", subtitle: nil, count: $draft.t3Red3s)
                            
                            HStack {
                                Text("Went Out").frame(width: 80, alignment: .leading)
                                Spacer()
                                Toggle("", isOn: $draft.t3WentOut)
                            }
                            HStack {
                                Text("Concealed").frame(width: 80, alignment: .leading)
                                Spacer()
                                Toggle("", isOn: $draft.t3WentOutConcealed)
                            }
                        }
                        
                        Section(header: Text("Melded Cards (Positive Points)"), footer: Text("Enter the total number of each card type melded on the table.")) {
                            OneTeamScoreRow(title: "Jokers", subtitle: "\(game.jokerPts) pts/ea", count: $draft.t3Jokers)
                            OneTeamScoreRow(title: "Deuces (2s)", subtitle: "\(game.deucePts) pts/ea", count: $draft.t3Deuces)
                            OneTeamScoreRow(title: "Aces", subtitle: "\(game.acePts) pts/ea", count: $draft.t3Aces)
                            OneTeamScoreRow(title: "8 thru King", subtitle: "\(game.highCardPts) pts/ea", count: $draft.t3HighCards)
                            OneTeamScoreRow(title: "4 thru 7", subtitle: "\(game.lowCardPts) pts/ea", count: $draft.t3LowCards)
                            OneTeamScoreRow(title: "Black 3s", subtitle: "\(game.black3Pts) pts/ea", count: $draft.t3Black3s)
                        }
                        
                        Section(header: Text("Cards In Hand (Penalty)"), footer: Text("Points for these cards will be automatically subtracted from the total.")) {
                            OneTeamScoreRow(title: "Jokers", subtitle: "-\(game.jokerPts) pts/ea", count: $draft.t3JokersInHand)
                            OneTeamScoreRow(title: "Deuces (2s)", subtitle: "-\(game.deucePts) pts/ea", count: $draft.t3DeucesInHand)
                            OneTeamScoreRow(title: "Aces", subtitle: "-\(game.acePts) pts/ea", count: $draft.t3AcesInHand)
                            OneTeamScoreRow(title: "8 thru King", subtitle: "-\(game.highCardPts) pts/ea", count: $draft.t3HighCardsInHand)
                            OneTeamScoreRow(title: "4 thru 7", subtitle: "-\(game.lowCardPts) pts/ea", count: $draft.t3LowCardsInHand)
                            OneTeamScoreRow(title: "Black 3s", subtitle: "-\(game.black3Pts) pts/ea", count: $draft.t3Black3sInHand)
                        }
                        
                        Section(header: Text("Live Round Total")) {
                            HStack { Text("\(draft.team3Total(game: game))").bold().frame(maxWidth: .infinity) }
                        }
                    }
                    .scrollDismissesKeyboard(.immediately) // Swiping drops keyboard
                    .tag(1)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .navigationTitle(editingRound == nil ? "Record Round" : "Edit Round")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let round = editingRound {
                    draft.t1Red3s = round.t1Red3s; draft.t1MixedCanastas = round.t1MixedCanastas; draft.t1PureCanastas = round.t1PureCanastas; draft.t1WentOut = round.t1WentOut; draft.t1WentOutConcealed = round.t1WentOutConcealed
                    draft.t2Red3s = round.t2Red3s; draft.t2MixedCanastas = round.t2MixedCanastas; draft.t2PureCanastas = round.t2PureCanastas; draft.t2WentOut = round.t2WentOut; draft.t2WentOutConcealed = round.t2WentOutConcealed
                    draft.t3Red3s = round.t3Red3s; draft.t3MixedCanastas = round.t3MixedCanastas; draft.t3PureCanastas = round.t3PureCanastas; draft.t3WentOut = round.t3WentOut; draft.t3WentOutConcealed = round.t3WentOutConcealed
                    
                    draft.t1Jokers = round.t1Jokers; draft.t1Deuces = round.t1Deuces; draft.t1Aces = round.t1Aces; draft.t1HighCards = round.t1HighCards; draft.t1LowCards = round.t1LowCards; draft.t1Black3s = round.t1Black3s
                    draft.t2Jokers = round.t2Jokers; draft.t2Deuces = round.t2Deuces; draft.t2Aces = round.t2Aces; draft.t2HighCards = round.t2HighCards; draft.t2LowCards = round.t2LowCards; draft.t2Black3s = round.t2Black3s
                    draft.t3Jokers = round.t3Jokers; draft.t3Deuces = round.t3Deuces; draft.t3Aces = round.t3Aces; draft.t3HighCards = round.t3HighCards; draft.t3LowCards = round.t3LowCards; draft.t3Black3s = round.t3Black3s
                    
                    draft.t1JokersInHand = round.t1JokersInHand; draft.t1DeucesInHand = round.t1DeucesInHand; draft.t1AcesInHand = round.t1AcesInHand; draft.t1HighCardsInHand = round.t1HighCardsInHand; draft.t1LowCardsInHand = round.t1LowCardsInHand; draft.t1Black3sInHand = round.t1Black3sInHand
                    draft.t2JokersInHand = round.t2JokersInHand; draft.t2DeucesInHand = round.t2DeucesInHand; draft.t2AcesInHand = round.t2AcesInHand; draft.t2HighCardsInHand = round.t2HighCardsInHand; draft.t2LowCardsInHand = round.t2LowCardsInHand; draft.t2Black3sInHand = round.t2Black3sInHand
                    draft.t3JokersInHand = round.t3JokersInHand; draft.t3DeucesInHand = round.t3DeucesInHand; draft.t3AcesInHand = round.t3AcesInHand; draft.t3HighCardsInHand = round.t3HighCardsInHand; draft.t3LowCardsInHand = round.t3LowCardsInHand; draft.t3Black3sInHand = round.t3Black3sInHand
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingRound == nil ? "Submit" : "Save") { saveRound() }
                }
                // Global "Done" button for the keyboard
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
        // This prevents swipe-to-dismiss and enables the minimized bottom view!
        .presentationDetents([.height(100), .large], selection: $currentDetent)
        .presentationBackgroundInteraction(.enabled(upThrough: .height(100)))
        .interactiveDismissDisabled()
    }
}

// MARK: - Custom Input Component (Handles Auto-Clear and Stepper Conflict)
struct HybridStepper: View {
    @Binding var value: Int
    @State private var text: String = "0"
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            TextField("0", text: $text)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)
                .multilineTextAlignment(.center)
                .focused($isFocused)
                .onChange(of: isFocused) { oldValue, newValue in
                    if newValue {
                        text = "" // Auto-clear text when box is clicked
                    } else if text.isEmpty {
                        text = "\(value)" // Restore zero if they click away empty
                    }
                }
                .onChange(of: text) { oldValue, newValue in
                    if let intVal = Int(newValue) {
                        value = intVal
                    } else if newValue.isEmpty {
                        value = 0
                    }
                }
                .onChange(of: value) { oldValue, newValue in
                    // If Stepper is pressed while user is typing in the box
                    if isFocused {
                        if Int(text) != newValue {
                            isFocused = false // Drop the keyboard immediately
                            text = "\(newValue)"
                        }
                    } else {
                        text = "\(newValue)"
                    }
                }
                .onAppear {
                    text = "\(value)"
                }
            
            Stepper("", value: $value, in: 0...999)
                .labelsHidden()
        }
    }
}

// MARK: - Reusable Stepper Row for Teams 1 & 2
struct TwoTeamScoreRow: View {
    let title: String
    let subtitle: String?
    @Binding var count1: Int
    @Binding var count2: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).fontWeight(.semibold)
                if let sub = subtitle { Text(sub).font(.caption).foregroundColor(.secondary) }
                Spacer()
            }
            HStack {
                Text("T1:").font(.caption).foregroundColor(.secondary)
                HybridStepper(value: $count1)
                
                Spacer()
                
                Text("T2:").font(.caption).foregroundColor(.secondary)
                HybridStepper(value: $count2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Reusable Stepper Row for Team 3
struct OneTeamScoreRow: View {
    let title: String
    let subtitle: String?
    @Binding var count: Int
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).fontWeight(.semibold)
                if let sub = subtitle { Text(sub).font(.caption).foregroundColor(.secondary) }
            }
            Spacer()
            HybridStepper(value: $count)
        }
        .padding(.vertical, 4)
    }
}

struct CustomRuleInputRow: View {
    let title: String
    @Binding var value: String
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: $value)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }
}

struct RuleRow: View {
    let title: String
    let points: Int
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(points)").bold()
        }
    }
}

struct RuleSection: View {
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3).fontWeight(.bold)
            Text(content).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 6. Rules Callouts
struct RuleDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var rules: RuleSet
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Game Condition")) { HStack { Text("Winning Score"); Spacer(); Text("\(rules.targetScore)").bold() } }
                Section(header: Text("Melds & Bonuses")) {
                    RuleRow(title: "Pure Canasta", points: rules.purePts); RuleRow(title: "Mixed Canasta", points: rules.mixedPts)
                    RuleRow(title: "Red 3", points: rules.red3Pts); RuleRow(title: "Going Out", points: rules.outPts)
                }
                Section(header: Text("Card Values")) {
                    RuleRow(title: "Jokers", points: rules.jokerPts); RuleRow(title: "Deuces (2s) & Aces", points: rules.deucePts)
                    RuleRow(title: "8 through King", points: rules.highCardPts); RuleRow(title: "4 through 7", points: rules.lowCardPts)
                    RuleRow(title: "Black 3s", points: rules.black3Pts)
                }
            }
            .navigationTitle("\(rules.name) Rules").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 7. How to Play
struct HowToPlaySheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    RuleSection(title: "The Objective", content: "Be the first team to reach the target score by melding cards and forming Canastas (melds of 7 or more cards).")
                    RuleSection(title: "The Deal", content: "Played with 2 to 6 players. Uses two standard decks including 4 Jokers (108 cards total).\n\nCards Dealt:\n• 2 Players: 15 cards each\n• 3 Players: 13 cards each\n• 4 Players: 11 cards each\n• 6 Players: 11 cards each (requires a 3rd deck)")
                    RuleSection(title: "A Turn", content: "1. Draw one card from the stock OR take the entire discard pile.\n2. Meld cards to the table (optional).\n3. Discard one card to end your turn.")
                    RuleSection(title: "Melding", content: "• A meld is 3 or more cards of the same rank.\n• Sequences (e.g., 4-5-6) are not allowed.\n• A meld must have at least two natural cards and can have up to three wild cards.")
                    RuleSection(title: "Canastas", content: "A Canasta is a meld of 7 or more cards.\n• Pure (Natural): Contains no wild cards.\n• Mixed: Contains 1 to 3 wild cards.")
                    RuleSection(title: "Special Cards", content: "• Red 3s: Place face up immediately and draw a replacement. Worth bonus points.\n• Black 3s: Can only be melded when going out. Discarding one prevents the next player from taking the pile.\n• Wild Cards (Jokers & 2s): Can be used in melds. Discarding one 'freezes' the pile.")
                    RuleSection(title: "Taking the Discard Pile", content: "You can only take the pile if you can immediately use its top card in a meld. If the pile is 'frozen' (contains a wild card or a red 3), you must have two natural matching cards in your hand to take it.")
                    RuleSection(title: "Going Out", content: "A player 'goes out' by playing or discarding their last card. You cannot go out unless your team has completed at least one Canasta.")
                    RuleSection(title: "Going Out Concealed", content: "A player plays their entire hand in a single turn without having made any prior melds. Neither the player nor their partner can have put down any melds prior to this turn (other than red threes). The meld must include at least one complete canasta. You can go out with or without a final discard.")
                }
                .padding()
            }
            .navigationTitle("How to Play").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
