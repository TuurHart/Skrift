import XCTest
@testable import SkriftMobile

/// Pure ChapterDetector tests — synthetic word streams, no audio, no engine.
final class ChapterDetectorTests: XCTestCase {

    /// Build a word stream from (gapBeforeWord, word) pairs. Words last 0.25 s.
    private func stream(_ script: [(TimeInterval, String)],
                        from start: TimeInterval = 0) -> [WordTiming] {
        var t = start
        var out: [WordTiming] = []
        for (gap, word) in script {
            t += gap
            out.append(WordTiming(word: word, start: t, end: t + 0.25))
            t += 0.25
        }
        return out
    }

    /// Filler prose: `n` words with small natural gaps, last word ends the sentence.
    private func prose(_ n: Int) -> [(TimeInterval, String)] {
        var script: [(TimeInterval, String)] = []
        for i in 0..<n {
            script.append((0.08, i == n - 1 ? "words." : "words"))
        }
        return script
    }

    // MARK: - Happy paths

    func testDigitHeadingsBecomeChapters() {
        let script = [(0.0, "Chapter"), (0.1, "1.")] + prose(30)
            + [(3.0, "Chapter"), (0.1, "2.")] + prose(30)
        let words = stream(script)
        let duration = (words.last?.end ?? 0) + 5
        let chapters = ChapterDetector.detect(fileWords: [words], fileStartTimes: [0],
                                              bookDuration: duration)
        XCTAssertEqual(chapters?.count, 2)
        XCTAssertEqual(chapters?[0].title, "Chapter 1")
        XCTAssertEqual(chapters?[1].title, "Chapter 2")
        // Durations tile the book: each ends where the next starts, last at bookDuration.
        XCTAssertEqual(chapters![0].start, 0, accuracy: 0.001)
        XCTAssertEqual(chapters![0].start + chapters![0].duration, chapters![1].start, accuracy: 0.001)
        XCTAssertEqual(chapters![1].start + chapters![1].duration, duration, accuracy: 0.001)
    }

    func testSpelledNumberWithSpokenTitle() {
        // Title hangs (0.8 s beat) before prose begins — accepted.
        let script = [(0.0, "Chapter"), (0.1, "Twenty-Three.")]
            + [(0.6, "The"), (0.08, "Iron"), (0.08, "Duke.")]
            + [(0.8, "then")] + prose(19)
            + [(2.5, "Chapter"), (0.1, "Twenty-Four.")] + prose(20)
        let words = stream(script)
        let chapters = ChapterDetector.detect(fileWords: [words], fileStartTimes: [0],
                                              bookDuration: (words.last?.end ?? 0) + 1)
        XCTAssertEqual(chapters?.count, 2)
        XCTAssertEqual(chapters?[0].title, "Chapter 23 — The Iron Duke")
        XCTAssertEqual(chapters?[1].title, "Chapter 24")
    }

    func testShortOpeningProseSentenceIsNotATitle() {
        // "He woke early." flows straight into more prose (no hang) → no title.
        let script = [(0.0, "Chapter"), (0.1, "5.")]
            + [(0.5, "He"), (0.08, "woke"), (0.08, "early.")]
            + prose(15)
            + [(2.5, "Chapter"), (0.1, "6.")] + prose(15)
        let words = stream(script)
        let chapters = ChapterDetector.detect(fileWords: [words], fileStartTimes: [0],
                                              bookDuration: (words.last?.end ?? 0) + 1)
        XCTAssertEqual(chapters?.map(\.title), ["Chapter 5", "Chapter 6"])
    }

    func testTwoWordSpelledNumber() {
        let script = [(0.0, "Chapter"), (0.1, "Twenty"), (0.1, "Three.")] + prose(10)
            + [(2.5, "Chapter"), (0.1, "Twenty"), (0.1, "Four.")] + prose(10)
        let words = stream(script)
        let chapters = ChapterDetector.detect(fileWords: [words], fileStartTimes: [0],
                                              bookDuration: (words.last?.end ?? 0) + 1)
        XCTAssertEqual(chapters?.map(\.title), ["Chapter 23", "Chapter 24"])
    }

    func testOrdinalAndDutch() {
        let script = [(0.0, "Hoofdstuk"), (0.1, "drieëntwintig.")] + prose(10)
            + [(2.5, "Chapter"), (0.1, "the"), (0.08, "Third.")] + prose(10)
        let words = stream(script)
        let chapters = ChapterDetector.detect(fileWords: [words], fileStartTimes: [0],
                                              bookDuration: (words.last?.end ?? 0) + 1)
        XCTAssertEqual(chapters?.map(\.title), ["Chapter 23", "Chapter 3"])
    }

    func testPartAndStandaloneSections() {
        let script = [(0.0, "Prologue.")] + prose(12)
            + [(3.0, "Part"), (0.1, "Two.")] + prose(12)
            + [(2.8, "Epilogue.")] + prose(12)
        let words = stream(script)
        let chapters = ChapterDetector.detect(fileWords: [words], fileStartTimes: [0],
                                              bookDuration: (words.last?.end ?? 0) + 1)
        XCTAssertEqual(chapters?.map(\.title), ["Prologue", "Part 2", "Epilogue"])
    }

