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

        // Open the recorder — INSTANT RECORD: recording auto-starts on open (the
        // "ready" screen is only a transient/fallback state now), so the pause
        // control must appear WITHOUT tapping the record button.
        let newRecording = app.buttons["new-recording-button"]
        XCTAssertTrue(newRecording.waitForExistence(timeout: 5))
        newRecording.tap()

        let recordButton = app.buttons["record-button"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pause-button"].waitForExistence(timeout: 5),
                      "Pause control didn't appear — instant record didn't auto-start")

        let recordingShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        recordingShot.name = "record-instant"; recordingShot.lifetime = .keepAlways; add(recordingShot)

        Thread.sleep(forTimeInterval: 0.6)
        recordButton.tap()   // stop → save → dismiss

        // Save-now lands in Memo detail; the seeded transcript fills the (always-
        // editable) transcript body — its text is the text view's value.
        let editor = app.textViews["transcript-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10),
                      "transcript editor never appeared after recording")
        XCTAssertTrue((editor.value as? String ?? "").contains(transcript),
                      "seeded transcript didn't fill the new memo")

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

        // INSTANT RECORD: the recorder auto-starts on open — no start tap.
        let recordButton = app.buttons["record-button"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))

        // Let the mock caption reveal a few words, then capture the caption-first
        // recording screen.
        XCTAssertTrue(app.buttons["pause-button"].waitForExistence(timeout: 5),
                      "instant record didn't auto-start")
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
