import XCTest

/// Phase 2: recording flow end to end with a seeded transcript (the Simulator has
/// no Neural Engine, so `-seedTranscript` injects a deterministic transcript and
/// puts recording in mock mode — no mic, no permission prompt). Proves
/// record → stop → save → transcribe → the memo shows the transcript.
final class RecordingUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRecordSeededTranscriptCreatesMemo() throws {
        let transcript = "hello from the test harness"
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedTranscript", transcript]
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let cancel = springboard.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 2) { cancel.tap() }

        XCTAssertTrue(
            app.staticTexts["Memos"].waitForExistence(timeout: 15)
                || app.navigationBars["Memos"].waitForExistence(timeout: 5),
            "Memos root never appeared"
        )

        // Open the recorder.
        let newRecording = app.buttons["new-recording-button"]
        XCTAssertTrue(newRecording.waitForExistence(timeout: 5))
        newRecording.tap()

        // Start → (mock timer runs) → stop.
        let recordButton = app.buttons["record-button"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        recordButton.tap()
        XCTAssertTrue(app.buttons["pause-button"].waitForExistence(timeout: 5),
                      "Pause control didn't appear — recording didn't start")
        Thread.sleep(forTimeInterval: 0.6)
        recordButton.tap()   // stop → save → dismiss

        // The memo appears with the seeded transcript filled in.
        XCTAssertTrue(
            app.staticTexts[transcript].waitForExistence(timeout: 10),
            "Seeded transcript never appeared on a memo row"
        )

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "record-seeded-memo"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
