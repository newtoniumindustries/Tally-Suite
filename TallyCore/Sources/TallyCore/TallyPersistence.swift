import Foundation
import OSLog
import SwiftData

public enum TallyLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.newtastic.TallySuite"

    public static let storage = Logger(subsystem: subsystem, category: "storage")
    public static let scoring = Logger(subsystem: subsystem, category: "scoring")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
}

public extension ModelContext {
    /// Saves pending changes and logs any error rather than silently discarding it.
    /// Automatically reloads WidgetKit timelines on success.
    @discardableResult
    func saveLoggingErrors(
        reloadWidgets: Bool = true,
        context: String = #function
    ) -> Bool {
        saveReportingError(reloadWidgets: reloadWidgets, context: context) == nil
    }

    /// Saves pending changes, logging any failure and returning a user-displayable message if saving failed.
    /// Automatically reloads WidgetKit timelines on success.
    func saveReportingError(
        reloadWidgets: Bool = true,
        context: String = #function
    ) -> String? {
        do {
            try save()
            if reloadWidgets {
                TallyWidgetReloader.reloadAll()
            }
            return nil
        } catch {
            TallyLogger.storage.error(
                "SwiftData save failed in \(context, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return "Changes could not be saved (\(error.localizedDescription)). Please check available device storage and try again."
        }
    }
}
