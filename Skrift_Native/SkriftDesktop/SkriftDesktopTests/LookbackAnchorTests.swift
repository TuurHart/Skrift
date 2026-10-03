import XCTest
import Foundation

/// Q288 (D173, C231): the Mac Journal's Looking back anchors on TODAY like the phone, the iPad and
/// the signed journal-desktop mock. Picking another calendar day only changes the day list below.
final class LookbackAnchorTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func memo(daysAgo: Int) -> Memo {
        let id = UUID()
        return Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a",
                    recordedAt: now.addingTimeInterval(-Double(daysAgo) * 86_400),
                    title: nil, transcript: "hello", transcriptStatus: .done, significance: 0.3)
    }

    /// The river labels come from the anchor: a note 7 days before `now` is "1 week ago" only
    /// when `now` is the anchor, so an anchor drifting to another day would change the label.
    func testRiverLabelsAreRelativeToTheAnchorDay() {
        let n = memo(daysAgo: 7)
        let today = LookbackProvider.river(for: [n], now: now, calendar: calendar, showImportantLately: false)
        XCTAssertEqual(today.entries.map(\.label), ["1 week ago"])
        let shifted = LookbackProvider.river(for: [n], now: now.addingTimeInterval(-6 * 86_400),
                                             calendar: calendar, showImportantLately: false)
        XCTAssertNotEqual(shifted.entries.map(\.label), ["1 week ago"])
    }

    /// The Mac Journal view must not pass its selected day into the river (source scan: the view
    /// is not in the host-less test target).
    func testMacJournalRiverIsNotAnchoredOnTheSelectedDay() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Features/Journal/JournalView.swift")
        guard let src = try? String(contentsOf: url, encoding: .utf8) else { throw XCTSkip("no JournalView.swift") }
        let code = src.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if let r = line.range(of: "//") { return String(line[..<r.lowerBound]) }
                return String(line)
            }.joined(separator: "\n")
        XCTAssertTrue(code.contains("LookbackProvider.river("), "river call moved; update this test")
        XCTAssertFalse(code.contains("now: selectedDay"), "Looking back must anchor on today (D173)")
        XCTAssertTrue(code.contains("now: Date()"))
    }
}
