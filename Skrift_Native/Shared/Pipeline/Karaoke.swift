import Foundation

/// Karaoke / read-along highlight math — pure, host-tested, and SHARED. The phone
/// and Mac each drove read-along with a DIFFERENT function (the phone a simple
/// active-word lookup over raw timings; the Mac a displayed-word→time alignment
/// that survives copy-edit / name-linking / header word-count changes). They were
/// never duplicated code, but they belong in ONE home so the read-along math has a
/// single source of truth. `WordTiming` is the shared wire-contract struct
/// (Shared/Model/WordTiming.swift).
enum Karaoke {

    // MARK: - Active-word lookup (phone read-along / capture-quote highlight)

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

    // MARK: - Displayed-word alignment (Mac review-body read-along)

    /// One playback time (seconds) per displayed word, monotonic non-decreasing.
    /// Content words (≥4 chars) that match a timed word IN ORDER become anchors with
    /// their real start time; everything else (short words, rephrasings, headers,
    /// `[[img]]` markers) is interpolated by position between anchors. Exact when the
    /// body equals the transcript; graceful under heavy edits. Empty when there are no
    /// words/timings — the caller then falls back to a pure time proportion.
    /// CONSOLIDATED into `AlignmentCore` (2026-07-27) — the fold this file's sibling
    /// always planned ("the consolidation point, not a fourth copy … the conductor folds
    /// them together later"). One aligner now serves both read-alongs: the book's and
    /// the note's.
    ///
    /// What changed, and why it's more accurate: the old local pass anchored only on
    /// words ≥4 characters and LINEARLY REDISTRIBUTED everything between anchors — the
    /// exact move the ePub round proved wrong when the highlight trailed the narrator by
    /// seconds across natural pauses. `AlignmentCore` matches short words too (uniqueness,
    /// not length, is what makes an anchor safe) and carries EXACT per-word times.
    /// Concretely, on the copy-edit fixture the old code put "the" at 0.0 — which is when
    /// "um" was spoken — because "the" is 3 characters and got interpolated back to the
    /// start. It is really spoken at 1.0, and that is what this returns now.
    ///
    /// `anchorN: 1`, not the ePub default of 4: a displayed body is a *subsequence* of
    /// the spoken words (copy-edit deletes fillers mid-phrase), so contiguous 4-grams
    /// mostly don't survive — at n=4 the aligner REJECTS an ordinary edited note outright
    /// (measured). Single-word anchors are safe here because `AlignmentCore` only anchors
    /// n-grams unique on BOTH sides, so a repeated word is never an anchor.
    ///
    /// Returns `[]` when the two don't align at all (`verdict == .rejected`) — the caller
    /// then falls back to a pure time proportion. That is a capability the old pass never
    /// had: it always produced *something*, so a body that didn't match its audio was
    /// highlighted confidently and wrongly.
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
        guard out.contains(where: { $0 != nil }) else { return [] }

        // Fill what the aligner left untimed — non-spoken tokens like a `**Name:**` turn
        // header, which consume no audio. Carry the previous time forward (and backfill a
        // leading run from the first known time), so a header sits with the word it
        // introduces and the sequence stays monotonic non-decreasing, which is the whole
        // contract `activeCount` counts against.
        let firstKnown = out.compactMap { $0 }.first ?? timings[0].start
        var last = firstKnown
        for i in out.indices {
            if let t = out[i] { last = t } else { out[i] = last }
        }
        return out.map { $0 ?? firstKnown }
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

    /// Normalize a token for matching: lowercase, drop `[[ ]]` wiki brackets + the
    /// alias-display `|display` (keep the SHOWN half — that's what was rendered),
    /// markdown `**`, and punctuation edges. So `[[Tiuri Hartog|Tuur]]` → `tuur` and
    /// `**Roksana:**` → `roksana`.
    static func normalize(_ w: String) -> String {
        var s = w.lowercased()
        s = s.replacingOccurrences(of: "[[", with: "").replacingOccurrences(of: "]]", with: "")
        if let pipe = s.lastIndex(of: "|") { s = String(s[s.index(after: pipe)...]) }
        s = s.replacingOccurrences(of: "**", with: "")
        return s.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }
}
