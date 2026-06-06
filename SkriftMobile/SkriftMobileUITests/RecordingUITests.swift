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

    func testPhotoSheetCapturesDuringRecording() throws {
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

        // Let the mock caption reveal a few words, then capture the caption-first
        // recording screen.
        _ = app.buttons["pause-button"].waitForExistence(timeout: 5)
        Thread.sleep(forTimeInterval: 1.2)
        let recShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        recShot.name = "rec-recording-caption"
        recShot.lifetime = .keepAlways
        add(recShot)

        // Caption-first: the Photo button opens the camera sheet; the shutter
        // inside it captures while recording keeps running.
        let photoButton = app.buttons["photo-button"]
        XCTAssertTrue(photoButton.waitForExistence(timeout: 5), "Photo button not shown while recording")
        photoButton.tap()

        let shutter = app.buttons["shutter-button"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 5), "camera sheet / shutter didn't appear")
        let camShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        camShot.name = "rec-camera-sheet"
        camShot.lifetime = .keepAlways
        add(camShot)
        shutter.tap()

        app.buttons["camera-done"].tap()

        // Back on the record screen the Photo button now shows a count badge.
        XCTAssertTrue(app.staticTexts["photo-count"].waitForExistence(timeout: 5),
                      "photo count badge didn't update after capture")
        XCTAssertEqual(app.staticTexts["photo-count"].label, "1")

        recordButton.tap()   // stop → save (with photo) → save-now opens Memo detail

        // Save-now flow: stopping lands us straight in Memo detail for the new
        // memo. Its presence (the player) proves the memo was created + saved.
        let inDetail = app.buttons["play-button"].waitForExistence(timeout: 10)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "record-with-photo"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertTrue(inDetail, "Memo detail didn't open after recording with a photo (save-now)")
    }
}