    func testOpeningPrependedWhenFirstHeadingIsLate() {
        let script = prose(20)   // ~40 s of front matter at 0.33 s/word — not enough…
        let late = [(3.0, "Chapter"), (0.1, "1.")] + prose(10)
            + [(2.5, "Chapter"), (0.1, "2.")] + prose(10)
        let words = stream(script + late, from: 60)   // push everything past the threshold
        let chapters = ChapterDetector.detect(fileWords: [words], fileStartTimes: [0],
                                              bookDuration: (words.last?.end ?? 0) + 1)
        XCTAssertEqual(chapters?.first?.title, "Opening")
        XCTAssertEqual(chapters?.first?.start, 0)
        XCTAssertEqual(chapters?.count, 3)
    }

    func testMultiFileGlobalTimes() {
        let f0 = stream([(0.0, "Chapter"), (0.1, "1.")] + prose(10))
        let f1 = stream([(0.0, "Chapter"), (0.1, "2.")] + prose(10))
        let chapters = ChapterDetector.detect(fileWords: [f0, f1], fileStartTimes: [0, 600],
                                              bookDuration: 1200)
        XCTAssertEqual(chapters?.count, 2)
        XCTAssertEqual(chapters![1].start, 600, accuracy: 0.001)
    }

    // MARK: - Rejections (precision)

    func testProseChapterMentionIsRejected() {
        // "chapter" mid-sentence, no long pause before it.
        let script = prose(8) + [(0.08, "in"), (0.08, "chapter"), (0.08, "seven"), (0.08, "we"), (0.08, "saw")] + prose(8)
        let words = stream(script)
        XCTAssertNil(ChapterDetector.detect(fileWords: [words], fileStartTimes: [0], bookDuration: 100))
    }

    func testHeadingShapedProseAfterPauseIsRejected() {
        // Long pause, then prose that merely STARTS with "Chapter seven" — the
        // number flows straight into prose (no punctuation, no beat), so no match.
        let script = prose(10)
            + [(2.5, "Chapter"), (0.08, "seven"), (0.05, "ended"), (0.05, "badly"), (0.05, "for"), (0.05, "everyone")]
            + prose(10)
        let words = stream(script)
        XCTAssertNil(ChapterDetector.detect(fileWords: [words], fileStartTimes: [0], bookDuration: 100))
    }

    func testStandaloneKeywordInProseIsRejected() {
        // After a pause, prose beginning "Introduction to…" — keyword doesn't
        // terminate (no punct, no beat), so it's not a section heading.
        let script = prose(10)
            + [(2.5, "Introduction"), (0.05, "to"), (0.05, "the"), (0.05, "matter")]
            + prose(10)
        let words = stream(script)
        XCTAssertNil(ChapterDetector.detect(fileWords: [words], fileStartTimes: [0], bookDuration: 100))
    }

    func testSingleDetectionIsNotChaptering() {
        let script = [(0.0, "Chapter"), (0.1, "4.")] + prose(30)
        let words = stream(script)
        XCTAssertNil(ChapterDetector.detect(fileWords: [words], fileStartTimes: [0], bookDuration: 100))
    }

    func testChaoticNumbersBail() {
        var script: [(TimeInterval, String)] = []
        for n in [5, 2, 9, 3] {
            script += [(3.0, "Chapter"), (0.1, "\(n).")] + prose(160)   // spaced ≥ 45 s apart
        }
        let words = stream(script)
        XCTAssertNil(ChapterDetector.detect(fileWords: [words], fileStartTimes: [0],
                                            bookDuration: (words.last?.end ?? 0) + 1))
    }

    func testNumberResetAfterPartIsSane() {
        let headings: [ChapterDetector.Heading] = [1, 2, 3, 1, 2, 3].map {
            .init(kind: .chapter($0), start: 0, title: nil)
        }
        XCTAssertTrue(ChapterDetector.numbersAreSane(headings))
    }

    func testEchoWithinSpacingDropped() {
        let script = [(0.0, "Chapter"), (0.1, "2.")] + prose(10)
            + [(2.5, "Chapter"), (0.1, "2.")] + prose(10)          // echo ~7 s later
            + [(3.0, "Chapter"), (0.1, "3.")] + prose(10)          // distinct number → kept
        let words = stream(script)
        let chapters = ChapterDetector.detect(fileWords: [words], fileStartTimes: [0],
                                              bookDuration: (words.last?.end ?? 0) + 1)
        XCTAssertEqual(chapters?.map(\.title), ["Chapter 2", "Chapter 3"])
    }

    // MARK: - Number parser units

    func testSpelledValues() {
        XCTAssertEqual(ChapterDetector.spelledValue(["seven"]), 7)
        XCTAssertEqual(ChapterDetector.spelledValue(["twenty", "three"]), 23)
        XCTAssertEqual(ChapterDetector.spelledValue(["twenty-three"]), 23)
        XCTAssertEqual(ChapterDetector.spelledValue(["one", "hundred", "and", "four"]), 104)
        XCTAssertEqual(ChapterDetector.spelledValue(["drieentwintig"]), 23)
        XCTAssertEqual(ChapterDetector.spelledValue(["twaalf"]), 12)
        XCTAssertNil(ChapterDetector.spelledValue(["banana"]))
        XCTAssertNil(ChapterDetector.spelledValue([]))
    }
}
