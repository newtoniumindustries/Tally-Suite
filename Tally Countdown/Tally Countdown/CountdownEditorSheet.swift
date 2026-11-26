import SwiftData
import SwiftUI
import TallyCore
import UIKit
import UserNotifications

struct CountdownEditorSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var editingItem: CountdownItem?

    @State private var didLoad = false
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var mode: CountdownMode = .countdown
    @State private var isAllDay: Bool = false
    @State private var startDate: Date = Date()
    @State private var targetDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date().addingTimeInterval(7 * 86_400)
    @State private var hasGoalTarget: Bool = true

    // Quick duration helper (e.g., "20 days from today")
    @State private var useDurationPicker: Bool = false
    @State private var durationAmountText: String = "20"
    @State private var durationUnit: DurationUnit = .days

    // Repeat settings
    @State private var repeatRule: RepeatRule = .none
    @State private var customRepeatDaysText: String = "7"

    // Alert settings
    @State private var alertsEnabled: Bool = false
    @State private var alertAtCompletion: Bool = true
    @State private var leadPreset: AlertLeadPreset = .none
    @State private var customLeadAmountText: String = "2"
    @State private var customLeadUnit: DurationUnit = .hours
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    // Appearance
    @State private var selectedColor: CountdownThemeColor = .orange
    @State private var selectedSymbol: String = "hourglass"

    @State private var saveErrorMessage: String?

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var supportsTargetAndAlerts: Bool {
        mode == .countdown || hasGoalTarget
    }

    private var parsedDurationAmount: Int? {
        TallyMath.parsePositiveInt(durationAmountText, max: 3650)
    }

    private var parsedCustomRepeatDays: Int? {
        TallyMath.parsePositiveInt(customRepeatDaysText, max: 3650)
    }

    private var computedLeadMinutes: Int {
        if let fixed = leadPreset.fixedMinutes {
            return fixed
        }
        guard let amount = TallyMath.parsePositiveInt(customLeadAmountText, max: 365_000) else {
            return 0
        }
        let total = TallyMath.multiply(amount, customLeadUnit.minutesMultiplier)
        return TallyMath.clamp(total, min: 0, max: CountdownCalculator.maxLeadMinutes)
    }

    private var resolvedTargetDate: Date {
        if useDurationPicker, let amount = parsedDurationAmount {
            let base = (mode == .countup) ? startDate : Date()
            let minutes = TallyMath.multiply(amount, durationUnit.minutesMultiplier)
            let computed = Calendar.current.date(byAdding: .minute, value: minutes, to: base) ?? base
            return CountdownCalculator.normalizeDate(computed, isAllDay: isAllDay)
        }
        return CountdownCalculator.normalizeDate(targetDate, isAllDay: isAllDay)
    }

    private var durationValidationError: String? {
        guard supportsTargetAndAlerts && useDurationPicker else { return nil }
        if parsedDurationAmount == nil {
            return "Enter a whole number between 1 and 3,650."
        }
        return nil
    }

    private var repeatValidationError: String? {
        guard supportsTargetAndAlerts && repeatRule == .customDays else { return nil }
        if parsedCustomRepeatDays == nil {
            return "Enter a repeat interval between 1 and 3,650 days."
        }
        return nil
    }

    private var leadValidationError: String? {
        guard supportsTargetAndAlerts && alertsEnabled && leadPreset == .custom else { return nil }
        if TallyMath.parsePositiveInt(customLeadAmountText, max: 365_000) == nil {
            return "Enter a positive lead time value."
        }
        return nil
    }

    private var alertsConfigurationWarning: String? {
        guard supportsTargetAndAlerts && alertsEnabled else { return nil }
        if !alertAtCompletion && computedLeadMinutes == 0 {
            return "Turn on \"Alert When Reached\" or pick a lead-time reminder."
        }
        return nil
    }

    private var targetBeforeStartError: String? {
        guard mode == .countup && hasGoalTarget && !useDurationPicker else { return nil }
        let normStart = CountdownCalculator.normalizeDate(startDate, isAllDay: isAllDay)
        let normTarget = CountdownCalculator.normalizeDate(targetDate, isAllDay: isAllDay)
        if normTarget <= normStart {
            return "Goal date must be after the start date."
        }
        return nil
    }

    private var canSave: Bool {
        !trimmedTitle.isEmpty
            && durationValidationError == nil
            && repeatValidationError == nil
            && leadValidationError == nil
            && alertsConfigurationWarning == nil
            && targetBeforeStartError == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name & Style") {
                    TextField("Name (e.g. Vacation, 20-Day Streak)", text: $title)
                    TextField("Notes (Optional)", text: $notes)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(CountdownThemeColor.allCases) { theme in
                                Button {
                                    selectedColor = theme
                                } label: {
                                    Circle()
                                        .fill(theme.color)
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.primary, lineWidth: selectedColor == theme ? 2.5 : 0)
                                                .padding(-3)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(theme.displayName) color")
                                .accessibilityAddTraits(selectedColor == theme ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(CountdownSymbol.all, id: \.self) { symbol in
                                let isSelected = selectedSymbol == symbol
                                Button {
                                    selectedSymbol = symbol
                                } label: {
                                    Image(systemName: symbol)
                                        .font(.body.weight(.semibold))
                                        .frame(width: 36, height: 36)
                                        .background(
                                            isSelected ? selectedColor.color.opacity(0.2) : Color(.tertiarySystemFill),
                                            in: RoundedRectangle(cornerRadius: 8)
                                        )
                                        .foregroundStyle(isSelected ? selectedColor.color : .primary)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(isSelected ? selectedColor.color : Color.clear, lineWidth: 1.5)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(symbol)
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Timer Type") {
                    Picker("Mode", selection: $mode) {
                        ForEach(CountdownMode.allCases) { itemMode in
                            Text(itemMode.displayName).tag(itemMode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _, newMode in
                        if newMode == .countup && editingItem == nil {
                            // Default new countup to "20 days from today" duration entry for fast setup
                            hasGoalTarget = true
                            useDurationPicker = true
                        }
                    }

                    Toggle("All Day (Date Only)", isOn: $isAllDay)
                }

                scheduleSection

                if supportsTargetAndAlerts {
                    repeatSection
                    alertsSection
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(editingItem == nil ? "New Timer" : "Edit Timer")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: loadInitialState)
            .task {
                notificationStatus = await NotificationScheduler.shared.authorizationStatus()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveItem() }
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

    @ViewBuilder
    private var scheduleSection: some View {
        let components: DatePickerComponents = isAllDay ? [.date] : [.date, .hourAndMinute]

        if mode == .countdown {
            Section(
                header: Text("Target Date"),
                footer: Text(useDurationPicker
                    ? "Target date will be set to \(resolvedTargetDate.formatted(date: .abbreviated, time: isAllDay ? .omitted : .shortened))."
                    : "Pick the date and time you are counting down to.")
            ) {
                Picker("Set Target By", selection: $useDurationPicker) {
                    Text("Pick Date").tag(false)
                    Text("Duration from Today").tag(true)
                }
                .pickerStyle(.segmented)

                if useDurationPicker {
                    durationInputRow
                    if let error = durationValidationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } else {
                    DatePicker("Target", selection: $targetDate, displayedComponents: components)
                }
            }
        } else {
            Section(
                header: Text("Count Up Schedule"),
                footer: Text(hasGoalTarget
                    ? "Counts up from the start date toward \(resolvedTargetDate.formatted(date: .abbreviated, time: isAllDay ? .omitted : .shortened))."
                    : "Counts upward continuously from the start date.")
            ) {
                DatePicker("Start Date", selection: $startDate, displayedComponents: components)

                Toggle("Set Goal (e.g. 20 Days)", isOn: $hasGoalTarget)

                if hasGoalTarget {
                    Picker("Goal Type", selection: $useDurationPicker) {
                        Text("Duration from Start").tag(true)
                        Text("Pick End Date").tag(false)
                    }
                    .pickerStyle(.segmented)

                    if useDurationPicker {
                        durationInputRow
                        if let error = durationValidationError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } else {
                        DatePicker("Goal Date", selection: $targetDate, displayedComponents: components)
                        if let error = targetBeforeStartError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
    }

    private var durationInputRow: some View {
        HStack {
            Text("Length")
            Spacer()
            TextField("20", text: $durationAmountText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 64, maxWidth: 84)
                .accessibilityLabel("Duration amount")

            Picker("Unit", selection: $durationUnit) {
                ForEach(isAllDay ? [DurationUnit.days] : DurationUnit.allCases) { unit in
                    Text(unit.displayName).tag(unit)
                }
            }
            .labelsHidden()
            .onChange(of: isAllDay) { _, allDay in
                if allDay { durationUnit = .days }
            }
        }
    }

    private var repeatSection: some View {
        Section(
            header: Text("Repeat"),
            footer: Text("When enabled, the timer automatically advances to the next cycle after reaching its target.")
        ) {
            Picker("Repeat", selection: $repeatRule) {
                ForEach(RepeatRule.allCases) { rule in
                    Text(rule.displayName).tag(rule)
                }
            }

            if repeatRule == .customDays {
                HStack {
                    Text("Every N Days")
                    Spacer()
                    TextField("7", text: $customRepeatDaysText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 64, maxWidth: 90)
                        .accessibilityLabel("Repeat interval in days")
                }
                if let error = repeatValidationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var alertsSection: some View {
        Section(
            header: Text("Alerts"),
            footer: Text("Get notified when your countdown ends, and optionally choose how far in advance to receive an early reminder.")
        ) {
            Toggle("Enable Alerts", isOn: $alertsEnabled)
                .onChange(of: alertsEnabled) { _, enabled in
                    if enabled {
                        Task {
                            _ = await NotificationScheduler.shared.ensureAuthorization()
                            notificationStatus = await NotificationScheduler.shared.authorizationStatus()
                        }
                    }
                }

            if alertsEnabled {
                if notificationStatus == .denied {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Notifications are turned off in iOS Settings.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.caption.bold())
                    }
                }

                Toggle("Alert When Reached", isOn: $alertAtCompletion)

                Picker("Remind Before End", selection: $leadPreset) {
                    ForEach(AlertLeadPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }

                if leadPreset == .custom {
                    HStack {
                        Text("Lead Time")
                        Spacer()
                        TextField("2", text: $customLeadAmountText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 64, maxWidth: 84)
                            .accessibilityLabel("Custom lead time amount")

                        Picker("Lead Unit", selection: $customLeadUnit) {
                            ForEach(DurationUnit.allCases) { unit in
                                Text(unit.displayName).tag(unit)
                            }
                        }
                        .labelsHidden()
                    }

                    if let error = leadValidationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if let warning = alertsConfigurationWarning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func loadInitialState() {
        guard !didLoad else { return }
        didLoad = true

        guard let item = editingItem else { return }
        title = item.title
        notes = item.notes
        mode = item.mode
        isAllDay = item.isAllDay
        startDate = item.startDate
        targetDate = item.targetDate
        hasGoalTarget = item.hasTargetDate
        useDurationPicker = false
        repeatRule = item.repeatRule
        customRepeatDaysText = String(item.customRepeatDays)
        alertsEnabled = item.alertsEnabled
        alertAtCompletion = item.alertAtCompletion
        selectedColor = item.colorTheme
        selectedSymbol = item.symbolName

        leadPreset = AlertLeadPreset.from(minutes: item.alertLeadMinutes)
        if leadPreset == .custom {
            if item.alertLeadMinutes % 1440 == 0 {
                customLeadUnit = .days
                customLeadAmountText = String(max(1, item.alertLeadMinutes / 1440))
            } else if item.alertLeadMinutes % 60 == 0 {
                customLeadUnit = .hours
                customLeadAmountText = String(max(1, item.alertLeadMinutes / 60))
            } else {
                customLeadUnit = .minutes
                customLeadAmountText = String(max(1, item.alertLeadMinutes))
            }
        }
    }

    private func saveItem() async {
        guard canSave else { return }
        TallyKeyboard.dismiss()

        let now = Date()
        let finalHasTarget = (mode == .countdown) ? true : hasGoalTarget
        let finalStart: Date
        if mode == .countdown {
            finalStart = editingItem?.startDate ?? CountdownCalculator.normalizeDate(now, isAllDay: isAllDay)
        } else {
            finalStart = CountdownCalculator.normalizeDate(startDate, isAllDay: isAllDay)
        }
        let finalTarget = finalHasTarget ? resolvedTargetDate : finalStart
        let finalRepeatRule = finalHasTarget ? repeatRule : .none
        let finalCustomDays = parsedCustomRepeatDays ?? 7
        let finalAlertsEnabled = finalHasTarget && alertsEnabled
        let finalLeadMinutes = finalAlertsEnabled ? computedLeadMinutes : 0

        let savedItem: CountdownItem
        if let existing = editingItem {
            existing.title = trimmedTitle
            existing.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.mode = mode
            existing.isAllDay = isAllDay
            existing.startDate = finalStart
            existing.targetDate = finalTarget
            existing.hasTargetDate = finalHasTarget
            existing.repeatRule = finalRepeatRule
            existing.customRepeatDays = finalCustomDays
            existing.alertsEnabled = finalAlertsEnabled
            existing.alertAtCompletion = alertAtCompletion
            existing.alertLeadMinutes = finalLeadMinutes
            existing.colorTheme = selectedColor
            existing.symbolName = selectedSymbol
            savedItem = existing
        } else {
            let newItem = CountdownItem(
                title: trimmedTitle,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                mode: mode,
                startDate: finalStart,
                targetDate: finalTarget,
                hasTargetDate: finalHasTarget,
                isAllDay: isAllDay,
                repeatRule: finalRepeatRule,
                customRepeatDays: finalCustomDays,
                alertsEnabled: finalAlertsEnabled,
                alertAtCompletion: alertAtCompletion,
                alertLeadMinutes: finalLeadMinutes,
                colorTheme: selectedColor,
                symbolName: selectedSymbol
            )
            context.insert(newItem)
            savedItem = newItem
        }

        if let error = context.saveReportingError() {
            saveErrorMessage = error
            return
        }

        await NotificationScheduler.shared.syncNotifications(for: savedItem, now: now)
        dismiss()
    }
}
