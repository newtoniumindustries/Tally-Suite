import Foundation
import SwiftData
import SwiftUI
import TallyCore

// MARK: - Domain Enums

enum CountdownMode: String, CaseIterable, Identifiable, Sendable {
    case countdown
    case countup
    case streak

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .countdown: return "Countdown"
        case .countup: return "Count Up"
        case .streak: return "Streak"
        }
    }

    var systemImage: String {
        switch self {
        case .countdown: return "hourglass"
        case .countup: return "arrow.up.forward.circle"
        case .streak: return "flame.fill"
        }
    }
}

enum RepeatRule: String, CaseIterable, Identifiable, Sendable {
    case none
    case daily
    case weekly
    case biweekly
    case monthly
    case yearly
    case customDays

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "Never"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .biweekly: return "Every 2 Weeks"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        case .customDays: return "Custom Days"
        }
    }

    func badgeLabel(customDays: Int) -> String? {
        switch self {
        case .none: return nil
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .biweekly: return "Biweekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        case .customDays:
            let days = max(1, customDays)
            return days == 1 ? "Every Day" : "Every \(days)d"
        }
    }
}

enum CountdownThemeColor: String, CaseIterable, Identifiable, Sendable {
    case orange
    case blue
    case indigo
    case green
    case teal
    case purple
    case red

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .orange: return .orange
        case .blue: return .blue
        case .indigo: return .indigo
        case .green: return .green
        case .teal: return .teal
        case .purple: return .purple
        case .red: return .red
        }
    }
}

enum CountdownSymbol {
    static let all: [String] = [
        "hourglass",
        "timer",
        "calendar",
        "flag.checkered",
        "airplane",
        "gift.fill",
        "flame.fill",
        "star.fill",
        "heart.fill",
        "trophy.fill",
        "graduationcap.fill",
        "figure.run",
        "sun.max.fill",
        "party.popper.fill",
        "bell.fill",
        "briefcase.fill"
    ]
}

enum DurationUnit: String, CaseIterable, Identifiable, Sendable {
    case minutes
    case hours
    case days

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }

    nonisolated var minutesMultiplier: Int {
        switch self {
        case .minutes: return 1
        case .hours: return 60
        case .days: return 1440
        }
    }
}

enum AlertLeadPreset: String, CaseIterable, Identifiable, Sendable {
    case none
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case oneDay
    case threeDays
    case oneWeek
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .fifteenMinutes: return "15 Minutes Before"
        case .thirtyMinutes: return "30 Minutes Before"
        case .oneHour: return "1 Hour Before"
        case .oneDay: return "1 Day Before"
        case .threeDays: return "3 Days Before"
        case .oneWeek: return "1 Week Before"
        case .custom: return "Custom…"
        }
    }

    var fixedMinutes: Int? {
        switch self {
        case .none: return 0
        case .fifteenMinutes: return 15
        case .thirtyMinutes: return 30
        case .oneHour: return 60
        case .oneDay: return 1440
        case .threeDays: return 4320
        case .oneWeek: return 10080
        case .custom: return nil
        }
    }

    static func from(minutes: Int) -> AlertLeadPreset {
        for preset in Self.allCases {
            if let fixed = preset.fixedMinutes, fixed == minutes {
                return preset
            }
        }
        return .custom
    }
}

// MARK: - SwiftData Model

