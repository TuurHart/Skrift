import XCTest
import Foundation

/// The 10-circle significance control's pure scale logic — the SHARED
/// `SignificanceScale` (Shared/Model/SignificanceScale.swift, rendered here by
/// Features/Review/SignificanceCircles.swift per mocks/significance-circles.html):
/// value↔circle mapping with float-noise tolerance + clamping, tier
/// boundaries 0.4/0.7, the top-right value text, and the 0.8 refine wall.
/// (The phone runs the same enum; its suite covers step/toggling/label.)
final class SignificanceScaleTests: XCTestCase {

    // MARK: litCount — stored value → lit circles

    func testLitCountOnGridValues() {
        XCTAssertEqual(SignificanceScale.litCount(0.1), 1)
        XCTAssertEqual(SignificanceScale.litCount(0.5), 5)
        XCTAssertEqual(SignificanceScale.litCount(0.7), 7)
        XCTAssertEqual(SignificanceScale.litCount(1.0), 10)
    }

    func testLitCountNilAndZeroAreUnrated() {
        XCTAssertEqual(SignificanceScale.litCount(nil), 0)
        XCTAssertEqual(SignificanceScale.litCount(0), 0)
    }

    func testLitCountToleratesFloatNoise() {
        // Drifted doubles from old slider writes snap back to their circle.
        XCTAssertEqual(SignificanceScale.litCount(0.30000000000000004), 3)
        XCTAssertEqual(SignificanceScale.litCount(0.7000000000000001), 7)
        XCTAssertEqual(SignificanceScale.litCount(0.6999999999999999), 7)
        XCTAssertEqual(SignificanceScale.litCount(0.9999999999999999), 10)
    }

    func testLitCountClampsOffContractValues() {
        // Out-of-range input clamps rather than trapping the Int conversion.
        XCTAssertEqual(SignificanceScale.litCount(1.7), 10)
        XCTAssertEqual(SignificanceScale.litCount(-0.3), 0)
        XCTAssertEqual(SignificanceScale.litCount(42), 10)
        XCTAssertEqual(SignificanceScale.litCount(-Double.greatestFiniteMagnitude), 0)
        XCTAssertEqual(SignificanceScale.litCount(Double.greatestFiniteMagnitude), 10)
    }

    func testLitCountNonFiniteValuesAreUnrated() {
        XCTAssertEqual(SignificanceScale.litCount(Double.nan), 0)
        XCTAssertEqual(SignificanceScale.litCount(Double.infinity), 0)
        XCTAssertEqual(SignificanceScale.litCount(-Double.infinity), 0)
    }

    // MARK: value(forStep:) — circle N → persisted 0.N

    func testValueForStepMatchesContractGrid() {
        XCTAssertEqual(SignificanceScale.value(forStep: 1), 0.1)
        XCTAssertEqual(SignificanceScale.value(forStep: 5), 0.5)
        XCTAssertEqual(SignificanceScale.value(forStep: 10), 1.0)
    }

    func testValueAndLitCountRoundTripForAllTenCircles() {
        for n in 1...10 {
            XCTAssertEqual(SignificanceScale.litCount(SignificanceScale.value(forStep: n)), n,
                           "circle \(n) didn't round-trip through its stored value")
        }
    }

    // MARK: tiers (mock locks the boundaries at 0.4 / 0.7)

    func testTierBoundaries() {
        // Top tier reads "Important" — the Importance relabel, SAME string as the
        // phone (the split copies once let the Mac keep "Significant").
        for n in 1...3 { XCTAssertEqual(SignificanceScale.tierName(forStep: n), "Passing") }
        for n in 4...6 { XCTAssertEqual(SignificanceScale.tierName(forStep: n), "Useful") }
        for n in 7...10 { XCTAssertEqual(SignificanceScale.tierName(forStep: n), "Important") }
    }

    // MARK: valueText — the top-right label

    func testValueText() {
        XCTAssertEqual(SignificanceScale.valueText(forStep: 3), "0.3 · Passing")
        XCTAssertEqual(SignificanceScale.valueText(forStep: 4), "0.4 · Useful")
        XCTAssertEqual(SignificanceScale.valueText(forStep: 7), "0.7 · Important")
        XCTAssertEqual(SignificanceScale.valueText(forStep: 10), "1.0 · Important")
    }

    // MARK: refine wall

    func testRefineWallIsCircleEight() {
        XCTAssertEqual(SignificanceScale.refineStep, 8)
    }
}
