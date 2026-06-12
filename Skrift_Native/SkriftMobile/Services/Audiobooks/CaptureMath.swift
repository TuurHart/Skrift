import Foundation

// Pure math for the audiobook quote-capture flow (no AVFoundation, no UI) —
// span proposal/clamping, sentence-snapping, and the C1 quote-block formatting.
// Everything here is host-less unit-tested (`AudiobookCaptureMathTests`).

/// The retroactive capture span: Capture pauses the book and proposes
/// [now − 30 s → now]; the Hybrid adjust screen opens auto-playing from
/// [now − 45 s] at 1.5×. All values clamp to the current chapter-file's bounds.
enum CaptureSpan {
    /// How far back the proposed span reaches from the pause point.
    static let lookback: TimeInterval = 30
    /// How far back the Hybrid adjust screen begins its auto-replay from the
    /// pause point (the initial strip window).
    static let replayLookback: TimeInterval = 45
    /// Step by which the strip window is extended further back when the user
    /// skips ⟲5 past the left edge. Repeated taps push the window back by this
    /// amount each time, clamped to the chapter file's start.
    static let windowExtensionStep: TimeInterval = 45
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
    /// 0 a minimal forward span is proposed so the strip has a region.
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

    /// The initial strip window for the Hybrid screen: [pausePoint − 45 s →
    /// pausePoint], clamped to the file. The right edge is fixed at the pause
    /// point; the user extends the left edge by skipping ⟲5 past it.
    static func replayWindow(now: TimeInterval, in bounds: Span) -> Span {
        let anchor = min(bounds.end, max(bounds.start, now))
        let start = max(bounds.start, anchor - replayLookback)
        return Span(start: start, end: anchor)
    }

    /// The span actually sent through the transcriber: the marked span ± the
    /// padding, clamped — never the whole book.
    static func transcriptionBuffer(for span: Span, duration: TimeInterval) -> Span {
        Span(start: max(0, span.start - transcriptionPadding),
             end: min(max(0, duration), span.end + transcriptionPadding))
    }
}

/// Pure math for the Hybrid capture adjust screen (signed off 2026-06-12):
/// mark placement with reaction bias, ±1s chip nudging, window extension, and
/// the strip's x↔time mapping. No draggable handles — IN/OUT flags drop at the
/// playhead. Everything here is host-less unit-tested in `AudiobookCaptureMathTests`.
enum CaptureMath {
    /// IN and OUT can never get closer than this (seconds).
    static let minimumSpan: TimeInterval = 1
    /// Reaction bias subtracted from the playhead time when a Mark button is
    /// tapped WHILE the audio is playing. Zero while paused.
    static let reactionBias: TimeInterval = 0.7
    /// How far before the new out-mark to begin the "last stretch" preview
    /// triggered by tapping an OUT chip (≈ 5 s tail).
    static let outChipTailLength: TimeInterval = 5.0

    // MARK: - Mark placement

    /// Place the IN mark at `playheadTime`, with a −0.7 s bias while playing.
    /// Result is clamped to `[bounds.start, bounds.end]`.
    static func placeInMark(
        playheadTime: TimeInterval,
        isPlaying: Bool,
        bounds: CaptureSpan.Span
    ) -> TimeInterval {
        let bias = isPlaying ? reactionBias : 0
        return max(bounds.start, min(bounds.end, playheadTime - bias))
    }

    /// Place the OUT mark at `playheadTime`, with a −0.7 s bias while playing.
    /// Result is clamped to `[bounds.start, bounds.end]` and enforces
    /// OUT ≥ inMark + minimumSpan when `inMark` is provided.
    static func placeOutMark(
        playheadTime: TimeInterval,
        isPlaying: Bool,
        inMark: TimeInterval?,
        bounds: CaptureSpan.Span
    ) -> TimeInterval {
        let bias = isPlaying ? reactionBias : 0
        let clamped = max(bounds.start, min(bounds.end, playheadTime - bias))
        if let inMark {
            return max(clamped, inMark + minimumSpan)
        }
        return clamped
    }

    // MARK: - ±1s chip nudging

