import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Triggers WidgetKit timeline refreshes when persisted app data changes.
public enum TallyWidgetReloader: Sendable {
    public static func reloadAll() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    public static func reload(kind: String) {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
        #endif
    }
}
