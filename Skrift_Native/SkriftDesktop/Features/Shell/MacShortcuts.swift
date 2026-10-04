import Foundation

/// What the app menu's keyboard commands ask for (D169). The chords come from
/// `AppShortcuts`; `RootView` owns the window state, so a command posts the action there.
enum MacShortcutAction: String {
    case newNote, record, search, notes, review

    @MainActor
    func post() {
        NotificationCenter.default.post(name: .macShortcut, object: rawValue)
    }
}

extension Notification.Name {
    static let macShortcut = Notification.Name("skrift.mac.shortcut")
}
