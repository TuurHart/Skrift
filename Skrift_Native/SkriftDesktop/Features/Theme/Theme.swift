import SwiftUI
import AppKit

/// Design tokens. The dark column is the original palette (ported from
/// `frontend-new/src/index.css`); the light column is its counterpart. Tokens are
/// *adaptive* (`NSColor` dynamic provider) so the whole app flips with the active
/// `NSAppearance` — driven by Settings → Appearance (see RootView/SkriftDesktopApp).
enum Theme {
    // Surfaces                          light (r,g,b)        dark (r,g,b)
    static let bg           = dyn(247, 247, 250,    15,  17,  23)   // window background
    static let sidebar      = dyn(237, 238, 243,    21,  23,  31)   // recessed panel
    static let surface      = dyn(255, 255, 255,    24,  26,  35)   // cards
    static let surfaceHover = dyn(240, 241, 246,    30,  33,  48)

    // Text                                light            dark
    static let textPrimary   = dyn( 28,  28,  32,  228, 228, 231)
    static let textSecondary = dyn(108, 108, 118,  139, 139, 151)
    static let textMuted     = dyn(150, 150, 162,   85,  85, 106)

    // Accent + semantic / step colors     light            dark
    static let accent      = dyn(108,  92, 224,  124, 107, 245)
    static let green       = dyn( 15, 157, 114,   52, 211, 153)   // ready / check / export
    static let blue        = dyn( 37,  99, 235,   96, 165, 250)   // transcribe
    static let amber       = dyn(217, 119,   6,  245, 158,  11)   // enhance
    static let violet      = dyn(108,  92, 224,  167, 139, 250)   // sanitise
    static let destructive = dyn(220,  38,  38,  239,  68,  68)

    // Naming review tiers (mocks/naming-review.html)  light            dark
    static let nameLink        = dyn(108,  92, 224,  157, 143, 247)  // linked subject (#9d8ff7 dark)
    static let nameSuggest     = dyn(150, 110,  48,  189, 164, 129)  // dotted suggestion text (#bda481 dark)
    static let nameSuggestLine = dyn(150, 110,  48,  171, 150, 118)  // dotted underline (#ab9676 dark)

    /// Hairline base — a faint dark line on light, a faint white line on dark.
    /// Used with `.opacity()` for borders / overlay tints (mirrors the web
    /// `--color-border` alpha-modifier pattern).
    static let hairline = Color(nsColor: NSColor(name: nil) { ap in
        isDark(ap) ? .white : .black
    })

    /// Static sRGB color (no adaptation) — for the accent gradients that read the
    /// same in both themes.
    static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: 1)
    }

    private static func isDark(_ ap: NSAppearance) -> Bool {
        ap.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// A light/dark RGB pair → one adaptive Color that resolves against the active
    /// appearance (so it follows the chosen theme).
    private static func dyn(_ lr: Double, _ lg: Double, _ lb: Double,
                            _ dr: Double, _ dg: Double, _ db: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { ap in
            let dark = isDark(ap)
            return NSColor(srgbRed: (dark ? dr : lr) / 255,
                           green:   (dark ? dg : lg) / 255,
                           blue:    (dark ? db : lb) / 255,
                           alpha: 1)
        })
    }
}

/// The "appTheme" preference ("dark" | "light" | "auto") → SwiftUI / AppKit
/// appearance. SwiftUI views adapt via `.preferredColorScheme`; system-drawn
/// controls (text-field placeholders, carets, menus) follow `NSApp.appearance`,
/// so both must be set — that's why the app forced `.darkAqua` before.
enum AppTheme {
    static let key = "appTheme"
    static var current: String { UserDefaults.standard.string(forKey: key) ?? "dark" }

    static func colorScheme(_ raw: String) -> ColorScheme? {
        switch raw {
        case "light": return .light
        case "auto":  return nil       // follow the system
        default:      return .dark
        }
    }

    static func nsAppearance(_ raw: String) -> NSAppearance? {
        switch raw {
        case "light": return NSAppearance(named: .aqua)
        case "auto":  return nil        // follow the system
        default:      return NSAppearance(named: .darkAqua)
        }
    }

    /// Push the preference to the AppKit layer (system-drawn controls).
    @MainActor static func applyToApp(_ raw: String = current) {
        NSApplication.shared.appearance = nsAppearance(raw)
    }
}
