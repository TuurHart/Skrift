import XCTest

/// Q178: the way-out row's meta line and urgency tone live once in `WayOut` (Shared); the phone's
/// `WayOutView` and the Mac's `WayOutColumn` both render these values.
final class WayOutDisplayTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func daysAgo(_ n: Int) -> Date { now.addingTimeInterval(-Double(n) * 86_400) }
    private func label(_ d: Date) -> String { d.formatted(date: .abbreviated, time: .omitted) }

    private func memo(deletedDaysAgo: Int? = nil, duration: Double = 0) -> Memo {
        let id = UUID()
        let m = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", recordedAt: daysAgo(40),
                     title: nil, transcript: "hello", transcriptStatus: .done, significance: 0,
                     deletedAt: deletedDaysAgo.map { daysAgo($0) })
        m.duration = duration
        return m
    }

    func testFadingRowReadsRecordedDateThenDuration() {
        let parts = WayOut.metaParts(for: memo(duration: 34))
        XCTAssertEqual(parts.map(\.text), [label(daysAgo(40)), "0:34"])
        XCTAssertTrue(parts.allSatisfy { !$0.emphasized })
    }

    func testDeletedRowSaysDeletedAndKeepsDuration() {
        let parts = WayOut.metaParts(for: memo(deletedDaysAgo: 3, duration: 63))
        XCTAssertEqual(parts.map(\.text), ["deleted \(label(daysAgo(3)))", "1:03"])
    }

    func testReplacedWordWinsAndIsEmphasised() {
        let m = memo(deletedDaysAgo: 3)
        m.replacedAt = daysAgo(2)
        let parts = WayOut.metaParts(for: m)
        XCTAssertEqual(parts.first?.text, "replaced \(label(daysAgo(2)))")
        XCTAssertEqual(parts.first?.emphasized, true)
        XCTAssertFalse(parts.contains { $0.text.hasPrefix("deleted") })
    }

    func testToneIsRedInsideThreeDaysAmberFadingMutedDeleted() {
        let soon = now.addingTimeInterval(2 * 86_400), later = now.addingTimeInterval(10 * 86_400)
        XCTAssertEqual(WayOut.tone(for: .fading(deletedAt: soon), now: now), .urgent)
        XCTAssertEqual(WayOut.tone(for: .deleted(goneAt: soon), now: now), .urgent)
        XCTAssertEqual(WayOut.tone(for: .fading(deletedAt: later), now: now), .warm)
        XCTAssertEqual(WayOut.tone(for: .deleted(goneAt: later), now: now), .quiet)
    }
}
