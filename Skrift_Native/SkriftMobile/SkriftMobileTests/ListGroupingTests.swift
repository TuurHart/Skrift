import XCTest
@testable import SkriftMobile

/// Q358 / D190 / D193: the notes list groups like Apple Notes — Today, Previous 7 Days,
/// Previous 30 Days, then one group per month this year, then one per earlier year — and the
/// row's line 2 carries the detail the old day headers did (the time today, "Yesterday", the
/// weekday this week, "27 Sep" this year, "24/12/2025" before). Days are counted between
/// calendar MIDNIGHTS in the device's time zone (Europe/Lisbon here), never as 24-hour spans,
/// so a note from 23:59 last night is never "Today" and one from 00:01 is.
final class ListGroupingTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        c.locale = Locale(identifier: "en_GB")
        return c
    }()

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
    }
    /// Tue 13 Oct 2026, 10:00 Lisbon — the mock's NOW.
    private var now: Date { at(2026, 10, 13, 10, 0) }
    private func bucket(_ d: Date, now: Date? = nil) -> String { MemoDate.bucket(d, now: now ?? self.now, calendar: cal) }
    private func line(_ d: Date, now: Date? = nil) -> String { MemoDate.listDate(d, now: now ?? self.now, calendar: cal) }

    // MARK: - Group boundaries

    func testTodayRunsFromLocalMidnight() {
        XCTAssertEqual(bucket(at(2026, 10, 13, 0, 1)), "Today")
        XCTAssertEqual(bucket(at(2026, 10, 13, 9, 59)), "Today")
        XCTAssertEqual(bucket(at(2026, 10, 12, 23, 59)), "Yesterday", "23:59 last night is yesterday")
    }

    func testPreviousSevenDaysEndsAtDaySeven() {
        XCTAssertEqual(bucket(at(2026, 10, 12)), "Yesterday")   // 1 day (D197)
        XCTAssertEqual(bucket(at(2026, 10, 11, 23, 59)), "Previous 7 Days")   // 2 days
        XCTAssertEqual(bucket(at(2026, 10, 6, 0, 1)), "Previous 7 Days")   // 7 days
        XCTAssertEqual(bucket(at(2026, 10, 5, 23, 59)), "Previous 30 Days")   // 8 days
    }

    func testPreviousThirtyDaysEndsAtDayThirty() {
        XCTAssertEqual(bucket(at(2026, 9, 13, 0, 1)), "Previous 30 Days")   // 30 days
        XCTAssertEqual(bucket(at(2026, 9, 12, 23, 59)), "September")   // 31 days
    }

    func testOlderThisYearGroupsByMonthThenEarlierYearsByYear() {
        XCTAssertEqual(bucket(at(2026, 8, 21)), "August")
        XCTAssertEqual(bucket(at(2026, 1, 1, 0, 0)), "January")
        XCTAssertEqual(bucket(at(2025, 12, 31, 23, 59)), "2025")
        XCTAssertEqual(bucket(at(2019, 6, 1)), "2019")
    }

    func testEarlyJanuaryStillReachesBackIntoDecember() {
        // On 3 Jan, a 20-day-old December note is "Previous 30 Days", not "2025".
        let jan3 = at(2026, 1, 3, 9, 0)
        XCTAssertEqual(bucket(at(2025, 12, 14), now: jan3), "Previous 30 Days")
        XCTAssertEqual(bucket(at(2025, 11, 20), now: jan3), "2025")
    }

    func testMidnightCountsAcrossTheDaylightSavingChange() {
        // Lisbon falls back on Sun 25 Oct 2026: that day is 25 hours long. A note from
        // 23:30 the day before the change is still exactly 1 day back the morning after.
        let mon = at(2026, 10, 26, 0, 30)
        XCTAssertEqual(bucket(at(2026, 10, 26, 0, 5), now: mon), "Today")
        XCTAssertEqual(bucket(at(2026, 10, 25, 23, 30), now: mon), "Yesterday")
        XCTAssertEqual(line(at(2026, 10, 25, 23, 30), now: mon), "Yesterday")
    }

    func testFutureDatesReadAsToday() {
        XCTAssertEqual(bucket(at(2026, 10, 14)), "Today", "a clock-skewed note never makes its own group")
    }

    func testUnknownDateKeepsItsWords() {
        XCTAssertEqual(bucket(MemoDate.unknown), MemoDate.unknownLabel)
        XCTAssertEqual(line(MemoDate.unknown), MemoDate.unknownLabel)
    }

    // MARK: - Line-2 date

    func testLineTwoDate() {
        XCTAssertEqual(line(at(2026, 10, 13, 9, 41)), "09:41")
        XCTAssertEqual(line(at(2026, 10, 12, 21, 5)), "Yesterday")
        XCTAssertEqual(line(at(2026, 10, 9, 11, 2)), "Friday")
        XCTAssertEqual(line(at(2026, 10, 6, 8, 0)), "Tuesday", "7 days back is still the weekday")
        XCTAssertEqual(line(at(2026, 9, 27, 10, 15)), "27 Sep")
        XCTAssertEqual(line(at(2025, 12, 24, 19, 30)), "24/12/2025")
    }

    // MARK: - Group order and the Q97 date rule, through the list's own grouping pass

    func testGroupsArriveInListOrderOnePerBucket() {
        let dates = [at(2026, 10, 13, 9, 41), at(2026, 10, 13, 8, 12), at(2026, 10, 12, 21, 5),
                     at(2026, 10, 7), at(2026, 9, 27), at(2026, 9, 2), at(2026, 8, 21), at(2026, 8, 3),
                     at(2025, 12, 24)]
        let groups = NotesListModel.dayGroups(dates) { bucket($0) }
        XCTAssertEqual(groups.map(\.title),
                       ["Today", "Yesterday", "Previous 7 Days", "Previous 30 Days", "September", "August", "2025"])
        XCTAssertEqual(groups.map(\.items.count), [2, 1, 1, 1, 1, 2, 1])
    }

    func testANoteThatArrivedYesterdayGroupsByItsRecordedDay() {
        // Q97: an old note synced in yesterday (createdAt) files under its recorded day.
        let m = Memo(recordedAt: at(2026, 9, 1), createdAt: at(2026, 10, 12))
        let d = NotesListModel.groupDate(recordedAt: m.recordedAt, lastEditedAt: m.lastEditedAt, byEditTime: false)
        XCTAssertEqual(bucket(d), "September")
    }

    // MARK: - The row's reliable title line (Q349 pick 10)

    func testUntitledRowTakesItsFirstSentenceAsTitle() {
        let l = NoteRowText.lines(title: nil, snippet: "Morning pages. Slept badly again, the neighbours were drilling.")
        XCTAssertEqual(l.title, "Morning pages")
        XCTAssertEqual(l.line, "Slept badly again, the neighbours were drilling.")
    }

    func testTitledRowKeepsItsTitleAndNeverRepeatsIt() {
        XCTAssertEqual(NoteRowText.lines(title: "Groceries", snippet: "Oat milk, eggs").line, "Oat milk, eggs")
        XCTAssertNil(NoteRowText.lines(title: "Whiteboard", snippet: "Whiteboard").line)
        XCTAssertEqual(NoteRowText.lines(title: nil, snippet: nil, busy: "Transcribing").busy, "Transcribing…")
    }

    // MARK: - D197 / Q377: Yesterday, and the Recorded / Added picker drives the groups

    func testYesterdayRunsFromLisbonMidnightToMidnight() {
        XCTAssertEqual(bucket(at(2026, 10, 12, 0, 0)), "Yesterday")
        XCTAssertEqual(bucket(at(2026, 10, 12, 23, 59)), "Yesterday")
        XCTAssertEqual(bucket(at(2026, 10, 11, 23, 59)), "Previous 7 Days", "00:00 two days back is no longer yesterday")
        XCTAssertEqual(bucket(at(2026, 10, 13, 0, 0)), "Today")
    }

    func testAnOldImportAddedTodayLandsInItsRealMonthByDefault() {
        let m = Memo(recordedAt: at(2026, 3, 9), createdAt: at(2026, 10, 13, 8, 0))
        let rec = NotesListModel.groupDate(recordedAt: m.recordedAt, lastEditedAt: m.lastEditedAt, byEditTime: false,
                                           addedAt: m.addedAt, field: .recorded)
        XCTAssertEqual(bucket(rec), "March")
        let add = NotesListModel.groupDate(recordedAt: m.recordedAt, lastEditedAt: m.lastEditedAt, byEditTime: false,
                                           addedAt: m.addedAt, field: .added)
        XCTAssertEqual(bucket(add), "Today", "the Added picker groups by the day it entered Skrift")
    }

    func testDateGroupsOrderSectionsAndRowsByTheGroupingDate() {
        // (name, recorded, added): the import was added today but recorded in March.
        let rows: [(String, Date, Date)] = [("import", at(2026, 3, 9), at(2026, 10, 13, 8)),
                                            ("today", at(2026, 10, 13, 9), at(2026, 10, 13, 9)),
                                            ("last-night", at(2026, 10, 12, 21), at(2026, 10, 12, 21)),
                                            ("earlier", at(2026, 10, 13, 7), at(2026, 10, 13, 7))]
        // The list arrives in ADDED order (the sort), as the apps' own sorts give it.
        let arrived = rows.sorted { $0.2 > $1.2 }
        let byRecorded = NotesListModel.dateGroups(arrived, date: { $0.1 }, ascending: false) { bucket($0) }
        XCTAssertEqual(byRecorded.map(\.title), ["Today", "Yesterday", "March"])
        XCTAssertEqual(byRecorded[0].items.map(\.0), ["today", "earlier"], "newest of the same date first")
        let byAdded = NotesListModel.dateGroups(arrived, date: { $0.2 }, ascending: false) { bucket($0) }
        XCTAssertEqual(byAdded.map(\.title), ["Today", "Yesterday"])
        XCTAssertEqual(byAdded[0].items.map(\.0), ["today", "import", "earlier"])
        let oldest = NotesListModel.dateGroups(arrived, date: { $0.1 }, ascending: true) { bucket($0) }
        XCTAssertEqual(oldest.map(\.title), ["March", "Yesterday", "Today"])
    }

    func testRecentlyEditedGroupsByEditDay() {
        let m = Memo(recordedAt: at(2026, 9, 1), createdAt: at(2026, 9, 1), editedAt: at(2026, 10, 13, 8, 0))
        let d = NotesListModel.groupDate(recordedAt: m.recordedAt, lastEditedAt: m.lastEditedAt, byEditTime: true)
        XCTAssertEqual(bucket(d), "Today")
    }
}
