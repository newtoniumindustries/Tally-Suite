import Foundation
import SwiftUI
import SwiftData
import UIKit

private enum ScoreMath {
    nonisolated static let maxMagnitude = 999_999_999

    nonisolated static func clamp(_ value: Int) -> Int {
        min(max(value, -maxMagnitude), maxMagnitude)
    }

    nonisolated static func parseInt(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return clamp(value)
    }

    nonisolated static func parsePositiveInt(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
            return nil
        }
        return min(value, maxMagnitude)
    }

    nonisolated static func add(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        if overflow {
            return rhs > 0 ? maxMagnitude : -maxMagnitude
        }
        return clamp(sum)
    }

    nonisolated static func subtract(_ lhs: Int, _ rhs: Int) -> Int {
        let (diff, overflow) = lhs.subtractingReportingOverflow(rhs)
        if overflow {
            return rhs > 0 ? -maxMagnitude : maxMagnitude
        }
        return clamp(diff)
    }
}

@MainActor
private func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Play", systemImage: "sportscourt.fill") {
                ActiveMatchesView()
            }
            Tab("Standings", systemImage: "trophy.fill") {
                StandingsView()
            }
            Tab("Setup", systemImage: "slider.horizontal.3") {
                SetupView()
            }
        }
    }
}

// MARK: - 1. Play & Live Scoreboard

