import SwiftUI

/// The "appTheme" preference ("dark" | "light" | "auto") — ONE reading for both apps
/// (Q172, setexp-08). The phone's `SkriftApp.colorScheme` and the Mac's
/// `AppTheme.colorScheme` / `AppTheme.nsAppearance` each carried the same switch;
/// they now read `mode(_:)`. Anything unknown (or the default) is dark: the palette
/// is dark-first.
enum ThemePreference {
    static let key = "appTheme"
    static let defaultRaw = "dark"

    enum Mode: Equatable { case light, dark, system }

    static func mode(_ raw: String) -> Mode {
        switch raw {
        case "light": return .light
        case "auto":  return .system   // follow the system
        default:      return .dark
        }
    }

    /// The SwiftUI scheme for `.preferredColorScheme`; nil = follow the system.
    static func colorScheme(_ raw: String) -> ColorScheme? {
        switch mode(raw) {
        case .light:  return .light
        case .system: return nil
        case .dark:   return .dark
        }
    }
}
