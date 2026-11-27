import Foundation

@MainActor
public enum TallyKeyboard {
    /// Host apps register their UIKit keyboard-dismissal handler on launch so `TallyCore`
    /// remains 100% App Extension safe (no `UIApplication.shared` symbol linked into widgets).
    public static var dismissHandler: (@MainActor () -> Void)?

    public static func dismiss() {
        dismissHandler?()
    }
}
