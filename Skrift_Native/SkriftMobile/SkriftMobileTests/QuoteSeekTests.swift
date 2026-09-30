import XCTest
@testable import SkriftMobile

/// Q83 (phone): tapping a word in the audiobook quote block seeks the quote clip to that
/// word's time. Timings are clip-relative (`QuoteCaptureProcessor` rebases the book's
/// per-word times by the span start), so word N of `CaptureQuote.displayText` is sidecar
/// word N and the seek target is `timings[N].start`.
final class QuoteSeekTests: XCTestCase {

    private let body = "> alpha bravo charlie\n> delta echo\n\nmy own ramble words here"
    private var timings: [WordTiming] {
        ["alpha", "bravo", "charlie", "delta", "echo", "my", "own", "ramble", "words", "here"]
            .enumerated().map { WordTiming(word: $1, start: Double($0) * 0.75, end: Double($0) * 0.75 + 0.5) }
    }

    func testTapOnEveryQuoteWordSeeksItsClipRelativeTime() throws {
        let quote = try XCTUnwrap(CaptureQuote.split(body))
        let ranges = KaraokeMap.wordRanges(in: quote.displayText as NSString)
        XCTAssertEqual(ranges.count, quote.spokenWordCount)
        for (n, r) in ranges.enumerated() {
            // Tap the middle of the word.
            let target = QuoteWordSeek.seekTime(atChar: r.location + r.length / 2,
                                                text: quote.displayText, timings: timings)
            XCTAssertEqual(target, timings[n].start, "word \(n)")
        }
    }

    func testTapOutsideTimedWordsDoesNothing() throws {
        let quote = try XCTUnwrap(CaptureQuote.split(body))
        XCTAssertNil(QuoteWordSeek.seekTime(atChar: 2, text: quote.displayText, timings: []))
        // Fewer timings than quote words (a partial sidecar): the untimed word has no target.
        XCTAssertNil(QuoteWordSeek.seekTime(atChar: (quote.displayText as NSString).length - 1,
                                            text: quote.displayText, timings: Array(timings.prefix(2))))
    }
}
