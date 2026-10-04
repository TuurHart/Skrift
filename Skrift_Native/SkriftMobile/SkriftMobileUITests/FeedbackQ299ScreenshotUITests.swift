import XCTest

/// Q299 visual check: the FeedbackKit button floats over the Notes screen and its sheet
/// says "From the Notes screen". PNG lands in `plan/reads/feedback-kit/` via
/// `SKRIFT_SHOT_DIR` (or the xcresult attachments). Needs the key from
/// `~/.config/feedback-kit/skrift.xcconfig`: without it FeedbackKit shows no button.
final class FeedbackQ299ScreenshotUITests: XCTestCase {

    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 1.0)
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SKRIFT_SHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    func testFeedbackSheetFromNotes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedDemoMemos"]
        app.launch()
        let button = app.buttons["Feedback"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 30), "feedback button missing (no key?)")
        capture(app, "notes-with-button")
        button.tap()
        let from = app.staticTexts["From the Notes screen"].firstMatch
        XCTAssertTrue(from.waitForExistence(timeout: 10), "sheet does not read 'From the Notes screen'")
        capture(app, "sheet")
    }
}