@Model
final class CountdownItem {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var modeRaw: String = CountdownMode.countdown.rawValue
    var startDate: Date = Date()
    var targetDate: Date = Date()
    var hasTargetDate: Bool = true
    var isAllDay: Bool = false
    var repeatRuleRaw: String = RepeatRule.none.rawValue
    var customRepeatDays: Int = 7
    var alertsEnabled: Bool = false
    var alertAtCompletion: Bool = true
    var alertLeadMinutes: Int = 0
    var completedDayKeys: [String] = []
    var dailyReminderHour: Int = 20
    var dailyReminderMinute: Int = 0
    var colorToken: String = CountdownThemeColor.orange.rawValue
    var symbolName: String = "⏳"
    var isPinned: Bool = false
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        mode: CountdownMode = .countdown,
        startDate: Date = Date(),
        targetDate: Date = Date(),
        hasTargetDate: Bool = true,
        isAllDay: Bool = false,
        repeatRule: RepeatRule = .none,
        customRepeatDays: Int = 7,
        alertsEnabled: Bool = false,
        alertAtCompletion: Bool = true,
        alertLeadMinutes: Int = 0,
        completedDayKeys: [String] = [],
        dailyReminderHour: Int = 20,
        dailyReminderMinute: Int = 0,
        colorTheme: CountdownThemeColor = .orange,
        symbolName: String = "⏳",
        isPinned: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.modeRaw = mode.rawValue
        self.startDate = startDate
        self.targetDate = targetDate
        self.hasTargetDate = (mode == .countdown) ? true : hasTargetDate
        self.isAllDay = (mode == .streak) ? true : isAllDay
        self.repeatRuleRaw = (mode == .streak) ? RepeatRule.none.rawValue : repeatRule.rawValue
        self.customRepeatDays = TallyMath.clamp(customRepeatDays, min: 1, max: 3650)
        self.alertsEnabled = alertsEnabled
        self.alertAtCompletion = alertAtCompletion
        self.alertLeadMinutes = TallyMath.clamp(alertLeadMinutes, min: 0, max: 525_600)
        self.completedDayKeys = Array(Set(completedDayKeys)).sorted()
        self.dailyReminderHour = TallyMath.clamp(dailyReminderHour, min: 0, max: 23)
        self.dailyReminderMinute = TallyMath.clamp(dailyReminderMinute, min: 0, max: 59)
        self.colorToken = colorTheme.rawValue
        self.symbolName = symbolName
        self.isPinned = isPinned
        self.createdAt = createdAt
    }

    var mode: CountdownMode {
        get { CountdownMode(rawValue: modeRaw) ?? .countdown }
        set {
            modeRaw = newValue.rawValue
            if newValue == .countdown {
                hasTargetDate = true
            } else if newValue == .streak {
                isAllDay = true
                repeatRuleRaw = RepeatRule.none.rawValue
            }
        }
    }

    var repeatRule: RepeatRule {
        get { RepeatRule(rawValue: repeatRuleRaw) ?? .none }
        set { repeatRuleRaw = newValue.rawValue }
    }

    var colorTheme: CountdownThemeColor {
        get { CountdownThemeColor(rawValue: colorToken) ?? .orange }
        set { colorToken = newValue.rawValue }
    }

    var valueSnapshot: CountdownItemValue {
        CountdownItemValue(
            id: id,
            title: title,
            mode: mode,
            startDate: startDate,
            targetDate: targetDate,
            hasTargetDate: mode == .countdown ? true : hasTargetDate,
            isAllDay: mode == .streak ? true : isAllDay,
            repeatRule: mode == .streak ? .none : repeatRule,
            customRepeatDays: customRepeatDays,
            alertsEnabled: alertsEnabled,
            alertAtCompletion: alertAtCompletion,
            alertLeadMinutes: alertLeadMinutes,
            completedDayKeys: completedDayKeys,
            dailyReminderHour: dailyReminderHour,
            dailyReminderMinute: dailyReminderMinute
        )
    }

    func snapshot(at now: Date, calendar: Calendar = .current) -> CountdownSnapshot {
        CountdownCalculator.snapshot(for: valueSnapshot, at: now, calendar: calendar)
    }

    func streakSnapshot(at now: Date, calendar: Calendar = .current) -> StreakSnapshot {
        CountdownCalculator.streakSnapshot(for: valueSnapshot, at: now, calendar: calendar)
    }

    func isCompleted(on date: Date, calendar: Calendar = .current) -> Bool {
        let key = CountdownCalculator.dayKey(for: date, calendar: calendar)
        return completedDayKeys.contains(key)
    }

    /// Toggles streak completion for `date` only if `date` falls within `startDate...today`.
    /// Returns `true` if `completedDayKeys` changed.
    @discardableResult
    func toggleCompletion(on date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard mode == .streak else { return false }
        let day = calendar.startOfDay(for: date)
        let startDay = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: now)
        guard day >= startDay && day <= today else { return false }

        let key = CountdownCalculator.dayKey(for: day, calendar: calendar)
        var set = Set(completedDayKeys)
        if set.contains(key) {
            set.remove(key)
        } else {
            set.insert(key)
        }
        completedDayKeys = set.sorted()
        return true
    }

    /// Advances a repeating item past `now` when its current cycle has elapsed.
    /// Returns `true` if the item's dates were updated.
    @discardableResult
    func advanceIfRepeatingPast(_ now: Date, calendar: Calendar = .current) -> Bool {
        guard mode != .streak, repeatRule != .none, (mode == .countdown || hasTargetDate) else {
            return false
        }
        guard let next = CountdownCalculator.rolloverDates(
            startDate: startDate,
            targetDate: targetDate,
            isAllDay: isAllDay,
            repeatRule: repeatRule,
            customRepeatDays: customRepeatDays,
            now: now,
            calendar: calendar
        ) else {
            return false
        }
        startDate = next.startDate
        targetDate = next.targetDate
        return true
    }

    /// Restarts the item from `now`, preserving the previous cycle's duration when a target date is active.
    func restartCycle(from now: Date = Date(), calendar: Calendar = .current) {
        if mode == .streak {
            let today = calendar.startOfDay(for: now)
            let oldStart = calendar.startOfDay(for: startDate)
            let oldTarget = calendar.startOfDay(for: targetDate)
            let previousGoalDays = max(1, (calendar.dateComponents([.day], from: oldStart, to: oldTarget).day ?? 29) + 1)
            startDate = today
            if hasTargetDate {
                targetDate = calendar.date(byAdding: .day, value: previousGoalDays - 1, to: today) ?? today
            } else {
                targetDate = today
            }
            completedDayKeys = []
            return
        }

        let baseStart = isAllDay ? calendar.startOfDay(for: now) : now
        if mode == .countup && !hasTargetDate {
            startDate = baseStart
            targetDate = baseStart
            return
        }

        let currentStart = isAllDay ? calendar.startOfDay(for: startDate) : startDate
        let currentTarget = isAllDay ? calendar.startOfDay(for: targetDate) : targetDate
        let previousSpan = currentTarget.timeIntervalSince(currentStart)

        startDate = baseStart
        if repeatRule != .none {
            targetDate = CountdownCalculator.advanceDate(
                baseStart,
                by: repeatRule,
                customRepeatDays: customRepeatDays,
                steps: 1,
                calendar: calendar
            )
        } else if previousSpan > 60 {
            targetDate = baseStart.addingTimeInterval(previousSpan)
        } else {
            targetDate = calendar.date(byAdding: .day, value: 1, to: baseStart) ?? baseStart.addingTimeInterval(86_400)
        }
    }
}

