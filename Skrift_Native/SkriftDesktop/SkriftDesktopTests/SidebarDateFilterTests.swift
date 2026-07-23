import XCTest
import Foundation

/// The shared `DateRangeFilter` rule behind BOTH Filter sheets — the iPad's
/// MemoFilter date range and the Mac sidebar's uploaded-date filter (Tuur
/// 2026-07-23: "add Date to the Mac"). Pure, so it lives in Shared/Pipeline.
final class SidebarDateFilterTests: XCTestCase {

    private let cal = Calendar.current
    private func daysAgo(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: Date())! }

    func testNoBoundsMatchEverything() {
        XCTAssertTrue(DateRangeFilter.contains(daysAgo(0), from: nil, to: nil))
        XCTAssertTrue(DateRangeFilter.contains(daysAgo(100), from: nil, to: nil))
    }

    func testFromExcludesOlder() {
        let from = daysAgo(3)
        XCTAssertTrue(DateRangeFilter.contains(daysAgo(0), from: from, to: nil))
        XCTAssertFalse(DateRangeFilter.contains(daysAgo(10), from: from, to: nil))
    }

    func testToIncludesTheWholeNamedDay() {
        let to = daysAgo(1)   // "yesterday"
        // Yesterday afternoon is inside "to = yesterday" (the whole day counts).
        XCTAssertTrue(DateRangeFilter.contains(daysAgo(1), from: nil, to: to))
        // Today is after the range.
        XCTAssertFalse(DateRangeFilter.contains(daysAgo(0), from: nil, to: to))
    }

    func testInclusiveRange() {
        let from = daysAgo(5), to = daysAgo(0)
        XCTAssertTrue(DateRangeFilter.contains(daysAgo(2), from: from, to: to))
        XCTAssertFalse(DateRangeFilter.contains(daysAgo(20), from: from, to: to))
    }
}
