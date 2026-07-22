import SwiftUI

/// iPad-wave layout constants + helpers (2026-07-22). The rule of the wave:
/// the phone's views are PROMOTED into panes at regular width — never forked.
/// Branch on `@Environment(\.horizontalSizeClass) == .regular` for layout,
/// `Adaptive.isPadIdiom` only for device-idiom facts (presentation style,
/// keyboard). Text never runs wall-to-wall: cap prose at `readingMaxWidth`.
enum Adaptive {
    /// The reading measure for note bodies / players / onboarding (~68ch).
    static let readingMaxWidth: CGFloat = 640
    /// The Notes list column width in the split view (the phone canvas, kept).
    static let listColumnWidth: CGFloat = 375
    /// Standing side panels (Connections, chapters rail).
    static let sidePanelWidth: CGFloat = 300

    static var isPadIdiom: Bool { UIDevice.current.userInterfaceIdiom == .pad }
}

extension View {
    /// Cap content at the reading measure and center it — the iPad's "no
    /// wall-to-wall prose" rule. A no-op visual on compact widths.
    func readingMeasure(_ max: CGFloat = Adaptive.readingMaxWidth) -> some View {
        frame(maxWidth: max)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
