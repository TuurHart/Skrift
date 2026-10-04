import XCTest
import SwiftData
@testable import SkriftMobile

/// Q88 (C115, D91, D145): the quick note wears the same header as the note screen. Its
/// rating + destination live in local state until the first keystroke, then ride onto the
/// row the instant it is born.
@MainActor
final class QuickNoteHeaderQ88Tests: XCTestCase {

    func testFirstKeystrokeCarriesRatingAndDestinationOntoTheRow() {
        let repo = NotesRepository(inMemory: true)
        let draft = QuickNoteDraft()
        draft.edited(title: "", body: "T", context: repo.context,
                     seedTags: ["a"], seedSignificance: 0.5,
                     seedDestination: .idea)
        let memo = draft.memo
        XCTAssertEqual(memo?.significance, 0.5)
        XCTAssertEqual(memo?.destination, .idea)
        XCTAssertEqual(memo?.tags, ["a"])
    }

    func testUntouchedHeaderStaysUnratedAndPersonal() {
        let repo = NotesRepository(inMemory: true)
        let draft = QuickNoteDraft()
        draft.edited(title: "", body: "T", context: repo.context)
        let memo = draft.memo
        XCTAssertEqual(memo?.significance, 0, "an unrated draft stores 0 (never rated)")
        XCTAssertEqual(memo?.destination, .personal)
    }

    func testDraftWithNoTextNeverCreatesARowEvenWhenHeaderIsSet() {
        let repo = NotesRepository(inMemory: true)
        let draft = QuickNoteDraft()
        draft.edited(title: "", body: "", context: repo.context,
                     seedSignificance: 1.0, seedDestination: .project)
        XCTAssertNil(draft.memo, "D91: rating the pill alone must not create a note")
    }
}
