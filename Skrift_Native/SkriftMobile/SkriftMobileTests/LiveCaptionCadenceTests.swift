import XCTest
@testable import SkriftMobile

/// Pure-logic coverage for the live-caption duty-cycle bounds: the self-pacing
/// poll delay (never busier than ~40% ASR duty, thermal floors) and the
/// early-rotation policy (commit a window whose snapshots got expensive for
/// this device). The actual ANE inference timing is device-owed.
final class LiveCaptionCadenceTests: XCTestCase {

    // MARK: - Poll pacing

    func testCheapSnapshotKeepsTheNominalCadence() {
        XCTAssertEqual(LiveCaptionEngine.pollDelay(
            afterSnapshotCost: 0.1, thermal: .nominal), 0.6)
        XCTAssertEqual(LiveCaptionEngine.pollDelay(
            afterSnapshotCost: 0, thermal: .nominal), 0.6)
    }

    func testExpensiveSnapshotSlowsThePoll() {
        // 1 s of inference → 1.5 s breather (~40% duty), not another instant poll.
        XCTAssertEqual(LiveCaptionEngine.pollDelay(
            afterSnapshotCost: 1.0, thermal: .nominal), 1.5)
        XCTAssertEqual(LiveCaptionEngine.pollDelay(
            afterSnapshotCost: 2.0, thermal: .nominal), 3.0)
    }

    func testDelayIsCappedSoCaptionsStayAlive() {
        XCTAssertEqual(LiveCaptionEngine.pollDelay(
            afterSnapshotCost: 30, thermal: .nominal), 6)
        XCTAssertEqual(LiveCaptionEngine.pollDelay(
            afterSnapshotCost: 30, thermal: .critical), 6)
    }

    func testThermalPressureRaisesTheFloor() {
        XCTAssertEqual(LiveCaptionEngine.pollDelay(
            afterSnapshotCost: 0.1, thermal: .serious), 2.5)
        XCTAssertEqual(LiveCaptionEngine.pollDelay(
            afterSnapshotCost: 0.1, thermal: .critical), 6)
        // An already-slow pace stays cost-driven, not floored down.
        XCTAssertEqual(LiveCaptionEngine.pollDelay(
            afterSnapshotCost: 2.0, thermal: .serious), 3.0)
    }

    // MARK: - Rotation policy

    func testHardCapAlwaysRotates() {
        XCTAssertTrue(TranscriptionService.shouldRotate(
            sinceRotation: 26, lastSnapshotCost: 0))
    }

    func testYoungCheapWindowDoesNotRotate() {
        XCTAssertFalse(TranscriptionService.shouldRotate(
            sinceRotation: 5, lastSnapshotCost: 0.2))
        XCTAssertFalse(TranscriptionService.shouldRotate(
            sinceRotation: 24, lastSnapshotCost: 0.9))
    }

    func testExpensiveWindowRotatesEarly() {
        // Snapshots past ~1.2 s on this device: commit at 10 s+ instead of
        // letting the per-poll cost climb toward the 25 s cap.
        XCTAssertTrue(TranscriptionService.shouldRotate(
            sinceRotation: 12, lastSnapshotCost: 1.5))
        XCTAssertFalse(TranscriptionService.shouldRotate(
            sinceRotation: 9, lastSnapshotCost: 1.5))   // too young even if pricey
    }
}
