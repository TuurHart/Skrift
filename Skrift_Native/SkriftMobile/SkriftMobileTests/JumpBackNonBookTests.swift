import XCTest
@testable import SkriftMobile

/// Q297 / D177: the book jump-back (Q151/Q273) also appears on non-book notes that carry a source
/// position: a podcast clip (an audio library item + seconds, the book join) and a PDF capture
/// (its own file + a page). The book's own resume place is never moved by either.
@MainActor
final class JumpBackNonBookTests: XCTestCase {

    private func pdfNote(page: Int?, fileName: String = "Lease.pdf", type: ShareContentType = .file) -> Memo {
        var meta = MemoMetadata()
        meta.sourcePage = page
        let shared = SharedContent(type: type, filePath: "file_x.pdf", fileName: fileName)
        return Memo.make(transcript: "Look at the notice clause.", metadata: meta, sharedContent: shared)
    }

    private func podcastClip(position: Double?) -> Memo {
        var meta = MemoMetadata()
        meta.bookID = UUID()
        meta.bookPosition = position
        // A clip kept as plain words: no "> quote" block, so only the position makes it jump-able.
        return Memo.make(transcript: "He says the grief is for a world that is gone.", metadata: meta)
    }

    // MARK: resolving the target

    func testPodcastClipWithoutQuoteBlockResolvesToAnAudioTarget() {
        let clip = podcastClip(position: 1812)
        guard case .audio(let t)? = SourceJump.target(for: clip) else { return XCTFail("no audio target") }
        XCTAssertEqual(t.position, 1812)
        XCTAssertEqual(t.bookID, clip.metadata?.bookID)
    }

    func testPDFNoteWithAPageResolvesToThatPage() {
        XCTAssertEqual(SourceJump.target(for: pdfNote(page: 12)), .pdf(page: 12))
    }

    func testNotesWithoutASourcePositionHaveNoJumpBack() {
        XCTAssertNil(SourceJump.target(for: Memo.make(transcript: "plain voice memo")))
        XCTAssertNil(SourceJump.target(for: podcastClip(position: nil)))
        XCTAssertNil(SourceJump.target(for: pdfNote(page: nil)), "a PDF note that never stored a page")
    }

    func testBadPagesAndNonPDFFilesAreRefused() {
        XCTAssertNil(SourceJump.target(for: pdfNote(page: 0)), "pages count from 1")
        XCTAssertNil(SourceJump.target(for: pdfNote(page: -3)))
        XCTAssertNil(SourceJump.target(for: pdfNote(page: 2, fileName: "Notes.docx")), "only a PDF has pages")
        XCTAssertNil(SourceJump.target(for: pdfNote(page: 2, type: .text)), "a text share is not a file")
    }

    func testBookQuoteStillResolvesToTheBookTarget() {
        var meta = MemoMetadata()
        let id = UUID()
        meta.bookID = id
        meta.bookPosition = 4325
        let memo = Memo.make(transcript: "> A quote.\n\nMy ramble.", metadata: meta)
        XCTAssertEqual(SourceJump.target(for: memo),
                       .audio(BookNotesJoin.JumpTarget(bookID: id, position: 4325)))
    }

    // MARK: label

    func testLabelsKeepTheBookWordingForAudioAndNameThePageForPDF() {
        XCTAssertEqual(SourceJump.label(for: .audio(.init(bookID: UUID(), position: 4325))),
                       "Back to it at 1:12:05 in Library")
        XCTAssertEqual(SourceJump.label(for: .pdf(page: 12)), "Back to it on page 12")
    }

    // MARK: the path is the book's: the resume place is untouched

    func testAnAudioJumpUsesTheSameNonPersistingSession() {
        XCTAssertFalse(BookNotesJoin.shouldPersistProgress(jumpBackSession: true))
        let missing = BookNotesJoin.JumpTarget(bookID: UUID(), position: 10)
        XCTAssertEqual(SourceJump.perform(.audio(missing), for: podcastClip(position: 10)),
                       .audioUnavailable, "an episode that isn't in the library says so, no dead player")
        XCTAssertFalse(AudiobookSession.shared.isJumpBack, "a refused jump never arms the session")
    }

    func testAPDFJumpOpensTheNotesFileAtThePageAndLeavesTheSessionAlone() {
        let before = AudiobookSession.shared.book?.id
        let outcome = SourceJump.perform(.pdf(page: 5), for: pdfNote(page: 5))
        guard case .openPDF(let url, let page) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(page, 5)
        XCTAssertEqual(url.lastPathComponent, "file_x.pdf")
        XCTAssertEqual(AudiobookSession.shared.book?.id, before)
        XCTAssertFalse(AudiobookSession.shared.isJumpBack)
    }

    func testPageIsClampedToTheDocumentWhenItsLengthIsKnown() {
        XCTAssertEqual(SourceJump.clampedPageIndex(page: 12, pageCount: 8), 7)
        XCTAssertEqual(SourceJump.clampedPageIndex(page: 1, pageCount: 8), 0)
        XCTAssertEqual(SourceJump.clampedPageIndex(page: 3, pageCount: 0), 0, "an unreadable document has no pages")
    }
}
