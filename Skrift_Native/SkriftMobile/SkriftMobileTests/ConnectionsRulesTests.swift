import XCTest
@testable import SkriftMobile

/// Q119 (R58, C110, C210, D30): the iPad Connections panel and the compact phone
/// footer follow the Mac panel's rules. Pure functions only: the importance stop,
/// the row cap + "Show all", the RetrievalGate states + failure line, the default
/// sort, and the footer's consent gate.
final class ConnectionsRulesTests: XCTestCase {

    private func row(_ i: Int, score: Float, day: Int) -> ConnectionRowVM {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: day))!
        return ConnectionRowVM(id: UUID(), title: "n\(i)", date: date,
                               score: score, significance: 0.6)
    }

    // MARK: importance = the ThreeBallScale stop (C210), the Mac's text

    func testImportanceReadoutBucketsLegacyValuesToTheStop() {
        XCTAssertEqual(ConnectionsPanelLogic.importanceReadout(0.7), "1.0", "0.7–1.0 → Important")
        XCTAssertEqual(ConnectionsPanelLogic.importanceReadout(1.0), "1.0")
        XCTAssertEqual(ConnectionsPanelLogic.importanceReadout(0.4), "0.6", "0.4–0.6 → Useful")
        XCTAssertEqual(ConnectionsPanelLogic.importanceReadout(0.6), "0.6")
        XCTAssertEqual(ConnectionsPanelLogic.importanceReadout(0.1), "0.3", "0.1–0.3 → Passing")
        XCTAssertEqual(ConnectionsPanelLogic.importanceReadout(0.3), "0.3")
        XCTAssertNil(ConnectionsPanelLogic.importanceReadout(0), "unrated shows nothing")
    }

    func testImportanceAmberIsTheTopStopOnly() {
        XCTAssertTrue(ConnectionsPanelLogic.importanceIsTop(0.7))
        XCTAssertTrue(ConnectionsPanelLogic.importanceIsTop(1.0))
        XCTAssertFalse(ConnectionsPanelLogic.importanceIsTop(0.6))
        XCTAssertFalse(ConnectionsPanelLogic.importanceIsTop(0))
    }

    func testIPadReadoutMatchesTheSharedMacReadout() {
        for v in stride(from: 0.0, through: 1.0, by: 0.1) {
            XCTAssertEqual(ConnectionsPanelLogic.importanceReadout(v), ThreeBallScale.readout(for: v))
            XCTAssertEqual(ConnectionsPanelLogic.importanceIsTop(v), ThreeBallScale.isTopStop(v))
        }
    }

    // MARK: cap = the Mac's 7, then "Show all N" (R58)

    func testCapIsTheMacsSevenWithShowAllPastIt() {
        let nine = (0..<9).map { row($0, score: 0.9 - Float($0) * 0.05, day: 10 + $0) }
        XCTAssertEqual(ConnectionsPanelLogic.visibleRows(nine, showAll: false).count, 7)
        XCTAssertEqual(ConnectionsPanelLogic.visibleRows(nine, showAll: true).count, 9)
        XCTAssertTrue(ConnectionsPanelLogic.showsShowAll(count: 9))
        XCTAssertTrue(ConnectionsPanelLogic.showsShowAll(count: 8))
        XCTAssertFalse(ConnectionsPanelLogic.showsShowAll(count: 7))
        XCTAssertFalse(ConnectionsPanelLogic.showsShowAll(count: 4),
                       "the old relatedK = 4 cap is gone from the panel")
    }

    func testCapKeepsTheEarliestRow() {
        // The weakest (index 8) is also the earliest (day 1): it must survive the cap.
        var rows = (0..<8).map { row($0, score: 0.9 - Float($0) * 0.05, day: 10 + $0) }
        let earliest = row(8, score: 0.46, day: 1)
        rows.append(earliest)
        let shown = ConnectionsPanelLogic.visibleRows(rows, showAll: false)
        XCTAssertEqual(shown.count, 7)
        XCTAssertTrue(shown.contains(earliest))
    }

    // MARK: panel states = RetrievalGate.derive (C110, R58)

    func testPanelStatesFollowTheSharedGate() {
        XCTAssertEqual(ConnectionsPanelLogic.panelState(
            active: false, downloadFraction: nil, sweeping: false, sweepProgress: nil,
            hasRows: false, querying: false), .gate)
        XCTAssertEqual(ConnectionsPanelLogic.panelState(
            active: false, downloadFraction: 0.4, sweeping: false, sweepProgress: nil,
            hasRows: false, querying: false), .downloading(fraction: 0.4))
        XCTAssertEqual(ConnectionsPanelLogic.panelState(
            active: false, downloadFraction: 1.0, sweeping: false, sweepProgress: nil,
            hasRows: false, querying: false), .preparing)
        XCTAssertEqual(ConnectionsPanelLogic.panelState(
            active: true, downloadFraction: nil, sweeping: true, sweepProgress: (3, 10),
            hasRows: false, querying: false), .indexing(done: 3, total: 10))
        XCTAssertEqual(ConnectionsPanelLogic.panelState(
            active: true, downloadFraction: nil, sweeping: false, sweepProgress: nil,
            hasRows: false, querying: true), .finding)
        XCTAssertEqual(ConnectionsPanelLogic.panelState(
            active: true, downloadFraction: nil, sweeping: true, sweepProgress: (3, 10),
            hasRows: true, querying: false), .ready, "rows win over progress")
    }

    func testFailedLookupReadsUnavailableNotEmpty() {
        XCTAssertEqual(RetrievalGate.failure(state: .ready, hasRows: false,
                                             lastError: "Related lookup failed: x"),
                       "Related lookup failed: x")
        XCTAssertNil(RetrievalGate.failure(state: .ready, hasRows: false, lastError: nil),
                     "no error = the honest empty state")
        XCTAssertNil(RetrievalGate.failure(state: .ready, hasRows: true, lastError: "x"),
                     "rows on screen win")
        XCTAssertNil(RetrievalGate.failure(state: .finding, hasRows: false, lastError: "x"))
        XCTAssertEqual(RetrievalGate.Copy.unavailableTitle, "Connections unavailable")
        XCTAssertNotEqual(RetrievalGate.Copy.unavailableTitle, RetrievalGate.Copy.emptyTitle)
    }

    // MARK: default sort = the Mac's Date (signed related-panel mock)

    func testDefaultSortIsDate() {
        XCTAssertTrue(RetrievalTuning.connectionsDefaultSortByDate)
    }

    // MARK: the compact footer's consent gate (C215 canSummon)

    func testFooterGateIsRatedAndUnlocked() {
        let unrated = Memo(transcript: "A passing thought.", significance: 0)
        let rated = Memo(transcript: "The harbor at dawn.", significance: 0.6)
        XCTAssertFalse(ConnectionsPanelLogic.canSummon(unrated, isLocked: false))
        XCTAssertTrue(ConnectionsPanelLogic.canSummon(rated, isLocked: false))
        XCTAssertFalse(ConnectionsPanelLogic.canSummon(rated, isLocked: true))
    }
}
