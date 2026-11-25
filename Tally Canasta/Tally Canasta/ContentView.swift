import SwiftUI
import SwiftData
import UIKit
import TallyCore

private enum CanastaViewMath {
    nonisolated static let maxMagnitude = 999_999_999
    nonisolated static let maxCount = 999

    nonisolated static func clamp(_ value: Int) -> Int {
        min(max(value, -maxMagnitude), maxMagnitude)
    }

    nonisolated static func clampCount(_ value: Int) -> Int {
        min(max(value, 0), maxCount)
    }

    nonisolated static func parseCount(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Int(trimmed) else { return nil }
        return clampCount(parsed)
    }

    nonisolated static func parsePositiveInt(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Int(trimmed), parsed > 0 else { return nil }
        return min(parsed, maxMagnitude)
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

@MainActor
private func dismissCanastaKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

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
                if games.isEmpty {
                    ContentUnavailableView(
                        "No Canasta Games Yet",
                        systemImage: "suit.club.fill",
                        description: Text("Tap + to start a new game and track rounds, melds, and canastas.")
                    )
                } else {
                    List {
                        ForEach(games) { game in
                            NavigationLink(destination: GameLedgerView(game: game)) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(
                                            game.isThreeTeams
                                                ? "\(game.team1Name) vs \(game.team2Name) vs \(game.team3Name)"
                                                : "\(game.team1Name) vs \(game.team2Name)"
                                        )
                                        .font(.headline)
                                        .lineLimit(1)
                                        Text("Target: \(game.targetScore)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(
                                        game.isThreeTeams
                                            ? "\(game.team1Total) / \(game.team2Total) / \(game.team3Total)"
                                            : "\(game.team1Total) / \(game.team2Total)"
                                    )
                                    .font(.system(.title3, design: .rounded).weight(.bold))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .foregroundStyle(.primary)
                                }
                            }
                        }
                        .onDelete(perform: deleteGames)
                    }
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
                    .foregroundStyle(.blue)
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
        let snapshot = games
        let toDelete = offsets.compactMap { snapshot.indices.contains($0) ? snapshot[$0] : nil }
        for game in toDelete {
            modelContext.delete(game)
        }
        try? modelContext.save()
    }
}

