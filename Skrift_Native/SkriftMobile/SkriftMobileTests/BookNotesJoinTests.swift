import XCTest
@testable import SkriftMobile

/// D127 / Q151: count and open a book's capture notes through `MemoMetadata.bookID`, and
/// resolve the note → book jump-back through `bookPosition`.
@MainActor
final class BookNotesJoinTests: XCTestCase {

    private let bookA = UUID()
    private let bookB = UUID()

    private func capture(book: UUID?, position: Double? = 100, chapter: String? = "4",
                         at date: Date = Date(), deleted: Date? = nil,
                         id: UUID = UUID(), transcript: String = "> A quote.\n\nMy ramble.") -> Memo {
        var meta = MemoMetadata()
        meta.bookTitle = "Some Book"
        meta.bookChapter = chapter
        meta.bookID = book
        meta.bookPosition = position
        return Memo.make(id: id, recordedAt: date, transcript: transcript, deletedAt: deleted, metadata: meta)
    }

    func testCountsGroupByBookID() {
        let memos = [capture(book: bookA), capture(book: bookA), capture(book: bookB),
                     Memo.make(transcript: "plain voice memo")]
        let counts = BookNotesJoin.counts(in: memos)
        XCTAssertEqual(counts[bookA], 2)
        XCTAssertEqual(counts[bookB], 1)
        XCTAssertEqual(counts.count, 2, "a memo with no bookID is nobody's note")
    }

    func testTrashedNotesDoNotCount() {
        let memos = [capture(book: bookA), capture(book: bookA, deleted: Date())]
        XCTAssertEqual(BookNotesJoin.counts(in: memos)[bookA], 1)
        XCTAssertEqual(BookNotesJoin.notes(forBook: bookA, in: memos).count, 1)
    }

    func testCloudKitCloneRowsCountOnce() {
        let id = UUID()
        let memos = [capture(book: bookA, id: id), capture(book: bookA, id: id)]
        XCTAssertEqual(BookNotesJoin.counts(in: memos)[bookA], 1)
    }

    func testNotesAreThisBooksOnlyNewestFirst() {
        let old = capture(book: bookA, at: Date(timeIntervalSince1970: 1_000))
        let new = capture(book: bookA, at: Date(timeIntervalSince1970: 9_000))
        let other = capture(book: bookB, at: Date(timeIntervalSince1970: 5_000))
        let notes = BookNotesJoin.notes(forBook: bookA, in: [old, other, new])
        XCTAssertEqual(notes.map(\.id), [new.id, old.id])
    }

    func testJumpTargetNeedsBookIDAndPosition() {
        XCTAssertEqual(BookNotesJoin.jumpTarget(for: capture(book: bookA, position: 4321.5)),
                       BookNotesJoin.JumpTarget(bookID: bookA, position: 4321.5))
        XCTAssertNil(BookNotesJoin.jumpTarget(for: capture(book: nil)), "no join key")
        XCTAssertNil(BookNotesJoin.jumpTarget(for: capture(book: bookA, position: nil)), "no stored place")
        XCTAssertNil(BookNotesJoin.jumpTarget(for: capture(book: bookA, position: -1)))
        XCTAssertNil(BookNotesJoin.jumpTarget(for: Memo.make(transcript: "plain")))
    }

    func testJumpLabelAndMetaLineMatchTheMock() {
        XCTAssertEqual(BookNotesJoin.jumpLabel(position: 4325), "Back to it at 1:12:05 in Library")
        XCTAssertEqual(BookNotesJoin.jumpLabel(position: 1421), "Back to it at 23:41 in Library")
        let memo = capture(book: bookA, position: 4325, chapter: "7",
                           at: Date(timeIntervalSince1970: 1_758_412_800))   // Sun 21 Sep 2025 UTC
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(BookNotesJoin.metaLine(for: memo, calendar: cal), "ch 7 · 1:12:05 · Sun 21 Sep")
        XCTAssertEqual(BookNotesJoin.accessibilityLabel(count: 1), "1 note from this book")
        XCTAssertEqual(BookNotesJoin.accessibilityLabel(count: 5), "5 notes from this book")
    }

    /// A book that is no longer in the library can't be jumped to: false, nothing opened.
    func testJumpToAMissingBookReturnsFalse() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("BookNotesJoin-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AudiobookLibraryStore(directory: dir)
        let session = AudiobookSession(store: store)
        XCTAssertFalse(BookNotesJoin.jump(to: .init(bookID: bookA, position: 10), store: store, session: session))
        XCTAssertFalse(session.isActive)
    }
}
