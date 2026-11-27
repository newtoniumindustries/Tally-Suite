import AppIntents
import Foundation
import SwiftData
import TallyCore

// MARK: - Shared Store Helper

@MainActor
enum TallyCanastaWidgetStore {
    private static let sharedContainer: ModelContainer? = {
        TallyCanastaAppGroup.makeContainerResult().container
    }()

    static func makeContext() -> ModelContext? {
        guard let sharedContainer else { return nil }
        return ModelContext(sharedContainer)
    }

    static func fetchGames() -> [CanastaGame] {
        guard let context = makeContext() else { return [] }
        let descriptor = FetchDescriptor<CanastaGame>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let all = (try? context.fetch(descriptor)) ?? []
        return all.sorted { lhs, rhs in
            let lhsActive = lhs.winner == nil
            let rhsActive = rhs.winner == nil
            if lhsActive != rhsActive { return lhsActive }
            return lhs.date > rhs.date
        }
    }

    static func resolveGame(id: UUID?) -> CanastaGame? {
        let games = fetchGames()
        if let id, let exact = games.first(where: { $0.gameID == id }) {
            return exact
        }
        return games.first(where: { $0.winner == nil }) ?? games.first
    }
}

// MARK: - Canasta Game Entity & Configuration Intent

struct CanastaGameWidgetEntity: AppEntity, Sendable {
    let id: UUID
    let matchupTitle: String
    let scoreSummary: String
    let isComplete: Bool

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Canasta Game")
    static let defaultQuery = CanastaGameWidgetEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        let status = isComplete ? "Complete" : "In Progress"
        return DisplayRepresentation(
            title: "\(matchupTitle)",
            subtitle: "\(status) • \(scoreSummary)"
        )
    }
}

struct CanastaGameWidgetEntityQuery: EntityQuery, Sendable {
    func entities(for identifiers: [UUID]) async throws -> [CanastaGameWidgetEntity] {
        let idSet = Set(identifiers)
        return await MainActor.run {
            TallyCanastaWidgetStore.fetchGames()
                .filter { idSet.contains($0.gameID) }
                .map(Self.entity(from:))
        }
    }

    func suggestedEntities() async throws -> [CanastaGameWidgetEntity] {
        await MainActor.run {
            TallyCanastaWidgetStore.fetchGames()
                .prefix(20)
                .map(Self.entity(from:))
        }
    }

    func defaultResult() async -> CanastaGameWidgetEntity? {
        nil
    }

    @MainActor
    private static func entity(from game: CanastaGame) -> CanastaGameWidgetEntity {
        let title = game.isThreeTeams
            ? "\(game.team1Name) vs \(game.team2Name) vs \(game.team3Name)"
            : "\(game.team1Name) vs \(game.team2Name)"
        let summary = game.isThreeTeams
            ? "\(game.team1Total) / \(game.team2Total) / \(game.team3Total)"
            : "\(game.team1Total) / \(game.team2Total)"
        return CanastaGameWidgetEntity(
            id: game.gameID,
            matchupTitle: title,
            scoreSummary: summary,
            isComplete: game.winner != nil
        )
    }
}

struct SelectCanastaGameIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Canasta Game"
    static let description = IntentDescription("Pick a Canasta game to display, or leave empty to automatically follow your latest active game.")

    @Parameter(title: "Game")
    var game: CanastaGameWidgetEntity?

    init() {}

    init(game: CanastaGameWidgetEntity? = nil) {
        self.game = game
    }
}
