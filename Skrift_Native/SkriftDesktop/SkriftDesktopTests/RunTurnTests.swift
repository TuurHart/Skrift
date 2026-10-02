import XCTest

/// Q208: the Mac's one run slot. `ProcessingCoordinator` is not compiled into this MLX-free
/// bundle, so the hand-off rule lives in `RunTurn` and is pinned here.
final class RunTurnTests: XCTestCase {

    /// The bug: a recording-stop transcribe that arrives during a Redo sat in `waiting` until
    /// some later request happened to drain it. The Redo's holder must hand it on.
    func testAJobQueuedDuringARedoRunsWhenTheRedoEnds() {
        var turn = RunTurn()
        XCTAssertTrue(turn.acquire(), "the Redo takes the free slot")

        XCTAssertFalse(turn.request(.transcribe(ids: ["rec"])), "arrives mid-Redo: queued, not run")
        XCTAssertFalse(turn.request(.process(ids: ["a"], retranscribe: [])))

        // The Redo ends and drains, oldest first.
        XCTAssertEqual(turn.advance(), .transcribe(ids: ["rec"]))
        XCTAssertEqual(turn.advance(), .process(ids: ["a"], retranscribe: []))
        XCTAssertNil(turn.advance())
        XCTAssertFalse(turn.held, "the slot is free again once the queue is empty")
    }

    func testARedoIsRefusedWhileARunHoldsTheSlotAndQueuesNothing() {
        var turn = RunTurn()
        XCTAssertTrue(turn.request(.process(ids: ["a"], retranscribe: [])))
        XCTAssertFalse(turn.acquire())
        XCTAssertTrue(turn.waiting.isEmpty)
    }

    func testAFreeSlotRunsTheFirstRequestImmediatelyAndQueuesTheRest() {
        var turn = RunTurn()
        XCTAssertTrue(turn.request(.transcribe(ids: ["a"])))
        XCTAssertFalse(turn.request(.split(id: "b")))
        XCTAssertEqual(turn.advance(), .split(id: "b"))
        XCTAssertNil(turn.advance())
        XCTAssertTrue(turn.request(.transcribe(ids: ["c"])), "released: the next request runs at once")
    }

    func testACancelledWaitingSplitIsNotHandedOn() {
        var turn = RunTurn()
        XCTAssertTrue(turn.acquire())
        XCTAssertFalse(turn.request(.split(id: "s")))
        XCTAssertTrue(turn.removeSplit(id: "s"))
        XCTAssertNil(turn.advance())
    }
}
