import Foundation
import SwiftData
import TallyCore

enum TallyCanastaAppGroup {
    nonisolated static let identifier = "group.com.newtastic.Tally-Canasta"

    @MainActor
    static func makeContainerResult() -> TallyContainerResult {
        TallyDataConfig.makeContainer(
            for: [
                CanastaGame.self,
                Round.self,
                RuleSet.self,
                TallyPlayer.self
            ],
            appGroupIdentifier: identifier
        )
    }
}

enum TallyCanastaDeepLink: Equatable, Sendable {
    nonisolated static let scheme = "tallycanasta"

    case game(UUID)
    case newRound(gameID: UUID)
    case newGame
    case howToPlay

    nonisolated var url: URL {
        switch self {
        case .game(let id):
            return URL(string: "\(Self.scheme)://game/\(id.uuidString)")!
        case .newRound(let gameID):
            return URL(string: "\(Self.scheme)://game/\(gameID.uuidString)/new-round")!
        case .newGame:
            return URL(string: "\(Self.scheme)://new-game")!
        case .howToPlay:
            return URL(string: "\(Self.scheme)://how-to-play")!
        }
    }

    nonisolated static func parse(_ url: URL) -> TallyCanastaDeepLink? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        switch url.host?.lowercased() {
        case "game":
            let parts = url.pathComponents.dropFirst()
            guard let rawID = parts.first, let id = UUID(uuidString: rawID) else {
                return nil
            }
            if parts.dropFirst().first?.lowercased() == "new-round" {
                return .newRound(gameID: id)
            }
            return .game(id)
        case "new-game":
            return .newGame
        case "how-to-play":
            return .howToPlay
        default:
            return nil
        }
    }
}
