import Foundation

// Pure math for the audiobook quote-capture flow (no AVFoundation, no UI) —
// span proposal/clamping, sentence-snapping, and the C1 quote-block formatting.
// Everything here is host-less unit-tested (`AudiobookCaptureMathTests`).

/// The retroactive capture span: Capture pauses the book and proposes
/// [now − 30 s → now]; the micro-scrubber window around it spans
/// [now − 60 s → now + 15 s]. All values clamp to the book's bounds.
enum CaptureSpan {
    /// How far back the proposed span reaches from the pause point.
    static let lookback: TimeInterval = 30
    /// Micro-scrubber window before the pause point.
    static let windowLookback: TimeInterval = 60
    /// Micro-scrubber window after the pause point (OUT may snap past "now" —
    /// the sentence finishes).
    static let windowLookahead: TimeInterval = 15
    /// Extra audio transcribed on each side of the marked span so the
    /// sentence-snap has material to snap OUTWARD into.
    static let transcriptionPadding: TimeInterval = 20
    /// A degenerate proposal (capture at position 0) still offers this much.
    static let minimumSpan: TimeInterval = 1

    struct Span: Equatable, Sendable {
        var start: TimeInterval
        var end: TimeInterval
        var length: TimeInterval { max(0, end - start) }
    }

    /// The proposed quote span when Capture fires at `now`: the last 30 s,
    /// clamped to the file. Near the file start the span shortens; at position
    /// 0 a minimal forward span is proposed so the scrubber has a region.
    static func proposal(now: TimeInterval, duration: TimeInterval) -> Span {
        proposal(now: now, in: Span(start: 0, end: max(0, duration)))
    }

    /// Bounded variant: the proposal clamps to `bounds` instead of [0, file
    /// end] — multi-file books confine a capture to the ONE file `now` falls
    /// in (bounds = that file's global range).
    static func proposal(now: TimeInterval, in bounds: Span) -> Span {
        var end = min(bounds.end, max(bounds.start, now))
        let start = max(bounds.start, end - lookback)
        if end - start < minimumSpan {
            end = min(bounds.end, start + minimumSpan)
        }
        return Span(start: start, end: max(end, start))
    }

    /// The micro-scrubber's visible window around the pause point, clamped to
    /// the file. Always contains the proposal for the same `now`.
    static func window(now: TimeInterval, duration: TimeInterval) -> Span {
        window(now: now, in: Span(start: 0, end: max(0, duration)))
    }

    /// Bounded variant of `window` (see `proposal(now:in:)`). This is only the
    /// INITIAL window — the strip can then PAN it anywhere inside the bounds
    /// (`CaptureScrub.pan`/`panned(toInclude:)`).
    static func window(now: TimeInterval, in bounds: Span) -> Span {
        let anchor = min(bounds.end, max(bounds.start, now))
        let start = max(bounds.start, anchor - windowLookback)
        let end = min(bounds.end, anchor + windowLookahead)
        return Span(start: start, end: max(end, start))
    }

    /// The span actually sent through the transcriber: the marked span ± the
    /// padding, clamped — never the whole book.
    static func transcriptionBuffer(for span: Span, duration: TimeInterval) -> Span {
        Span(start: max(0, span.start - transcriptionPadding),
             end: min(max(0, duration), span.end + transcriptionPadding))
    }
}

/// Pure math for the micro-scrubber's IN/OUT handles and the PANNABLE window
/// (no UI, host-less unit-tested in `AudiobookScrubberTests`): drag latching,
/// no-cross clamping with a minimum span, x↔time mapping, and window panning
/// within the file's bounds.
enum CaptureScrub {
    /// IN and OUT can never get closer than this (seconds).
    static let minimumSpan: TimeInterval = 1

    enum Handle: Equatable, Sendable { case inMarker, outMarker }

    /// Drag ownership: the FIRST change of a drag claims its handle and keeps
    /// it until that drag releases it — a simultaneous touch on the other
    /// handle can't steal or re-aim an in-flight drag (the "OUT jumps while
    /// dragging toward IN" bug). Which handle a drag moves is decided ONCE,
    /// at gesture start, never re-evaluated per move.
    struct Latch: Equatable, Sendable {
        private(set) var active: Handle?

