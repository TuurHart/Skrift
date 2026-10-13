import XCTest
@testable import SkriftMobile

/// Q97 / C70 / C115: the phone list's day headers group by the note's REAL date
/// (`recordedAt`, the date the card shows) — never by when the note landed on
/// this device or was authored (`createdAt`). Tuur 2026-10-02: a fresh phone
/// filled from CloudKit put "a whole ton of notes" under Yesterday.
final class MemoListGroupingTests: XCTestCase {

    private let now = Date()
    private func daysAgo(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: -n, to: now)! }

    /// A memo recorded 3 weeks ago that arrived (createdAt) yesterday — the Mac-authored /
    /// freshly-synced shape.
    private func arrivedYesterday() -> Memo {
        Memo(recordedAt: daysAgo(21), createdAt: daysAgo(1))
    }

    func testRecentlyAddedGroupsByRecordedDateNotArrival() {
        let m = arrivedYesterday()
        let date = NotesListModel.groupDate(recordedAt: m.recordedAt, lastEditedAt: m.lastEditedAt, byEditTime: false)
        XCTAssertEqual(MemoDate.bucket(date, now: now), MemoDate.bucket(daysAgo(21), now: now))
        XCTAssertNotEqual(MemoDate.bucket(date, now: now), "Yesterday")
    }
    // Q358 (D190): the "Yesterday" day group is deleted, and with it the two tests that asserted
    // it. Their invariants (arrival day never groups, Recently-edited groups by edit day) are
    // re-asserted against the D190 buckets in ListGroupingTests.
}
