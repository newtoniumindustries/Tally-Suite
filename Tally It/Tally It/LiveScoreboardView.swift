import SwiftData
import SwiftUI
import TallyCore

struct LiveScoreboardView: View {
    @Bindable var match: Match
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showingRulesSheet = false
    @State private var showingRoundLedger = true
    @State private var showingResetConfirmation = false
    @State private var saveErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: match.useCondensedView ? 8 : 14) {
                if match.isCompleted {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Text("Match Submitted (Read-Only)")
                                .font(.subheadline.bold())
                            Spacer()
                        }

                        HStack(spacing: 10) {
                            Button {
                                withAnimation {
                                    match.reopenMatch()
                                    if let error = context.saveReportingError() {
                                        saveErrorMessage = error
                                    }
                                }
                            } label: {
                                Label("Reopen & Continue", systemImage: "arrow.uturn.backward.circle.fill")
                                    .font(.caption.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                showingResetConfirmation = true
                            } label: {
                                Label("Reset to 0", systemImage: "arrow.counterclockwise.circle.fill")
                                    .font(.caption.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
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
                                if let maxR = match.activeMaxRounds {
                                    return "ROUND \(min(match.currentRound, maxR)) of \(maxR)"
                                }
                                return "ROUND \(match.currentRound)"
                            }()
                            Text(roundDisplay)
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(.tint)

                            if let maxR = match.activeMaxRounds, match.currentRound > maxR {
                                Text("Final Results (Max Rounds Reached)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                            } else if let target = match.targetScore, target > 0 {
                                Label("Goal: \(target) pts (\(match.lowestScoreWins ? "Low Wins" : "High Wins"))", systemImage: "flag.checkered")
                                    .font(.caption.bold())
                            } else {
                                Text(match.lowestScoreWins ? "Lowest Score Wins" : "Highest Score Wins")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if !match.isCompleted {
                            let isFinal = match.activeMaxRounds.map { match.currentRound >= $0 } ?? false
                            Button {
                                TallyKeyboard.dismiss()
                                advanceRound()
                            } label: {
                                Label(isFinal ? "Finish Game" : "Next Round", systemImage: isFinal ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(isFinal ? Color.green : Color.accentColor, in: Capsule())
                                    .foregroundStyle(.white)
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

                if let bannerText = match.winnerBannerText {
                    HStack(spacing: 10) {
                        Image(systemName: "trophy.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text(bannerText)
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
                        isWinnerHighlighted: match.isHighlightedWinner(entry),
                        isReadOnly: match.isCompleted,
                        onSaveError: { saveErrorMessage = $0 }
                    )
                }

                if match.trackRounds && (!match.roundHistoryEmpty || match.currentRound > 1 || match.sortedEntries.contains(where: { $0.currentRoundDelta != 0 })) {
                    RoundLedgerSection(
                        match: match,
                        isExpanded: $showingRoundLedger,
                        isReadOnly: match.isCompleted,
                        onSaveError: { saveErrorMessage = $0 }
                    )
                    .padding(.horizontal)
                }

                if !match.isCompleted {
                    let hasActiveWinner = !match.winningEntries.isEmpty
                    Button {
                        TallyKeyboard.dismiss()
                        completeMatch()
                    } label: {
                        Label("Finish Match & Record Standings", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(hasActiveWinner ? Color.green : Color.accentColor)
                            .foregroundStyle(.white)
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
                Button("Done") { TallyKeyboard.dismiss() }
            }
        }
        .sheet(isPresented: $showingRulesSheet) {
            AdjustMatchScoringSheet(match: match)
        }
        .alert("Reset Match to 0?", isPresented: $showingResetConfirmation) {
            Button("Reset to 0", role: .destructive) {
                withAnimation {
                    match.restartMatchFromZero()
                    if let error = context.saveReportingError() {
                        saveErrorMessage = error
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears all scores and round history for \(match.gameTypeName) and restarts from Round 1.")
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

    private func advanceRound() {
        let didComplete = match.advanceRound()
        if let error = context.saveReportingError() {
            saveErrorMessage = error
            return
        }
        if didComplete {
            dismiss()
        }
    }

    private func completeMatch() {
        match.completeMatch()
        if let error = context.saveReportingError() {
            saveErrorMessage = error
            return
        }
        dismiss()
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
    var onSaveError: (String) -> Void = { _ in }

    @State private var customInputText: String = ""
    @ScaledMetric(relativeTo: .title) private var condensedScoreSize: CGFloat = 28
    @ScaledMetric(relativeTo: .largeTitle) private var expandedScoreSize: CGFloat = 38

    private var parsedCustomInput: Int? {
        TallyMath.parseInt(customInputText)
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
                                .foregroundStyle(.white)
                        }
                    }

                    if trackRounds {
                        HStack(spacing: 6) {
                            let sign = entry.currentRoundDelta >= 0 ? "+" : ""
                            Text("R\(currentRound): \(sign)\(entry.currentRoundDelta)")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)

                            if let target = targetScore, target > 0, !isWinnerHighlighted {
                                let remaining = max(0, TallyMath.subtract(target, entry.score))
                                if remaining > 0 {
                                    Text(lowestScoreWins ? "| \(remaining) to limit" : "| \(remaining) left")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else if let target = targetScore, target > 0, !isWinnerHighlighted {
                        let remaining = max(0, TallyMath.subtract(target, entry.score))
                        if remaining > 0 {
                            Text(lowestScoreWins ? "\(remaining) pts to limit" : "\(remaining) pts left")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                Text("\(entry.score)")
                    .font(.system(
                        size: min(useCondensedView ? condensedScoreSize : expandedScoreSize, 52),
                        weight: .heavy,
                        design: .rounded
                    ))
                    .foregroundStyle(isWinnerHighlighted ? Color.green : Color.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(entry.teamName) score \(entry.score)")
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
                                .accessibilityLabel("\(delta > 0 ? "Add" : "Subtract") \(abs(delta)) points for \(entry.teamName)")
                            }
                        }
                    }
                }

                HStack(spacing: 6) {
                    TextField("Points (+/- or total)", text: $customInputText)
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .accessibilityLabel("Custom points for \(entry.teamName)")

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
                            entry.setScore(val, trackRounds: trackRounds)
                            if let error = context.saveReportingError() {
                                onSaveError(error)
                            }
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
        entry.applyDelta(delta, trackRounds: trackRounds)
        if let error = context.saveReportingError() {
            onSaveError(error)
        }
    }
}

// MARK: - Buffered Editable Round History Ledger (Atomic Save & Cancel)

struct RoundLedgerSection: View {
    @Environment(\.modelContext) private var context
    @Bindable var match: Match
    @Binding var isExpanded: Bool
    let isReadOnly: Bool
    var onSaveError: (String) -> Void = { _ in }

    @State private var isEditingLedger: Bool = false
    @State private var draftScores: [String: String] = [:]

    private var completedRoundsArray: [Int] {
        Array(0..<match.completedRoundCount)
    }

    private func isCellInvalid(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        return TallyMath.parseInt(trimmed) == nil
    }

    private var hasAnyInvalidDraftCell: Bool {
        draftScores.values.contains { isCellInvalid($0) }
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
                            .foregroundStyle(.primary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isExpanded && !completedRoundsArray.isEmpty && !isReadOnly {
                    if isEditingLedger {
                        HStack(spacing: 8) {
                            Button("Cancel") {
                                cancelEditing()
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.secondary.opacity(0.18), in: Capsule())
                            .foregroundStyle(.primary)

                            Button("Save") {
                                commitEdits()
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(hasAnyInvalidDraftCell ? Color.secondary.opacity(0.3) : Color.accentColor, in: Capsule())
                            .foregroundStyle(.white)
                            .disabled(hasAnyInvalidDraftCell)
                        }
                    } else {
                        Button("Edit") {
                            beginEditing()
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.18), in: Capsule())
                        .foregroundStyle(.primary)
                    }
                }
            }

            if isExpanded {
                Divider()

                if isEditingLedger && hasAnyInvalidDraftCell {
                    Text("Fix highlighted cells with valid whole numbers (or leave blank for 0) before saving.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if needsHorizontalScroll {
                    ScrollView(.horizontal, showsIndicators: true) {
                        ledgerRows(entries: entries, fixedColumnWidth: 84)
                    }
                } else {
                    ledgerRows(entries: entries, fixedColumnWidth: nil)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .onChange(of: isReadOnly) { _, readOnly in
            if readOnly && isEditingLedger {
                cancelEditing()
            }
        }
    }

    @ViewBuilder
    private func ledgerRows(entries: [MatchScoreEntry], fixedColumnWidth: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Rnd")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 48, alignment: .leading)

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
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 48, alignment: .leading)

                    ForEach(entries) { entry in
                        let val = roundIndex < entry.roundHistory.count ? entry.roundHistory[roundIndex] : 0

                        if isEditingLedger && !isReadOnly {
                            let key = cellKey(entryID: entry.id, roundIndex: roundIndex)
                            let text = draftScores[key] ?? String(val)
                            let invalid = isCellInvalid(text)

                            TextField("0", text: draftBinding(forKey: key, fallback: val))
                                .keyboardType(.numbersAndPunctuation)
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                                .font(.subheadline.bold().monospacedDigit())
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(invalid ? Color.red : Color.clear, lineWidth: 1.5)
                                )
                                .frame(width: fixedColumnWidth, alignment: .trailing)
                                .frame(maxWidth: fixedColumnWidth == nil ? .infinity : nil, alignment: .trailing)
                                .accessibilityLabel("Round \(roundIndex + 1) score for \(entry.teamName)")
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
                        .foregroundStyle(.tint)
                        .frame(minWidth: 48, alignment: .leading)

                    ForEach(entries) { entry in
                        let val = entry.currentRoundDelta
                        Text(val >= 0 ? "+\(val)" : "\(val)")
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(.tint)
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

    private func draftBinding(forKey key: String, fallback: Int) -> Binding<String> {
        Binding(
            get: { draftScores[key] ?? String(fallback) },
            set: { draftScores[key] = $0 }
        )
    }

    private func beginEditing() {
        var initial: [String: String] = [:]
        let totalRounds = match.completedRoundCount
        for entry in match.entries {
            for rIndex in 0..<totalRounds {
                let value = rIndex < entry.roundHistory.count ? entry.roundHistory[rIndex] : 0
                initial[cellKey(entryID: entry.id, roundIndex: rIndex)] = String(value)
            }
        }
        draftScores = initial
        isEditingLedger = true
    }

    private func cancelEditing() {
        TallyKeyboard.dismiss()
        draftScores = [:]
        isEditingLedger = false
    }

    private func commitEdits() {
        guard !hasAnyInvalidDraftCell else { return }
        TallyKeyboard.dismiss()

        let totalRounds = match.completedRoundCount
        for entry in match.entries {
            while entry.roundHistory.count < totalRounds {
                entry.roundHistory.append(0)
            }
            for rIndex in 0..<totalRounds {
                let key = cellKey(entryID: entry.id, roundIndex: rIndex)
                if let text = draftScores[key] {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        entry.roundHistory[rIndex] = 0
                    } else if let parsed = TallyMath.parseInt(trimmed) {
                        entry.roundHistory[rIndex] = parsed
                    }
                }
            }
            entry.recalculateTotalScore()
        }

        if let error = context.saveReportingError() {
            onSaveError(error)
            return
        }
        draftScores = [:]
        isEditingLedger = false
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
    @State private var saveErrorMessage: String?

    private var areIncrementsInvalid: Bool {
        !useCondensedView && ScoreIncrementParser.parseStrict(incrementsRaw).isEmpty
    }

    private var isTargetInvalid: Bool {
        let trimmed = targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && TallyMath.parsePositiveInt(trimmed) == nil
    }

    private var maxRoundsValidationError: String? {
        let trimmed = maxRoundsText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        guard let parsed = TallyMath.parsePositiveInt(trimmed) else {
            return "Enter a positive whole number or leave blank."
        }
        let minAllowed = max(1, match.completedRoundCount)
        if parsed < minAllowed {
            return "Cannot be less than \(minAllowed) already-completed round(s)."
        }
        return nil
    }

    private var canSave: Bool {
        !areIncrementsInvalid && !isTargetInvalid && maxRoundsValidationError == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Scoreboard Layout") {
                    Toggle("Condensed View (Hide + / - Buttons)", isOn: $useCondensedView)
                }
                if !useCondensedView {
                    Section("Point Buttons (Comma-Separated)") {
                        TextField("e.g. 1, 5, 10, -1", text: $incrementsRaw)
                        if areIncrementsInvalid {
                            Text("Enter at least one non-zero comma-separated integer.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                Section("Amount Needed to Win") {
                    TextField("Leave blank for no target", text: $targetText)
                        .keyboardType(.numberPad)
                    if isTargetInvalid {
                        Text("Enter a positive whole number or leave blank.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Section("Max Rounds to Win") {
                    TextField("Leave blank for unlimited", text: $maxRoundsText)
                        .keyboardType(.numberPad)
                    if let error = maxRoundsValidationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
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

    private func applyChanges() {
        guard canSave else { return }
        let enablingRoundTracking = !match.trackRounds && trackRounds
        if enablingRoundTracking {
            for entry in match.entries {
                let historySum = TallyMath.sum(entry.roundHistory)
                entry.currentRoundDelta = TallyMath.subtract(entry.score, historySum)
            }
        }

        match.useCondensedView = useCondensedView
        match.incrementsRaw = ScoreIncrementParser.canonicalString(from: incrementsRaw)
        match.targetScore = TallyMath.parsePositiveInt(targetText)
        match.maxRounds = TallyMath.parsePositiveInt(maxRoundsText)
        match.trackRounds = trackRounds
        match.lowestScoreWins = lowestScoreWins
        if let error = context.saveReportingError() {
            saveErrorMessage = error
            return
        }
        dismiss()
    }
}