// MARK: - 2. New Game Setup
struct NewGameSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \RuleSet.name) private var ruleSets: [RuleSet]
    @Query(sort: \TallyPlayer.name) private var players: [TallyPlayer]

    @State private var selectedRuleSetID: PersistentIdentifier?
    @State private var showingCustomRuleSheet = false
    @State private var showingRuleDetails = false

    @State private var team1 = "Team 1"
    @State private var team2 = "Team 2"
    @State private var team3 = ""
    @State private var customWinningScore = "5000"

    private var selectedRuleSet: RuleSet? {
        if let id = selectedRuleSetID,
           let matched = ruleSets.first(where: { $0.persistentModelID == id }) {
            return matched
        }
        return ruleSets.first
    }

    private var canStartGame: Bool {
        let t1 = team1.trimmingCharacters(in: .whitespacesAndNewlines)
        let t2 = team2.trimmingCharacters(in: .whitespacesAndNewlines)
        return selectedRuleSet != nil && !t1.isEmpty && !t2.isEmpty
    }

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
                            } label: {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }

                    HStack {
                        TextField("Team 2 Name", text: $team2)
                        if !players.isEmpty {
                            Menu {
                                ForEach(players) { player in
                                    Button(player.name) { team2 = player.name }
                                }
                            } label: {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }

                    HStack {
                        TextField("Team 3 Name (Optional)", text: $team3)
                        if !players.isEmpty {
                            Menu {
                                ForEach(players) { player in
                                    Button(player.name) { team3 = player.name }
                                }
                            } label: {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }

                Section("Scoring Rules") {
                    if !ruleSets.isEmpty {
                        Picker("Ruleset", selection: $selectedRuleSetID) {
                            ForEach(ruleSets) { rules in
                                Text(rules.name).tag(Optional(rules.persistentModelID))
                            }
                        }
                        .onChange(of: selectedRuleSetID) { _, newID in
                            if let matchedRule = ruleSets.first(where: { $0.persistentModelID == newID }) {
                                customWinningScore = String(matchedRule.targetScore)
                            }
                        }

                        if let rules = selectedRuleSet {
                            Button(action: { showingRuleDetails = true }) {
                                HStack {
                                    Text("View \(rules.name) Details")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "info.circle")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    } else {
                        Text("Loading defaults...")
                            .foregroundStyle(.secondary)
                    }

                    Button("Create Custom Rule Set...") { showingCustomRuleSheet = true }
                }

                Section(
                    header: Text("Winning Score"),
                    footer: Text("Enter a positive target score (e.g., 5000). Adjusting this only affects this game.")
                ) {
                    TextField("Winning Score", text: $customWinningScore)
                        .keyboardType(.numberPad)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Game")
            .onAppear(perform: seedAndSyncRules)
            .onChange(of: ruleSets.count) { _, _ in
                syncSelectedRuleSetIfNeeded()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start", action: startGame)
                        .disabled(!canStartGame)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissCanastaKeyboard() }
                }
            }
            .sheet(isPresented: $showingCustomRuleSheet) {
                CustomRuleSheet(selectedRuleSetID: $selectedRuleSetID) { createdRules in
                    customWinningScore = String(createdRules.targetScore)
                }
            }
            .sheet(isPresented: $showingRuleDetails) {
                if let rules = selectedRuleSet {
                    RuleDetailsSheet(rules: rules)
                }
            }
        }
    }

    private func seedAndSyncRules() {
        if ruleSets.isEmpty {
            let classic = RuleSet(name: "Classic", targetScore: 5000, isBuiltIn: true)
            let modern = RuleSet(name: "Modern American", targetScore: 8500, isBuiltIn: true)
            modelContext.insert(classic)
            modelContext.insert(modern)
            try? modelContext.save()
            selectedRuleSetID = classic.persistentModelID
            customWinningScore = "5000"
        } else {
            syncSelectedRuleSetIfNeeded()
        }
    }

    private func syncSelectedRuleSetIfNeeded() {
        if let currentID = selectedRuleSetID,
           let current = ruleSets.first(where: { $0.persistentModelID == currentID }) {
            if customWinningScore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                customWinningScore = String(current.targetScore)
            }
            return
        }
        if let first = ruleSets.first {
            selectedRuleSetID = first.persistentModelID
            customWinningScore = String(first.targetScore)
        }
    }

    private func startGame() {
        guard let rules = selectedRuleSet else { return }
        let t1 = team1.trimmingCharacters(in: .whitespacesAndNewlines)
        let t2 = team2.trimmingCharacters(in: .whitespacesAndNewlines)
        let t3 = team3.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t1.isEmpty, !t2.isEmpty else { return }

        let newGame = CanastaGame(team1Name: t1, team2Name: t2, team3Name: t3, rules: rules)
        newGame.targetScore = CanastaViewMath.parsePositiveInt(customWinningScore) ?? max(1, rules.targetScore)
        modelContext.insert(newGame)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - 3. Custom Rule Creator
struct CustomRuleSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedRuleSetID: PersistentIdentifier?
    var onCreated: (RuleSet) -> Void = { _ in }

    @State private var name = ""
    @State private var target = "5000"
    @State private var red3 = "100"
    @State private var mixed = "300"
    @State private var pure = "500"
    @State private var out = "100"
    @State private var outConcealed = "200"
    @State private var joker = "50"
    @State private var deuce = "20"
    @State private var high = "10"
    @State private var low = "5"
    @State private var black3 = "5"

    private func saveRules() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = trimmedName.isEmpty ? "Custom" : trimmedName
        let parsedDeuce = CanastaViewMath.parseCount(deuce) ?? 20

        let newRules = RuleSet(
            name: safeName,
            targetScore: CanastaViewMath.parsePositiveInt(target) ?? 5000,
            red3Pts: CanastaViewMath.parseCount(red3) ?? 100,
            mixedPts: CanastaViewMath.parseCount(mixed) ?? 300,
            purePts: CanastaViewMath.parseCount(pure) ?? 500,
            outPts: CanastaViewMath.parseCount(out) ?? 100,
            outConcealedPts: CanastaViewMath.parseCount(outConcealed) ?? 200,
            jokerPts: CanastaViewMath.parseCount(joker) ?? 50,
            deucePts: parsedDeuce,
            acePts: parsedDeuce,
            highCardPts: CanastaViewMath.parseCount(high) ?? 10,
            lowCardPts: CanastaViewMath.parseCount(low) ?? 5,
            black3Pts: CanastaViewMath.parseCount(black3) ?? 5,
            isBuiltIn: false
        )
        modelContext.insert(newRules)
        try? modelContext.save()
        selectedRuleSetID = newRules.persistentModelID
        onCreated(newRules)
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
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Custom Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveRules() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissCanastaKeyboard() }
                }
            }
        }
    }
}

