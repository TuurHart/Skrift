import XCTest
@testable import SkriftMobile

/// The 10-circle significance control's scale logic (SignificanceCircles.swift,
/// per mocks/significance-circles.html): value↔step mapping, the star-rating
/// toggle (re-tap clears), tier boundaries 0.4/0.7, the live label, the 0.8+
/// refine wall, and the flag-to-send microcopy.
final class SignificanceCirclesTests: XCTestCase {

    // MARK: value ↔ step

    func testStepForValueRoundsAndClamps() {
        XCTAssertEqual(SignificanceScale.step(for: 0), 0)
        XCTAssertEqual(SignificanceScale.step(for: 0.1), 1)
        XCTAssertEqual(SignificanceScale.step(for: 0.5), 5)
        XCTAssertEqual(SignificanceScale.step(for: 1.0), 10)
        // Drifted doubles (e.g. 0.7000000000000001 from old slider writes) snap home.
        XCTAssertEqual(SignificanceScale.step(for: 0.30000000000000004), 3)
        XCTAssertEqual(SignificanceScale.step(for: 0.7000000000000001), 7)
        // Out-of-range input clamps rather than crashing the control.
        XCTAssertEqual(SignificanceScale.step(for: -0.3), 0)
        XCTAssertEqual(SignificanceScale.step(for: 1.4), 10)
    }

    func testValueForStep() {
        XCTAssertEqual(SignificanceScale.value(forStep: 0), 0)
        XCTAssertEqual(SignificanceScale.value(forStep: 5), 0.5)
        XCTAssertEqual(SignificanceScale.value(forStep: 10), 1.0)
    }

    func testValueAndStepRoundTripForAllTenCircles() {
        for step in 0...10 {
            XCTAssertEqual(SignificanceScale.step(for: SignificanceScale.value(forStep: step)), step)
        }
    }

    // MARK: tap behaviour (star-rating toggle)

    func testTapSetsRating() {
        XCTAssertEqual(SignificanceScale.toggling(0, tappedStep: 6), 0.6)
        XCTAssertEqual(SignificanceScale.toggling(0.3, tappedStep: 9), 0.9)
    }

    func testReTapOnSetCircleClearsToNotRated() {
        XCTAssertEqual(SignificanceScale.toggling(0.6, tappedStep: 6), 0)
        XCTAssertEqual(SignificanceScale.toggling(1.0, tappedStep: 10), 0)
    }

    // MARK: tiers (mock locks the boundaries at 0.4 / 0.7)

    func testTierBoundaries() {
        for step in 1...3 { XCTAssertEqual(SignificanceScale.tierName(forStep: step), "Passing") }
        for step in 4...6 { XCTAssertEqual(SignificanceScale.tierName(forStep: step), "Useful") }
        for step in 7...10 { XCTAssertEqual(SignificanceScale.tierName(forStep: step), "Significant") }
    }

    func testLiveLabel() {
        XCTAssertEqual(SignificanceScale.label(forStep: 0), "Not rated")
        XCTAssertEqual(SignificanceScale.label(forStep: 3), "0.3 · Passing")
        XCTAssertEqual(SignificanceScale.label(forStep: 5), "0.5 · Useful")
        XCTAssertEqual(SignificanceScale.label(forStep: 7), "0.7 · Significant")
        XCTAssertEqual(SignificanceScale.label(forStep: 10), "1.0 · Significant")
    }

    // MARK: refine wall (0.8+)

    func testRefineWallStartsAtPointEight() {
        XCTAssertFalse(SignificanceScale.isRefine(step: 7))
        XCTAssertTrue(SignificanceScale.isRefine(step: 8))
        XCTAssertTrue(SignificanceScale.isRefine(step: 10))
    }

    // MARK: flag-to-send microcopy

    func testSyncCopy() {
        XCTAssertEqual(SignificanceScale.syncCopy(forStep: 0),
                       "Stays on this phone — rate to flag for sync")
        XCTAssertEqual(SignificanceScale.syncCopy(forStep: 1), "Will sync to the Mac")
        XCTAssertEqual(SignificanceScale.syncCopy(forStep: 7), "Will sync to the Mac")
        XCTAssertEqual(SignificanceScale.syncCopy(forStep: 8),
                       "Will sync · flagged for a refine pass")
    }
}