    /// Nudge the IN mark by `delta` seconds (should be ±1).
    /// Clamps to `[bounds.start, outMark − minimumSpan]`.
    static func nudgeInMark(
        current: TimeInterval,
        delta: TimeInterval,
        outMark: TimeInterval?,
        bounds: CaptureSpan.Span
    ) -> TimeInterval {
        let maxIn = outMark.map { $0 - minimumSpan } ?? bounds.end
        return max(bounds.start, min(maxIn, current + delta))
    }

    /// Nudge the OUT mark by `delta` seconds (should be ±1).
    /// Clamps to `[inMark + minimumSpan, bounds.end]`.
    static func nudgeOutMark(
        current: TimeInterval,
        delta: TimeInterval,
        inMark: TimeInterval?,
        bounds: CaptureSpan.Span
    ) -> TimeInterval {
        let minOut = inMark.map { $0 + minimumSpan } ?? bounds.start
        return max(minOut, min(bounds.end, current + delta))
    }

    // MARK: - Seek targets after chip taps

    /// Where to seek when an IN chip is tapped: at the new in-mark itself.
    /// Playback then resumes from there so the user hears the exact new start.
    static func inChipSeekTarget(newInMark: TimeInterval) -> TimeInterval {
        newInMark
    }

    /// Where to seek when an OUT chip is tapped: `outChipTailLength` seconds
    /// before the new out-mark so the user hears the last stretch up to the new
    /// boundary. Clamped to be ≥ inMark (when set).
    static func outChipSeekTarget(newOutMark: TimeInterval, inMark: TimeInterval?) -> TimeInterval {
        let earliest = inMark ?? 0
        return max(earliest, newOutMark - outChipTailLength)
    }

    // MARK: - Window extension (⟲5 past the left edge)

    /// Extend the strip window further back by `step` seconds. The right edge
    /// (pause point) is unchanged; the new left edge is
    /// `max(bounds.start, window.start − step)`.
    static func extendWindowLeft(
        window: CaptureSpan.Span,
        step: TimeInterval = CaptureSpan.windowExtensionStep,
        bounds: CaptureSpan.Span
    ) -> CaptureSpan.Span {
        let newStart = max(bounds.start, window.start - step)
        return CaptureSpan.Span(start: newStart, end: window.end)
    }

    // MARK: - Strip x ↔ time mapping

    /// Map a tap x in strip coordinates to time on the window.
    /// Unclamped — values past the strip edges continue to map past the window.
    static func time(atX x: Double, stripWidth: Double, window: CaptureSpan.Span) -> TimeInterval {
        guard stripWidth > 0 else { return window.start }
        return window.start + (x / stripWidth) * window.length
    }

    /// Map a time to its x position in strip coordinates (unclamped).
    static func xPosition(of t: TimeInterval, stripWidth: Double, window: CaptureSpan.Span) -> Double {
        guard window.length > 0 else { return 0 }
        return stripWidth * (t - window.start) / window.length
    }

    // MARK: - ⟲5 / 5⟳ skip handling

