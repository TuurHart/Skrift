import XCTest
@testable import SkriftMobile

final class LookbackProviderTests: XCTestCase {
    private let calendar = Calendar.current
    /// Fixed "now" so windows don't shift with the wall clock.
    private lazy var now: Date = {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 7, hour: 12))!
    }()

    private func memo(daysAgo: Int = 0, monthsAgo: Int = 0, yearsAgo: Int = 0,
                      significance: Double = 0.5, title: String = "m") -> Memo {
        let date = calendar.date(byAdding: DateComponents(
            month: -monthsAgo, day: -daysAgo), to: now)!
        let shifted = yearsAgo == 0 ? date
            : calendar.date(byAdding: .year, value: -yearsAgo, to: date)!
        return Memo.make(recordedAt: shifted, title: title, transcript: "t",
                         transcriptStatus: .done, significance: significance)
    }

    func testPicksHighestImportanceInWindowTiesGoToNewest() {
        let low = memo(monthsAgo: 1, significance: 0.2, title: "low")
        let high = memo(daysAgo: 1, monthsAgo: 1, significance: 0.9, title: "high")
        let entries = LookbackProvider.entries(for: [low, high], now: now, calendar: calendar)
        XCTAssertEqual(entries.first?.id, high.id)
        XCTAssertEqual(entries.first?.label, "1 month ago")
    }

    func testEmptyWindowsAreHidden() {
        let only = memo(monthsAgo: 3, title: "three")
        let entries = LookbackProvider.entries(for: [only], now: now, calendar: calendar)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.label, "3 months ago")
    }

    func testOnThisDayPriorYearTopsTheListWithYearLabel() {
        let lastYear = memo(yearsAgo: 1, significance: 0.3, title: "otd")
        let oneMonth = memo(monthsAgo: 1, significance: 0.9, title: "recent")
        let entries = LookbackProvider.entries(for: [lastYear, oneMonth], now: now, calendar: calendar)
        XCTAssertEqual(entries.first?.label, "On this day · 2025")
        XCTAssertEqual(entries.first?.id, lastYear.id)
    }

    func testOnThisDayFallsBackWithinWindow() {
        let nearMiss = memo(daysAgo: 2, yearsAgo: 1, title: "near")
        let entries = LookbackProvider.entries(for: [nearMiss], now: now, calendar: calendar)
        XCTAssertTrue(entries.contains { $0.label == "On this day · 2025" && $0.id == nearMiss.id })
    }

    func testMemoAppearsAtMostOnce() {
        // Exactly one year back: matches BOTH on-this-day and the 12-month window.
        let m = memo(yearsAgo: 1, title: "both")
        let entries = LookbackProvider.entries(for: [m], now: now, calendar: calendar)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.label, "On this day · 2025")
    }

    func testWeekWindowKeepsAYoungCorpusAlive() {
        // Device finding 2026-07-07: a corpus only days old showed zero cards.
        let lastWeek = memo(daysAgo: 7, title: "week")
        let entries = LookbackProvider.entries(for: [lastWeek], now: now, calendar: calendar)
        XCTAssertEqual(entries.first?.label, "1 week ago")
        XCTAssertEqual(entries.first?.id, lastWeek.id)
    }

    func testTodaysMemosNeverLookBack() {
        let today = memo(title: "today")
        XCTAssertTrue(LookbackProvider.entries(for: [today], now: now, calendar: calendar).isEmpty)
    }

    func testExcludedNotesNeverAppearInLookbacks() {
        // A note already shown by Important lately must not duplicate into a
        // lookback card (build-43 device finding).
        let star = memo(daysAgo: 1, significance: 0.9, title: "star")
        let entries = LookbackProvider.entries(for: [star], now: now, calendar: calendar,
                                               excluding: [star.id])
        XCTAssertTrue(entries.isEmpty)
    }

    func testNeverEmptyGuaranteeForDayOldCorpus() {
        // Build-41 device finding: notes from yesterday only → zero cards.
        let yesterday = memo(daysAgo: 1, title: "y")
        let entries = LookbackProvider.entries(for: [yesterday], now: now, calendar: calendar)
        XCTAssertEqual(entries.first?.label, "Yesterday")
        XCTAssertEqual(entries.first?.id, yesterday.id)

        // Between anchors (12 days: misses week + month windows) → still a card.
        let stranded = memo(daysAgo: 12, title: "s")
        let entries2 = LookbackProvider.entries(for: [stranded], now: now, calendar: calendar)
        XCTAssertEqual(entries2.first?.label, "12 days ago")
    }

    func testDayCountsAndHotFlag() {
        let a = memo(daysAgo: 0, significance: 0)
        let b = memo(daysAgo: 0, significance: 0.8)
        let counts = LookbackProvider.dayCounts(for: [a, b], month: now, calendar: calendar)
        let day = calendar.component(.day, from: now)
        XCTAssertEqual(counts[day]?.count, 2)
        XCTAssertEqual(counts[day]?.hot, true)
    }
}
