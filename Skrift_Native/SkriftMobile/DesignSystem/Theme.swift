import SwiftUI
import UIKit

/// The Skrift visual language, ported 1:1 from the locked mockups
/// (`mockups/mockup{1..5}.html`). The dark palette is the original/default; the
/// light variant is the second column of each token. Tokens are *adaptive*
/// (`UIColor` dynamic provider) so the whole app flips with the active trait —
/// `.preferredColorScheme` (driven by Settings → Theme) sets that trait.
extension Color {
    /// Hex literal → Color, e.g. `Color(hex: 0x7c6bf5)`.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }

    /// A light/dark hex pair → one adaptive Color that resolves against the active
    /// `userInterfaceStyle` (so it follows `.preferredColorScheme`).
    static func skDynamic(light: UInt32, dark: UInt32, alpha: Double = 1) -> Color {
        Color(uiColor: UIColor { tc in
            let hex = tc.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xff) / 255,
                green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255,
                alpha: CGFloat(alpha)
            )
        })
    }

    /// Shared-palette overload — cross-app tokens come from `Palette`
    /// (Shared/UI/Palette.swift), one hex table for both apps.
    static func skDynamic(_ pair: PalettePair, alpha: Double = 1) -> Color {
        skDynamic(light: pair.light, dark: pair.dark, alpha: alpha)
    }

    // Surfaces (cross-app values: Palette; phone-only: literal)
    static let skSurface = skDynamic(Palette.surface)                    // cards
    static let skBg      = skDynamic(Palette.bg.phone)                   // window
    static let skElev    = skDynamic(light: 0xebebf0, dark: 0x1e2130)   // chips / fields (phone-only)
    /// Hairline: a faint dark line on light, a faint white line on dark.
    static let skBorder  = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.06) : UIColor(white: 0, alpha: 0.09)
    })

    // Text
    static let skText      = skDynamic(Palette.textPrimary.phone)     // t1 — primary
    static let skTextDim   = skDynamic(Palette.textSecondary.phone)   // t2 — secondary
    static let skTextFaint = skDynamic(Palette.textTertiary.phone)    // t3 — tertiary

    // Accent + semantics
    static let skAccent     = skDynamic(Palette.accent)
    static let skAccentSoft = skDynamic(Palette.accent, alpha: 0.13)
    /// The lighter-purple accent used for small text/labels (e.g. tag text). On
    /// light it deepens so it stays legible on white. (Phone-only token.)
    static let skAccentText = skDynamic(light: 0x6051c8, dark: 0xb9acff)
    static let skGreen      = skDynamic(Palette.green)
    static let skAmber      = skDynamic(Palette.amber)
    static let skRed        = skDynamic(Palette.red)

    // Name-linking tiers — the phone in-place linking surface
    // (mocks/phone-name-linking.html). Dark = the mock's exact values; light deepens for
    // contrast on white. LINKED is solid; SUGGESTED/AMBIGUOUS/PLAIN are dotted underlines.
    static let skNameLinked      = skDynamic(Palette.nameLinked)                 // solid accent
    static let skNameSuggest     = skDynamic(Palette.nameSuggest.phone)          // tan text
    static let skNameSuggestLine = skDynamic(Palette.nameSuggestLine.phone)      // tan dotted underline
    static let skNameAmbigLine   = skDynamic(Palette.accent, alpha: 0.7)         // purple dotted
    /// Faint dotted underline for a kept-plain (leftplain) token.
    static let skNamePlainLine   = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.26) : UIColor(white: 0, alpha: 0.28)
    })
}

/// Spacing, corner radii, and motion constants. The mockups use a 4/8/16/24/32
/// spacing scale, continuous corners, and one spring for everything.
enum Theme {
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        /// Card inner padding + inter-card gap from the mockups.
        static let cardPadding: CGFloat = 13
        static let cardGap: CGFloat = 10
        /// Screen side margins.
        static let margin: CGFloat = 20
    }

    enum Radius {
        static let card: CGFloat = 16
        static let field: CGFloat = 11
        static let editBox: CGFloat = 12
        static let chip: CGFloat = 8
        static let sheet: CGFloat = 24
        static let group: CGFloat = 16
    }

    enum Motion {
        /// The single signature spring (`response:0.35, dampingFraction:0.85`).
        static let spring = Animation.spring(response: 0.35, dampingFraction: 0.85)
        /// For taps/toggles.
        static let snappy = Animation.snappy(duration: 0.22)
    }

    /// The recording timer's custom font — the only non-Dynamic-Type face.
    static func timerFont(_ size: CGFloat = 52) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }
}

/// Continuous-corner rounded rectangle, the app's default card/sheet shape.
extension RoundedRectangle {
    static func sk(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}
