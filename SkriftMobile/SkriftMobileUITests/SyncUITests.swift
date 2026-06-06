import XCTest

/// Phase 6: record a memo, then sync it to the Mac. `-mockMac` stubs the upload
/// transport (the real round-trip against the native server is device/server-owed),
/// so this proves the record → waiting → sync → synced flow end to end.
final class SyncUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRecordedMemoSyncsToMac() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedTranscript", "sync this memo", "-mockMac"]
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let cancel = springboard.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 2) { cancel.tap() }

        // Record a memo.
        app.buttons["new-recording-button"].tap()
        let recordButton = app.buttons["record-button"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        recordButton.tap()
        XCTAssertTrue(app.buttons["pause-button"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)
        recordButton.tap()   // stop → save → dismiss

        // It lands with its transcript and starts out Waiting.
        XCTAssertTrue(app.staticTexts["sync this memo"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Waiting"].waitForExistence(timeout: 5))

        // Sync → flips to Synced.
        app.buttons["sync-button"].tap()
        XCTAssertTrue(app.staticTexts["Synced"].waitForExistence(timeout: 10),
                      "memo never flipped to Synced after sync")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "synced-memo"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
