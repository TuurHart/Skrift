import Foundation
import NaturalLanguage

// Pure math for the audiobook quote-capture flow (no AVFoundation, no UI) —
// the transcription buffer, sentence-snapping, and the C1 quote-block formatting.
// Everything here is host-less unit-tested (`AudiobookCaptureMathTests`).

/// The capture span: the audio range a quote capture covers, plus the padding
/// transcribed around it.
enum CaptureSpan {
    /// Extra audio transcribed on each side of the marked span so the
    /// sentence-snap has material to snap OUTWARD into.
    static let transcriptionPadding: TimeInterval = 20

    struct Span: Equatable, Sendable {
        var start: TimeInterval
        var end: TimeInterval
        var length: TimeInterval { max(0, end - start) }
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

    /// Indices that BEGIN a sentence. Uses `NLTokenizer(.sentence)` over the
    /// reconstructed text — it respects abbreviations ("Mr."), decimals ("3.14"),
    /// ellipses and quotes, where the old trailing-terminator match split mid-sentence
    /// (the "sentences break in weird spots" report). On CLEAN sentence ends NLTokenizer
    /// agrees with the punctuation rule, so seam-cutting + capture-snap behaviour is
    /// unchanged there. Always non-empty for non-empty input (index 0 is always a start).
    static func sentenceStartIndices(_ words: [WordTiming]) -> [Int] {
        guard !words.isEmpty else { return [] }
        // Reconstruct the spoken text + each word's UTF-16 offset (matches NLTokenizer's
        // NSRange coordinates).
        var text = ""
        var wordCharStart: [Int] = []
        for (i, w) in words.enumerated() {
            if i > 0 { text += " " }
            wordCharStart.append((text as NSString).length)
            text += w.word
        }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var starts: Set<Int> = [0]
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let off = NSRange(range, in: text).location
            // The sentence begins at the first word at/after its char offset.
            if let idx = wordCharStart.firstIndex(where: { $0 >= off }) { starts.insert(idx) }
            return true
        }
        return starts.sorted()
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
}
