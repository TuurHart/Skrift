import SwiftUI

/// Design tokens ported from `frontend-new/src/index.css` (DARK theme — the default).
/// RGB values are kept verbatim so the native app matches the web palette exactly.
/// `.light` theme is deferred (Phase 8); dark is the product default.
enum Theme {
    // Surfaces
    static let bg           = rgb(15, 17, 23)    // window background
    static let sidebar      = rgb(21, 23, 31)    // flat, lightened panel (#15171f)
    static let surface      = rgb(24, 26, 35)
    static let surfaceHover = rgb(30, 33, 48)

    // Text
    static let textPrimary   = rgb(228, 228, 231)
    static let textSecondary = rgb(139, 139, 151)
    static let textMuted     = rgb(85, 85, 106)

    // Accent + semantic / step colors
    static let accent      = rgb(124, 107, 245)
    static let green       = rgb(52, 211, 153)   // ready / check / export
    static let blue        = rgb(96, 165, 250)   // transcribe
    static let amber       = rgb(245, 158, 11)   // enhance
    static let violet      = rgb(167, 139, 250)  // sanitise
    static let destructive = rgb(239, 68, 68)

    /// White — use with `.opacity()` for hairline borders / overlay tints
    /// (mirrors the web `--color-border` alpha-modifier pattern).
    static let hairline = Color.white

    static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: 1)
    }
}
