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
        let dur = max(0, duration)
        var end = min(dur, max(0, now))
        let start = max(0, end - lookback)
        if end - start < minimumSpan {
            end = min(dur, start + minimumSpan)
        }
        return Span(start: start, end: end)
    }

    /// The micro-scrubber's visible window around the pause point, clamped to
    /// the file. Always contains the proposal for the same `now`.
    static func window(now: TimeInterval, duration: TimeInterval) -> Span {
        let dur = max(0, duration)
        let anchor = min(dur, max(0, now))
        let start = max(0, anchor - windowLookback)
        let end = min(dur, anchor + windowLookahead)
        return Span(start: start, end: max(end, start))
    }

    /// The span actually sent through the transcriber: the marked span ± the
    /// padding, clamped — never the whole book.
    static func transcriptionBuffer(for span: Span, duration: TimeInterval) -> Span {
        Span(start: max(0, span.start - transcriptionPadding),
             end: min(max(0, duration), span.end + transcriptionPadding))
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
