import XCTest
@testable import SkriftMobile

/// The pure layout maths behind the live caption: the volatile-word boundary (F3,
/// the colour-by-confidence approximation) and the photo-marker clamping (F4). The
/// clamp is the load-bearing safety net — photo word-indices are captured against a
/// caption that re-transcribes wholesale, so a stale index must never index past the
/// current word count.
final class LiveCaptionLayoutTests: XCTestCase {

    func testVolatileStartSplitsOffTheTrailingWords() {
        XCTAssertEqual(LiveCaptionLayout.volatileStart(wordCount: 20, trailing: 6), 14)
        XCTAssertEqual(LiveCaptionLayout.volatileStart(wordCount: 6, trailing: 6), 0)
        // Fewer words than the volatile window → everything is volatile (start 0).
        XCTAssertEqual(LiveCaptionLayout.volatileStart(wordCount: 3, trailing: 6), 0)
        XCTAssertEqual(LiveCaptionLayout.volatileStart(wordCount: 0, trailing: 6), 0)
    }

    func testMarksGroupByWordIndex() {
        let marks = [(wordIndex: 0, number: 1), (wordIndex: 3, number: 2), (wordIndex: 3, number: 3)]
        let grouped = LiveCaptionLayout.marksByIndex(marks, wordCount: 5)
        XCTAssertEqual(grouped[0], [1])
        XCTAssertEqual(grouped[3], [2, 3])      // two photos at the same position keep order
        XCTAssertNil(grouped[1])
    }

    func testStaleMarkIndexIsClampedNotOvershot() {
        // A photo captured when the caption had 12 words, but the caption has since
        // re-transcribed shorter (4 words). The marker must clamp to the end (4), not
        // index out of range.
        let grouped = LiveCaptionLayout.marksByIndex([(wordIndex: 12, number: 1)], wordCount: 4)
        XCTAssertEqual(grouped[4], [1])
        XCTAssertNil(grouped[12])
    }

    func testNegativeIndexClampsToZero() {
        let grouped = LiveCaptionLayout.marksByIndex([(wordIndex: -3, number: 1)], wordCount: 10)
        XCTAssertEqual(grouped[0], [1])
    }

    func testEmptyMarksProduceEmptyMap() {
        XCTAssertTrue(LiveCaptionLayout.marksByIndex([], wordCount: 10).isEmpty)
    }
}