// MARK: - 4. The Ledger
struct GameLedgerView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var game: CanastaGame
    @State private var showingNewRoundEntry = false
    @State private var roundToEdit: Round?

    private func openingMeld(for score: Int) -> Int {
        if score < 0 { return 15 }
        if score < 1500 { return 50 }
        if score < 3000 { return 90 }
        return 120
    }

    private var roundsDescending: [Round] {
        game.sortedRounds.reversed()
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if let winner = game.winner {
                    Text("🎉 \(winner) WINS! 🎉")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green)
                }

                HStack(spacing: 0) {
                    TeamHeaderView(
                        name: game.team1Name,
                        total: game.team1Total,
                        meldReq: openingMeld(for: game.team1Total),
                        color: .blue
                    )
                    Divider().frame(height: 80)
                    TeamHeaderView(
                        name: game.team2Name,
                        total: game.team2Total,
                        meldReq: openingMeld(for: game.team2Total),
                        color: .red
                    )

                    if game.isThreeTeams {
                        Divider().frame(height: 80)
                        TeamHeaderView(
                            name: game.team3Name,
                            total: game.team3Total,
                            meldReq: openingMeld(for: game.team3Total),
                            color: .green
                        )
                    }
                }
                Divider()
            }

            List {
                ForEach(roundsDescending) { round in
                    Button(action: { roundToEdit = round }) {
                        HStack {
                            Text("R\(round.roundNumber)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .leading)

                            Text(round.team1RoundTotal >= 0 ? "+\(round.team1RoundTotal)" : "\(round.team1RoundTotal)")
                                .font(.system(.body, design: .rounded).weight(.bold))
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, alignment: .center)

                            Text(round.team2RoundTotal >= 0 ? "+\(round.team2RoundTotal)" : "\(round.team2RoundTotal)")
                                .font(.system(.body, design: .rounded).weight(.bold))
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, alignment: .center)

                            if game.isThreeTeams {
                                Text(round.team3RoundTotal >= 0 ? "+\(round.team3RoundTotal)" : "\(round.team3RoundTotal)")
                                    .font(.system(.body, design: .rounded).weight(.bold))
                                    .monospacedDigit()
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete(perform: deleteRounds)
            }

            let gameFinished = game.winner != nil
            Button(action: { showingNewRoundEntry = true }) {
                Text(gameFinished ? "Game Complete" : "Record Round")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(gameFinished ? Color.secondary.opacity(0.35) : Color.blue)
                    .foregroundStyle(gameFinished ? Color.secondary : Color.white)
                    .cornerRadius(10)
            }
            .padding()
            .disabled(gameFinished)
        }
        .navigationTitle("Scoreboard")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingNewRoundEntry) { RoundEntrySheet(game: game, editingRound: nil) }
        .sheet(item: $roundToEdit) { round in RoundEntrySheet(game: game, editingRound: round) }
    }

    private func deleteRounds(offsets: IndexSet) {
        let snapshot = roundsDescending
        let toDelete = offsets.compactMap { snapshot.indices.contains($0) ? snapshot[$0] : nil }
        for round in toDelete {
            game.rounds.removeAll(where: { $0.persistentModelID == round.persistentModelID })
            modelContext.delete(round)
        }
        let remaining = game.sortedRounds
        for (index, round) in remaining.enumerated() {
            round.roundNumber = index + 1
        }
        try? modelContext.save()
    }
}

