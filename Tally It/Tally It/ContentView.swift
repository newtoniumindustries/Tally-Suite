import Foundation
import SwiftUI
import SwiftData

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
                                    for index in offsets {
                                        context.delete(activeMatches[index])
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

                                            Button {
                                                match.restartMatchFromZero()
                                                try? context.save()
                                                selectedMatchForNavigation = match
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
                                    for index in offsets {
                                        context.delete(recentCompletedMatches[index])
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
                    let roundText = match.maxRounds != nil
                        ? "Round \(match.currentRound)/\(match.maxRounds!)"
                        : "Round \(match.currentRound)"
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
                            customTargetScoreText = game.targetScore != nil ? String(game.targetScore!) : ""
                            customMaxRoundsText = game.maxRounds != nil ? String(game.maxRounds!) : ""
                            useCondensedView = game.useCondensedView
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
                            customTargetScoreText = createdGame.targetScore != nil ? String(createdGame.targetScore!) : ""
                            customMaxRoundsText = createdGame.maxRounds != nil ? String(createdGame.maxRounds!) : ""
                            useCondensedView = createdGame.useCondensedView
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
            }
        }
    }

    private func syncDefaultGameSelection() {
        if selectedGameTypeID == nil, let first = gameTypes.first {
            selectedGameTypeID = first.id
            customTargetScoreText = first.targetScore != nil ? String(first.targetScore!) : ""
            customMaxRoundsText = first.maxRounds != nil ? String(first.maxRounds!) : ""
            useCondensedView = first.useCondensedView
        }
    }

    private func startMatch() {
        guard let game = selectedGameType else { return }
        let chosenTeams = teams.filter { selectedTeamIDs.contains($0.id) }
        let entries = chosenTeams.enumerated().map { index, team in
            MatchScoreEntry(teamID: team.id, teamName: team.name, score: 0, sortOrder: index)
        }
        let match = Match(gameType: game, entries: entries)
        match.targetScore = Int(customTargetScoreText.trimmingCharacters(in: .whitespaces))
        match.maxRounds = Int(customMaxRoundsText.trimmingCharacters(in: .whitespaces))
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
    @State private var increments = "1, 5, 10, -1"
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
        .navigationTitle("Create Game Type")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    let newGame = GameType(
                        name: trimmed,
                        incrementsRaw: increments,
                        targetScore: Int(target.trimmingCharacters(in: .whitespaces)),
                        maxRounds: Int(maxRounds.trimmingCharacters(in: .whitespaces)),
                        lowestScoreWins: lowWins,
                        trackRounds: trackRounds,
                        useCondensedView: useCondensedView
                    )
                    context.insert(newGame)
                    try? context.save()
                    onCreated(newGame)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
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

    var body: some View {
        ScrollView {
            VStack(spacing: match.useCondensedView ? 8 : 14) {
                // Completed Match Banner with Restart Actions
                if match.isCompleted {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Color.green)
                            Text("Match Submitted")
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
                                withAnimation {
                                    match.restartMatchFromZero()
                                    try? context.save()
                                }
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
                            let displayRound = match.maxRounds != nil
                                ? min(match.currentRound, match.maxRounds!)
                                : match.currentRound
                            let roundDisplay = match.maxRounds != nil
                                ? "ROUND \(displayRound) of \(match.maxRounds!)"
                                : "ROUND \(displayRound)"
                            Text(roundDisplay)
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(Color.blue)

                            if let maxR = match.maxRounds, match.currentRound > maxR {
                                Text("Final Results (Max Rounds Reached)")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.green)
                            } else if let target = match.targetScore {
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
                            Button {
                                advanceRound()
                            } label: {
                                let isFinal = match.maxRounds != nil && match.currentRound >= match.maxRounds!
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
                } else if let target = match.targetScore {
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
                            .foregroundStyle(Color.yellow)
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
                        trackRounds: match.trackRounds,
                        useCondensedView: match.useCondensedView,
                        isWinnerHighlighted: match.isTargetWinner(entry)
                    )
                }

                if match.trackRounds && (!match.roundHistoryEmpty || match.currentRound > 1 || match.sortedEntries.contains(where: { $0.currentRoundDelta != 0 })) {
                    RoundLedgerSection(match: match, isExpanded: $showingRoundLedger)
                        .padding(.horizontal)
                }

                if !match.isCompleted {
                    Button {
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
            }
        }
        .sheet(isPresented: $showingRulesSheet) {
            AdjustMatchScoringSheet(match: match)
        }
    }

    private func advanceRound() {
        for entry in match.entries {
            entry.roundHistory.append(entry.currentRoundDelta)
            entry.currentRoundDelta = 0
            entry.recalculateTotalScore()
        }

        if let maxR = match.maxRounds, match.currentRound >= maxR {
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
        if let maxR = maxRounds, currentRound > maxR {
            currentRound = maxR
        }
        if trackRounds {
            for entry in entries {
                while entry.roundHistory.count >= currentRound && !entry.roundHistory.isEmpty {
                    let restoredDelta = entry.roundHistory.removeLast()
                    entry.currentRoundDelta += restoredDelta
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
    @Bindable var entry: MatchScoreEntry
    let increments: [Int]
    let currentRound: Int
    let targetScore: Int?
    let trackRounds: Bool
    let useCondensedView: Bool
    let isWinnerHighlighted: Bool

    @State private var customInputText: String = ""

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

                            if let target = targetScore, !isWinnerHighlighted {
                                let remaining = max(0, target - entry.score)
                                if remaining > 0 {
                                    Text("| \(remaining) left")
                                        .font(.caption2)
                                        .foregroundStyle(Color.secondary)
                                }
                            }
                        }
                    } else if let target = targetScore, !isWinnerHighlighted {
                        let remaining = max(0, target - entry.score)
                        if remaining > 0 {
                            Text("\(remaining) pts left")
                                .font(.caption2)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }

                Spacer()

                Text("\(entry.score)")
                    .font(.system(size: useCondensedView ? 28 : 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(isWinnerHighlighted ? Color.green : Color.primary)
                    .contentTransition(.numericText())
            }

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
                    if let val = Int(customInputText.trimmingCharacters(in: .whitespaces)) {
                        applyScoreChange(delta: val)
                        customInputText = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(useCondensedView ? .small : .regular)

                Button("Set") {
                    if let val = Int(customInputText.trimmingCharacters(in: .whitespaces)) {
                        let diff = val - entry.score
                        entry.score = val
                        if trackRounds {
                            entry.currentRoundDelta += diff
                        }
                        customInputText = ""
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(useCondensedView ? .small : .regular)
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
        entry.score += delta
        if trackRounds {
            entry.currentRoundDelta += delta
        }
    }
}

// MARK: - Inline Editable Round History Ledger

struct RoundLedgerSection: View {
    @Environment(\.modelContext) private var context
    let match: Match
    @Binding var isExpanded: Bool

    @State private var isEditingLedger: Bool = false
    @State private var draftScores: [String: String] = [:]

    private var completedRoundsArray: [Int] {
        let count = match.sortedEntries.map { $0.roundHistory.count }.max() ?? 0
        return Array(0..<count)
    }

    var body: some View {
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

                if isExpanded && !completedRoundsArray.isEmpty {
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

                HStack {
                    Text("Rnd")
                        .font(.caption.bold())
                        .foregroundStyle(Color.secondary)
                        .frame(width: 42, alignment: .leading)
                    ForEach(match.sortedEntries) { entry in
                        Text(entry.teamName)
                            .font(.caption.bold())
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                ForEach(completedRoundsArray, id: \.self) { roundIndex in
                    HStack {
                        Text("R\(roundIndex + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.secondary)
                            .frame(width: 42, alignment: .leading)

                        ForEach(match.sortedEntries) { entry in
                            let val = roundIndex < entry.roundHistory.count ? entry.roundHistory[roundIndex] : 0

                            if isEditingLedger {
                                TextField("0", text: bindingForCell(entry: entry, roundIndex: roundIndex, fallback: val))
                                    .keyboardType(.numbersAndPunctuation)
                                    .multilineTextAlignment(.trailing)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.subheadline.bold().monospacedDigit())
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            } else {
                                Text(val >= 0 ? "+\(val)" : "\(val)")
                                    .font(.subheadline.bold().monospacedDigit())
                                    .foregroundStyle(val >= 0 ? Color.primary : Color.red)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                if !match.isCompleted {
                    HStack {
                        Text("R\(match.currentRound)*")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(Color.blue)
                            .frame(width: 42, alignment: .leading)

                        ForEach(match.sortedEntries) { entry in
                            let val = entry.currentRoundDelta
                            Text(val >= 0 ? "+\(val)" : "\(val)")
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(Color.blue)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
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
                if let parsed = Int(newValue.trimmingCharacters(in: .whitespaces)),
                   roundIndex < entry.roundHistory.count {
                    entry.roundHistory[roundIndex] = parsed
                    entry.recalculateTotalScore()
                }
            }
        )
    }

    private func toggleEditMode() {
        if isEditingLedger {
            for entry in match.entries {
                for rIndex in 0..<entry.roundHistory.count {
                    let key = cellKey(entryID: entry.id, roundIndex: rIndex)
                    if let text = draftScores[key],
                       let parsed = Int(text.trimmingCharacters(in: .whitespaces)) {
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
    @Bindable var match: Match
    @Environment(\.dismiss) private var dismiss
    @State private var targetText: String = ""
    @State private var maxRoundsText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Scoreboard Layout") {
                    Toggle("Condensed View (Hide + / - Buttons)", isOn: $match.useCondensedView)
                }
                if !match.useCondensedView {
                    Section("Point Buttons (Comma-Separated)") {
                        TextField("e.g. 1, 5, 10, -1", text: $match.incrementsRaw)
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
                    Toggle("Track Rounds & Ledger", isOn: $match.trackRounds)
                }
                Section("Win Rule") {
                    Toggle("Lowest Score Wins", isOn: $match.lowestScoreWins)
                }
            }
            .navigationTitle("Scoring Details")
            .onAppear {
                if let target = match.targetScore {
                    targetText = String(target)
                }
                if let maxR = match.maxRounds {
                    maxRoundsText = String(maxR)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        match.targetScore = Int(targetText.trimmingCharacters(in: .whitespaces))
                        match.maxRounds = Int(maxRoundsText.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }
                }
            }
        }
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

    private var selectedGameName: String {
        guard let id = selectedGameTypeID,
              let game = gameTypes.first(where: { $0.id == id }) else {
            return "All Games"
        }
        return game.name
    }

    private var completedMatches: [Match] {
        allMatches.filter { match in
            guard match.isCompleted else { return false }
            if let filterID = selectedGameTypeID {
                return match.gameTypeID == filterID
            }
            return true
        }
    }

    private var standings: [TeamStandingRow] {
        var map: [UUID: TeamStandingRow] = [:]
        for match in completedMatches {
            for entry in match.entries {
                var row = map[entry.teamID] ?? TeamStandingRow(id: entry.teamID, teamName: entry.teamName)
                row.totalPoints += entry.score
                if let winnerID = match.winnerTeamID {
                    if winnerID == entry.teamID {
                        row.wins += 1
                    } else {
                        row.losses += 1
                    }
                } else {
                    row.ties += 1
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
                            isSelected: selectedGameTypeID == nil
                        ) {
                            selectedGameTypeID = nil
                        }

                        ForEach(gameTypes) { game in
                            FilterPillButton(
                                title: game.name,
                                isSelected: selectedGameTypeID == game.id
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
                                        .foregroundStyle(index == 0 ? Color.yellow : Color.secondary)
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
    @State private var newGameIncrements = "1, 5, 10, -1"
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
                            let trimmed = newTeamName.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            context.insert(Team(name: trimmed))
                            try? context.save()
                            newTeamName = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newTeamName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("Teams (\(teams.count))") {
                    ForEach(teams) { team in
                        Text(team.name)
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(teams[i]) }
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
                        let trimmed = newGameName.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        let target = Int(newGameTargetScore.trimmingCharacters(in: .whitespaces))
                        let maxR = Int(newGameMaxRounds.trimmingCharacters(in: .whitespaces))
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
                        newGameTargetScore = ""
                        newGameMaxRounds = ""
                        newGameCondensedView = true
                    }
                    .disabled(newGameName.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section("Saved Game Types (Tap to Edit)") {
                    ForEach(gameTypes) { game in
                        NavigationLink(destination: EditGameTypeView(gameType: game)) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(game.name)
                                        .font(.headline)
                                    Spacer()
                                    if let target = game.targetScore {
                                        Text("Win: \(target)")
                                            .font(.caption.bold())
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.15), in: Capsule())
                                            .foregroundStyle(Color.blue)
                                    } else if let maxR = game.maxRounds {
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
                        for i in offsets { context.delete(gameTypes[i]) }
                        try? context.save()
                    }
                }
            }
            .navigationTitle("Setup")
        }
    }
}

struct EditGameTypeView: View {
    @Bindable var gameType: GameType
    @Query(sort: \Match.startedAt, order: .reverse) private var allMatches: [Match]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var targetScoreText: String = ""
    @State private var maxRoundsText: String = ""

    var body: some View {
        Form {
            Section("Game Identity") {
                TextField("Game Name", text: $gameType.name)
            }

            Section("Scoring Configuration") {
                Toggle("Condensed View (Hide + / - Buttons)", isOn: $gameType.useCondensedView)

                if !gameType.useCondensedView {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Point Buttons (Comma-Separated)")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                        TextField("e.g. 1, 5, 10, -1", text: $gameType.incrementsRaw)
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

                Toggle("Track Rounds & Ledger", isOn: $gameType.trackRounds)
                Toggle("Lowest Score Wins", isOn: $gameType.lowestScoreWins)
            }
        }
        .navigationTitle("Edit Game Type")
        .onAppear {
            if let target = gameType.targetScore {
                targetScoreText = String(target)
            }
            if let maxR = gameType.maxRounds {
                maxRoundsText = String(maxR)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    gameType.targetScore = Int(targetScoreText.trimmingCharacters(in: .whitespaces))
                    gameType.maxRounds = Int(maxRoundsText.trimmingCharacters(in: .whitespaces))

                    for match in allMatches where match.gameTypeID == gameType.id {
                        match.gameTypeName = gameType.name
                        match.maxRounds = gameType.maxRounds
                        match.useCondensedView = gameType.useCondensedView
                    }
                    try? context.save()
                    dismiss()
                }
                .disabled(gameType.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
