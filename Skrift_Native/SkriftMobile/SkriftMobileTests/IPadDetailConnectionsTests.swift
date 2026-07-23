import XCTest
@testable import SkriftMobile

/// Pure logic behind the iPad Connections panel (mock m3 v2 — the Mac panel,
/// copied): the importance decimal, the Closest/Date-rail ordering, and the
/// SHARED why-chip derivation. No Memo, no main actor. (The v1 closeness-% was
/// REMOVED in v2 — the Mac keeps closeness behind hover; touch shows none.)
final class IPadDetailConnectionsTests: XCTestCase {

    private func row(_ title: String, score: Float, significance: Double = 0.5,
                     day: Int) -> ConnectionRowVM {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: day))!
        return ConnectionRowVM(id: UUID(), title: title, date: date,
                               score: score, significance: significance)
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

    // MARK: ordering — Closest = score DESC; Date mode feeds the rail OLDEST first

    func testClosestOrdersByScoreDescending() {
        let rows = [
            row("mid", score: 0.6, day: 10),
            row("top", score: 0.9, day: 2),
            row("low", score: 0.3, day: 20),
        ]
        let ordered = ConnectionsPanelLogic.ordered(rows, byDate: false)
        XCTAssertEqual(ordered.map(\.title), ["top", "mid", "low"])
    }

    func testDateOrdersOldestFirstForTheRail() {
        let rows = [
            row("mid", score: 0.6, day: 10),
            row("top", score: 0.9, day: 2),
            row("low", score: 0.3, day: 20),
        ]
        let ordered = ConnectionsPanelLogic.ordered(rows, byDate: true)
        XCTAssertEqual(ordered.map(\.title), ["top", "mid", "low"]) // day 2, 10, 20 — the arc
    }

    // MARK: shared why-chips (the Mac's derivation, now Shared/Retrieval)

    func testWhyChipsSharedTagsAndTerms() {
        let chips = ConnectionWhyDerivation.chips(
            currentNames: [], currentTags: ["skrift", "ipad"],
            currentBody: "thinking about the polish pipeline and the polish contract",
            otherNames: [], otherTags: ["ipad", "books"],
            otherBody: "the polish pipeline needs a device gate")
        XCTAssertTrue(chips.contains(ConnectionWhy(kind: .tag, text: "#ipad")))
        XCTAssertTrue(chips.contains(ConnectionWhy(kind: .term, text: "polish")))
        XCTAssertFalse(chips.contains(ConnectionWhy(kind: .tag, text: "#books")))
    }

    func testWhyChipsPersonComesFromNamesIntersection() {
        let chips = ConnectionWhyDerivation.chips(
            currentNames: ["Hendrik", "Rox"], currentTags: [], currentBody: "",
            otherNames: ["Hendrik"], otherTags: [], otherBody: "")
        XCTAssertEqual(chips.first, ConnectionWhy(kind: .person, text: "Hendrik"))
    }

    func testWhyChipsCapAtFour() {
        let body = "alpha_ bravo_ charlie_ delta_ echo_"  // 5 shared ≥5-char terms
            .replacingOccurrences(of: "_", with: "xx")
        let chips = ConnectionWhyDerivation.chips(
            currentNames: ["A", "B", "C"], currentTags: ["t1", "t2", "t3"], currentBody: body,
            otherNames: ["A", "B", "C"], otherTags: ["t1", "t2", "t3"], otherBody: body)
        XCTAssertEqual(chips.count, 4)   // 2 people + 2 tags fill the cap; no terms
        XCTAssertEqual(chips.filter { $0.kind == .person }.count, 2)
        XCTAssertEqual(chips.filter { $0.kind == .tag }.count, 2)
    }
}
