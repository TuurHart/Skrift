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

    /// A sliding panel column (mock ipad-note-stacking.html): the content keeps
    /// its fixed width while an outer window animates open↔0, pinned to the
    /// window's surviving edge — so the column SLIDES off-screen instead of
    /// squashing, and it never leaves the hierarchy (its state, and any
    /// presentations hanging off it, survive the collapse).
    func slidingColumn(width: CGFloat, open: Bool, edge: HorizontalEdge) -> some View {
        frame(width: width)
            .frame(width: open ? width : 0,
                   alignment: edge == .leading ? .trailing : .leading)
            .clipped()
    }

    /// iPadOS-26 bar-control containment (signed mock ipad-note-chrome-belongs):
    /// no control hangs bare in the workbench toolbar — each sits in a quiet
    /// glass chip (`skElev` fill + hairline), or an accent-soft chip while its
    /// state is active. Shape-generic so ◧ (circle) and the Connections capsule
    /// share one treatment.
    func barGlass(on: Bool = false, in shape: some InsettableShape = Circle()) -> some View {
        background(on ? Color.skAccentSoft : Color.skElev, in: shape)
            .overlay(on ? nil : shape.strokeBorder(Color.skBorder, lineWidth: 0.5))
    }
}

/// The workbench's one panel toggle — the pinned ◧ (signed mock
/// ipad-note-chrome-belongs.html): a plain system sidebar glyph in an
/// iPadOS-26 glass chip, accent-soft while the list is open, quiet while it's
/// hidden. Screen-pinned by its host so it never appears to move as the
/// surface beneath it changes.
struct PanelToggle: View {
    let icon: String
    let on: Bool
    let label: String
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(on ? Color.skAccentText : Color.skTextDim)
                .frame(width: 30, height: 30)
                .barGlass(on: on)
        }
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
    }
}
