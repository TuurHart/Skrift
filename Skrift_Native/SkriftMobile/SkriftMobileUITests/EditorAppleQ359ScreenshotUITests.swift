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

    func testReadingTypingSelectionAndAa() {
        let app = launch("-seedPolished")
        let editor = app.textViews["transcript-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 25), "editor missing")
        capture(app, "phone-1-reading")

        // dy 0.62 landed on the People footer (run 1); 0.40 is the name-free "commonplace" line.
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.40)).tap()
        XCTAssertTrue(app.buttons["accessory-done"].waitForExistence(timeout: 5), "top-bar Done missing")
        XCTAssertTrue(app.buttons["accessory-format"].exists, "Aa missing from the keyboard bar")
        capture(app, "phone-2-typing")

        // Selection: double-tap a word → the edit menu (Cut Copy Paste · B I U S · New person…).
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.40)).doubleTap()
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
        let app = launch("-seedPhotoTextMemo")
        let editor = app.textViews["transcript-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 25), "editor missing")
        capture(app, "phone-5-photo-before")
        let photo = editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        photo.press(forDuration: 0.8, thenDragTo: editor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        capture(app, "phone-5-photo-after")
    }

    func testBookQuote() {
        let app = launch("-seedQuoteMemo")
        XCTAssertTrue(app.textViews["transcript-editor"].waitForExistence(timeout: 25), "editor missing")
        capture(app, "phone-6-quote")
    }

    func testSpeakers() {
        let app = launch("-seedConversationMemo")
        XCTAssertTrue(app.buttons["detail-menu"].waitForExistence(timeout: 25), "note missing")
        capture(app, "phone-7-speakers")
    }
}
