import XCTest

/// Q517 (C155, D217/D218): the Mac Settings iCloud row never says "Up to date" beside the
/// sync-health banner. A different account reads stopped, a full iCloud reads full, a failed
/// upload's sign-in error reads signed out — in the banner's own words.
final class MacSyncStateStoppedTests: XCTestCase {

    private func state(_ problem: SyncHealth.Problem?, switchOn: Bool = true, opened: Bool = true,
                       account: MacSyncAccount = .available, inFlight: Bool = false) -> MacSyncState {
        MacSyncState.resolve(switchOn: switchOn, containerOpened: opened, account: account,
                             inFlight: inFlight, problem: problem)
    }

    func testAnAccountSwitchReadsStoppedNotUpToDate() {
        XCTAssertEqual(state(.accountSwitched), .stopped)
        XCTAssertEqual(state(.accountSwitched, inFlight: true), .stopped, "the mirror's traffic is not our sync")
        XCTAssertEqual(state(.accountSwitched, account: .noAccount), .stopped)
        XCTAssertEqual(state(.accountSwitched, switchOn: false), .off, "a switched-off Mac is Off whatever happened")
    }

    func testAFullICloudReadsFull() {
        XCTAssertEqual(state(.quotaFull), .full)
        XCTAssertEqual(state(.quotaFull, inFlight: true), .full)
        XCTAssertEqual(state(.quotaFull, opened: false), .failed, "a store that never opened explains more")
    }

    func testAnUploadSignInErrorReadsSignedOut() {
        XCTAssertEqual(state(.signedOut), .signedOut)
    }

    func testNoProblemKeepsTheOldRule() {
        XCTAssertEqual(state(nil), .upToDate)
        XCTAssertEqual(state(nil, inFlight: true), .syncing)
    }

    func testTheRowSpeaksTheBannersWords() {
        var h = SyncHealth()
        h.accountSeen(.available(recordName: "_A"))
        h.accountSeen(.available(recordName: "_B"))
        XCTAssertEqual(MacSyncState.stopped.rowText, h.banner(unsyncedCount: 0, device: "this Mac")?.title)
        XCTAssertTrue(MacSyncState.stopped.alertText?.contains(SyncHealth.switchedLine) == true)

        var full = SyncHealth()
        full.exportFailure = .quotaFull
        XCTAssertEqual(MacSyncState.full.rowText, full.banner(unsyncedCount: 1, device: "this Mac")?.title)

        var out = SyncHealth()
        out.signedOut = true
        XCTAssertEqual(MacSyncState.signedOut.capsuleText, out.banner(unsyncedCount: 0, device: "this Mac")?.title)
    }

    func testBothNewStatesAreAmberWithAnAlert() {
        for s in [MacSyncState.stopped, .full] {
            XCTAssertTrue(s.rowIsWarning, "\(s)")
            XCTAssertTrue(s.capsuleIsWarning, "\(s)")
            XCTAssertNotNil(s.alertText, "\(s)")
            XCTAssertNotEqual(s.rowText, MacSyncState.upToDate.rowText)
        }
    }
}
