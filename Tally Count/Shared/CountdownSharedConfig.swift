import Foundation
import SwiftData
import TallyCore

enum TallyCountAppGroup {
    nonisolated static let identifier = "group.com.newtastic.Tally-Count"

    @MainActor
    static func makeContainerResult() -> TallyContainerResult {
        TallyDataConfig.makeContainer(
            for: [CountdownItem.self],
            appGroupIdentifier: identifier
        )
    }
}

enum TallyCountDeepLink: Sendable, Equatable {
    case item(UUID)
    case newTimer

    nonisolated static let scheme = "tallycount"

    nonisolated var url: URL {
        switch self {
        case .item(let id):
            return URL(string: "\(Self.scheme)://item/\(id.uuidString)")!
        case .newTimer:
            return URL(string: "\(Self.scheme)://new")!
        }
    }

    nonisolated static func parse(_ url: URL) -> TallyCountDeepLink? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let host = url.host()?.lowercased() ?? ""
        switch host {
        case "new":
            return .newTimer
        case "item":
            let idString = url.pathComponents.dropFirst().first ?? ""
            guard let id = UUID(uuidString: idString) else { return nil }
            return .item(id)
        default:
            return nil
        }
    }
}
