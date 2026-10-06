import XCTest
@testable import SkriftMobile

/// Q329 / D183: a captured quote edits like the rest of the note. Karaoke and tap-to-seek keep
/// working on the words that still line up with the audio; an edit that changes the word count
/// degrades to no highlight for the words that no longer match — never a crash, never a wrong
/// word, never an out-of-range index.
final class QuoteEditKaraokeTests: XCTestCase {

    private let spoken = ["alpha", "bravo", "charlie", "delta", "echo",
                          "my", "own", "ramble", "words", "here"]
    private var timings: [WordTiming] {
        spoken.enumerated().map { WordTiming(word: $1, start: Double($0) * 0.75, end: Double($0) * 0.75 + 0.5) }
    }
    private let ramble = "my own ramble words here"

    private func map(_ quote: String) -> QuoteKaraokeMap {
        QuoteKaraokeMap(quoteWords: QuoteKaraokeMap.words(of: quote),
                        rambleWordCount: QuoteKaraokeMap.spokenWordCount(ofRamble: ramble),
                        timings: timings)
    }

    func testUneditedQuoteIsPositional() {
        let m = map("alpha bravo charlie delta echo")
        XCTAssertEqual(m.wordCount, 5)
        for i in 0..<5 { XCTAssertEqual(m.seekTime(forWord: i), timings[i].start, "word \(i)") }
        XCTAssertEqual(m.activeWord(at: 1.6), 2, "charlie plays at 1.5–2.0")
        XCTAssertNil(m.activeWord(at: -1))
    }

    func testDeletedWordKeepsTheRestOnTheirOwnTimes() {
        let m = map("alpha charlie delta echo")   // bravo deleted
        XCTAssertEqual(m.wordCount, 4)
        XCTAssertEqual(m.seekTime(forWord: 0), timings[0].start)
        XCTAssertEqual(m.seekTime(forWord: 1), timings[2].start, "charlie keeps charlie's time")
        XCTAssertEqual(m.seekTime(forWord: 3), timings[4].start)
        XCTAssertEqual(m.activeWord(at: 2.3), 1, "charlie, not the word at index 2")
    }

    func testInsertedWordDoesNotLightAndDoesNotShiftTheOthers() {
        let m = map("alpha bravo really charlie delta echo")
        XCTAssertNil(m.seekTime(forWord: 2), "the new word has no audio")
        XCTAssertEqual(m.seekTime(forWord: 3), timings[2].start)
        XCTAssertEqual(m.seekTime(forWord: 5), timings[4].start)
        // At charlie's time the active word is charlie (index 3), not the inserted one.
        XCTAssertEqual(m.activeWord(at: 1.55), 3)
    }

    func testReplacedWordAmongMatchesStaysDark() {
        let m = map("alpha bravo CHARLES delta echo")   // same count, one word retyped
        XCTAssertEqual(m.seekTime(forWord: 0), timings[0].start)
        XCTAssertEqual(m.seekTime(forWord: 4), timings[4].start)
        for i in 0..<m.wordCount {
            if let t = m.seekTime(forWord: i) {
                XCTAssertTrue(timings.contains { $0.start == t }, "a time only ever comes from a real timing")
            }
        }
    }

    func testPastTheLastMatchedWordEverythingReadsAsRead() {
        let m = map("alpha bravo charlie delta echo")
        XCTAssertEqual(m.activeWord(at: 3.2), 4, "echo is still playing")
        XCTAssertEqual(m.activeWord(at: 3.9), 5, "quote finished: all 5 read, none lit")
    }

