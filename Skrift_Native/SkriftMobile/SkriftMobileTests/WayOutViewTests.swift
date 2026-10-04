import XCTest
@testable import SkriftMobile

/// The merged "On its way out" surface (WayOutView) — Fading + Recently Deleted
/// collapsed into one conveyor, one verb (Q4, 2026-07-20). Covers only the pure
/// parts pulled out of the view: the Bring back mutation and the row countdown wiring
/// (ordering = WayOutSharedTests, merged count = ReviewRowGlyphTests). The countdown COPY itself is
/// MemoSpine's own contract (see MemoSpineTests) — the wiring tests here only
/// confirm WayOutView hands the spine the right memo.
final class WayOutViewTests: XCTestCase {

    private let now = Date()
    private func daysAgo(_ n: Int) -> Date { now.addingTimeInterval(-Double(n) * 86_400) }

    /// A bare, untouched voice note recorded `days` ago (same fixture shape as
    /// MemoLifecycleTests/MemoSpineTests).
    private func bareMemo(days: Int) -> Memo {
        Memo(audioFilename: "m.m4a", recordedAt: daysAgo(days),
             transcript: "just words", transcriptStatus: .done)
    }

    // MARK: Bring back — pinned cross-app semantics (BASE.md's seam note): keptAt
    // ALWAYS set, deletedAt ALWAYS cleared. NOT the same as NotesRepository.restore(_:),
    // which only clears deletedAt — that alone would let a rescued note re-fade at once.

    @MainActor
    func testBringBackOnAFadingNoteSetsKeptAtAndItNeverFadesAgain() {
        let repo = NotesRepository(inMemory: true)
        let memo = bareMemo(days: 45)
        repo.insert(memo)
        XCTAssertNil(memo.keptAt)

        WayOutView.bringBack(memo, repository: repo)

        XCTAssertNotNil(memo.keptAt)
        XCTAssertNil(memo.deletedAt, "a fading row never had a deletedAt — clearing it must stay a no-op")
        XCTAssertFalse(MemoLifecycle.isFading(memo, backlinked: [], now: now),
                        "kept — must not still read as fading")
    }

    @MainActor
    func testBringBackOnADeletedNoteRestoresItAndMarksItKept() {
        let repo = NotesRepository(inMemory: true)
        let memo = Memo(audioFilename: "m.m4a")
        repo.insert(memo)
        repo.softDelete(memo)
        XCTAssertNotNil(memo.deletedAt)

        WayOutView.bringBack(memo, repository: repo)

        XCTAssertNil(memo.deletedAt)
        XCTAssertNotNil(memo.keptAt, "an explicit rescue is a touch, even for a formerly-deleted note")
        XCTAssertEqual(repo.allMemos().map(\.id), [memo.id], "back on the main list")
    }

    // MARK: the row's countdown wiring — MemoSpine owns the copy (MemoSpineTests);
    // this only confirms WayOut.oneLiner routes each memo to the right branch.

    func testOneLinerForAStillFadingRowMovesToDeleted() {
        let memo = bareMemo(days: 31)   // untouched, past day 30, not yet deleted
        let expected = MemoSpine.oneLiner(for: .fading(deletedAt: MemoLifecycle.trashesAt(memo)), now: now)
        XCTAssertEqual(WayOut.oneLiner(for: memo, now: now), expected)
        XCTAssertTrue(expected.hasPrefix("moves to Recently Deleted"), "got: \(expected)")
    }

    func testOneLinerForADeletedRowIsGoneForGood() {
        let memo = Memo(deletedAt: now.addingTimeInterval(-5 * 86_400))
        memo.trashSeenAt = memo.deletedAt   // seen at deletion — the countdown runs from here (v3)
        let expected = MemoSpine.oneLiner(
            for: .deleted(goneAt: memo.deletedAt!.addingTimeInterval(TrashPolicy.retention)), now: now)
        XCTAssertEqual(WayOut.oneLiner(for: memo, now: now), expected)
        XCTAssertTrue(expected.hasPrefix("gone for good"), "got: \(expected)")
    }
}
