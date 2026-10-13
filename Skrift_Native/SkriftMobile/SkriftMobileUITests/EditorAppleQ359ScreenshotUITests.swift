import XCTest

/// Q359 visual check against the signed mock Q350-note-editor-apple (phone states: Reading,
/// Typing, Selection, Aa, Move a photo, Book quote, Speakers). Screenshots land in
/// `plan/reads/editor-apple/` via `SKRIFT_SHOT_DIR` (pass `TEST_RUNNER_SKRIFT_SHOT_DIR`), or the
/// xcresult attachments.
final class EditorAppleQ359ScreenshotUITests: XCTestCase {

    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.8)
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SKRIFT_SHOT_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    private func launch(_ seed: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", seed, "-selectFirstMemo", "-destinationsOn"]
        app.launch()
        return app
    }

    /// Seeds with several notes open on the list at phone width: tap the newest row.
    private func openFirstNote(_ app: XCUIApplication) {
        if app.textViews["transcript-editor"].waitForExistence(timeout: 6) { return }
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        if row.waitForExistence(timeout: 10) { row.tap() }
    }

    func testReadingTypingSelectionAndAa() {
        let app = launch("-seedPolished")
        let editor = app.textViews["transcript-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 25), "editor missing")
        capture(app, "phone-1-reading")

        // The editor element spans more than the body, so tap by SCREEN position: in the
        // seeded note the word "commonplace" sits at ~(0.3, 0.425) of the screen.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.425)).tap()
        XCTAssertTrue(app.buttons["accessory-done"].waitForExistence(timeout: 5), "top-bar Done missing")
        XCTAssertTrue(app.buttons["accessory-format"].exists, "Aa missing from the keyboard bar")
        capture(app, "phone-2-typing")

        // Selection: double-tap a word → the edit menu (Cut Copy Paste · B I U S · New person…).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.425)).doubleTap()
        capture(app, "phone-3-selection")

        // Aa: the Format panel replaces the keyboard; Heading on the caret line, Bold on the word.
        app.buttons["accessory-format"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["format-panel"].waitForExistence(timeout: 5),
                      "format panel missing")
        capture(app, "phone-4-aa")
        app.buttons["format-B"].tap()
        capture(app, "phone-4b-aa-bold")
        app.buttons["format-close"].tap()
        app.buttons["accessory-done"].tap()
        capture(app, "phone-4c-after-done")
    }

    func testMoveAPhoto() {
        let app = launch("-seedPhotoMoveMemo")
        openFirstNote(app)
        let editor = app.textViews["transcript-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 25), "editor missing")
        capture(app, "phone-5-photo-before")
        // Three paragraphs with the photo between 1 and 2 (~0.47 of the screen height): drag it
        // up onto the first sentence (~0.29).
        let app0 = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.47))
        app0.press(forDuration: 1.0, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.29)))
        capture(app, "phone-5-photo-after")
    }

    func testBookQuote() {
        let app = launch("-seedQuoteMemo")
        openFirstNote(app)
        XCTAssertTrue(app.textViews["transcript-editor"].waitForExistence(timeout: 25), "editor missing")
        capture(app, "phone-6-quote")
    }

    func testSpeakers() {
        let app = launch("-seedConversationMemo")
        openFirstNote(app)
        XCTAssertTrue(app.buttons["detail-menu"].waitForExistence(timeout: 25), "note missing")
        capture(app, "phone-7-speakers")
    }
}
