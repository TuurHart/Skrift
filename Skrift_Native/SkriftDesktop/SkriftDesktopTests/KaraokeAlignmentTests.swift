import XCTest
import Foundation

/// C3: the karaoke highlight must track the ACTUAL spoken word, aligning the shown
/// body words to the raw ASR timings — not scale a fraction across a word count the
/// copy-edit / name-linking / conversation headers changed.
final class KaraokeAlignmentTests: XCTestCase {

    private func timings(_ pairs: [(String, Double)]) -> [WordTiming] {
        pairs.map { WordTiming(word: $0.0, start: $0.1, end: $0.1 + 0.4) }
    }

    /// Body == transcript → every displayed word gets its exact timing start.
    func testExactWhenBodyEqualsTranscript() {
        let t = timings([("hello", 0), ("world", 1), ("this", 2), ("is", 3), ("great", 4)])
        let words = ["hello", "world", "this", "is", "great"]
        let times = Karaoke.wordTimes(displayedWords: words, timings: t)
        XCTAssertEqual(times, [0, 1, 2, 3, 4], "each shown word aligns to its real start; got \(times)")
    }

    /// Copy-edit removed fillers ("um", "you know", "really") → content words still land
    /// on their REAL times, the dropped-filler gaps are absorbed, and it stays monotonic.
    func testCopyEditRemovedFillersStillAligns() {
        let t = timings([("um", 0), ("the", 1), ("meeting", 2), ("you", 3),
                         ("know", 4), ("went", 5), ("really", 6), ("well", 7)])
        let words = ["the", "meeting", "went", "well"]   // the cleaned copy-edit
        let times = Karaoke.wordTimes(displayedWords: words, timings: t)
        XCTAssertEqual(times, [0, 2, 5, 7], "content words anchor to their spoken times; got \(times)")
        XCTAssertEqual(times, times.sorted(), "monotonic non-decreasing")
    }

    /// Conversation `**Name:**` headers are NOT spoken tokens → they interpolate between
    /// the real spoken anchors instead of consuming audio, and never break monotonicity.
    func testConversationHeadersInterpolate() {
        let t = timings([("hello", 0), ("there", 1), ("hello", 2), ("back", 3)])
        let words = ["**Roksana:**", "hello", "there", "**Tuur:**", "hello", "back"]
        let times = Karaoke.wordTimes(displayedWords: words, timings: t)
        XCTAssertEqual(times, times.sorted(), "monotonic even with header tokens; got \(times)")
        XCTAssertEqual(times[1], 0, "first spoken 'hello' at its real time")
        XCTAssertEqual(times[5], 3, "last spoken 'back' at its real time")
        XCTAssertGreaterThanOrEqual(times[3], times[2], "the '**Tuur:**' header can't jump backward")
    }

    /// `activeCount` = how many shown words have started by `currentTime` (the highlight
    /// count) — the boundary that drives which words are bright.
    func testActiveCountAtTime() {
        let times: [Double] = [0, 2, 5, 7]
        XCTAssertEqual(Karaoke.activeCount(times: times, currentTime: -1), 0)
        XCTAssertEqual(Karaoke.activeCount(times: times, currentTime: 2), 2)
        XCTAssertEqual(Karaoke.activeCount(times: times, currentTime: 6), 3)
        XCTAssertEqual(Karaoke.activeCount(times: times, currentTime: 99), 4)
    }

    /// No timings → empty (the caller falls back to a pure time/duration proportion).
    func testNoTimingsIsEmpty() {
        XCTAssertTrue(Karaoke.wordTimes(displayedWords: ["a", "b"], timings: []).isEmpty)
        XCTAssertTrue(Karaoke.wordTimes(displayedWords: [], timings: timings([("x", 0)])).isEmpty)
    }

    /// Normalization: alias-display links show their SPOKEN half, headers drop markdown.
    func testNormalizeStripsMarkup() {
        XCTAssertEqual(Karaoke.normalize("[[Tiuri Hartog|Tuur]]"), "tuur")
        XCTAssertEqual(Karaoke.normalize("**Roksana:**"), "roksana")
        XCTAssertEqual(Karaoke.normalize("world,"), "world")
    }
}
