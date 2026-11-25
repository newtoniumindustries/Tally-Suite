import SwiftData
import SwiftUI
import TallyCore

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
    @State private var saveErrorMessage: String?

    private var selectedGameType: GameType? {
        if let id = selectedGameTypeID {
            return gameTypes.first(where: { $0.id == id })
        }
        return gameTypes.first
    }

    private var isTargetInvalid: Bool {
        let trimmed = customTargetScoreText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && TallyMath.parsePositiveInt(trimmed) == nil
    }

    private var isMaxRoundsInvalid: Bool {
        let trimmed = customMaxRoundsText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && TallyMath.parsePositiveInt(trimmed) == nil
    }

    private var canStart: Bool {
        selectedGameType != nil
            && selectedTeamIDs.count >= 2
            && !isTargetInvalid
            && !isMaxRoundsInvalid
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
                            TextField("Optional", text: $customMaxRoundsText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(minWidth: 80, maxWidth: 110)
                        }
                        if isMaxRoundsInvalid {
                            Text("Enter a positive whole number or leave blank.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Toggle("Condensed View (Hide + / - Buttons)", isOn: $useCondensedView)
                    } else {
                        Text("No game types saved yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        CreateGameTypeInlineView(existingGameTypes: gameTypes) { createdGame in
                            selectedGameTypeID = createdGame.id
                            applyGameTypeDefaults(createdGame)
                        }
                    } label: {
                        Label("Create New Game Type", systemImage: "plus.circle")
                            .foregroundStyle(.tint)
                    }
                }

                Section("Select Teams (2 or More)") {
                    if teams.isEmpty {
                        Text("No teams saved. Add teams in the Setup tab first.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(teams) { team in
                            let isSelected = selectedTeamIDs.contains(team.id)
                            Button {
                                if isSelected {
                                    selectedTeamIDs.remove(team.id)
                                } else {
                                    selectedTeamIDs.insert(team.id)
                                }
                            } label: {
                                HStack {
                                    Text(team.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                    .disabled(!canStart)
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
        guard let game = selectedGameType, canStart else { return }
        let chosenTeams = teams.filter { selectedTeamIDs.contains($0.id) }
        guard chosenTeams.count >= 2 else { return }

        let entries = chosenTeams.enumerated().map { index, team in
            MatchScoreEntry(teamID: team.id, teamName: team.name, score: 0, sortOrder: index)
        }
        let match = Match(gameType: game, entries: entries)
        match.targetScore = TallyMath.parsePositiveInt(customTargetScoreText)
        match.maxRounds = TallyMath.parsePositiveInt(customMaxRoundsText)
        match.useCondensedView = useCondensedView
        context.insert(match)
        if let error = context.saveReportingError() {
            saveErrorMessage = error
            return
        }
        dismiss()
    }
}

struct CreateGameTypeInlineView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var existingGameTypes: [GameType]
    var onCreated: (GameType) -> Void

    @State private var name = ""
    @State private var increments = ScoreIncrementParser.defaultRaw
    @State private var target = ""
    @State private var maxRounds = ""
    @State private var trackRounds = true
    @State private var lowWins = false
    @State private var useCondensedView = true
    @State private var saveErrorMessage: String?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicateName: Bool {
        !trimmedName.isEmpty && existingGameTypes.contains {
            $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }
    }

    private var areIncrementsInvalid: Bool {
        !useCondensedView && ScoreIncrementParser.parseStrict(increments).isEmpty
    }

    private var isTargetInvalid: Bool {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && TallyMath.parsePositiveInt(trimmed) == nil
    }

    private var isMaxRoundsInvalid: Bool {
        let trimmed = maxRounds.trimmingCharacters(in: .whitespacesAndNewlines)
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
            Section("New Game Details") {
                TextField("Game Name", text: $name)
                if isDuplicateName {
                    Text("A game type with this name already exists.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Toggle("Condensed View (Default)", isOn: $useCondensedView)
                if !useCondensedView {
                    TextField("Point Buttons (e.g. 1, 5, 10, -1)", text: $increments)
                    if areIncrementsInvalid {
                        Text("Enter at least one non-zero comma-separated integer.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                TextField("Amount Needed to Win (Optional)", text: $target)
                    .keyboardType(.numberPad)
                if isTargetInvalid {
                    Text("Enter a positive whole number or leave blank.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                TextField("Max Rounds to Win (Optional)", text: $maxRounds)
                    .keyboardType(.numberPad)
                if isMaxRoundsInvalid {
                    Text("Enter a positive whole number or leave blank.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Toggle("Track Rounds & Ledger", isOn: $trackRounds)
                Toggle("Lowest Score Wins", isOn: $lowWins)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Create Game Type")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard canSave else { return }
                    let newGame = GameType(
                        name: trimmedName,
                        incrementsRaw: increments,
                        targetScore: TallyMath.parsePositiveInt(target),
                        maxRounds: TallyMath.parsePositiveInt(maxRounds),
                        lowestScoreWins: lowWins,
                        trackRounds: trackRounds,
                        useCondensedView: useCondensedView
                    )
                    context.insert(newGame)
                    if let error = context.saveReportingError() {
                        saveErrorMessage = error
                        return
                    }
                    onCreated(newGame)
                    dismiss()
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
}