struct TeamHeaderView: View {
    let name: String
    let total: Int
    let meldReq: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(name)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text("\(total)")
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text("Meld req: \(meldReq)")
                .font(.caption2)
                .fontWeight(.medium)
                .monospacedDigit()
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(color.opacity(0.15))
                .foregroundStyle(color)
                .cornerRadius(6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
        .padding(.vertical)
        .background(color.opacity(0.04))
    }
}

// MARK: - Temporary Form State
private struct DraftRoundData {
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
        computeTotal(
            game: game,
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

    func team2Total(game: CanastaGame) -> Int {
        computeTotal(
            game: game,
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

    func team3Total(game: CanastaGame) -> Int {
        computeTotal(
            game: game,
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

    private func computeTotal(
        game: CanastaGame,
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
        let red3Base = CanastaViewMath.multiply(red3s, game.red3Pts)
        let red3Score = abs(red3s) >= 4 ? CanastaViewMath.multiply(red3Base, 2) : red3Base
        let goingOutBonus = wentOutConcealed ? game.outConcealedPts : (wentOut ? game.outPts : 0)

        let base = [
            red3Score,
            CanastaViewMath.multiply(mixedCanastas, game.mixedPts),
            CanastaViewMath.multiply(pureCanastas, game.purePts),
            goingOutBonus
        ].reduce(0, CanastaViewMath.add)

        let cards = [
            CanastaViewMath.multiply(jokers, game.jokerPts),
            CanastaViewMath.multiply(deuces, game.deucePts),
            CanastaViewMath.multiply(aces, game.acePts),
            CanastaViewMath.multiply(highCards, game.highCardPts),
            CanastaViewMath.multiply(lowCards, game.lowCardPts),
            CanastaViewMath.multiply(black3s, game.black3Pts)
        ].reduce(0, CanastaViewMath.add)

        let penalty = [
            CanastaViewMath.multiply(jokersInHand, game.jokerPts),
            CanastaViewMath.multiply(deucesInHand, game.deucePts),
            CanastaViewMath.multiply(acesInHand, game.acePts),
            CanastaViewMath.multiply(highCardsInHand, game.highCardPts),
            CanastaViewMath.multiply(lowCardsInHand, game.lowCardPts),
            CanastaViewMath.multiply(black3sInHand, game.black3Pts)
        ].reduce(0, CanastaViewMath.add)

        let gross = CanastaViewMath.add(base, cards)
        return CanastaViewMath.subtract(gross, penalty)
    }
}

// MARK: - 5. Round Entry Form (Sliding Pages)
struct RoundEntrySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    var game: CanastaGame
    var editingRound: Round?

    @State private var didInitializeDraft = false
    @State private var draft = DraftRoundData()
    @State private var selectedTab = 0
    @State private var currentDetent: PresentationDetent = .large

    private func applyDraft(_ draft: DraftRoundData, to round: Round) {
        round.t1Red3s = draft.t1Red3s; round.t1MixedCanastas = draft.t1MixedCanastas; round.t1PureCanastas = draft.t1PureCanastas
        round.t1WentOutConcealed = draft.t1WentOutConcealed; round.t1WentOut = draft.t1WentOutConcealed ? false : draft.t1WentOut

        round.t2Red3s = draft.t2Red3s; round.t2MixedCanastas = draft.t2MixedCanastas; round.t2PureCanastas = draft.t2PureCanastas
        round.t2WentOutConcealed = draft.t2WentOutConcealed; round.t2WentOut = draft.t2WentOutConcealed ? false : draft.t2WentOut

        round.t3Red3s = draft.t3Red3s; round.t3MixedCanastas = draft.t3MixedCanastas; round.t3PureCanastas = draft.t3PureCanastas
        round.t3WentOutConcealed = draft.t3WentOutConcealed; round.t3WentOut = draft.t3WentOutConcealed ? false : draft.t3WentOut

        round.t1Jokers = draft.t1Jokers; round.t1Deuces = draft.t1Deuces; round.t1Aces = draft.t1Aces; round.t1HighCards = draft.t1HighCards; round.t1LowCards = draft.t1LowCards; round.t1Black3s = draft.t1Black3s
        round.t2Jokers = draft.t2Jokers; round.t2Deuces = draft.t2Deuces; round.t2Aces = draft.t2Aces; round.t2HighCards = draft.t2HighCards; round.t2LowCards = draft.t2LowCards; round.t2Black3s = draft.t2Black3s
        round.t3Jokers = draft.t3Jokers; round.t3Deuces = draft.t3Deuces; round.t3Aces = draft.t3Aces; round.t3HighCards = draft.t3HighCards; round.t3LowCards = draft.t3LowCards; round.t3Black3s = draft.t3Black3s

        round.t1JokersInHand = draft.t1JokersInHand; round.t1DeucesInHand = draft.t1DeucesInHand; round.t1AcesInHand = draft.t1AcesInHand; round.t1HighCardsInHand = draft.t1HighCardsInHand; round.t1LowCardsInHand = draft.t1LowCardsInHand; round.t1Black3sInHand = draft.t1Black3sInHand
        round.t2JokersInHand = draft.t2JokersInHand; round.t2DeucesInHand = draft.t2DeucesInHand; round.t2AcesInHand = draft.t2AcesInHand; round.t2HighCardsInHand = draft.t2HighCardsInHand; round.t2LowCardsInHand = draft.t2LowCardsInHand; round.t2Black3sInHand = draft.t2Black3sInHand
        round.t3JokersInHand = draft.t3JokersInHand; round.t3DeucesInHand = draft.t3DeucesInHand; round.t3AcesInHand = draft.t3AcesInHand; round.t3HighCardsInHand = draft.t3HighCardsInHand; round.t3LowCardsInHand = draft.t3LowCardsInHand; round.t3Black3sInHand = draft.t3Black3sInHand
    }

    private func saveRound() {
        if let round = editingRound {
            applyDraft(draft, to: round)
        } else {
            let nextRoundNumber = (game.rounds.map(\.roundNumber).max() ?? 0) + 1
            let newRound = Round(roundNumber: nextRoundNumber)
            applyDraft(draft, to: newRound)
            newRound.game = game
            modelContext.insert(newRound)
            game.rounds.append(newRound)
        }
        try? modelContext.save()
        dismiss()
    }

    private func goingOutBindings(wentOut: Binding<Bool>, concealed: Binding<Bool>) -> (out: Binding<Bool>, concealed: Binding<Bool>) {
        let outBinding = Binding<Bool>(
            get: { wentOut.wrappedValue },
            set: { newValue in
                wentOut.wrappedValue = newValue
                if newValue {
                    concealed.wrappedValue = false
                }
            }
        )
        let concealedBinding = Binding<Bool>(
            get: { concealed.wrappedValue },
            set: { newValue in
                concealed.wrappedValue = newValue
                if newValue {
                    wentOut.wrappedValue = false
                }
            }
        )
        return (outBinding, concealedBinding)
    }

    var body: some View {
        let t1Out = goingOutBindings(wentOut: $draft.t1WentOut, concealed: $draft.t1WentOutConcealed)
        let t2Out = goingOutBindings(wentOut: $draft.t2WentOut, concealed: $draft.t2WentOutConcealed)
        let t3Out = goingOutBindings(wentOut: $draft.t3WentOut, concealed: $draft.t3WentOutConcealed)

        NavigationStack {
            TabView(selection: $selectedTab) {
                // PAGE 1: Teams 1 & 2
                Form {
                    HStack {
                        if game.isThreeTeams { Image(systemName: "chevron.left.circle.fill").opacity(0) }
                        Text(game.team1Name).bold().lineLimit(1).frame(maxWidth: .infinity)
                        Text(game.team2Name).bold().lineLimit(1).frame(maxWidth: .infinity)
                        if game.isThreeTeams {
                            Button(action: { withAnimation { selectedTab = 1 } }) {
                                Image(systemName: "chevron.right.circle.fill").foregroundStyle(.blue).imageScale(.large)
                            }.buttonStyle(.borderless)
                        }
                    }

                    Section(
                        header: Text("Canastas & Bonuses"),
                        footer: Text("Going Out and Concealed are mutually exclusive; Concealed replaces the standard going-out bonus. 4 Red 3s double.")
                    ) {
                        TwoTeamScoreRow(title: "Pure", subtitle: "Canasta", count1: $draft.t1PureCanastas, count2: $draft.t2PureCanastas)
                        TwoTeamScoreRow(title: "Mixed", subtitle: "Canasta", count1: $draft.t1MixedCanastas, count2: $draft.t2MixedCanastas)
                        TwoTeamScoreRow(title: "Red 3s", subtitle: "2x at 4+", count1: $draft.t1Red3s, count2: $draft.t2Red3s)

                        HStack {
                            Text("Went Out").frame(width: 84, alignment: .leading)
                            Toggle("", isOn: t1Out.out).labelsHidden().frame(maxWidth: .infinity)
                            Toggle("", isOn: t2Out.out).labelsHidden().frame(maxWidth: .infinity)
                        }
                        HStack {
                            Text("Concealed").frame(width: 84, alignment: .leading)
                            Toggle("", isOn: t1Out.concealed).labelsHidden().frame(maxWidth: .infinity)
                            Toggle("", isOn: t2Out.concealed).labelsHidden().frame(maxWidth: .infinity)
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
                            Text("\(draft.team1Total(game: game))").bold().monospacedDigit().frame(maxWidth: .infinity)
                            Text("\(draft.team2Total(game: game))").bold().monospacedDigit().frame(maxWidth: .infinity)
                        }
                    }
                }
                .scrollDismissesKeyboard(.immediately)
                .tag(0)

                // PAGE 2: Team 3
                if game.isThreeTeams {
                    Form {
                        HStack {
                            Button(action: { withAnimation { selectedTab = 0 } }) {
                                Image(systemName: "chevron.left.circle.fill").foregroundStyle(.blue).imageScale(.large)
                            }.buttonStyle(.borderless)
                            Text(game.team3Name).bold().lineLimit(1).frame(maxWidth: .infinity)
                            Image(systemName: "chevron.right.circle.fill").opacity(0)
                        }

                        Section(
                            header: Text("Canastas & Bonuses"),
                            footer: Text("Going Out and Concealed are mutually exclusive; Concealed replaces the standard going-out bonus. 4 Red 3s double.")
                        ) {
                            OneTeamScoreRow(title: "Pure", subtitle: "Canasta", count: $draft.t3PureCanastas)
                            OneTeamScoreRow(title: "Mixed", subtitle: "Canasta", count: $draft.t3MixedCanastas)
                            OneTeamScoreRow(title: "Red 3s", subtitle: "2x at 4+", count: $draft.t3Red3s)

                            HStack {
                                Text("Went Out").frame(width: 84, alignment: .leading)
                                Spacer()
                                Toggle("", isOn: t3Out.out).labelsHidden()
                            }
                            HStack {
                                Text("Concealed").frame(width: 84, alignment: .leading)
                                Spacer()
                                Toggle("", isOn: t3Out.concealed).labelsHidden()
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
                            HStack { Text("\(draft.team3Total(game: game))").bold().monospacedDigit().frame(maxWidth: .infinity) }
                        }
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .tag(1)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .navigationTitle(editingRound == nil ? "Record Round" : "Edit Round")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !didInitializeDraft else { return }
                didInitializeDraft = true
                if let round = editingRound {
                    draft.t1Red3s = round.t1Red3s; draft.t1MixedCanastas = round.t1MixedCanastas; draft.t1PureCanastas = round.t1PureCanastas
                    draft.t1WentOutConcealed = round.t1WentOutConcealed; draft.t1WentOut = round.t1WentOutConcealed ? false : round.t1WentOut

                    draft.t2Red3s = round.t2Red3s; draft.t2MixedCanastas = round.t2MixedCanastas; draft.t2PureCanastas = round.t2PureCanastas
                    draft.t2WentOutConcealed = round.t2WentOutConcealed; draft.t2WentOut = round.t2WentOutConcealed ? false : round.t2WentOut

                    draft.t3Red3s = round.t3Red3s; draft.t3MixedCanastas = round.t3MixedCanastas; draft.t3PureCanastas = round.t3PureCanastas
                    draft.t3WentOutConcealed = round.t3WentOutConcealed; draft.t3WentOut = round.t3WentOutConcealed ? false : round.t3WentOut

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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissCanastaKeyboard() }
                }
            }
        }
        .presentationDetents([.height(100), .large], selection: $currentDetent)
        .presentationBackgroundInteraction(.enabled(upThrough: .height(100)))
        .interactiveDismissDisabled()
    }
}

// MARK: - Custom Input Component (Handles Clamped Input and Stepper Sync)
private struct HybridStepper: View {
    @Binding var value: Int
    @State private var text: String = "0"
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField("0", text: $text)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 54)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in
                    if !focused {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            text = "\(value)"
                        } else if let parsed = CanastaViewMath.parseCount(trimmed) {
                            value = parsed
                            text = "\(parsed)"
                        } else {
                            text = "\(value)"
                        }
                    }
                }
                .onChange(of: text) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        return
                    }
                    if let parsed = CanastaViewMath.parseCount(trimmed) {
                        if value != parsed {
                            value = parsed
                        }
                        if newValue != "\(parsed)" {
                            text = "\(parsed)"
                        }
                    }
                }
                .onChange(of: value) { _, newValue in
                    let clamped = CanastaViewMath.clampCount(newValue)
                    if clamped != newValue {
                        value = clamped
                        return
                    }
                    if isFocused {
                        isFocused = false
                    }
                    if text != "\(clamped)" {
                        text = "\(clamped)"
                    }
                }
                .onAppear {
                    let clamped = CanastaViewMath.clampCount(value)
                    value = clamped
                    text = "\(clamped)"
                }

            Stepper("", value: $value, in: 0...CanastaViewMath.maxCount)
                .labelsHidden()
        }
    }
}

