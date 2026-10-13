import XCTest
@testable import SkriftMobile

/// Q356 (D177, absorbs Q297): the note → source jump-back works from PDF capture notes (to the
/// page) and podcast capture notes (to the time), and never moves the source's own place.
final class JumpBackNonBookTests: XCTestCase {

    private func source(_ title: String, kind: LibrarySourceKind?, duration: TimeInterval,
                        position: TimeInterval) -> Audiobook {
        var b = Audiobook(audioFilename: "a.mp3", title: title, author: "NRC Het Uur",
                          duration: duration, position: position)
        b.kind = kind
        return b
    }

    private func note(bookID: UUID, chapter: String?, position: Double?, quote: Bool = true) -> Memo {
        Memo.make(id: UUID(), recordedAt: Date(), syncStatus: .waiting,
                  transcript: quote ? "> a quote\n\nmy words" : "my words", transcriptStatus: .done,
                  metadata: MemoMetadata(bookTitle: "T", bookChapter: chapter, bookID: bookID, bookPosition: position))
    }

    // MARK: - Where the jump goes

    func testAPdfNoteJumpsToThePage() throws {
        let pdf = source("GFR", kind: .pdf, duration: 18, position: 9)
        let memo = note(bookID: pdf.id, chapter: "p. 4", position: 4)
        let target = try XCTUnwrap(BookNotesJoin.jumpTarget(for: memo))
        XCTAssertEqual(BookNotesJoin.route(for: target, source: pdf), .page(4))
        XCTAssertEqual(BookNotesJoin.jumpLabel(for: .page(4)), "Back to it at p. 4 in Library")
    }

    func testAPodcastNoteJumpsToTheTime() throws {
        let ep = source("Joris Luyendijk", kind: .episode, duration: 3713, position: 100)
        let memo = note(bookID: ep.id, chapter: nil, position: 1421)
        let target = try XCTUnwrap(BookNotesJoin.jumpTarget(for: memo))
        XCTAssertEqual(BookNotesJoin.route(for: target, source: ep), .time(1421))
        XCTAssertEqual(BookNotesJoin.jumpLabel(for: .time(1421)), "Back to it at 23:41 in Library")
    }

    func testABookNoteStillJumpsToTheTime() throws {
        let b = source("Four Thousand Weeks", kind: nil, duration: 20_000, position: 0)
        let target = try XCTUnwrap(BookNotesJoin.jumpTarget(for: note(bookID: b.id, chapter: "7", position: 4325)))
        XCTAssertEqual(BookNotesJoin.route(for: target, source: b), .time(4325))
    }

    func testAPdfPageOutsideTheDocumentIsClamped() throws {
        let pdf = source("GFR", kind: .pdf, duration: 18, position: 1)
        XCTAssertEqual(BookNotesJoin.route(for: .init(bookID: pdf.id, position: 40), source: pdf), .page(18))
        XCTAssertEqual(BookNotesJoin.route(for: .init(bookID: pdf.id, position: 0), source: pdf), .page(1))
    }

    func testANoteSentFromASourceJumpsBackTooWithoutAQuote() throws {
        let ep = source("Joris Luyendijk", kind: .episode, duration: 3713, position: 0)
        let memo = note(bookID: ep.id, chapter: nil, position: 1421, quote: false)
        XCTAssertNil(memo.captureQuote)
        let target = try XCTUnwrap(BookNotesJoin.jumpTarget(for: memo))
        XCTAssertEqual(BookNotesJoin.route(for: target, source: ep), .time(1421))
    }

    // MARK: - The source's own place is not moved (D177)

    func testAPdfJumpBackDoesNotSaveThePage() {
        XCTAssertFalse(LibraryPDF.savesPage(jumpBackPage: 4, ready: true), "a jump-back reader never moves the kept page")
        XCTAssertTrue(LibraryPDF.savesPage(jumpBackPage: nil, ready: true))
        XCTAssertFalse(LibraryPDF.savesPage(jumpBackPage: nil, ready: false), "nothing is saved before the first layout")
    }

    func testAPodcastJumpBackSessionDoesNotPersistProgress() {
        XCTAssertFalse(BookNotesJoin.shouldPersistProgress(jumpBackSession: true))
    }

    func testTheToastNamesTheKindOfSource() {
        XCTAssertEqual(BookNotesJoin.jumpToast(title: "Het Uur", position: 1421, kind: .episode),
                       "Opens Het Uur at 23:41. The episode\u{2019}s own place is not moved.")
        XCTAssertEqual(BookNotesJoin.jumpToast(title: "Some Book", position: 4325, kind: .book),
                       BookNotesJoin.jumpToast(bookTitle: "Some Book", position: 4325),
                       "a book keeps today's words")
    }

    // MARK: - The notes sheet's meta line

    func testAPodcastNoteMetaLineShowsTheTime() {
        let memo = note(bookID: UUID(), chapter: nil, position: 1421)
        XCTAssertTrue(BookNotesJoin.metaLine(for: memo).hasPrefix("23:41 · "), BookNotesJoin.metaLine(for: memo))
    }

    func testAPdfNoteMetaLineShowsThePageOnly() {
        let memo = note(bookID: UUID(), chapter: "p. 4", position: 4)
        let line = BookNotesJoin.metaLine(for: memo)
        XCTAssertTrue(line.hasPrefix("p. 4 · "), line)
        XCTAssertFalse(line.contains("0:04"), line)
    }
}
