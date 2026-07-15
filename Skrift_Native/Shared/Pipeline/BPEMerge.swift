import Foundation

/// A whole word with timing, after merging BPE sub-word tokens. The transient
/// in-memory shape between the ASR engine and marker insertion / fusion — NOT
/// the `word_timings.json` element (that's the shared `WordTiming`, whose
/// `word` key is a wire contract; this one is never serialized).
struct TimedWord: Equatable, Sendable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

/// A raw ASR sub-word token, decoupled from FluidAudio's `TokenTiming` so the merge
/// is host-testable. Each app's engine maps FluidAudio tokens → these.
struct RawToken: Equatable, Sendable {
    let token: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}

/// Deterministic transcript post-processing — pure, host-testable, and SHARED:
/// both apps run the same Parakeet models, so token→word merging, the
/// rescored-text word alignment, and the phantom-transcript guard must behave
/// identically on phone and Mac (each previously carried its own copy — the
/// phone's lived inline in its TranscriptionService/VocabularyBooster).
enum BPEMerge {

    /// Custom-vocab rescore swaps whole words in the TEXT; the word timings
    /// (karaoke) must show the corrected words too. When the rescored text
    /// still has the same word count, swap strings positionally (times
    /// unchanged). nil = counts diverged — caller keeps the original words.
    static func alignWords(original: [String], rescoredText: String) -> [String]? {
        let rescored = rescoredText
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
        guard rescored.count == original.count else { return nil }
        return rescored
    }

    /// Merge BPE sub-word tokens into whole words. A token whose raw text starts
    /// with a space begins a new word; others continue the current one. Bit-for-bit
    /// the same as the RN-era merge and the backend word merge.
    static func mergeBPETokens(_ tokens: [RawToken]) -> [TimedWord] {
        var words: [TimedWord] = []
        var pending: (text: String, start: TimeInterval, end: TimeInterval)?

        for token in tokens {
            let raw = token.token
            if raw.isEmpty { continue }
            let isNewWord = raw.hasPrefix(" ") || pending == nil
            let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty { continue }
            let s = max(0.0, token.startTime)
            let e = max(s, token.endTime)

            if isNewWord {
                if let p = pending, !p.text.trimmingCharacters(in: .whitespaces).isEmpty {
                    words.append(TimedWord(text: p.text.trimmingCharacters(in: .whitespaces), start: p.start, end: p.end))
                }
                pending = (text: clean, start: s, end: e)
            } else {
                pending?.text.append(clean)
                pending?.end = e
            }
        }
        if let p = pending, !p.text.trimmingCharacters(in: .whitespaces).isEmpty {
            words.append(TimedWord(text: p.text.trimmingCharacters(in: .whitespaces), start: p.start, end: p.end))
        }
        return words
    }

    /// Phantom-transcript guard: TDT can hallucinate a short transcript on
    /// (near-)silent audio. Drop empty, or tiny-AND-low-energy — gated on a small
    /// word count so real speech is never dropped. Threshold device-tuned.
    static func shouldDropAsPhantom(rms: Float?, wordCount: Int, isEmpty: Bool) -> Bool {
        if isEmpty { return true }
        let lowEnergy = rms.map { $0 < 0.0075 } ?? false
        return lowEnergy && wordCount <= 3
    }

    /// The phantom guard with a LAZY energy source: RMS decodes the whole file and
    /// is only consulted for tiny transcripts, so pass a provider — a real
    /// transcript (every memo, import, book chunk) skips the extra decode pass.
    /// Folds the identical `trimmed`/`wordCount`/lazy-gate that each app's
    /// TranscriptionService used to inline (the drift surface behind `averageRMS`).
    static func shouldDropAsPhantom(text: String, rms: () -> Float?) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = trimmed.isEmpty
            ? 0
            : trimmed.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
        let value = (!trimmed.isEmpty && wordCount <= 3) ? rms() : nil
        return shouldDropAsPhantom(rms: value, wordCount: wordCount, isEmpty: trimmed.isEmpty)
    }
}
