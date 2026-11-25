import Foundation
import SwiftData

public struct TallyContainerResult: Sendable {
    public let container: ModelContainer?
    public let isUsingFallbackStore: Bool
    public let startupErrorDescription: String?

    public init(
        container: ModelContainer?,
        isUsingFallbackStore: Bool,
        startupErrorDescription: String?
    ) {
        self.container = container
        self.isUsingFallbackStore = isUsingFallbackStore
        self.startupErrorDescription = startupErrorDescription
    }
}

public enum TallyDataConfig {
    public static func makeContainer(for models: [any PersistentModel.Type]) -> TallyContainerResult {
        let schema = Schema(models)

        let persistentConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [persistentConfig])
            return TallyContainerResult(
                container: container,
                isUsingFallbackStore: false,
                startupErrorDescription: nil
            )
        } catch {
            let fallbackConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            if let fallbackContainer = try? ModelContainer(for: schema, configurations: [fallbackConfig]) {
                return TallyContainerResult(
                    container: fallbackContainer,
                    isUsingFallbackStore: true,
                    startupErrorDescription: "Saved data could not be loaded. Changes in this session are temporary."
                )
            } else {
                return TallyContainerResult(
                    container: nil,
                    isUsingFallbackStore: false,
                    startupErrorDescription: "Unable to initialize local storage. Please restart the app or check available device storage."
                )
            }
        }
    }
}
