import XCTest
import Foundation

/// Q102 — C182/C215/D10: a locked note is in the Process pile. Lock gates the eyes, not
/// the pipeline, so `ProcessPile.isWaiting` / `isDone` carry no lock term. Synthetic notes only.
final class ProcessPileLockedTests: XCTestCase {

    private func memo(significance: Double = 1, locked: Bool, transcript: String? = "a private thought",
                      deleted: Bool = false) -> Memo {
        let id = UUID()
        let m = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", recordedAt: Date(),
                     title: nil, transcript: transcript, transcriptStatus: .done,
                     significance: significance)
        m.locked = locked
        if deleted { m.deletedAt = Date() }
        return m
    }

    func testLockedRatedTranscribedUnprocessedNoteIsWaiting() {
        let m = memo(locked: true)
        XCTAssertTrue(ProcessPile.isWaiting(m, enhancedIDs: []))
        XCTAssertEqual(ProcessPile.waiting(memos: [m], enhancedIDs: []).count, 1)
    }

    func testLockedNoteStillNeedsARealTranscript() {
        XCTAssertFalse(ProcessPile.isWaiting(memo(locked: true, transcript: "  \n"), enhancedIDs: []))
        XCTAssertFalse(ProcessPile.isWaiting(memo(locked: true, transcript: nil), enhancedIDs: []))
    }

    func testLockedTrashedNoteIsNotWaiting() {
        XCTAssertFalse(ProcessPile.isWaiting(memo(locked: true, deleted: true), enhancedIDs: []))
    }

    func testLockedNoteWaitingMatchesUnlockedTwin() {
        let locked = memo(locked: true), open = memo(locked: false)
        XCTAssertEqual(ProcessPile.isWaiting(locked, enhancedIDs: []), ProcessPile.isWaiting(open, enhancedIDs: []))
    }

    func testLockedProcessedNoteIsDone() {
        let m = memo(locked: true)
        XCTAssertTrue(ProcessPile.isDone(m, enhancedIDs: [m.id]))
        XCTAssertFalse(ProcessPile.isWaiting(m, enhancedIDs: [m.id]))
    }
}
