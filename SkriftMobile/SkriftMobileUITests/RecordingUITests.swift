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

    func testShutterCapturesPhotoDuringRecording() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedTranscript", "alpha bravo charlie delta echo"]
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let cancel = springboard.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 2) { cancel.tap() }

        let newRecording = app.buttons["new-recording-button"]
        XCTAssertTrue(newRecording.waitForExistence(timeout: 15))
        newRecording.tap()

        let recordButton = app.buttons["record-button"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        recordButton.tap()   // start

        let shutter = app.buttons["shutter-button"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 5), "shutter not shown while recording")
        shutter.tap()

        XCTAssertTrue(app.staticTexts["1 photo"].waitForExistence(timeout: 5),
                      "photo count didn't update after shutter")

        recordButton.tap()   // stop → save (with photo) → dismiss

        // A memo row should land in the list (identifier-based, robust to the
        // [[img_NNN]] markers the transcript now carries). Marker *correctness* is
        // covered by the deterministic unit test.
        let firstRow = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        let appeared = firstRow.waitForExistence(timeout: 10)

        let labels = app.staticTexts.allElementsBoundByIndex.filter { $0.exists }.map { $0.label }
        print("SCREEN[after-stop]: " + labels.joined(separator: " || "))

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "record-with-photo"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertTrue(appeared, "memo row never appeared after recording with a photo")
    }
}
