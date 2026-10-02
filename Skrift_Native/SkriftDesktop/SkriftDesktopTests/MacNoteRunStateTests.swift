import XCTest

/// Q118 (C194/C182): the Mac note bar takes THIS note's run state from the coordinator's live run
/// and its own failure — the iPad's `PolishCenter.Phase` for the Mac.
final class MacNoteRunStateTests: XCTestCase {

    private func state(_ id: String = "A", run: MacRunSnapshot? = nil,
                       transcribe: StepStatus = .done, enhance: StepStatus = .pending,
                       error: String? = nil, needsProcessing: Bool = true) -> MacNoteRunState {
        MacNoteRunState.of(noteID: id, run: run, transcribe: transcribe, enhance: enhance,
                           error: error, needsProcessing: needsProcessing)
    }

    func testNoRunIsIdle() {
        XCTAssertEqual(state(), .idle)
        XCTAssertFalse(state().isBusy)
    }

    func testCurrentNoteRunsWithTheSharedStepLine() {
        let run = MacRunSnapshot(currentID: "A", currentSteps: 1, pendingIDs: ["A", "B"])
        XCTAssertEqual(state(run: run),
                       .running(line: SharedCopy.processingStep("Polish", 1, of: 1), fraction: 0.5))
        XCTAssertTrue(state(run: run).isBusy)
    }

    func testTranscribeThenPolishWalksTwoSteps() {
        let run = MacRunSnapshot(currentID: "A", currentSteps: 2, pendingIDs: ["A"])
        let first = state(run: run, transcribe: .processing)
        XCTAssertEqual(first, .running(line: SharedCopy.processingStep("Transcribe", 1, of: 2), fraction: 0.25))
        let second = state(run: run, transcribe: .done, enhance: .processing)
        XCTAssertEqual(second, .running(line: SharedCopy.processingStep("Polish", 2, of: 2), fraction: 0.75))
    }

    func testAnotherNoteInTheRunWaits() {
        let run = MacRunSnapshot(currentID: "A", currentSteps: 1, pendingIDs: ["A", "B"])
        XCTAssertEqual(state("B", run: run), .queued)
        XCTAssertTrue(state("B", run: run).isBusy, "the verb is replaced while the note waits for its turn")
    }

    func testAFinishedNoteOfTheRunIsNoLongerBusy() {
        let run = MacRunSnapshot(currentID: "B", currentSteps: 1, pendingIDs: ["B"])
        XCTAssertEqual(state("A", run: run, enhance: .done, needsProcessing: false), .idle)
    }

    func testModelLoadShowsOnEveryNoteOfTheRun() {
        let run = MacRunSnapshot(currentID: nil, pendingIDs: ["A"], loadingLabel: "enhancement model", loadingFraction: 0.45)
        XCTAssertEqual(state(run: run), .loading(line: SharedCopy.processingDownload(0.45), fraction: 0.45))
        let cached = MacRunSnapshot(currentID: nil, pendingIDs: ["A"], loadingLabel: "enhancement model", loadingFraction: nil)
        XCTAssertEqual(state(run: cached), .loading(line: SharedCopy.processingLoading("enhancement model"), fraction: nil))
    }

    func testNoteOutsideTheRunIsUntouchedByIt() {
        let run = MacRunSnapshot(currentID: "A", currentSteps: 1, pendingIDs: ["A"])
        XCTAssertEqual(state("Z", run: run), .idle)
    }

    // ── failure ──

    func testFailedPassShowsRetryAndKeepsTheReason() {
        XCTAssertEqual(state(enhance: .error, error: "boom"), .failed(reason: "boom"))
        XCTAssertEqual(state(transcribe: .error), .failed(reason: ""))
        XCTAssertFalse(state(enhance: .error).isBusy, "Retry is pressable")
        XCTAssertEqual(MacNoteRunState.failedLine, "Couldn't process")
    }

    func testRetryRunningReplacesTheFailure() {
        let run = MacRunSnapshot(currentID: "A", currentSteps: 1, pendingIDs: ["A"])
        let s = state(run: run, enhance: .processing, error: "old failure")
        if case .running = s {} else { XCTFail("a live run on the note wins over its old failure: \(s)") }
    }

    func testFailureIsHiddenOnceTheNoteIsProcessed() {
        // A failed re-transcribe of an already polished note has nothing for Retry (Process) to do.
        XCTAssertEqual(state(transcribe: .error, enhance: .done, error: "gone", needsProcessing: false), .idle)
    }
}
