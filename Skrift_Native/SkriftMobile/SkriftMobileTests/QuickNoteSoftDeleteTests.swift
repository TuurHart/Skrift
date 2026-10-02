import XCTest
import SwiftData
@testable import SkriftMobile

/// Q140 (C212/C90): the quick note's explicit Delete is a soft delete like every other delete;
/// a blank draft still vanishes silently (D91).
@MainActor
final class QuickNoteSoftDeleteTests: XCTestCase {

    func testDeleteOfWrittenNoteIsSoft() throws {
        let repo = NotesRepository(inMemory: true)
        let draft = QuickNoteDraft()
        let memo = try XCTUnwrap(draft.edited(title: "Idea", body: "Tram 28", context: repo.context))
        let id = memo.id
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        draft.discard(context: repo.context, at: when)

        XCTAssertNil(draft.memo)
        let found = try XCTUnwrap(repo.memo(id: id), "the row must survive a quick-note Delete")
        XCTAssertEqual(found.deletedAt, when)
        XCTAssertEqual(found.trashSeenAt, when)
        XCTAssertTrue(repo.deletedMemos().contains { $0.id == id }, "it must list under Recently Deleted")
        XCTAssertEqual(found.transcript, "Tram 28", "the text must be intact so Restore is lossless")
    }

    func testDeletedQuickNoteCanBeRestored() throws {
        let repo = NotesRepository(inMemory: true)
        let draft = QuickNoteDraft()
        let memo = try XCTUnwrap(draft.edited(title: "", body: "keep me", context: repo.context))
        draft.discard(context: repo.context)
        repo.restore(memo)
        XCTAssertNil(memo.deletedAt)
        XCTAssertEqual(memo.transcript, "keep me")
    }

    func testBlankDraftStillVanishesSilently() throws {
        let repo = NotesRepository(inMemory: true)
        let draft = QuickNoteDraft()
        _ = draft.edited(title: "", body: "x", context: repo.context)
        _ = draft.edited(title: "", body: "", context: repo.context)
        draft.discard(context: repo.context)
        XCTAssertEqual(try repo.context.fetch(FetchDescriptor<Memo>()).count, 0,
                       "an empty draft is never a note: no trash row")
    }

    func testNeverTypedDiscardIsANoOp() throws {
        let repo = NotesRepository(inMemory: true)
        let draft = QuickNoteDraft()
        draft.discard(context: repo.context)
        XCTAssertEqual(try repo.context.fetch(FetchDescriptor<Memo>()).count, 0)
    }
}
