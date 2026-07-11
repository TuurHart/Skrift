import Foundation

/// Deterministic hesitation strip for VOICE MEMOS — opt-in (Settings →
/// Transcription), OFF by default. Drops standalone filler tokens from the
/// transcript AND the karaoke word-timings in lockstep, so display, export,
/// and read-along stay aligned. The Mac contract survives untouched: its
/// copy-edit prompt deletes the same fillers anyway, and name-linking can't
/// care about a dropped "um".
///
/// Scope rules (hard):
/// - Voice memos / imports only — NEVER audiobook quote captures (verbatim
///   book text) and never the live caption (display-only, raw).
/// - The stoplist stays tiny and unambiguous. Anything that is also a real
///   word in English or Dutch ("er", "so", "like", "ah") stays out — real
///   disfluency cleanup is the enhancement LLM's job, not ours.
enum FillerFilter {
    /// @AppStorage key for the Settings toggle (default false = off).
    static let settingKey = "stripFillerWords"

    /// Standalone hesitations, EN/NL shared. Matched against the lowercased,
    /// punctuation-stripped token only.
    static let fillers: Set<String> = [
        "um", "umm", "uh", "uhh", "uhm", "mm", "mmm", "hmm", "hm", "ehm", "eh", "erm",
    ]

    struct Output: Equatable {
        var text: String
        var words: [WordTiming]
        var removedCount: Int
    }

    /// Strip fillers from a transcript + its word timings (positionally
    /// paired, `[[img_NNN]]` marker tokens pass through consuming no timing —
    /// the same walk as `Paragrapher.paragraphed(transcript:words:)`). When a
    /// dropped filler carried the sentence terminator ("we stop hmm. Then"),
    /// the punctuation transfers to the previous kept word so the sentence
    /// still ends. Returns the input unchanged when nothing matched or when
    /// stripping would empty the transcript.
    static func strip(transcript: String, words: [WordTiming]) -> Output {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let unchanged = Output(text: trimmed, words: words, removedCount: 0)
        guard !trimmed.isEmpty, !words.isEmpty else { return unchanged }
        let tokens = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        var outTokens: [String] = []
        var outWords: [WordTiming] = []
        var wordIndex = 0
        var removed = 0
        for token in tokens {
            let isMarker = token.hasPrefix("[[")
            guard !isMarker, wordIndex < words.count else {
                outTokens.append(token)   // marker / overflow: pass through
                continue
            }
            let timing = words[wordIndex]
            wordIndex += 1
            guard fillers.contains(core(token)) else {
                outTokens.append(token)
                outWords.append(timing)
                continue
            }
            removed += 1
            // Keep the sentence terminator the filler carried.
            if Paragrapher.endsSentence(token),
               let lastToken = outTokens.last, !lastToken.hasPrefix("[["),
               !Paragrapher.endsSentence(lastToken),
               let lastWord = outWords.last {
                let punct = trailingPunctuation(of: token)
                outTokens[outTokens.count - 1] = lastToken + punct
                outWords[outWords.count - 1] = WordTiming(
                    word: lastWord.word + punct, start: lastWord.start, end: lastWord.end)
            }
        }
        guard removed > 0 else { return unchanged }
        // A transcript of ONLY fillers stays as-is — "Hmm." is a (tiny) memo,
        // an empty transcript reads as a failed one.
        guard outTokens.contains(where: { !$0.hasPrefix("[[") }) else { return unchanged }
        return Output(text: outTokens.joined(separator: " "),
                      words: outWords, removedCount: removed)
    }

    /// Lowercased token with edge punctuation stripped ("Um," → "um").
    private static func core(_ token: String) -> String {
        token.trimmingCharacters(in: .alphanumerics.inverted).lowercased()
    }

    /// The token's trailing non-alphanumeric cluster ("hmm.)" → ".)").
    private static func trailingPunctuation(of token: String) -> String {
        String(token.reversed().prefix(while: { !$0.isLetter && !$0.isNumber }).reversed())
    }
}
