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

    // Quick duration helper (e.g., "20 days from today" or "30-day streak")
    @State private var useDurationPicker: Bool = false
    @State private var durationAmountText: String = "20"
    @State private var durationUnit: DurationUnit = .days

    // Repeat settings (Countdown & Count Up)
    @State private var repeatRule: RepeatRule = .none
    @State private var customRepeatDaysText: String = "7"

    // Alert settings
    @State private var alertsEnabled: Bool = false
    @State private var alertAtCompletion: Bool = true
    @State private var leadPreset: AlertLeadPreset = .none
    @State private var customLeadAmountText: String = "2"
    @State private var customLeadUnit: DurationUnit = .hours
    @State private var dailyReminderTime: Date = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    // Appearance
    @State private var selectedColor: CountdownThemeColor = .blue
    @State private var selectedSymbol: String = CountdownIconCatalog.defaultIcon
    @State private var showingMoreIconsSheet: Bool = false

    @State private var saveErrorMessage: String?

    private var inlineIconOptions: [String] {
        var options = CountdownIconCatalog.quickEmojis
        if !options.contains(selectedSymbol) {
            options.insert(selectedSymbol, at: 0)
        }
        return options
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var supportsTargetAndRepeat: Bool {
        mode == .countdown || (mode == .countup && hasGoalTarget)
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
        if mode == .streak {
            let normStart = Calendar.current.startOfDay(for: startDate)
            if useDurationPicker, let days = parsedDurationAmount {
                // Inclusive day count: a 30-day streak starting Nov 1 ends on Nov 30 (+29 days)
                return Calendar.current.date(byAdding: .day, value: max(0, days - 1), to: normStart) ?? normStart
            }
            return Calendar.current.startOfDay(for: targetDate)
        }

        if useDurationPicker, let amount = parsedDurationAmount {
            let base = (mode == .countup) ? startDate : Date()
            return CountdownCalculator.addDuration(
                amount: amount,
                unit: durationUnit,
                to: base,
                isAllDay: isAllDay
            )
        }
        return CountdownCalculator.normalizeDate(targetDate, isAllDay: isAllDay)
    }

    private var durationValidationError: String? {
        let needsDuration = (mode == .countdown && useDurationPicker)
            || ((mode == .countup || mode == .streak) && hasGoalTarget && useDurationPicker)
        guard needsDuration else { return nil }
        if parsedDurationAmount == nil {
            return "Enter a whole number between 1 and 3,650."
        }
        return nil
    }

    private var repeatValidationError: String? {
        guard supportsTargetAndRepeat && repeatRule == .customDays else { return nil }
        if parsedCustomRepeatDays == nil {
            return "Enter a repeat interval between 1 and 3,650 days."
        }
        return nil
    }

    private var leadValidationError: String? {
        guard mode != .streak && supportsTargetAndRepeat && alertsEnabled && leadPreset == .custom else { return nil }
        if TallyMath.parsePositiveInt(customLeadAmountText, max: 365_000) == nil {
            return "Enter a positive lead time value."
        }
        return nil
    }

    private var alertsConfigurationWarning: String? {
        guard mode != .streak && supportsTargetAndRepeat && alertsEnabled else { return nil }
        if !alertAtCompletion && computedLeadMinutes == 0 {
            return "Turn on \"Alert When Reached\" or pick a lead-time reminder."
        }
        return nil
    }

    private var targetBeforeStartError: String? {
        guard (mode == .countup || mode == .streak) && hasGoalTarget && !useDurationPicker else { return nil }
        let effectiveAllDay = (mode == .streak) ? true : isAllDay
        let normStart = CountdownCalculator.normalizeDate(startDate, isAllDay: effectiveAllDay)
        let normTarget = CountdownCalculator.normalizeDate(targetDate, isAllDay: effectiveAllDay)
        if mode == .streak {
            if normTarget < normStart {
                return "End date must be on or after the start date."
            }
        } else if normTarget <= normStart {
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
                    TextField(namePlaceholder, text: $title)
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
                        HStack(spacing: 8) {
                            ForEach(inlineIconOptions, id: \.self) { icon in
                                let isSelected = selectedSymbol == icon
                                Button {
                                    selectedSymbol = icon
                                } label: {
                                    Group {
                                        if CountdownIconCatalog.isEmoji(icon) {
                                            Text(icon)
                                                .font(.title3)
                                        } else {
                                            Image(systemName: icon)
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(isSelected ? selectedColor.color : .primary)
                                        }
                                    }
                                    .frame(width: 40, height: 40)
                                    .background(
                                        isSelected ? selectedColor.color.opacity(0.22) : Color(.tertiarySystemFill),
                                        in: RoundedRectangle(cornerRadius: 10)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(isSelected ? selectedColor.color : Color.clear, lineWidth: 2)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(icon)
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }

                            Button {
                                showingMoreIconsSheet = true
                            } label: {
                                Label("More", systemImage: "ellipsis.circle")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .frame(height: 40)
                                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                                    .foregroundStyle(selectedColor.color)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("More emojis and symbols")
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
                        guard editingItem == nil else { return }
                        switch newMode {
                        case .countdown:
                            hasGoalTarget = true
                            useDurationPicker = false
                        case .countup:
                            hasGoalTarget = true
                            useDurationPicker = true
                            durationAmountText = "20"
                            durationUnit = .days
                        case .streak:
                            hasGoalTarget = false
                            useDurationPicker = true
                            durationAmountText = "30"
                            durationUnit = .days
                            if selectedSymbol == CountdownIconCatalog.defaultIcon {
                                selectedSymbol = "🔥"
                            }
                        }
                    }

                    if mode != .streak {
                        Toggle("All Day (Date Only)", isOn: $isAllDay)
                    }
                }

                scheduleSection

                if mode == .streak {
                    streakDailyAlertSection
                } else if supportsTargetAndRepeat {
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
            .sheet(isPresented: $showingMoreIconsSheet) {
                CountdownIconPickerSheet(
                    selectedIcon: $selectedSymbol,
                    tintColor: selectedColor.color
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

    private var namePlaceholder: String {
        switch mode {
        case .countdown: return "Name (e.g. Vacation, Launch Day)"
        case .countup: return "Name (e.g. 20-Day Challenge)"
        case .streak: return "Name (e.g. Daily Workout, Read 20 Min)"
        }
    }

    @ViewBuilder
    private var scheduleSection: some View {
        let components: DatePickerComponents = isAllDay ? [.date] : [.date, .hourAndMinute]

        switch mode {
        case .countdown:
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
                    durationInputRow(daysOnly: isAllDay)
                    if let error = durationValidationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } else {
                    DatePicker("Target", selection: $targetDate, displayedComponents: components)
                }
            }

        case .countup:
            Section(
                header: Text("Count Up Schedule"),
                footer: Text(hasGoalTarget
                    ? "Counts up from the start date toward \(resolvedTargetDate.formatted(date: .abbreviated, time: isAllDay ? .omitted : .shortened))."
                    : "Counts upward continuously from the start date.")
            ) {
                DatePicker("Start Date", selection: $startDate, displayedComponents: components)

                Toggle("Set Goal (e.g. 20 Days)", isOn: $hasGoalTarget)
                    .onChange(of: hasGoalTarget) { _, enabled in
                        if enabled && targetDate <= startDate {
                            targetDate = CountdownCalculator.addDuration(
                                amount: parsedDurationAmount ?? 20,
                                unit: .days,
                                to: startDate,
                                isAllDay: isAllDay
                            )
                        }
                    }

                if hasGoalTarget {
                    Picker("Goal Type", selection: $useDurationPicker) {
                        Text("Duration from Start").tag(true)
                        Text("Pick End Date").tag(false)
                    }
                    .pickerStyle(.segmented)

                    if useDurationPicker {
                        durationInputRow(daysOnly: isAllDay)
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

        case .streak:
            Section(
                header: Text("Streak Schedule"),
                footer: Text(hasGoalTarget
                    ? "Goal ends on \(resolvedTargetDate.formatted(date: .abbreviated, time: .omitted)). Consecutive check-in progress resets if a day is missed."
                    : "Open-ended daily streak. Check in every day and backfill missed past days anytime.")
            ) {
                DatePicker("Start Date", selection: $startDate, displayedComponents: [.date])

                Toggle("Set End Goal (Optional)", isOn: $hasGoalTarget)
                    .onChange(of: hasGoalTarget) { _, enabled in
                        if enabled && Calendar.current.startOfDay(for: targetDate) < Calendar.current.startOfDay(for: startDate) {
                            targetDate = Calendar.current.date(byAdding: .day, value: 29, to: Calendar.current.startOfDay(for: startDate)) ?? startDate
                        }
                    }

                if hasGoalTarget {
                    Picker("Goal Type", selection: $useDurationPicker) {
                        Text("Goal Days").tag(true)
                        Text("Pick End Date").tag(false)
                    }
                    .pickerStyle(.segmented)

                    if useDurationPicker {
                        durationInputRow(daysOnly: true)
                        if let error = durationValidationError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } else {
                        DatePicker("End Date", selection: $targetDate, displayedComponents: [.date])
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

    private func durationInputRow(daysOnly: Bool) -> some View {
        HStack {
            Text(mode == .streak ? "Goal Length" : "Length")
            Spacer()
            TextField(mode == .streak ? "30" : "20", text: $durationAmountText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 64, maxWidth: 84)
                .accessibilityLabel("Duration amount")

            if daysOnly {
                Text("Days")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Unit", selection: $durationUnit) {
                    ForEach(DurationUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
                .labelsHidden()
            }
        }
        .onChange(of: daysOnly) { _, restricted in
            if restricted { durationUnit = .days }
        }
    }

    private var streakDailyAlertSection: some View {
        Section(
            header: Text("Daily Reminder"),
            footer: Text("Receive a daily notification reminding you to check in and keep your streak alive.")
        ) {
            Toggle("Daily Reminder Alert", isOn: $alertsEnabled)
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
                    notificationDeniedBanner
                }

                DatePicker("Reminder Time", selection: $dailyReminderTime, displayedComponents: [.hourAndMinute])
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
                    notificationDeniedBanner
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

    private var notificationDeniedBanner: some View {
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
        dailyReminderTime = Calendar.current.date(
            bySettingHour: item.dailyReminderHour,
            minute: item.dailyReminderMinute,
            second: 0,
            of: Date()
        ) ?? Date()

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
        let finalAllDay = (mode == .streak) ? true : isAllDay
        let finalHasTarget = (mode == .countdown) ? true : hasGoalTarget
        let finalStart: Date
        if mode == .countdown {
            finalStart = editingItem?.startDate ?? CountdownCalculator.normalizeDate(now, isAllDay: finalAllDay)
        } else {
            finalStart = CountdownCalculator.normalizeDate(startDate, isAllDay: finalAllDay)
        }
        let finalTarget = finalHasTarget ? resolvedTargetDate : finalStart
        let finalRepeatRule = (mode == .streak || !finalHasTarget) ? .none : repeatRule
        let finalCustomDays = parsedCustomRepeatDays ?? 7
        let finalAlertsEnabled = (mode == .streak || finalHasTarget) && alertsEnabled
        let finalLeadMinutes = (mode != .streak && finalAlertsEnabled) ? computedLeadMinutes : 0
        let reminderComps = Calendar.current.dateComponents([.hour, .minute], from: dailyReminderTime)
        let finalReminderHour = reminderComps.hour ?? 20
        let finalReminderMinute = reminderComps.minute ?? 0

        let savedItem: CountdownItem
        if let existing = editingItem {
            existing.title = trimmedTitle
            existing.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.mode = mode
            existing.isAllDay = finalAllDay
            existing.startDate = finalStart
            existing.targetDate = finalTarget
            existing.hasTargetDate = finalHasTarget
            existing.repeatRule = finalRepeatRule
            existing.customRepeatDays = finalCustomDays
            existing.alertsEnabled = finalAlertsEnabled
            existing.alertAtCompletion = alertAtCompletion
            existing.alertLeadMinutes = finalLeadMinutes
            existing.dailyReminderHour = finalReminderHour
            existing.dailyReminderMinute = finalReminderMinute
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
                isAllDay: finalAllDay,
                repeatRule: finalRepeatRule,
                customRepeatDays: finalCustomDays,
                alertsEnabled: finalAlertsEnabled,
                alertAtCompletion: alertAtCompletion,
                alertLeadMinutes: finalLeadMinutes,
                completedDayKeys: [],
                dailyReminderHour: finalReminderHour,
                dailyReminderMinute: finalReminderMinute,
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
