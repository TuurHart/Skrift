import Foundation

/// Karaoke + tap-to-seek for an audiobook / text-capture QUOTE that may have been edited
/// (D183: a quote is text — it edits like the rest of the note). The timings sidecar holds
/// the quote's spoken words first, then the ramble's; after an edit the shown quote no longer
/// has to line up with them word for word.
///
/// Per shown word the map holds the sidecar time it still lines up with, or nil. nil words are
/// never highlighted and a tap on one seeks nowhere — a degraded highlight, never a wrong one.
/// Pure and shared so the phone's quote block and the Mac's note tests ask the same rule.
struct QuoteKaraokeMap: Equatable, Sendable {
    /// One entry per shown quote word; nil = no longer lines up with the audio.
    let starts: [Double?]
    let ends: [Double?]

    var wordCount: Int { starts.count }

    /// - quoteWords: the shown quote, whitespace split (no `>` markers).
    /// - rambleWordCount: spoken-word count of the note text BELOW the quote. With the shown
    ///   quote + ramble adding up to the sidecar, the quote is the sidecar's head and word N IS
    ///   timing N (the unedited capture, and the Q83 contract). Otherwise something was edited,
    ///   so the quote is aligned against the sidecar (`AlignmentCore`) and only words it can
    ///   place with a direct time keep one.
    init(quoteWords: [String], rambleWordCount: Int, timings: [WordTiming]) {
        let n = quoteWords.count
        guard n > 0, !timings.isEmpty else {
            starts = [Double?](repeating: nil, count: n)
            ends = starts
            return
        }
        let head = (n + rambleWordCount == timings.count) ? Array(timings.prefix(n)) : timings
        if head.count == n {
            starts = head.map { Optional($0.start) }
            ends = head.map { Optional($0.end) }
            return
        }
        var s = [Double?](repeating: nil, count: n)
        var e = [Double?](repeating: nil, count: n)
        var config = AlignmentCore.Config()
        config.anchorN = 1
        let result = AlignmentCore.align(
            transcript: head.map { AlignmentCore.Word(text: $0.word, start: $0.start, end: $0.end) },
            book: [AlignmentCore.Block(text: quoteWords.joined(separator: " "), sourceFile: "quote")],
            config: config)
        if result.verdict != .rejected {
            for range in result.matchedRanges {
                for (offset, wt) in range.wordTimes.enumerated() where wt.direct {
                    let i = range.bookWordStart + offset
                    if i >= 0, i < n { s[i] = wt.start; e[i] = wt.end }
                }
            }
        }
        starts = s
        ends = e
    }

    /// Where the RAMBLE's timings start in the sidecar. Unedited that is the quote's word count.
    /// An edited quote changes the quote's count but not the sidecar, so with the ramble's own
    /// words known the tail is `timingCount - rambleWordCount` — whichever is earlier, so an
    /// edit never pushes the ramble past where its first spoken word really is. A quote count
    /// at or past the whole sidecar (typed ramble, nothing spoken after) means the whole sidecar.
    static func rambleTimingsStart(quoteWordCount: Int, rambleWordCount: Int, timingCount: Int) -> Int {
        guard quoteWordCount > 0, quoteWordCount < timingCount else { return 0 }
        return min(quoteWordCount, max(0, timingCount - rambleWordCount))
    }

    /// The shown quote's words (whitespace split), the way `KaraokeMap.wordRanges` counts them.
    static func words(of text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Spoken words in the text under a quote: whitespace tokens, minus `[[img_N]]` photo markers.
    static func spokenWordCount(ofRamble ramble: String) -> Int {
        words(of: ramble).filter { !$0.hasPrefix("[[img_") }.count
    }

    /// The shown word playing at `time`: the last matched word that has started. Once the last
    /// matched word has finished, `wordCount` (every word read, none playing) so a ramble
    /// playing after the quote doesn't leave the quote's last word lit. nil before the first.
    func activeWord(at time: TimeInterval) -> Int? {
        var last: Int?
        for i in starts.indices {
            if let s = starts[i], s <= time { last = i }
        }
        guard let last else { return nil }
        if last == starts.lastIndex(where: { $0 != nil }), let end = ends[last], time >= end { return wordCount }
        return last
    }

    /// Where a tap on shown word `index` seeks. nil for an unmatched or missing word.
    func seekTime(forWord index: Int) -> TimeInterval? {
        guard index >= 0, index < starts.count else { return nil }
        return starts[index]
    }
}
