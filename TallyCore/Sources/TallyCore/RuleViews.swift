import SwiftUI

public struct RuleSection: View {
    public let title: String
    public let content: String
    
    public init(title: String, content: String) {
        self.title = title
        self.content = content
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundColor(.blue)
            Text(content).font(.body).lineSpacing(4).foregroundColor(.primary)
        }
    }
}

public struct RuleRow: View {
    public let title: String
    public let points: Int
    
    public init(title: String, points: Int) {
        self.title = title
        self.points = points
    }
    
    public var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(points) pts").foregroundColor(.secondary)
        }
    }
}
