import SwiftUI
import AppKit

/// Design tokens. The dark column is the original palette (ported from
/// `frontend-new/src/index.css`); the light column is its counterpart. Tokens are
/// *adaptive* (`NSColor` dynamic provider) so the whole app flips with the active
/// `NSAppearance` — driven by Settings → Appearance (see RootView/SkriftDesktopApp).
enum Theme {
    // Surfaces (cross-app values: Palette — Shared/UI; Mac-only: literal hex)
    static let bg           = dyn(Palette.bg.mac)                     // window background
    static let sidebar      = dyn(light: 0xedeef3, dark: 0x15171f)    // recessed panel (Mac-only)
    static let surface      = dyn(Palette.surface)                    // cards
    static let surfaceHover = dyn(light: 0xf0f1f6, dark: 0x1e2130)    // (Mac-only)

    // Text
    static let textPrimary   = dyn(Palette.textPrimary.mac)
    static let textSecondary = dyn(Palette.textSecondary.mac)
    static let textMuted     = dyn(Palette.textTertiary.mac)

    // Accent + semantic / step colors
    static let accent      = dyn(Palette.accent)
    static let green       = dyn(Palette.green)                       // ready / check / export
    static let blue        = dyn(light: 0x2563eb, dark: 0x60a5fa)     // transcribe (Mac-only)
    static let amber       = dyn(Palette.amber)                       // enhance
    static let violet      = dyn(light: 0x6c5ce0, dark: 0xa78bfa)     // sanitise (Mac-only)
    static let destructive = dyn(Palette.red)

    // Naming review tiers (mocks/naming-review.html)
    static let nameLink        = dyn(Palette.nameLinked)              // linked subject
    static let nameSuggest     = dyn(Palette.nameSuggest.mac)         // dotted suggestion text
    static let nameSuggestLine = dyn(Palette.nameSuggestLine.mac)     // dotted underline

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

    /// A light/dark hex pair → one adaptive Color that resolves against the active
    /// appearance (so it follows the chosen theme). Cross-app tokens pass a
    /// `Palette` pair (Shared/UI/Palette.swift — one hex table for both apps).
    private static func dyn(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { ap in
            let hex = isDark(ap) ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                           green:   CGFloat((hex >> 8) & 0xff) / 255,
                           blue:    CGFloat(hex & 0xff) / 255,
                           alpha: 1)
        })
    }

    private static func dyn(_ pair: PalettePair) -> Color {
        dyn(light: pair.light, dark: pair.dark)
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
