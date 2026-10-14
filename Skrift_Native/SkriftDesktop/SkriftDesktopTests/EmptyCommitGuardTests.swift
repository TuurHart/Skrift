import XCTest
import Foundation

/// C261 / R70: an editor commit that nets to empty (raw transcript or the Mac's polished copy)
/// never lands silently. Pure confirm state, shared by the phone, iPad and Mac editors.
final class EmptyCommitGuardTests: XCTestCase {

    // editor-clear-raw
    func testEditorClearRaw() {
        var g = EmptyCommitGuard()
        XCTAssertFalse(g.request(.raw, prior: "Jack called at nine.", proposed: ""), "an empty raw commit must park")
        XCTAssertTrue(g.isPending)
        XCTAssertEqual(g.pending?.field, .raw)
        // Cancel keeps the prior text and writes nothing.
        let cancelled = g.cancel()
        XCTAssertEqual(cancelled?.prior, "Jack called at nine.")
        XCTAssertFalse(g.isPending)

        // Confirm hands back the empty commit exactly once.
        XCTAssertFalse(g.request(.raw, prior: "Jack called at nine.", proposed: "  \n "))
        XCTAssertEqual(g.confirm()?.proposed, "  \n ")
        XCTAssertNil(g.confirm())
        XCTAssertFalse(g.isPending)
    }

    // editor-clear-polished
    func testEditorClearPolished() {
        var g = EmptyCommitGuard()
        XCTAssertFalse(g.request(.polished, prior: "Jack called at nine.", proposed: "\n"))
        XCTAssertEqual(g.pending?.field, .polished)
        XCTAssertEqual(g.cancel()?.prior, "Jack called at nine.")
        XCTAssertNotEqual(EmptyCommitGuard.title(for: .polished), EmptyCommitGuard.title(for: .raw))
        XCTAssertTrue(EmptyCommitGuard.message(for: .polished).contains("every device"))
    }

    func testOrdinaryCommitsPassStraightThrough() {
        var g = EmptyCommitGuard()
        XCTAssertTrue(g.request(.raw, prior: "old", proposed: "new"))
        XCTAssertTrue(g.request(.polished, prior: "old", proposed: "[[img_001]]"), "a photo marker is not empty")
        XCTAssertTrue(g.request(.raw, prior: "", proposed: ""), "empty over empty has nothing to lose")
        XCTAssertTrue(g.request(.raw, prior: nil, proposed: "  "))
        XCTAssertTrue(g.request(.raw, prior: "   ", proposed: ""), "a whitespace-only prior has nothing to lose")
        XCTAssertFalse(g.isPending)
    }

    func testNetsToEmptyIsTheOneRule() {
        XCTAssertTrue(EmptyCommitGuard.netsToEmpty(prior: "x", proposed: ""))
        XCTAssertTrue(EmptyCommitGuard.netsToEmpty(prior: "x", proposed: " \n\t"))
        XCTAssertFalse(EmptyCommitGuard.netsToEmpty(prior: "x", proposed: "y"))
        XCTAssertFalse(EmptyCommitGuard.netsToEmpty(prior: nil, proposed: ""))
    }
}
