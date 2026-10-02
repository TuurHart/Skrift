import XCTest
import Foundation

/// Q97 / C70 / C115: the ONE day-header date rule (`NotesListModel.groupDate`) — headers
/// follow the note's real date (what the card shows), never its arrival/authoring time.
/// This bundle compiles `Shared/UI/NotesListModel.swift` directly, so it runs the same code
/// the phone/iPad list calls (the phone's twin: `MemoListGroupingTests`).
final class NotesListGroupDateTests: XCTestCase {
    private let now = Date()
    private func daysAgo(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: -n, to: now)! }

    func testHeadersFollowRecordedDateNotArrival() {
        let recorded = daysAgo(21)
        let d = NotesListModel.groupDate(recordedAt: recorded, lastEditedAt: daysAgo(1), byEditTime: false)
        XCTAssertEqual(d, recorded)
    }

    func testEditSortKeepsEditTime() {
        let edited = daysAgo(1)
        XCTAssertEqual(NotesListModel.groupDate(recordedAt: daysAgo(21), lastEditedAt: edited, byEditTime: true), edited)
    }
}
