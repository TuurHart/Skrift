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
    static func wordTimes(displayedWords: [String], timings: [WordTiming]) -> [Double] {
        guard !displayedWords.isEmpty, !timings.isEmpty else { return [] }
        let dn = displayedWords.map(normalize)
        let tn = timings.map { normalize($0.word) }

        // 1. Greedy in-order anchors on content words. Short/common words (≤3 chars)
        //    mis-sync a coincidental match, so they're interpolated, not anchored.
        var aIdx: [Int] = []          // indices into displayedWords
        var aTime: [Double] = []      // the matched timed word's start
        var t = 0
        for i in 0..<dn.count where dn[i].count >= 4 {
            var j = t
            while j < tn.count, tn[j] != dn[i] { j += 1 }
            if j < tn.count { aIdx.append(i); aTime.append(timings[j].start); t = j + 1 }
        }

        var out = [Double](repeating: 0, count: displayedWords.count)
        let firstT = timings.first!.start
        let lastT = max(firstT, timings.last!.start)
        guard let a0 = aIdx.first else {
            // No content-word anchors matched — degrade to index-proportional (still
            // better than nothing; identical to the pre-C3 behavior in spirit).
            let n = max(1, out.count - 1)
            for i in 0..<out.count { out[i] = firstT + (lastT - firstT) * Double(i) / Double(n) }
            return out
        }
        // Before the first anchor.
        for i in 0..<a0 { out[i] = firstT + (aTime[0] - firstT) * Double(i) / Double(max(1, a0)) }
        out[a0] = aTime[0]
        // Between consecutive anchors (linear by word index).
        for k in 0..<(aIdx.count - 1) {
            let i0 = aIdx[k], i1 = aIdx[k + 1], t0 = aTime[k], t1 = aTime[k + 1]
            for i in (i0 + 1)...i1 { out[i] = t0 + (t1 - t0) * Double(i - i0) / Double(i1 - i0) }
        }
        // After the last anchor.
        let la = aIdx.last!, lt = aTime.last!
        let tail = max(1, out.count - 1 - la)
        for i in (la + 1)..<out.count { out[i] = lt + (lastT - lt) * Double(i - la) / Double(tail) }
        return out
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
