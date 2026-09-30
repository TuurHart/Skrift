import XCTest
@testable import SkriftMobile

/// Deterministic paragraphing: break on a long pause after a finished sentence.
final class ParagrapherTests: XCTestCase {

    private func w(_ word: String, _ start: Double, _ end: Double) -> WordTiming {
        WordTiming(word: word, start: start, end: end)
    }

    func testTranscriptVariantPreservesMarkersAndPunctuation() {
        // Token-preserving: exact words + [[img]] marker survive; only \n\n is added.
        let words = [
            w("Look.", 0.0, 0.5),
            w("Here.", 2.0, 2.4),   // 1.5s gap after "Look." → paragraph break
        ]
        // The marked transcript has an image marker between the two words.
        let out = Paragrapher.paragraphed(transcript: "Look. [[img_001]] Here.",
                                          words: words, gapThreshold: 0.65, maxSentences: 4)
        XCTAssertEqual(out, "Look. [[img_001]]\n\nHere.")
    }

    func testTranscriptVariantNoTimingsReturnsTrimmed() {
        XCTAssertEqual(Paragrapher.paragraphed(transcript: "  Plain text.  ", words: []), "Plain text.")
    }

    func testAlreadyStructuredTextPassesThroughUntouched() {
        // An existing newline is deliberate structure (speaker turns, a live draft's own
        // paragraph joins) — re-flowing the tokens would destroy it. Raw ASR is always flat.
        let attributed = "**Tiuri:** one two.\n\n**Roksana:** three four."
        let words = [w("one", 0.0, 0.2), w("two.", 0.3, 0.5),
                     w("three", 3.0, 3.2), w("four.", 3.3, 3.5)]
        XCTAssertEqual(Paragrapher.paragraphed(transcript: attributed, words: words), attributed)
    }

    func testEndsSentence() {
        XCTAssertTrue(Paragrapher.endsSentence("done."))
        XCTAssertTrue(Paragrapher.endsSentence("really?"))
        XCTAssertTrue(Paragrapher.endsSentence("stop!"))
        XCTAssertTrue(Paragrapher.endsSentence("\"quote.\""))
        XCTAssertFalse(Paragrapher.endsSentence("comma,"))
        XCTAssertFalse(Paragrapher.endsSentence("plain"))
        // Caveat: an abbreviation like "e.g." ends in "." so it reads as a sentence
        // end — acceptable, since it rarely coincides with a long (paragraph) pause.
        XCTAssertTrue(Paragrapher.endsSentence("e.g."))
    }
}
