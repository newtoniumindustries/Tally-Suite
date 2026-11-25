import SwiftData
import SwiftUI
import TallyCore

// MARK: - 2. New Game Setup

struct NewGameSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isUsingFallbackStore) private var isUsingFallbackStore

    @AppStorage("tallyCanastaHasSeededDefaultRules") private var hasSeededDefaultRules = false

    @Query(sort: \RuleSet.name) private var ruleSets: [RuleSet]
    @Query(sort: \TallyPlayer.name) private var players: [TallyPlayer]

    @State private var selectedRuleSetID: PersistentIdentifier?
    @State private var showingCustomRuleSheet = false
    @State private var showingManageRuleSets = false
    @State private var showingRuleDetails = false
    @State private var saveErrorMessage: String?

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

    private var trimmedTeams: (t1: String, t2: String, t3: String) {
        (
            team1.trimmingCharacters(in: .whitespacesAndNewlines),
            team2.trimmingCharacters(in: .whitespacesAndNewlines),
            team3.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private var hasDuplicateTeamNames: Bool {
        let active = [trimmedTeams.t1, trimmedTeams.t2, trimmedTeams.t3]
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
        return Set(active).count != active.count
    }

    private var parsedWinningScore: Int? {
        TallyMath.parsePositiveInt(customWinningScore)
    }

    private var isWinningScoreInvalid: Bool {
        let trimmed = customWinningScore.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && parsedWinningScore == nil
    }

    private var canStartGame: Bool {
        selectedRuleSet != nil
            && !trimmedTeams.t1.isEmpty
            && !trimmedTeams.t2.isEmpty
            && !hasDuplicateTeamNames
            && !isWinningScoreInvalid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Teams") {
                    TeamNameInputRow(
                        placeholder: "Team 1 Name",
                        teamName: $team1,
                        players: players
                    )
                    TeamNameInputRow(
                        placeholder: "Team 2 Name",
                        teamName: $team2,
                        players: players
                    )
                    TeamNameInputRow(
                        placeholder: "Team 3 Name (Optional)",
                        teamName: $team3,
                        players: players
                    )

                    if hasDuplicateTeamNames {
                        Text("Each team should have a unique name.")
                            .font(.caption)
                            .foregroundStyle(.red)
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
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    } else {
                        Text("Loading defaults...")
                            .foregroundStyle(.secondary)
                    }

                    Button("Create Custom Rule Set...") { showingCustomRuleSheet = true }

                    if ruleSets.contains(where: { !$0.isBuiltIn }) {
                        Button("Manage Custom Rule Sets...") { showingManageRuleSets = true }
                    }
                }

                Section(
                    header: Text("Winning Score"),
                    footer: Text("Enter a positive target score (e.g., 5000). Adjusting this only affects this game.")
                ) {
                    TextField("Winning Score", text: $customWinningScore)
                        .keyboardType(.numberPad)

                    if isWinningScoreInvalid {
                        Text("Enter a whole number greater than 0.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
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
                    Button("Done") { TallyKeyboard.dismiss() }
                }
            }
            .sheet(isPresented: $showingCustomRuleSheet) {
                CustomRuleSheet(
                    existingRuleSet: nil,
                    existingRuleSets: ruleSets,
                    selectedRuleSetID: $selectedRuleSetID
                ) { createdRules in
                    customWinningScore = String(createdRules.targetScore)
                }
            }
            .sheet(isPresented: $showingManageRuleSets) {
                ManageRuleSetsSheet(selectedRuleSetID: $selectedRuleSetID)
            }
            .sheet(isPresented: $showingRuleDetails) {
                if let rules = selectedRuleSet {
                    RuleDetailsSheet(rules: rules)
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

    private func seedAndSyncRules() {
        if ruleSets.isEmpty {
            let classic = RuleSet.makeClassicPreset()
            let modern = RuleSet.makeModernAmericanPreset()
            modelContext.insert(classic)
            modelContext.insert(modern)
            if let error = modelContext.saveReportingError() {
                saveErrorMessage = error
                return
            }
            if !isUsingFallbackStore {
                hasSeededDefaultRules = true
            }
            selectedRuleSetID = classic.persistentModelID
            customWinningScore = String(classic.targetScore)
        } else {
            // Upgrade existing built-in Modern American preset thresholds if still on old Classic values
            var didUpgradeBuiltIn = false
            for rule in ruleSets where rule.isBuiltIn && rule.name == "Modern American" && rule.meldTier1Requirement == 50 {
                rule.meldBelowZero = 125
                rule.meldTier1Threshold = 3000
                rule.meldTier1Requirement = 125
                rule.meldTier2Threshold = 5000
                rule.meldTier2Requirement = 155
                rule.meldTier3Requirement = 180
                didUpgradeBuiltIn = true
            }
            if didUpgradeBuiltIn {
                modelContext.saveLoggingErrors()
            }
            if !isUsingFallbackStore && !hasSeededDefaultRules {
                hasSeededDefaultRules = true
            }
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
        guard let rules = selectedRuleSet, canStartGame else { return }
        let names = trimmedTeams

        let newGame = CanastaGame(team1Name: names.t1, team2Name: names.t2, team3Name: names.t3, rules: rules)
        newGame.targetScore = parsedWinningScore ?? max(1, rules.targetScore)
        modelContext.insert(newGame)
        if let error = modelContext.saveReportingError() {
            saveErrorMessage = error
            return
        }
        dismiss()
    }
}

private struct TeamNameInputRow: View {
    let placeholder: String
    @Binding var teamName: String
    let players: [TallyPlayer]

    var body: some View {
        HStack {
            TextField(placeholder, text: $teamName)
            if !players.isEmpty {
                Menu {
                    Section("Set Team Name") {
                        ForEach(players) { player in
                            Button(player.name) {
                                teamName = player.name
                            }
                        }
                    }
                    let trimmed = teamName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        Section("Add Partner to \"\(trimmed)\"") {
                            ForEach(players) { player in
                                Button("+ \(player.name)") {
                                    teamName = "\(trimmed) & \(player.name)"
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .foregroundStyle(.tint)
                }
                .accessibilityLabel("Pick player from roster for \(placeholder)")
            }
        }
    }
}

// MARK: - 3. Custom Rule Creator / Editor & Manager

struct ManageRuleSetsSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \RuleSet.name) private var ruleSets: [RuleSet]

    @Binding var selectedRuleSetID: PersistentIdentifier?
    @State private var ruleSetToEdit: RuleSet?
    @State private var saveErrorMessage: String?

    private var customRuleSets: [RuleSet] {
        ruleSets.filter { !$0.isBuiltIn }
    }

    var body: some View {
        NavigationStack {
            List {
                if customRuleSets.isEmpty {
                    Text("No custom rule sets yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(customRuleSets) { rules in
                        Button {
                            ruleSetToEdit = rules
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rules.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("Target: \(rules.targetScore) pts • Pure: \(rules.purePts) • Mixed: \(rules.mixedPts)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteRuleSets)
                }
            }
            .navigationTitle("Custom Rule Sets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $ruleSetToEdit) { rules in
                CustomRuleSheet(
                    existingRuleSet: rules,
                    existingRuleSets: ruleSets,
                    selectedRuleSetID: $selectedRuleSetID
                )
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

    private func deleteRuleSets(offsets: IndexSet) {
        let snapshot = customRuleSets
        let toDelete = offsets.compactMap { snapshot.indices.contains($0) ? snapshot[$0] : nil }
        for rules in toDelete {
            if selectedRuleSetID == rules.persistentModelID {
                selectedRuleSetID = nil
            }
            modelContext.delete(rules)
        }
        if let error = modelContext.saveReportingError() {
            saveErrorMessage = error
        }
    }
}

struct CustomRuleSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var existingRuleSet: RuleSet?
    var existingRuleSets: [RuleSet]
    @Binding var selectedRuleSetID: PersistentIdentifier?
    var onSaved: (RuleSet) -> Void = { _ in }

    @State private var didLoad = false
    @State private var name = ""
    @State private var target = "5000"
    @State private var red3 = "100"
    @State private var mixed = "300"
    @State private var pure = "500"
    @State private var out = "100"
    @State private var outConcealed = "200"
    @State private var joker = "50"
    @State private var deuce = "20"
    @State private var ace = "20"
    @State private var high = "10"
    @State private var low = "5"
    @State private var black3 = "5"

    @State private var meldBelowZero = "15"
    @State private var meldTier1Threshold = "1500"
    @State private var meldTier1Requirement = "50"
    @State private var meldTier2Threshold = "3000"
    @State private var meldTier2Requirement = "90"
    @State private var meldTier3Requirement = "120"

    @State private var saveErrorMessage: String?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicateName: Bool {
        guard !trimmedName.isEmpty else { return false }
        return existingRuleSets.contains { rules in
            if let existingRuleSet, rules.persistentModelID == existingRuleSet.persistentModelID {
                return false
            }
            return rules.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }
    }

    private var areMeldThresholdsOrdered: Bool {
        guard let t1 = TallyMath.parseNonNegativeInt(meldTier1Threshold, max: TallyMath.maxRulePoints),
              let t2 = TallyMath.parseNonNegativeInt(meldTier2Threshold, max: TallyMath.maxRulePoints) else {
            return false
        }
        return t1 < t2
    }

    private var canSave: Bool {
        !trimmedName.isEmpty
            && !isDuplicateName
            && TallyMath.parsePositiveInt(target, max: TallyMath.maxRulePoints) != nil
            && TallyMath.parseNonNegativeInt(red3, max: TallyMath.maxRulePoints) != nil
            && TallyMath.parseNonNegativeInt(mixed, max: TallyMath.maxRulePoints) != nil
            && TallyMath.parseNonNegativeInt(pure, max: TallyMath.maxRulePoints) != nil
            && TallyMath.parseNonNegativeInt(out, max: TallyMath.maxRulePoints) != nil
            && TallyMath.parseNonNegativeInt(outConcealed, max: TallyMath.maxRulePoints) != nil
            && TallyMath.parseNonNegativeInt(joker, max: TallyMath.maxRulePoints) != nil
            && TallyMath.parseNonNegativeInt(deuce, max: TallyMath.maxRulePoints) != nil
            && TallyMath.parseNonNegativeInt(ace, max: TallyMath.maxRulePoints) != nil
            && TallyMath.parseNonNegativeInt(high, max: TallyMath.maxRulePoints) != nil
            && TallyMath.parseNonNegativeInt(low, max: TallyMath.maxRulePoints) != nil
            && TallyMath.parseNonNegativeInt(black3, max: TallyMath.maxRulePoints) != nil
            && TallyMath.parseNonNegativeInt(meldBelowZero, max: TallyMath.maxRulePoints) != nil
            && TallyMath.parseNonNegativeInt(meldTier1Requirement, max: TallyMath.maxRulePoints) != nil
            && TallyMath.parseNonNegativeInt(meldTier2Requirement, max: TallyMath.maxRulePoints) != nil
            && TallyMath.parseNonNegativeInt(meldTier3Requirement, max: TallyMath.maxRulePoints) != nil
            && areMeldThresholdsOrdered
    }

    private func saveRules() {
        guard canSave else { return }
        let targetVal = TallyMath.parsePositiveInt(target, max: TallyMath.maxRulePoints) ?? 5000
        let red3Val = TallyMath.parseNonNegativeInt(red3, max: TallyMath.maxRulePoints) ?? 100
        let mixedVal = TallyMath.parseNonNegativeInt(mixed, max: TallyMath.maxRulePoints) ?? 300
        let pureVal = TallyMath.parseNonNegativeInt(pure, max: TallyMath.maxRulePoints) ?? 500
        let outVal = TallyMath.parseNonNegativeInt(out, max: TallyMath.maxRulePoints) ?? 100
        let outConcealedVal = TallyMath.parseNonNegativeInt(outConcealed, max: TallyMath.maxRulePoints) ?? 200
        let jokerVal = TallyMath.parseNonNegativeInt(joker, max: TallyMath.maxRulePoints) ?? 50
        let deuceVal = TallyMath.parseNonNegativeInt(deuce, max: TallyMath.maxRulePoints) ?? 20
        let aceVal = TallyMath.parseNonNegativeInt(ace, max: TallyMath.maxRulePoints) ?? 20
        let highVal = TallyMath.parseNonNegativeInt(high, max: TallyMath.maxRulePoints) ?? 10
        let lowVal = TallyMath.parseNonNegativeInt(low, max: TallyMath.maxRulePoints) ?? 5
        let black3Val = TallyMath.parseNonNegativeInt(black3, max: TallyMath.maxRulePoints) ?? 5
        let belowZeroVal = TallyMath.parseNonNegativeInt(meldBelowZero, max: TallyMath.maxRulePoints) ?? 15
        let t1ThresholdVal = TallyMath.parseNonNegativeInt(meldTier1Threshold, max: TallyMath.maxRulePoints) ?? 1500
        let t1ReqVal = TallyMath.parseNonNegativeInt(meldTier1Requirement, max: TallyMath.maxRulePoints) ?? 50
        let t2ThresholdVal = TallyMath.parseNonNegativeInt(meldTier2Threshold, max: TallyMath.maxRulePoints) ?? 3000
        let t2ReqVal = TallyMath.parseNonNegativeInt(meldTier2Requirement, max: TallyMath.maxRulePoints) ?? 90
        let t3ReqVal = TallyMath.parseNonNegativeInt(meldTier3Requirement, max: TallyMath.maxRulePoints) ?? 120

        let savedRules: RuleSet
        if let existingRuleSet {
            existingRuleSet.name = trimmedName
            existingRuleSet.targetScore = targetVal
            existingRuleSet.red3Pts = red3Val
            existingRuleSet.mixedPts = mixedVal
            existingRuleSet.purePts = pureVal
            existingRuleSet.outPts = outVal
            existingRuleSet.outConcealedPts = outConcealedVal
            existingRuleSet.jokerPts = jokerVal
            existingRuleSet.deucePts = deuceVal
            existingRuleSet.acePts = aceVal
            existingRuleSet.highCardPts = highVal
            existingRuleSet.lowCardPts = lowVal
            existingRuleSet.black3Pts = black3Val
            existingRuleSet.meldBelowZero = belowZeroVal
            existingRuleSet.meldTier1Threshold = t1ThresholdVal
            existingRuleSet.meldTier1Requirement = t1ReqVal
            existingRuleSet.meldTier2Threshold = t2ThresholdVal
            existingRuleSet.meldTier2Requirement = t2ReqVal
            existingRuleSet.meldTier3Requirement = t3ReqVal
            savedRules = existingRuleSet
        } else {
            let newRules = RuleSet(
                name: trimmedName,
                targetScore: targetVal,
                red3Pts: red3Val,
                mixedPts: mixedVal,
                purePts: pureVal,
                outPts: outVal,
                outConcealedPts: outConcealedVal,
                jokerPts: jokerVal,
                deucePts: deuceVal,
                acePts: aceVal,
                highCardPts: highVal,
                lowCardPts: lowVal,
                black3Pts: black3Val,
                meldBelowZero: belowZeroVal,
                meldTier1Threshold: t1ThresholdVal,
                meldTier1Requirement: t1ReqVal,
                meldTier2Threshold: t2ThresholdVal,
                meldTier2Requirement: t2ReqVal,
                meldTier3Requirement: t3ReqVal,
                isBuiltIn: false
            )
            modelContext.insert(newRules)
            savedRules = newRules
        }

        if let error = modelContext.saveReportingError() {
            saveErrorMessage = error
            return
        }
        selectedRuleSetID = savedRules.persistentModelID
        onSaved(savedRules)
        dismiss()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Settings") {
                    TextField("Configuration Name (e.g., 'House Rules')", text: $name)
                    if isDuplicateName {
                        Text("A ruleset with this name already exists.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
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
                    CustomRuleInputRow(title: "Deuces (2s)", value: $deuce)
                    CustomRuleInputRow(title: "Aces", value: $ace)
                    CustomRuleInputRow(title: "8 through King", value: $high)
                    CustomRuleInputRow(title: "4 through 7", value: $low)
                    CustomRuleInputRow(title: "Black 3s", value: $black3)
                }

                Section(
                    header: Text("Opening Meld Requirements"),
                    footer: Text("Thresholds define when the minimum opening meld increases based on a team's total score.")
                ) {
                    CustomRuleInputRow(title: "Score Below 0", value: $meldBelowZero)
                    CustomRuleInputRow(title: "Tier 1 Max Score", value: $meldTier1Threshold)
                    CustomRuleInputRow(title: "Tier 1 Meld Req", value: $meldTier1Requirement)
                    CustomRuleInputRow(title: "Tier 2 Max Score", value: $meldTier2Threshold)
                    CustomRuleInputRow(title: "Tier 2 Meld Req", value: $meldTier2Requirement)
                    CustomRuleInputRow(title: "Tier 3+ Meld Req", value: $meldTier3Requirement)

                    if !areMeldThresholdsOrdered {
                        Text("Tier 1 Max Score must be less than Tier 2 Max Score.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(existingRuleSet == nil ? "Custom Rules" : "Edit Rules")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !didLoad, let rules = existingRuleSet else { return }
                didLoad = true
                name = rules.name
                target = String(rules.targetScore)
                red3 = String(rules.red3Pts)
                mixed = String(rules.mixedPts)
                pure = String(rules.purePts)
                out = String(rules.outPts)
                outConcealed = String(rules.outConcealedPts)
                joker = String(rules.jokerPts)
                deuce = String(rules.deucePts)
                ace = String(rules.acePts)
                high = String(rules.highCardPts)
                low = String(rules.lowCardPts)
                black3 = String(rules.black3Pts)
                meldBelowZero = String(rules.meldBelowZero)
                meldTier1Threshold = String(rules.meldTier1Threshold)
                meldTier1Requirement = String(rules.meldTier1Requirement)
                meldTier2Threshold = String(rules.meldTier2Threshold)
                meldTier2Requirement = String(rules.meldTier2Requirement)
                meldTier3Requirement = String(rules.meldTier3Requirement)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveRules() }
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
}

// MARK: - 6. Rules Callouts

struct RuleDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var rules: RuleSet

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Game Condition")) {
                    RuleRow(title: "Winning Score", points: rules.targetScore)
                }
                Section(
                    header: Text("Melds & Bonuses"),
                    footer: Text("4 Red 3s double automatically (both positive and negative penalty). Concealed going out replaces the standard going-out bonus.")
                ) {
                    RuleRow(title: "Pure Canasta", points: rules.purePts)
                    RuleRow(title: "Mixed Canasta", points: rules.mixedPts)
                    RuleRow(title: "Red 3", points: rules.red3Pts)
                    RuleRow(title: "Going Out", points: rules.outPts)
                    RuleRow(title: "Going Out Concealed", points: rules.outConcealedPts)
                }
                Section(header: Text("Card Values")) {
                    RuleRow(title: "Jokers", points: rules.jokerPts)
                    RuleRow(title: "Deuces (2s)", points: rules.deucePts)
                    RuleRow(title: "Aces", points: rules.acePts)
                    RuleRow(title: "8 through King", points: rules.highCardPts)
                    RuleRow(title: "4 through 7", points: rules.lowCardPts)
                    RuleRow(title: "Black 3s", points: rules.black3Pts)
                }
                Section(header: Text("Opening Meld Requirements")) {
                    RuleRow(title: "Below 0", points: rules.meldBelowZero)
                    RuleRow(title: "0 to \(max(0, rules.meldTier1Threshold - 1))", points: rules.meldTier1Requirement)
                    RuleRow(title: "\(rules.meldTier1Threshold) to \(max(rules.meldTier1Threshold, rules.meldTier2Threshold - 1))", points: rules.meldTier2Requirement)
                    RuleRow(title: "\(rules.meldTier2Threshold)+", points: rules.meldTier3Requirement)
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
                    RuleSection(title: "Special Cards", content: "• Red 3s: Place face up immediately and draw a replacement. Worth bonus points (or negative points if your team never melds).\n• Black 3s: Can only be melded when going out. Discarding one prevents the next player from taking the pile.\n• Wild Cards (Jokers & 2s): Can be used in melds. Discarding one 'freezes' the pile.")
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
