import Foundation
import OSLog
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
    private static let storeFilename = "default.store"

    /// Creates a `ModelContainer`, optionally backed by a shared App Group container so
    /// Widget Extensions and App Intents share the exact same SwiftData database as the app.
    /// Automatically migrates any existing pre-App-Group store without losing user data.
    public static func makeContainer(
        for models: [any PersistentModel.Type],
        appGroupIdentifier: String? = nil
    ) -> TallyContainerResult {
        let schema = Schema(models)
        let persistentConfig = makePersistentConfiguration(
            schema: schema,
            appGroupIdentifier: appGroupIdentifier
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [persistentConfig])
            return TallyContainerResult(
                container: container,
                isUsingFallbackStore: false,
                startupErrorDescription: nil
            )
        } catch {
            TallyLogger.storage.error(
                "Persistent ModelContainer failed to initialize: \(error.localizedDescription, privacy: .public)"
            )
            let fallbackConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            do {
                let fallbackContainer = try ModelContainer(for: schema, configurations: [fallbackConfig])
                return TallyContainerResult(
                    container: fallbackContainer,
                    isUsingFallbackStore: true,
                    startupErrorDescription: "Saved data could not be loaded. Changes in this session are temporary."
                )
            } catch {
                TallyLogger.storage.fault(
                    "In-memory fallback ModelContainer also failed: \(error.localizedDescription, privacy: .public)"
                )
                return TallyContainerResult(
                    container: nil,
                    isUsingFallbackStore: false,
                    startupErrorDescription: "Unable to initialize local storage. Please restart the app or check available device storage."
                )
            }
        }
    }

    private static func makePersistentConfiguration(
        schema: Schema,
        appGroupIdentifier: String?
    ) -> ModelConfiguration {
        guard let groupID = appGroupIdentifier, !groupID.isEmpty else {
            return ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
        }

        let fileManager = FileManager.default
        guard let groupRoot = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            TallyLogger.storage.warning(
                "App Group container '\(groupID, privacy: .public)' unavailable; falling back to app sandbox store."
            )
            return ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
        }

        let appSupportDir = groupRoot
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        let groupStoreURL = appSupportDir.appendingPathComponent(storeFilename)
        let legacyStoreURL = URL.applicationSupportDirectory.appendingPathComponent(storeFilename)

        do {
            try migrateLegacyStoreIfNeeded(
                from: legacyStoreURL,
                to: groupStoreURL,
                fileManager: fileManager
            )
        } catch {
            TallyLogger.storage.error(
                "Legacy SwiftData store migration to App Group failed: \(error.localizedDescription, privacy: .public)"
            )
        }

        return ModelConfiguration(
            schema: schema,
            url: groupStoreURL,
            cloudKitDatabase: .none
        )
    }

    /// Copies a legacy SwiftData SQLite store (plus `-wal` and `-shm` sidecars) into `destinationURL`
    /// if `destinationURL` does not yet exist and `legacyURL` is present.
    @discardableResult
    public static func migrateLegacyStoreIfNeeded(
        from legacyURL: URL,
        to destinationURL: URL,
        fileManager: FileManager = .default
    ) throws -> Bool {
        let destinationDir = destinationURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: destinationDir.path) {
            try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        }

        guard !fileManager.fileExists(atPath: destinationURL.path),
              fileManager.fileExists(atPath: legacyURL.path) else {
            return false
        }

        try fileManager.copyItem(at: legacyURL, to: destinationURL)

        for suffix in ["-wal", "-shm"] {
            let legacySidecar = URL(fileURLWithPath: legacyURL.path + suffix)
            let destSidecar = URL(fileURLWithPath: destinationURL.path + suffix)
            if fileManager.fileExists(atPath: legacySidecar.path)
                && !fileManager.fileExists(atPath: destSidecar.path) {
                try fileManager.copyItem(at: legacySidecar, to: destSidecar)
            }
        }

        TallyLogger.storage.info(
            "Migrated legacy SwiftData store to shared App Group location."
        )
        return true
    }
}
