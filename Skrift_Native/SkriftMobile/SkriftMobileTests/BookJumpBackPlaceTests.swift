import XCTest
@testable import SkriftMobile

/// Q273 / D127: a note's jump-back plays from the note's place without moving the book's own
/// resume place (Q6 mock: "The book's own place is not moved").
@MainActor
final class BookJumpBackPlaceTests: XCTestCase {

    func testJumpBackSessionDoesNotPersistProgress() {
        XCTAssertFalse(BookNotesJoin.shouldPersistProgress(jumpBackSession: true))
    }

    func testNormalSessionPersistsProgress() {
        XCTAssertTrue(BookNotesJoin.shouldPersistProgress(jumpBackSession: false))
    }

    func testToastSaysThePlaceIsNotMoved() {
        let t = BookNotesJoin.jumpToast(bookTitle: "Some Book", position: 4325)
        XCTAssertEqual(t, "Opens Some Book at 1:12:05. The book\u{2019}s own place is not moved.")
    }

    func testFreshSessionIsNotAJumpBack() {
        XCTAssertFalse(AudiobookSession.shared.isJumpBack)
    }
}
