import XCTest
@testable import SkriftMobile

final class KaraokeTests: XCTestCase {
    private let timings: [WordTiming] = [
        WordTiming(word: "hello",  start: 0.0, end: 0.5),
        WordTiming(word: "there",  start: 0.5, end: 1.0),
        WordTiming(word: "friend", start: 1.2, end: 1.8),
    ]

    func testActiveWordIndex() {
        XCTAssertNil(Karaoke.activeWordIndex([], at: 1.0))            // no timings
        XCTAssertNil(Karaoke.activeWordIndex(timings, at: -0.1))     // before the first word
        XCTAssertEqual(Karaoke.activeWordIndex(timings, at: 0.0), 0) // first word starts
        XCTAssertEqual(Karaoke.activeWordIndex(timings, at: 0.3), 0)
        XCTAssertEqual(Karaoke.activeWordIndex(timings, at: 0.5), 1) // second word starts
        XCTAssertEqual(Karaoke.activeWordIndex(timings, at: 1.1), 1) // gap → stays on the previous word
        XCTAssertEqual(Karaoke.activeWordIndex(timings, at: 1.2), 2)
        XCTAssertEqual(Karaoke.activeWordIndex(timings, at: 99),  2) // past the end → last word
    }
}
