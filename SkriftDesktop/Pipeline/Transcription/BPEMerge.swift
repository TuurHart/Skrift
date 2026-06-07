import Foundation

/// A whole word with timing, after merging BPE sub-word tokens.
struct TimedWord: Equatable, Sendable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

/// A raw ASR sub-word token, decoupled from FluidAudio's `TokenTiming` so the merge
/// is host-testable. The engine maps FluidAudio tokens → these.
struct RawToken: Equatable, Sendable {
    let token: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}

/// Deterministic transcript post-processing — pure, host-testable. The
/// FluidAudio-coupled engine feeds it `RawToken`s and an RMS reading.
enum BPEMerge {

    /// Merge BPE sub-word tokens into whole words. A token whose raw text starts
    /// with a space begins a new word; others continue the current one. Bit-for-bit
    /// the same as the phone's `mergeBPETokens` and the backend word merge.
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
    /// word count so real speech is never dropped. Threshold from the phone (device-tuned).
    static func shouldDropAsPhantom(rms: Float?, wordCount: Int, isEmpty: Bool) -> Bool {
        if isEmpty { return true }
        let lowEnergy = rms.map { $0 < 0.0075 } ?? false
        return lowEnergy && wordCount <= 3
    }
}
