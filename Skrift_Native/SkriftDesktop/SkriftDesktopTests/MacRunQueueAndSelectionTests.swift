import XCTest

/// Q77, items (a) and (c) — the pure halves.
///
/// (c) "right mouse button Process worked flaky": the coordinator runs one batch at a time and
/// used to REFUSE a Process click while a run was live (and silently drop an import's own
/// transcription). `RunQueue` is what a request waits in now.
/// (a) "I can't shift select multiple": `ListSelection` is the click rule behind ⇧/⌘-click.
final class MacRunQueueAndSelectionTests: XCTestCase {

    // MARK: - (c) RunQueue

    func testRequestsArrivingDuringARunWaitInOrderAndAreNotLost() {
        var q = RunQueue()
        q.enqueue(.process(ids: ["a"], retranscribe: []))
        q.enqueue(.process(ids: ["b", "c"], retranscribe: []))
        XCTAssertEqual(q.next(), .process(ids: ["a"], retranscribe: []))
        XCTAssertEqual(q.next(), .process(ids: ["b", "c"], retranscribe: []))
        XCTAssertNil(q.next())
    }

    func testTheSameNoteClickedTwiceRunsOnce() {
        var q = RunQueue()
        q.enqueue(.process(ids: ["a", "b"], retranscribe: []))
        q.enqueue(.process(ids: ["b", "c"], retranscribe: []))
        XCTAssertEqual(q.jobs, [.process(ids: ["a", "b"], retranscribe: []),
                                .process(ids: ["c"], retranscribe: [])])
    }

    /// An import that lands while Process is running still gets its words — the silent drop
    /// in `transcribe` was one of the ways an imported memo stayed wordless.
    func testAnImportTranscribeDuringARunIsQueuedNotDropped() {
        var q = RunQueue()
        q.enqueue(.transcribe(ids: ["x", "y"]))
        XCTAssertEqual(q.next(), .transcribe(ids: ["x", "y"]))
    }

    /// Process transcribes too, so a waiting words-only job for the same note is redundant —
    /// in either order.
    func testProcessAndTranscribeForTheSameNoteDoNotDoubleRun() {
        var q = RunQueue()
        q.enqueue(.transcribe(ids: ["a", "b"]))
        q.enqueue(.process(ids: ["a"], retranscribe: []))
        XCTAssertEqual(q.jobs, [.transcribe(ids: ["b"]), .process(ids: ["a"], retranscribe: [])])

        var r = RunQueue()
        r.enqueue(.process(ids: ["a"], retranscribe: []))
        r.enqueue(.transcribe(ids: ["a"]))
        XCTAssertEqual(r.jobs, [.process(ids: ["a"], retranscribe: [])])
    }

    func testAQueuedReTranscribeIsNotDowngradedByAnEarlierPlainProcess() {
        var q = RunQueue()
        q.enqueue(.process(ids: ["a"], retranscribe: []))
        q.enqueue(.process(ids: ["a"], retranscribe: ["a"]))
        XCTAssertEqual(q.jobs, [.process(ids: ["a"], retranscribe: ["a"])])
    }

    // MARK: - (a) ListSelection

    private let order = ["n1", "q1", "n2", "n3", "n4"]   // q1 = a quiet unrated note between rows
    private let selectable: Set<String> = ["n1", "n2", "n3", "n4"]

    private func click(_ c: ListSelection.Click, _ id: String, _ s: ListSelection.State) -> ListSelection.State {
        ListSelection.apply(c, id: id, displayOrder: order, selectable: selectable, to: s)
    }

    func testShiftClickSelectsTheContiguousRangeFromTheAnchor() {
        var s = click(.plain, "n1", .init())
        s = click(.range, "n3", s)
        XCTAssertEqual(s.selection, ["n1", "n2", "n3"], "the quiet note in between is skipped, not selected")
        XCTAssertEqual(s.active, "n3")
    }

    func testCommandClickTogglesOneRow() {
        var s = click(.plain, "n1", .init())
        s = click(.toggle, "n3", s)
        XCTAssertEqual(s.selection, ["n1", "n3"])
        s = click(.toggle, "n1", s)
        XCTAssertEqual(s.selection, ["n3"])
    }

    /// Native behaviour: the anchor stays put across ⇧-clicks, so the range can shrink.
    func testASecondShiftClickPivotsOnTheSameAnchor() {
        var s = click(.plain, "n1", .init())
        s = click(.range, "n4", s)
        XCTAssertEqual(s.selection, ["n1", "n2", "n3", "n4"])
        s = click(.range, "n2", s)
        XCTAssertEqual(s.selection, ["n1", "n2"])
        XCTAssertEqual(s.anchor, "n1")
    }

    func testShiftClickUpwardsWorks() {
        var s = click(.plain, "n4", .init())
        s = click(.range, "n2", s)
        XCTAssertEqual(s.selection, ["n2", "n3", "n4"])
    }

    /// The failure that made ⇧-click do nothing: a quiet note opened in the pane is the open
    /// note but not a pipeline row, and the old range needed the anchor to be one.
    func testARangeCanStartFromAQuietNoteOpenedInThePane() {
        let s0 = ListSelection.State(selection: ["q1"], active: "q1", anchor: "q1")
        let s = click(.range, "n3", s0)
        XCTAssertEqual(s.selection, ["n2", "n3"])
    }

    func testShiftClickWithNoAnchorActsLikeAPlainClick() {
        let s = click(.range, "n2", .init())
        XCTAssertEqual(s.selection, ["n2"])
        XCTAssertEqual(s.anchor, "n2")
    }

    func testCommandThenShiftExtendsFromTheCommandClickedRow() {
        var s = click(.plain, "n1", .init())
        s = click(.toggle, "n3", s)     // anchor moves to n3
        s = click(.range, "n4", s)
        XCTAssertEqual(s.selection, ["n3", "n4"])
    }
}
