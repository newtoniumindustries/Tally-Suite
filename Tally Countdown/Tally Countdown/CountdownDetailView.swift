import SwiftData
import SwiftUI
import TallyCore

struct CountdownDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var item: CountdownItem

    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false
    @State private var showingRestartConfirmation = false
    @State private var saveErrorMessage: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
            let now = timeline.date
            let snap = item.snapshot(at: now)
            let themeColor = item.colorTheme.color

            ScrollView {
                VStack(spacing: 16) {
                    if let streak = snap.streak {
                        streakHeroCard(streak: streak, isUpcoming: snap.isUpcomingStart, now: now, themeColor: themeColor)

                        StreakCalendarView(
                            startDay: streak.startDay,
                            today: streak.today,
                            completedDayKeys: item.completedDayKeys,
                            tintColor: themeColor
                        ) { tappedDay in
                            toggleStreakDay(tappedDay, now: now)
                        }

                        streakDailyReminderCard(themeColor: themeColor, now: now)
                    } else {
                        heroCard(snap: snap, themeColor: themeColor)
                    }

                    scheduleDetailsCard(snap: snap, themeColor: themeColor)

                    if item.mode != .streak && (item.mode == .countdown || item.hasTargetDate) {
                        alertsCard(now: now, themeColor: themeColor)
                    }

                    if !item.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Notes", systemImage: "note.text")
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)
                            Text(item.notes)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    }

                    actionButtons(snap: snap, themeColor: themeColor)
                }
                .padding()
            }
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    showingEditor = true
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            CountdownEditorSheet(editingItem: item)
        }
        .alert("Restart Cycle?", isPresented: $showingRestartConfirmation) {
            Button("Restart") {
                item.restartCycle()
                if let error = context.saveReportingError() {
                    saveErrorMessage = error
                    return
                }
                Task {
                    await NotificationScheduler.shared.syncNotifications(for: item)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(item.mode == .streak
                ? "This clears logged check-in days for \"\(item.title)\" and starts a fresh streak from today."
                : "This resets \"\(item.title)\" starting from now and reschedules any enabled alerts.")
        }
        .alert("Delete Timer?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                let itemID = item.id
                context.delete(item)
                if let error = context.saveReportingError() {
                    saveErrorMessage = error
                    return
                }
                NotificationScheduler.shared.cancelNotifications(for: itemID)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes \"\(item.title)\" and cancels any scheduled alerts.")
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

    // MARK: - Streak Hero & Reminder Cards

    private func streakHeroCard(
        streak: StreakSnapshot,
        isUpcoming: Bool,
        now: Date,
        themeColor: Color
    ) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                CountdownBadgeIcon(icon: item.symbolName, tint: themeColor, size: 44, cornerRadius: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text("DAILY STREAK")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(themeColor)
                    Text(streak.isComplete
                        ? "Goal reached!"
                        : (isUpcoming
                            ? "Starts \(streak.startDay.formatted(date: .abbreviated, time: .omitted))"
                            : (streak.isCompletedToday ? "Checked in today" : "Waiting for today's check-in")))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if streak.isComplete {
                    Label("Goal", systemImage: "checkmark.seal.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.18), in: Capsule())
                        .foregroundStyle(.green)
                }
            }

            Button {
                toggleStreakDay(now, now: now)
            } label: {
                Label(
                    streak.isCompletedToday ? "Completed Today" : "Mark Today Complete",
                    systemImage: streak.isCompletedToday ? "checkmark.circle.fill" : "circle"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(streak.isCompletedToday ? .green : themeColor)
            .disabled(isUpcoming)
            .sensoryFeedback(.success, trigger: streak.isCompletedToday)

            HStack(spacing: 8) {
                TimeUnitTile(value: streak.currentStreak, label: "Current", tint: themeColor)
                TimeUnitTile(value: streak.longestStreak, label: "Best", tint: themeColor)
                TimeUnitTile(value: streak.totalCompletedDays, label: "Total", tint: themeColor)
            }

            if let progress = streak.progress, let goalDays = streak.goalDays {
                VStack(spacing: 6) {
                    ProgressView(value: progress)
                        .tint(streak.isComplete ? .green : themeColor)

                    HStack {
                        Text("\(CountdownCalculator.formatProgressPercent(progress, isComplete: streak.isComplete)) complete")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(streak.currentStreak) of \(goalDays) consecutive \(goalDays == 1 ? "day" : "days")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func streakDailyReminderCard(themeColor: Color, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Daily Reminder", systemImage: "bell.badge")
                    .font(.subheadline.bold())
                    .foregroundStyle(themeColor)
                Spacer()
                Toggle("Daily Reminder Enabled", isOn: Binding(
                    get: { item.alertsEnabled },
                    set: { newValue in
                        item.alertsEnabled = newValue
                        if let error = context.saveReportingError() {
                            saveErrorMessage = error
                            return
                        }
                        Task {
                            await NotificationScheduler.shared.syncNotifications(for: item, now: now)
                        }
                    }
                ))
                .labelsHidden()
                .accessibilityLabel("Enable daily reminder for \(item.title)")
            }

            if item.alertsEnabled {
                DetailRow(
                    label: "Reminder Time",
                    value: "Daily at \(CountdownCalculator.formatDailyReminderTime(hour: item.dailyReminderHour, minute: item.dailyReminderMinute))"
                )
            } else {
                Text("Daily reminders are turned off. Edit this streak to customize the reminder time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Countdown / Count Up Hero Card

    private func heroCard(snap: CountdownSnapshot, themeColor: Color) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                CountdownBadgeIcon(icon: item.symbolName, tint: themeColor, size: 44, cornerRadius: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.mode == .countdown ? "COUNTDOWN" : (snap.isUpcomingStart ? "UPCOMING COUNT UP" : "COUNT UP"))
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(themeColor)
                    Text(statusSubtitle(for: snap))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if snap.isComplete {
                    Label("Done", systemImage: "checkmark.seal.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.18), in: Capsule())
                        .foregroundStyle(.green)
                }
            }

            HStack(spacing: 8) {
                TimeUnitTile(value: snap.primaryBreakdown.days, label: "Days", tint: themeColor)
                TimeUnitTile(value: snap.primaryBreakdown.hours, label: "Hrs", tint: themeColor)
                TimeUnitTile(value: snap.primaryBreakdown.minutes, label: "Min", tint: themeColor)
                TimeUnitTile(value: snap.primaryBreakdown.seconds, label: "Sec", tint: themeColor)
            }

            if let progress = snap.progress {
                VStack(spacing: 6) {
                    ProgressView(value: progress)
                        .tint(snap.isComplete ? .green : themeColor)

                    HStack {
                        Text("\(CountdownCalculator.formatProgressPercent(progress, isComplete: snap.isComplete)) complete")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        if snap.mode == .countup, let remaining = snap.remainingToGoal, !snap.isComplete {
                            Text("\(remaining.formattedCompact(isAllDay: snap.isAllDay)) left")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let goalDays = snap.totalGoalDays, snap.mode == .countup {
                            Text("Goal: \(goalDays) \(goalDays == 1 ? "day" : "days")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Schedule, Alerts & Actions

    private func scheduleDetailsCard(snap: CountdownSnapshot, themeColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Schedule", systemImage: "calendar")
                .font(.subheadline.bold())
                .foregroundStyle(themeColor)

            DetailRow(
                label: item.mode == .countdown ? "Started" : "Start Date",
                value: formattedDate(snap.effectiveStartDate, isAllDay: snap.isAllDay)
            )

            if let target = snap.effectiveTargetDate {
                DetailRow(
                    label: item.mode == .countdown ? "Target Date" : (item.mode == .streak ? "End Goal Date" : "Goal Date"),
                    value: formattedDate(target, isAllDay: snap.isAllDay)
                )
            } else if item.mode == .streak {
                DetailRow(label: "End Goal", value: "Open-Ended")
            }

            if item.mode != .streak {
                DetailRow(
                    label: "Repeat",
                    value: item.repeatRule == .customDays
                        ? "Every \(item.customRepeatDays) \(item.customRepeatDays == 1 ? "day" : "days")"
                        : item.repeatRule.displayName
                )

                DetailRow(
                    label: "Timing",
                    value: item.isAllDay ? "All Day" : "Exact Time"
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func alertsCard(now: Date, themeColor: Color) -> some View {
        let scheduled = CountdownCalculator.scheduledAlerts(for: item.valueSnapshot, at: now)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Alerts", systemImage: "bell.badge")
                    .font(.subheadline.bold())
                    .foregroundStyle(themeColor)
                Spacer()
                Toggle("Alerts Enabled", isOn: Binding(
                    get: { item.alertsEnabled },
                    set: { newValue in
                        item.alertsEnabled = newValue
                        if let error = context.saveReportingError() {
                            saveErrorMessage = error
                            return
                        }
                        Task {
                            await NotificationScheduler.shared.syncNotifications(for: item)
                        }
                    }
                ))
                .labelsHidden()
                .accessibilityLabel("Enable alerts for \(item.title)")
            }

            if item.alertsEnabled {
                DetailRow(
                    label: "When Reached",
                    value: item.alertAtCompletion ? "On" : "Off"
                )
                DetailRow(
                    label: "Advance Reminder",
                    value: item.alertLeadMinutes > 0
                        ? "\(CountdownCalculator.formatLeadTime(minutes: item.alertLeadMinutes)) before"
                        : "None"
                )

                if scheduled.isEmpty {
                    Text("No upcoming alerts remain for this cycle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(scheduled, id: \.identifier) { alert in
                        HStack {
                            Image(systemName: alert.kind == .lead ? "clock.badge.exclamationmark" : "bell.fill")
                                .font(.caption)
                                .foregroundStyle(themeColor)
                            Text(alert.kind == .lead ? "Lead Alert" : "Final Alert")
                                .font(.caption.bold())
                            Spacer()
                            Text(alert.fireDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("Alerts are turned off for this timer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func actionButtons(snap: CountdownSnapshot, themeColor: Color) -> some View {
        VStack(spacing: 10) {
            if snap.isComplete || item.mode == .countup || item.mode == .streak {
                Button {
                    showingRestartConfirmation = true
                } label: {
                    Label(
                        item.mode == .streak ? "Reset Streak" : "Restart Cycle from Now",
                        systemImage: "arrow.counterclockwise.circle.fill"
                    )
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(themeColor)
            }

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete Timer", systemImage: "trash")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
        }
    }

    private func toggleStreakDay(_ day: Date, now: Date) {
        guard item.toggleCompletion(on: day, now: now) else { return }
        if let error = context.saveReportingError() {
            saveErrorMessage = error
            return
        }
        Task {
            await NotificationScheduler.shared.syncNotifications(for: item, now: now)
        }
    }

    private func statusSubtitle(for snap: CountdownSnapshot) -> String {
        switch snap.mode {
        case .countdown:
            return snap.isComplete ? "Countdown reached" : "Time remaining"
        case .countup:
            if snap.isUpcomingStart { return "Starts soon" }
            if snap.isComplete { return "Goal reached" }
            return snap.hasGoal ? "Elapsed toward goal" : "Time elapsed"
        case .streak:
            return snap.isComplete ? "Streak goal reached" : "Daily streak"
        }
    }

    private func formattedDate(_ date: Date, isAllDay: Bool) -> String {
        if isAllDay {
            return date.formatted(date: .long, time: .omitted)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct TimeUnitTile: View {
    let value: Int
    let label: String
    let tint: Color

    @ScaledMetric(relativeTo: .title2) private var numberFontSize: CGFloat = 26

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: min(numberFontSize, 36), weight: .heavy, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2.bold())
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
