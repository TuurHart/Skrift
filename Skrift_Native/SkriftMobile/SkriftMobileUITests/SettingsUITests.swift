import XCTest

/// Settings tab: feedback, Models inventory, and Custom words. (Sync is automatic
/// over CloudKit — no Mac pairing UI to exercise.)
final class SettingsUITests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    /// Feedback capture: type a note → Send. On the Simulator MFMailComposeViewController
    /// can't send (no Mail account), so the "Mail not available" alert confirms the flow
    /// reached the send step. (Voice dictation + the real mail composer are device-owed.)
    func testSendFeedbackTypedNote() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedDemoMemos"]
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let cancel = springboard.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 2) { cancel.tap() }

        app.tabBars.buttons["Settings"].tap()
        let feedback = app.buttons["send-feedback-button"]
        // Settings grew (Playback section) — scroll to reveal the feedback row if needed.
        if !feedback.waitForExistence(timeout: 3) { app.swipeUp(); app.swipeUp() }
        XCTAssertTrue(feedback.waitForExistence(timeout: 5), "Send feedback row missing")
        feedback.tap()

        let note = app.textFields["feedback-note-field"]
        XCTAssertTrue(note.waitForExistence(timeout: 5), "feedback note field missing")
        note.tap()
        note.typeText("The record button is great")

        app.buttons["feedback-send-button"].tap()
        XCTAssertTrue(app.staticTexts["Mail not available"].waitForExistence(timeout: 5),
                      "send should reach the mail step (sim has no Mail → not-available alert)")
    }

    /// Settings → Models: every inventory row renders with a downloaded state
    /// (the sim typically shows "Not downloaded" — the rows + footer must exist).
    func testModelsTabListsInventory() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore"]
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let cancel = springboard.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 2) { cancel.tap() }

        app.tabBars.buttons["Settings"].tap()
        let link = app.descendants(matching: .any).matching(identifier: "models-link").firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5), "Models link missing")
        link.tap()

        XCTAssertTrue(app.staticTexts["Transcription"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Speaker recognition"].exists)
        XCTAssertTrue(app.staticTexts["Custom-word spotting"].exists)

        // The sim never downloads the ~600 MB model, so the transcription row is
        // always in the not-downloaded state — which must offer a manual Download
        // (the fix for skipping the model step in onboarding). NOT tapped here:
        // tapping kicks off the real FluidAudio download.
        // (The row-level accessibilityIdentifier propagates to the child button,
        // so query by label.)
        XCTAssertTrue(app.buttons["Download"].waitForExistence(timeout: 3),
                      "transcription model has no manual Download — a user who skipped onboarding is stuck")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "models-tab"; shot.lifetime = .keepAlways; add(shot)
    }

    /// Settings → Capture → Custom words: add two words, delete-able list persists.
    func testCustomWordsAddAndList() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore"]
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let cancel = springboard.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 2) { cancel.tap() }

        app.tabBars.buttons["Settings"].tap()
        let link = app.descendants(matching: .any).matching(identifier: "custom-words-link").firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5), "Custom words link missing")
        link.tap()

        let field = app.textFields["custom-word-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Skrift")
        app.buttons["custom-word-add"].tap()
        XCTAssertTrue(app.staticTexts["Skrift"].waitForExistence(timeout: 3), "added word not listed")

        field.tap()
        field.typeText("Gemma\n")   // submit via return
        XCTAssertTrue(app.staticTexts["Gemma"].waitForExistence(timeout: 3), "submitted word not listed")
    }
}