        /// True when `handle` owns the drag (claiming it if free).
        mutating func claim(_ handle: Handle) -> Bool {
            if active == nil { active = handle }
            return active == handle
        }

        /// Release only by the owner — a stray `onEnded` from a losing gesture
        /// must not free the latch out from under the active drag.
        mutating func release(_ handle: Handle) {
            if active == handle { active = nil }
        }
    }

    /// Map a drag x in strip coordinates to time on the window. NOT clamped —
    /// a finger past the strip's edge maps past the window, which is exactly
    /// what `panned(toInclude:)` uses to edge-bump the window along.
    static func time(atX x: Double, stripWidth: Double, window: CaptureSpan.Span) -> TimeInterval {
        window.start + (x / max(1, stripWidth)) * window.length
    }

    /// Apply a handle drag: move ONLY `handle` to `raw`, clamped to `bounds`,
    /// never crossing the other handle (minimum span preserved).
    static func dragged(
        _ span: CaptureSpan.Span,
        handle: Handle,
        to raw: TimeInterval,
        bounds: CaptureSpan.Span
    ) -> CaptureSpan.Span {
        var s = span
        switch handle {
        case .inMarker:
            // The outer max guards tiny files where end − minimumSpan would
            // fall before the bounds.
            s.start = min(max(bounds.start, raw), max(bounds.start, span.end - minimumSpan))
        case .outMarker:
            s.end = max(min(bounds.end, raw), min(bounds.end, span.start + minimumSpan))
        }
        return s
    }

    /// Window-confined handle drag (capture round 2): the handle moves ONLY
    /// inside the visible window (∩ bounds) — a finger past the strip's edge
    /// pins at the edge instead of auto-panning the window along underneath,
    /// which is how a span ran away to "pause+99s → pause+256s" on device.
    /// Reaching earlier/later audio is now explicit: pan the window first
    /// (the span stays anchored to its book positions), then drag the handle.
    static func dragged(
        _ span: CaptureSpan.Span,
        handle: Handle,
        to raw: TimeInterval,
        within window: CaptureSpan.Span,
        bounds: CaptureSpan.Span
    ) -> CaptureSpan.Span {
        let pinned = min(max(raw, window.start), window.end)
        return dragged(span, handle: handle, to: pinned, bounds: bounds)
    }

    /// Pan the window by `delta` seconds (the strip-background drag),
    /// preserving its length, clamped inside `bounds`.
    static func pan(
        _ window: CaptureSpan.Span,
        by delta: TimeInterval,
        bounds: CaptureSpan.Span
    ) -> CaptureSpan.Span {
        let length = min(window.length, bounds.length)
        let start = min(max(bounds.start, window.start + delta), bounds.end - length)
        return CaptureSpan.Span(start: start, end: start + length)
    }

    /// Edge-bump: pan the window just enough to contain `t` — a handle dragged
    /// past the visible edge keeps going and the window follows the finger.
    static func panned(
        toInclude t: TimeInterval,
        window: CaptureSpan.Span,
        bounds: CaptureSpan.Span
    ) -> CaptureSpan.Span {
        let clamped = min(max(bounds.start, t), bounds.end)
        if clamped < window.start { return pan(window, by: clamped - window.start, bounds: bounds) }
        if clamped > window.end { return pan(window, by: clamped - window.end, bounds: bounds) }
        return window
    }
}

/// Snap sloppy IN/OUT markers OUTWARD to whole sentences using the span
/// transcription's word timings + punctuation: IN moves EARLIER to the nearest
/// sentence start, OUT moves LATER to the nearest sentence end — a capture
/// never clips mid-sentence.
enum SentenceSnap {
    /// One sentence-snapped capture: times are relative to the transcribed
    /// audio; `words` is the exact slice the quote is built from.
    struct Snapped: Equatable, Sendable {
        var start: TimeInterval
        var end: TimeInterval
        var text: String
        var words: [WordTiming]
    }

    /// Closing punctuation that may trail a terminator (`he said.”`).
    private static let closers = Set<Character>("\"'”’)]»")
    private static let terminators = Set<Character>(".!?…")

