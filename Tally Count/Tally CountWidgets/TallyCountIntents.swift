import AppIntents
import Foundation
import SwiftData
import TallyCore
import WidgetKit

// MARK: - Shared Widget Data Store Access

struct WidgetTimerSummary: Sendable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let symbolName: String
    let colorTheme: CountdownThemeColor
    let isPinned: Bool
    let value: CountdownItemValue
}

@MainActor
enum TallyCountWidgetStore {
    static func fetchAllTimers(now: Date = Date()) -> [WidgetTimerSummary] {
        let result = TallyCountAppGroup.makeContainerResult()
        guard let container = result.container else { return [] }
        let context = container.mainContext
        let descriptor = FetchDescriptor<CountdownItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let items = try? context.fetch(descriptor) else { return [] }

        var didAdvance = false
        for item in items {
            if item.advanceIfRepeatingPast(now) {
                didAdvance = true
            }
        }
        if didAdvance {
            context.saveLoggingErrors(reloadWidgets: false)
        }

        return items.map { item in
            WidgetTimerSummary(
                id: item.id,
                title: item.title,
                symbolName: item.symbolName,
                colorTheme: item.colorTheme,
                isPinned: item.isPinned,
                value: item.valueSnapshot
            )
        }
    }

    static func defaultPrimaryTimer(from timers: [WidgetTimerSummary], now: Date = Date()) -> WidgetTimerSummary? {
        let pinned = timers.filter { $0.isPinned }
        if let firstPinned = sortBySoonest(pinned, now: now).first {
            return firstPinned
        }
        let active = timers.filter { !CountdownCalculator.snapshot(for: $0.value, at: now).isComplete }
        return sortBySoonest(active, now: now).first ?? timers.first
    }

    static func sortBySoonest(_ timers: [WidgetTimerSummary], now: Date) -> [WidgetTimerSummary] {
        timers.sorted { lhs, rhs in
            let lSnap = CountdownCalculator.snapshot(for: lhs.value, at: now)
            let rSnap = CountdownCalculator.snapshot(for: rhs.value, at: now)
            let lDate = lSnap.effectiveTargetDate ?? lSnap.effectiveStartDate
            let rDate = rSnap.effectiveTargetDate ?? rSnap.effectiveStartDate
            if lDate != rDate {
                return lDate < rDate
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}

// MARK: - Configurable Widget Entities & Parameters

struct TimerWidgetEntity: AppEntity, Identifiable, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Timer"
    static let defaultQuery = TimerWidgetEntityQuery()

    let id: UUID
    let title: String
    let subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(subtitle)"
        )
    }
}

struct TimerWidgetEntityQuery: EntityQuery {
    func entities(for identifiers: [TimerWidgetEntity.ID]) async throws -> [TimerWidgetEntity] {
        let all = await MainActor.run { TallyCountWidgetStore.fetchAllTimers() }
        let idSet = Set(identifiers)
        return all
            .filter { idSet.contains($0.id) }
            .map { TimerWidgetEntity(id: $0.id, title: $0.title, subtitle: $0.value.mode.displayName) }
    }

    func suggestedEntities() async throws -> [TimerWidgetEntity] {
        let all = await MainActor.run { TallyCountWidgetStore.fetchAllTimers() }
        return all.map { TimerWidgetEntity(id: $0.id, title: $0.title, subtitle: $0.value.mode.displayName) }
    }

    func defaultResult() async -> TimerWidgetEntity? {
        let primary = await MainActor.run {
            let all = TallyCountWidgetStore.fetchAllTimers()
            return TallyCountWidgetStore.defaultPrimaryTimer(from: all)
        }
        guard let primary else { return nil }
        return TimerWidgetEntity(id: primary.id, title: primary.title, subtitle: primary.value.mode.displayName)
    }
}

struct SelectTimerWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Select Timer"
    static let description = IntentDescription("Choose a Countdown, Count Up, or Streak to display.")

    @Parameter(title: "Timer")
    var timer: TimerWidgetEntity?
}

enum TimersOverviewFilter: String, AppEnum, Sendable {
    case all
    case pinned
    case countdowns
    case countups
    case streaks

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Filter"
    static let caseDisplayRepresentations: [TimersOverviewFilter: DisplayRepresentation] = [
        .all: "All Active",
        .pinned: "Pinned Only",
        .countdowns: "Countdowns",
        .countups: "Count Ups",
        .streaks: "Streaks"
    ]
}

struct SelectOverviewFilterIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Filter Timers"
    static let description = IntentDescription("Choose which timers appear in your overview widget.")

    @Parameter(title: "Filter", default: .all)
    var filter: TimersOverviewFilter
}

// MARK: - Interactive Streak Check-In AppIntents

struct ToggleStreakTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Check In Streak Today"
    static let description = IntentDescription("Marks or unmarks today's check-in for a daily streak.")

    @Parameter(title: "Timer ID")
    var itemID: String

    init() {
        self.itemID = ""
    }

    init(itemID: UUID) {
        self.itemID = itemID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: itemID) else { return .result() }
        await MainActor.run {
            let result = TallyCountAppGroup.makeContainerResult()
            guard let container = result.container else { return }
            let context = container.mainContext
            let descriptor = FetchDescriptor<CountdownItem>(
                predicate: #Predicate { $0.id == uuid }
            )
            guard let item = try? context.fetch(descriptor).first else { return }
            let now = Date()
            if item.toggleCompletion(on: now, now: now) {
                context.saveLoggingErrors(reloadWidgets: true)
            }
        }
        return .result()
    }
}

struct ToggleStreakDayIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Streak Day"
    static let description = IntentDescription("Toggles a specific recent day's completion for a daily streak.")

    @Parameter(title: "Timer ID")
    var itemID: String

    @Parameter(title: "Day Key")
    var dayKey: String

    init() {
        self.itemID = ""
        self.dayKey = ""
    }

    init(itemID: UUID, dayKey: String) {
        self.itemID = itemID.uuidString
        self.dayKey = dayKey
    }

    func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: itemID),
              let day = CountdownCalculator.date(fromDayKey: dayKey) else {
            return .result()
        }
        await MainActor.run {
            let result = TallyCountAppGroup.makeContainerResult()
            guard let container = result.container else { return }
            let context = container.mainContext
            let descriptor = FetchDescriptor<CountdownItem>(
                predicate: #Predicate { $0.id == uuid }
            )
            guard let item = try? context.fetch(descriptor).first else { return }
            let now = Date()
            if item.toggleCompletion(on: day, now: now) {
                context.saveLoggingErrors(reloadWidgets: true)
            }
        }
        return .result()
    }
}