// MARK: - Pure Value Snapshot & Calculation Engine

struct CountdownItemValue: Sendable, Equatable {
    let id: UUID
    let title: String
    let mode: CountdownMode
    let startDate: Date
    let targetDate: Date
    let hasTargetDate: Bool
    let isAllDay: Bool
    let repeatRule: RepeatRule
    let customRepeatDays: Int
    let alertsEnabled: Bool
    let alertAtCompletion: Bool
    let alertLeadMinutes: Int
    let completedDayKeys: [String]
    let dailyReminderHour: Int
    let dailyReminderMinute: Int

    nonisolated init(
        id: UUID,
        title: String,
        mode: CountdownMode,
        startDate: Date,
        targetDate: Date,
        hasTargetDate: Bool,
        isAllDay: Bool,
        repeatRule: RepeatRule,
        customRepeatDays: Int,
        alertsEnabled: Bool,
        alertAtCompletion: Bool,
        alertLeadMinutes: Int,
        completedDayKeys: [String] = [],
        dailyReminderHour: Int = 20,
        dailyReminderMinute: Int = 0
    ) {
        self.id = id
        self.title = title
        self.mode = mode
        self.startDate = startDate
        self.targetDate = targetDate
        self.hasTargetDate = hasTargetDate
        self.isAllDay = isAllDay
        self.repeatRule = repeatRule
        self.customRepeatDays = customRepeatDays
        self.alertsEnabled = alertsEnabled
        self.alertAtCompletion = alertAtCompletion
        self.alertLeadMinutes = alertLeadMinutes
        self.completedDayKeys = completedDayKeys
        self.dailyReminderHour = dailyReminderHour
        self.dailyReminderMinute = dailyReminderMinute
    }
}

struct StreakDayStatus: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date
    let isCompleted: Bool
    let isToday: Bool
    let isEditable: Bool
}

struct StreakSnapshot: Equatable, Sendable {
    let startDay: Date
    let endDay: Date?
    let today: Date
    let isCompletedToday: Bool
    let currentStreak: Int
    let longestStreak: Int
    let totalCompletedDays: Int
    let goalDays: Int?
    let progress: Double?
    let isComplete: Bool
    let recentSevenDays: [StreakDayStatus]

    nonisolated var primaryHeadline: String {
        if let goalDays, goalDays > 0 {
            if isComplete {
                return "Goal Reached (\(goalDays)d)"
            }
            return "\(currentStreak) / \(goalDays) \(goalDays == 1 ? "Day" : "Days")"
        }
        return currentStreak == 1 ? "1 Day Streak" : "\(currentStreak) Day Streak"
    }
}

struct CountdownDurationBreakdown: Equatable, Sendable {
    let totalSeconds: Int
    let days: Int
    let hours: Int
    let minutes: Int
    let seconds: Int

