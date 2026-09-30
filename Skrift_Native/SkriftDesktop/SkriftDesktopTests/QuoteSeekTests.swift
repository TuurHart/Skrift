import XCTest
import Foundation

/// Q83: tapping a word in an audiobook quote capture seeks the quote clip to THAT word's
/// time, through the same shared seek code a voice note uses (`Karaoke.seekTarget`).
/// Synthetic capture: a `> ` quote block (clip-relative timings from 0), then the ramble
/// whose timings continue after the quote's.
final class QuoteSeekTests: XCTestCase {

    private let body = "> alpha bravo charlie\n> delta echo\n\nmy own ramble words here"
    private let words = ["alpha", "bravo", "charlie", "delta", "echo",
                         "my", "own", "ramble", "words", "here"]

    private var timings: [WordTiming] {
        words.enumerated().map { WordTiming(word: $1, start: Double($0) * 0.75, end: Double($0) * 0.75 + 0.5) }
    }

    /// The Mac click path: storage word tokens include the `>` markers (the text view
    /// hides them but keeps the characters), the times come from `Karaoke.wordTimes` over
    /// the same whitespace split, and a click on word token W seeks `seekTarget(W…)`.
    func testMacClickOnEveryQuoteWordSeeksThatWordsTime() {
        let displayed = body.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let times = Karaoke.wordTimes(displayedWords: displayed, timings: timings)
        XCTAssertEqual(times.count, displayed.count)
        let duration = 7.5
        for (token, text) in displayed.enumerated() where words.contains(text) {
            let spoken = words.firstIndex(of: text)!
            let target = Karaoke.seekTarget(wordIndex: token, times: times, timings: timings, duration: duration)
            XCTAssertEqual(target, timings[spoken].start, accuracy: 0.001,
                           "clicking \"\(text)\" must seek to its own time, got \(target)")
        }
    }

    /// The phone tap path: the quote text has no markers, so tapped word N IS sidecar word N.
    func testSeekTimeForWordIsThatWordsStart() {
        for (i, w) in timings.enumerated() {
            XCTAssertEqual(Karaoke.seekTime(forWord: i, in: timings), w.start)
        }
        XCTAssertNil(Karaoke.seekTime(forWord: -1, in: timings))
        XCTAssertNil(Karaoke.seekTime(forWord: timings.count, in: timings))
        XCTAssertNil(Karaoke.seekTime(forWord: 0, in: []))
    }
}
