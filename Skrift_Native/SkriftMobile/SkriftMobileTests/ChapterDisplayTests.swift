import XCTest
@testable import SkriftMobile

/// Reader-facing chapter titles (device finding 2026-06-12): synthesized
/// multi-file chapter names showed the full source filename per row —
/// unreadable. The common prefix is stripped and numbered remainders
/// prettify to "Chapter N"; real m4b titles must pass through untouched.
final class ChapterDisplayTests: XCTestCase {

    // MARK: - The device finding: filename-derived chapter names

    func testFilenameChaptersPrettifyToChapterN() {
        // What importParts synthesizes today: filenameTitle(originalName),
        // underscores already spaces, extension already dropped.
        let raw = [
            "TheBeginningOfInfinity chapter 01",
            "TheBeginningOfInfinity chapter 02",
            "TheBeginningOfInfinity chapter 10",
        ]
        XCTAssertEqual(ChapterDisplay.displayTitles(raw),
                       ["Chapter 1", "Chapter 2", "Chapter 10"])
    }

    func testRawFilenamesWithUnderscoresAndExtension() {
        let raw = ["MyBook_chapter_01.mp3", "MyBook_chapter_02.mp3"]
        XCTAssertEqual(ChapterDisplay.displayTitles(raw), ["Chapter 1", "Chapter 2"])
    }

    func testDigitsOnlyRemaindersBecomeChapterN() {
        // The "chapter" word itself lands inside the common prefix — the
        // remainder is bare digits and still must read as a chapter.
        let raw = ["Infinity - Chapter 01", "Infinity - Chapter 02", "Infinity - Chapter 03"]
        XCTAssertEqual(ChapterDisplay.displayTitles(raw),
                       ["Chapter 1", "Chapter 2", "Chapter 3"])
    }

    func testNamedRemaindersKeepTheirNames() {
        let raw = ["BOI 01 - Creation.mp3", "BOI 02 - The Spark.mp3"]
        XCTAssertEqual(ChapterDisplay.displayTitles(raw),
                       ["01 - Creation", "02 - The Spark"])
    }

    // MARK: - Real titles must never be mangled

    func testRealTitlesSharingLettersAreUntouched() {
        // LCP "Cre" ends mid-word — no separator boundary, nothing stripped.
        let raw = ["Creation", "Crescendo"]
        XCTAssertEqual(ChapterDisplay.displayTitles(raw), ["Creation", "Crescendo"])
    }

    func testRealTitlesSharingAWordKeepIt() {
        // Remainders carry no digits — these are real names, not numbered
        // parts; "The " must NOT be stripped.
        let raw = ["The Spark", "The Creation"]
        XCTAssertEqual(ChapterDisplay.displayTitles(raw), ["The Spark", "The Creation"])
    }

    func testEmbeddedNumberedTitlesStayStable() {
        let raw = ["Chapter 1", "Chapter 2", "Chapter 12"]
        XCTAssertEqual(ChapterDisplay.displayTitles(raw),
                       ["Chapter 1", "Chapter 2", "Chapter 12"])
    }

    func testIdenticalTitlesFallThroughUnchanged() {
        let raw = ["Book one", "Book one"]
        XCTAssertEqual(ChapterDisplay.displayTitles(raw), ["Book one", "Book one"])
    }

    // MARK: - Edges

    func testSingleChapterStillPrettifies() {
        XCTAssertEqual(ChapterDisplay.displayTitles(["chapter_01"]), ["Chapter 1"])
        XCTAssertEqual(ChapterDisplay.displayTitles(["Prologue"]), ["Prologue"])
    }

    func testEmptyAndBlankFallBackToIndex() {
        XCTAssertEqual(ChapterDisplay.displayTitles([]), [])
        XCTAssertEqual(ChapterDisplay.displayTitles(["   "]), ["Chapter 1"])
    }

    func testOnlyKnownAudioExtensionsAreStripped() {
        XCTAssertEqual(ChapterDisplay.stripAudioExtension("part_01.mp3"), "part_01")
        XCTAssertEqual(ChapterDisplay.stripAudioExtension("Part.Two"), "Part.Two")
    }

    func testBoundaryTrimNeverSplitsANumber() {
        // Raw LCP of "ch01"/"ch02" is "ch0" — trimming must not leave the
        // shared zero stranded inside the prefix (there's no separator at
        // all, so nothing is stripped and the full names survive).
        XCTAssertEqual(ChapterDisplay.boundaryTrimmed("ch0"), "")
        XCTAssertEqual(ChapterDisplay.displayTitles(["ch01", "ch02"]), ["ch01", "ch02"])
        // With a separator the trim keeps it: "book_ch0" → "book_".
        XCTAssertEqual(ChapterDisplay.boundaryTrimmed("book_ch0"), "book_")
    }

    func testLongestCommonPrefix() {
        XCTAssertEqual(ChapterDisplay.longestCommonPrefix(["abc", "abd"]), "ab")
        XCTAssertEqual(ChapterDisplay.longestCommonPrefix(["x"]), "x")
        XCTAssertEqual(ChapterDisplay.longestCommonPrefix(["a", "b"]), "")
        XCTAssertEqual(ChapterDisplay.longestCommonPrefix([]), "")
    }

    // MARK: - Through the Audiobook surface (menu / chapter line / capture)

    private func book(chapterTitles: [String]) -> Audiobook {
        var chapters: [AudiobookChapter] = []
        for (i, t) in chapterTitles.enumerated() {
            chapters.append(AudiobookChapter(title: t, start: Double(i) * 100, duration: 100))
        }
        return Audiobook(
            audioFilename: "book.m4b", title: "Infinity", author: "Deutsch",
            duration: Double(chapterTitles.count) * 100, chapters: chapters
        )
    }

    func testChapterLineUsesDisplayTitleWithoutRepeatingTheIndex() {
        let b = book(chapterTitles: ["Infinity chapter 01", "Infinity chapter 02"])
        // Display title "Chapter 2" would just repeat "Chapter 2 of 2".
        XCTAssertEqual(b.chapterLine(at: 150), "Chapter 2 of 2")
        XCTAssertEqual(b.shortChapterLabel(at: 150), "ch. 2")
    }

    func testChapterLineKeepsRealTitles() {
        let b = book(chapterTitles: ["The Spark", "The Creation"])
        XCTAssertEqual(b.chapterLine(at: 150), "Chapter 2 of 2 — The Creation")
        XCTAssertEqual(b.shortChapterLabel(at: 0), "ch. 1 — The Spark")
    }

    func testAttributionNumberStaysTheIndex() {
        let b = book(chapterTitles: ["Infinity chapter 05", "Infinity chapter 06"])
        // The C2 metadata number is positional — NOT parsed from the name.
        XCTAssertEqual(b.chapterNumberString(at: 150), "2")
    }
}