struct ActiveMatchesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Match.startedAt, order: .reverse) private var matches: [Match]
    @Query(sort: \GameType.name) private var gameTypes: [GameType]
    @Query(sort: \Team.name) private var teams: [Team]

    @State private var showingNewMatchSheet = false
    @State private var didSeedDefaults = false
    @State private var selectedMatchForNavigation: Match?
    @State private var matchPendingReset: Match?

    private var activeMatches: [Match] {
        matches.filter { !$0.isCompleted }
    }

    /// Limited to the last 5 completed games, sorted by most recently completed
    private var recentCompletedMatches: [Match] {
        let completed = matches
            .filter { $0.isCompleted }
            .sorted { ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt) }
        return Array(completed.prefix(5))
    }

    var body: some View {
        NavigationStack {
            Group {
                if activeMatches.isEmpty && recentCompletedMatches.isEmpty {
                    ContentUnavailableView(
                        "No Active Game",
                        systemImage: "flag.2.crossed.fill",
                        description: Text("Tap + to start a new match and pick your teams and game rules.")
                    )
                } else {
                    List {
                        Section("Active Matches") {
                            if activeMatches.isEmpty {
                                Text("No active matches in progress.")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.secondary)
                            } else {
                                ForEach(activeMatches) { match in
                                    NavigationLink(destination: LiveScoreboardView(match: match)) {
                                        MatchRowSummaryView(match: match, isCompleted: false)
                                    }
                                }
                                .onDelete { offsets in
                                    let snapshot = activeMatches
                                    let toDelete = offsets.compactMap { snapshot.indices.contains($0) ? snapshot[$0] : nil }
                                    for match in toDelete {
                                        context.delete(match)
                                    }
                                    try? context.save()
                                }
                            }
                        }

                        if !recentCompletedMatches.isEmpty {
                            Section("Recently Completed (Last 5)") {
                                ForEach(recentCompletedMatches) { match in
                                    HStack(spacing: 12) {
                                        NavigationLink(destination: LiveScoreboardView(match: match)) {
                                            MatchRowSummaryView(match: match, isCompleted: true)
                                        }

                                        Menu {
                                            Button {
                                                match.reopenMatch()
                                                try? context.save()
                                                selectedMatchForNavigation = match
                                            } label: {
                                                Label("Reopen & Continue Scoring", systemImage: "arrow.uturn.backward.circle")
                                            }

                                            Button(role: .destructive) {
                                                matchPendingReset = match
                                            } label: {
                                                Label("Restart from 0 (Reset Scores)", systemImage: "arrow.counterclockwise.circle")
                                            }
                                        } label: {
                                            Text("Restart")
                                                .font(.caption.bold())
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color.blue.opacity(0.15), in: Capsule())
                                                .foregroundStyle(Color.blue)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                                .onDelete { offsets in
                                    let snapshot = recentCompletedMatches
                                    let toDelete = offsets.compactMap { snapshot.indices.contains($0) ? snapshot[$0] : nil }
                                    for match in toDelete {
                                        context.delete(match)
                                    }
                                    try? context.save()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tally: It")
            .navigationDestination(item: $selectedMatchForNavigation) { match in
                LiveScoreboardView(match: match)
            }
            .onAppear {
                if !didSeedDefaults {
                    didSeedDefaults = true
                    seedDefaultsIfNeeded()
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewMatchSheet = true
                    } label: {
                        Label("New Match", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingNewMatchSheet) {
                NewMatchSheet()
            }
            .alert(
                "Reset Match to 0?",
                isPresented: Binding(
                    get: { matchPendingReset != nil },
                    set: { if !$0 { matchPendingReset = nil } }
                ),
                presenting: matchPendingReset
            ) { match in
                Button("Reset to 0", role: .destructive) {
                    match.restartMatchFromZero()
                    try? context.save()
                    selectedMatchForNavigation = match
                    matchPendingReset = nil
                }
                Button("Cancel", role: .cancel) {
                    matchPendingReset = nil
                }
            } message: { match in
                Text("This clears all scores and round history for \(match.gameTypeName) and restarts from Round 1.")
            }
        }
    }

    private func seedDefaultsIfNeeded() {
        var didChange = false
        if gameTypes.isEmpty {
            context.insert(GameType(name: "Cornhole", incrementsRaw: "1, 3, -1", targetScore: 21, trackRounds: true, useCondensedView: true))
            context.insert(GameType(name: "10-Round Game", incrementsRaw: "5, 10, 20", maxRounds: 10, trackRounds: true, useCondensedView: true))
            didChange = true
        }
        if teams.isEmpty {
            context.insert(Team(name: "Team Alpha"))
            context.insert(Team(name: "Team Bravo"))
            didChange = true
        }
        if didChange {
            try? context.save()
        }
    }
}

struct MatchRowSummaryView: View {
    let match: Match
    let isCompleted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(match.gameTypeName)
                    .font(.headline)
                Spacer()
                if isCompleted {
                    Text("Completed")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.green)
                } else if match.trackRounds {
                    let roundText: String = {
                        if let maxR = match.maxRounds, maxR > 0 {
                            return "Round \(min(match.currentRound, maxR))/\(maxR)"
                        }
                        return "Round \(match.currentRound)"
                    }()
                    Text(roundText)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.blue)
                } else {
                    Text("Total Only")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.secondary)
                }
            }
            Text(match.sortedEntries.map { "\($0.teamName): \($0.score)" }.joined(separator: "  |  "))
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct NewMatchSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \GameType.name) private var gameTypes: [GameType]
    @Query(sort: \Team.name) private var teams: [Team]

    @State private var selectedGameTypeID: UUID?
    @State private var selectedTeamIDs: Set<UUID> = []
    @State private var customTargetScoreText: String = ""
    @State private var customMaxRoundsText: String = ""
    @State private var useCondensedView: Bool = true

    private var selectedGameType: GameType? {
        if let id = selectedGameTypeID {
            return gameTypes.first(where: { $0.id == id })
        }
        return gameTypes.first
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Game Type") {
                    if !gameTypes.isEmpty {
                        Picker("Game", selection: $selectedGameTypeID) {
                            ForEach(gameTypes) { game in
                                Text(game.name).tag(Optional(game.id))
                            }
                        }
                        .onChange(of: selectedGameTypeID) { _, newID in
                            guard let game = gameTypes.first(where: { $0.id == newID }) else { return }
                            applyGameTypeDefaults(game)
                        }

                        HStack {
                            Text("Amount Needed to Win")
                            Spacer()
                            TextField("Optional", text: $customTargetScoreText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                        }

                        HStack {
                            Text("Max Rounds to Win")
                            Spacer()
                            TextField("Optional", text: $customMaxRoundsText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                        }

                        Toggle("Condensed View (Hide + / - Buttons)", isOn: $useCondensedView)
                    } else {
                        Text("No game types saved yet.")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }

                    NavigationLink {
                        CreateGameTypeInlineView { createdGame in
                            selectedGameTypeID = createdGame.id
                            applyGameTypeDefaults(createdGame)
                        }
                    } label: {
                        Label("Create New Game Type", systemImage: "plus.circle")
                            .foregroundStyle(Color.blue)
                    }
                }

                Section("Select Teams (2 or More)") {
                    if teams.isEmpty {
                        Text("No teams saved. Add teams in the Setup tab first.")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    } else {
                        ForEach(teams) { team in
                            Button {
                                if selectedTeamIDs.contains(team.id) {
                                    selectedTeamIDs.remove(team.id)
                                } else {
                                    selectedTeamIDs.insert(team.id)
                                }
                            } label: {
                                HStack {
                                    Text(team.name)
                                        .foregroundStyle(Color.primary)
                                    Spacer()
                                    Image(systemName: selectedTeamIDs.contains(team.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedTeamIDs.contains(team.id) ? Color.blue : Color.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Match")
            .onAppear {
                syncDefaultGameSelection()
            }
            .onChange(of: gameTypes.count) { _, _ in
                syncDefaultGameSelection()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        startMatch()
                    }
                    .disabled(selectedGameType == nil || selectedTeamIDs.count < 2)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }
                }
            }
        }
    }

    private func applyGameTypeDefaults(_ game: GameType) {
        customTargetScoreText = game.targetScore.map(String.init) ?? ""
        customMaxRoundsText = game.maxRounds.map(String.init) ?? ""
        useCondensedView = game.useCondensedView
    }

    private func syncDefaultGameSelection() {
        if selectedGameTypeID == nil, let first = gameTypes.first {
            selectedGameTypeID = first.id
            applyGameTypeDefaults(first)
        }
    }

    private func startMatch() {
        guard let game = selectedGameType else { return }
        let chosenTeams = teams.filter { selectedTeamIDs.contains($0.id) }
        guard chosenTeams.count >= 2 else { return }

        let entries = chosenTeams.enumerated().map { index, team in
            MatchScoreEntry(teamID: team.id, teamName: team.name, score: 0, sortOrder: index)
        }
        let match = Match(gameType: game, entries: entries)
        match.targetScore = ScoreMath.parsePositiveInt(customTargetScoreText)
        match.maxRounds = ScoreMath.parsePositiveInt(customMaxRoundsText)
        match.useCondensedView = useCondensedView
        context.insert(match)
        try? context.save()
        dismiss()
    }
}

struct CreateGameTypeInlineView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var onCreated: (GameType) -> Void

    @State private var name = ""
    @State private var increments = ScoreIncrementParser.defaultRaw
    @State private var target = ""
    @State private var maxRounds = ""
    @State private var trackRounds = true
    @State private var lowWins = false
    @State private var useCondensedView = true

    var body: some View {
        Form {
            Section("New Game Details") {
                TextField("Game Name", text: $name)
                Toggle("Condensed View (Default)", isOn: $useCondensedView)
                if !useCondensedView {
                    TextField("Point Buttons (e.g. 1, 5, 10, -1)", text: $increments)
                }
                TextField("Amount Needed to Win (Optional)", text: $target)
                    .keyboardType(.numberPad)
                TextField("Max Rounds to Win (Optional)", text: $maxRounds)
                    .keyboardType(.numberPad)
                Toggle("Track Rounds & Ledger", isOn: $trackRounds)
                Toggle("Lowest Score Wins", isOn: $lowWins)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Create Game Type")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let newGame = GameType(
                        name: trimmed,
                        incrementsRaw: increments,
                        targetScore: ScoreMath.parsePositiveInt(target),
                        maxRounds: ScoreMath.parsePositiveInt(maxRounds),
                        lowestScoreWins: lowWins,
                        trackRounds: trackRounds,
                        useCondensedView: useCondensedView
                    )
                    context.insert(newGame)
                    try? context.save()
                    onCreated(newGame)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
            }
        }
    }
}

struct LiveScoreboardView: View {
    @Bindable var match: Match
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showingRulesSheet = false
    @State private var showingRoundLedger = true
    @State private var showingResetConfirmation = false

    private var activeMaxRounds: Int? {
        guard let maxR = match.maxRounds, maxR > 0 else { return nil }
        return maxR
    }

    var body: some View {
        ScrollView {
            VStack(spacing: match.useCondensedView ? 8 : 14) {
                if match.isCompleted {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Color.green)
                            Text("Match Submitted (Read-Only)")
                                .font(.subheadline.bold())
                            Spacer()
                        }

                        HStack(spacing: 10) {
                            Button {
                                withAnimation {
                                    match.reopenMatch()
                                    try? context.save()
                                }
                            } label: {
                                Label("Reopen & Continue", systemImage: "arrow.uturn.backward.circle.fill")
                                    .font(.caption.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(Color.white)
                            }

                            Button {
                                showingResetConfirmation = true
                            } label: {
                                Label("Reset to 0", systemImage: "arrow.counterclockwise.circle.fill")
                                    .font(.caption.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(Color.orange)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }

                if match.trackRounds {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            let roundDisplay: String = {
                                if let maxR = activeMaxRounds {
                                    return "ROUND \(min(match.currentRound, maxR)) of \(maxR)"
                                }
                                return "ROUND \(match.currentRound)"
                            }()
                            Text(roundDisplay)
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(Color.blue)

                            if let maxR = activeMaxRounds, match.currentRound > maxR {
                                Text("Final Results (Max Rounds Reached)")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.green)
                            } else if let target = match.targetScore, target > 0 {
                                Label("Goal: \(target) pts (\(match.lowestScoreWins ? "Low Wins" : "High Wins"))", systemImage: "flag.checkered")
                                    .font(.caption.bold())
                            } else {
                                Text(match.lowestScoreWins ? "Lowest Score Wins" : "Highest Score Wins")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                        }

                        Spacer()

                        if !match.isCompleted {
                            let isFinal = activeMaxRounds.map { match.currentRound >= $0 } ?? false
                            Button {
                                hideKeyboard()
                                advanceRound()
                            } label: {
                                Label(isFinal ? "Finish Game" : "Next Round", systemImage: isFinal ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(isFinal ? Color.green : Color.blue, in: Capsule())
                                    .foregroundStyle(Color.white)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                } else if let target = match.targetScore, target > 0 {
                    HStack {
                        Label("Goal: \(target) pts (\(match.lowestScoreWins ? "Low Wins" : "High Wins"))", systemImage: "flag.checkered")
                            .font(.caption.bold())
                        Spacer()
                    }
                    .padding(.horizontal)
                }

                let winners = match.winningEntries
                if !winners.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "trophy.fill")
                            .font(.headline)
                            .foregroundStyle(Color.orange)
                        Text("\(winners.map(\.teamName).joined(separator: " & ")) leads / wins!")
                            .font(.subheadline.bold())
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.green, lineWidth: 1.5)
                    )
                    .padding(.horizontal)
                }

                ForEach(match.sortedEntries) { entry in
                    TeamScoreCard(
                        entry: entry,
                        increments: match.increments,
                        currentRound: match.currentRound,
                        targetScore: match.targetScore,
                        lowestScoreWins: match.lowestScoreWins,
                        trackRounds: match.trackRounds,
                        useCondensedView: match.useCondensedView,
                        isWinnerHighlighted: match.isTargetWinner(entry),
                        isReadOnly: match.isCompleted
                    )
                }

                if match.trackRounds && (!match.roundHistoryEmpty || match.currentRound > 1 || match.sortedEntries.contains(where: { $0.currentRoundDelta != 0 })) {
                    RoundLedgerSection(match: match, isExpanded: $showingRoundLedger, isReadOnly: match.isCompleted)
                        .padding(.horizontal)
                }

                if !match.isCompleted {
                    Button {
                        hideKeyboard()
                        completeMatch()
                    } label: {
                        Label("Finish Match & Record Standings", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(winners.isEmpty ? Color.blue : Color.green)
                            .foregroundStyle(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(match.gameTypeName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingRulesSheet = true
                } label: {
                    Label("Adjust Scoring", systemImage: "slider.horizontal.3")
                }
                .disabled(match.isCompleted)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
            }
        }
        .sheet(isPresented: $showingRulesSheet) {
            AdjustMatchScoringSheet(match: match)
        }
        .alert("Reset Match to 0?", isPresented: $showingResetConfirmation) {
            Button("Reset to 0", role: .destructive) {
                withAnimation {
                    match.restartMatchFromZero()
                    try? context.save()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears all scores and round history for \(match.gameTypeName) and restarts from Round 1.")
        }
    }

    private func advanceRound() {
        for entry in match.entries {
            entry.roundHistory.append(entry.currentRoundDelta)
            entry.currentRoundDelta = 0
            entry.recalculateTotalScore()
        }

        if let maxR = activeMaxRounds, match.currentRound >= maxR {
            match.currentRound += 1
            completeMatch()
        } else {
            match.currentRound += 1
            try? context.save()
        }
    }

    private func completeMatch() {
        if match.trackRounds && match.entries.contains(where: { $0.currentRoundDelta != 0 }) {
            for entry in match.entries {
                entry.roundHistory.append(entry.currentRoundDelta)
                entry.currentRoundDelta = 0
                entry.recalculateTotalScore()
            }
        }

        let sorted = match.entries.sorted { a, b in
            match.lowestScoreWins ? (a.score < b.score) : (a.score > b.score)
        }
        if sorted.count >= 2, sorted[0].score != sorted[1].score {
            match.winnerTeamID = sorted[0].teamID
        } else {
            match.winnerTeamID = nil
        }
        match.isCompleted = true
        match.completedAt = Date()
        try? context.save()
        dismiss()
    }
}

extension Match {
    var roundHistoryEmpty: Bool {
        entries.allSatisfy { $0.roundHistory.isEmpty }
    }

    /// Un-submits a completed match and restores the active round state so scoring can continue
    func reopenMatch() {
        if let maxR = maxRounds, maxR > 0, currentRound > maxR {
            currentRound = maxR
        }
        if trackRounds {
            for entry in entries {
                while entry.roundHistory.count >= currentRound && !entry.roundHistory.isEmpty {
                    let restoredDelta = entry.roundHistory.removeLast()
                    entry.currentRoundDelta = ScoreMath.add(entry.currentRoundDelta, restoredDelta)
                }
                entry.recalculateTotalScore()
            }
        }
        isCompleted = false
        completedAt = nil
        winnerTeamID = nil
    }

    /// Resets a completed match back to Round 1 with 0 points for all teams
    func restartMatchFromZero() {
        currentRound = 1
        for entry in entries {
            entry.score = 0
            entry.currentRoundDelta = 0
            entry.roundHistory = []
        }
        isCompleted = false
        completedAt = nil
        winnerTeamID = nil
    }
}

struct TeamScoreCard: View {
    @Environment(\.modelContext) private var context
    @Bindable var entry: MatchScoreEntry
    let increments: [Int]
    let currentRound: Int
    let targetScore: Int?
    let lowestScoreWins: Bool
    let trackRounds: Bool
    let useCondensedView: Bool
    let isWinnerHighlighted: Bool
    let isReadOnly: Bool

    @State private var customInputText: String = ""

    private var parsedCustomInput: Int? {
        ScoreMath.parseInt(customInputText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: useCondensedView ? 6 : 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.teamName)
                            .font(useCondensedView ? .headline : .title3.bold())
                            .lineLimit(1)
                        if isWinnerHighlighted {
                            Label("WIN", systemImage: "crown.fill")
                                .font(.caption2.weight(.heavy))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green, in: Capsule())
                                .foregroundStyle(Color.white)
                        }
                    }

                    if trackRounds {
                        HStack(spacing: 6) {
                            let sign = entry.currentRoundDelta >= 0 ? "+" : ""
                            Text("R\(currentRound): \(sign)\(entry.currentRoundDelta)")
                                .font(.caption2.bold())
                                .foregroundStyle(Color.secondary)

                            if let target = targetScore, target > 0, !isWinnerHighlighted {
                                let remaining = max(0, target - entry.score)
                                if remaining > 0 {
                                    Text(lowestScoreWins ? "| \(remaining) to limit" : "| \(remaining) left")
                                        .font(.caption2)
                                        .foregroundStyle(Color.secondary)
                                }
                            }
                        }
                    } else if let target = targetScore, target > 0, !isWinnerHighlighted {
                        let remaining = max(0, target - entry.score)
                        if remaining > 0 {
                            Text(lowestScoreWins ? "\(remaining) pts to limit" : "\(remaining) pts left")
                                .font(.caption2)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }

                Spacer()

                Text("\(entry.score)")
                    .font(.system(size: useCondensedView ? 28 : 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(isWinnerHighlighted ? Color.green : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
            }

            if !isReadOnly {
                if !useCondensedView {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(increments, id: \.self) { delta in
                                Button {
                                    applyScoreChange(delta: delta)
                                } label: {
                                    Text(delta > 0 ? "+\(delta)" : "\(delta)")
                                        .font(.subheadline.bold())
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(delta >= 0 ? Color.blue.opacity(0.15) : Color.red.opacity(0.15))
                                        .foregroundStyle(delta >= 0 ? Color.blue : Color.red)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 6) {
                    TextField("Points (+/- or total)", text: $customInputText)
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)

                    Button("Add To") {
                        if let val = parsedCustomInput {
                            applyScoreChange(delta: val)
                            customInputText = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(useCondensedView ? .small : .regular)
                    .disabled(parsedCustomInput == nil)

                    Button("Set") {
                        if let val = parsedCustomInput {
                            let diff = ScoreMath.subtract(val, entry.score)
                            entry.score = val
                            if trackRounds {
                                entry.currentRoundDelta = ScoreMath.add(entry.currentRoundDelta, diff)
                            }
                            try? context.save()
                            customInputText = ""
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(useCondensedView ? .small : .regular)
                    .disabled(parsedCustomInput == nil)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, useCondensedView ? 8 : 14)
        .background(
            isWinnerHighlighted
                ? Color.green.opacity(0.12)
                : Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isWinnerHighlighted ? Color.green : Color.clear, lineWidth: 2)
        )
        .padding(.horizontal)
    }

    private func applyScoreChange(delta: Int) {
        entry.score = ScoreMath.add(entry.score, delta)
        if trackRounds {
            entry.currentRoundDelta = ScoreMath.add(entry.currentRoundDelta, delta)
        }
        try? context.save()
    }
}

// MARK: - Inline Editable Round History Ledger

struct RoundLedgerSection: View {
    @Environment(\.modelContext) private var context
    let match: Match
    @Binding var isExpanded: Bool
    let isReadOnly: Bool

    @State private var isEditingLedger: Bool = false
    @State private var draftScores: [String: String] = [:]

    private var completedRoundsArray: [Int] {
        let count = match.sortedEntries.map { $0.roundHistory.count }.max() ?? 0
        return Array(0..<count)
    }

    var body: some View {
        let entries = match.sortedEntries
        let needsHorizontalScroll = entries.count > 2

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Label("Round History Ledger", systemImage: "list.number")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.primary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                }

                Spacer()

                if isExpanded && !completedRoundsArray.isEmpty && !isReadOnly {
                    Button {
                        toggleEditMode()
                    } label: {
                        Text(isEditingLedger ? "Done" : "Edit")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(isEditingLedger ? Color.blue : Color.secondary.opacity(0.18), in: Capsule())
                            .foregroundStyle(isEditingLedger ? Color.white : Color.primary)
                    }
                }
            }

            if isExpanded {
                Divider()

                if needsHorizontalScroll {
                    ScrollView(.horizontal, showsIndicators: true) {
                        ledgerRows(entries: entries, fixedColumnWidth: 76)
                    }
                } else {
                    ledgerRows(entries: entries, fixedColumnWidth: nil)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .onChange(of: isReadOnly) { _, readOnly in
            if readOnly {
                isEditingLedger = false
            }
        }
    }

    @ViewBuilder
    private func ledgerRows(entries: [MatchScoreEntry], fixedColumnWidth: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Rnd")
                    .font(.caption.bold())
                    .foregroundStyle(Color.secondary)
                    .frame(width: 44, alignment: .leading)

                ForEach(entries) { entry in
                    Text(entry.teamName)
                        .font(.caption.bold())
                        .lineLimit(1)
                        .frame(width: fixedColumnWidth, alignment: .trailing)
                        .frame(maxWidth: fixedColumnWidth == nil ? .infinity : nil, alignment: .trailing)
                }
            }

            ForEach(completedRoundsArray, id: \.self) { roundIndex in
                HStack(spacing: 8) {
                    Text("R\(roundIndex + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.secondary)
                        .frame(width: 44, alignment: .leading)

                    ForEach(entries) { entry in
                        let val = roundIndex < entry.roundHistory.count ? entry.roundHistory[roundIndex] : 0

                        if isEditingLedger && !isReadOnly {
                            TextField("0", text: bindingForCell(entry: entry, roundIndex: roundIndex, fallback: val))
                                .keyboardType(.numbersAndPunctuation)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                                .font(.subheadline.bold().monospacedDigit())
                                .frame(width: fixedColumnWidth, alignment: .trailing)
                                .frame(maxWidth: fixedColumnWidth == nil ? .infinity : nil, alignment: .trailing)
                        } else {
                            Text(val >= 0 ? "+\(val)" : "\(val)")
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(val >= 0 ? Color.primary : Color.red)
                                .frame(width: fixedColumnWidth, alignment: .trailing)
                                .frame(maxWidth: fixedColumnWidth == nil ? .infinity : nil, alignment: .trailing)
                                .padding(.vertical, 4)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            if !match.isCompleted {
                HStack(spacing: 8) {
                    Text("R\(match.currentRound)*")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(Color.blue)
                        .frame(width: 44, alignment: .leading)

                    ForEach(entries) { entry in
                        let val = entry.currentRoundDelta
                        Text(val >= 0 ? "+\(val)" : "\(val)")
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(Color.blue)
                            .frame(width: fixedColumnWidth, alignment: .trailing)
                            .frame(maxWidth: fixedColumnWidth == nil ? .infinity : nil, alignment: .trailing)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func cellKey(entryID: UUID, roundIndex: Int) -> String {
        "\(entryID.uuidString)_\(roundIndex)"
    }

    private func bindingForCell(entry: MatchScoreEntry, roundIndex: Int, fallback: Int) -> Binding<String> {
        let key = cellKey(entryID: entry.id, roundIndex: roundIndex)
        return Binding(
            get: { draftScores[key] ?? String(fallback) },
            set: { newValue in
                draftScores[key] = newValue
                if let parsed = ScoreMath.parseInt(newValue),
                   roundIndex < entry.roundHistory.count {
                    entry.roundHistory[roundIndex] = parsed
                    entry.recalculateTotalScore()
                }
            }
        )
    }

    private func toggleEditMode() {
        if isEditingLedger {
            hideKeyboard()
            for entry in match.entries {
                for rIndex in 0..<entry.roundHistory.count {
                    let key = cellKey(entryID: entry.id, roundIndex: rIndex)
                    if let text = draftScores[key],
                       let parsed = ScoreMath.parseInt(text) {
                        entry.roundHistory[rIndex] = parsed
                    }
                }
                entry.recalculateTotalScore()
            }
            try? context.save()
            isEditingLedger = false
        } else {
            var initial: [String: String] = [:]
            for entry in match.entries {
                for (rIndex, val) in entry.roundHistory.enumerated() {
                    initial[cellKey(entryID: entry.id, roundIndex: rIndex)] = String(val)
                }
            }
            draftScores = initial
            isEditingLedger = true
        }
    }
}

struct AdjustMatchScoringSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var match: Match

    @State private var didLoad = false
    @State private var useCondensedView: Bool = true
    @State private var incrementsRaw: String = ScoreIncrementParser.defaultRaw
    @State private var targetText: String = ""
    @State private var maxRoundsText: String = ""
    @State private var trackRounds: Bool = true
    @State private var lowestScoreWins: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Scoreboard Layout") {
                    Toggle("Condensed View (Hide + / - Buttons)", isOn: $useCondensedView)
                }
                if !useCondensedView {
                    Section("Point Buttons (Comma-Separated)") {
                        TextField("e.g. 1, 5, 10, -1", text: $incrementsRaw)
                    }
                }
                Section("Amount Needed to Win") {
                    TextField("Leave blank for no target", text: $targetText)
                        .keyboardType(.numberPad)
                }
                Section("Max Rounds to Win") {
                    TextField("Leave blank for unlimited", text: $maxRoundsText)
                        .keyboardType(.numberPad)
                }
                Section("Round Tracking") {
                    Toggle("Track Rounds & Ledger", isOn: $trackRounds)
                }
                Section("Win Rule") {
                    Toggle("Lowest Score Wins", isOn: $lowestScoreWins)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Scoring Details")
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                useCondensedView = match.useCondensedView
                incrementsRaw = match.incrementsRaw
                targetText = match.targetScore.map(String.init) ?? ""
                maxRoundsText = match.maxRounds.map(String.init) ?? ""
                trackRounds = match.trackRounds
                lowestScoreWins = match.lowestScoreWins
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applyChanges()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }
                }
            }
        }
    }

    private func applyChanges() {
        let enablingRoundTracking = !match.trackRounds && trackRounds
        if enablingRoundTracking {
            for entry in match.entries {
                let historySum = entry.roundHistory.reduce(0, ScoreMath.add)
                entry.currentRoundDelta = ScoreMath.subtract(entry.score, historySum)
            }
        }

        match.useCondensedView = useCondensedView
        match.incrementsRaw = incrementsRaw
        match.targetScore = ScoreMath.parsePositiveInt(targetText)
        match.maxRounds = ScoreMath.parsePositiveInt(maxRoundsText)
        match.trackRounds = trackRounds
        match.lowestScoreWins = lowestScoreWins
        try? context.save()
    }
}

// MARK: - 2. Standings by Game Type

struct TeamStandingRow: Identifiable {
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

struct StandingsView: View {
    @Query(sort: \Match.completedAt, order: .reverse) private var allMatches: [Match]
    @Query(sort: \GameType.name) private var gameTypes: [GameType]

    @State private var selectedGameTypeID: UUID? = nil

    private var effectiveGameTypeID: UUID? {
        guard let id = selectedGameTypeID,
              gameTypes.contains(where: { $0.id == id }) else {
            return nil
        }
        return id
    }

    private var selectedGameName: String {
        guard let id = effectiveGameTypeID,
              let game = gameTypes.first(where: { $0.id == id }) else {
            return "All Games"
        }
        return game.name
    }

    private var completedMatches: [Match] {
        allMatches.filter { match in
            guard match.isCompleted else { return false }
            if let filterID = effectiveGameTypeID {
                return match.gameTypeID == filterID
            }
            return true
        }
    }

    private var standings: [TeamStandingRow] {
        var map: [UUID: TeamStandingRow] = [:]
        for match in completedMatches {
            let bestScore: Int? = match.lowestScoreWins
                ? match.entries.map(\.score).min()
                : match.entries.map(\.score).max()

            for entry in match.entries {
                var row = map[entry.teamID] ?? TeamStandingRow(id: entry.teamID, teamName: entry.teamName)
                row.totalPoints = ScoreMath.add(row.totalPoints, entry.score)

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
        return map.values.sorted {
            if $0.wins != $1.wins { return $0.wins > $1.wins }
            if $0.winPercentage != $1.winPercentage { return $0.winPercentage > $1.winPercentage }
            return $0.totalPoints > $1.totalPoints
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterPillButton(
                            title: "All Games",
                            isSelected: effectiveGameTypeID == nil
                        ) {
                            selectedGameTypeID = nil
                        }

                        ForEach(gameTypes) { game in
                            FilterPillButton(
                                title: game.name,
                                isSelected: effectiveGameTypeID == game.id
                            ) {
                                selectedGameTypeID = game.id
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .background(Color(.systemGroupedBackground))

                if standings.isEmpty {
                    ContentUnavailableView(
                        "No Standings for \(selectedGameName)",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Finish a match to see team win/loss records.")
                    )
                } else {
                    List {
                        Section {
                            HStack {
                                StatSummaryBox(title: "Category", value: selectedGameName)
                                Divider()
                                StatSummaryBox(title: "Matches", value: "\(completedMatches.count)")
                                Divider()
                                StatSummaryBox(title: "Top Team", value: standings.first?.teamName ?? "-")
                            }
                            .padding(.vertical, 4)
                        }

                        Section("Leaderboard") {
                            ForEach(Array(standings.enumerated()), id: \.element.id) { index, row in
                                let winPct = Int((row.winPercentage * 100).rounded())
                                HStack(spacing: 12) {
                                    Text("#\(index + 1)")
                                        .font(.subheadline.weight(.heavy))
                                        .foregroundStyle(index == 0 ? Color.orange : Color.secondary)
                                        .frame(width: 32, alignment: .leading)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(row.teamName)
                                            .font(.headline)
                                        Text("\(row.gamesPlayed) Played  |  \(row.totalPoints) Total Pts")
                                            .font(.caption)
                                            .foregroundStyle(Color.secondary)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text("\(row.wins)W - \(row.losses)L" + (row.ties > 0 ? " - \(row.ties)T" : ""))
                                            .font(.subheadline.bold())
                                        Text("\(winPct)% Win")
                                            .font(.caption.bold())
                                            .foregroundStyle(row.winPercentage >= 0.5 ? Color.green : Color.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Standings")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("All Games") { selectedGameTypeID = nil }
                        Divider()
                        ForEach(gameTypes) { game in
                            Button(game.name) { selectedGameTypeID = game.id }
                        }
                    } label: {
                        Label("Filter Game", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }
}

struct FilterPillButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .bold : .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color(.secondarySystemGroupedBackground), in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
    }
}

struct StatSummaryBox: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.subheadline.bold())
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 3. Teams & Game Types Setup (With Editing)

struct SetupView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Team.name) private var teams: [Team]
    @Query(sort: \GameType.name) private var gameTypes: [GameType]

    @State private var newTeamName = ""
    @State private var newGameName = ""
    @State private var newGameIncrements = ScoreIncrementParser.defaultRaw
    @State private var newGameTargetScore = ""
    @State private var newGameMaxRounds = ""
    @State private var newGameTrackRounds = true
    @State private var newGameLowestWins = false
    @State private var newGameCondensedView = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Add Team") {
                    HStack {
                        TextField("Team Name", text: $newTeamName)
                        Button("Add") {
                            let trimmed = newTeamName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            context.insert(Team(name: trimmed))
                            try? context.save()
                            newTeamName = ""
                            hideKeyboard()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newTeamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section("Teams (\(teams.count))") {
                    ForEach(teams) { team in
                        Text(team.name)
                    }
                    .onDelete { offsets in
                        let snapshot = teams
                        let toDelete = offsets.compactMap { snapshot.indices.contains($0) ? snapshot[$0] : nil }
                        for team in toDelete {
                            context.delete(team)
                        }
                        try? context.save()
                    }
                }

                Section("Create New Game Type") {
                    TextField("Game Name (e.g. Darts, Catan)", text: $newGameName)
                    Toggle("Condensed View (Default)", isOn: $newGameCondensedView)
                    if !newGameCondensedView {
                        TextField("Point Buttons (e.g. 1, 5, 10, -1)", text: $newGameIncrements)
                    }
                    TextField("Amount Needed to Win (Optional)", text: $newGameTargetScore)
                        .keyboardType(.numberPad)
                    TextField("Max Rounds to Win (Optional)", text: $newGameMaxRounds)
                        .keyboardType(.numberPad)
                    Toggle("Track Rounds & Ledger", isOn: $newGameTrackRounds)
                    Toggle("Lowest Score Wins", isOn: $newGameLowestWins)

                    Button("Save Game Type") {
                        let trimmed = newGameName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let target = ScoreMath.parsePositiveInt(newGameTargetScore)
                        let maxR = ScoreMath.parsePositiveInt(newGameMaxRounds)
                        context.insert(
                            GameType(
                                name: trimmed,
                                incrementsRaw: newGameIncrements,
                                targetScore: target,
                                maxRounds: maxR,
                                lowestScoreWins: newGameLowestWins,
                                trackRounds: newGameTrackRounds,
                                useCondensedView: newGameCondensedView
                            )
                        )
                        try? context.save()
                        newGameName = ""
                        newGameIncrements = ScoreIncrementParser.defaultRaw
                        newGameTargetScore = ""
                        newGameMaxRounds = ""
                        newGameTrackRounds = true
                        newGameLowestWins = false
                        newGameCondensedView = true
                        hideKeyboard()
                    }
                    .disabled(newGameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Saved Game Types (Tap to Edit)") {
                    ForEach(gameTypes) { game in
                        NavigationLink(destination: EditGameTypeView(gameType: game)) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(game.name)
                                        .font(.headline)
                                    Spacer()
                                    if let target = game.targetScore, target > 0 {
                                        Text("Win: \(target)")
                                            .font(.caption.bold())
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.15), in: Capsule())
                                            .foregroundStyle(Color.blue)
                                    } else if let maxR = game.maxRounds, maxR > 0 {
                                        Text("\(maxR) Rounds")
                                            .font(.caption.bold())
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.15), in: Capsule())
                                            .foregroundStyle(Color.blue)
                                    }
                                }
                                let viewModeLabel = game.useCondensedView ? "Condensed" : "Expanded (\(game.incrementsRaw))"
                                let roundsLabel = game.trackRounds ? "Rounds On" : "Total Only"
                                let winRuleLabel = game.lowestScoreWins ? "Low Wins" : "High Wins"
                                Text("\(viewModeLabel) | \(roundsLabel) | \(winRuleLabel)")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .onDelete { offsets in
                        let snapshot = gameTypes
                        let toDelete = offsets.compactMap { snapshot.indices.contains($0) ? snapshot[$0] : nil }
                        for game in toDelete {
                            context.delete(game)
                        }
                        try? context.save()
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Setup")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }
                }
            }
        }
    }
}

struct EditGameTypeView: View {
    @Bindable var gameType: GameType
    @Query(sort: \Match.startedAt, order: .reverse) private var allMatches: [Match]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var didLoad = false
    @State private var name: String = ""
    @State private var useCondensedView: Bool = true
    @State private var incrementsRaw: String = ScoreIncrementParser.defaultRaw
    @State private var targetScoreText: String = ""
    @State private var maxRoundsText: String = ""
    @State private var trackRounds: Bool = true
    @State private var lowestScoreWins: Bool = false

    var body: some View {
        Form {
            Section("Game Identity") {
                TextField("Game Name", text: $name)
            }

            Section("Scoring Configuration") {
                Toggle("Condensed View (Hide + / - Buttons)", isOn: $useCondensedView)

                if !useCondensedView {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Point Buttons (Comma-Separated)")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                        TextField("e.g. 1, 5, 10, -1", text: $incrementsRaw)
                    }
                }

                HStack {
                    Text("Amount Needed to Win")
                    Spacer()
                    TextField("None", text: $targetScoreText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 110)
                }

                HStack {
                    Text("Max Rounds to Win")
                    Spacer()
                    TextField("None", text: $maxRoundsText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 110)
                }

                Toggle("Track Rounds & Ledger", isOn: $trackRounds)
                Toggle("Lowest Score Wins", isOn: $lowestScoreWins)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Edit Game Type")
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            name = gameType.name
            useCondensedView = gameType.useCondensedView
            incrementsRaw = gameType.incrementsRaw
            targetScoreText = gameType.targetScore.map(String.init) ?? ""
            maxRoundsText = gameType.maxRounds.map(String.init) ?? ""
            trackRounds = gameType.trackRounds
            lowestScoreWins = gameType.lowestScoreWins
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }

                    gameType.name = trimmed
                    gameType.useCondensedView = useCondensedView
                    gameType.incrementsRaw = incrementsRaw
                    gameType.targetScore = ScoreMath.parsePositiveInt(targetScoreText)
                    gameType.maxRounds = ScoreMath.parsePositiveInt(maxRoundsText)
                    gameType.trackRounds = trackRounds
                    gameType.lowestScoreWins = lowestScoreWins

                    for match in allMatches where match.gameTypeID == gameType.id {
                        match.gameTypeName = trimmed
                        if !match.isCompleted {
                            match.maxRounds = gameType.maxRounds
                            match.useCondensedView = gameType.useCondensedView
                        }
                    }
                    try? context.save()
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
            }
        }
    }
}
// END OF ContentView.swift
