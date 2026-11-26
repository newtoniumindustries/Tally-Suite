import Foundation
import SwiftData
import TallyCore
import Testing
@preconcurrency import UserNotifications
@testable import Tally_Countdown

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

@Suite("CountdownCalculator & Recurrence Tests")
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
        let target = makeUTCDate(year: 2026, month: 6, day: 11, hour: 12, minute: 0) // 10 days later
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
        #expect(midSnap.primaryBreakdown.hours == 0)
        #expect(midSnap.progress == 0.5)

        let doneSnap = CountdownCalculator.snapshot(for: item, at: target.addingTimeInterval(10), calendar: utcCalendar)
        #expect(doneSnap.isComplete)
        #expect(doneSnap.primaryBreakdown.totalSeconds == 0)
        #expect(doneSnap.progress == 1.0)
    }

    @Test("Goal-based countup tracks elapsed days, progress, and completion for 20 days from today")
    func goalBasedCountup() {
        let start = makeUTCDate(year: 2026, month: 7, day: 1)
        let target = makeUTCDate(year: 2026, month: 7, day: 21) // 20 days from start
        let day5 = makeUTCDate(year: 2026, month: 7, day: 6)

        let item = CountdownItemValue(
            id: UUID(),
            title: "20-Day Streak",
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

        let snap = CountdownCalculator.snapshot(for: item, at: day5, calendar: utcCalendar)
        #expect(!snap.isComplete)
        #expect(!snap.isUpcomingStart)
        #expect(snap.elapsedDaysCount == 5)
        #expect(snap.totalGoalDays == 20)
        #expect(snap.progress == 0.25)
        #expect(snap.primaryHeadline == "Day 5 of 20")
        #expect(snap.remainingToGoal?.days == 15)

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

        // Open-ended countups never schedule target alerts
        let alerts = CountdownCalculator.scheduledAlerts(for: item, at: beforeStart, calendar: utcCalendar)
        #expect(alerts.isEmpty)
    }

    @Test("Recurrence rollover handles daily, weekly, monthly month-end clamping, custom days, and multi-year jumps")
    func recurrenceRollover() {
        // Monthly Jan 31 -> Feb 28 (non-leap year 2026)
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
        #expect(rolledMonthly != nil)
        #expect(rolledMonthly?.targetDate == makeUTCDate(year: 2026, month: 2, day: 28))

        // Custom 20-day cycle jumping forward across multiple elapsed cycles in O(1)
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
        let target = makeUTCDate(year: 2026, month: 9, day: 2, hour: 10, minute: 0) // 24h away

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
            alertLeadMinutes: 120 // 2 hours before
        )

        let alerts = CountdownCalculator.scheduledAlerts(for: item, at: now, calendar: utcCalendar)
        #expect(alerts.count == 2)
        #expect(alerts[0].kind == .lead)
        #expect(alerts[0].fireDate == makeUTCDate(year: 2026, month: 9, day: 2, hour: 8, minute: 0))
        #expect(alerts[1].kind == .completion)
        #expect(alerts[1].fireDate == target)

        // When lead time has already passed (only 1 hour left), only completion alert remains
        let oneHourBefore = makeUTCDate(year: 2026, month: 9, day: 2, hour: 9, minute: 0)
        let remainingAlerts = CountdownCalculator.scheduledAlerts(for: item, at: oneHourBefore, calendar: utcCalendar)
        #expect(remainingAlerts.count == 1)
        #expect(remainingAlerts[0].kind == .completion)

        #expect(CountdownCalculator.formatLeadTime(minutes: 1500) == "1 day 1 hour")
    }
}

@Suite("Tally Countdown Persistence & Notification Scheduler Tests")
@MainActor
struct CountdownLifecycleTests {
    @Test("NotificationScheduler schedules lead and completion requests when authorized and skips when denied")
    func notificationSchedulerSync() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let target = now.addingTimeInterval(86_400) // +24h

        let item = CountdownItemValue(
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
        await scheduler.syncNotifications(for: item, now: now)

        let added = authorizedClient.addedRequests
        #expect(added.count == 2)
        #expect(added.map(\.identifier).contains(CountdownCalculator.notificationIdentifier(for: item.id, kind: .lead)))
        #expect(added.map(\.identifier).contains(CountdownCalculator.notificationIdentifier(for: item.id, kind: .completion)))

        let deniedClient = MockNotificationClient(status: .denied)
        let deniedScheduler = NotificationScheduler(client: deniedClient)
        await deniedScheduler.syncNotifications(for: item, now: now)
        #expect(deniedClient.addedRequests.isEmpty)
    }

    @Test("SwiftData inserts, advances repeating items, restarts cycles, and deletes cleanly")
    func swiftDataLifecycle() throws {
        let schema = Schema([CountdownItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let now = Date()
        let pastStart = now.addingTimeInterval(-10 * 86_400)
        let pastTarget = now.addingTimeInterval(-2 * 86_400)

        let item = CountdownItem(
            title: "Weekly Review",
            mode: .countdown,
            startDate: pastStart,
            targetDate: pastTarget,
            isAllDay: false,
            repeatRule: .weekly,
            alertsEnabled: true,
            alertAtCompletion: true,
            alertLeadMinutes: 60,
            colorTheme: .indigo,
            symbolName: "calendar",
            isPinned: true
        )
        context.insert(item)
        #expect(context.saveReportingError() == nil)

        #expect(item.advanceIfRepeatingPast(now))
        #expect(item.targetDate > now)

        item.restartCycle(from: now)
        #expect(item.startDate == now)
        #expect(item.targetDate > now)

        let fetched = try context.fetch(FetchDescriptor<CountdownItem>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Weekly Review")

        context.delete(item)
        #expect(context.saveReportingError() == nil)
        #expect(try context.fetch(FetchDescriptor<CountdownItem>()).isEmpty)
    }
}
