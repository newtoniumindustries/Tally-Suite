import AppIntents
import SwiftUI
import WidgetKit

struct TimersOverviewEntry: TimelineEntry, Sendable {
    let date: Date
    let filter: TimersOverviewFilter
    let timers: [WidgetTimerSummary]
}

struct TimersOverviewTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TimersOverviewEntry {
        TimersOverviewEntry(date: Date(), filter: .all, timers: [])
    }

    func snapshot(for configuration: SelectOverviewFilterIntent, in context: Context) async -> TimersOverviewEntry {
        let now = Date()
        let items = await fetchFilteredTimers(filter: configuration.filter, now: now)
        return TimersOverviewEntry(date: now, filter: configuration.filter, timers: items)
    }

    func timeline(for configuration: SelectOverviewFilterIntent, in context: Context) async -> Timeline<TimersOverviewEntry> {
        let now = Date()
        let items = await fetchFilteredTimers(filter: configuration.filter, now: now)
        let cal = Calendar.current
        let nextRefresh = cal.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
        return Timeline(
            entries: [TimersOverviewEntry(date: now, filter: configuration.filter, timers: items)],
            policy: .after(nextRefresh)
        )
    }

    private func fetchFilteredTimers(filter: TimersOverviewFilter, now: Date) async -> [WidgetTimerSummary] {
        await MainActor.run {
            let all = TallyCountWidgetStore.fetchAllTimers(now: now)
            let filtered = all.filter { timer in
                switch filter {
                case .all:
                    return !CountdownCalculator.snapshot(for: timer.value, at: now).isComplete
                case .pinned:
                    return timer.isPinned
                case .countdowns:
                    return timer.value.mode == .countdown
                case .countups:
                    return timer.value.mode == .countup
                case .streaks:
                    return timer.value.mode == .streak
                }
            }
            let pinnedFirst = filtered.sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                let lSnap = CountdownCalculator.snapshot(for: lhs.value, at: now)
                let rSnap = CountdownCalculator.snapshot(for: rhs.value, at: now)
                let lDate = lSnap.effectiveTargetDate ?? lSnap.effectiveStartDate
                let rDate = rSnap.effectiveTargetDate ?? rSnap.effectiveStartDate
                return lDate < rDate
            }
            return Array(pinnedFirst.prefix(5))
        }
    }
}

struct TimersOverviewWidget: Widget {
    let kind: String = "TimersOverviewWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectOverviewFilterIntent.self,
            provider: TimersOverviewTimelineProvider()
        ) { entry in
            TimersOverviewWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Timers Overview")
        .description("View multiple countdowns, count ups, and check in on daily streaks from one widget.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct TimersOverviewWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TimersOverviewEntry

    private var maxRows: Int {
        family == .systemLarge ? 5 : 2
    }

    private var filterTitle: String {
        switch entry.filter {
        case .all: return "Active"
        case .pinned: return "Pinned"
        case .countdowns: return "Countdowns"
        case .countups: return "Count Ups"
        case .streaks: return "Streaks"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tally: Count • \(filterTitle)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Link(destination: TallyCountDeepLink.newTimer.url) {
                    Label("New", systemImage: "plus.circle.fill")
                        .font(.caption2.bold())
                }
            }

            if entry.timers.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("No matching timers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                VStack(spacing: 8) {
                    ForEach(entry.timers.prefix(maxRows)) { timer in
                        timerRow(timer)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func timerRow(_ timer: WidgetTimerSummary) -> some View {
        let snap = CountdownCalculator.snapshot(for: timer.value, at: entry.date)
        let tint = timer.colorTheme.color

        return HStack(spacing: 10) {
            Link(destination: TallyCountDeepLink.item(timer.id).url) {
                HStack(spacing: 8) {
                    CountdownBadgeIcon(icon: timer.symbolName, tint: tint, size: 30, cornerRadius: 7)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(timer.title)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(snap.primaryHeadline)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(snap.isComplete ? .green : .secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            if let streak = snap.streak, !snap.isUpcomingStart {
                Button(intent: ToggleStreakTodayIntent(itemID: timer.id)) {
                    Label(
                        streak.isCompletedToday ? "Done" : "Check",
                        systemImage: streak.isCompletedToday ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        streak.isCompletedToday ? Color.green : tint.opacity(0.2),
                        in: Capsule()
                    )
                    .foregroundStyle(streak.isCompletedToday ? Color.white : tint)
                }
                .buttonStyle(.plain)
            } else if let progress = snap.progress {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(CountdownCalculator.formatProgressPercent(progress, isComplete: snap.isComplete))
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(snap.isComplete ? .green : tint)
                    ProgressView(value: progress)
                        .tint(snap.isComplete ? .green : tint)
                        .frame(width: 56)
                }
            }
        }
    }
}
