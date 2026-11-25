import SwiftData
import SwiftUI
import TallyCore

// MARK: - 3. Teams & Game Types Setup (With Editing & Validation)

struct SetupView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Team.name) private var teams: [Team]
    @Query(sort: \GameType.name) private var gameTypes: [GameType]

    @State private var newTeamName = ""
    @State private var teamBeingRenamed: Team?
    @State private var renameTeamText = ""

    @State private var newGameName = ""
    @State private var newGameIncrements = ScoreIncrementParser.defaultRaw
    @State private var newGameTargetScore = ""
    @State private var newGameMaxRounds = ""
    @State private var newGameTrackRounds = true
    @State private var newGameLowestWins = false
    @State private var newGameCondensedView = true

    @State private var saveErrorMessage: String?

    private var trimmedTeamName: String {
        newTeamName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicateTeamName: Bool {
        !trimmedTeamName.isEmpty && teams.contains {
            $0.name.caseInsensitiveCompare(trimmedTeamName) == .orderedSame
        }
    }

    private var trimmedGameName: String {
        newGameName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicateGameName: Bool {
        !trimmedGameName.isEmpty && gameTypes.contains {
            $0.name.caseInsensitiveCompare(trimmedGameName) == .orderedSame
        }
    }

    private var areNewIncrementsInvalid: Bool {
        !newGameCondensedView && ScoreIncrementParser.parseStrict(newGameIncrements).isEmpty
    }

    private var isNewTargetInvalid: Bool {
        let trimmed = newGameTargetScore.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && TallyMath.parsePositiveInt(trimmed) == nil
    }

    private var isNewMaxRoundsInvalid: Bool {
        let trimmed = newGameMaxRounds.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && TallyMath.parsePositiveInt(trimmed) == nil
    }

    private var canSaveNewGame: Bool {
        !trimmedGameName.isEmpty
            && !isDuplicateGameName
            && !areNewIncrementsInvalid
            && !isNewTargetInvalid
            && !isNewMaxRoundsInvalid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Add Team") {
                    HStack {
                        TextField("Team Name", text: $newTeamName)
                            .submitLabel(.done)
                            .onSubmit(addTeam)
                        Button("Add", action: addTeam)
                            .buttonStyle(.borderedProminent)
                            .disabled(trimmedTeamName.isEmpty || isDuplicateTeamName)
                    }

                    if isDuplicateTeamName {
                        Text("A team with this name already exists.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Teams (\(teams.count)) — Tap to Rename") {
                    if teams.isEmpty {
                        Text("No teams added yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(teams) { team in
                            Button {
                                teamBeingRenamed = team
                                renameTeamText = team.name
                            } label: {
                                HStack {
                                    Text(team.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "pencil")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete(perform: deleteTeams)
                    }
                }

                Section("Create New Game Type") {
                    TextField("Game Name (e.g. Darts, Catan)", text: $newGameName)
                    if isDuplicateGameName {
                        Text("A game type with this name already exists.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Toggle("Condensed View (Default)", isOn: $newGameCondensedView)
                    if !newGameCondensedView {
                        TextField("Point Buttons (e.g. 1, 5, 10, -1)", text: $newGameIncrements)
                        if areNewIncrementsInvalid {
                            Text("Enter at least one non-zero comma-separated integer.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    TextField("Amount Needed to Win (Optional)", text: $newGameTargetScore)
                        .keyboardType(.numberPad)
                    if isNewTargetInvalid {
                        Text("Enter a positive whole number or leave blank.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    TextField("Max Rounds to Win (Optional)", text: $newGameMaxRounds)
                        .keyboardType(.numberPad)
                    if isNewMaxRoundsInvalid {
                        Text("Enter a positive whole number or leave blank.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Toggle("Track Rounds & Ledger", isOn: $newGameTrackRounds)
                    Toggle("Lowest Score Wins", isOn: $newGameLowestWins)

                    Button("Save Game Type") {
                        saveNewGameType()
                    }
                    .disabled(!canSaveNewGame)
                }

                Section("Saved Game Types (Tap to Edit)") {
                    ForEach(gameTypes) { game in
                        NavigationLink(destination: EditGameTypeView(gameType: game, existingGameTypes: gameTypes)) {
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
                                            .foregroundStyle(.blue)
                                    } else if let maxR = game.maxRounds, maxR > 0 {
                                        Text("\(maxR) Rounds")
                                            .font(.caption.bold())
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.15), in: Capsule())
                                            .foregroundStyle(.blue)
                                    }
                                }
                                let viewModeLabel = game.useCondensedView ? "Condensed" : "Expanded (\(game.incrementsRaw))"
                                let roundsLabel = game.trackRounds ? "Rounds On" : "Total Only"
                                let winRuleLabel = game.lowestScoreWins ? "Low Wins" : "High Wins"
                                Text("\(viewModeLabel) | \(roundsLabel) | \(winRuleLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .onDelete(perform: deleteGameTypes)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Setup")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { TallyKeyboard.dismiss() }
                }
            }
            .alert(
                "Rename Team",
                isPresented: Binding(
                    get: { teamBeingRenamed != nil },
                    set: { if !$0 { teamBeingRenamed = nil } }
                ),
                presenting: teamBeingRenamed
            ) { team in
                TextField("Team Name", text: $renameTeamText)
                Button("Save") {
                    renameTeam(team, to: renameTeamText)
                    teamBeingRenamed = nil
                }
                Button("Cancel", role: .cancel) {
                    teamBeingRenamed = nil
                }
            } message: { _ in
                Text("Enter a unique name for this team. Existing match entries will also reflect the new name.")
            }
            .alert(
                "Could Not Save",
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "")
            }
        }
    }

    private func addTeam() {
        let trimmed = trimmedTeamName
        guard !trimmed.isEmpty, !isDuplicateTeamName else { return }
        context.insert(Team(name: trimmed))
        if let error = context.saveReportingError() {
            saveErrorMessage = error
            return
        }
        newTeamName = ""
        TallyKeyboard.dismiss()
    }

    private func renameTeam(_ team: Team, to proposedName: String) {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let duplicate = teams.contains {
            $0.id != team.id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard !duplicate else {
            saveErrorMessage = "A team named \"\(trimmed)\" already exists."
            return
        }

        team.name = trimmed
        let targetTeamID = team.id
        let descriptor = FetchDescriptor<MatchScoreEntry>(
            predicate: #Predicate { $0.teamID == targetTeamID }
        )
        if let entries = try? context.fetch(descriptor) {
            for entry in entries {
                entry.teamName = trimmed
            }
        }
        if let error = context.saveReportingError() {
            saveErrorMessage = error
        }
    }

    private func deleteTeams(offsets: IndexSet) {
        let snapshot = teams
        let toDelete = offsets.compactMap { snapshot.indices.contains($0) ? snapshot[$0] : nil }
        for team in toDelete {
            context.delete(team)
        }
        if let error = context.saveReportingError() {
            saveErrorMessage = error
        }
    }

    private func saveNewGameType() {
        guard canSaveNewGame else { return }
        let target = TallyMath.parsePositiveInt(newGameTargetScore)
        let maxR = TallyMath.parsePositiveInt(newGameMaxRounds)
        context.insert(
            GameType(
                name: trimmedGameName,
                incrementsRaw: newGameIncrements,
                targetScore: target,
                maxRounds: maxR,
                lowestScoreWins: newGameLowestWins,
                trackRounds: newGameTrackRounds,
                useCondensedView: newGameCondensedView
            )
        )
        if let error = context.saveReportingError() {
            saveErrorMessage = error
            return
        }
        newGameName = ""
        newGameIncrements = ScoreIncrementParser.defaultRaw
        newGameTargetScore = ""
        newGameMaxRounds = ""
        newGameTrackRounds = true
        newGameLowestWins = false
        newGameCondensedView = true
        TallyKeyboard.dismiss()
    }

    private func deleteGameTypes(offsets: IndexSet) {
        let snapshot = gameTypes
        let toDelete = offsets.compactMap { snapshot.indices.contains($0) ? snapshot[$0] : nil }
        for game in toDelete {
            context.delete(game)
        }
        if let error = context.saveReportingError() {
            saveErrorMessage = error
        }
    }
}

struct EditGameTypeView: View {
    @Bindable var gameType: GameType
    var existingGameTypes: [GameType]

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
    @State private var applyRulesToActiveMatches: Bool = false
    @State private var saveErrorMessage: String?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicateName: Bool {
        !trimmedName.isEmpty && existingGameTypes.contains {
            $0.id != gameType.id && $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }
    }

    private var areIncrementsInvalid: Bool {
        !useCondensedView && ScoreIncrementParser.parseStrict(incrementsRaw).isEmpty
    }

    private var isTargetInvalid: Bool {
        let trimmed = targetScoreText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && TallyMath.parsePositiveInt(trimmed) == nil
    }

    private var isMaxRoundsInvalid: Bool {
        let trimmed = maxRoundsText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && TallyMath.parsePositiveInt(trimmed) == nil
    }

    private var canSave: Bool {
        !trimmedName.isEmpty
            && !isDuplicateName
            && !areIncrementsInvalid
            && !isTargetInvalid
            && !isMaxRoundsInvalid
    }

    var body: some View {
        Form {
            Section("Game Identity") {
                TextField("Game Name", text: $name)
                if isDuplicateName {
                    Text("A game type with this name already exists.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Scoring Configuration") {
                Toggle("Condensed View (Hide + / - Buttons)", isOn: $useCondensedView)

                if !useCondensedView {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Point Buttons (Comma-Separated)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("e.g. 1, 5, 10, -1", text: $incrementsRaw)
                    }
                    if areIncrementsInvalid {
                        Text("Enter at least one non-zero comma-separated integer.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                HStack {
                    Text("Amount Needed to Win")
                    Spacer()
                    TextField("None", text: $targetScoreText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 80, maxWidth: 110)
                }
                if isTargetInvalid {
                    Text("Enter a positive whole number or leave blank.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack {
                    Text("Max Rounds to Win")
                    Spacer()
                    TextField("None", text: $maxRoundsText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 80, maxWidth: 110)
                }
                if isMaxRoundsInvalid {
                    Text("Enter a positive whole number or leave blank.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Toggle("Track Rounds & Ledger", isOn: $trackRounds)
                Toggle("Lowest Score Wins", isOn: $lowestScoreWins)
            }

            Section(
                header: Text("Active Matches"),
                footer: Text("By default, rule changes apply to future matches so custom per-match overrides stay intact. The game name always stays in sync.")
            ) {
                Toggle("Apply Rule Changes to Active Matches", isOn: $applyRulesToActiveMatches)
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
                    saveChanges()
                }
                .disabled(!canSave)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { TallyKeyboard.dismiss() }
            }
        }
        .alert(
            "Could Not Save",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    private func saveChanges() {
        guard canSave else { return }

        gameType.name = trimmedName
        gameType.useCondensedView = useCondensedView
        gameType.incrementsRaw = ScoreIncrementParser.canonicalString(from: incrementsRaw)
        gameType.targetScore = TallyMath.parsePositiveInt(targetScoreText)
        gameType.maxRounds = TallyMath.parsePositiveInt(maxRoundsText)
        gameType.trackRounds = trackRounds
        gameType.lowestScoreWins = lowestScoreWins

        let targetGameTypeID = gameType.id
        let descriptor = FetchDescriptor<Match>(
            predicate: #Predicate { $0.gameTypeID == targetGameTypeID }
        )
        if let matchingMatches = try? context.fetch(descriptor) {
            for match in matchingMatches {
                match.gameTypeName = trimmedName
                if applyRulesToActiveMatches && !match.isCompleted {
                    match.useCondensedView = gameType.useCondensedView
                    match.incrementsRaw = gameType.incrementsRaw
                    match.targetScore = gameType.targetScore
                    match.lowestScoreWins = gameType.lowestScoreWins
                    if let newMaxR = gameType.maxRounds {
                        match.maxRounds = max(newMaxR, match.completedRoundCount)
                    } else {
                        match.maxRounds = nil
                    }
                    if !match.trackRounds && gameType.trackRounds {
                        for entry in match.entries {
                            let historySum = TallyMath.sum(entry.roundHistory)
                            entry.currentRoundDelta = TallyMath.subtract(entry.score, historySum)
                        }
                    }
                    match.trackRounds = gameType.trackRounds
                }
            }
        }

        if let error = context.saveReportingError() {
            saveErrorMessage = error
            return
        }
        dismiss()
    }
}
