import Foundation

/// Karaoke / read-along highlight math — pure, host-tested, and SHARED. `KaraokeTrack`
/// is the one rule both apps use to answer "which word is playing"; it builds on
/// `wordTimes` (displayed-word → time alignment that survives copy-edit / name-linking /
/// header word-count changes) and `activeCount`. `WordTiming` is the shared wire-contract
/// struct (Shared/Model/WordTiming.swift).
enum Karaoke {

    // MARK: - Active-word lookup over raw timings (no production caller; pinned by tests)

    /// Index of the word being spoken at `time` — the last word whose `start` is at
    /// or before `time`. nil before the first word starts (no highlight yet).
    /// `timings` must be in start order.
    static func activeWordIndex(_ timings: [WordTiming], at time: TimeInterval) -> Int? {
        guard let first = timings.first, time >= first.start else { return nil }
        var idx = 0
        for (i, t) in timings.enumerated() {
            if t.start <= time { idx = i } else { break }
        }
        return idx
    }

    /// Cursor-resuming variant for per-tick callers (the 20Hz playback clock):
    /// pass the previous result as `hint` — playback advances monotonically, so
    /// the scan resumes at the current word instead of index 0 every tick.
    /// A backward seek (or invalid hint) falls back to the full scan.
    static func activeWordIndex(_ timings: [WordTiming], at time: TimeInterval, hint: Int?) -> Int? {
        guard let hint, hint >= 0, hint < timings.count, timings[hint].start <= time else {
            return activeWordIndex(timings, at: time)
        }
        var idx = hint
        var i = hint + 1
        while i < timings.count, timings[i].start <= time { idx = i; i += 1 }
        return idx
    }

    // MARK: - Displayed-word alignment (review-body read-along, both apps)

    /// One playback time (seconds) per displayed word, monotonic non-decreasing, from
    /// `AlignmentCore` (the one aligner behind both the book's and the note's read-along).
    /// Words the aligner matched carry their real spoken start; untimed ones (non-spoken
    /// tokens like a `**Name:**` turn header) take the previous time, a leading run the
    /// first known time. Short words anchor too: uniqueness on both sides, not length,
    /// makes an anchor safe, so "the" lands where it is spoken, not interpolated.
    ///
    /// `anchorN: 1`, not the ePub default of 4: a displayed body is a *subsequence* of the
    /// spoken words (copy-edit deletes fillers mid-phrase), so contiguous 4-grams mostly
    /// don't survive and the aligner would reject an ordinary edited note outright.
    /// Single-word anchors are safe because only n-grams unique on BOTH sides anchor.
    ///
    /// Returns `[]` when there are no words/timings or the two don't align at all
    /// (`verdict == .rejected`); the caller then falls back to a pure time proportion
    /// rather than highlighting a body that doesn't match its audio.
    static func wordTimes(displayedWords: [String], timings: [WordTiming]) -> [Double] {
        guard !displayedWords.isEmpty, !timings.isEmpty else { return [] }

        var config = AlignmentCore.Config()
        config.anchorN = 1
        let result = AlignmentCore.align(
            transcript: timings.map { AlignmentCore.Word(text: $0.word, start: $0.start, end: $0.end) },
            // ONE block. Index parity with `displayedWords` is guaranteed: `AlignmentCore`
            // tokenizes a block with the identical whitespace split and keeps every token,
            // so its book-word i IS our displayed word i.
            book: [AlignmentCore.Block(text: displayedWords.joined(separator: " "), sourceFile: "note")],
            config: config)
        guard result.verdict != .rejected else { return [] }

        var out = [Double?](repeating: nil, count: displayedWords.count)
        for range in result.matchedRanges {
            for (offset, wt) in range.wordTimes.enumerated() {
                let i = range.bookWordStart + offset
                if i >= 0, i < out.count { out[i] = wt.start }
            }
        }
        guard let firstKnown = out.lazy.compactMap({ $0 }).first else { return [] }

        // Fill what the aligner left untimed (see above); keeps the sequence monotonic
        // non-decreasing, which is the whole contract `activeCount` counts against.
        var last = firstKnown
        return out.map { t in
            if let t { last = t }
            return last
        }
    }

    // MARK: - Tap-a-word → seek (voice notes, audiobook quote captures; both apps)

    /// The playback time a tap on sidecar word `index` seeks to: that word's real start.
    /// nil when there is no such timed word (empty/partial sidecar) — the caller does nothing.
    /// The phone's voice-note tap, its quote-block tap and its speaker-turn tap all land here.
    static func seekTime(forWord index: Int, in timings: [WordTiming]) -> TimeInterval? {
        guard index >= 0, index < timings.count else { return nil }
        return timings[index].start
    }

    /// The Mac's click-a-word target. `wordIndex` is the clicked word's MODEL index in the
    /// displayed body; `times` is `wordTimes` over that same body (the aligned time of the
    /// SHOWN word, so copy-edit / name-linking / `> ` markers don't skew it). Falls back to
    /// the raw index, then to a proportion of `duration` when there are no timings at all.
    /// Clamped into `0...duration`.
    static func seekTarget(wordIndex: Int, times: [Double], timings: [WordTiming],
                           duration: Double) -> Double {
        let target: Double
        if wordIndex >= 0, wordIndex < times.count {
            target = times[wordIndex]
        } else if wordIndex >= 0, wordIndex < timings.count {
            target = timings[wordIndex].start
        } else if timings.count > 1 {
            target = duration * Double(wordIndex) / Double(timings.count - 1)
        } else {
            target = 0
        }
        return max(0, min(target, duration))
    }

    /// How many displayed words have STARTED by `currentTime` — the karaoke highlight
    /// count. `times` from `wordTimes`.
    static func activeCount(times: [Double], currentTime: Double) -> Int {
        times.reduce(0) { $0 + ($1 <= currentTime ? 1 : 0) }
    }
}