    /// Apply a ⟲5 or 5⟳ skip (negative delta = backward). Returns the new
    /// playhead time and whether the strip window should be extended left
    /// (because the skip would push the playhead before the window start).
    static func applySkip(
        playheadTime: TimeInterval,
        delta: TimeInterval,
        window: CaptureSpan.Span,
        bounds: CaptureSpan.Span
    ) -> (newTime: TimeInterval, extendWindow: Bool) {
        let proposed = playheadTime + delta
        if delta < 0, proposed < window.start {
            // Past the left edge → signal a window extension and pin at the
            // current window start (the extension will re-anchor the strip).
            return (window.start, true)
        }
        return (max(bounds.start, min(bounds.end, proposed)), false)
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

    /// Closing punctuation that may trail a terminator (`he said."`).
    // " ' ” ’ ) ] » — typographic quotes via escapes so the literal can't be
    // mis-terminated by its own contents.
    private static let closers = Set<Character>("\"'\u{201D}\u{2019})]»")
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

    /// How far before a sentence start the IN mark may still snap FORWARD to
    /// it: the reaction-bias overshoot lands ≤ this far before the next
    /// sentence start when the user marks just after the sentence ended.
    static let inForwardSnapThreshold: TimeInterval = 1.0

    /// Nearest-boundary snap for the IN edge.
    ///
    /// The −0.7 s reaction bias often drops the mark in the tail of the
    /// PREVIOUS sentence — one sentence earlier than the user intended. The
    /// nearest-boundary rule resolves this:
    ///
    /// - If `proposedIn` lands within `inForwardSnapThreshold` seconds BEFORE
    ///   a sentence start, snap FORWARD to that sentence start.
    /// - Otherwise snap BACKWARD to the latest sentence start ≤ proposedIn
    ///   (the original outward behaviour — captures mid-sentence are expected).
    /// - Both paths fall back to `starts[0]` when the mark precedes all words.
    static func inIndex(starts: [Int], words: [WordTiming], proposedIn: TimeInterval) -> Int {
        // The backward (outward) candidate: latest sentence start ≤ the mark.
        let backIdx = starts.last(where: { words[$0].start <= proposedIn }) ?? starts[0]
        // Forward candidate: earliest sentence start ahead of the mark within
        // the overshoot window.
        if let forwardIdx = starts.first(where: { words[$0].start > proposedIn
                                                   && words[$0].start - proposedIn <= inForwardSnapThreshold }) {
            // Snap forward ONLY when the mark sits in the TAIL of its sentence —
            // closer to the next boundary than to its own start. The absolute
            // threshold alone misfires on short sentences (a mark 0.1s into a
            // 0.9s sentence is "within 1s of the next start", but the user
            // plainly meant THIS sentence).
            let intoCurrent = proposedIn - words[backIdx].start
            let toNext = words[forwardIdx].start - proposedIn
            if toNext < intoCurrent { return forwardIdx }
        }
        // Genuine mid-sentence or exact-boundary → snap backward (outward).
        return backIdx
    }

    /// Snap `[proposedIn → proposedOut]` outward to whole sentences.
    ///
    /// IN edge: nearest-boundary (see `inIndex`) — forward if the mark is in
    /// the overshoot zone before the next sentence, backward otherwise.
    /// OUT edge: earliest sentence end at-or-after `proposedOut` (unchanged).
    ///
    /// Returns nil for empty word timings (callers keep the raw span).
    static func snap(words: [WordTiming],
                     proposedIn: TimeInterval,
                     proposedOut: TimeInterval) -> Snapped? {
        guard !words.isEmpty else { return nil }

        let starts = sentenceStartIndices(words)
        let inIdx = inIndex(starts: starts, words: words, proposedIn: proposedIn)

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

// MARK: - Legacy CaptureScrub (binary-compatible shim — kept so the old
// scrubber tests still compile; remove with the next full test-rewrite pass).

enum CaptureScrub {
    static let minimumSpan: TimeInterval = 1

    enum Handle: Equatable, Sendable { case inMarker, outMarker }

    struct Latch: Equatable, Sendable {
        private(set) var active: Handle?

        mutating func claim(_ handle: Handle) -> Bool {
            if active == nil { active = handle }
            return active == handle
        }

        mutating func release(_ handle: Handle) {
            if active == handle { active = nil }
        }
    }

    static func time(atX x: Double, stripWidth: Double, window: CaptureSpan.Span) -> TimeInterval {
        CaptureMath.time(atX: x, stripWidth: stripWidth, window: window)
    }

    static func dragged(
        _ span: CaptureSpan.Span,
        handle: Handle,
        to raw: TimeInterval,
        bounds: CaptureSpan.Span
    ) -> CaptureSpan.Span {
        var s = span
        switch handle {
        case .inMarker:
            s.start = min(max(bounds.start, raw), max(bounds.start, span.end - minimumSpan))
        case .outMarker:
            s.end = max(min(bounds.end, raw), min(bounds.end, span.start + minimumSpan))
        }
        return s
    }

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

    static func pan(
        _ window: CaptureSpan.Span,
        by delta: TimeInterval,
        bounds: CaptureSpan.Span
    ) -> CaptureSpan.Span {
        let length = min(window.length, bounds.length)
        let start = min(max(bounds.start, window.start + delta), bounds.end - length)
        return CaptureSpan.Span(start: start, end: start + length)
    }

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
