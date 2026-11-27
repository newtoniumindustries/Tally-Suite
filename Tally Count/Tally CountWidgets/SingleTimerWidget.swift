import AppIntents
import SwiftUI
import WidgetKit

struct SingleTimerEntry: TimelineEntry, Sendable {
    let date: Date
    let timer: WidgetTimerSummary?
}

struct SingleTimerTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SingleTimerEntry {
        SingleTimerEntry(date: Date(), timer: Self.sampleStreak)
    }

    func snapshot(for configuration: SelectTimerWidgetIntent, in context: Context) async -> SingleTimerEntry {
        let now = Date()
        if context.isPreview {
            return SingleTimerEntry(date: now, timer: Self.sampleStreak)
        }
        let timer = await resolveTimer(for: configuration, now: now)
        return SingleTimerEntry(date: now, timer: timer ?? Self.sampleStreak)
    }

    func timeline(for configuration: SelectTimerWidgetIntent, in context: Context) async -> Timeline<SingleTimerEntry> {
        let now = Date()
        let timer = await resolveTimer(for: configuration, now: now)

        var refreshDates: [Date] = [now]
        let calendar = Calendar.current
        if let nextMinute = calendar.date(byAdding: .minute, value: 15, to: now) {
            refreshDates.append(nextMinute)
        }
        if let nextHour = calendar.date(byAdding: .hour, value: 1, to: now) {
            refreshDates.append(nextHour)
        }
        if let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            refreshDates.append(tomorrowStart)
        }
        if let timer {
            let snap = CountdownCalculator.snapshot(for: timer.value, at: now)
            if let target = snap.effectiveTargetDate, target > now {
                refreshDates.append(target)
            }
        }

        let uniqueSorted = Array(Set(refreshDates)).sorted()
        let entries = uniqueSorted.map { SingleTimerEntry(date: $0, timer: timer) }
        let reloadDate = calendar.date(byAdding: .hour, value: 2, to: now) ?? now.addingTimeInterval(7200)
        return Timeline(entries: entries, policy: .after(reloadDate))
    }

    private func resolveTimer(for configuration: SelectTimerWidgetIntent, now: Date) async -> WidgetTimerSummary? {
        await MainActor.run {
            let all = TallyCountWidgetStore.fetchAllTimers(now: now)
            if let chosenID = configuration.timer?.id,
               let matched = all.first(where: { $0.id == chosenID }) {
                return matched
            }
            return TallyCountWidgetStore.defaultPrimaryTimer(from: all, now: now)
        }
    }

    private static var sampleStreak: WidgetTimerSummary {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -14, to: today) ?? today
        let end = cal.date(byAdding: .day, value: 15, to: today) ?? today
        let keys = (-11...0).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: today).map { CountdownCalculator.dayKey(for: $0, calendar: cal) }
        }
        let id = UUID()
        return WidgetTimerSummary(
            id: id,
            title: "Daily Run",
            symbolName: "🔥",
            colorTheme: .orange,
            isPinned: true,
            value: CountdownItemValue(
                id: id,
                title: "Daily Run",
                mode: .streak,
                startDate: start,
                targetDate: end,
                hasTargetDate: true,
                isAllDay: true,
                repeatRule: .none,
                customRepeatDays: 7,
                alertsEnabled: true,
                alertAtCompletion: false,
                alertLeadMinutes: 0,
                completedDayKeys: keys,
                dailyReminderHour: 20,
                dailyReminderMinute: 0
            )
        )
    }
}

