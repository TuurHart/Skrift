import XCTest
@testable import SkriftMobile

/// R88/C213: MemoDetailView's three Copy entry points — the ⋯-menu's
/// `workbenchChrome` Copy, `noteOverflowItems`' own Copy item, and the
/// compact-sheet "Copy transcript" — all call `MemoDetailView.copyTranscript()`,
/// which delegates to `GatedCopy.copyTranscript(_:lockGate:write:)`. These
/// assert that ONE gate, not silence, decides whether a locked note's
/// transcript reaches the pasteboard.
final class LockedNoteCopyTests: XCTestCase {

    @MainActor
    func testUnlockedMemoCopiesImmediately() async {
        let gate = LockGate.shared
        gate.relockAll()
        let memo = Memo(title: "Open", transcript: "plain words")
        var copied: String?
        await GatedCopy.copyTranscript(memo, lockGate: gate) { copied = $0 }
        XCTAssertEqual(copied, "plain words")
    }

    @MainActor
    func testLockedMemoAsksForAuthBeforeCopying() async {
        let gate = LockGate.shared
        gate.relockAll()
        gate.authenticate = { _ in true }   // user passes Face ID
        let memo = Memo(title: "Diary", transcript: "hidden words")
        memo.locked = true
        var copied: String?
        var askedReason: String?
        gate.authenticate = { reason in askedReason = reason; return true }
        await GatedCopy.copyTranscript(memo, lockGate: gate) { copied = $0 }
        XCTAssertNotNil(askedReason, "a locked note must ask for auth, not silently no-op")
        XCTAssertEqual(copied, "hidden words", "auth succeeded, so the copy proceeds")
        gate.relockAll()
    }

    @MainActor
    func testFailedAuthCopiesNothing() async {
        let gate = LockGate.shared
        gate.relockAll()
        gate.authenticate = { _ in false }  // user cancels / fails Face ID
        let memo = Memo(title: "Diary", transcript: "hidden words")
        memo.locked = true
        var copied: String?
        await GatedCopy.copyTranscript(memo, lockGate: gate) { copied = $0 }
        XCTAssertNil(copied, "a failed/cancelled auth must not leak the transcript")
        gate.relockAll()
    }

    @MainActor
    func testAlreadyUnlockedThisSessionCopiesWithoutReprompting() async {
        let gate = LockGate.shared
        gate.relockAll()
        gate.authenticate = { _ in true }
        let memo = Memo(title: "Diary", transcript: "hidden words")
        memo.locked = true
        _ = await gate.unlock(memo.id)   // unlocked earlier this session (e.g. opened the detail page)
        gate.authenticate = { _ in
            XCTFail("must not re-authenticate once this session already unlocked the note")
            return false
        }
        var copied: String?
        await GatedCopy.copyTranscript(memo, lockGate: gate) { copied = $0 }
        XCTAssertEqual(copied, "hidden words")
        gate.relockAll()
    }
}
