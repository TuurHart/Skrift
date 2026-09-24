import SwiftUI
import AppKit

/// Design tokens. The dark column is the original palette (ported from
/// `frontend-new/src/index.css`); the light column is its counterpart. Tokens are
/// *adaptive* (`NSColor` dynamic provider) so the whole app flips with the active
/// `NSAppearance` — driven by Settings → Appearance (see RootView/SkriftDesktopApp).
enum Theme {
    // Surfaces (cross-app values: Palette — Shared/UI; Mac-only: literal hex)
    static let bg           = dyn(Palette.bg.mac)                     // window background
    // `sidebar` is GONE (2026-07-25): a Mac-only #15171f that made every panel
    // read darker than the iPad's. Tuur, comparing them: "we need to match the
    // colors of the panels on mac to what the ipad has… ipad is better. also match
    // those in shared code." Panels — the notes list, the Connections inspector, the
    // docked player — now all sit on the SHARED surface below, exactly as the iPad's
    // list column and Connections sheet do.
    static let surface      = dyn(Palette.surface)                    // panels + cards
    /// D135/D136 (one-notes-list): the sidebar's own ground, deliberately the
    /// PHONE's grey (`Palette.bg.phone`), not the Mac's own `Palette.bg.mac` window
    /// color — "I like the gray of the iPhone better". Rows sit on `Theme.surface`
    /// (white) over this, same figure/ground the phone/iPad now share.
    static let sidebarGround = dyn(Palette.bg.phone)
    static let surfaceHover = dyn(light: 0xf0f1f6, dark: 0x1e2130)    // (Mac-only)
    /// Bar-control containment fill — the quiet chip a toolbar control sits in
    /// (see `barGlass` below). Shared with the phone's `skElev`.
    static let chip         = dyn(Palette.chipFill)

    // Text
    static let textPrimary   = dyn(Palette.textPrimary.mac)
    static let textSecondary = dyn(Palette.textSecondary.mac)
    static let textMuted     = dyn(Palette.textTertiary.mac)

    // Accent + semantic / step colors
    static let accent      = dyn(Palette.accent)
    /// An ACTIVE bar chip's fill + its label colour (the phone's
    /// `skAccentSoft` / `skAccentText`) — a state tint, not a filled button.
    static let accentSoft  = dyn(Palette.accent).opacity(0.13)
    static let accentText  = dyn(Palette.accentText)
    static let green       = dyn(Palette.green)                       // ready / check / export
    static let blue        = dyn(light: 0x2563eb, dark: 0x60a5fa)     // transcribe (Mac-only)
    static let amber       = dyn(Palette.amber)                       // enhance
    static let violet      = dyn(light: 0x6c5ce0, dark: 0xa78bfa)     // sanitise (Mac-only)
    static let destructive = dyn(Palette.red)

    // Naming review tiers (mocks/naming-review.html)
    static let nameLink        = dyn(Palette.nameLinked)              // linked subject
    static let nameSuggest     = dyn(Palette.nameSuggest.mac)         // dotted suggestion text
    static let nameSuggestLine = dyn(Palette.nameSuggestLine.mac)     // dotted underline

    /// A conversation speaker's colour, by diarization/identity slot — the gutter name and
    /// its spine (signed mock E1). Table + slot doctrine: `Palette.speakerHues`.
    static func speakerHue(slot: Int) -> Color { dyn(Palette.speakerHue(slot: slot)) }

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

extension View {
    /// Bar-control containment — the Mac mirror of the iPad's `barGlass`
    /// (`SkriftMobile/DesignSystem/Adaptive.swift`, signed mock
    /// `mocks/ipad-note-chrome-belongs.html`): no control hangs bare in the note
    /// toolbar, each sits in a quiet chip (`Theme.chip` + hairline), or an
    /// accent-soft chip while its state is active. Shape-generic so ◧ (circle) and
    /// the Connections capsule share one treatment.
    func barGlass(on: Bool = false, in shape: some InsettableShape = Circle()) -> some View {
        background(on ? Theme.accentSoft : Theme.chip, in: shape)
            .overlay(on ? nil : shape.strokeBorder(Theme.hairline.opacity(0.10), lineWidth: 0.5))
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

/// The Mac look for the shared `TagEditorRow` (C240) — 12 pt chips, 22 pt tall, `✕`
/// on hover rather than tap-arm (D139 signed mock `tag-ui-revamp.html`: the pointer's
/// hover already gives the "are you sure" beat a touch doesn't have).
extension TagRowStyle {
    static let mac = TagRowStyle(
        chipFont: .system(size: 12, weight: .medium), chipHeight: 22, chipHPad: 9,
        fieldWidth: 90, armsOnTap: false,
        textColor: Theme.accent, backgroundColor: Theme.accentSoft, dimTextColor: Theme.textSecondary,
        elevColor: Theme.chip, borderColor: Theme.hairline.opacity(0.2), dangerColor: Theme.destructive,
        fieldBackground: Theme.hairline.opacity(0.06), fieldBorder: Theme.hairline.opacity(0.2))
}
