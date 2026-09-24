import XCTest
import Foundation

/// The 3-ball importance control's pure scale logic (Q8, mock
/// `three-ball-importance.html`): legacy grid bucketing to the three stops
/// (Passing 0.3 / Useful 0.6 / Important 1.0), the tap-to-set/re-tap-to-clear
/// rule, and the no-refine-pass sync copy. `SignificanceScaleTests` in this
/// same target covers the OLD 10-circle scale, which stays live for the
/// non-ball-control call sites Q8 doesn't touch (`NoteConsent`,
/// `ConnectionsPanel`, `JournalView`, `RunFile`, `LookbackProvider`) — it was
/// not retired here because it is a protected test file.
final class ThreeBallScaleTests: XCTestCase {

    // MARK: step(for:) — legacy grid value → its ball

    func testStepBucketsLegacyGridToNearestStop() {
        // 0.1–0.3 → Passing (1)
        XCTAssertEqual(ThreeBallScale.step(for: 0.1), 1)
        XCTAssertEqual(ThreeBallScale.step(for: 0.2), 1)
        XCTAssertEqual(ThreeBallScale.step(for: 0.3), 1)
        // 0.4–0.6 → Useful (2)
        XCTAssertEqual(ThreeBallScale.step(for: 0.4), 2)
        XCTAssertEqual(ThreeBallScale.step(for: 0.5), 2)
        XCTAssertEqual(ThreeBallScale.step(for: 0.6), 2)
        // 0.7–1.0 → Important (3) — 0.7 rounds UP, it already read "Important"
        XCTAssertEqual(ThreeBallScale.step(for: 0.7), 3)
        XCTAssertEqual(ThreeBallScale.step(for: 0.9), 3)
        XCTAssertEqual(ThreeBallScale.step(for: 1.0), 3)
    }

    func testStepZeroAndNilAreUnrated() {
        XCTAssertEqual(ThreeBallScale.step(for: 0), 0)
        XCTAssertEqual(ThreeBallScale.step(for: Optional<Double>.none), 0)
        XCTAssertEqual(ThreeBallScale.step(for: Optional(0.6)), 2)
    }

    func testStepToleratesFloatNoise() {
        XCTAssertEqual(ThreeBallScale.step(for: 0.30000000000000004), 1)
        XCTAssertEqual(ThreeBallScale.step(for: 0.6999999999999999), 3)
        XCTAssertEqual(ThreeBallScale.step(for: 0.9999999999999999), 3)
    }

    func testStepClampsOffContractValues() {
        XCTAssertEqual(ThreeBallScale.step(for: 1.7), 3)
        XCTAssertEqual(ThreeBallScale.step(for: 42), 3)
        XCTAssertEqual(ThreeBallScale.step(for: -0.3), 0)
        XCTAssertEqual(ThreeBallScale.step(for: -Double.greatestFiniteMagnitude), 0)
        XCTAssertEqual(ThreeBallScale.step(for: Double.greatestFiniteMagnitude), 3)
    }

    func testStepNonFiniteValuesAreUnrated() {
        XCTAssertEqual(ThreeBallScale.step(for: Double.nan), 0)
        XCTAssertEqual(ThreeBallScale.step(for: Double.infinity), 0)
        XCTAssertEqual(ThreeBallScale.step(for: -Double.infinity), 0)
    }

    // MARK: value(forStep:) — ball → persisted stop

    func testValueForStepMatchesTheThreeStops() {
        XCTAssertEqual(ThreeBallScale.value(forStep: 1), 0.3)
        XCTAssertEqual(ThreeBallScale.value(forStep: 2), 0.6)
        XCTAssertEqual(ThreeBallScale.value(forStep: 3), 1.0)
        XCTAssertEqual(ThreeBallScale.value(forStep: 0), 0)
    }

    func testValueAndStepRoundTripForAllThreeBalls() {
        for n in 1...3 {
            XCTAssertEqual(ThreeBallScale.step(for: ThreeBallScale.value(forStep: n)), n,
                           "ball \(n) didn't round-trip through its stored value")
        }
    }

    // MARK: tap-to-set / re-tap-to-clear

    func testTapSetsRating() {
        XCTAssertEqual(ThreeBallScale.toggling(nil, tappedStep: 2), 0.6)
        XCTAssertEqual(ThreeBallScale.toggling(0.3, tappedStep: 3), 1.0)
    }

    func testReTapOnSetBallClearsToNotRated() {
        XCTAssertEqual(ThreeBallScale.toggling(0.6, tappedStep: 2), 0)
        XCTAssertEqual(ThreeBallScale.toggling(1.0, tappedStep: 3), 0)
        // Re-tap clears whatever OLD 0.1–1.0 value lit the ball, not just an
        // exact stop (the mock: "Tapping the lit ball clears it, whatever old
        // value lit it").
        XCTAssertEqual(ThreeBallScale.toggling(0.5, tappedStep: 2), 0)
    }

    // MARK: names — no fourth button, no refine wall

    func testThereAreExactlyThreeNames() {
        XCTAssertEqual(ThreeBallScale.stepCount, 3)
        XCTAssertEqual(ThreeBallScale.names, ["Passing", "Useful", "Important"])
    }

    func testLabelIsTheWordAlone() {
        XCTAssertEqual(ThreeBallScale.label(forStep: 0), "Not rated")
        XCTAssertEqual(ThreeBallScale.label(forStep: 1), "Passing")
        XCTAssertEqual(ThreeBallScale.label(forStep: 2), "Useful")
        XCTAssertEqual(ThreeBallScale.label(forStep: 3), "Important")
    }

    // MARK: sync copy — no refine pass (D52)

    func testSyncCopyHasNoRefinePassBranch() {
        XCTAssertEqual(ThreeBallScale.syncCopy(forStep: 0), "Not rated — left alone")
        XCTAssertEqual(ThreeBallScale.syncCopy(forStep: 1), "Rated — ready to process")
        XCTAssertEqual(ThreeBallScale.syncCopy(forStep: 2), "Rated — ready to process")
        // Step 3 (Important, the old refine-wall territory) reads the same as
        // any other rated ball — the refine pass is gone.
        XCTAssertEqual(ThreeBallScale.syncCopy(forStep: 3), "Rated — ready to process")
    }

    func testSyncCopyCarriesNoRefineOrFlagLanguage() {
        for step in 0...3 {
            let copy = ThreeBallScale.syncCopy(forStep: step).lowercased()
            XCTAssertFalse(copy.contains("flag"), "step \(step) still uses flag language")
            XCTAssertFalse(copy.contains("refine"), "step \(step) still mentions the refine pass")
        }
    }
}
