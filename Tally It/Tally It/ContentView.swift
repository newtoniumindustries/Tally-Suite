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

    private var activeMatches: [Match] {
        matches.filter { !$0.isCompleted }
    }

    var body: some View {
        NavigationStack {
            Group {
                if activeMatches.isEmpty {
                    ContentUnavailableView(
                        "No Active Game",
                        systemImage: "flag.2.crossed.fill",
                        description: Text("Start a new match and pick your teams and game rules.")
                    )
                } else {
                    List {
                        ForEach(activeMatches) { match in
                            NavigationLink(destination: LiveScoreboardView(match: match)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(match.gameTypeName)
                                            .font(.headline)
                                        Spacer()
                                        if match.trackRounds {
                                            Text("Round \(match.currentRound)")
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
                                    Text(match.sortedEntries.map { "\($0.teamName): \($0.score)" }.joined(separator: "  •  "))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
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
            }
            .navigationTitle("Tally: It")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        seedDefaultsIfNeeded()
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
        if gameTypes.isEmpty {
            context.insert(GameType(name: "Cornhole", incrementsRaw: "1, 3, -1", targetScore: 21, trackRounds: true))
            context.insert(GameType(name: "Canasta / Cards", incrementsRaw: "5, 10, 20, 100, -5", targetScore: 5000, trackRounds: true))
        }
        if teams.isEmpty {
            context.insert(Team(name: "Team Alpha"))
            context.insert(Team(name: "Team Bravo"))
        }
        try? context.save()
    }
}

struct NewMatchSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \GameType.name) private var gameTypes: [GameType]
    @Query(sort: \Team.name) private var teams: [Team]

    @State private var selectedGameType: GameType?
    @State private var selectedTeamIDs: Set<UUID> = []
    @State private var customTargetScoreText: String = ""

    // State for creating a game type inline if none exist
    @State private var showingInlineGameCreator = false
    @State private var newGameName = ""
    @State private var newGameIncrements = "1, 5, 10, -1"
    @State private var newGameTarget = ""
    @State private var newGameTrackRounds = true
    @State private var newGameLowWins = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Game Type") {
                    if gameTypes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No game types saved yet.")
                                .font(.subheadline)
                                .foregroundStyle(Color.secondary)
                            Button("Create New Game Type") {
                                showingInlineGameCreator = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 4)
                    } else {
                        Picker("Game", selection: $selectedGameType) {
                            ForEach(gameTypes) { game in
                                Text(game.name).tag(Optional(game))
                            }
                        }
                        .onChange(of: selectedGameType) { _, newValue in
                            if let target = newValue?.targetScore {
                                customTargetScoreText = String(target)
                            } else {
                                customTargetScoreText = ""
                            }
                        }

                        HStack {
                            Text("Amount Needed to Win")
                            Spacer()
                            TextField("Optional", text: $customTargetScoreText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                        }
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
                                    if selectedTeamIDs.contains(team.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.blue)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundStyle(Color.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Match")
            .onAppear {
                if gameTypes.isEmpty {
                    seedDefaultsIfNeeded()
                }
                if selectedGameType == nil, let first = gameTypes.first {
                    selectedGameType = first
                    if let target = first.targetScore {
                        customTargetScoreText = String(target)
                    }
                }
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
            .sheet(isPresented: $showingInlineGameCreator) {
                NavigationStack {
                    Form {
                        Section("New Game Details") {
                            TextField("Game Name", text: $newGameName)
                            TextField("Point Buttons (e.g. 1, 5, 10, -1)", text: $newGameIncrements)
                            TextField("Win Target (Optional)", text: $newGameTarget)
                                .keyboardType(.numberPad)
                            Toggle("Track Rounds & Ledger", isOn: $newGameTrackRounds)
                            Toggle("Lowest Score Wins", isOn: $newGameLowWins)
                        }
                    }
                    .navigationTitle("Create Game Type")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingInlineGameCreator = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                let trimmed = newGameName.trimmingCharacters(in: .whitespaces)
                                guard !trimmed.isEmpty else { return }
                                let targetVal = Int(newGameTarget.trimmingCharacters(in: .whitespaces))
                                let newGame = GameType(
                                    name: trimmed,
                                    incrementsRaw: newGameIncrements,
                                    targetScore: targetVal,
                                    lowestScoreWins: newGameLowWins,
                                    trackRounds: newGameTrackRounds
                                )
                                context.insert(newGame)
                                try? context.save()
                                selectedGameType = newGame
                                if let target = newGame.targetScore {
                                    customTargetScoreText = String(target)
                                }
                                showingInlineGameCreator = false
                                newGameName = ""
                                newGameTarget = ""
                            }
                            .disabled(newGameName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            }
        }
    }

    private func seedDefaultsIfNeeded() {
        if gameTypes.isEmpty {
            let defaultGame = GameType(name: "Cornhole", incrementsRaw: "1, 3, -1", targetScore: 21, trackRounds: true)
            context.insert(defaultGame)
        }
        if teams.isEmpty {
            context.insert(Team(name: "Team Alpha"))
            context.insert(Team(name: "Team Bravo"))
        }
        try? context.save()
    }

    private func startMatch() {
        guard let game = selectedGameType else { return }
        let chosenTeams = teams.filter { selectedTeamIDs.contains($0.id) }
        let entries = chosenTeams.enumerated().map { index, team in
            MatchScoreEntry(teamID: team.id, teamName: team.name, score: 0, sortOrder: index)
        }
        let match = Match(gameType: game, entries: entries)
        let trimmedTarget = customTargetScoreText.trimmingCharacters(in: .whitespaces)
        match.targetScore = Int(trimmedTarget)
        context.insert(match)
        try? context.save()
        dismiss()
    }
}

struct LiveScoreboardView: View {
    @Bindable var match: Match
    @Environment(\.dismiss) private var dismiss
    @State private var showingRulesSheet = false
    @State private var showingRoundLedger = true

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if match.trackRounds {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ROUND \(match.currentRound)")
                                    .font(.caption.weight(.heavy))
                                    .foregroundStyle(Color.blue)
                                if let target = match.targetScore {
                                    Label("Goal: \(target) pts (\(match.lowestScoreWins ? "Low Wins" : "High Wins"))", systemImage: "flag.checkered")
                                        .font(.subheadline.bold())
                                } else {
                                    Text(match.lowestScoreWins ? "Lowest Score Wins" : "Highest Score Wins")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.secondary)
                                }
                            }

                            Spacer()

                            if !match.isCompleted {
                                Button {
                                    advanceRound()
                                } label: {
                                    Label("Next Round", systemImage: "arrow.right.circle.fill")
                                        .font(.subheadline.bold())
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Color.blue, in: Capsule())
                                        .foregroundStyle(Color.white)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
                } else {
                    if let target = match.targetScore {
                        HStack {
                            Label("Goal: \(target) pts (\(match.lowestScoreWins ? "Low Wins" : "High Wins"))", systemImage: "flag.checkered")
                                .font(.subheadline.bold())
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                }

                let winners = match.winningEntries
                if !winners.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "trophy.fill")
                            .font(.title2)
                            .foregroundStyle(Color.yellow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Target Reached!")
                                .font(.caption.weight(.heavy))
                                .textCase(.uppercase)
                            Text("\(winners.map(\.teamName).joined(separator: " & ")) in the lead!")
                                .font(.headline)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color.green.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.green, lineWidth: 2)
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
                        isWinnerHighlighted: match.isTargetWinner(entry)
                    )
                }

                if match.trackRounds && (match.currentRound > 1 || match.sortedEntries.contains(where: { $0.currentRoundDelta != 0 })) {
                    RoundLedgerSection(match: match, isExpanded: $showingRoundLedger)
                        .padding(.horizontal)
                }

                if !match.isCompleted {
                    Button {
                        completeMatch()
                    } label: {
                        Label("Finish Match & Record Standings", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(winners.isEmpty ? Color.blue : Color.green)
                            .foregroundStyle(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                } else {
                    Text("Match Completed")
                        .font(.headline)
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(.vertical)
        }
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
        withAnimation {
            for entry in match.entries {
                entry.roundHistory.append(entry.currentRoundDelta)
                entry.currentRoundDelta = 0
            }
            match.currentRound += 1
        }
    }

    private func completeMatch() {
        if match.trackRounds && match.entries.contains(where: { $0.currentRoundDelta != 0 }) {
            for entry in match.entries {
                entry.roundHistory.append(entry.currentRoundDelta)
                entry.currentRoundDelta = 0
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
        dismiss()
    }
}

struct TeamScoreCard: View {
    @Bindable var entry: MatchScoreEntry
    let increments: [Int]
    let currentRound: Int
    let targetScore: Int?
    let trackRounds: Bool
    let isWinnerHighlighted: Bool

    @State private var customInputText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(entry.teamName)
                            .font(.title3.bold())
                        if isWinnerHighlighted {
                            Label("WINNER", systemImage: "crown.fill")
                                .font(.caption2.weight(.heavy))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green, in: Capsule())
                                .foregroundStyle(Color.white)
                        }
                    }

                    if trackRounds {
                        HStack(spacing: 8) {
                            let sign = entry.currentRoundDelta >= 0 ? "+" : ""
                            Text("Round \(currentRound): \(sign)\(entry.currentRoundDelta)")
                                .font(.caption.bold())
                                .foregroundStyle(Color.secondary)

                            if let target = targetScore, !isWinnerHighlighted {
                                let remaining = max(0, target - entry.score)
                                if remaining > 0 {
                                    Text("• \(remaining) to go")
                                        .font(.caption)
                                        .foregroundStyle(Color.secondary)
                                }
                            }
                        }
                    } else if let target = targetScore, !isWinnerHighlighted {
                        let remaining = max(0, target - entry.score)
                        if remaining > 0 {
                            Text("\(remaining) points to go")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }

                Spacer()

                Text("\(entry.score)")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(isWinnerHighlighted ? Color.green : Color.primary)
                    .contentTransition(.numericText())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(increments, id: \.self) { delta in
                        Button {
                            withAnimation {
                                entry.score += delta
                                if trackRounds {
                                    entry.currentRoundDelta += delta
                                }
                            }
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

            HStack(spacing: 8) {
                TextField("Custom pts (+/- or exact)", text: $customInputText)
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder)

                Button("Add") {
                    if let val = Int(customInputText.trimmingCharacters(in: .whitespaces)) {
                        withAnimation {
                            entry.score += val
                            if trackRounds {
                                entry.currentRoundDelta += val
                            }
                        }
                        customInputText = ""
                    }
                }
                .buttonStyle(.bordered)
                .tint(.blue)

                Button("Set Total") {
                    if let val = Int(customInputText.trimmingCharacters(in: .whitespaces)) {
                        withAnimation {
                            let diff = val - entry.score
                            entry.score = val
                            if trackRounds {
                                entry.currentRoundDelta += diff
                            }
                        }
                        customInputText = ""
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(
            isWinnerHighlighted
                ? Color.green.opacity(0.12)
                : Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isWinnerHighlighted ? Color.green : Color.clear, lineWidth: 2.5)
        )
        .padding(.horizontal)
    }
}

struct RoundLedgerSection: View {
    let match: Match
    @Binding var isExpanded: Bool

    private var completedRoundsArray: [Int] {
        let count = match.sortedEntries.map { $0.roundHistory.count }.max() ?? 0
        return Array(0..<count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    Label("Round History Ledger", systemImage: "list.number")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
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
                            Text(val >= 0 ? "+\(val)" : "\(val)")
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(val >= 0 ? Color.primary : Color.red)
                                .frame(maxWidth: .infinity, alignment: .trailing)
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
}

struct AdjustMatchScoringSheet: View {
    @Bindable var match: Match
    @Environment(\.dismiss) private var dismiss
    @State private var targetText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Point Buttons (Comma-Separated)") {
                    TextField("e.g. 1, 5, 10, -1", text: $match.incrementsRaw)
                }
                Section("Amount Needed to Win") {
                    TextField("Leave blank for no target", text: $targetText)
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
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let trimmed = targetText.trimmingCharacters(in: .whitespaces)
                        match.targetScore = Int(trimmed)
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
                            withAnimation { selectedGameTypeID = nil }
                        }

                        ForEach(gameTypes) { game in
                            FilterPillButton(
                                title: game.name,
                                isSelected: selectedGameTypeID == game.id
                            ) {
                                withAnimation { selectedGameTypeID = game.id }
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
                                StatSummaryBox(title: "Top Team", value: standings.first?.teamName ?? "—")
                            }
                            .padding(.vertical, 4)
                        }

                        Section("Leaderboard") {
                            ForEach(Array(standings.enumerated()), id: \.element.id) { index, row in
                                HStack(spacing: 12) {
                                    Text("#\(index + 1)")
                                        .font(.subheadline.weight(.heavy))
                                        .foregroundStyle(index == 0 ? Color.yellow : Color.secondary)
                                        .frame(width: 32, alignment: .leading)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(row.teamName)
                                            .font(.headline)
                                        Text("\(row.gamesPlayed) Played  •  \(row.totalPoints) Total Pts")
                                            .font(.caption)
                                            .foregroundStyle(Color.secondary)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text("\(row.wins)W - \(row.losses)L" + (row.ties > 0 ? " - \(row.ties)T" : ""))
                                            .font(.subheadline.bold())
                                        Text(String(format: "%.0f%% Win", row.winPercentage * 100))
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
        .buttonStyle(.plain)
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
    @State private var newGameTrackRounds = true
    @State private var newGameLowestWins = false

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
                    TextField("Point Buttons (e.g. 1, 5, 10, -1)", text: $newGameIncrements)
                    TextField("Amount Needed to Win (Optional)", text: $newGameTargetScore)
                        .keyboardType(.numberPad)
                    Toggle("Track Rounds & Ledger", isOn: $newGameTrackRounds)
                    Toggle("Lowest Score Wins", isOn: $newGameLowestWins)

                    Button("Save Game Type") {
                        let trimmed = newGameName.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        let target = Int(newGameTargetScore.trimmingCharacters(in: .whitespaces))
                        context.insert(
                            GameType(
                                name: trimmed,
                                incrementsRaw: newGameIncrements,
                                targetScore: target,
                                lowestScoreWins: newGameLowestWins,
                                trackRounds: newGameTrackRounds
                            )
                        )
                        try? context.save()
                        newGameName = ""
                        newGameTargetScore = ""
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
                                    }
                                }
                                Text("Buttons: \(game.incrementsRaw) • \(game.trackRounds ? "Rounds On" : "Total Only") • \(game.lowestScoreWins ? "Low Wins" : "High Wins")")
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
    @Environment(\.dismiss) private var dismiss

    @State private var targetScoreText: String = ""

    var body: some View {
        Form {
            Section("Game Identity") {
                TextField("Game Name", text: $gameType.name)
            }

            Section("Scoring Configuration") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Point Buttons (Comma-Separated)")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                    TextField("e.g. 1, 5, 10, -1", text: $gameType.incrementsRaw)
                }

                HStack {
                    Text("Amount Needed to Win")
                    Spacer()
                    TextField("None", text: $targetScoreText)
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
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let trimmedTarget = targetScoreText.trimmingCharacters(in: .whitespaces)
                    gameType.targetScore = Int(trimmedTarget)

                    for match in allMatches where match.gameTypeID == gameType.id {
                        match.gameTypeName = gameType.name
                    }
                    dismiss() // Corrected here
                }
                .disabled(gameType.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
