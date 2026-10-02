import XCTest
@testable import SkriftMobile

/// Q101 — a locked note stays locked on every other phone surface (C91/C161/C213, R88):
/// Journal rows (snippet / title), "Share note…", and search (text and Related). Synthetic
/// notes only.
final class LockedSurfacesTests: XCTestCase {

    private let words = "a private thought about the thing"

    private func lockedMemo(title: String? = nil) -> Memo {
        let m = Memo(title: title, transcript: words)
        m.locked = true
        m.tags = ["secret-tag"]
        return m
    }

    // MARK: - search

    func testSearchDoesNotMatchALockedNotesBody() {
        let m = lockedMemo(title: "Groceries")
        XCTAssertTrue(m.matches(query: "grocer"), "the set title still matches")
        XCTAssertFalse(m.matches(query: "private"), "transcript")
        XCTAssertFalse(m.matches(query: "secret-tag"), "tags")
    }

    func testSearchMatchesBodyAgainOnceUnlockedThisSession() {
        let m = lockedMemo(title: "Groceries")
        XCTAssertTrue(m.matches(query: "private", unlockedThisSession: true))
        XCTAssertTrue(m.matches(query: "secret-tag", unlockedThisSession: true))
    }

    func testUnlockedNoteSearchIsUnchanged() {
        let m = Memo(title: "Groceries", transcript: words)
        XCTAssertTrue(m.matches(query: "private"))
        XCTAssertTrue(m.matches(query: ""))
    }

    // MARK: - Share note…

    func testShareItemsAreEmptyForAHiddenLockedNote() {
        let m = lockedMemo(title: "Groceries")
        XCTAssertTrue(MemoShare.items(for: m, unlockedThisSession: false).isEmpty)
    }

    func testShareItemsCarryTheNoteOnceUnlockedOrWhenNeverLocked() {
        let m = lockedMemo(title: "Groceries")
        let unlocked = MemoShare.items(for: m, unlockedThisSession: true)
        XCTAssertEqual((unlocked.first as? String)?.contains(words), true)
        let open = Memo(title: "Open", transcript: words)
        XCTAssertFalse(MemoShare.items(for: open, unlockedThisSession: false).isEmpty)
    }

    // MARK: - the shared gate the Journal rows use

    @MainActor
    func testJournalRowGateFollowsTheSessionUnlock() async {
        let gate = LockGate.shared
        gate.relockAll()
        gate.authenticate = { _ in true }
        let m = lockedMemo()
        XCTAssertTrue(gate.isLocked(m))
        XCTAssertEqual(NoteVisibility.displayTitle(locked: m.locked, unlockedThisSession: !gate.isLocked(m),
                                                   title: m.title, fallback: { m.displayTitle }),
                       "Locked note", "no first-line fallback while hidden")
        XCTAssertNil(NoteVisibility.snippet(locked: m.locked, unlockedThisSession: !gate.isLocked(m), words))
        _ = await gate.unlock(m.id)
        XCTAssertFalse(gate.isLocked(m))
        XCTAssertEqual(NoteVisibility.snippet(locked: m.locked, unlockedThisSession: !gate.isLocked(m), words), words)
        gate.relockAll()
    }
}
