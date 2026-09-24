import XCTest
import SwiftData
@testable import SkriftMobile

/// Q7 (C112/C114/C43, D91/D134/D135): the quick-note screen's routing +
/// lazy-creation + silent-discard core.
@MainActor
final class QuickNoteTests: XCTestCase {

    // MARK: - Routing (widget / Siri / Control Center → the same screen)

    func testNewNoteDeepLinkRequestsQuickNote() {
        let before = QuickNoteBridge.shared.requestID
        AppURLHandler.handle(URL(string: "skrift://newnote")!)
        XCTAssertEqual(QuickNoteBridge.shared.requestID, before + 1,
                       "skrift://newnote should request a quick note")
    }

    func testRecordDeepLinkDoesNotRequestQuickNote() {
        let before = QuickNoteBridge.shared.requestID
        AppURLHandler.handle(URL(string: "skrift://record")!)
        XCTAssertEqual(QuickNoteBridge.shared.requestID, before,
                       "the record deep link must not also open a quick note")
    }

    // MARK: - Lazy creation on first keystroke (D91: "create the Memo on the
    // first keystroke, or an empty note syncs to the Mac")

    func testNoMemoUntilFirstKeystroke() {
        let repo = NotesRepository(inMemory: true)
        let draft = QuickNoteDraft()
        XCTAssertNil(draft.memo)
        // Opening the screen and focusing fields types nothing — still no Memo.
        draft.edited(title: "", body: "", context: repo.context)
        XCTAssertNil(draft.memo, "an untouched quick note must never create a Memo")
    }

    func testFirstKeystrokeCreatesTheMemo() {
        let repo = NotesRepository(inMemory: true)
        let draft = QuickNoteDraft()
        let countBefore = try? repo.context.fetch(FetchDescriptor<Memo>()).count
        let memo = draft.edited(title: "", body: "T", context: repo.context)
        XCTAssertNotNil(memo)
        XCTAssertEqual(memo?.transcript, "T")
        XCTAssertEqual(SourceKind.of(memo!), .typedNote)
        let countAfter = try? repo.context.fetch(FetchDescriptor<Memo>()).count
        XCTAssertEqual(countAfter, (countBefore ?? 0) + 1)
    }

    func testSubsequentEditsUpdateTheSameMemo() {
        let repo = NotesRepository(inMemory: true)
        let draft = QuickNoteDraft()
        let first = draft.edited(title: "", body: "H", context: repo.context)
        let second = draft.edited(title: "", body: "Hi", context: repo.context)
        XCTAssertEqual(first?.id, second?.id)
        XCTAssertEqual(second?.transcript, "Hi")
    }

    // MARK: - Silent discard on leave (D91/C43 + D91's silent-discard pick)

    func testNeverTypedLeavesNothingToDiscard() {
        let repo = NotesRepository(inMemory: true)
        let draft = QuickNoteDraft()
        draft.leave(context: repo.context)   // no-op: nothing was ever created
        let count = try? repo.context.fetch(FetchDescriptor<Memo>()).count
        XCTAssertEqual(count, 0)
    }

    func testEmptyMemoIsDeletedOnLeave() {
        let repo = NotesRepository(inMemory: true)
        let draft = QuickNoteDraft()
        _ = draft.edited(title: "", body: "x", context: repo.context)
        _ = draft.edited(title: "", body: "", context: repo.context)   // typed then deleted it all
        draft.leave(context: repo.context)
        let count = try? repo.context.fetch(FetchDescriptor<Memo>()).count
        XCTAssertEqual(count, 0, "typing then deleting everything must still count as empty")
        XCTAssertNil(draft.memo)
    }

    func testNonEmptyMemoSurvivesLeave() {
        let repo = NotesRepository(inMemory: true)
        let draft = QuickNoteDraft()
        _ = draft.edited(title: "", body: "Tram 28 idea", context: repo.context)
        draft.leave(context: repo.context)
        let count = try? repo.context.fetch(FetchDescriptor<Memo>()).count
        XCTAssertEqual(count, 1)
    }

    func testTitleOnlyCountsAsNotEmpty() {
        let repo = NotesRepository(inMemory: true)
        let draft = QuickNoteDraft()
        _ = draft.edited(title: "Groceries", body: "", context: repo.context)
        draft.leave(context: repo.context)
        let count = try? repo.context.fetch(FetchDescriptor<Memo>()).count
        XCTAssertEqual(count, 1)
    }
}
