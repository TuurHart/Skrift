import XCTest

/// Q327 (D182, mock Q162): each account / monitor state maps to the right Settings row text,
/// and the notes-list capsule shows ONLY when sync is broken, off or signed out.
final class MacSyncStateTests: XCTestCase {
    private func state(on: Bool = true, opened: Bool = true,
                       _ account: MacSyncAccount = .available, flight: Bool = false) -> MacSyncState {
        MacSyncState.resolve(switchOn: on, containerOpened: opened, account: account, inFlight: flight)
    }

    // MARK: resolve

    func testSignedInIdleIsUpToDate() { XCTAssertEqual(state(), .upToDate) }
    func testEventsInFlightIsSyncing() { XCTAssertEqual(state(flight: true), .syncing) }
    func testSwitchOffIsOffWhateverElse() {
        XCTAssertEqual(state(on: false), .off)
        XCTAssertEqual(state(on: false, opened: false, .noAccount, flight: true), .off)
    }
    func testNoAccountIsSignedOut() {
        XCTAssertEqual(state(.noAccount), .signedOut)
        // signed out explains more than a container that did not open
        XCTAssertEqual(state(opened: false, .noAccount), .signedOut)
    }
    func testContainerThatDidNotOpenIsFailed() { XCTAssertEqual(state(opened: false), .failed) }
    func testRestrictedAccountIsFailed() { XCTAssertEqual(state(.restricted), .failed) }
    func testUnknownAccountDoesNotAlarm() {
        XCTAssertEqual(state(.unknown), .upToDate)
        XCTAssertEqual(state(.unknown, flight: true), .syncing)
    }

    // MARK: row text

    func testRowTextPerState() {
        XCTAssertEqual(MacSyncState.syncing.rowText, "Syncing…")
        XCTAssertEqual(MacSyncState.upToDate.rowText, "Up to date")
        XCTAssertEqual(MacSyncState.off.rowText, "Off")
        XCTAssertEqual(MacSyncState.signedOut.rowText, "Not signed in")
        XCTAssertEqual(MacSyncState.failed.rowText, "Couldn't start")
        XCTAssertEqual(MacSyncState.signedOut.rowText, SharedCopy.syncSignedOutRow)
    }

    func testOnlySignedOutAndFailedRowsAreAmber() {
        for s in MacSyncState.allCases {
            XCTAssertEqual(s.rowIsWarning, s == .signedOut || s == .failed, "\(s)")
        }
    }

    // MARK: capsule

    func testCapsuleNeverShowsWhileSyncingNormally() {
        XCTAssertFalse(MacSyncState.syncing.showsCapsule)
        XCTAssertFalse(MacSyncState.upToDate.showsCapsule)
        XCTAssertNil(MacSyncState.syncing.capsuleText)
        XCTAssertNil(MacSyncState.upToDate.capsuleText)
    }

    func testCapsuleShowsForOffSignedOutAndFailed() {
        XCTAssertEqual(MacSyncState.off.capsuleText, "iCloud sync is off")
        XCTAssertEqual(MacSyncState.signedOut.capsuleText, "Not signed in to iCloud")
        XCTAssertEqual(MacSyncState.signedOut.capsuleText, SharedCopy.syncSignedOutCapsule)
        XCTAssertEqual(MacSyncState.failed.capsuleText, "iCloud sync couldn’t start")
        for s in [MacSyncState.off, .signedOut, .failed] { XCTAssertTrue(s.showsCapsule, "\(s)") }
    }

    func testCapsuleIsGreyWhenOffAmberWhenBroken() {
        XCTAssertFalse(MacSyncState.off.capsuleIsWarning)
        XCTAssertTrue(MacSyncState.signedOut.capsuleIsWarning)
        XCTAssertTrue(MacSyncState.failed.capsuleIsWarning)
    }

    // MARK: alerts + gates

    func testAlertsOnlyForSignedOutAndFailed() {
        for s in MacSyncState.allCases {
            XCTAssertEqual(s.alertText != nil, s == .signedOut || s == .failed, "\(s)")
        }
        XCTAssertTrue(MacSyncState.signedOut.alertText!.hasPrefix("This Mac isn't signed in to iCloud."))
        XCTAssertTrue(MacSyncState.failed.alertText!.contains("Your notes on this Mac are safe."))
    }

    func testFailureDetailNamesRestrictedAccount() {
        XCTAssertTrue(MacSyncState.failureDetail(account: .restricted).contains("restricted"))
        XCTAssertTrue(MacSyncState.failureDetail(account: .available).contains("memo_cloud.store"))
    }

    func testGateListIsTheMocksSevenLines() {
        XCTAssertEqual(MacSyncState.gates.count, 7)
        XCTAssertEqual(MacSyncState.gates.filter { $0.0 == .incoming }.count, 1)
        XCTAssertEqual(MacSyncState.gates.filter { $0.0 == .outgoing }.count, 2)
    }
}
