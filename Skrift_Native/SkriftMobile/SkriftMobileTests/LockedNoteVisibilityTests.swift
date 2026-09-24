import XCTest
@testable import SkriftMobile

/// R88 (a locked note losing protection the moment it's trashed): a locked
/// note keeps that protection everywhere — the merged Fading/Recently
/// Deleted shelf, and copy — by routing through the ONE Shared predicate
/// (`NoteVisibility.contentVisible`) the detail page's `LockGate.isLocked`
/// already used. C161/C213/C91.
final class LockedNoteVisibilityTests: XCTestCase {

    // MARK: - The pure Shared predicate

    func testContentVisibleWhenNotLocked() {
        XCTAssertTrue(NoteVisibility.contentVisible(locked: false, unlockedThisSession: false))
        XCTAssertTrue(NoteVisibility.contentVisible(locked: false, unlockedThisSession: true))
    }

    func testContentHiddenWhenLockedAndNotUnlocked() {
        XCTAssertFalse(NoteVisibility.contentVisible(locked: true, unlockedThisSession: false))
    }

    func testContentVisibleWhenLockedButUnlockedThisSession() {
        XCTAssertTrue(NoteVisibility.contentVisible(locked: true, unlockedThisSession: true))
    }

    // MARK: - LockGate.isLocked routes through the predicate

    @MainActor
    func testLockGateIsLockedAgreesWithThePredicate() async {
        let gate = LockGate.shared
        gate.relockAll()
        gate.authenticate = { _ in true }
        let memo = Memo(title: "Diary", transcript: "hidden")
        memo.locked = true
        XCTAssertTrue(gate.isLocked(memo))
        _ = await gate.unlock(memo.id)
        XCTAssertFalse(gate.isLocked(memo))
        gate.relockAll()
    }

    // MARK: - Copy is gated behind auth (C213, R88)

    @MainActor
    func testCopyableTextNilWhileLockedAndUnauthenticated() {
        let gate = LockGate.shared
        gate.relockAll()
        let memo = Memo(title: "Diary", transcript: "hidden words")
        memo.locked = true
        XCTAssertNil(memo.copyableText, "a locked, un-unlocked note must not hand out its transcript")
        gate.relockAll()
    }

    @MainActor
    func testCopyableTextReturnsOnceUnlockedThisSession() async {
        let gate = LockGate.shared
        gate.relockAll()
        gate.authenticate = { _ in true }
        let memo = Memo(title: "Diary", transcript: "hidden words")
        memo.locked = true
        _ = await gate.unlock(memo.id)
        XCTAssertEqual(memo.copyableText, "hidden words")
        gate.relockAll()
    }

    // MARK: - WayOutView's row/peek fallback title (title + 🔒 only, C91)

    @MainActor
    func testWayOutBringBackNeverTouchesTheLockFlag() {
        // Bring-back is a lifecycle move, not a content reveal — it must not
        // require or change the lock (WayOutView's own contract, unaffected
        // by the R88 fix so a regression there would show up here too).
        let memo = Memo(title: "Diary", transcript: "hidden words")
        memo.locked = true
        memo.deletedAt = Date()
        WayOutView.bringBack(memo, repository: NotesRepository(inMemory: true))
        XCTAssertTrue(memo.locked, "bring-back must not silently unlock a note")
        XCTAssertNil(memo.deletedAt)
    }
}
