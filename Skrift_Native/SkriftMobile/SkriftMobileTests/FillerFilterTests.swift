import XCTest
@testable import SkriftMobile

final class FillerFilterTests: XCTestCase {

    private func timings(_ words: [String]) -> [WordTiming] {
        words.enumerated().map { i, w in
            WordTiming(word: w, start: Double(i) * 0.3, end: Double(i) * 0.3 + 0.25)
        }
    }

    func testStripsStandaloneFillers() {
        let text = "Um, I think uh we should go."
        let words = timings(["Um,", "I", "think", "uh", "we", "should", "go."])
        let out = FillerFilter.strip(transcript: text, words: words)
        XCTAssertEqual(out.text, "I think we should go.")
        XCTAssertEqual(out.words.map(\.word), ["I", "think", "we", "should", "go."])
        XCTAssertEqual(out.removedCount, 2)
        // Timings keep their original clock values.
        XCTAssertEqual(out.words[0].start, 0.3, accuracy: 0.001)
    }

    func testRealWordsSurvive() {
        // "er" (Dutch), "so", "like" are real words and NOT in the stoplist.
        let text = "Er is like so much to do."
        let words = timings(["Er", "is", "like", "so", "much", "to", "do."])
        let out = FillerFilter.strip(transcript: text, words: words)
        XCTAssertEqual(out.text, text)
        XCTAssertEqual(out.removedCount, 0)
    }

    func testSentenceTerminatorTransfersFromDroppedFiller() {
        let text = "we should stop hmm. Then continue."
        let words = timings(["we", "should", "stop", "hmm.", "Then", "continue."])
        let out = FillerFilter.strip(transcript: text, words: words)
        XCTAssertEqual(out.text, "we should stop. Then continue.")
        XCTAssertEqual(out.words.map(\.word), ["we", "should", "stop.", "Then", "continue."])
    }

    func testMarkersPassThroughUntouched() {
        let text = "Um, look at [[img_001]] this one."
        let words = timings(["Um,", "look", "at", "this", "one."])
        let out = FillerFilter.strip(transcript: text, words: words)
        XCTAssertEqual(out.text, "look at [[img_001]] this one.")
        XCTAssertEqual(out.words.count, 4)
    }

    func testAllFillerTranscriptStaysUnchanged() {
        let text = "Um, hmm."
        let words = timings(["Um,", "hmm."])
        let out = FillerFilter.strip(transcript: text, words: words)
        XCTAssertEqual(out.text, text)
        XCTAssertEqual(out.removedCount, 0)
    }

    func testNoFillersIsIdentity() {
        let text = "A perfectly clean sentence."
        let words = timings(["A", "perfectly", "clean", "sentence."])
        let out = FillerFilter.strip(transcript: text, words: words)
        XCTAssertEqual(out.text, text)
        XCTAssertEqual(out.words, words)
    }
}
