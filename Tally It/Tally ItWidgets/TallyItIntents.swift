import AppIntents
import Foundation
import SwiftData
import TallyCore
import WidgetKit

// MARK: - Shared Store Helper for Widgets & AppIntents

@MainActor
enum TallyItWidgetStore {
    private static let sharedContainer: ModelContainer? = {
        TallyItAppGroup.makeContainerResult().container
    }()

    static func makeContext() -> ModelContext? {
        guard let sharedContainer else { return nil }
        return ModelContext(sharedContainer)
    }

    static func fetchMatches() -> [Match] {
        guard let context = makeContext() else { return [] }
        let descriptor = FetchDescriptor<Match>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        let all = (try? context.fetch(descriptor)) ?? []
        return all.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
            return lhs.startedAt > rhs.startedAt
        }
    }

    static func fetchGameTypes() -> [GameType] {
        guard let context = makeContext() else { return [] }
        let descriptor = FetchDescriptor<GameType>(sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }

    static func resolveMatch(id: UUID?) -> Match? {
        let matches = fetchMatches()
        if let id, let exact = matches.first(where: { $0.id == id }) {
            return exact
        }
        return matches.first(where: { !$0.isCompleted }) ?? matches.first
    }

    static func adjustScore(matchID: UUID, entryID: UUID, delta: Int) {
        guard let context = makeContext() else { return }
        let descriptor = FetchDescriptor<Match>(predicate: #Predicate { $0.id == matchID })
        guard let match = try? context.fetch(descriptor).first,
              !match.isCompleted,
              let entry = match.entries.first(where: { $0.id == entryID }) else {
            return
        }
        entry.applyDelta(delta, trackRounds: match.trackRounds)
        _ = context.saveReportingError()
    }

    static func advanceRound(matchID: UUID) {
        guard let context = makeContext() else { return }
        let descriptor = FetchDescriptor<Match>(predicate: #Predicate { $0.id == matchID })
        guard let match = try? context.fetch(descriptor).first,
              !match.isCompleted,
              match.trackRounds else {
            return
        }
        match.advanceRound()
        _ = context.saveReportingError()
    }
}

// MARK: - Match Entity & Configuration Intent

struct MatchWidgetEntity: AppEntity, Sendable {
    let id: UUID
    let gameTypeName: String
    let scoreSummary: String
    let isCompleted: Bool

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Match")
    static let defaultQuery = MatchWidgetEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        let status = isCompleted ? "Completed" : "Live"
        return DisplayRepresentation(
            title: "\(gameTypeName)",
            subtitle: "\(status) • \(scoreSummary)"
        )
    }
}

struct MatchWidgetEntityQuery: EntityQuery, Sendable {
    func entities(for identifiers: [UUID]) async throws -> [MatchWidgetEntity] {
        let idSet = Set(identifiers)
        return await MainActor.run {
            TallyItWidgetStore.fetchMatches()
                .filter { idSet.contains($0.id) }
                .map(Self.entity(from:))
        }
    }

    func suggestedEntities() async throws -> [MatchWidgetEntity] {
        await MainActor.run {
            TallyItWidgetStore.fetchMatches()
                .prefix(20)
                .map(Self.entity(from:))
        }
    }

    func defaultResult() async -> MatchWidgetEntity? {
        nil
    }

    @MainActor
    private static func entity(from match: Match) -> MatchWidgetEntity {
        let summary = match.sortedEntries.map { "\($0.teamName): \($0.score)" }.joined(separator: " | ")
        return MatchWidgetEntity(
            id: match.id,
            gameTypeName: match.gameTypeName,
            scoreSummary: summary,
            isCompleted: match.isCompleted
        )
    }
}

struct SelectMatchWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Match"
    static let description = IntentDescription("Pick a match to score, or leave empty to automatically follow your latest active match.")

    @Parameter(title: "Match")
    var match: MatchWidgetEntity?

    init() {}

    init(match: MatchWidgetEntity? = nil) {
        self.match = match
    }
}

// MARK: - Game Type Filter Entity for Standings Widget

struct GameTypeWidgetEntity: AppEntity, Sendable {
    let id: UUID
    let name: String

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Game Type")
    static let defaultQuery = GameTypeWidgetEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct GameTypeWidgetEntityQuery: EntityQuery, Sendable {
    func entities(for identifiers: [UUID]) async throws -> [GameTypeWidgetEntity] {
        let idSet = Set(identifiers)
        return await MainActor.run {
            allGameTypes().filter { idSet.contains($0.id) }
        }
    }

    func suggestedEntities() async throws -> [GameTypeWidgetEntity] {
        await MainActor.run {
            allGameTypes()
        }
    }

    func defaultResult() async -> GameTypeWidgetEntity? {
        nil
    }

    @MainActor
    private func allGameTypes() -> [GameTypeWidgetEntity] {
        var byID: [UUID: GameTypeWidgetEntity] = [:]
        for game in TallyItWidgetStore.fetchGameTypes() {
            byID[game.id] = GameTypeWidgetEntity(id: game.id, name: game.name)
        }
        for match in TallyItWidgetStore.fetchMatches() where match.isCompleted && byID[match.gameTypeID] == nil {
            byID[match.gameTypeID] = GameTypeWidgetEntity(id: match.gameTypeID, name: match.gameTypeName)
        }
        return byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

struct SelectStandingsFilterIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Standings Filter"
    static let description = IntentDescription("Pick a specific game type, or leave empty to view standings across All Games.")

    @Parameter(title: "Game Type")
    var gameType: GameTypeWidgetEntity?

    init() {}

    init(gameType: GameTypeWidgetEntity? = nil) {
        self.gameType = gameType
    }
}

// MARK: - Interactive Score & Round AppIntents

struct AdjustTeamScoreIntent: AppIntent {
    static let title: LocalizedStringResource = "Adjust Team Score"
    static let description = IntentDescription("Adds or subtracts points for a team in a live match.")

    @Parameter(title: "Match ID")
    var matchID: String

    @Parameter(title: "Entry ID")
    var entryID: String

    @Parameter(title: "Points")
    var delta: Int

    init() {}

    init(matchID: UUID, entryID: UUID, delta: Int) {
        self.matchID = matchID.uuidString
        self.entryID = entryID.uuidString
        self.delta = delta
    }

    func perform() async throws -> some IntentResult {
        guard let mID = UUID(uuidString: matchID),
              let eID = UUID(uuidString: entryID) else {
            return .result()
        }
        await MainActor.run {
            TallyItWidgetStore.adjustScore(matchID: mID, entryID: eID, delta: delta)
        }
        return .result()
    }
}

struct AdvanceRoundIntent: AppIntent {
    static let title: LocalizedStringResource = "Advance to Next Round"
    static let description = IntentDescription("Commits current round scores and advances the match to the next round.")

    @Parameter(title: "Match ID")
    var matchID: String

    init() {}

    init(matchID: UUID) {
        self.matchID = matchID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let mID = UUID(uuidString: matchID) else { return .result() }
        await MainActor.run {
            TallyItWidgetStore.advanceRound(matchID: mID)
        }
        return .result()
    }
}
