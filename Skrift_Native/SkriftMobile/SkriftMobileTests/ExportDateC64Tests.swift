import XCTest
@testable import SkriftMobile

/// Q433 (C64, R15), the phone's half: a note recorded at 23:30 local exports `date:` = that
/// local day through the real phone path (`MemoExporter.markdown`). The Mac's half
/// (`ExportDiffHarnessTests.testLateNightNoteHasOneDateOnPhoneAndMac`) pins the SAME literals on
/// the Mac path (sweep → `PipelineFile` → compile), so the two devices agree.
final class ExportDateC64Tests: XCTestCase {

    private var savedZone: TimeZone?
    override func setUp() { super.setUp(); savedZone = NSTimeZone.default }
    override func tearDown() {
        if let savedZone { NSTimeZone.default = savedZone }
        super.tearDown()
    }

    func testLateNightNoteExportsItsLocalDay() throws {
        let cases: [(zone: String, recorded: String, day: String)] = [
            ("Europe/Lisbon", "2026-09-14T23:30:00+01:00", "2026-09-14"),
            ("Asia/Tokyo", "2026-09-14T23:30:00+09:00", "2026-09-14"),
            ("America/Los_Angeles", "2026-09-14T23:30:00-07:00", "2026-09-14"),
        ]
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        for c in cases {
            NSTimeZone.default = TimeZone(identifier: c.zone)!
            let recorded = try XCTUnwrap(iso.date(from: c.recorded))
            let memo = Memo(recordedAt: recorded, title: "Late note", transcript: "Written just before midnight.",
                            transcriptStatus: .done, significance: 0.5)
            let md = MemoExporter.markdown(for: memo, people: [])
            let day = md.components(separatedBy: "\n").first { $0.hasPrefix("date: ") }.map { String($0.dropFirst(6)) }
            XCTAssertEqual(day, c.day, "\(c.zone): phone date")
            XCTAssertEqual(MemoExporter.markdown(for: memo, people: [], profile: .portfolio)
                .components(separatedBy: "\n").first { $0.hasPrefix("date: ") }, "date: \(c.day)",
                           "\(c.zone): portfolio profile, same rule")
        }
    }
}
