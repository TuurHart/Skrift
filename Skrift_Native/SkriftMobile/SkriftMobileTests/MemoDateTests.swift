import XCTest
@testable import SkriftMobile

/// The memo-list date label degrades sensibly with age (2026-06-25 fix): a memo older than a
/// week shows a real date instead of a bare weekday — so a last-year video reads "2025-06-19",
/// not "Fri" (which looked identical to last Friday). The Obsidian export date is separate
/// (Compiler uses recordedAt → yyyy-MM-dd) and was always correct.
final class MemoDateTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 14, _ min: Int = 29) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testTodayAndYesterday() {
        let now = date(2026, 6, 25, 18, 0)
        XCTAssertTrue(MemoDate.label(date(2026, 6, 25), now: now).hasPrefix("Today · "))
        XCTAssertTrue(MemoDate.label(date(2026, 6, 24), now: now).hasPrefix("Yesterday · "))
    }

    func testThisWeekShowsWeekdayNotADate() {
        let now = date(2026, 6, 25)
        let label = MemoDate.label(date(2026, 6, 22), now: now)   // 3 days ago
        XCTAssertTrue(label.contains("· 14:29"))
        XCTAssertFalse(label.contains("2026"), "within a week stays weekday — no year")
        XCTAssertFalse(label.contains("Jun"), "within a week is weekday form, not 'd MMM'")
    }

    func testSameYearOlderShowsMonthDayNoYear() {
        let now = date(2026, 6, 25)
        let label = MemoDate.label(date(2026, 1, 10), now: now)   // ~5 months earlier, same year
        XCTAssertTrue(label.contains("· 14:29"))
        XCTAssertFalse(label.hasPrefix("Today") || label.hasPrefix("Yesterday"))
        XCTAssertFalse(label.contains("2026"), "same-year memo omits the year")
    }

    func testDifferentYearShowsISODate() {
        let now = date(2026, 6, 25)
        XCTAssertEqual(MemoDate.label(date(2025, 6, 19), now: now), "2025-06-19 · 14:29",
                       "a last-year memo shows the full ISO date, not a bare weekday")
    }

    func testGroupHeaderCarriesYearOnlyForOtherYears() {
        let now = date(2026, 6, 25)
        XCTAssertTrue(MemoDate.group(date(2025, 6, 19), now: now).contains("2025"))
        XCTAssertFalse(MemoDate.group(date(2026, 1, 10), now: now).contains("2026"))
    }
}
