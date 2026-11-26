import SwiftData
import SwiftUI
import TallyCore

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Play", systemImage: "sportscourt.fill") {
                ActiveMatchesView()
            }
            Tab("Standings", systemImage: "trophy.fill") {
                StandingsView()
            }
            Tab("Setup", systemImage: "slider.horizontal.3") {
                SetupView()
            }
        }
    }
}

// MARK: - 1. Play & Match History

struct ActiveMatchesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.isUsingFallbackStore) private var isUsingFallbackStore

    @AppStorage("tallyItHasSeededDefaults") private var hasSeededDefaults = false

    @Query(sort: \Match.startedAt, order: .reverse) private var matches: [Match]
    @Query(sort: \GameType.name) private var gameTypes: [GameType]
    @Query(sort: \Team.name) private var teams: [Team]

    @State private var navigationPath: [Match] = []
    @State private var showingNewMatchSheet = false
    @State private var didCheckFallbackSeed = false
    @State private var matchPendingReset: Match?
    @State private var matchPendingDelete: Match?
    @State private var saveErrorMessage: String?

    private var activeMatches: [Match] {
        matches.filter { !$0.isCompleted }
    }

    private var allCompletedMatches: [Match] {
        matches
            .filter { $0.isCompleted }
            .sorted { ($0.completedAt ?? $0.startedAt) > ($1.completedAt ?? $1.startedAt) }
    }

    /// Limited to the last 5 completed games, sorted by most recently completed
    private var recentCompletedMatches: [Match] {
        Array(allCompletedMatches.prefix(5))
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if activeMatches.isEmpty && recentCompletedMatches.isEmpty {
                    ContentUnavailableView(
                        "No Active Game",
                        systemImage: "flag.2.crossed.fill",
                        description: Text("Tap + to start a new match and pick your teams and game rules.")
                    )
                } else {
                    List {
                        Section("Active Matches") {
                            if activeMatches.isEmpty {
                                Text("No active matches in progress.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(activeMatches) { match in
                                    NavigationLink(value: match) {
                                        MatchRowSummaryView(match: match, isCompleted: false)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            matchPendingDelete = match
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }

                        if !recentCompletedMatches.isEmpty {
                            Section("Recently Completed (Last 5)") {
                                ForEach(recentCompletedMatches) { match in
                                    NavigationLink(value: match) {
                                        MatchRowSummaryView(match: match, isCompleted: true)
                                    }
                                    .contextMenu {
                                        completedMatchMenuItems(for: match)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            matchPendingDelete = match
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        Button {
                                            matchPendingReset = match
                                        } label: {
                                            Label("Reset", systemImage: "arrow.counterclockwise")
                                        }
                                        .tint(.orange)
                                        Button {
                                            reopenAndNavigate(to: match)
                                        } label: {
                                            Label("Reopen", systemImage: "arrow.uturn.backward")
                                        }
                                        .tint(.blue)
                                    }
                                }

                                if allCompletedMatches.count > 5 {
                                    NavigationLink {
                                        CompletedMatchesHistoryView(
                                            onReopen: { match in
                                                reopenAndNavigate(to: match)
                                            },
                                            onRequestReset: { match in
                                                matchPendingReset = match
                                            }
                                        )
                                    } label: {
                                        Label(
                                            "View All Completed (\(allCompletedMatches.count))",
                                            systemImage: "clock.arrow.circlepath"
                                        )
                                        .font(.subheadline.weight(.medium))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tally: It")
            .navigationDestination(for: Match.self) { match in
                LiveScoreboardView(match: match)
            }
            .onAppear(perform: seedDefaultsIfNeeded)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewMatchSheet = true
                    } label: {
                        Label("New Match", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingNewMatchSheet) {
                NewMatchSheet()
            }
            .alert(
                "Reset Match to 0?",
                isPresented: Binding(
                    get: { matchPendingReset != nil },
                    set: { if !$0 { matchPendingReset = nil } }
                ),
                presenting: matchPendingReset
            ) { match in
                Button("Reset to 0", role: .destructive) {
                    match.restartMatchFromZero()
                    if let error = context.saveReportingError() {
                        saveErrorMessage = error
                    } else {
                        navigationPath.append(match)
                    }
                    matchPendingReset = nil
                }
                Button("Cancel", role: .cancel) {
                    matchPendingReset = nil
                }
            } message: { match in
                Text("This clears all scores and round history for \(match.gameTypeName) and restarts from Round 1.")
            }
            .alert(
                "Delete Match?",
                isPresented: Binding(
                    get: { matchPendingDelete != nil },
                    set: { if !$0 { matchPendingDelete = nil } }
                ),
                presenting: matchPendingDelete
            ) { match in
                Button("Delete Match", role: .destructive) {
                    context.delete(match)
                    if let error = context.saveReportingError() {
                        saveErrorMessage = error
                    }
                    matchPendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    matchPendingDelete = nil
                }
            } message: { match in
                if match.isCompleted {
                    Text("Deleting this completed \(match.gameTypeName) match permanently removes it and updates Standings.")
                } else {
                    Text("This permanently deletes this active \(match.gameTypeName) match and its scores.")
                }
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

    @ViewBuilder
    private func completedMatchMenuItems(for match: Match) -> some View {
        Button {
            reopenAndNavigate(to: match)
        } label: {
            Label("Reopen & Continue Scoring", systemImage: "arrow.uturn.backward.circle")
        }

        Button {
            matchPendingReset = match
        } label: {
            Label("Restart from 0 (Reset Scores)", systemImage: "arrow.counterclockwise.circle")
        }

        Divider()

        Button(role: .destructive) {
            matchPendingDelete = match
        } label: {
            Label("Delete Match", systemImage: "trash")
        }
    }

    private func reopenAndNavigate(to match: Match) {
        match.reopenMatch()
        if let error = context.saveReportingError() {
            saveErrorMessage = error
            return
        }
        navigationPath.append(match)
    }

    private func seedDefaultsIfNeeded() {
        if isUsingFallbackStore {
            guard !didCheckFallbackSeed else { return }
            didCheckFallbackSeed = true
        } else {
            guard !hasSeededDefaults else { return }
        }

        var didChange = false
        if gameTypes.isEmpty {
            context.insert(GameType(name: "Cornhole", incrementsRaw: "1, 3, -1", targetScore: 21, trackRounds: true, useCondensedView: true))
            context.insert(GameType(name: "10-Round Game", incrementsRaw: "5, 10, 20", maxRounds: 10, trackRounds: true, useCondensedView: true))
            didChange = true
        }
        if teams.isEmpty {
            context.insert(Team(name: "Team Alpha"))
            context.insert(Team(name: "Team Bravo"))
            didChange = true
        }
        if didChange {
            if let error = context.saveReportingError() {
                saveErrorMessage = error
                return
            }
        }
        if !isUsingFallbackStore {
            hasSeededDefaults = true
        }
    }
}

struct CompletedMatchesHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<Match> { $0.isCompleted },
        sort: \Match.completedAt,
        order: .reverse
    ) private var completedMatches: [Match]

    var onReopen: (Match) -> Void
    var onRequestReset: (Match) -> Void

    @State private var matchPendingDelete: Match?
    @State private var saveErrorMessage: String?

    var body: some View {
        List {
            if completedMatches.isEmpty {
                Text("No completed matches yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(completedMatches) { match in
                    NavigationLink(value: match) {
                        MatchRowSummaryView(match: match, isCompleted: true)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            matchPendingDelete = match
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            onRequestReset(match)
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                        .tint(.orange)
                        Button {
                            onReopen(match)
                        } label: {
                            Label("Reopen", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .navigationTitle("Completed Matches")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Delete Match?",
            isPresented: Binding(
                get: { matchPendingDelete != nil },
                set: { if !$0 { matchPendingDelete = nil } }
            ),
            presenting: matchPendingDelete
        ) { match in
            Button("Delete Match", role: .destructive) {
                context.delete(match)
                if let error = context.saveReportingError() {
                    saveErrorMessage = error
                }
                matchPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                matchPendingDelete = nil
            }
        } message: { match in
            Text("Deleting this completed \(match.gameTypeName) match permanently removes it and updates Standings.")
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

struct MatchRowSummaryView: View {
    let match: Match
    let isCompleted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(match.gameTypeName)
                    .font(.headline)
                Spacer()
                if isCompleted {
                    Text("Completed")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.green)
                } else if match.trackRounds {
                    let roundText: String = {
                        if let maxR = match.activeMaxRounds {
                            return "Round \(min(match.currentRound, maxR))/\(maxR)"
                        }
                        return "Round \(match.currentRound)"
                    }()
                    Text(roundText)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.blue)
                } else {
                    Text("Total Only")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.secondary)
                }
            }
            Text(match.sortedEntries.map { "\($0.teamName): \($0.score)" }.joined(separator: "  |  "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
