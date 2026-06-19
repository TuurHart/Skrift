import Foundation

/// Turns a flat transcript into readable paragraphs — deterministic, no model.
///
/// Parakeet v3 already emits sentence punctuation, and we have per-word timings, so
/// a natural paragraph break is a **long pause that follows a finished sentence**
/// (a sentence-ending word + a silence ≥ `gapThreshold`). That groups sentences
/// into paragraphs at the speaker's real breaks, instead of one-line-per-sentence
/// or an undifferentiated wall of text.
///
/// `gapThreshold` is the knob to tune (the bigger it is, the fewer/longer the
/// paragraphs). A text-only fallback groups by sentence count when no timings are
/// available.
enum Paragrapher {
    /// Default break: a ≥0.65s silence after a sentence-ending word. (Tunable; the
    /// `-paragraph` desktop harness sweeps 0.5/0.7/1.0s on real audio.)
    static let defaultGap: TimeInterval = 0.65

    /// Hybrid paragraphing (the default — robust for both steady audiobook narration
    /// and natural-pause voice memos). A new paragraph starts before word *i* when
    /// the previous word ended a sentence (`. ? !`, tolerating a trailing quote) AND
    /// **either** the silence before *i* is ≥ `gapThreshold` (a real structural pause)
    /// **or** the current paragraph already holds `maxSentences` (so densely-read
    /// audiobooks, which barely pause between sentences, still break into paragraphs).
    /// Words rejoin with single spaces (Parakeet's own join) — text otherwise unchanged.
    ///
    /// Tuning seen on a real chapter: pause-only under-segments steady narration (one
    /// giant block); the sentence cap is what gives audiobooks regular paragraphs.
    static func paragraphed(words: [WordTiming],
                            gapThreshold: TimeInterval = defaultGap,
                            maxSentences: Int = 4) -> String {
        guard !words.isEmpty else { return "" }
        var paragraphs: [[String]] = [[]]
        var sentencesInParagraph = 0
        for (i, w) in words.enumerated() {
            if i > 0, endsSentence(words[i - 1].word) {
                let gap = w.start - words[i - 1].end
                let longPause = gap >= gapThreshold
                let capReached = maxSentences > 0 && sentencesInParagraph >= maxSentences
                if longPause || capReached {
                    paragraphs.append([])
                    sentencesInParagraph = 0
                }
            }
            paragraphs[paragraphs.count - 1].append(w.word)
            if endsSentence(w.word) { sentencesInParagraph += 1 }
        }
        return paragraphs
            .map { $0.joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

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

    /// Text-only fallback (no timings): split into sentences and group every
    /// `sentencesPerParagraph`. Used when a transcript has no word timings.
    static func paragraphed(text: String, sentencesPerParagraph: Int = 4) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, sentencesPerParagraph > 0 else { return trimmed }
        let sentences = splitSentences(trimmed)
        guard sentences.count > sentencesPerParagraph else { return trimmed }
        var paragraphs: [String] = []
        var i = 0
        while i < sentences.count {
            let slice = sentences[i..<min(i + sentencesPerParagraph, sentences.count)]
            paragraphs.append(slice.joined(separator: " "))
            i += sentencesPerParagraph
        }
        return paragraphs.joined(separator: "\n\n")
    }

    /// True if `word` ends a sentence — last non-quote/paren character is `. ? !`.
    static func endsSentence(_ word: String) -> Bool {
        let closers: Set<Character> = ["\"", "”", "'", "’", ")", "]", "»"]
        guard let last = word.reversed().first(where: { !closers.contains($0) }) else { return false }
        return last == "." || last == "?" || last == "!"
    }

    private static func splitSentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: true).map(String.init) {
            current += current.isEmpty ? word : " " + word
            if endsSentence(word) { out.append(current); current = "" }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
