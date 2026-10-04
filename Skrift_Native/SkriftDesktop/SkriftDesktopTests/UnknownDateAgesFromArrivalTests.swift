import XCTest

/// Q141 / C76 / D18 safety: a date-unknown note carries `recordedAt = MemoDate.unknown` (the epoch).
/// Every age / lookback / bucket reader must treat that as "no date" and use the arrival moment
/// (`createdAt`), or the note would be "older than 30 days" and fade at the next sweep, and the
/// Journal would file it under 1970.
final class UnknownDateAgesFromArrivalTests: XCTestCase {

    private let now = Date()
    private func daysAgo(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }

    /// An Apple Note imported `arrivedDaysAgo` days ago, no creation date in the export.
    private func undated(arrivedDaysAgo: Double) -> Memo {
        Memo(audioFilename: "", recordedAt: MemoDate.unknown, transcript: "words",
             transcriptStatus: .done, createdAt: daysAgo(arrivedDaysAgo))
    }

    func testAgeDateIsArrivalForUnknownAndRecordedOtherwise() {
        let u = undated(arrivedDaysAgo: 2)
        XCTAssertEqual(u.ageDate, u.createdAt)
        let dated = Memo(audioFilename: "m.m4a", recordedAt: daysAgo(9), createdAt: daysAgo(1))
        XCTAssertEqual(dated.ageDate, dated.recordedAt)
    }

    func testJustImportedUndatedNoteDoesNotFade() {
        let m = undated(arrivedDaysAgo: 0)
        XCTAssertFalse(MemoLifecycle.isFading(m, backlinked: [], now: now), "not 1970-old")
        XCTAssertFalse(MemoLifecycle.sweepDue(m, backlinked: [], now: now))
        XCTAssertGreaterThan(MemoLifecycle.trashesAt(m), now)
    }

    func testUndatedNoteAgesFromArrivalLikeAnyOther() {
        XCTAssertFalse(MemoLifecycle.isFading(undated(arrivedDaysAgo: 29), backlinked: [], now: now))
        XCTAssertTrue(MemoLifecycle.isFading(undated(arrivedDaysAgo: 31), backlinked: [], now: now))
        XCTAssertFalse(MemoLifecycle.sweepDue(undated(arrivedDaysAgo: 31), backlinked: [], now: now))
        XCTAssertTrue(MemoLifecycle.sweepDue(undated(arrivedDaysAgo: 61), backlinked: [], now: now))
    }

    func testSpineStationAnchorsOnArrival() {
        let m = undated(arrivedDaysAgo: 1)
        let station = MemoSpine.station(for: MemoSpine.Input.from(m, backlinked: []), now: now)
        guard case .new(let fadesAt) = station else { return XCTFail("a fresh undated import is New, got \(station)") }
        XCTAssertEqual(fadesAt.timeIntervalSince(daysAgo(1)), 30 * 86_400, accuracy: 1)
    }

    func testJournalFilesTheNoteOnItsArrivalDayNotIn1970() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let m = undated(arrivedDaysAgo: 3)
        XCTAssertEqual(LookbackProvider.journalDate(m), m.createdAt)
        XCTAssertGreaterThan(cal.component(.year, from: LookbackProvider.journalDate(m)), 2000)
        let in1970 = LookbackProvider.dayCounts(for: [m], month: MemoDate.unknown, calendar: cal)
        XCTAssertTrue(in1970.isEmpty, "no note sits in the January 1970 calendar month")
        let arrival = LookbackProvider.dayCounts(for: [m], month: daysAgo(3), calendar: cal)
        XCTAssertEqual(arrival.values.map(\.count).reduce(0, +), 1, "it sits in its arrival month")
        XCTAssertTrue(LookbackProvider.memos(for: [m], onDay: MemoDate.unknown, calendar: cal).isEmpty)
    }

    func testThenVsNowTreatsAnUndatedImportAsNewNotAncient() {
        let m = undated(arrivedDaysAgo: 1)
        let cut = daysAgo(7)
        XCTAssertEqual(ThenVsNow.recents(in: [m], since: cut).map(\.id), [m.id], "recent, by arrival")
        XCTAssertEqual(ThenVsNow.dates(of: [m])[m.id], m.createdAt)
    }

    func testDisplayStillSaysDateUnknown() {
        let m = undated(arrivedDaysAgo: 1)
        XCTAssertEqual(MemoDate.label(m.recordedAt), "Date unknown")
        XCTAssertEqual(MemoDate.day(m.recordedAt), "Date unknown")
        XCTAssertEqual(MemoDate.time(m.recordedAt), "Date unknown")
        XCTAssertNotEqual(MemoDate.day(Date()), "Date unknown")
    }
}
