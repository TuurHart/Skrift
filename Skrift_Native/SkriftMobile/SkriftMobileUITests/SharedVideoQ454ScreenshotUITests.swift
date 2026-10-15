import XCTest

/// Q454 visual check (D210): a shared video's note opens with the video itself as the inline
/// block at the top (small by default, D202), the transcript below it, and no "Photo" card.
/// Screenshots land in `SKRIFT_SHOT_DIR` (pass `TEST_RUNNER_SKRIFT_SHOT_DIR`), or the xcresult.
final class SharedVideoQ454ScreenshotUITests: XCTestCase {

    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 1.0)
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

    func testTheSharedVideoNote() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedSharedVideoMemo", "-selectFirstMemo", "-skipOnboarding",
                               "-routeViaList", "-appTheme", "light"]
        app.launch()
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 25), "list row missing")
        capture(app, "q454-phone-list")
        row.tap()
        XCTAssertTrue(app.textViews["transcript-editor"].waitForExistence(timeout: 25), "editor missing")
        Thread.sleep(forTimeInterval: 2.0)   // the video poster is made off the main thread
        capture(app, "q454-phone-note")
    }
}
