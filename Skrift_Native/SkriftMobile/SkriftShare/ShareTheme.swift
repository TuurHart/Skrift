import SwiftUI
import UIKit

/// The share extension's fixed dark palette + sizing, shared by the host
/// controller, the sheet and the feedback card (they each carried a copy).
enum ShareTheme {
    private static let backdropRGB = (r: 0.055, g: 0.059, b: 0.086)   // #0e0f16
    private static let surfaceRGB = (r: 0.106, g: 0.110, b: 0.157)    // #1b1d28 per mock

    /// Opaque backdrop behind the card: a translucent scrim would wash out over
    /// the host sheet's light-gray backdrop. One step darker than the surface.
    static let backdrop = Color(red: backdropRGB.r, green: backdropRGB.g, blue: backdropRGB.b)
    static let backdropUI = UIColor(red: backdropRGB.r, green: backdropRGB.g, blue: backdropRGB.b, alpha: 1)
    /// The elevated sheet surface.
    static let surface = Color(red: surfaceRGB.r, green: surfaceRGB.g, blue: surfaceRGB.b)
    /// Ask the host for more height than any sheet can give; it clamps.
    static let hostHeight: CGFloat = 10_000
    static let sheetCornerRadius: CGFloat = 22
}

extension View {
    /// The bottom-sheet block: elevated surface with rounded top corners and a
    /// hairline. `.container` only — ignoring the whole bottom safe area would
    /// also ignore the KEYBOARD region, burying the controls under it while
    /// typing (the 2026-06-12 finding).
    func shareSheetSurface() -> some View {
        self
            .background(
                ShareTheme.surface
                    .ignoresSafeArea(.container, edges: .bottom)
                    .clipShape(.rect(topLeadingRadius: ShareTheme.sheetCornerRadius,
                                     topTrailingRadius: ShareTheme.sheetCornerRadius,
                                     style: .continuous))
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: ShareTheme.sheetCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
                    .ignoresSafeArea(.container, edges: .bottom)
            }
    }
}
