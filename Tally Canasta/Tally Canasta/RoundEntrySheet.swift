import SwiftData
import SwiftUI
import TallyCore

// MARK: - Temporary Form State (Delegates Scoring to Unified CanastaScorer)

struct DraftRoundData {
    var team1 = CanastaTeamRoundInput()
    var team2 = CanastaTeamRoundInput()
    var team3 = CanastaTeamRoundInput()

    init() {}

    init(from round: Round) {
        self.team1 = round.input(for: .team1)
        self.team2 = round.input(for: .team2)
        self.team3 = round.input(for: .team3)
    }

    func apply(to round: Round) {
        round.apply(team1, for: .team1)
        round.apply(team2, for: .team2)
        round.apply(team3, for: .team3)
    }

    func total(for slot: CanastaTeamSlot, game: CanastaGame) -> Int {
        let input: CanastaTeamRoundInput
        switch slot {
        case .team1: input = team1
        case .team2: input = team2
        case .team3: input = team3
        }
        return CanastaScorer.roundTotal(for: input, rules: game.scoringRules)
    }

    mutating func setWentOut(_ isOn: Bool, concealed: Bool, for slot: CanastaTeamSlot) {
        if isOn {
            // Only one team can go out in a Canasta round, and Concealed replaces Went Out
            team1.wentOut = false
            team1.wentOutConcealed = false
            team2.wentOut = false
            team2.wentOutConcealed = false
            team3.wentOut = false
            team3.wentOutConcealed = false
        }
        switch slot {
        case .team1:
            if concealed { team1.wentOutConcealed = isOn } else { team1.wentOut = isOn }
        case .team2:
            if concealed { team2.wentOutConcealed = isOn } else { team2.wentOut = isOn }
        case .team3:
            if concealed { team3.wentOutConcealed = isOn } else { team3.wentOut = isOn }
        }
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
    @State private var saveErrorMessage: String?

    private func saveRound() {
        if let round = editingRound {
            draft.apply(to: round)
        } else {
            let nextRoundNumber = (game.rounds.map(\.roundNumber).max() ?? 0) + 1
            let newRound = Round(roundNumber: nextRoundNumber)
            draft.apply(to: newRound)
            modelContext.insert(newRound)
            game.rounds.append(newRound)
        }
        if let error = modelContext.saveReportingError() {
            saveErrorMessage = error
            return
        }
        dismiss()
    }

    private func wentOutBinding(for slot: CanastaTeamSlot, concealed: Bool) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                let input: CanastaTeamRoundInput
                switch slot {
                case .team1: input = draft.team1
                case .team2: input = draft.team2
                case .team3: input = draft.team3
                }
                return concealed ? input.wentOutConcealed : input.wentOut
            },
            set: { newValue in
                draft.setWentOut(newValue, concealed: concealed, for: slot)
            }
        )
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                // PAGE 1: Teams 1 & 2
                Form {
                    HStack {
                        Color.clear.frame(width: 84, height: 1)
                        Text(game.team1Name)
                            .bold()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                        Text(game.team2Name)
                            .bold()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                        if game.isThreeTeams {
                            Button(action: { withAnimation { selectedTab = 1 } }) {
                                Image(systemName: "chevron.right.circle.fill")
                                    .foregroundStyle(.tint)
                                    .imageScale(.large)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Next page: \(game.team3Name)")
                        }
                    }

                    Section(
                        header: Text("Canastas & Bonuses"),
                        footer: Text("Only one team can go out per round; Concealed replaces standard Going Out. Use negative Red 3s if a team never melded; 4+ Red 3s double automatically.")
                    ) {
                        TwoTeamScoreRow(
                            title: "Pure",
                            subtitle: "Canasta",
                            team1Label: game.team1Name,
                            team2Label: game.team2Name,
                            count1: $draft.team1.pureCanastas,
                            count2: $draft.team2.pureCanastas
                        )
                        TwoTeamScoreRow(
                            title: "Mixed",
                            subtitle: "Canasta",
                            team1Label: game.team1Name,
                            team2Label: game.team2Name,
                            count1: $draft.team1.mixedCanastas,
                            count2: $draft.team2.mixedCanastas
                        )
                        TwoTeamScoreRow(
                            title: "Red 3s",
                            subtitle: "2x at ±4+",
                            team1Label: game.team1Name,
                            team2Label: game.team2Name,
                            range: CanastaScorer.minRed3Count...CanastaScorer.maxRed3Count,
                            count1: $draft.team1.red3s,
                            count2: $draft.team2.red3s
                        )

                        HStack {
                            Text("Went Out")
                                .frame(width: 84, alignment: .leading)
                            Toggle("\(game.team1Name) Went Out", isOn: wentOutBinding(for: .team1, concealed: false))
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel("\(game.team1Name) Went Out")
                            Toggle("\(game.team2Name) Went Out", isOn: wentOutBinding(for: .team2, concealed: false))
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel("\(game.team2Name) Went Out")
                        }
                        HStack {
                            Text("Concealed")
                                .frame(width: 84, alignment: .leading)
                            Toggle("\(game.team1Name) Went Out Concealed", isOn: wentOutBinding(for: .team1, concealed: true))
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel("\(game.team1Name) Went Out Concealed")
                            Toggle("\(game.team2Name) Went Out Concealed", isOn: wentOutBinding(for: .team2, concealed: true))
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel("\(game.team2Name) Went Out Concealed")
                        }
                    }

                    Section(
                        header: Text("Melded Cards (Positive Points)"),
                        footer: Text("Enter the total number of each card type melded on the table.")
                    ) {
                        TwoTeamScoreRow(title: "Jokers", subtitle: "\(game.jokerPts) pts/ea", team1Label: game.team1Name, team2Label: game.team2Name, count1: $draft.team1.jokers, count2: $draft.team2.jokers)
                        TwoTeamScoreRow(title: "Deuces (2s)", subtitle: "\(game.deucePts) pts/ea", team1Label: game.team1Name, team2Label: game.team2Name, count1: $draft.team1.deuces, count2: $draft.team2.deuces)
                        TwoTeamScoreRow(title: "Aces", subtitle: "\(game.acePts) pts/ea", team1Label: game.team1Name, team2Label: game.team2Name, count1: $draft.team1.aces, count2: $draft.team2.aces)
                        TwoTeamScoreRow(title: "8 thru King", subtitle: "\(game.highCardPts) pts/ea", team1Label: game.team1Name, team2Label: game.team2Name, count1: $draft.team1.highCards, count2: $draft.team2.highCards)
                        TwoTeamScoreRow(title: "4 thru 7", subtitle: "\(game.lowCardPts) pts/ea", team1Label: game.team1Name, team2Label: game.team2Name, count1: $draft.team1.lowCards, count2: $draft.team2.lowCards)
                        TwoTeamScoreRow(title: "Black 3s", subtitle: "\(game.black3Pts) pts/ea", team1Label: game.team1Name, team2Label: game.team2Name, count1: $draft.team1.black3s, count2: $draft.team2.black3s)
                    }

                    Section(
                        header: Text("Cards In Hand (Penalty)"),
                        footer: Text("Points for these cards will be automatically subtracted from the total.")
                    ) {
                        TwoTeamScoreRow(title: "Jokers", subtitle: "-\(game.jokerPts) pts/ea", team1Label: game.team1Name, team2Label: game.team2Name, count1: $draft.team1.jokersInHand, count2: $draft.team2.jokersInHand)
                        TwoTeamScoreRow(title: "Deuces (2s)", subtitle: "-\(game.deucePts) pts/ea", team1Label: game.team1Name, team2Label: game.team2Name, count1: $draft.team1.deucesInHand, count2: $draft.team2.deucesInHand)
                        TwoTeamScoreRow(title: "Aces", subtitle: "-\(game.acePts) pts/ea", team1Label: game.team1Name, team2Label: game.team2Name, count1: $draft.team1.acesInHand, count2: $draft.team2.acesInHand)
                        TwoTeamScoreRow(title: "8 thru King", subtitle: "-\(game.highCardPts) pts/ea", team1Label: game.team1Name, team2Label: game.team2Name, count1: $draft.team1.highCardsInHand, count2: $draft.team2.highCardsInHand)
                        TwoTeamScoreRow(title: "4 thru 7", subtitle: "-\(game.lowCardPts) pts/ea", team1Label: game.team1Name, team2Label: game.team2Name, count1: $draft.team1.lowCardsInHand, count2: $draft.team2.lowCardsInHand)
                        TwoTeamScoreRow(title: "Black 3s", subtitle: "-\(game.black3Pts) pts/ea", team1Label: game.team1Name, team2Label: game.team2Name, count1: $draft.team1.black3sInHand, count2: $draft.team2.black3sInHand)
                    }

                    Section(header: Text("Live Round Totals")) {
                        HStack {
                            VStack(spacing: 2) {
                                Text(game.team1Name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Text("\(draft.total(for: .team1, game: game))").bold().monospacedDigit()
                            }
                            .frame(maxWidth: .infinity)
                            VStack(spacing: 2) {
                                Text(game.team2Name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Text("\(draft.total(for: .team2, game: game))").bold().monospacedDigit()
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .tag(0)

                // PAGE 2: Team 3
                if game.isThreeTeams {
                    Form {
                        HStack {
                            Button(action: { withAnimation { selectedTab = 0 } }) {
                                Image(systemName: "chevron.left.circle.fill")
                                    .foregroundStyle(.tint)
                                    .imageScale(.large)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Previous page: \(game.team1Name) and \(game.team2Name)")

                            Text(game.team3Name)
                                .bold()
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)

                            Image(systemName: "chevron.right.circle.fill")
                                .opacity(0)
                                .accessibilityHidden(true)
                        }

                        Section(
                            header: Text("Canastas & Bonuses"),
                            footer: Text("Only one team can go out per round; Concealed replaces standard Going Out. Use negative Red 3s if a team never melded; 4+ Red 3s double automatically.")
                        ) {
                            OneTeamScoreRow(title: "Pure", subtitle: "Canasta", teamLabel: game.team3Name, count: $draft.team3.pureCanastas)
                            OneTeamScoreRow(title: "Mixed", subtitle: "Canasta", teamLabel: game.team3Name, count: $draft.team3.mixedCanastas)
                            OneTeamScoreRow(
                                title: "Red 3s",
                                subtitle: "2x at ±4+",
                                teamLabel: game.team3Name,
                                range: CanastaScorer.minRed3Count...CanastaScorer.maxRed3Count,
                                count: $draft.team3.red3s
                            )

                            HStack {
                                Text("Went Out")
                                Spacer()
                                Toggle("\(game.team3Name) Went Out", isOn: wentOutBinding(for: .team3, concealed: false))
                                    .labelsHidden()
                                    .accessibilityLabel("\(game.team3Name) Went Out")
                            }
                            HStack {
                                Text("Concealed")
                                Spacer()
                                Toggle("\(game.team3Name) Went Out Concealed", isOn: wentOutBinding(for: .team3, concealed: true))
                                    .labelsHidden()
                                    .accessibilityLabel("\(game.team3Name) Went Out Concealed")
                            }
                        }

                        Section(
                            header: Text("Melded Cards (Positive Points)"),
                            footer: Text("Enter the total number of each card type melded on the table.")
                        ) {
                            OneTeamScoreRow(title: "Jokers", subtitle: "\(game.jokerPts) pts/ea", teamLabel: game.team3Name, count: $draft.team3.jokers)
                            OneTeamScoreRow(title: "Deuces (2s)", subtitle: "\(game.deucePts) pts/ea", teamLabel: game.team3Name, count: $draft.team3.deuces)
                            OneTeamScoreRow(title: "Aces", subtitle: "\(game.acePts) pts/ea", teamLabel: game.team3Name, count: $draft.team3.aces)
                            OneTeamScoreRow(title: "8 thru King", subtitle: "\(game.highCardPts) pts/ea", teamLabel: game.team3Name, count: $draft.team3.highCards)
                            OneTeamScoreRow(title: "4 thru 7", subtitle: "\(game.lowCardPts) pts/ea", teamLabel: game.team3Name, count: $draft.team3.lowCards)
                            OneTeamScoreRow(title: "Black 3s", subtitle: "\(game.black3Pts) pts/ea", teamLabel: game.team3Name, count: $draft.team3.black3s)
                        }

                        Section(
                            header: Text("Cards In Hand (Penalty)"),
                            footer: Text("Points for these cards will be automatically subtracted from the total.")
                        ) {
                            OneTeamScoreRow(title: "Jokers", subtitle: "-\(game.jokerPts) pts/ea", teamLabel: game.team3Name, count: $draft.team3.jokersInHand)
                            OneTeamScoreRow(title: "Deuces (2s)", subtitle: "-\(game.deucePts) pts/ea", teamLabel: game.team3Name, count: $draft.team3.deucesInHand)
                            OneTeamScoreRow(title: "Aces", subtitle: "-\(game.acePts) pts/ea", teamLabel: game.team3Name, count: $draft.team3.acesInHand)
                            OneTeamScoreRow(title: "8 thru King", subtitle: "-\(game.highCardPts) pts/ea", teamLabel: game.team3Name, count: $draft.team3.highCardsInHand)
                            OneTeamScoreRow(title: "4 thru 7", subtitle: "-\(game.lowCardPts) pts/ea", teamLabel: game.team3Name, count: $draft.team3.lowCardsInHand)
                            OneTeamScoreRow(title: "Black 3s", subtitle: "-\(game.black3Pts) pts/ea", teamLabel: game.team3Name, count: $draft.team3.black3sInHand)
                        }

                        Section(header: Text("Live Round Total")) {
                            HStack {
                                VStack(spacing: 2) {
                                    Text(game.team3Name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    Text("\(draft.total(for: .team3, game: game))").bold().monospacedDigit()
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
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
                    draft = DraftRoundData(from: round)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingRound == nil ? "Submit" : "Save") {
                        TallyKeyboard.dismiss()
                        saveRound()
                    }
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
        .presentationDetents([.height(100), .large], selection: $currentDetent)
        .presentationBackgroundInteraction(.enabled(upThrough: .height(100)))
        .interactiveDismissDisabled()
    }
}

// MARK: - Custom Input Component (Supports Multi-Digit Typing, Signed Ranges & Stepper Sync)

private struct HybridStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...TallyMath.maxCount
    var accessibilityLabel: String

    @State private var text: String = "0"
    @FocusState private var isFocused: Bool

    private var allowsNegative: Bool {
        range.lowerBound < 0
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField("0", text: $text)
                .keyboardType(allowsNegative ? .numbersAndPunctuation : .numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 54, maxWidth: 68)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .focused($isFocused)
                .accessibilityLabel(accessibilityLabel)
                .onChange(of: isFocused) { _, focused in
                    if !focused {
                        commitText()
                    }
                }
                .onChange(of: text) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Allow intermediate empty or "-" states while typing
                    if trimmed.isEmpty || (allowsNegative && trimmed == "-") {
                        return
                    }
                    if let parsed = TallyMath.parseCount(
                        trimmed,
                        min: range.lowerBound,
                        max: range.upperBound
                    ) {
                        if value != parsed {
                            value = parsed
                        }
                    }
                }
                .onChange(of: value) { _, newValue in
                    let clamped = TallyMath.clampCount(newValue, min: range.lowerBound, max: range.upperBound)
                    if clamped != newValue {
                        value = clamped
                        return
                    }
                    // Only overwrite the text field when not actively typing so multi-digit entry stays intact
                    if !isFocused && text != "\(clamped)" {
                        text = "\(clamped)"
                    }
                }
                .onAppear {
                    let clamped = TallyMath.clampCount(value, min: range.lowerBound, max: range.upperBound)
                    value = clamped
                    text = "\(clamped)"
                }

            Stepper(
                accessibilityLabel,
                onIncrement: {
                    if isFocused { isFocused = false }
                    let next = TallyMath.clampCount(value + 1, min: range.lowerBound, max: range.upperBound)
                    value = next
                    text = "\(next)"
                },
                onDecrement: {
                    if isFocused { isFocused = false }
                    let next = TallyMath.clampCount(value - 1, min: range.lowerBound, max: range.upperBound)
                    value = next
                    text = "\(next)"
                }
            )
            .labelsHidden()
        }
    }

    private func commitText() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let zeroClamped = TallyMath.clampCount(0, min: range.lowerBound, max: range.upperBound)
            value = zeroClamped
            text = "\(zeroClamped)"
        } else if let parsed = TallyMath.parseCount(trimmed, min: range.lowerBound, max: range.upperBound) {
            value = parsed
            text = "\(parsed)"
        } else {
            text = "\(value)"
        }
    }
}

// MARK: - Reusable Stepper Row for Teams 1 & 2

private struct TwoTeamScoreRow: View {
    let title: String
    let subtitle: String?
    let team1Label: String
    let team2Label: String
    var range: ClosedRange<Int> = 0...TallyMath.maxCount
    @Binding var count1: Int
    @Binding var count2: Int

    private func compactLabel(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return fallback }
        if trimmed.count <= 8 { return trimmed }
        return String(trimmed.prefix(7)) + "…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).fontWeight(.semibold)
                if let sub = subtitle { Text(sub).font(.caption).foregroundStyle(.secondary) }
                Spacer()
            }

            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("\(compactLabel(team1Label, fallback: "T1")):")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HybridStepper(
                        value: $count1,
                        range: range,
                        accessibilityLabel: "\(team1Label) \(title)"
                    )
                    Spacer()
                    Text("\(compactLabel(team2Label, fallback: "T2")):")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HybridStepper(
                        value: $count2,
                        range: range,
                        accessibilityLabel: "\(team2Label) \(title)"
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(team1Label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        HybridStepper(
                            value: $count1,
                            range: range,
                            accessibilityLabel: "\(team1Label) \(title)"
                        )
                    }
                    HStack {
                        Text(team2Label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        HybridStepper(
                            value: $count2,
                            range: range,
                            accessibilityLabel: "\(team2Label) \(title)"
                        )
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
    let teamLabel: String
    var range: ClosedRange<Int> = 0...TallyMath.maxCount
    @Binding var count: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).fontWeight(.semibold)
                if let sub = subtitle { Text(sub).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            HybridStepper(
                value: $count,
                range: range,
                accessibilityLabel: "\(teamLabel) \(title)"
            )
        }
        .padding(.vertical, 4)
    }
}
