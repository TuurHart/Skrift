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
        // 23 → 3 is a numbered restart → the book separator announces it.
        XCTAssertEqual(chapters?.map(\.title), ["Chapter 23", "Book 2", "Chapter 3"])
    }

    func testPartAndStandaloneSections() {
        // Realistic spacing — the duration prior vetoes seconds-long "chapters".
        let script = [(0.0, "Prologue.")] + prose(900)
            + [(3.0, "Part"), (0.1, "Two.")] + prose(900)
            + [(2.8, "Epilogue.")] + prose(900)
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

    // MARK: - v2 styles: LibriVox, bare numbers, title-only

    func testLibriVoxHeaderFormat() {
        // "Chapter N of <book title>." flows without a pause after the number —
        // the of-continuation must accept it (and not treat the book title as
        // a chapter title).
        let intro: [(TimeInterval, String)] = [
            (0.0, "Chapter"), (0.1, "4"), (0.08, "of"), (0.08, "Pride"), (0.08, "and"), (0.08, "Prejudice."),
            (0.5, "This"), (0.08, "is"), (0.08, "a"), (0.08, "LibriVox"), (0.08, "recording."),
        ]
        let script = intro + prose(20)
            + [(3.0, "Chapter"), (0.1, "5"), (0.08, "of"), (0.08, "Pride"), (0.08, "and"), (0.08, "Prejudice.")]
            + prose(20)
        let words = stream(script)
        let chapters = ChapterDetector.detect(fileWords: [words], fileStartTimes: [0],
                                              bookDuration: (words.last?.end ?? 0) + 1)
        XCTAssertEqual(chapters?.map(\.title), ["Chapter 4", "Chapter 5"])
    }

    func testBareNumberHeadings() {
        // Kleon-style: "<number>. <title>." with no "chapter" keyword. Three
        // ascending, ~5 min apart → bare-number style wins.
        func heading(_ n: String, _ title: [String]) -> [(TimeInterval, String)] {
            var out: [(TimeInterval, String)] = [(3.0, n)]
            for (i, w) in title.enumerated() {
                out.append((i == 0 ? 0.6 : 0.08, w))
            }
            return out
        }
        var script: [(TimeInterval, String)] = prose(6)
        script += heading("Seven.", ["Don't", "turn", "into", "human", "spam."]) + [(0.8, "so")] + prose(900)
        script += heading("Eight.", ["Learn", "to", "take", "a", "punch."]) + [(0.8, "so")] + prose(900)
        script += heading("Nine.", ["Sell", "out."]) + [(0.8, "so")] + prose(300)
        let words = stream(script)
        let chapters = ChapterDetector.detect(fileWords: [words], fileStartTimes: [0],
                                              bookDuration: (words.last?.end ?? 0) + 1)
        XCTAssertEqual(chapters?.map(\.title),
                       ["Chapter 7 — Don't turn into human spam",
                        "Chapter 8 — Learn to take a punch", "Chapter 9 — Sell out"])
    }

    func testCountingSceneIsNotChapters() {
        // Fiction counting: standalone numbers seconds apart — spacing guard
        // keeps one, quorum fails, nothing detected.
        let script = prose(10)
            + [(2.5, "One."), (2.5, "Two."), (2.5, "Three."), (2.5, "Four.")]
            + prose(10)
        let words = stream(script)
        XCTAssertNil(ChapterDetector.detect(fileWords: [words], fileStartTimes: [0],
                                            bookDuration: (words.last?.end ?? 0) + 1))
    }

    func testTitleOnlyBookDetected() {
        // Digital-Minimalism style: no numbers, no keywords — just short
        // hanging titles after real silences, consistently. Six of them,
        // ~5 min apart, and the book's biggest gaps are exactly these sites.
        func chapter(_ title: [String]) -> [(TimeInterval, String)] {
            var out: [(TimeInterval, String)] = []
            for (i, w) in title.enumerated() { out.append((i == 0 ? 3.0 : 0.08, w)) }
            out.append((0.8, "so"))
            return out + prose(900)
        }
        var script: [(TimeInterval, String)] = []
        script += chapter(["A", "Lopsided", "Arms", "Race."])
        script += chapter(["Digital", "Minimalism."])
        script += chapter(["The", "Digital", "Declutter."])
        script += chapter(["Spend", "Time", "Alone."])
        script += chapter(["Don't", "Click", "Like."])
        script += chapter(["Reclaim", "Leisure."])
        let words = stream(script)
        let chapters = ChapterDetector.detect(fileWords: [words], fileStartTimes: [0],
                                              bookDuration: (words.last?.end ?? 0) + 1)
        XCTAssertEqual(chapters?.count, 6)
        XCTAssertEqual(chapters?.first?.title, "A Lopsided Arms Race")
        XCTAssertEqual(chapters?.last?.title, "Reclaim Leisure")
    }

    func testStingHeavyBookRejectsTitleOnly() {
        // A gift-book production: it HAS a few short hanging quotes after
        // gaps, but its BIGGEST silences are music stings flowing into long
        // prose — dominance fails, no chapters invented.
        func quote(_ text: [String]) -> [(TimeInterval, String)] {
            var out: [(TimeInterval, String)] = []
            for (i, w) in text.enumerated() { out.append((i == 0 ? 2.5 : 0.08, w)) }
            out.append((0.8, "so"))
            return out
        }
        var script: [(TimeInterval, String)] = prose(6)
        for _ in 0..<6 {
            script += quote(["Keep", "going", "and", "make", "things."]) + prose(420)
            script += [(12.0, "meanwhile")] + prose(420)   // sting into flowing prose
            script += [(13.0, "later")] + prose(420)       // another sting
        }
        let words = stream(script)
        XCTAssertNil(ChapterDetector.detect(fileWords: [words], fileStartTimes: [0],
                                            bookDuration: (words.last?.end ?? 0) + 1))
    }

    func testBookSeparatorInsertedAtNumberReset() {
        // A trilogy in one import: numbers restart where the next work begins —
        // a "Book 2" separator explains the restart.
        var script: [(TimeInterval, String)] = [(0.0, "Seven.")]
        script += prose(900)
        script += [(3.0, "Eight.")]; script += prose(900)
        script += [(3.0, "One.")]; script += prose(900)
        script += [(3.0, "Two.")]; script += prose(900)
        let words = stream(script)
        let chapters = ChapterDetector.detect(fileWords: [words], fileStartTimes: [0],
                                              bookDuration: (words.last?.end ?? 0) + 1)
        XCTAssertEqual(chapters?.map(\.title),
                       ["Chapter 7", "Chapter 8", "Book 2", "Chapter 1", "Chapter 2"])
        // The separator sits exactly at the resetting chapter's start, and is
        // marked display-only.
        XCTAssertEqual(chapters?[2].start, chapters?[3].start)
        XCTAssertEqual(chapters?[2].isSeparator, true)
        XCTAssertNil(chapters?[3].isSeparator)
    }

    func testSeparatorExcludedFromChapterSemantics() {
        var book = Audiobook(audioFilename: "b.mp3", title: "Trilogy", author: "A", duration: 400)
        book.detectedChapters = [
            AudiobookChapter(title: "Chapter 7", start: 0, duration: 100),
            AudiobookChapter(title: "Chapter 8", start: 100, duration: 100),
            AudiobookChapter(title: "Book 2", start: 200, duration: 0, isSeparator: true),
            AudiobookChapter(title: "Chapter 1", start: 200, duration: 200),
        ]
        // Counting/navigation skip the separator…
        XCTAssertEqual(book.playableChapters.count, 3)
        XCTAssertEqual(book.chapterIndex(at: 250), 2)              // Chapter 1, not the divider
        XCTAssertEqual(book.chapter(at: 250)?.title, "Chapter 1")
        XCTAssertEqual(book.chapterLine(at: 250), "Chapter 1  ·  3 of 3")
        XCTAssertEqual(book.chapterNumberString(at: 250), "1")     // announced number
        // …but the sheet's row list still shows it.
        XCTAssertEqual(book.effectiveChapters.count, 4)
        XCTAssertEqual(book.displayChapterTitles[2], "Book 2")
    }

    func testNoSeparatorWhenPartHeadingMarksTheReset() {
        // A real announced "Part Two" already explains the restart — no extra entry.
        var script: [(TimeInterval, String)] = [(0.0, "Chapter"), (0.1, "1.")]
        script += prose(900)
        script += [(3.0, "Chapter"), (0.1, "2.")]; script += prose(900)
        script += [(3.0, "Part"), (0.1, "Two."), (0.8, "so")]; script += prose(100)
        script += [(2.5, "Chapter"), (0.1, "1.")]; script += prose(900)
        let words = stream(script)
        let chapters = ChapterDetector.detect(fileWords: [words], fileStartTimes: [0],
                                              bookDuration: (words.last?.end ?? 0) + 1)
        XCTAssertEqual(chapters?.map(\.title),
                       ["Chapter 1", "Chapter 2", "Part 2", "Chapter 1"])
    }

    func testSentenceAnchoredNumbersInZeroGapProduction() {
        // Kleon-style: NO silence before headings — the previous sentence's
        // period is the anchor ("…their example. Two. Think process not product.").
        func heading(_ n: String, _ title: [String]) -> [(TimeInterval, String)] {
            var out: [(TimeInterval, String)] = [(0.08, n)]
            for w in title { out.append((0.08, w)) }
            return out
        }
        var script: [(TimeInterval, String)] = prose(6)   // ends with "words."
        script += heading("One.", ["Steal", "like", "an", "artist."]); script += prose(900)
        script += heading("Two.", ["Think", "process", "not", "product."]); script += prose(900)
        script += heading("Three.", ["Tell", "good", "stories."]); script += prose(900)
        let words = stream(script)
        let chapters = ChapterDetector.detect(fileWords: [words], fileStartTimes: [0],
                                              bookDuration: (words.last?.end ?? 0) + 1)
        XCTAssertEqual(chapters?.map(\.title),
                       ["Chapter 1 — Steal like an artist",
                        "Chapter 2 — Think process not product",
                        "Chapter 3 — Tell good stories"])
    }

    func testMidSentenceNumbersStayRejected() {
        // "a nine to five job." / "when he saw one." — numbers mid-flow never
        // follow a finished sentence, so the anchor rejects them.
        var script: [(TimeInterval, String)] = prose(6)
        script += [(0.08, "with"), (0.08, "a"), (0.08, "nine"), (0.08, "to"),
                   (0.08, "five"), (0.08, "job.")]
        script += prose(400)
        script += [(0.08, "when"), (0.08, "he"), (0.08, "saw"), (0.08, "one."),
                   (0.08, "He"), (0.08, "was"), (0.08, "not"), (0.08, "amused.")]
        script += prose(400)
        let words = stream(script)
        XCTAssertNil(ChapterDetector.detect(fileWords: [words], fileStartTimes: [0],
                                            bookDuration: (words.last?.end ?? 0) + 1))
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
