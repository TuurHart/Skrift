import Foundation

// MARK: - Text-capture sentence selection (pure, host-testable)

/// Contiguous sentence selection for the build-your-quote body (`MergedCaptureView`).
/// Every grey line shows "+"; tapping any extends the quote to cover it; tapping a
/// selected END line drops it. Pure so the rules are unit-tested without a view.
/// (Lifted out of the retired `TextCaptureView` when the merged capture screen
/// became the only flow, 2026-06-13.)
struct TextCaptureSelection: Equatable {
    var lo: Int
    var hi: Int

    /// Apply a tap on sentence `i`; returns a short status (or nil). Mutates lo/hi.
    mutating func tap(_ i: Int) -> String? {
        if i < lo { lo = i; return "added — \(count) lines" }
        if i > hi { hi = i; return "added — \(count) lines" }
        if lo == hi { return "this is your quote — tap a + line to add more" }
        if i == lo { lo += 1; return "dropped the top line" }
        if i == hi { hi -= 1; return "dropped the bottom line" }
        return "tap an end line (✕) to shorten"
    }

    var count: Int { hi - lo + 1 }
    func isSelected(_ i: Int) -> Bool { i >= lo && i <= hi }
    func isEdge(_ i: Int) -> Bool { hi > lo && (i == lo || i == hi) }
}

enum TextCaptureMath {
    /// GLOBAL book span for the selected sentence range. `sentences[*].start/end`
    /// are window-local; add `windowStart` (file-local) then `fileOrigin`
    /// (global) — the inverse of the rebasing the capture flow does to file-local.
    static func globalSpan(sentences: [BufferSentence], lo: Int, hi: Int,
                           windowStart: TimeInterval, fileOrigin: TimeInterval) -> CaptureSpan.Span? {
        guard sentences.indices.contains(lo), sentences.indices.contains(hi), lo <= hi else { return nil }
        return CaptureSpan.Span(
            start: sentences[lo].start + windowStart + fileOrigin,
            end:   sentences[hi].end   + windowStart + fileOrigin
        )
    }
}
