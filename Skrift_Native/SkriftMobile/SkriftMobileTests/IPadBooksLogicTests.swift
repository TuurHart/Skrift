import XCTest
@testable import SkriftMobile

/// Pure logic added for the iPad Books lane (shelf tile formatting + the
/// chapter/rail index mapping). Host-less — no UI, no AVFoundation.
final class IPadBooksLogicTests: XCTestCase {

    // MARK: - BookShelfTile.progressLabel(for:)

    func testProgressLabelWithoutChaptersShowsBarePercentage() {
        let book = Audiobook(
            files: ["book.m4b"], fileDurations: [1000],
            title: "T", author: "A", duration: 1000, chapters: [],
            position: 400   // 40%, timeLeft 600 — well clear of the finished tail
        )
        XCTAssertEqual(BookShelfTile.progressLabel(for: book), "40%")
    }

    func testProgressLabelWithChaptersShowsChapterAndPercentage() {
        let chapters = [
            AudiobookChapter(title: "One", start: 0, duration: 300),
            AudiobookChapter(title: "Two", start: 300, duration: 300),
            AudiobookChapter(title: "Three", start: 600, duration: 400),
        ]
        let book = Audiobook(
            files: ["book.m4b"], fileDurations: [1000],
            title: "T", author: "A", duration: 1000, chapters: chapters,
            position: 620   // inside chapter index 2 (0-based) — "ch 3"; 62%
        )
        XCTAssertEqual(BookShelfTile.progressLabel(for: book), "ch 3 · 62%")
    }

    func testProgressLabelPastFinishedTailReadsFinished() {
        let book = Audiobook(
            files: ["book.m4b"], fileDurations: [1000],
            title: "T", author: "A", duration: 1000,
            position: 985   // timeLeft 15 <= finishedTail(30)
        )
        XCTAssertEqual(BookShelfTile.progressLabel(for: book), "finished")
    }

    /// The threshold is inclusive (`<=`), matching `BookStatusFilter.finished`
    /// exactly — the shelf and the status-filter chip must never disagree
    /// about whether a book counts as done.
    func testProgressLabelAtExactFinishedTailBoundaryReadsFinished() {
        let book = Audiobook(
            files: ["book.m4b"], fileDurations: [1000],
            title: "T", author: "A", duration: 1000,
            position: 970   // timeLeft == finishedTail exactly
        )
        XCTAssertEqual(BookShelfTile.progressLabel(for: book), "finished")
    }

    /// A degenerate (zero-duration) record must never crash or fabricate a
    /// chapter — no-bad-info: falls back to a plain "0%".
    func testProgressLabelWithZeroDurationNeverCrashes() {
        let book = Audiobook(files: [], fileDurations: [], title: "Empty", author: "A", duration: 0)
        XCTAssertEqual(BookShelfTile.progressLabel(for: book), "0%")
    }

    // MARK: - chapterPlayableIndices(_:) — sheet/rail current-highlight mapping

    func testChapterPlayableIndicesSkipsSeparators() {
        let chapters = [
            AudiobookChapter(title: "Book 1", start: 0, duration: 0, isSeparator: true),
            AudiobookChapter(title: "Ch 1", start: 0, duration: 100),
            AudiobookChapter(title: "Ch 2", start: 100, duration: 100),
            AudiobookChapter(title: "Book 2", start: 200, duration: 0, isSeparator: true),
            AudiobookChapter(title: "Ch 1", start: 200, duration: 100),
        ]
        let book = Audiobook(
            files: ["a.m4b"], fileDurations: [300],
            title: "T", author: "A", duration: 300, chapters: chapters
        )
        XCTAssertEqual(chapterPlayableIndices(book), [nil, 0, 1, nil, 2])
    }

    func testChapterPlayableIndicesWithNoSeparatorsIsSequential() {
        let chapters = (0..<4).map { AudiobookChapter(title: "Ch \($0)", start: TimeInterval($0) * 100, duration: 100) }
        let book = Audiobook(
            files: ["a.m4b"], fileDurations: [400],
            title: "T", author: "A", duration: 400, chapters: chapters
        )
        XCTAssertEqual(chapterPlayableIndices(book), [0, 1, 2, 3])
    }

    func testChapterPlayableIndicesOnBookWithNoChaptersIsEmpty() {
        let book = Audiobook(files: ["a.m4b"], fileDurations: [400], title: "T", author: "A", duration: 400)
        XCTAssertEqual(chapterPlayableIndices(book), [])
    }
}
