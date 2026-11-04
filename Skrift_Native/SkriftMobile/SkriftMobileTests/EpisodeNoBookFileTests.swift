import XCTest
@testable import SkriftMobile

/// Q541 (Tuur 2026-10-16, FeedbackKit 7488094a): a podcast episode has no book file, so the Text
/// sheet's Level 2, its Add row and the once-per-book import prompt must not offer one. The rule is
/// `Audiobook.offersBookFile`, read off the existing `kind`; audiobooks are unchanged.
final class EpisodeNoBookFileTests: XCTestCase {

    private func book(kind: LibrarySourceKind?) -> Audiobook {
        var b = Audiobook(audioFilename: "a.m4b", title: "T", author: "A", duration: 100)
        b.kind = kind
        return b
    }

    func testEpisodeOffersNoBookFile() {
        XCTAssertFalse(book(kind: .episode).offersBookFile)
    }

    func testAudiobookOffersBookFile() {
        XCTAssertTrue(book(kind: .book).offersBookFile)
    }

    func testBookWrittenBeforeKindExistedStillOffersBookFile() {
        XCTAssertTrue(book(kind: nil).offersBookFile)
    }

    func testPDFAndArticleAreNotTouched() {
        XCTAssertTrue(book(kind: .pdf).offersBookFile)
        XCTAssertTrue(book(kind: .article).offersBookFile)
    }

    func testEpisodeSubtitleAndFooterNeverMentionTheBook() {
        let sub = BookTextDisplay.sheetSubtitle(coveredPercent: 0, transcribing: false,
                                                hasWaitingText: false, offersBookFile: false)
        let footer = BookTextDisplay.sheetFooter(transcribing: true, hasCoverage: false, offersBookFile: false)
        for line in [sub, footer] {
            XCTAssertFalse(line.lowercased().contains("book"), line)
            XCTAssertFalse(line.lowercased().contains("epub"), line)
            XCTAssertFalse(line.lowercased().contains("both"), line)
        }
    }

    func testReadAlongNudgeNamesTheEpisode() {
        XCTAssertEqual(book(kind: .episode).transcribeNoun, "episode")
        XCTAssertEqual(book(kind: .book).transcribeNoun, "book")
        XCTAssertEqual(book(kind: nil).transcribeNoun, "book")
    }

    func testAudiobookCopyIsUnchanged() {
        XCTAssertEqual(
            BookTextDisplay.sheetSubtitle(coveredPercent: 0, transcribing: false, hasWaitingText: false),
            "Give this audiobook words \u{2014} transcribe it, then add the real book for the published text.")
        XCTAssertEqual(BookTextDisplay.sheetFooter(transcribing: false, hasCoverage: false),
                       "Both run in the background \u{2014} you can keep listening.")
    }
}
