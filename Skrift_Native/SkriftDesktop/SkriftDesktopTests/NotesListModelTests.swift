import XCTest
import Foundation

/// The unified notes-list's cross-app shapes (Q26, mocks/one-notes-list.html,
/// D134–D137): chip counts, day grouping, and the pill-visibility rule. This
/// bundle compiles `Shared/UI/NotesListModel.swift` directly (no `@testable
/// import` — same discipline as `ThreeBallScaleTests`/`SharedCopy` in this
/// target), so it exercises the SAME code the phone/iPad/Mac all call.
final class NotesListModelTests: XCTestCase {

    // MARK: chipCounts

    func testChipCountsCarriesTheThreeSuppliedNumbers() {
        let counts = NotesListModel.chipCounts(needsWork: 1, done: 2, notRated: 2)
        XCTAssertEqual(counts[.needsWork], 1)
        XCTAssertEqual(counts[.done], 2)
        XCTAssertEqual(counts[.notRated], 2)
    }

    /// D135: "All carries no number" — the caller never supplies one, and the
    /// map must not invent one.
    func testChipCountsNeverCarriesAllCount() {
        let counts = NotesListModel.chipCounts(needsWork: 3, done: 0, notRated: 5)
        XCTAssertNil(counts[.all])
    }

    // MARK: dayGroups

    private struct Dated { let label: String; let day: String }

    func testDayGroupsBucketsByLabelInFirstSeenOrder() {
        let items = [
            Dated(label: "a", day: "Today"),
            Dated(label: "b", day: "Yesterday"),
            Dated(label: "c", day: "Today"),
            Dated(label: "d", day: "Mon 3 Jun"),
        ]
        let groups = NotesListModel.dayGroups(items, dayLabel: { $0.day })
        XCTAssertEqual(groups.map(\.title), ["Today", "Yesterday", "Mon 3 Jun"])
        XCTAssertEqual(groups[0].items.map(\.label), ["a", "c"], "same-day items land in ONE bucket, in list order")
        XCTAssertEqual(groups[1].items.map(\.label), ["b"])
    }

    func testDayGroupsOfEmptyListIsEmpty() {
        let groups = NotesListModel.dayGroups([Dated](), dayLabel: { $0.day })
        XCTAssertTrue(groups.isEmpty)
    }

    // MARK: PillRule

    /// D136: a pill shows ONLY while working or broken — never for a calm,
    /// finished state (the always-on-badge-is-no-signal doctrine).
    func testPillRuleShowsOnlyWhileWorkingOrBroken() {
        XCTAssertTrue(NotesListModel.PillRule.working.showsPill)
        XCTAssertTrue(NotesListModel.PillRule.broken.showsPill)
        XCTAssertFalse(NotesListModel.PillRule.calm.showsPill)
    }
}
