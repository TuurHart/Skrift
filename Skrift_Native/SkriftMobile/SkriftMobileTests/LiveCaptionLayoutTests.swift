import XCTest
@testable import SkriftMobile

/// The pure layout maths behind the live caption: the volatile-word boundary (F3,
/// the colour-by-confidence approximation) and the photo-marker clamping (F4). The
/// clamp is the load-bearing safety net — photo word-indices are captured against a
/// caption that re-transcribes wholesale, so a stale index must never index past the
/// current word count.
final class LiveCaptionLayoutTests: XCTestCase {

    private func words(_ n: Int) -> [String] { (1...n).map { "w\($0)" } }

    func testMarksGroupByWordIndex() {
        let marks = [LiveCaptionLayout.Mark(wordIndex: 0, number: 1),
                     LiveCaptionLayout.Mark(wordIndex: 3, number: 2),
                     LiveCaptionLayout.Mark(wordIndex: 3, number: 3)]
        let grouped = LiveCaptionLayout.marksByIndex(marks, words: words(5))
        XCTAssertEqual(grouped[0], [1])
        XCTAssertEqual(grouped[3], [2, 3])      // two photos at the same position keep order
        XCTAssertNil(grouped[1])
    }

    func testStaleMarkIndexIsClampedNotOvershot() {
        // A photo captured when the caption had 12 words, but the caption has since
        // re-transcribed shorter (4 words). The marker must clamp to the end (4), not
        // index out of range.
        let grouped = LiveCaptionLayout.marksByIndex([LiveCaptionLayout.Mark(wordIndex: 12, number: 1)], words: words(4))
        XCTAssertEqual(grouped[4], [1])
        XCTAssertNil(grouped[12])
    }

    func testNegativeIndexClampsToZero() {
        let grouped = LiveCaptionLayout.marksByIndex([LiveCaptionLayout.Mark(wordIndex: -3, number: 1)], words: words(10))
        XCTAssertEqual(grouped[0], [1])
    }

    func testEmptyMarksProduceEmptyMap() {
        XCTAssertTrue(LiveCaptionLayout.marksByIndex([], words: words(10)).isEmpty)
    }

    // MARK: - segments (the single-AttributedString runs behind the one-Text caption)
    //
    // The caption used to be built as per-word `Text + Text` concatenation, which
    // SwiftUI resolves recursively — long recordings overflowed the stack (SIGSEGV
    // in ConcatenatedTextStorage.resolve). The fix renders ONE Text over runs from
    // `segments`; these tests pin the run shapes (and that the run count stays
    // constant as the caption grows).

    func testSegmentsCoalesceIntoSolidAndVolatileRuns() {
        // firstVolatile = the committed-chunk word count (the REAL finalized
        // boundary) — everything after it is the live chunk, still settling.
        let words = ["a", "b", "c", "d", "e", "f", "g", "h"]
        let segs = LiveCaptionLayout.segments(words: words, photoMarks: [], firstVolatile: 2)
        XCTAssertEqual(segs, [
            LiveCaptionLayout.Segment(text: "a b ", style: .solid),
            LiveCaptionLayout.Segment(text: "c d e f g h ", style: .volatile),
        ])
    }

    func testSegmentsRunCountStaysConstantOnLongRecordings() {
        let words = (1...5000).map { "w\($0)" }
        let segs = LiveCaptionLayout.segments(words: words, photoMarks: [], firstVolatile: 4994)
        XCTAssertEqual(segs.count, 2, "run count must stay constant — one run per word is the crash shape")
    }

    func testSegmentsSplicePhotoTokensAtTheirWordIndex() {
        let segs = LiveCaptionLayout.segments(
            words: ["one", "two", "three"],
            photoMarks: [LiveCaptionLayout.Mark(wordIndex: 2, number: 1)],
            firstVolatile: 0
        )
        XCTAssertEqual(segs, [
            LiveCaptionLayout.Segment(text: "one two ", style: .volatile),
            LiveCaptionLayout.Segment(text: "[photo 1] ", style: .photo),
            LiveCaptionLayout.Segment(text: "three ", style: .volatile),
        ])
    }

    func testSegmentsClampStaleMarksIntoRange() {
        let segs = LiveCaptionLayout.segments(
            words: ["only"],
            photoMarks: [LiveCaptionLayout.Mark(wordIndex: -2, number: 1),
                         LiveCaptionLayout.Mark(wordIndex: 99, number: 2)],
            firstVolatile: 0
        )
        XCTAssertEqual(segs, [
            LiveCaptionLayout.Segment(text: "[photo 1] ", style: .photo),
            LiveCaptionLayout.Segment(text: "only ", style: .volatile),
            LiveCaptionLayout.Segment(text: "[photo 2] ", style: .photo),
        ])
    }

    func testSegmentsWithNoWordsKeepMarkersOnly() {
        let segs = LiveCaptionLayout.segments(words: [], photoMarks: [LiveCaptionLayout.Mark(wordIndex: 0, number: 1)], firstVolatile: 0)
        XCTAssertEqual(segs, [LiveCaptionLayout.Segment(text: "[photo 1] ", style: .photo)])
    }

    // MARK: - anchor relocation (photo-marker drift fix)
    //
    // The live caption re-transcribes its current chunk wholesale, so a mark's
    // absolute word index drifts when words merge/split BEFORE it. The mark now
    // carries the words it followed at capture; render re-locates them.

    func testAnchorRelocatesWhenWordsMergeBeforeTheMark() {
        // Captured after "going to" (index 4: ["i","am","gonna","go","now"] → wait,
        // simpler: caption at capture: ["i","am","going","to","stop"] mark at 5.
        // Re-transcription merged "i am" → "i'm": ["i'm","going","to","stop","more","words"].
        let mark = LiveCaptionLayout.Mark(wordIndex: 5, number: 1, anchor: ["going", "to", "stop"])
        let now = ["i'm", "going", "to", "stop", "more", "words"]
        XCTAssertEqual(LiveCaptionLayout.resolvedIndex(of: mark, in: now), 4,
                       "mark follows its anchor words, not the stale count")
    }

    func testAnchorMatchIsPunctuationAndCaseInsensitive() {
        let mark = LiveCaptionLayout.Mark(wordIndex: 3, number: 1, anchor: ["hello", "world"])
        let now = ["well", "Hello", "world.", "again"]
        XCTAssertEqual(LiveCaptionLayout.resolvedIndex(of: mark, in: now), 3)
    }

    func testRewrittenAnchorFallsBackToClampedIndex() {
        let mark = LiveCaptionLayout.Mark(wordIndex: 9, number: 1, anchor: ["totally", "rewritten"])
        let now = ["short", "caption"]
        XCTAssertEqual(LiveCaptionLayout.resolvedIndex(of: mark, in: now), 2, "clamped to end")
    }

    func testNearestAnchorOccurrenceWins() {
        // The anchor appears twice; the one nearest the captured index is chosen.
        let mark = LiveCaptionLayout.Mark(wordIndex: 6, number: 1, anchor: ["the", "end"])
        let now = ["the", "end", "is", "not", "the", "end", "yet"]
        XCTAssertEqual(LiveCaptionLayout.resolvedIndex(of: mark, in: now), 6)
    }
}
