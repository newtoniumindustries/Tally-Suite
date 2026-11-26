import SwiftData
import SwiftUI

private struct FallbackStoreEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Indicates whether the app fell back to an in-memory SwiftData store because persistent storage failed to load.
    var isUsingFallbackStore: Bool {
        get { self[FallbackStoreEnvironmentKey.self] }
        set { self[FallbackStoreEnvironmentKey.self] = newValue }
    }
}

/// Shared root container wrapper that attaches the `ModelContainer`, surfaces the fallback-store warning banner,
/// or displays an unavailable-storage state when local storage cannot be initialized.
public struct TallyAppContainerView<Content: View>: View {
    private let result: TallyContainerResult
    private let appDisplayName: String
    private let content: () -> Content

    public init(
        result: TallyContainerResult,
        appDisplayName: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.result = result
        self.appDisplayName = appDisplayName
        self.content = content
    }

    public var body: some View {
        if let container = result.container {
            VStack(spacing: 0) {
                if result.isUsingFallbackStore, let warning = result.startupErrorDescription {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .accessibilityHidden(true)
                        Text(warning)
                            .font(.caption.bold())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange)
                    .accessibilityElement(children: .combine)
                }

                content()
            }
            .environment(\.isUsingFallbackStore, result.isUsingFallbackStore)
            .modelContainer(container)
        } else {
            ContentUnavailableView(
                "Storage Unavailable",
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text(
                    result.startupErrorDescription
                        ?? "Please restart \(appDisplayName) to try again."
                )
            )
        }
    }
}
