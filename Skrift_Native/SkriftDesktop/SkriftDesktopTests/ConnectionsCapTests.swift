import XCTest
import Foundation

/// `RetrievalTuning.cappedRelated` — the Mac Connections panel's top-K cap.
/// The contract: closest `cap` rows win, EXCEPT the genuinely earliest row
/// always makes the cut (the Date rail's "first mentioned" claim must stay
/// true at any corpus size), and score-DESC order is preserved.
final class ConnectionsCapTests: XCTestCase {
    private struct Row: Equatable {
        let name: String
        let score: Float
        let date: Date
    }

    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: Double(n) * 86_400) }

    /// score-DESC fixture; "spark" is both the WEAKEST match and the EARLIEST note.
    private var rows: [Row] {
        [Row(name: "best",   score: 0.9, date: day(80)),
         Row(name: "second", score: 0.8, date: day(40)),
         Row(name: "third",  score: 0.7, date: day(60)),
         Row(name: "fourth", score: 0.6, date: day(30)),
         Row(name: "fifth",  score: 0.5, date: day(70)),
         Row(name: "spark",  score: 0.4, date: day(1))]
    }

    func testUnderCapPassesThrough() {
        XCTAssertEqual(RetrievalTuning.cappedRelated(rows, cap: 6, date: \.date), rows)
        XCTAssertEqual(RetrievalTuning.cappedRelated(rows, cap: 10, date: \.date), rows)
    }

    func testEarliestSwapsInForTheWeakestShown() {
        let shown = RetrievalTuning.cappedRelated(rows, cap: 4, date: \.date)
        XCTAssertEqual(shown.map(\.name), ["best", "second", "third", "spark"],
                       "top cap-1 by score + the earliest in the last slot")
    }

    func testNoSwapWhenEarliestAlreadyShown() {
        // Make the top scorer also the earliest — plain top-K prefix.
        var r = rows
        r[0] = Row(name: "best", score: 0.9, date: day(0))
        let shown = RetrievalTuning.cappedRelated(r, cap: 4, date: \.date)
        XCTAssertEqual(shown.map(\.name), ["best", "second", "third", "fourth"])
    }

    func testCapOneShowsTheEarliest() {
        let shown = RetrievalTuning.cappedRelated(rows, cap: 1, date: \.date)
        XCTAssertEqual(shown.map(\.name), ["spark"])
    }

    func testEarliestTieBreaksToTheStrongerMatch() {
        // Two rows share the earliest date — the higher-scored one (earlier
        // index in a score-DESC list) is the one guaranteed a slot.
        var r = rows
        r[4] = Row(name: "fifth", score: 0.5, date: day(1))   // ties "spark"
        let shown = RetrievalTuning.cappedRelated(r, cap: 4, date: \.date)
        XCTAssertEqual(shown.map(\.name), ["best", "second", "third", "fifth"])
    }
}
