import XCTest

final class RunReconcilerTests: XCTestCase {

    func testResetsInterruptedStepsButPreservesDoneAndPending() {
        let pf = PipelineFile(id: "x", filename: "memo.m4a", sourceType: .audio)
        pf.transcribeStatus = .done
        pf.enhanceStatus = .processing      // interrupted mid-enhance
        pf.sanitiseStatus = .pending
        pf.exportStatus = .pending

        XCTAssertTrue(RunReconciler.resetInterrupted([pf]))
        XCTAssertEqual(pf.enhanceStatus, .pending)     // the stuck step recovered
        XCTAssertEqual(pf.transcribeStatus, .done)     // completed work preserved
        XCTAssertEqual(pf.sanitiseStatus, .pending)

        // Idempotent: nothing left to reset.
        XCTAssertFalse(RunReconciler.resetInterrupted([pf]))
    }

    func testNoProcessingMeansNoChange() {
        let pf = PipelineFile(id: "y", filename: "memo.m4a", sourceType: .audio)
        pf.transcribeStatus = .done; pf.enhanceStatus = .done
        XCTAssertFalse(RunReconciler.resetInterrupted([pf]))
    }
}
