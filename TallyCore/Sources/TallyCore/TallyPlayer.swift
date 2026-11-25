import Foundation
import SwiftData

@Model
public final class TallyPlayer {
    public var id: UUID = UUID()
    public var name: String = ""
    public var createdAt: Date = Date()

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}
