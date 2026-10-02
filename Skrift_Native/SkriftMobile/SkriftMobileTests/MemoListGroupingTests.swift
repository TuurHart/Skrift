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
        XCTAssertEqual(MemoDate.group(date, now: now), MemoDate.group(daysAgo(21), now: now))
        XCTAssertNotEqual(MemoDate.group(date, now: now), "Yesterday")
    }

    func testDayGroupsOverArrivalDayMemosKeepTheirRealDay() {
        let old = arrivedYesterday()
        let fresh = Memo(recordedAt: daysAgo(1), createdAt: daysAgo(1))
        let groups = NotesListModel.dayGroups([old, fresh]) {
            MemoDate.group(NotesListModel.groupDate(recordedAt: $0.recordedAt, lastEditedAt: $0.lastEditedAt,
                                                    byEditTime: false), now: now)
        }
        XCTAssertEqual(groups.count, 2, "the 3-week-old note must not share Yesterday's header")
        XCTAssertEqual(groups.first { $0.title == "Yesterday" }?.items.count, 1)
    }

    func testRecentlyEditedStillGroupsByEditTime() {
        let m = Memo(recordedAt: daysAgo(21), createdAt: daysAgo(21), editedAt: daysAgo(1))
        let date = NotesListModel.groupDate(recordedAt: m.recordedAt, lastEditedAt: m.lastEditedAt, byEditTime: true)
        XCTAssertEqual(MemoDate.group(date, now: now), "Yesterday")
    }
}
