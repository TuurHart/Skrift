import Foundation
import NaturalLanguage

// Pure math for the audiobook quote-capture flow (no AVFoundation, no UI) —
// sentence start indices and the C1 quote-block formatting.
// Everything here is host-less unit-tested (`AudiobookCaptureMathTests`).

/// The capture span: the audio range a quote capture covers.
enum CaptureSpan {
    struct Span: Equatable, Sendable {
        var start: TimeInterval
        var end: TimeInterval
        var length: TimeInterval { max(0, end - start) }
    }
}

/// Sentence boundaries over word timings.
enum SentenceSnap {
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
