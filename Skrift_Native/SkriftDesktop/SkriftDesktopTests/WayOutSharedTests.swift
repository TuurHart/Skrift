import XCTest
import Foundation

/// Q82 group 9: the way-out shelf rules live once in `WayOut` (Shared). Identical file in the
/// phone and Mac test targets: same input, same output.
final class WayOutSharedTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func daysAgo(_ n: Int) -> Date { now.addingTimeInterval(-Double(n) * 86_400) }
    private func memo(days: Int, deletedDaysAgo: Int? = nil) -> Memo {
        let id = UUID()
        return Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", recordedAt: daysAgo(days),
                    title: nil, transcript: "hello", transcriptStatus: .done, significance: 0,
                    deletedAt: deletedDaysAgo.map { daysAgo($0) })
    }

    func testBringBackIsATouchAndClearsTheTrash() {
        let m = memo(days: 40, deletedDaysAgo: 3)
        m.trashSeenAt = daysAgo(2)
        WayOut.bringBack(m, now: now)
        XCTAssertEqual(m.keptAt, now)
        XCTAssertNil(m.deletedAt)
        XCTAssertNil(m.trashSeenAt)
    }

    func testShelfOrderIsWhatHappensNext() {
        let soon = memo(days: 59), later = memo(days: 31)
        XCTAssertEqual(WayOut.fadingOrdered([later, soon]).map(\.id), [soon.id, later.id])
        let old = memo(days: 40, deletedDaysAgo: 13), fresh = memo(days: 40, deletedDaysAgo: 6)
        XCTAssertEqual(WayOut.deletedOrdered([fresh, old]).map(\.id), [old.id, fresh.id])
    }

    func testUrgencyThresholdIsThreeDaysOnBothShelves() {
        XCTAssertTrue(WayOut.isUrgent(.fading(deletedAt: now.addingTimeInterval(2 * 86_400)), now: now))
        XCTAssertTrue(WayOut.isUrgent(.fading(deletedAt: now.addingTimeInterval(3 * 86_400)), now: now))
        XCTAssertFalse(WayOut.isUrgent(.fading(deletedAt: now.addingTimeInterval(10 * 86_400)), now: now))
        XCTAssertTrue(WayOut.isUrgent(.deleted(goneAt: now.addingTimeInterval(86_400)), now: now))
        XCTAssertFalse(WayOut.isUrgent(.deleted(goneAt: now.addingTimeInterval(9 * 86_400)), now: now))
        XCTAssertFalse(WayOut.isUrgent(.toProcess, now: now))
        XCTAssertEqual(WayOut.daysLeft(until: now.addingTimeInterval(-5), now: now), 0, "never negative")
        XCTAssertEqual(WayOut.daysLeft(until: now.addingTimeInterval(86_400 + 1), now: now), 2)
    }

    func testTwoCloneRowsCollapseToOneOnEveryReader() {
        let id = UUID()
        func row(_ text: String) -> Memo {
            Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", recordedAt: now, title: nil,
                 transcript: text, transcriptStatus: .done, significance: 0)
        }
        let thin = row("a"), full = row("a much longer transcript")
        XCTAssertEqual(MemoDuplicates.canonicalRows([thin, full]).count, 1)
        XCTAssertTrue(MemoDuplicates.canonicalRows([thin, full])[0] === full, "the row with the most content wins")
    }
}