    /// True when the word ends a sentence: its last character (after stripping
    /// trailing quotes/brackets) is `.` `!` `?` or `…`.
    static func isSentenceEnd(_ word: String) -> Bool {
        var rest = Substring(word)
        while let last = rest.last, closers.contains(last) { rest = rest.dropLast() }
        guard let last = rest.last else { return false }
        return terminators.contains(last)
    }

    /// Indices that BEGIN a sentence: the first word, plus every word following
    /// a sentence end. Always non-empty for non-empty input.
    static func sentenceStartIndices(_ words: [WordTiming]) -> [Int] {
        guard !words.isEmpty else { return [] }
        var starts = [0]
        for i in 1..<words.count where isSentenceEnd(words[i - 1].word) {
            starts.append(i)
        }
        return starts
    }

    /// Snap `[proposedIn → proposedOut]` outward to whole sentences.
    /// - IN lands on the latest sentence start at-or-before `proposedIn`
    ///   (falling back to the first word when the marker precedes everything).
    /// - OUT lands on the earliest sentence end at-or-after `proposedOut`
    ///   (falling back to the last word when the buffer ends mid-sentence).
    /// Returns nil for empty word timings (callers keep the raw span).
    static func snap(words: [WordTiming],
                     proposedIn: TimeInterval,
                     proposedOut: TimeInterval) -> Snapped? {
        guard !words.isEmpty else { return nil }

        let starts = sentenceStartIndices(words)
        let inIdx = starts.last(where: { words[$0].start <= proposedIn }) ?? starts[0]

        let ends = words.indices.filter { isSentenceEnd(words[$0].word) }
        let outIdx = ends.first(where: { $0 >= inIdx && words[$0].end >= proposedOut })
            ?? ends.last(where: { $0 >= inIdx })
            ?? (words.count - 1)

        let slice = Array(words[inIdx...max(inIdx, outIdx)])
        return Snapped(
            start: slice[0].start,
            end: slice[slice.count - 1].end,
            text: slice.map(\.word).joined(separator: " "),
            words: slice
        )
    }
}

/// C1 quote-block formatting: a capture memo's transcript is the quote as
/// markdown blockquote lines ("> " prefix) at the TOP; the ramble then appends
/// below via the existing append flow (`existing + "\n\n" + ramble`). The phone
/// writes NO `[[..]]` and NO attribution line — the Mac owns both at export.
enum QuoteFormatting {
    /// "Optimism is not…" → "> Optimism is not…" (per line; blank lines stay
    /// as bare ">"). Empty/whitespace input → "".
    static func blockquote(_ quote: String) -> String {
        let trimmed = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed
            .components(separatedBy: .newlines)
            .map { line in
                let l = line.trimmingCharacters(in: .whitespaces)
                return l.isEmpty ? ">" : "> " + l
            }
            .joined(separator: "\n")
    }

    /// Everything BELOW the leading C1 blockquote — the user's own recorded
    /// thoughts, shown on the capture sheet for review once a ramble lands
    /// (`[[img_NNN]]` markers stripped). Nil while the capture is quote-only.
    static func rambleBody(transcript: String) -> String? {
        let cleaned = transcript.replacingOccurrences(
            of: #"\[\[img_\d+\]\]"#, with: "", options: .regularExpression
        )
        var body: [String] = []
        var inQuoteHead = true
        for raw in cleaned.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if inQuoteHead {
                if line.isEmpty || line.hasPrefix(">") { continue }
                inQuoteHead = false
            }
            body.append(raw)
        }
        let joined = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    /// The attribution PREVIEW shown on the capture sheet — plain text, no
    /// wikilink ([[Author]] is written by the Mac at export only). Never part
    /// of the transcript. e.g. "— David Deutsch, The Beginning of Infinity, ch. 4".
    static func attributionPreview(author: String?, book: String?, chapter: String?) -> String {
        var parts: [String] = []
        if let author, !author.isEmpty { parts.append(author) }
        if let book, !book.isEmpty { parts.append(book) }
        if let chapter, !chapter.isEmpty { parts.append("ch. \(chapter)") }
        guard !parts.isEmpty else { return "" }
        return "— " + parts.joined(separator: ", ")
    }
}
