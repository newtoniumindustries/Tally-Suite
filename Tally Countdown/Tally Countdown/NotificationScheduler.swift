import Foundation
import OSLog
import TallyCore
@preconcurrency import UserNotifications

protocol NotificationCenterClient: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

struct SystemNotificationCenterClient: NotificationCenterClient {
    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    private let client: any NotificationCenterClient

    init(client: any NotificationCenterClient = SystemNotificationCenterClient()) {
        self.client = client
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await client.authorizationStatus()
    }

    /// Requests notification permission if not yet determined. Returns `true` if authorized/provisional.
    @discardableResult
    func ensureAuthorization() async -> Bool {
        let status = await client.authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await client.requestAuthorization()
            } catch {
                TallyLogger.ui.error("Notification authorization request failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        @unknown default:
            return false
        }
    }

    func cancelNotifications(for itemID: UUID) {
        let identifiers = CountdownCalculator.allNotificationIdentifiers(for: itemID)
        client.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func syncNotifications(
        for item: CountdownItem,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        await syncNotifications(for: item.valueSnapshot, now: now, calendar: calendar)
    }

    func syncNotifications(
        for item: CountdownItemValue,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        cancelNotifications(for: item.id)

        let alerts = CountdownCalculator.scheduledAlerts(for: item, at: now, calendar: calendar)
        guard !alerts.isEmpty else { return }

        let authorized = await ensureAuthorization()
        guard authorized else { return }

        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default

            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: alert.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: alert.identifier,
                content: content,
                trigger: trigger
            )

            do {
                try await client.add(request)
            } catch {
                TallyLogger.ui.error(
                    "Failed to schedule notification \(alert.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    func syncAll(
        items: [CountdownItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        let snapshots = items.map(\.valueSnapshot)
        for snapshot in snapshots {
            await syncNotifications(for: snapshot, now: now, calendar: calendar)
        }
    }
}
