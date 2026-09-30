import XCTest
@testable import SkriftMobile

/// Q82 group 8: the Journal river (Important lately + Looking back, one exclusion rule) and the
/// Then vs Now window live once in `Shared/`. Identical file in the phone and Mac test targets:
/// same input, same output.
final class LookbackRiverTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func memo(daysAgo: Int, significance: Double) -> Memo {
        let id = UUID()
        return Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a",
                    recordedAt: now.addingTimeInterval(-Double(daysAgo) * 86_400),
                    title: nil, transcript: "hello", transcriptStatus: .done, significance: significance)
    }

    /// The only note near the "1 week ago" anchor is also Important lately: the phone shows it
    /// under Important and NOT again as a lookback; the Mac (no Important card) keeps it as the
    /// lookback so it is never hidden.
    func testAnImportantNoteIsExcludedFromLookbacksOnlyWhereItIsShownAsImportant() {
        let n = memo(daysAgo: 7, significance: 1.0)
        let phone = LookbackProvider.river(for: [n], now: now, calendar: calendar, showImportantLately: true)
        XCTAssertEqual(phone.important.map(\.id), [n.id])
        XCTAssertFalse(phone.entries.contains { $0.id == n.id })
        let mac = LookbackProvider.river(for: [n], now: now, calendar: calendar, showImportantLately: false)
        XCTAssertTrue(mac.important.isEmpty)
        XCTAssertEqual(mac.entries.first?.id, n.id)
        XCTAssertEqual(mac.entries.first?.label, "1 week ago")
    }

    func testTheThenVsNowPairNeverShowsAgainAsALookback() {
        let a = memo(daysAgo: 7, significance: 0.3), b = memo(daysAgo: 30, significance: 0.3)
        let plain = LookbackProvider.river(for: [a, b], now: now, calendar: calendar, showImportantLately: false)
        XCTAssertEqual(Set(plain.entries.map(\.id)), [a.id, b.id])
        let paired = LookbackProvider.river(for: [a, b], now: now, calendar: calendar,
                                            thenNow: ThenVsNow.Pair(then: b.id, now: a.id),
                                            showImportantLately: false)
        XCTAssertFalse(paired.entries.contains { $0.id == a.id || $0.id == b.id })
    }

    func testThenVsNowWindowAndRecentsAreTheSameOnBothApps() {
        let w = ThenVsNow.window(now: now, calendar: calendar)
        XCTAssertNotNil(w)
        XCTAssertEqual(w!.recentCut, now.addingTimeInterval(-14 * 86_400))
        XCTAssertEqual(calendar.dateComponents([.month], from: w!.gapCut, to: now).month, 6)
        let fresh = memo(daysAgo: 2, significance: 0), older = memo(daysAgo: 20, significance: 0)
        XCTAssertEqual(ThenVsNow.recents(in: [older, fresh], since: w!.recentCut).map(\.id), [fresh.id])
        XCTAssertEqual(ThenVsNow.dates(of: [fresh])[fresh.id], fresh.recordedAt)
    }
}
