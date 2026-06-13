import XCTest
@testable import SkriftMobile

/// Pure logic behind the text-first capture screen: the tap-to-build selection
/// rules and the window-local → book-time span mapping. The real transcription
/// (export + Parakeet) is device-owed; these pin the math the UI depends on.
final class TextCaptureTests: XCTestCase {

    func testTapExtendsUpAndDown() {
        var s = TextCaptureSelection(lo: 5, hi: 5)
        XCTAssertEqual(s.count, 1)
        _ = s.tap(7)                                   // below the range → extend down
        XCTAssertEqual([s.lo, s.hi], [5, 7])
        _ = s.tap(3)                                   // above the range → extend up
        XCTAssertEqual([s.lo, s.hi], [3, 7])
        XCTAssertEqual(s.count, 5)
    }

    func testTapEdgeShrinks() {
        var s = TextCaptureSelection(lo: 3, hi: 7)
        _ = s.tap(3)                                   // top edge → drop top
        XCTAssertEqual([s.lo, s.hi], [4, 7])
        _ = s.tap(7)                                   // bottom edge → drop bottom
        XCTAssertEqual([s.lo, s.hi], [4, 6])
    }

    func testSingleSelectionWontShrinkBelowOne() {
        var s = TextCaptureSelection(lo: 2, hi: 2)
        let msg = s.tap(2)
        XCTAssertEqual([s.lo, s.hi], [2, 2], "the quote keeps at least one line")
        XCTAssertEqual(msg, "this is your quote — tap a + line to add more")
    }

    func testTapMiddleRefusesWithHint() {
        var s = TextCaptureSelection(lo: 2, hi: 6)
        let msg = s.tap(4)
        XCTAssertEqual([s.lo, s.hi], [2, 6], "middle taps don't change the range")
        XCTAssertEqual(msg, "tap an end line (✕) to shorten")
    }

    func testGlobalSpanMapsWindowLocalToBookTime() {
        let sents = [
            BufferSentence(text: "a", start: 1, end: 3, words: [], isInInitialSpan: false),
            BufferSentence(text: "b", start: 3, end: 6, words: [], isInInitialSpan: false),
            BufferSentence(text: "c", start: 6, end: 9, words: [], isInInitialSpan: false),
        ]
        // window starts 100 s into the file; the file starts 1000 s into the book.
        let span = TextCaptureMath.globalSpan(sentences: sents, lo: 0, hi: 1,
                                              windowStart: 100, fileOrigin: 1000)
        XCTAssertEqual(span?.start, 1101)              // 1 + 100 + 1000
        XCTAssertEqual(span?.end, 1106)                // 6 + 100 + 1000
    }

    func testGlobalSpanOutOfRangeIsNil() {
        XCTAssertNil(TextCaptureMath.globalSpan(sentences: [], lo: 0, hi: 0,
                                                windowStart: 0, fileOrigin: 0))
        let one = [BufferSentence(text: "x", start: 0, end: 1, words: [], isInInitialSpan: false)]
        XCTAssertNil(TextCaptureMath.globalSpan(sentences: one, lo: 0, hi: 5,
                                                windowStart: 0, fileOrigin: 0))
    }

}