    nonisolated init(totalSeconds: Int) {
        let clamped = max(0, totalSeconds)
        self.totalSeconds = clamped
        self.days = clamped / 86_400
        let afterDays = clamped % 86_400
        self.hours = afterDays / 3_600
        let afterHours = afterDays % 3_600
        self.minutes = afterHours / 60
        self.seconds = afterHours % 60
    }

    nonisolated func formattedCompact(isAllDay: Bool) -> String {
        if isAllDay {
            if days == 0 {
                return hours > 0 || minutes > 0 ? "< 1 Day" : "Today"
            }
            return days == 1 ? "1 Day" : "\(days) Days"
        }

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

struct CountdownSnapshot: Equatable, Sendable {
    let mode: CountdownMode
    let isAllDay: Bool
    let isComplete: Bool
    let isUpcomingStart: Bool
    let hasGoal: Bool
    let effectiveStartDate: Date
    let effectiveTargetDate: Date?
    let primaryBreakdown: CountdownDurationBreakdown
    let remainingToGoal: CountdownDurationBreakdown?
    let progress: Double?
    let elapsedDaysCount: Int
    let totalGoalDays: Int?
    let streak: StreakSnapshot?

    nonisolated var primaryHeadline: String {
        switch mode {
        case .countdown:
            if isComplete {
                return isAllDay ? "Today / Reached" : "Reached!"
            }
            return primaryBreakdown.formattedCompact(isAllDay: isAllDay)
        case .countup:
            if isUpcomingStart {
                return "Starts in \(primaryBreakdown.formattedCompact(isAllDay: isAllDay))"
            }
            if hasGoal, let goalDays = totalGoalDays, goalDays > 0 {
                if isComplete {
                    return "Completed (\(goalDays)d)"
                }
                if isAllDay {
                    let displayDay = min(elapsedDaysCount + 1, goalDays)
                    return "Day \(displayDay) of \(goalDays)"
                }
            }
            return primaryBreakdown.formattedCompact(isAllDay: isAllDay)
        case .streak:
            return streak?.primaryHeadline ?? "0 Day Streak"
        }
    }
}

struct ScheduledAlert: Equatable, Sendable {
    enum Kind: String, Sendable {
        case lead
        case completion
        case dailyReminder
    }

    let identifier: String
    let kind: Kind
    let fireDate: Date
    let title: String
    let body: String
}

struct ScheduledDailyReminder: Equatable, Sendable {
    let identifier: String
    let hour: Int
    let minute: Int
    let title: String
    let body: String
}

enum CountdownCalculator: Sendable {
    nonisolated static let maxLeadMinutes = 525_600 // 365 days

    nonisolated static func notificationIdentifier(for itemID: UUID, kind: ScheduledAlert.Kind) -> String {
        "tally-count-\(itemID.uuidString)-\(kind.rawValue)"
    }

    nonisolated static func allNotificationIdentifiers(for itemID: UUID) -> [String] {
        [
            notificationIdentifier(for: itemID, kind: .lead),
            notificationIdentifier(for: itemID, kind: .completion),
            notificationIdentifier(for: itemID, kind: .dailyReminder)
        ]
    }

    nonisolated static func normalizeDate(_ date: Date, isAllDay: Bool, calendar: Calendar = .current) -> Date {
        isAllDay ? calendar.startOfDay(for: date) : date
    }

    /// DST-safe duration addition (uses calendar `.day` addition when `unit == .days`).
    nonisolated static func addDuration(
        amount: Int,
        unit: DurationUnit,
        to baseDate: Date,
        isAllDay: Bool,
        calendar: Calendar = .current
    ) -> Date {
        let clamped = max(1, amount)
        let normalizedBase = normalizeDate(baseDate, isAllDay: isAllDay, calendar: calendar)
        let computed: Date
        switch unit {
        case .days:
            computed = calendar.date(byAdding: .day, value: clamped, to: normalizedBase) ?? normalizedBase
        case .hours:
            computed = calendar.date(byAdding: .hour, value: clamped, to: normalizedBase) ?? normalizedBase
        case .minutes:
            computed = calendar.date(byAdding: .minute, value: clamped, to: normalizedBase) ?? normalizedBase
        }
        return normalizeDate(computed, isAllDay: isAllDay, calendar: calendar)
    }

    /// Formats a progress ratio (`0.0...1.0`) accurately without hiding early progress at `0%`
    /// or falsely rounding `99.6%` to `100%` before completion.
    nonisolated static func formatProgressPercent(_ progress: Double, isComplete: Bool) -> String {
        if isComplete || progress >= 1.0 {
            return "100%"
        }
        let clamped = min(max(progress, 0.0), 0.9999)
        if clamped <= 0.0 {
            return "0%"
        }
        let pct = clamped * 100.0
        if pct < 0.1 {
            return "< 0.1%"
        }
        if pct < 10.0 {
            let tenths = floor(pct * 10.0) / 10.0
            if tenths.truncatingRemainder(dividingBy: 1.0) == 0 {
                return "\(Int(tenths))%"
            }
            return String(format: "%.1f%%", tenths)
        }
        return "\(min(99, Int(floor(pct))))%"
    }

    // MARK: - Day Keys (Timezone & DST-Safe Calendar Dates)

    nonisolated static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 1970
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    nonisolated static func date(fromDayKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        var comps = DateComponents()
        comps.calendar = calendar
        comps.timeZone = calendar.timeZone
        comps.year = year
        comps.month = month
        comps.day = day
        return calendar.date(from: comps)
    }

    // MARK: - Streak Snapshot Calculation

    nonisolated static func streakSnapshot(
        for item: CountdownItemValue,
        at now: Date,
        calendar: Calendar = .current
    ) -> StreakSnapshot {
        let startDay = calendar.startOfDay(for: item.startDate)
        let today = calendar.startOfDay(for: now)
        let endDay: Date? = item.hasTargetDate ? calendar.startOfDay(for: item.targetDate) : nil

        let goalDays: Int?
        if let endDay {
            let diff = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
            goalDays = max(1, diff + 1) // Inclusive day count (e.g. Nov 1..Nov 30 = 30 days)
        } else {
            goalDays = nil
        }

        // Keep only valid dates within startDay...today
        let validDates: Set<Date> = Set(
            item.completedDayKeys.compactMap { key -> Date? in
                guard let parsed = date(fromDayKey: key, calendar: calendar) else { return nil }
                let normalized = calendar.startOfDay(for: parsed)
                guard normalized >= startDay && normalized <= today else { return nil }
                return normalized
            }
        )

        let isCompletedToday = validDates.contains(today)

        // Current consecutive streak: ends at today (if completed today) or yesterday (if still active today).
        // Resets to 0 if yesterday was missed and today is not completed.
        var currentStreak = 0
        let anchorDay: Date?
        if isCompletedToday {
            anchorDay = today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  yesterday >= startDay,
                  validDates.contains(yesterday) {
            anchorDay = yesterday
        } else {
            anchorDay = nil
        }

        if var cursor = anchorDay {
            while cursor >= startDay && validDates.contains(cursor) {
                currentStreak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = prev
            }
        }

        // Longest consecutive streak across all valid completed days
        let sortedDates = validDates.sorted()
        var longestStreak = 0
        var run = 0
        var previousDate: Date?
        for day in sortedDates {
            if let prev = previousDate,
               let expectedNext = calendar.date(byAdding: .day, value: 1, to: prev),
               calendar.isDate(day, inSameDayAs: expectedNext) {
                run += 1
            } else {
                run = 1
            }
            longestStreak = max(longestStreak, run)
            previousDate = day
        }

        // Progress is based on current consecutive streak / goalDays (resets if a day is missed)
        let progress: Double?
        let isComplete: Bool
        if let goalDays, goalDays > 0 {
            let ratio = min(max(Double(currentStreak) / Double(goalDays), 0.0), 1.0)
            progress = ratio
            isComplete = currentStreak >= goalDays
        } else {
            progress = nil
            isComplete = false
        }

        // Last 7 days ending today for quick card visualization
        var recent: [StreakDayStatus] = []
        for offset in stride(from: -6, through: 0, by: 1) {
            if let day = calendar.date(byAdding: .day, value: offset, to: today) {
                let normalized = calendar.startOfDay(for: day)
                recent.append(
                    StreakDayStatus(
                        id: dayKey(for: normalized, calendar: calendar),
                        date: normalized,
                        isCompleted: validDates.contains(normalized),
                        isToday: offset == 0,
                        isEditable: normalized >= startDay && normalized <= today
                    )
                )
            }
        }

        return StreakSnapshot(
            startDay: startDay,
            endDay: endDay,
            today: today,
            isCompletedToday: isCompletedToday,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            totalCompletedDays: validDates.count,
            goalDays: goalDays,
            progress: progress,
            isComplete: isComplete,
            recentSevenDays: recent
        )
    }

    // MARK: - Recurrence & Countdown/Countup Snapshot

    nonisolated static func advanceDate(
        _ date: Date,
        by rule: RepeatRule,
        customRepeatDays: Int,
        steps: Int = 1,
        calendar: Calendar = .current
    ) -> Date {
        guard steps > 0 else { return date }
        switch rule {
        case .none:
            return date
        case .daily:
            return calendar.date(byAdding: .day, value: steps, to: date) ?? date
        case .weekly:
            return calendar.date(byAdding: .day, value: TallyMath.multiply(7, steps), to: date) ?? date
        case .biweekly:
            return calendar.date(byAdding: .day, value: TallyMath.multiply(14, steps), to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: steps, to: date) ?? date
        case .yearly:
            return calendar.date(byAdding: .year, value: steps, to: date) ?? date
        case .customDays:
            let interval = max(1, customRepeatDays)
            return calendar.date(byAdding: .day, value: TallyMath.multiply(interval, steps), to: date) ?? date
        }
    }

    /// Computes the next future `(startDate, targetDate)` pair for a repeating item if its target has passed `now`.
    /// Uses O(1) calendar jumps so arbitrarily old dates never stall.
    nonisolated static func rolloverDates(
        startDate: Date,
        targetDate: Date,
        isAllDay: Bool,
        repeatRule: RepeatRule,
        customRepeatDays: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> (startDate: Date, targetDate: Date)? {
        guard repeatRule != .none else { return nil }

        let effectiveTarget = normalizeDate(targetDate, isAllDay: isAllDay, calendar: calendar)
        guard effectiveTarget <= now else { return nil }

        let effectiveStart = normalizeDate(startDate, isAllDay: isAllDay, calendar: calendar)
        let preservedSpan = effectiveTarget.timeIntervalSince(effectiveStart)

        let steps: Int
        switch repeatRule {
        case .none:
            return nil
        case .daily, .weekly, .biweekly, .customDays:
            let intervalDays: Int
            switch repeatRule {
            case .daily: intervalDays = 1
            case .weekly: intervalDays = 7
            case .biweekly: intervalDays = 14
            case .customDays: intervalDays = max(1, customRepeatDays)
            default: intervalDays = 1
            }
            let elapsedDays = max(0, calendar.dateComponents([.day], from: effectiveTarget, to: now).day ?? 0)
            steps = (elapsedDays / intervalDays) + 1
        case .monthly:
            let elapsedMonths = max(0, calendar.dateComponents([.month], from: effectiveTarget, to: now).month ?? 0)
            steps = elapsedMonths + 1
        case .yearly:
            let elapsedYears = max(0, calendar.dateComponents([.year], from: effectiveTarget, to: now).year ?? 0)
            steps = elapsedYears + 1
        }

        var currentStep = max(1, steps)
        var candidateTarget = advanceDate(
            effectiveTarget,
            by: repeatRule,
            customRepeatDays: customRepeatDays,
            steps: currentStep,
            calendar: calendar
        )

        var guardIterations = 0
        while candidateTarget <= now && guardIterations < 4 {
            currentStep += 1
            candidateTarget = advanceDate(
                effectiveTarget,
                by: repeatRule,
                customRepeatDays: customRepeatDays,
                steps: currentStep,
                calendar: calendar
            )
            guardIterations += 1
        }

        let previousTarget = advanceDate(
            effectiveTarget,
            by: repeatRule,
            customRepeatDays: customRepeatDays,
            steps: currentStep - 1,
            calendar: calendar
        )

        let newStart: Date
        if preservedSpan > 0 && preservedSpan < candidateTarget.timeIntervalSince(previousTarget) {
            newStart = normalizeDate(candidateTarget.addingTimeInterval(-preservedSpan), isAllDay: isAllDay, calendar: calendar)
        } else {
            newStart = normalizeDate(previousTarget, isAllDay: isAllDay, calendar: calendar)
        }

        return (startDate: newStart, targetDate: normalizeDate(candidateTarget, isAllDay: isAllDay, calendar: calendar))
    }

    nonisolated static func snapshot(
        for item: CountdownItemValue,
        at now: Date,
        calendar: Calendar = .current
    ) -> CountdownSnapshot {
        let effectiveStart = normalizeDate(item.startDate, isAllDay: item.isAllDay, calendar: calendar)
        let hasGoal = (item.mode == .countdown) || item.hasTargetDate
        let effectiveTarget = hasGoal ? normalizeDate(item.targetDate, isAllDay: item.isAllDay, calendar: calendar) : nil

        switch item.mode {
        case .countdown:
            let target = effectiveTarget ?? effectiveStart
            let remainingInterval = target.timeIntervalSince(now)
            let isComplete = remainingInterval <= 0
            let remainingSeconds = isComplete ? 0 : Int(ceil(remainingInterval))
            let breakdown = CountdownDurationBreakdown(totalSeconds: remainingSeconds)

            let totalSpan = target.timeIntervalSince(effectiveStart)
            let progress: Double?
            if totalSpan > 0 {
                let elapsed = now.timeIntervalSince(effectiveStart)
                progress = min(max(elapsed / totalSpan, 0.0), 1.0)
            } else {
                progress = isComplete ? 1.0 : 0.0
            }

            return CountdownSnapshot(
                mode: .countdown,
                isAllDay: item.isAllDay,
                isComplete: isComplete,
                isUpcomingStart: false,
                hasGoal: true,
                effectiveStartDate: effectiveStart,
                effectiveTargetDate: target,
                primaryBreakdown: breakdown,
                remainingToGoal: breakdown,
                progress: progress,
                elapsedDaysCount: 0,
                totalGoalDays: totalSpan > 0 ? max(1, Int(round(totalSpan / 86_400))) : nil,
                streak: nil
            )

        case .countup:
            let elapsedInterval = now.timeIntervalSince(effectiveStart)
            if elapsedInterval < 0 {
                let untilStart = Int(ceil(-elapsedInterval))
                let goalDays: Int? = effectiveTarget.flatMap { target in
                    let span = target.timeIntervalSince(effectiveStart)
                    return span > 0 ? max(1, Int(round(span / 86_400))) : nil
                }
                return CountdownSnapshot(
                    mode: .countup,
                    isAllDay: item.isAllDay,
                    isComplete: false,
                    isUpcomingStart: true,
                    hasGoal: hasGoal,
                    effectiveStartDate: effectiveStart,
                    effectiveTargetDate: effectiveTarget,
                    primaryBreakdown: CountdownDurationBreakdown(totalSeconds: untilStart),
                    remainingToGoal: effectiveTarget.map {
                        CountdownDurationBreakdown(totalSeconds: max(0, Int(ceil($0.timeIntervalSince(now)))))
                    },
                    progress: hasGoal ? 0.0 : nil,
                    elapsedDaysCount: 0,
                    totalGoalDays: goalDays,
                    streak: nil
                )
            }

            let elapsedSeconds = Int(floor(elapsedInterval))
            let elapsedDays = max(0, calendar.dateComponents([.day], from: effectiveStart, to: now).day ?? (elapsedSeconds / 86_400))

            if let target = effectiveTarget, hasGoal {
                let totalSpan = target.timeIntervalSince(effectiveStart)
                let remainingInterval = target.timeIntervalSince(now)
                let isComplete = remainingInterval <= 0
                let clampedElapsedSeconds = isComplete && totalSpan > 0 ? Int(totalSpan) : elapsedSeconds
                let remainingBreakdown = CountdownDurationBreakdown(
                    totalSeconds: isComplete ? 0 : Int(ceil(remainingInterval))
                )
                let progress: Double = totalSpan > 0
                    ? min(max(elapsedInterval / totalSpan, 0.0), 1.0)
                    : (isComplete ? 1.0 : 0.0)
                let goalDays = totalSpan > 0 ? max(1, Int(round(totalSpan / 86_400))) : nil

                return CountdownSnapshot(
                    mode: .countup,
                    isAllDay: item.isAllDay,
                    isComplete: isComplete,
                    isUpcomingStart: false,
                    hasGoal: true,
                    effectiveStartDate: effectiveStart,
                    effectiveTargetDate: target,
                    primaryBreakdown: CountdownDurationBreakdown(totalSeconds: clampedElapsedSeconds),
                    remainingToGoal: remainingBreakdown,
                    progress: progress,
                    elapsedDaysCount: elapsedDays,
                    totalGoalDays: goalDays,
                    streak: nil
                )
            } else {
                return CountdownSnapshot(
                    mode: .countup,
                    isAllDay: item.isAllDay,
                    isComplete: false,
                    isUpcomingStart: false,
                    hasGoal: false,
                    effectiveStartDate: effectiveStart,
                    effectiveTargetDate: nil,
                    primaryBreakdown: CountdownDurationBreakdown(totalSeconds: elapsedSeconds),
                    remainingToGoal: nil,
                    progress: nil,
                    elapsedDaysCount: elapsedDays,
                    totalGoalDays: nil,
                    streak: nil
                )
            }

        case .streak:
            let streakSnap = streakSnapshot(for: item, at: now, calendar: calendar)
            let totalSeconds = streakSnap.currentStreak * 86_400
            return CountdownSnapshot(
                mode: .streak,
                isAllDay: true,
                isComplete: streakSnap.isComplete,
                isUpcomingStart: streakSnap.today < streakSnap.startDay,
                hasGoal: streakSnap.goalDays != nil,
                effectiveStartDate: streakSnap.startDay,
                effectiveTargetDate: streakSnap.endDay,
                primaryBreakdown: CountdownDurationBreakdown(totalSeconds: totalSeconds),
                remainingToGoal: streakSnap.goalDays.map { goal in
                    CountdownDurationBreakdown(totalSeconds: max(0, goal - streakSnap.currentStreak) * 86_400)
                },
                progress: streakSnap.progress,
                elapsedDaysCount: streakSnap.currentStreak,
                totalGoalDays: streakSnap.goalDays,
                streak: streakSnap
            )
        }
    }

    // MARK: - Alerts

    nonisolated static func scheduledAlerts(
        for item: CountdownItemValue,
        at now: Date,
        calendar: Calendar = .current
    ) -> [ScheduledAlert] {
        guard item.mode != .streak else { return [] }
        guard item.alertsEnabled else { return [] }
        guard item.mode == .countdown || item.hasTargetDate else { return [] }

        let target = normalizeDate(item.targetDate, isAllDay: item.isAllDay, calendar: calendar)
        let displayTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Tally: Count"
            : item.title.trimmingCharacters(in: .whitespacesAndNewlines)

        var alerts: [ScheduledAlert] = []

        if item.alertLeadMinutes > 0 {
            let leadSeconds = TimeInterval(min(item.alertLeadMinutes, maxLeadMinutes) * 60)
            let leadFireDate = target.addingTimeInterval(-leadSeconds)
            if leadFireDate > now {
                let leadDescription = formatLeadTime(minutes: item.alertLeadMinutes)
                let body = item.mode == .countdown
                    ? "\(displayTitle) is \(leadDescription) away."
                    : "\(displayTitle) reaches its goal in \(leadDescription)."
                alerts.append(
                    ScheduledAlert(
                        identifier: notificationIdentifier(for: item.id, kind: .lead),
                        kind: .lead,
                        fireDate: leadFireDate,
                        title: displayTitle,
                        body: body
                    )
                )
            }
        }

        if item.alertAtCompletion && target > now {
            let body = item.mode == .countdown
                ? "Your countdown for \(displayTitle) has arrived!"
                : "You reached your goal for \(displayTitle)!"
            alerts.append(
                ScheduledAlert(
                    identifier: notificationIdentifier(for: item.id, kind: .completion),
                    kind: .completion,
                    fireDate: target,
                    title: displayTitle,
                    body: body
                )
            )
        }

        return alerts
    }

    nonisolated static func dailyReminder(
        for item: CountdownItemValue,
        at now: Date,
        calendar: Calendar = .current
    ) -> ScheduledDailyReminder? {
        guard item.mode == .streak && item.alertsEnabled else { return nil }
        let snap = streakSnapshot(for: item, at: now, calendar: calendar)
        guard !snap.isComplete else { return nil }

        let displayTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Tally: Count"
            : item.title.trimmingCharacters(in: .whitespacesAndNewlines)

        return ScheduledDailyReminder(
            identifier: notificationIdentifier(for: item.id, kind: .dailyReminder),
            hour: TallyMath.clamp(item.dailyReminderHour, min: 0, max: 23),
            minute: TallyMath.clamp(item.dailyReminderMinute, min: 0, max: 59),
            title: displayTitle,
            body: "Don't forget to check in today to keep your \(displayTitle) streak going!"
        )
    }

    nonisolated static func formatLeadTime(minutes: Int) -> String {
        let clamped = max(0, minutes)
        if clamped == 0 { return "None" }

        let days = clamped / 1440
        let remainingAfterDays = clamped % 1440
        let hours = remainingAfterDays / 60
        let mins = remainingAfterDays % 60

        var parts: [String] = []
        if days > 0 {
            parts.append(days == 1 ? "1 day" : "\(days) days")
        }
        if hours > 0 {
            parts.append(hours == 1 ? "1 hour" : "\(hours) hours")
        }
        if mins > 0 {
            parts.append(mins == 1 ? "1 minute" : "\(mins) minutes")
        }
        return parts.joined(separator: " ")
    }

    nonisolated static func formatDailyReminderTime(hour: Int, minute: Int, calendar: Calendar = .current) -> String {
        var comps = DateComponents()
        comps.hour = TallyMath.clamp(hour, min: 0, max: 23)
        comps.minute = TallyMath.clamp(minute, min: 0, max: 59)
        let date = calendar.date(from: comps) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
