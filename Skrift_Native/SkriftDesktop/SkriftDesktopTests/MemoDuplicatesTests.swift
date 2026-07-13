import XCTest
import Foundation

/// The SHARED same-id keeper rule (`Shared/Pipeline/MemoDuplicates.swift`) — the row
/// both apps agree is "the memo" when CloudKit materializes duplicates (2026-07-12
/// incident). The phone's MemoDeduperTests pin the healing side; these pin the rule.
final class MemoDuplicatesTests: XCTestCase {

    private func memo(id: UUID, transcript: String?, deletedAt: Date? = nil,
                      editedAt: Date? = nil) -> Memo {
        // createdAt pinned: a real CloudKit clone syncs the SAME createdAt, and the
        // default Date() would make lastEditedAt differ by microseconds — no true tie.
        let m = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a",
                     recordedAt: Date(timeIntervalSince1970: 1_000_000),
                     transcript: transcript, deletedAt: deletedAt,
                     createdAt: Date(timeIntervalSince1970: 1_000_000), editedAt: editedAt)
        return m
    }

    func testAliveBeatsTrashed() {
        let id = UUID()
        // The trashed clone even has MORE content — alive still wins (a healed
        // clone must never shadow its keeper).
        let trashed = memo(id: id, transcript: "much longer transcript text", deletedAt: Date())
        let alive = memo(id: id, transcript: "short")
        XCTAssertTrue(MemoDuplicates.keeper(of: [trashed, alive]) === alive)
    }

    func testMostContentWins() {
        let id = UUID()
        let small = memo(id: id, transcript: "hi")
        let big = memo(id: id, transcript: "a considerably longer transcript")
        XCTAssertTrue(MemoDuplicates.keeper(of: [small, big]) === big)
    }

    func testFullTieKeepsTheFirst() {
        let id = UUID()
        let a = memo(id: id, transcript: "same")
        let b = memo(id: id, transcript: "same")
        XCTAssertTrue(MemoDuplicates.keeper(of: [a, b]) === a)
    }

    func testCanonicalRowsCollapsesPerIDPreservingOrder() {
        let id1 = UUID(), id2 = UUID()
        let a1 = memo(id: id1, transcript: "first, small")
        let b = memo(id: id2, transcript: "unique")
        let a2 = memo(id: id1, transcript: "second row of id1 with more text")
        let canon = MemoDuplicates.canonicalRows([a1, b, a2])
        XCTAssertEqual(canon.count, 2)
        XCTAssertTrue(canon[0] === a2, "id1 collapses onto its keeper, at first-seen position")
        XCTAssertTrue(canon[1] === b)
    }
}