struct SingleTimerWidget: Widget {
    let kind: String = "SingleTimerWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectTimerWidgetIntent.self,
            provider: SingleTimerTimelineProvider()
        ) { entry in
            SingleTimerWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Timer & Streak")
        .description("Track a countdown, count up, or interactive daily streak right on your Home Screen or Lock Screen.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

private struct SingleTimerWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SingleTimerEntry

    var body: some View {
        if let timer = entry.timer {
            let snap = CountdownCalculator.snapshot(for: timer.value, at: entry.date)
            Group {
                switch family {
                case .systemSmall:
                    smallView(timer: timer, snap: snap)
                case .systemMedium:
                    mediumView(timer: timer, snap: snap)
                case .systemLarge:
                    largeView(timer: timer, snap: snap)
                case .accessoryCircular:
                    circularLockView(timer: timer, snap: snap)
                case .accessoryRectangular:
                    rectangularLockView(timer: timer, snap: snap)
                case .accessoryInline:
                    inlineLockView(timer: timer, snap: snap)
                default:
                    mediumView(timer: timer, snap: snap)
                }
            }
            .widgetURL(TallyCountDeepLink.item(timer.id).url)
        } else {
            emptyStateView
                .widgetURL(TallyCountDeepLink.newTimer.url)
        }
    }

    // MARK: - Small

    private func smallView(timer: WidgetTimerSummary, snap: CountdownSnapshot) -> some View {
        let tint = timer.colorTheme.color
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                CountdownBadgeIcon(icon: timer.symbolName, tint: tint, size: 28, cornerRadius: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(timer.title)
                        .font(.caption.bold())
                        .lineLimit(1)
                    Text(timer.value.mode.displayName)
                        .font(.caption2)
                        .foregroundStyle(tint)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 2)

            Text(snap.primaryHeadline)
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(snap.isComplete ? .green : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            if let streak = snap.streak {
                sevenDayDotRow(days: streak.recentSevenDays, tint: tint, dotSize: 7)
            } else if let target = snap.effectiveTargetDate {
                Text(target.formatted(date: .abbreviated, time: snap.isAllDay ? .omitted : .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let progress = snap.progress {
                HStack(spacing: 4) {
                    ProgressView(value: progress)
                        .tint(snap.isComplete ? .green : tint)
                    Text(CountdownCalculator.formatProgressPercent(progress, isComplete: snap.isComplete))
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let streak = snap.streak, !snap.isUpcomingStart {
                Button(intent: ToggleStreakTodayIntent(itemID: timer.id)) {
                    Label(
                        streak.isCompletedToday ? "Done Today" : "Check In",
                        systemImage: streak.isCompletedToday ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.caption2.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        streak.isCompletedToday ? Color.green : tint.opacity(0.2),
                        in: Capsule()
                    )
                    .foregroundStyle(streak.isCompletedToday ? Color.white : tint)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Medium

    private func mediumView(timer: WidgetTimerSummary, snap: CountdownSnapshot) -> some View {
        let tint = timer.colorTheme.color
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CountdownBadgeIcon(icon: timer.symbolName, tint: tint, size: 36, cornerRadius: 9)

                VStack(alignment: .leading, spacing: 2) {
                    Text(timer.title)
                        .font(.headline)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(timer.value.mode.displayName)
                            .font(.caption2.bold())
                            .foregroundStyle(tint)
                        if let streak = snap.streak {
                            Text("• Best: \(streak.longestStreak)d")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else if let repeatLabel = timer.value.repeatRule.badgeLabel(customDays: timer.value.customRepeatDays) {
                            Label(repeatLabel, systemImage: "repeat")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer(minLength: 4)

                if let streak = snap.streak, !snap.isUpcomingStart {
                    Button(intent: ToggleStreakTodayIntent(itemID: timer.id)) {
                        Label(
                            streak.isCompletedToday ? "Done" : "Check In",
                            systemImage: streak.isCompletedToday ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            streak.isCompletedToday ? Color.green : tint.opacity(0.2),
                            in: Capsule()
                        )
                        .foregroundStyle(streak.isCompletedToday ? Color.white : tint)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let streak = snap.streak {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snap.primaryHeadline)
                            .font(.system(.title2, design: .rounded).weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(snap.isComplete ? .green : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("Total: \(streak.totalCompletedDays) completed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        sevenDayDotRow(days: streak.recentSevenDays, tint: tint, dotSize: 9)
                        Text("Last 7 days")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snap.primaryHeadline)
                            .font(.system(.title2, design: .rounded).weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(snap.isComplete ? .green : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let target = snap.effectiveTargetDate {
                            Text(timer.value.mode == .countdown ? "Target: \(target.formatted(date: .abbreviated, time: snap.isAllDay ? .omitted : .shortened))" : "Goal: \(target.formatted(date: .abbreviated, time: snap.isAllDay ? .omitted : .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("Since \(snap.effectiveStartDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        compactUnitBox(snap.primaryBreakdown.days, "D", tint: tint)
                        compactUnitBox(snap.primaryBreakdown.hours, "H", tint: tint)
                        compactUnitBox(snap.primaryBreakdown.minutes, "M", tint: tint)
                    }
                }
            }

            if let progress = snap.progress {
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                        .tint(snap.isComplete ? .green : tint)
                    Text(CountdownCalculator.formatProgressPercent(progress, isComplete: snap.isComplete))
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(snap.isComplete ? .green : .secondary)
                }
            }
        }
    }

    // MARK: - Large (Includes Interactive 7-Day Streak Backfill!)

    private func largeView(timer: WidgetTimerSummary, snap: CountdownSnapshot) -> some View {
        let tint = timer.colorTheme.color
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                CountdownBadgeIcon(icon: timer.symbolName, tint: tint, size: 42, cornerRadius: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(timer.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(largeSubtitle(timer: timer, snap: snap))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if snap.isComplete {
                    Label("Done", systemImage: "checkmark.seal.fill")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.18), in: Capsule())
                        .foregroundStyle(.green)
                }
            }

            if let streak = snap.streak {
                HStack(spacing: 8) {
                    statTile(value: streak.currentStreak, label: "Current", tint: tint)
                    statTile(value: streak.longestStreak, label: "Best", tint: tint)
                    statTile(value: streak.totalCompletedDays, label: "Total", tint: tint)
                }

                if let progress = streak.progress {
                    HStack(spacing: 8) {
                        ProgressView(value: progress)
                            .tint(streak.isComplete ? .green : tint)
                        Text(CountdownCalculator.formatProgressPercent(progress, isComplete: streak.isComplete))
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Last 7 Days — Tap any day to toggle")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        ForEach(streak.recentSevenDays) { day in
                            let weekday = day.date.formatted(.dateTime.weekday(.narrow))
                            if day.isEditable {
                                Button(intent: ToggleStreakDayIntent(itemID: timer.id, dayKey: day.id)) {
                                    dayToggleChip(weekday: weekday, day: day, tint: tint)
                                }
                                .buttonStyle(.plain)
                            } else {
                                dayToggleChip(weekday: weekday, day: day, tint: tint)
                                    .opacity(0.4)
                            }
                        }
                    }
                }

                if !snap.isUpcomingStart {
                    Button(intent: ToggleStreakTodayIntent(itemID: timer.id)) {
                        Label(
                            streak.isCompletedToday ? "Completed Today" : "Mark Today Complete",
                            systemImage: streak.isCompletedToday ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(streak.isCompletedToday ? Color.green : tint, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 8) {
                    statTile(value: snap.primaryBreakdown.days, label: "Days", tint: tint)
                    statTile(value: snap.primaryBreakdown.hours, label: "Hrs", tint: tint)
                    statTile(value: snap.primaryBreakdown.minutes, label: "Min", tint: tint)
                }

                if let progress = snap.progress {
                    VStack(spacing: 4) {
                        ProgressView(value: progress)
                            .tint(snap.isComplete ? .green : tint)
                        HStack {
                            Text("\(CountdownCalculator.formatProgressPercent(progress, isComplete: snap.isComplete)) complete")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let target = snap.effectiveTargetDate {
                                Text(target.formatted(date: .abbreviated, time: snap.isAllDay ? .omitted : .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Spacer(minLength: 4)
            }

            HStack(spacing: 8) {
                Link(destination: TallyCountDeepLink.item(timer.id).url) {
                    Label("Open Details", systemImage: "arrow.up.right.square")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                }

                Link(destination: TallyCountDeepLink.newTimer.url) {
                    Label("New Timer", systemImage: "plus.circle")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(tint)
                }
            }
        }
    }

    // MARK: - Lock Screen Views

    private func circularLockView(timer: WidgetTimerSummary, snap: CountdownSnapshot) -> some View {
        let valueText: String = {
            if let streak = snap.streak {
                return "\(streak.currentStreak)d"
            }
            return snap.primaryBreakdown.days > 0 ? "\(snap.primaryBreakdown.days)d" : "\(snap.primaryBreakdown.hours)h"
        }()

        return Group {
            if let progress = snap.progress {
                Gauge(value: progress) {
                    Text(CountdownIconCatalog.isEmoji(timer.symbolName) ? timer.symbolName : "⏳")
                } currentValueLabel: {
                    Text(valueText)
                        .font(.caption2.bold().monospacedDigit())
                }
                .gaugeStyle(.accessoryCircular)
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 1) {
                        if CountdownIconCatalog.isEmoji(timer.symbolName) {
                            Text(timer.symbolName).font(.caption)
                        } else {
                            Image(systemName: timer.symbolName).font(.caption)
                        }
                        Text(valueText)
                            .font(.caption2.bold().monospacedDigit())
                    }
                }
            }
        }
    }

    private func rectangularLockView(timer: WidgetTimerSummary, snap: CountdownSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if CountdownIconCatalog.isEmoji(timer.symbolName) {
                    Text(timer.symbolName).font(.caption)
                } else {
                    Image(systemName: timer.symbolName).font(.caption)
                }
                Text(timer.title)
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            Text(snap.primaryHeadline)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
            if let progress = snap.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }
        }
    }

    private func inlineLockView(timer: WidgetTimerSummary, snap: CountdownSnapshot) -> some View {
        let prefix = CountdownIconCatalog.isEmoji(timer.symbolName) ? "\(timer.symbolName) " : ""
        return Text("\(prefix)\(snap.primaryHeadline) • \(timer.title)")
    }

    // MARK: - Shared Subcomponents

    private func sevenDayDotRow(days: [StreakDayStatus], tint: Color, dotSize: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(days) { day in
                Circle()
                    .fill(day.isCompleted ? tint : (day.isEditable ? Color(.tertiarySystemFill) : Color.clear))
                    .frame(width: dotSize, height: dotSize)
                    .overlay(
                        Circle()
                            .stroke(
                                day.isToday ? tint : Color.secondary.opacity(day.isEditable ? 0.3 : 0.12),
                                lineWidth: day.isToday ? 1.5 : 0.75
                            )
                    )
            }
        }
    }

    private func dayToggleChip(weekday: String, day: StreakDayStatus, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(weekday)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(day.isToday ? tint : .secondary)
            ZStack {
                Circle()
                    .fill(day.isCompleted ? tint : Color(.tertiarySystemFill))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .stroke(day.isToday ? tint : Color.clear, lineWidth: 1.5)
                    )
                if day.isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func statTile(value: Int, label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private func compactUnitBox(_ value: Int, _ unit: String, tint: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .monospacedDigit()
            Text(unit)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 34)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func largeSubtitle(timer: WidgetTimerSummary, snap: CountdownSnapshot) -> String {
        if let streak = snap.streak {
            if let goal = streak.goalDays {
                return "Daily Streak • \(goal)-Day Goal"
            }
            return "Open-Ended Daily Streak"
        }
        return timer.value.mode.displayName
    }

    private var emptyStateView: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar.badge.plus")
                .font(.title2)
                .foregroundStyle(.tint)
            Text("Tally: Count")
                .font(.caption.bold())
            Text("Tap to add a timer or streak")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
