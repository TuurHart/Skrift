import SwiftUI

/// The Skrift visual language, ported 1:1 from the locked mockups
/// (`mockups/mockup{1..5}.html`). Dark-only for now; a Light/Auto toggle is a
/// later Settings detail. Colors are literal (not semantic) because the design
/// is a single fixed dark palette — adaptive system colors would fight it.
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

    // Surfaces
    static let skBg = Color(hex: 0x0f1117)
    static let skSurface = Color(hex: 0x181a23)
    static let skElev = Color(hex: 0x1e2130)
    static let skBorder = Color.white.opacity(0.06)

    // Text
    static let skText = Color(hex: 0xe4e4e7)       // t1 — primary
    static let skTextDim = Color(hex: 0x8b8b97)    // t2 — secondary
    static let skTextFaint = Color(hex: 0x55556a)  // t3 — tertiary

    // Accent + semantics
    static let skAccent = Color(hex: 0x7c6bf5)
    static let skAccentSoft = Color(hex: 0x7c6bf5, alpha: 0.15)
    static let skGreen = Color(hex: 0x34d399)
    static let skAmber = Color(hex: 0xf59e0b)
    static let skRed = Color(hex: 0xef4444)
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
