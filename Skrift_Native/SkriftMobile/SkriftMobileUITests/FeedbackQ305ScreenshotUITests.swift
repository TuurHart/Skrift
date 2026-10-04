import XCTest

/// Q305 visual check: the FeedbackKit sheet follows Skrift's own theme (Settings -> Theme,
/// `appTheme`) natively. Screenshots the open sheet in dark and light, with the
/// "What gets sent" row expanded so its chevron is on screen. PNGs land in
/// `SKRIFT_SHOT_DIR` (pass it as `TEST_RUNNER_SKRIFT_SHOT_DIR`) and in the xcresult.
final class FeedbackQ305ScreenshotUITests: XCTestCase {

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

    private func openSheet(theme: String, name: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedDemoMemos", "-appTheme", theme]
        app.launch()
        let button = app.buttons["Feedback"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 30), "feedback button missing (no key?)")
        button.tap()
        XCTAssertTrue(app.staticTexts["From the Notes screen"].firstMatch.waitForExistence(timeout: 10))
        capture(app, name)
        let sent = app.descendants(matching: .any)["What gets sent"].firstMatch
        if sent.exists { sent.tap(); capture(app, "\(name)-sent") }
    }

    func testSheetDark() { openSheet(theme: "dark", name: "sheet-dark") }
    func testSheetLight() { openSheet(theme: "light", name: "sheet-light") }
}
