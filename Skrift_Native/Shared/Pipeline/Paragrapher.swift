import Foundation

/// Turns a flat transcript into readable paragraphs — deterministic, no model.
///
/// Parakeet v3 already emits sentence punctuation, and we have per-word timings, so
/// a natural paragraph break is a **long pause that follows a finished sentence**
/// (a sentence-ending word + a silence ≥ `gapThreshold`). That groups sentences
/// into paragraphs at the speaker's real breaks, instead of one-line-per-sentence
/// or an undifferentiated wall of text.
///
/// SHARED (moved from the phone's Models/, 2026-07-28): the phone applies it in
/// `MemoSaver.runTranscription`, the Mac in `BatchRunner.run` — the SAME rule, so a note
/// paragraphs identically wherever it was transcribed (Tuur's ROUND 10: "on the phone I
/// have paragraph generation when I talk. Here I don't."). `LiveCaptionEngine` also leans
/// on `endsSentence` to place paragraph joins at pause-rotate boundaries mid-take.
///
/// `gapThreshold` is the knob to tune (the bigger it is, the fewer/longer the
/// paragraphs).
enum Paragrapher {
    /// Default break: a ≥0.65s silence after a sentence-ending word.
    static let defaultGap: TimeInterval = 0.65

    /// The Mac's long-form threshold — live joins (`LiveCaptionEngine.resolvedJoin`)
    /// AND the Mac file pass (`BatchRunner`), one constant so the draft and the
    /// resting note agree. Tuur's first real Mac takes (ROUND 11, 2026-07-28):
    /// thinking aloud pauses ~0.7–1.5 s at nearly every sentence, so `defaultGap`
    /// shredded the note into one-line paragraphs ("a lot of gaps in there"). On the
    /// Mac a paragraph needs a DELIBERATE stop, not a breath. The phone keeps
    /// `defaultGap` — its on-the-go dictation feel is confirmed good at 0.65.
    static let longFormGap: TimeInterval = 2.0

    /// Paragraph an EXISTING transcript STRING in place — preserving its exact words,
    /// punctuation, and `[[img_NNN]]` markers — using the per-word pause info. Only
    /// `\n\n` is inserted; every token is otherwise untouched, so karaoke (which is
    /// newline-aware) and the Mac contract are unaffected. Markers (and any tokens
    /// past `words`) pass through without a break decision. This is the variant the
    /// app stores (memo + export). Returns the trimmed text unchanged when there are
    /// no timings.
    static func paragraphed(transcript: String, words: [WordTiming],
                            gapThreshold: TimeInterval = defaultGap, maxSentences: Int = 4) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !words.isEmpty else { return trimmed }
        // Already-structured text passes through UNTOUCHED: an existing newline (speaker
        // turns, a live draft's own paragraph joins) is someone's deliberate structure, and
        // re-flowing the tokens here would destroy it (the Mac's DiarizationTests caught an
        // attributed conversation being flattened back into one line). Raw ASR output is
        // always flat, so the paragraphing path is unaffected.
        guard !trimmed.contains("\n") else { return trimmed }
        let tokens = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return trimmed }

        var paragraphs: [[String]] = [[]]
        var wordIndex = 0
        var sentencesInParagraph = 0
        var prevWord: WordTiming?
        var prevEndedSentence = false
        for token in tokens {
            let isMarker = token.hasPrefix("[[")    // image markers ([[img_NNN]])
            if !isMarker, wordIndex < words.count {
                let w = words[wordIndex]
                if prevEndedSentence, let prev = prevWord {
                    let longPause = (w.start - prev.end) >= gapThreshold
                    let capReached = maxSentences > 0 && sentencesInParagraph >= maxSentences
                    if longPause || capReached { paragraphs.append([]); sentencesInParagraph = 0 }
                }
                paragraphs[paragraphs.count - 1].append(token)
                prevWord = w
                wordIndex += 1
                prevEndedSentence = endsSentence(token)
                if prevEndedSentence { sentencesInParagraph += 1 }
            } else {
                paragraphs[paragraphs.count - 1].append(token)   // marker / overflow: pass through
            }
        }
        return paragraphs
            .map { $0.joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// True if `word` ends a sentence — last non-quote/paren character is `. ? !`.
    static func endsSentence(_ word: String) -> Bool {
        let closers: Set<Character> = ["\"", "”", "'", "’", ")", "]", "»"]
        guard let last = word.reversed().first(where: { !closers.contains($0) }) else { return false }
        return last == "." || last == "?" || last == "!"
    }
}
