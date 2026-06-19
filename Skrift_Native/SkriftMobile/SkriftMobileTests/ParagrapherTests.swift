import XCTest
@testable import SkriftMobile

/// Deterministic paragraphing: break on a long pause after a finished sentence.
final class ParagrapherTests: XCTestCase {

    private func w(_ word: String, _ start: Double, _ end: Double) -> WordTiming {
        WordTiming(word: word, start: start, end: end)
    }

    func testBreaksOnLongPauseAfterSentence() {
        let words = [
            w("Hello.", 0.0, 0.5),
            w("World.", 0.7, 1.1),       // short gap (0.2s) — same paragraph
            w("New", 2.0, 2.3),          // long gap (0.9s) after "World." — break
            w("para.", 2.4, 2.8),
        ]
        let out = Paragrapher.paragraphed(words: words, gapThreshold: 0.65)
        XCTAssertEqual(out, "Hello. World.\n\nNew para.")
    }

    func testNoBreakOnLongPauseMidSentence() {
        // A long silence after a non-sentence-ending word must NOT break (it's a
        // dramatic pause mid-sentence, not a paragraph boundary).
        let words = [
            w("The", 0.0, 0.2),
            w("answer", 0.3, 0.8),
            w("is", 2.0, 2.2),           // 1.2s gap but "answer" isn't a sentence end
            w("yes.", 2.3, 2.7),
        ]
        let out = Paragrapher.paragraphed(words: words, gapThreshold: 0.65)
        XCTAssertEqual(out, "The answer is yes.")
    }

    func testTrailingQuoteStillCountsAsSentenceEnd() {
        let words = [
            w("\"Stop!\"", 0.0, 0.6),
            w("Next", 1.5, 1.8),         // 0.9s gap after a sentence end with a quote
            w("one.", 1.9, 2.2),
        ]
        let out = Paragrapher.paragraphed(words: words, gapThreshold: 0.65)
        XCTAssertEqual(out, "\"Stop!\"\n\nNext one.")
    }

    func testEmptyAndSingleWord() {
        XCTAssertEqual(Paragrapher.paragraphed(words: []), "")
        XCTAssertEqual(Paragrapher.paragraphed(words: [w("Solo.", 0, 0.5)]), "Solo.")
    }

    func testHigherThresholdMakesFewerParagraphs() {
        let words = [
            w("One.", 0.0, 0.4),
            w("Two.", 1.2, 1.6),         // 0.8s gap after a sentence
            w("Three.", 2.8, 3.2),       // 1.2s gap after a sentence
        ]
        // 0.65s threshold → breaks at both gaps → 3 paragraphs.
        XCTAssertEqual(Paragrapher.paragraphed(words: words, gapThreshold: 0.65).components(separatedBy: "\n\n").count, 3)
        // 1.0s threshold → only the 1.2s gap breaks → 2 paragraphs.
        XCTAssertEqual(Paragrapher.paragraphed(words: words, gapThreshold: 1.0).components(separatedBy: "\n\n").count, 2)
    }

    func testSentenceCapBreaksDenseNarration() {
        // Six sentences read steadily (0.1s gaps — no pause break ever). With a
        // 2-sentence cap, dense narration still breaks every 2 sentences.
        var words: [WordTiming] = []
        var t = 0.0
        for n in 1...6 { words.append(w("S\(n).", t, t + 0.4)); t += 0.5 }
        let out = Paragrapher.paragraphed(words: words, gapThreshold: 0.65, maxSentences: 2)
        XCTAssertEqual(out, "S1. S2.\n\nS3. S4.\n\nS5. S6.")
    }

    func testPauseBreakStillWinsBeforeCap() {
        // A long pause breaks immediately even if the cap isn't reached.
        let words = [
            w("A.", 0.0, 0.4),
            w("B.", 2.0, 2.4),   // 1.6s gap after A. → break (cap=4 not reached)
            w("C.", 2.5, 2.9),
        ]
        XCTAssertEqual(Paragrapher.paragraphed(words: words, gapThreshold: 0.65, maxSentences: 4),
                       "A.\n\nB. C.")
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

    func testTextOnlyFallbackGroupsSentences() {
        let text = "A. B. C. D. E."
        let out = Paragrapher.paragraphed(text: text, sentencesPerParagraph: 2)
        XCTAssertEqual(out, "A. B.\n\nC. D.\n\nE.")
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
