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

    // Surfaces                              light       dark
    static let skSurface = skDynamic(light: 0xffffff, dark: 0x181a23)   // cards
    static let skBg      = skDynamic(light: 0xf5f5f7, dark: 0x0f1117)   // window
    static let skElev    = skDynamic(light: 0xebebf0, dark: 0x1e2130)   // chips / fields
    /// Hairline: a faint dark line on light, a faint white line on dark.
    static let skBorder  = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.06) : UIColor(white: 0, alpha: 0.09)
    })

    // Text                                     light       dark
    static let skText      = skDynamic(light: 0x1c1c1e, dark: 0xe4e4e7)   // t1 — primary
    static let skTextDim   = skDynamic(light: 0x6c6c72, dark: 0x8b8b97)   // t2 — secondary
    static let skTextFaint = skDynamic(light: 0xa3a3aa, dark: 0x55556a)   // t3 — tertiary

    // Accent + semantics                       light       dark
    static let skAccent     = skDynamic(light: 0x6c5ce0, dark: 0x7c6bf5)
    static let skAccentSoft = skDynamic(light: 0x6c5ce0, dark: 0x7c6bf5, alpha: 0.13)
    /// The lighter-purple accent used for small text/labels (e.g. tag text). On
    /// light it deepens so it stays legible on white.
    static let skAccentText = skDynamic(light: 0x6051c8, dark: 0xb9acff)
    static let skGreen      = skDynamic(light: 0x0f9d72, dark: 0x34d399)
    static let skAmber      = skDynamic(light: 0xd97706, dark: 0xf59e0b)
    static let skRed        = skDynamic(light: 0xdc2626, dark: 0xef4444)

    // Name-linking tiers — the phone in-place linking surface
    // (mocks/phone-name-linking.html). Dark = the mock's exact values; light deepens for
    // contrast on white. LINKED is solid; SUGGESTED/AMBIGUOUS/PLAIN are dotted underlines.
    static let skNameLinked      = skDynamic(light: 0x6c5ce0, dark: 0x9d8ff7)   // solid accent
    static let skNameSuggest     = skDynamic(light: 0x8a6d3b, dark: 0xbda481)   // tan text
    static let skNameSuggestLine = skDynamic(light: 0xa8843f, dark: 0xc4a982)   // tan dotted underline
    static let skNameAmbigLine   = skDynamic(light: 0x6c5ce0, dark: 0x7c6bf5, alpha: 0.7)  // purple dotted
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
