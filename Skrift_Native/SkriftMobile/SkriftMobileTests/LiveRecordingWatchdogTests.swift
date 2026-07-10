import XCTest
@testable import SkriftMobile

/// Pure-logic coverage for the capture watchdog (the "recorded only half my
/// message" defense): a dead engine mid-recording must trigger a rebuild, but
/// never while the rebuild ladder's own retry backoff (~3 s) is still on it.
/// The interruption/foreground observers and the actual engine recovery are
/// device-owed — the Simulator has no callable interruptions.
final class LiveRecordingWatchdogTests: XCTestCase {

    func testHealthyStallDurationDoesNotFire() {
        XCTAssertFalse(LiveRecordingService.watchdogShouldRebuild(
            stalledFor: 0, sinceLastRebuildAttempt: nil))
        XCTAssertFalse(LiveRecordingService.watchdogShouldRebuild(
            stalledFor: 1.9, sinceLastRebuildAttempt: nil))
    }

    func testFiresAfterTwoSecondsWithNoRebuildInFlight() {
        XCTAssertTrue(LiveRecordingService.watchdogShouldRebuild(
            stalledFor: 2.0, sinceLastRebuildAttempt: nil))
        XCTAssertTrue(LiveRecordingService.watchdogShouldRebuild(
            stalledFor: 30, sinceLastRebuildAttempt: nil))
    }

    func testDefersToARecentRebuildAttempt() {
        // The rebuild ladder retried 1 s ago — its backoff (≈3 s) still owns
        // recovery; the watchdog treading in would double-drive the teardown.
        XCTAssertFalse(LiveRecordingService.watchdogShouldRebuild(
            stalledFor: 2.5, sinceLastRebuildAttempt: 1.0))
        XCTAssertFalse(LiveRecordingService.watchdogShouldRebuild(
            stalledFor: 10, sinceLastRebuildAttempt: 3.9))
    }

    func testReDrivesAnExhaustedBackoff() {
        // Backoff exhausted (last attempt > 4 s ago), engine still dead — the
        // watchdog re-drives recovery instead of waiting for a notification
        // that may never come.
        XCTAssertTrue(LiveRecordingService.watchdogShouldRebuild(
            stalledFor: 2.5, sinceLastRebuildAttempt: 4.0))
        XCTAssertTrue(LiveRecordingService.watchdogShouldRebuild(
            stalledFor: 60, sinceLastRebuildAttempt: 45))
    }
}