// MARK: - Reusable Stepper Row for Teams 1 & 2
private struct TwoTeamScoreRow: View {
    let title: String
    let subtitle: String?
    @Binding var count1: Int
    @Binding var count2: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).fontWeight(.semibold)
                if let sub = subtitle { Text(sub).font(.caption).foregroundStyle(.secondary) }
                Spacer()
            }

            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("T1:").font(.caption).foregroundStyle(.secondary)
                    HybridStepper(value: $count1)
                    Spacer()
                    Text("T2:").font(.caption).foregroundStyle(.secondary)
                    HybridStepper(value: $count2)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("T1:").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        HybridStepper(value: $count1)
                    }
                    HStack {
                        Text("T2:").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        HybridStepper(value: $count2)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Reusable Stepper Row for Team 3
private struct OneTeamScoreRow: View {
    let title: String
    let subtitle: String?
    @Binding var count: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).fontWeight(.semibold)
                if let sub = subtitle { Text(sub).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            HybridStepper(value: $count)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 6. Rules Callouts
private struct RuleDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var rules: RuleSet

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Game Condition")) {
                    RuleRow(title: "Winning Score", points: rules.targetScore)
                }
                Section(header: Text("Melds & Bonuses"), footer: Text("4 Red 3s double automatically. Concealed going out replaces the standard going-out bonus.")) {
                    RuleRow(title: "Pure Canasta", points: rules.purePts)
                    RuleRow(title: "Mixed Canasta", points: rules.mixedPts)
                    RuleRow(title: "Red 3", points: rules.red3Pts)
                    RuleRow(title: "Going Out", points: rules.outPts)
                    RuleRow(title: "Going Out Concealed", points: rules.outConcealedPts)
                }
                Section(header: Text("Card Values")) {
                    RuleRow(title: "Jokers", points: rules.jokerPts)
                    RuleRow(title: "Deuces (2s) & Aces", points: rules.deucePts)
                    RuleRow(title: "8 through King", points: rules.highCardPts)
                    RuleRow(title: "4 through 7", points: rules.lowCardPts)
                    RuleRow(title: "Black 3s", points: rules.black3Pts)
                }
            }
            .navigationTitle("\(rules.name) Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 7. How to Play
private struct HowToPlaySheet: View {
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
            .navigationTitle("How to Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
