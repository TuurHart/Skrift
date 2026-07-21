import XCTest
@testable import SkriftMobile

/// The merged "On its way out" surface (WayOutView) — Fading + Recently Deleted
/// collapsed into one conveyor, one verb (Q4, 2026-07-20). Covers only the pure
/// parts pulled out of the view: the merged count, imminence ordering for both
/// sections, and the Bring back mutation. The countdown COPY itself is
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

    // MARK: merged count

    func testMergedCountAddsBothSections() {
        let fading = [bareMemo(days: 31), bareMemo(days: 45)]
        let deleted = [Memo(deletedAt: now)]
        XCTAssertEqual(WayOutView.total(fading: fading, deleted: deleted), 3)
    }

    func testMergedCountIsZeroWhenBothSectionsAreEmpty() {
        XCTAssertEqual(WayOutView.total(fading: [], deleted: []), 0)
    }

    // MARK: imminence ordering

    func testFadingRowsOrderSoonestToMoveFirst() {
        let soon = bareMemo(days: 58)    // 2 days from the 60-day auto-move
        let later = bareMemo(days: 31)   // 29 days from the auto-move
        let ordered = WayOutView.orderedByImminence(fading: [later, soon])
        XCTAssertEqual(ordered.map(\.id), [soon.id, later.id])
    }

    func testDeletedRowsOrderSoonestToPurgeFirst() {
        let soonToPurge = Memo(deletedAt: now.addingTimeInterval(-13 * 86_400))   // 1 day left
        let later = Memo(deletedAt: now.addingTimeInterval(-2 * 86_400))          // 12 days left
        let ordered = WayOutView.orderedByImminence(deleted: [later, soonToPurge])
        XCTAssertEqual(ordered.map(\.id), [soonToPurge.id, later.id])
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
    // this only confirms WayOutView.oneLiner routes each memo to the right branch.

    func testOneLinerForAStillFadingRowMovesToDeleted() {
        let memo = bareMemo(days: 31)   // untouched, past day 30, not yet deleted
        let expected = MemoSpine.oneLiner(for: .fading(deletedAt: MemoLifecycle.fadesAt(memo)), now: now)
        XCTAssertEqual(WayOutView.oneLiner(for: memo, now: now), expected)
        XCTAssertTrue(expected.hasPrefix("moves to Recently Deleted"), "got: \(expected)")
    }

    func testOneLinerForADeletedRowIsGoneForGood() {
        let memo = Memo(deletedAt: now.addingTimeInterval(-5 * 86_400))
        let expected = MemoSpine.oneLiner(
            for: .deleted(goneAt: memo.deletedAt!.addingTimeInterval(TrashPolicy.retention)), now: now)
        XCTAssertEqual(WayOutView.oneLiner(for: memo, now: now), expected)
        XCTAssertTrue(expected.hasPrefix("gone for good"), "got: \(expected)")
    }
}
