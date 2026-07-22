import XCTest
@testable import SkriftMobile

/// Pure logic behind the iPad Connections panel (mock m3): closeness %, the
/// importance decimal, and the Closest⇄Date ordering. No Memo, no main actor.
final class IPadDetailConnectionsTests: XCTestCase {

    private func row(_ title: String, score: Float, significance: Double = 0.5,
                     day: Int) -> ConnectionRowVM {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: day))!
        return ConnectionRowVM(id: UUID(), title: title, date: date,
                               score: score, significance: significance)
    }

    // MARK: closeness %

    func testClosenessPercentRoundsScoreTimes100() {
        XCTAssertEqual(ConnectionsPanelLogic.closenessPct(0.82), 82)
        XCTAssertEqual(ConnectionsPanelLogic.closenessPct(0.6), 60)
        XCTAssertEqual(ConnectionsPanelLogic.closenessPct(1.0), 100)
        XCTAssertEqual(ConnectionsPanelLogic.closenessPct(0.0), 0)
    }

    func testClosenessPercentRoundsHalvesAway() {
        XCTAssertEqual(ConnectionsPanelLogic.closenessPct(0.746), 75) // 74.6 → 75
        XCTAssertEqual(ConnectionsPanelLogic.closenessPct(0.744), 74) // 74.4 → 74
    }

    // MARK: importance decimal (unrated → nil)

    func testImportanceTextOneDecimal() {
        XCTAssertEqual(ConnectionsPanelLogic.importanceText(0.8), "0.8")
        XCTAssertEqual(ConnectionsPanelLogic.importanceText(0.7), "0.7")
    }

    func testImportanceTextTopStepIsOnePointZero() {
        XCTAssertEqual(ConnectionsPanelLogic.importanceText(1.0), "1.0")
    }

    func testImportanceTextUnratedIsNil() {
        // No fake "0.0" — unrated shows nothing (no-bad-info; matches the Mac panel).
        XCTAssertNil(ConnectionsPanelLogic.importanceText(0.0))
    }

    // MARK: Closest ⇄ Date ordering

    func testClosestOrdersByScoreDescending() {
        let rows = [
            row("mid", score: 0.6, day: 10),
            row("top", score: 0.9, day: 2),
            row("low", score: 0.3, day: 20),
        ]
        let ordered = ConnectionsPanelLogic.ordered(rows, byDate: false)
        XCTAssertEqual(ordered.map(\.title), ["top", "mid", "low"])
    }

    func testDateOrdersByDateNewestFirst() {
        let rows = [
            row("mid", score: 0.6, day: 10),
            row("top", score: 0.9, day: 2),
            row("low", score: 0.3, day: 20),
        ]
        let ordered = ConnectionsPanelLogic.ordered(rows, byDate: true)
        XCTAssertEqual(ordered.map(\.title), ["low", "mid", "top"]) // day 20, 10, 2
    }
}
