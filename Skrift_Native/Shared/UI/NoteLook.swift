import Foundation
import CoreGraphics

/// The note's look tokens, one copy for both apps (Q185; rows note-body-15, note-body-19,
/// note-chrome-01, note-chrome-02). Numbers and words only, no Color/UIColor/NSColor, so
/// each app's drawing code stays its own and cannot drift on a value.
///
/// Picks (a signed mock wins where it names a value, otherwise the phone's):
/// - inline photo: phone rule (fills the column, 320pt tall cap)
/// - memo-link chip: the Mac's bordered look and 🗒 glyph (mocks/journal-desktop.html,
///   related-panel.html draw `🗒 Title`); the title cut stays a per-app limit because a
///   chip image cannot wrap and the phone column is narrow
/// - top band: 14pt side padding (mocks/ipad-note-chrome-belongs.html `.chromebar`),
///   hairline at the phone's alpha
/// - list toggle: the phone's 'Hide notes list' / 'Show notes list'
enum NoteLook {
    // MARK: Inline photo

    /// Tallest an inline photo grows, in points.
    static let photoMaxHeight: CGFloat = 320
    /// Corner radius as a fraction of the photo's shorter side.
    static let photoCornerFraction: CGFloat = 0.04

    /// Size to draw a photo of `image` size in a column `columnWidth` wide: fill the column,
    /// keep the aspect, cap the height (a portrait frame shrinks its WIDTH to keep aspect).
    static func photoSize(image: CGSize, columnWidth: CGFloat) -> CGSize {
        guard image.width > 0, image.height > 0, columnWidth > 0 else {
            return CGSize(width: max(0, columnWidth), height: 0)
        }
        let aspect = image.width / image.height
        var w = columnWidth
        var h = w / aspect
        if h > photoMaxHeight { h = photoMaxHeight; w = h * aspect }
        return CGSize(width: w, height: h)
    }

    // MARK: Memo-link chip

    /// Leading glyph of the chip label.
    static let memoLinkGlyph = "🗒"
    static let memoLinkUntitled = "Untitled"
    static let memoLinkFillAlpha: CGFloat = 0.13
    static let memoLinkStrokeAlpha: CGFloat = 0.35
    static let memoLinkCornerRadius: CGFloat = 6
    static let memoLinkPadH: CGFloat = 8
    /// Title cut per app: the phone column is narrow, the Mac chip shows the full title.
    static let memoLinkMaxTitlePhone = 28

    /// The chip's label text. `maxTitle` nil = full title.
    static func memoLinkLabel(title: String, maxTitle: Int?) -> String {
        var shown = title.isEmpty ? memoLinkUntitled : title
        if let maxTitle, shown.count > maxTitle { shown = String(shown.prefix(maxTitle - 1)) + "…" }
        return "\(memoLinkGlyph) \(shown)"
    }

    // MARK: Top band (note chrome)

    static let bandHeight: CGFloat = 48
    static let bandSidePadding: CGFloat = 14
    static let bandHairlineHeight: CGFloat = 0.5
    /// Hairline alpha (black on light, white on dark). Also the phone's `skBorder`.
    static let hairlineAlphaDark: Double = 0.06
    static let hairlineAlphaLight: Double = 0.09
    static func hairlineAlpha(dark: Bool) -> Double { dark ? hairlineAlphaDark : hairlineAlphaLight }

    // MARK: Notes-list toggle

    static func listToggleLabel(listVisible: Bool) -> String {
        listVisible ? "Hide notes list" : "Show notes list"
    }
}
