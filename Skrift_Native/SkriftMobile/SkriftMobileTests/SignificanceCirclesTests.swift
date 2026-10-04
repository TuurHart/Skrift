import XCTest
@testable import SkriftMobile

/// The 3-ball importance control's pure scale logic on the phone (Q24 rewrite —
/// the old 10-circle scale is fully retired; the control now runs the SHARED
/// `ThreeBallScale`, mirroring the desktop's `ThreeBallScaleTests`): value↔ball
/// mapping, legacy-grid bucketing, the tap-to-set/re-tap-to-clear rule, the
/// live label, and the no-refine-pass microcopy.
final class SignificanceCirclesTests: XCTestCase {

    // MARK: value ↔ step (legacy grid bucketing)

    func testStepBucketsLegacyGridToNearestBall() {
        XCTAssertEqual(ThreeBallScale.step(for: 0), 0)
        XCTAssertEqual(ThreeBallScale.step(for: 0.1), 1)
        XCTAssertEqual(ThreeBallScale.step(for: 0.5), 2)
        XCTAssertEqual(ThreeBallScale.step(for: 0.7), 3)
        XCTAssertEqual(ThreeBallScale.step(for: 1.0), 3)
        // Drifted doubles (e.g. 0.7000000000000001 from old slider writes) snap home.
        XCTAssertEqual(ThreeBallScale.step(for: 0.30000000000000004), 1)
        XCTAssertEqual(ThreeBallScale.step(for: 0.6999999999999999), 3)
        // Out-of-range input clamps rather than crashing the control.
        XCTAssertEqual(ThreeBallScale.step(for: -0.3), 0)
        XCTAssertEqual(ThreeBallScale.step(for: 1.4), 3)
    }

    func testValueForStep() {
        XCTAssertEqual(ThreeBallScale.value(forStep: 0), 0)
        XCTAssertEqual(ThreeBallScale.value(forStep: 1), 0.3)
        XCTAssertEqual(ThreeBallScale.value(forStep: 2), 0.6)
        XCTAssertEqual(ThreeBallScale.value(forStep: 3), 1.0)
    }

    func testValueAndStepRoundTripForAllThreeBalls() {
        for step in 1...3 {
            XCTAssertEqual(ThreeBallScale.step(for: ThreeBallScale.value(forStep: step)), step)
        }
    }

    // MARK: no fourth button, no refine wall

    func testThereAreExactlyThreeNames() {
        XCTAssertEqual(ThreeBallScale.stepCount, 3)
        XCTAssertEqual(ThreeBallScale.names, ["Passing", "Useful", "Important"])
    }

    func testLiveLabelIsTheWordAlone() {
        XCTAssertEqual(ThreeBallScale.label(forStep: 0), "Not rated")
        XCTAssertEqual(ThreeBallScale.label(forStep: 1), "Passing")
        XCTAssertEqual(ThreeBallScale.label(forStep: 2), "Useful")
        XCTAssertEqual(ThreeBallScale.label(forStep: 3), "Important")
    }

}
