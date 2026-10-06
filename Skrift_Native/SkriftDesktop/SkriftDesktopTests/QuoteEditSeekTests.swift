import XCTest
import Foundation

/// Q329 / D183: the Mac's quote is ordinary editable text and clicking one of its words during
/// playback still seeks that word. The click path is the shared `KaraokeTrack` over the whole
/// body (the `> ` markers are tokens in the storage), so an EDITED quote has to keep seeking the
/// words that still line up, never a neighbour's time.
final class QuoteEditSeekTests: XCTestCase {

    private let spoken = ["alpha", "bravo", "charlie", "delta", "echo",
                          "my", "own", "ramble", "words", "here"]
    private var timings: [WordTiming] {
        spoken.enumerated().map { WordTiming(word: $1, start: Double($0) * 0.75, end: Double($0) * 0.75 + 0.5) }
    }

    /// Click on shown token `token` of `body`, the way `NoteBody.karaokePlayback` resolves it.
    private func seek(_ body: String, token: Int) -> Double? {
        let displayed = body.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return KaraokeTrack(displayedWords: displayed, timings: timings, duration: 7.5).seekTime(forWord: token)
    }

    private func token(of word: String, in body: String) -> Int {
        body.split(whereSeparator: { $0.isWhitespace }).map(String.init).firstIndex(of: word)!
    }

    func testUneditedQuoteWordsSeekTheirOwnTimes() {
        let body = "> alpha bravo charlie\n> delta echo\n\nmy own ramble words here"
        for (i, w) in spoken.enumerated() {
            XCTAssertEqual(seek(body, token: token(of: w, in: body)) ?? -1, timings[i].start, accuracy: 0.001, w)
        }
    }

    func testEditedQuoteStillSeeksTheWordsThatLineUp() {
        // "bravo" deleted, "really" inserted, a typo fixed in the ramble-side word count unchanged.
        let body = "> alpha charlie really delta echo\n\nmy own ramble words here"
        for w in ["alpha", "charlie", "delta", "echo", "ramble"] {
            let i = spoken.firstIndex(of: w)!
            XCTAssertEqual(seek(body, token: token(of: w, in: body)) ?? -1, timings[i].start, accuracy: 0.001,
                           "\(w) must seek its own time after the edit")
        }
    }

    func testClearedQuoteIsJustTheRambleAndSeeksIt() {
        let body = "my own ramble words here"
        XCTAssertEqual(seek(body, token: token(of: "ramble", in: body)) ?? -1, timings[7].start, accuracy: 0.001)
    }

    func testEditingTheQuoteNeedsNoReadOnlyGate() throws {
        // D183: the editor no longer asks `CaptureQuote.editVerdict` — the split is still how the
        // note is drawn and exported, and an edited block splits back into the same ramble.
        let body = "> alpha bravo\n\nmy own ramble"
        let split = try XCTUnwrap(CaptureQuote.split(body))
        XCTAssertEqual(split.ramble, "my own ramble")
        let typed = "> alpha bravo, edited\n\nmy own ramble"
        XCTAssertEqual(CaptureQuote.split(typed)?.displayText, "alpha bravo, edited")
        XCTAssertEqual(CaptureQuote.split(typed)?.ramble, "my own ramble")
    }
}
