import XCTest

/// Q466 visual check (mock Q452 option B): with the keyboard up, a few typed lines scroll the
/// header off the top and the last line stays above the keyboard bar. Screenshots land in
/// `SKRIFT_SHOT_DIR` (TEST_RUNNER_SKRIFT_SHOT_DIR) and the xcresult.
final class TypingScrollQ466ScreenshotUITests: XCTestCase {

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

    private var corpusPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test-fixtures/corpus").path
    }

    func testHeaderScrollsAwayWhileTyping() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-corpus", corpusPath, "-destinationsOn", "-skipOnboarding"]
        app.launch()
        let newNote = app.buttons["ipad-new-note-button"]
        XCTAssertTrue(newNote.waitForExistence(timeout: 20), "the new-note button never appeared")
        newNote.tap()
        XCTAssertTrue(app.buttons["note-back-button"].waitForExistence(timeout: 10))
        let tip = app.buttons["Continue"]
        if tip.waitForExistence(timeout: 2) { tip.tap() }
        let rating = app.buttons["rating-pill"]
        XCTAssertTrue(rating.waitForExistence(timeout: 5), "rating pill missing")
        let body = app.textViews["transcript-editor"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        capture(app, "1-keyboard-up-before-typing")
        body.typeText("First line of the note")
        capture(app, "2-after-first-line")
        XCTAssertFalse(rating.isHittable, "the header row must have scrolled off the top after the first line")
        body.typeText("\nSecond line\nThird line\nFourth line\nFifth line")
        capture(app, "3-after-five-lines")
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.exists)
        XCTAssertFalse(rating.isHittable)
    }
}
