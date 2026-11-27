import Foundation
import SwiftData
import TallyCore
import Testing
@preconcurrency import UserNotifications
@testable import Tally_Count

@MainActor
private final class MockNotificationClient: NotificationCenterClient {
    var status: UNAuthorizationStatus
    var grantedOnRequest: Bool
    var addedRequests: [UNNotificationRequest] = []
    var removedIdentifiers: [[String]] = []

    init(status: UNAuthorizationStatus = .authorized, grantedOnRequest: Bool = true) {
        self.status = status
        self.grantedOnRequest = grantedOnRequest
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func requestAuthorization() async throws -> Bool {
        grantedOnRequest
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(identifiers)
    }
}

@Suite("CountdownCalculator, Streaks & Recurrence Tests")
struct CountdownCalculatorTests {
    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return cal
    }

    private func makeUTCDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) -> Date {
        let components = DateComponents(
            calendar: utcCalendar,
            timeZone: utcCalendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
        return utcCalendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    @Test("Countdown computes remaining breakdown, progress, and completion accurately")
    func countdownBreakdownAndCompletion() {
        let start = makeUTCDate(year: 2026, month: 6, day: 1, hour: 12, minute: 0)
        let target = makeUTCDate(year: 2026, month: 6, day: 11, hour: 12, minute: 0)
        let halfway = makeUTCDate(year: 2026, month: 6, day: 6, hour: 12, minute: 0)

        let item = CountdownItemValue(
            id: UUID(),
            title: "Launch Day",
            mode: .countdown,
            startDate: start,
            targetDate: target,
            hasTargetDate: true,
            isAllDay: false,
            repeatRule: .none,
            customRepeatDays: 7,
            alertsEnabled: false,
            alertAtCompletion: true,
            alertLeadMinutes: 0
        )

        let midSnap = CountdownCalculator.snapshot(for: item, at: halfway, calendar: utcCalendar)
        #expect(!midSnap.isComplete)
        #expect(midSnap.primaryBreakdown.days == 5)
        #expect(midSnap.progress == 0.5)

        let doneSnap = CountdownCalculator.snapshot(for: item, at: target.addingTimeInterval(10), calendar: utcCalendar)
        #expect(doneSnap.isComplete)
        #expect(doneSnap.primaryBreakdown.totalSeconds == 0)
        #expect(doneSnap.progress == 1.0)
    }

    @Test("Goal-based countup tracks elapsed days, accurate percent formatting, and completion")
    func goalBasedCountupAndPercentFormatting() {
        let start = makeUTCDate(year: 2026, month: 7, day: 1)
        let target = CountdownCalculator.addDuration(amount: 20, unit: .days, to: start, isAllDay: true, calendar: utcCalendar)
        #expect(target == makeUTCDate(year: 2026, month: 7, day: 21))

        let item = CountdownItemValue(
            id: UUID(),
            title: "20-Day Challenge",
            mode: .countup,
            startDate: start,
            targetDate: target,
            hasTargetDate: true,
            isAllDay: true,
            repeatRule: .none,
            customRepeatDays: 20,
            alertsEnabled: true,
            alertAtCompletion: true,
            alertLeadMinutes: 1440
        )

        // Day 1 shows "Day 1 of 20" (not Day 0)
        let day1Early = makeUTCDate(year: 2026, month: 7, day: 1, hour: 2, minute: 0)
        let day1Snap = CountdownCalculator.snapshot(for: item, at: day1Early, calendar: utcCalendar)
        #expect(day1Snap.primaryHeadline == "Day 1 of 20")
        #expect(CountdownCalculator.formatProgressPercent(day1Snap.progress ?? 0, isComplete: false) == "0.4%")

        // Day 6 (5 full days elapsed = 25%)
        let day6 = makeUTCDate(year: 2026, month: 7, day: 6)
        let snap = CountdownCalculator.snapshot(for: item, at: day6, calendar: utcCalendar)
        #expect(!snap.isComplete)
        #expect(snap.elapsedDaysCount == 5)
        #expect(snap.totalGoalDays == 20)
        #expect(snap.progress == 0.25)
        #expect(CountdownCalculator.formatProgressPercent(snap.progress ?? 0, isComplete: false) == "25%")

        // Tiny progress shows < 0.1%, near-complete never falsely rounds to 100%
        #expect(CountdownCalculator.formatProgressPercent(0.0, isComplete: false) == "0%")
        #expect(CountdownCalculator.formatProgressPercent(0.0002, isComplete: false) == "< 0.1%")
        #expect(CountdownCalculator.formatProgressPercent(0.996, isComplete: false) == "99%")
        #expect(CountdownCalculator.formatProgressPercent(1.0, isComplete: true) == "100%")

        let finishedSnap = CountdownCalculator.snapshot(for: item, at: target, calendar: utcCalendar)
        #expect(finishedSnap.isComplete)
        #expect(finishedSnap.progress == 1.0)
        #expect(finishedSnap.primaryHeadline == "Completed (20d)")
    }

    @Test("Open-ended countup counts upward continuously and handles upcoming start dates")
    func openEndedCountup() {
        let start = makeUTCDate(year: 2026, month: 8, day: 10, hour: 9, minute: 0)
        let beforeStart = makeUTCDate(year: 2026, month: 8, day: 8, hour: 9, minute: 0)
        let afterStart = makeUTCDate(year: 2026, month: 8, day: 13, hour: 11, minute: 30)

        let item = CountdownItemValue(
            id: UUID(),
            title: "Days Since Move",
            mode: .countup,
            startDate: start,
            targetDate: start,
            hasTargetDate: false,
            isAllDay: false,
            repeatRule: .none,
            customRepeatDays: 7,
            alertsEnabled: true,
            alertAtCompletion: true,
            alertLeadMinutes: 60
        )

        let upcomingSnap = CountdownCalculator.snapshot(for: item, at: beforeStart, calendar: utcCalendar)
        #expect(upcomingSnap.isUpcomingStart)
        #expect(upcomingSnap.primaryBreakdown.days == 2)
        #expect(upcomingSnap.progress == nil)

        let elapsedSnap = CountdownCalculator.snapshot(for: item, at: afterStart, calendar: utcCalendar)
        #expect(!elapsedSnap.isUpcomingStart)
        #expect(!elapsedSnap.isComplete)
        #expect(elapsedSnap.primaryBreakdown.days == 3)
        #expect(elapsedSnap.primaryBreakdown.hours == 2)
        #expect(elapsedSnap.primaryBreakdown.minutes == 30)
        #expect(CountdownCalculator.scheduledAlerts(for: item, at: beforeStart, calendar: utcCalendar).isEmpty)
    }

    @Test("Streak computes current consecutive streak, resets on missed day, and updates on past-day backfill")
    func streakConsecutiveProgressAndBackfill() {
        let start = makeUTCDate(year: 2026, month: 11, day: 1)
        let end = makeUTCDate(year: 2026, month: 11, day: 10) // 10-day inclusive goal
        let nov5 = makeUTCDate(year: 2026, month: 11, day: 5, hour: 14, minute: 0)

        // Completed Nov 1, 2, 4 (missed Nov 3, not yet checked in Nov 5) -> currentStreak = 1 (Nov 4), longest = 2 (Nov 1-2)
        let brokenItem = CountdownItemValue(
            id: UUID(),
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
            completedDayKeys: ["2026-11-01", "2026-11-02", "2026-11-04"],
            dailyReminderHour: 20,
            dailyReminderMinute: 0
        )

        let snap1 = CountdownCalculator.streakSnapshot(for: brokenItem, at: nov5, calendar: utcCalendar)
        #expect(!snap1.isCompletedToday)
        #expect(snap1.currentStreak == 1)
        #expect(snap1.longestStreak == 2)
        #expect(snap1.totalCompletedDays == 3)
        #expect(snap1.goalDays == 10)
        #expect(snap1.progress == 0.1) // Current consecutive streak (1) / 10

        // Missed yesterday too (Nov 4 removed) -> current streak resets to 0 and progress resets to 0%
        let resetItem = CountdownItemValue(
            id: brokenItem.id,
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
            completedDayKeys: ["2026-11-01", "2026-11-02"],
            dailyReminderHour: 20,
            dailyReminderMinute: 0
        )
        let snapReset = CountdownCalculator.streakSnapshot(for: resetItem, at: nov5, calendar: utcCalendar)
        #expect(snapReset.currentStreak == 0)
        #expect(snapReset.longestStreak == 2)
        #expect(snapReset.progress == 0.0)

        // Backfilling Nov 3 + checking in Nov 5 restores continuous 5-day streak (50% of 10-day goal)
        let backfilledItem = CountdownItemValue(
            id: brokenItem.id,
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
            completedDayKeys: ["2026-11-01", "2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05"],
            dailyReminderHour: 20,
            dailyReminderMinute: 0
        )
        let snapBackfilled = CountdownCalculator.streakSnapshot(for: backfilledItem, at: nov5, calendar: utcCalendar)
        #expect(snapBackfilled.isCompletedToday)
        #expect(snapBackfilled.currentStreak == 5)
        #expect(snapBackfilled.longestStreak == 5)
        #expect(snapBackfilled.progress == 0.5)
        #expect(!snapBackfilled.isComplete)
    }

    @Test("Recurrence rollover handles monthly month-end clamping and multi-year custom intervals")
    func recurrenceRollover() {
        let jan1 = makeUTCDate(year: 2026, month: 1, day: 1)
        let jan31 = makeUTCDate(year: 2026, month: 1, day: 31)
        let feb2 = makeUTCDate(year: 2026, month: 2, day: 2)

        let rolledMonthly = CountdownCalculator.rolloverDates(
            startDate: jan1,
            targetDate: jan31,
            isAllDay: true,
            repeatRule: .monthly,
            customRepeatDays: 7,
            now: feb2,
            calendar: utcCalendar
        )
        #expect(rolledMonthly?.targetDate == makeUTCDate(year: 2026, month: 2, day: 28))

        let oldStart = makeUTCDate(year: 2024, month: 1, day: 1)
        let oldTarget = makeUTCDate(year: 2024, month: 1, day: 21)
        let now = makeUTCDate(year: 2026, month: 1, day: 10)

        let rolledCustom = CountdownCalculator.rolloverDates(
            startDate: oldStart,
            targetDate: oldTarget,
            isAllDay: true,
            repeatRule: .customDays,
            customRepeatDays: 20,
            now: now,
            calendar: utcCalendar
        )
        #expect(rolledCustom != nil)
        if let rolledCustom {
            #expect(rolledCustom.targetDate > now)
            #expect(rolledCustom.startDate <= now)
        }
    }

    @Test("Scheduled alerts calculate lead-time and completion fire dates and skip past triggers")
    func scheduledAlertCalculation() {
        let now = makeUTCDate(year: 2026, month: 9, day: 1, hour: 10, minute: 0)
        let target = makeUTCDate(year: 2026, month: 9, day: 2, hour: 10, minute: 0)

        let item = CountdownItemValue(
            id: UUID(),
            title: "Flight",
            mode: .countdown,
            startDate: now,
            targetDate: target,
            hasTargetDate: true,
            isAllDay: false,
            repeatRule: .none,
            customRepeatDays: 7,
            alertsEnabled: true,
            alertAtCompletion: true,
            alertLeadMinutes: 120
        )

        let alerts = CountdownCalculator.scheduledAlerts(for: item, at: now, calendar: utcCalendar)
        #expect(alerts.count == 2)
        #expect(alerts[0].kind == .lead)
        #expect(alerts[0].fireDate == makeUTCDate(year: 2026, month: 9, day: 2, hour: 8, minute: 0))
        #expect(alerts[1].kind == .completion)
        #expect(alerts[1].fireDate == target)

        let oneHourBefore = makeUTCDate(year: 2026, month: 9, day: 2, hour: 9, minute: 0)
        let remainingAlerts = CountdownCalculator.scheduledAlerts(for: item, at: oneHourBefore, calendar: utcCalendar)
        #expect(remainingAlerts.count == 1)
        #expect(remainingAlerts[0].kind == .completion)

        #expect(CountdownCalculator.formatLeadTime(minutes: 1500) == "1 day 1 hour")
    }

    @Test("CountdownIconCatalog distinguishes emojis from SF Symbols and extracts custom emojis safely")
    func iconCatalogEmojiDetection() {
        #expect(CountdownIconCatalog.isEmoji("⏳"))
        #expect(CountdownIconCatalog.isEmoji("🏖️"))
        #expect(CountdownIconCatalog.isEmoji("🏋️‍♀️"))
        #expect(!CountdownIconCatalog.isEmoji("hourglass"))
        #expect(!CountdownIconCatalog.isEmoji("gift.fill"))
        #expect(!CountdownIconCatalog.isEmoji(""))

        #expect(CountdownIconCatalog.extractFirstEmoji(from: "🎉🥳") == "🎉")
        #expect(CountdownIconCatalog.extractFirstEmoji(from: "Trip ✈️!") == "✈️")
        #expect(CountdownIconCatalog.extractFirstEmoji(from: "abc123") == nil)
    }

    @Test("TallyCountDeepLink builds and parses item and new timer URLs cleanly")
    func deepLinkRoundTrip() {
        let id = UUID()
        let itemURL = TallyCountDeepLink.item(id).url
        #expect(TallyCountDeepLink.parse(itemURL) == .item(id))

        let newURL = TallyCountDeepLink.newTimer.url
        #expect(TallyCountDeepLink.parse(newURL) == .newTimer)

        #expect(TallyCountDeepLink.parse(URL(string: "https://example.com")!) == nil)
    }
}

@Suite("Tally Count Persistence & Notification Scheduler Tests")
@MainActor
struct CountdownLifecycleTests {
    @Test("NotificationScheduler schedules countdown alerts and repeating daily streak reminders")
    func notificationSchedulerSync() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let target = now.addingTimeInterval(86_400)

        let countdownItem = CountdownItemValue(
            id: UUID(),
            title: "Anniversary",
            mode: .countdown,
            startDate: now,
            targetDate: target,
            hasTargetDate: true,
            isAllDay: false,
            repeatRule: .yearly,
            customRepeatDays: 7,
            alertsEnabled: true,
            alertAtCompletion: true,
            alertLeadMinutes: 60
        )

        let authorizedClient = MockNotificationClient(status: .authorized)
        let scheduler = NotificationScheduler(client: authorizedClient)
        await scheduler.syncNotifications(for: countdownItem, now: now)

        #expect(authorizedClient.addedRequests.count == 2)
        #expect(authorizedClient.addedRequests.map(\.identifier).contains(CountdownCalculator.notificationIdentifier(for: countdownItem.id, kind: .lead)))
        #expect(authorizedClient.addedRequests.map(\.identifier).contains(CountdownCalculator.notificationIdentifier(for: countdownItem.id, kind: .completion)))

        // Streak daily reminder schedules a repeating calendar notification at 20:30
        let streakItem = CountdownItemValue(
            id: UUID(),
            title: "Meditate",
            mode: .streak,
            startDate: now,
            targetDate: now,
            hasTargetDate: false,
            isAllDay: true,
            repeatRule: .none,
            customRepeatDays: 7,
            alertsEnabled: true,
            alertAtCompletion: false,
            alertLeadMinutes: 0,
            completedDayKeys: [],
            dailyReminderHour: 20,
            dailyReminderMinute: 30
        )

        let streakClient = MockNotificationClient(status: .authorized)
        let streakScheduler = NotificationScheduler(client: streakClient)
        await streakScheduler.syncNotifications(for: streakItem, now: now)

        #expect(streakClient.addedRequests.count == 1)
        let trigger = streakClient.addedRequests.first?.trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.repeats == true)
        #expect(trigger?.dateComponents.hour == 20)
        #expect(trigger?.dateComponents.minute == 30)

        let deniedClient = MockNotificationClient(status: .denied)
        let deniedScheduler = NotificationScheduler(client: deniedClient)
        await deniedScheduler.syncNotifications(for: streakItem, now: now)
        #expect(deniedClient.addedRequests.isEmpty)
    }

    @Test("Streak toggleCompletion enforces startDate...today bounds and persists via SwiftData")
    func swiftDataStreakAndCountdownLifecycle() throws {
        let schema = Schema([CountdownItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: today)!
        let fourDaysAgo = calendar.date(byAdding: .day, value: -4, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let streak = CountdownItem(
            title: "Read Daily",
            mode: .streak,
            startDate: threeDaysAgo,
            targetDate: threeDaysAgo,
            hasTargetDate: false,
            alertsEnabled: true,
            dailyReminderHour: 21,
            dailyReminderMinute: 15,
            colorTheme: .teal,
            symbolName: "📚"
        )
        context.insert(streak)

        // Days before startDate or in the future are rejected
        #expect(!streak.toggleCompletion(on: fourDaysAgo, now: today, calendar: calendar))
        #expect(!streak.toggleCompletion(on: tomorrow, now: today, calendar: calendar))

        // Valid past day (yesterday) + today succeed
        #expect(streak.toggleCompletion(on: yesterday, now: today, calendar: calendar))
        #expect(streak.toggleCompletion(on: today, now: today, calendar: calendar))
        #expect(context.saveReportingError() == nil)

        let snap = streak.streakSnapshot(at: today, calendar: calendar)
        #expect(snap.currentStreak == 2)
        #expect(snap.isCompletedToday)

        // Toggle today off -> currentStreak stays 1 (yesterday)
        #expect(streak.toggleCompletion(on: today, now: today, calendar: calendar))
        #expect(streak.streakSnapshot(at: today, calendar: calendar).currentStreak == 1)

        // Restart clears history
        streak.restartCycle(from: today, calendar: calendar)
        #expect(streak.completedDayKeys.isEmpty)
        #expect(streak.startDate == today)

        context.delete(streak)
        #expect(context.saveReportingError() == nil)
        #expect(try context.fetch(FetchDescriptor<CountdownItem>()).isEmpty)
    }
}
