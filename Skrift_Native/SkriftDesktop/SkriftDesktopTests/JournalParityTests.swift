import XCTest
import Foundation

/// Q182: the Journal's Then-vs-Now derivation, calendar grid, dot rule, first-day rule and intro
/// copy each live once in `Shared/` (recsj-084, -088, -091, -092).
final class JournalParityTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2   // Monday
        return c
    }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func memo(daysAgo: Int) -> Memo {
        let id = UUID()
        return Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a",
                    recordedAt: now.addingTimeInterval(-Double(daysAgo) * 86_400),
                    title: nil, transcript: "hello", transcriptStatus: .done, significance: 0.3)
    }

    func testDeriveRunsTheWholeLoopFromRelatedScores() async {
        let fresh = memo(daysAgo: 2), old = memo(daysAgo: 300), recentToo = memo(daysAgo: 5)
        let pair = await ThenVsNow.derive(memos: [fresh, old, recentToo], now: now, calendar: calendar,
                                          floor: 0.5) { id in
            id == fresh.id ? [(memoID: recentToo.id, score: 0.9), (memoID: old.id, score: 0.7)] : []
        }
        // recentToo is too young to be a "then"; the old note is the pick.
        XCTAssertEqual(pair, ThenVsNow.Pair(then: old.id, now: fresh.id))
        let none = await ThenVsNow.derive(memos: [fresh, old], now: now, calendar: calendar, floor: 0.5) { _ in
            [(memoID: old.id, score: 0.1)]
        }
        XCTAssertNil(none)
    }

    func testCalendarGridPadsToFullWeeksStartingOnTheFirstWeekday() {
        // 2027-01-15 12:00 UTC: January 2027 starts on a Friday; Monday-first => 4 leading blanks.
        let month = Date(timeIntervalSince1970: 1_800_000_000 - 86_400 * 0 )
        let days = JournalCalendarGrid.days(in: month, calendar: calendar)
        XCTAssertEqual(days.count % 7, 0)
        let real = days.compactMap { $0 }
        let monthDays = calendar.range(of: .day, in: .month, for: month)!.count
        XCTAssertEqual(real.count, monthDays)
        let first = real[0]
        let lead = days.firstIndex { $0 != nil }!
        XCTAssertEqual(lead, (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7)
        let symbols = JournalCalendarGrid.weekdaySymbols(calendar: calendar)
        XCTAssertEqual(symbols.count, 7)
        XCTAssertEqual(symbols.first, calendar.veryShortWeekdaySymbols[1])   // Monday first
    }

    func testDotRuleIsUpToThreeAndDimUnlessRated() {
        XCTAssertEqual(JournalCalendarGrid.dots(count: 0, hot: false).count, 0)
        XCTAssertEqual(JournalCalendarGrid.dots(count: 2, hot: false).count, 2)
        XCTAssertEqual(JournalCalendarGrid.dots(count: 9, hot: true).count, 3)
        XCTAssertTrue(JournalCalendarGrid.dots(count: 1, hot: true).strong)
        XCTAssertFalse(JournalCalendarGrid.dots(count: 1, hot: false).strong)
    }

    func testEveryCalendarOpensOnTodayAndTheIntroIsOneSentence() {
        XCTAssertEqual(JournalCalendarGrid.firstSelectedDay(now: now, calendar: calendar),
                       calendar.startOfDay(for: now))
        XCTAssertEqual(SharedCopy.reviewIntro,
                       "As your notes age, past thinking resurfaces here — a month ago, a year ago, on this day.")
        XCTAssertEqual(ThenVsNow.laterCaption(months: 8), "8 months later")
        XCTAssertEqual(ThenVsNow.monthsApart(then: now.addingTimeInterval(-86_400 * 250), now: now,
                                             calendar: calendar), 8)
    }
}
