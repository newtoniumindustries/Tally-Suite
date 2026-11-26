import SwiftData
import SwiftUI
import TallyCore

private enum CountdownFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case countdowns = "Countdowns"
    case countups = "Count Ups"
    case streaks = "Streaks"
    case repeating = "Repeating"

    var id: String { rawValue }
}

private enum CountdownSort: String, CaseIterable, Identifiable {
    case soonest = "Soonest Target"
    case name = "Name"
    case newest = "Recently Added"

    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \CountdownItem.createdAt, order: .reverse) private var items: [CountdownItem]

    @State private var selectedFilter: CountdownFilter = .all
    @State private var selectedSort: CountdownSort = .soonest
    @State private var showingNewEditor = false
    @State private var itemToEdit: CountdownItem?
    @State private var itemPendingDelete: CountdownItem?
    @State private var saveErrorMessage: String?

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                let now = timeline.date
                let filtered = filteredAndSortedItems(at: now)
                let pinned = filtered.filter { $0.isPinned }
                let active = filtered.filter { !$0.isPinned && !$0.snapshot(at: now).isComplete }
                let completed = filtered.filter { !$0.isPinned && $0.snapshot(at: now).isComplete }

                VStack(spacing: 0) {
                    if !items.isEmpty {
                        filterBar
                    }

                    if items.isEmpty {
                        ContentUnavailableView(
                            "No Timers Yet",
                            systemImage: "calendar.badge.clock",
                            description: Text("Tap + to create a countdown, count up, or daily streak.")
                        )
                    } else if filtered.isEmpty {
                        ContentUnavailableView(
                            "No Matching Timers",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("Try switching the filter above or create a new timer.")
                        )
                    } else {
                        List {
                            if !pinned.isEmpty {
                                Section("Pinned") {
                                    sectionRows(pinned, now: now)
                                }
                            }

                            if !active.isEmpty {
                                Section(pinned.isEmpty ? "Active" : "Upcoming & In Progress") {
                                    sectionRows(active, now: now)
                                }
                            }

                            if !completed.isEmpty {
                                Section("Completed") {
                                    sectionRows(completed, now: now)
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                }
            }
            .navigationTitle("Tally: Countdown")
            .navigationDestination(for: CountdownItem.self) { item in
                CountdownDetailView(item: item)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort By", selection: $selectedSort) {
                            ForEach(CountdownSort.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down.circle")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewEditor = true
                    } label: {
                        Label("New Timer", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingNewEditor) {
                CountdownEditorSheet(editingItem: nil)
            }
            .sheet(item: $itemToEdit) { item in
                CountdownEditorSheet(editingItem: item)
            }
            .alert(
                "Delete Timer?",
                isPresented: Binding(
                    get: { itemPendingDelete != nil },
                    set: { if !$0 { itemPendingDelete = nil } }
                ),
                presenting: itemPendingDelete
            ) { item in
                Button("Delete", role: .destructive) {
                    deleteItem(item)
                    itemPendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    itemPendingDelete = nil
                }
            } message: { item in
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
            .task {
                await rolloverAndSyncNotifications()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task {
                        await rolloverAndSyncNotifications()
                    }
                }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CountdownFilter.allCases) { filter in
                    let isSelected = selectedFilter == filter
                    Button {
                        withAnimation(.snappy) {
                            selectedFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(.subheadline.weight(isSelected ? .bold : .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground),
                                in: Capsule()
                            )
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func sectionRows(_ sectionItems: [CountdownItem], now: Date) -> some View {
        ForEach(sectionItems) { item in
            NavigationLink(value: item) {
                CountdownCardView(
                    item: item,
                    now: now,
                    onToggleStreakToday: item.mode == .streak ? {
                        toggleStreakToday(item, now: now)
                    } : nil
                )
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    togglePin(item)
                } label: {
                    Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
                }
                .tint(.orange)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    itemPendingDelete = item
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                Button {
                    itemToEdit = item
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.blue)
            }
            .contextMenu {
                if item.mode == .streak {
                    let completedToday = item.isCompleted(on: now)
                    Button {
                        toggleStreakToday(item, now: now)
                    } label: {
                        Label(
                            completedToday ? "Undo Today's Check-In" : "Check In Today",
                            systemImage: completedToday ? "xmark.circle" : "checkmark.circle.fill"
                        )
                    }
                }

                Button {
                    togglePin(item)
                } label: {
                    Label(item.isPinned ? "Unpin" : "Pin to Top", systemImage: item.isPinned ? "pin.slash" : "pin")
                }

                Button {
                    itemToEdit = item
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button {
                    restartItem(item)
                } label: {
                    Label("Restart Cycle", systemImage: "arrow.counterclockwise")
                }

                Divider()

                Button(role: .destructive) {
                    itemPendingDelete = item
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func filteredAndSortedItems(at now: Date) -> [CountdownItem] {
        let filtered = items.filter { item in
            switch selectedFilter {
            case .all:
                return true
            case .countdowns:
                return item.mode == .countdown
            case .countups:
                return item.mode == .countup
            case .streaks:
                return item.mode == .streak
            case .repeating:
                return item.repeatRule != .none
            }
        }

        return filtered.sorted { lhs, rhs in
            switch selectedSort {
            case .soonest:
                let lSnap = lhs.snapshot(at: now)
                let rSnap = rhs.snapshot(at: now)
                let lDate = lSnap.effectiveTargetDate ?? lSnap.effectiveStartDate
                let rDate = rSnap.effectiveTargetDate ?? rSnap.effectiveStartDate
                if lDate != rDate {
                    return lDate < rDate
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .name:
                let order = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                if order != .orderedSame {
                    return order == .orderedAscending
                }
                return lhs.createdAt > rhs.createdAt
            case .newest:
                return lhs.createdAt > rhs.createdAt
            }
        }
    }

    private func toggleStreakToday(_ item: CountdownItem, now: Date) {
        guard item.toggleCompletion(on: now, now: now) else { return }
        if let error = context.saveReportingError() {
            saveErrorMessage = error
            return
        }
        Task {
            await NotificationScheduler.shared.syncNotifications(for: item, now: now)
        }
    }

    private func togglePin(_ item: CountdownItem) {
        item.isPinned.toggle()
        if let error = context.saveReportingError() {
            saveErrorMessage = error
        }
    }

    private func restartItem(_ item: CountdownItem) {
        item.restartCycle()
        if let error = context.saveReportingError() {
            saveErrorMessage = error
            return
        }
        Task {
            await NotificationScheduler.shared.syncNotifications(for: item)
        }
    }

    private func deleteItem(_ item: CountdownItem) {
        let itemID = item.id
        context.delete(item)
        if let error = context.saveReportingError() {
            saveErrorMessage = error
            return
        }
        NotificationScheduler.shared.cancelNotifications(for: itemID)
    }

    private func rolloverAndSyncNotifications() async {
        let now = Date()
        var didAdvanceAny = false
        for item in items {
            if item.advanceIfRepeatingPast(now) {
                didAdvanceAny = true
            }
        }
        if didAdvanceAny {
            if let error = context.saveReportingError() {
                saveErrorMessage = error
            }
        }
        await NotificationScheduler.shared.syncAll(items: items, now: now)
    }
}
