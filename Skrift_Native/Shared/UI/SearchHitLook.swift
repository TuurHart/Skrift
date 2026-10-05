import Foundation
import CoreGraphics

/// THE cross-app search-hit rule (Q321): a note opened from a search shows every
/// occurrence of the term like a highlighter pen, and scrolls the FIRST one to the
/// vertical middle of the visible area. One yellow, one centring formula — the
/// phone (`NoteBodyView`) and the Mac (`BodyTextView`) both read it from here.
enum SearchHitLook {
    /// Highlighter yellow. The same value in light and dark: it is a pen, not a surface.
    static let fillHex: UInt32 = 0xFFE81F
    /// Dark text on the yellow, in both modes (light-mode body text is dark already;
    /// dark-mode body text is near-white and would vanish on yellow).
    static let textHex: UInt32 = 0x1A1A1A
    /// How long the pen stays on the page before the normal styling repaints.
    static let holdSeconds: Double = 6
    /// More than this many occurrences is a stopword, not a hit; the rest stay unpainted.
    static let maxHighlights = 300

    /// Every case- and diacritic-insensitive occurrence of `query` in `text`, in order.
    static func matchRanges(of query: String, in text: String) -> [NSRange] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let ns = text as NSString
        var out: [NSRange] = []
        var from = 0
        while from < ns.length, out.count < maxHighlights {
            let r = ns.range(of: q, options: [.caseInsensitive, .diacriticInsensitive],
                             range: NSRange(location: from, length: ns.length - from))
            guard r.location != NSNotFound, r.length > 0 else { break }
            out.append(r)
            from = NSMaxRange(r)
        }
        return out
    }

    /// The scroll offset (`contentOffset.y`) that puts the hit's vertical centre at the
    /// centre of the VISIBLE area — the viewport minus the top/bottom insets (safe area,
    /// player bar, keyboard) — clamped so a hit near either end of the note scrolls only
    /// as far as the content allows.
    /// - hitMidY: vertical centre of the hit rect, in content coordinates.
    /// - viewportHeight: the scroll view's full bounds height.
    /// - topInset / bottomInset: the adjusted content insets (0 on the Mac).
    static func centeredOffsetY(hitMidY: CGFloat, contentHeight: CGFloat,
                                viewportHeight: CGFloat,
                                topInset: CGFloat = 0, bottomInset: CGFloat = 0) -> CGFloat {
        let visible = max(0, viewportHeight - topInset - bottomInset)
        let wanted = hitMidY - topInset - visible / 2
        let lowest = -topInset
        let highest = max(lowest, contentHeight + bottomInset - viewportHeight)
        return min(max(wanted, lowest), highest)
    }
}
