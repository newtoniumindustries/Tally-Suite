import SwiftUI

// MARK: - Emoji & Symbol Catalog (Shared between App & Widget Extension)

struct CountdownIconCategory: Identifiable, Sendable {
    let id: String
    let title: String
    let emojis: [String]
}

enum CountdownIconCatalog: Sendable {
    nonisolated static let defaultIcon = "⏳"

    /// Quick-select emojis displayed inline in the editor before the "More" button.
    nonisolated static let quickEmojis: [String] = [
        "⏳", "🎉", "✈️", "🎂", "🔥", "🏆"
    ]

    nonisolated static let emojiCategories: [CountdownIconCategory] = [
        CountdownIconCategory(
            id: "celebrations",
            title: "Celebrations & Milestones",
            emojis: ["🎉", "🎂", "🎁", "🎈", "🥳", "💍", "🎓", "👶", "🥂", "🎊", "💐", "🎆"]
        ),
        CountdownIconCategory(
            id: "travel",
            title: "Travel & Outdoors",
            emojis: ["✈️", "🏖️", "🏔️", "🏕️", "🚢", "🚗", "🗺️", "🌴", "🎢", "🏝️", "🚆", "🌅"]
        ),
        CountdownIconCategory(
            id: "fitness",
            title: "Health, Fitness & Habits",
            emojis: ["🔥", "🏃", "🏋️", "🚴", "🧘", "💪", "🥗", "💧", "😴", "🏅", "🏆", "🎯"]
        ),
        CountdownIconCategory(
            id: "time",
            title: "Timers & Productivity",
            emojis: ["⏳", "⏰", "📅", "🚀", "💼", "📚", "💻", "📝", "🔔", "⭐", "🏁", "📌"]
        ),
        CountdownIconCategory(
            id: "holidays",
            title: "Holidays & Seasons",
            emojis: ["🎄", "🎃", "❤️", "☘️", "🦃", "❄️", "☀️", "🌸", "🍂", "🌙", "🎇", "⛄"]
        ),
        CountdownIconCategory(
            id: "fun",
            title: "Entertainment & Life",
            emojis: ["🎵", "🎬", "🎮", "🎸", "⚽", "🏀", "🏈", "⚾", "🐶", "🏡", "🍕", "☕"]
        )
    ]

    nonisolated static let sfSymbols: [String] = CountdownSymbol.all

    /// Distinguishes an emoji string from an ASCII SF Symbol identifier.
    nonisolated static func isEmoji(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.unicodeScalars.contains { !$0.isASCII }
    }

    /// Extracts the first emoji grapheme cluster from user input, rejecting plain ASCII characters.
    nonisolated static func extractFirstEmoji(from text: String) -> String? {
        for character in text {
            let hasEmojiScalar = character.unicodeScalars.contains { scalar in
                scalar.properties.isEmojiPresentation
                    || (scalar.properties.isEmoji && !scalar.isASCII)
            }
            if hasEmojiScalar {
                return String(character)
            }
        }
        return nil
    }
}

// MARK: - Reusable Icon Badge (Supports Both Emojis and SF Symbols)

struct CountdownBadgeIcon: View {
    let icon: String
    let tint: Color
    var size: CGFloat = 40
    var cornerRadius: CGFloat = 10

    var body: some View {
        Group {
            if CountdownIconCatalog.isEmoji(icon) {
                Text(icon)
                    .font(.system(size: size * 0.56))
                    .minimumScaleFactor(0.5)
            } else {
                Image(systemName: icon)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
    }
}