    func testNoTimingsOrEmptyOrWildlyDifferentNeverCrash() {
        let none = QuoteKaraokeMap(quoteWords: ["a", "b"], rambleWordCount: 0, timings: [])
        XCTAssertNil(none.seekTime(forWord: 0))
        XCTAssertNil(none.activeWord(at: 5))
        let empty = QuoteKaraokeMap(quoteWords: [], rambleWordCount: 0, timings: timings)
        XCTAssertEqual(empty.wordCount, 0)
        XCTAssertNil(empty.seekTime(forWord: 0))
        let wild = map("completely different words that were never spoken at all today")
        for i in -2..<(wild.wordCount + 3) { _ = wild.seekTime(forWord: i) }   // out of range → nil, no trap
        _ = wild.activeWord(at: 100)
        XCTAssertNil(wild.seekTime(forWord: wild.wordCount))
        XCTAssertNil(wild.seekTime(forWord: -1))
    }

    func testTapOnAnEditedQuoteSeeksOnlyMatchedWords() {
        let text = "alpha bravo really charlie"
        let m = map(text)
        func tap(_ word: String) -> TimeInterval? {
            let r = (text as NSString).range(of: word)
            return QuoteWordSeek.seekTime(atChar: r.location + 1, text: text, map: m)
        }
        XCTAssertEqual(tap("bravo"), timings[1].start)
        XCTAssertNil(tap("really"), "an inserted word has nowhere to seek")
        XCTAssertEqual(tap("charlie"), timings[2].start)
    }

    func testRambleSliceFollowsAnEditedQuote() {
        // 5 quote + 5 ramble timings. Unedited: ramble starts at 5.
        XCTAssertEqual(QuoteKaraokeMap.rambleTimingsStart(quoteWordCount: 5, rambleWordCount: 5, timingCount: 10), 5)
        // Quote grew to 8 shown words; the ramble is still the sidecar's last 5.
        XCTAssertEqual(QuoteKaraokeMap.rambleTimingsStart(quoteWordCount: 8, rambleWordCount: 5, timingCount: 10), 5)
        // Quote shrank to 3: never later than the quote, so the ramble keeps its words.
        XCTAssertEqual(QuoteKaraokeMap.rambleTimingsStart(quoteWordCount: 3, rambleWordCount: 5, timingCount: 10), 3)
        // Quote at/past the whole sidecar (typed ramble): the whole sidecar, as before.
        XCTAssertEqual(QuoteKaraokeMap.rambleTimingsStart(quoteWordCount: 10, rambleWordCount: 4, timingCount: 10), 0)
        XCTAssertEqual(QuoteKaraokeMap.rambleTimingsStart(quoteWordCount: 0, rambleWordCount: 4, timingCount: 10), 0)
    }

    // MARK: the stored body after a quote edit

    func testBodyWithEditedQuoteKeepsMarkersAndRambleBytes() throws {
        let body = "> alpha bravo charlie\n> delta echo\n\nmy own ramble words here"
        let quote = try XCTUnwrap(CaptureQuote.split(body))
        XCTAssertEqual(quote.body(withQuote: quote.displayText), body, "unchanged quote = unchanged body")
        let edited = quote.body(withQuote: "alpha bravo\ncharlie delta echo.\n\nsecond paragraph")
        XCTAssertEqual(edited, "> alpha bravo\n> charlie delta echo.\n>\n> second paragraph\n\nmy own ramble words here")
        let again = try XCTUnwrap(CaptureQuote.split(edited))
        XCTAssertEqual(again.displayText, "alpha bravo\ncharlie delta echo.\n\nsecond paragraph")
        XCTAssertEqual(again.ramble, "my own ramble words here")
    }

    func testClearingTheQuoteLeavesTheRamble() throws {
        let quote = try XCTUnwrap(CaptureQuote.split("> a b c\n\nmine"))
        XCTAssertEqual(quote.body(withQuote: "  \n "), "mine")
        let only = try XCTUnwrap(CaptureQuote.split("> a b c"))
        XCTAssertEqual(only.body(withQuote: ""), "")
        XCTAssertEqual(only.body(withQuote: "a b"), "> a b", "a quote-only capture stays quote-only")
    }
}
