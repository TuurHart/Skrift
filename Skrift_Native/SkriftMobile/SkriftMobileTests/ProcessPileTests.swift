import XCTest
@testable import SkriftMobile

/// The shared "what is waiting to be processed" rule (Shared/Pipeline/ProcessPile).
/// It exists because the iPad's header button shipped counting the UNRATED pile
/// while wearing the Mac's Process verb — the exact opposite set, since an
/// unrated note is one every polisher deliberately skips (2026-07-23).
final class ProcessPileTests: XCTestCase {

    private func memo(significance: Double = 0.5,
                      transcript: String? = "just words",
                      locked: Bool = false,
                      deleted: Bool = false) -> Memo {
        let m = Memo(audioFilename: "m.m4a",
                     transcript: transcript,
                     transcriptStatus: .done,
                     significance: significance,
                     deletedAt: deleted ? Date() : nil)
        m.locked = locked
        return m
    }

    // MARK: the waiting pile

    func testRatedUnprocessedNoteIsWaiting() {
        let m = memo()
        XCTAssertEqual(ProcessPile.waiting(memos: [m], enhancedIDs: []).map(\.id), [m.id])
    }

    /// The doctrine: the rating IS the flag, so significance 0 is NOT waiting on
    /// a model — it is waiting on Tuur.
    func testUnratedNoteIsNotWaiting() {
        XCTAssertTrue(ProcessPile.waiting(memos: [memo(significance: 0)], enhancedIDs: []).isEmpty)
    }

    func testAlreadyEnhancedNoteIsNotWaiting() {
        let m = memo()
        XCTAssertTrue(ProcessPile.waiting(memos: [m], enhancedIDs: [m.id]).isEmpty)
    }

    func testLockedNoteIsNotWaiting() {
        XCTAssertTrue(ProcessPile.waiting(memos: [memo(locked: true)], enhancedIDs: []).isEmpty)
    }

    func testTrashedNoteIsNotWaiting() {
        XCTAssertTrue(ProcessPile.waiting(memos: [memo(deleted: true)], enhancedIDs: []).isEmpty)
    }

    func testEmptyOrWhitespaceTranscriptIsNotWaiting() {
        XCTAssertTrue(ProcessPile.waiting(memos: [memo(transcript: nil)], enhancedIDs: []).isEmpty)
        XCTAssertTrue(ProcessPile.waiting(memos: [memo(transcript: "   \n ")], enhancedIDs: []).isEmpty)
    }

    // MARK: the two piles are different sets

    func testWaitingAndUnratedNeverOverlap() {
        let rated = memo(significance: 0.5)
        let unrated = memo(significance: 0)
        let pool = [rated, unrated]
        let waiting = Set(ProcessPile.waiting(memos: pool, enhancedIDs: []).map(\.id))
        let unratedIDs = Set(ProcessPile.unrated(memos: pool).map(\.id))
        XCTAssertEqual(waiting, [rated.id])
        XCTAssertEqual(unratedIDs, [unrated.id])
        XCTAssertTrue(waiting.isDisjoint(with: unratedIDs))
    }

    func testUnratedExcludesTrashedAndLocked() {
        let pool = [memo(significance: 0, deleted: true), memo(significance: 0, locked: true)]
        XCTAssertTrue(ProcessPile.unrated(memos: pool).isEmpty)
    }

    // MARK: the bulk line is the Mac's

    func testPileRunLineUsesTheMacsWording() {
        XCTAssertEqual(PolishCenter.PileRun(done: 0, total: 5).line, "Processing 1 of 5")
        XCTAssertEqual(PolishCenter.PileRun(done: 4, total: 5).line, "Processing 5 of 5")
        // Never "6 of 5" as the last note completes.
        XCTAssertEqual(PolishCenter.PileRun(done: 5, total: 5).line, "Processing 5 of 5")
    }

    func testPileRunFraction() {
        XCTAssertEqual(PolishCenter.PileRun(done: 0, total: 4).fraction, 0)
        XCTAssertEqual(PolishCenter.PileRun(done: 2, total: 4).fraction, 0.5)
        XCTAssertEqual(PolishCenter.PileRun(done: 0, total: 0).fraction, 0)
    }
}
