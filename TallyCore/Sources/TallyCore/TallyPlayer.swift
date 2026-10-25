import Foundation
import SwiftData

@Model
public final class TallyPlayer {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    
    // We must explicitly make the initializer public so your apps can create players
    public init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}
