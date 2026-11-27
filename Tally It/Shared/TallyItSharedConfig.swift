import Foundation
import SwiftData
import TallyCore

enum TallyItAppGroup {
    nonisolated static let identifier = "group.com.newtastic.Tally-It"

    @MainActor
    static func makeContainerResult() -> TallyContainerResult {
        TallyDataConfig.makeContainer(
            for: [
                GameType.self,
                Team.self,
                Match.self,
                MatchScoreEntry.self
            ],
            appGroupIdentifier: identifier
        )
    }
}

enum TallyItDeepLink: Equatable, Sendable {
    nonisolated static let scheme = "tallyit"

    case match(UUID)
    case standings(gameTypeID: UUID?)
    case newMatch

    nonisolated var url: URL {
        switch self {
        case .match(let id):
            return URL(string: "\(Self.scheme)://match/\(id.uuidString)")!
        case .standings(let gameTypeID):
            if let gameTypeID {
                return URL(string: "\(Self.scheme)://standings/\(gameTypeID.uuidString)")!
            }
            return URL(string: "\(Self.scheme)://standings")!
        case .newMatch:
            return URL(string: "\(Self.scheme)://new-match")!
        }
    }

    nonisolated static func parse(_ url: URL) -> TallyItDeepLink? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        switch url.host?.lowercased() {
        case "match":
            let rawID = url.pathComponents.dropFirst().first ?? ""
            guard let id = UUID(uuidString: rawID) else { return nil }
            return .match(id)
        case "standings":
            if let rawID = url.pathComponents.dropFirst().first, !rawID.isEmpty {
                guard let id = UUID(uuidString: rawID) else { return nil }
                return .standings(gameTypeID: id)
            }
            return .standings(gameTypeID: nil)
        case "new-match":
            return .newMatch
        default:
            return nil
        }
    }
}
