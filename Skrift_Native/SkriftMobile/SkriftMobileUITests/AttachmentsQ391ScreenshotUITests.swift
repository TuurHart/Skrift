import XCTest

/// Q391 visual check against the signed mock Q384-note-attachments (phone): the seeded note with a
/// large video, a photo, a DXF card and a PDF card; the same note after Set All to Large; and the
/// block's hold menu. Screenshots land in `SKRIFT_SHOT_DIR` (pass `TEST_RUNNER_SKRIFT_SHOT_DIR`),
/// or the xcresult attachments. Light theme, opened through the list.
final class AttachmentsQ391ScreenshotUITests: XCTestCase {

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

    private func openNote(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedAttachmentMemo", "-selectFirstMemo", "-skipOnboarding",
                               "-routeViaList", "-appTheme", "light"] + extra
        app.launch()
        let editor = app.textViews["transcript-editor"]
        if !editor.waitForExistence(timeout: 6) {
            let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
            if row.waitForExistence(timeout: 10) { row.tap() }
        }
        XCTAssertTrue(editor.waitForExistence(timeout: 25), "editor missing")
        Thread.sleep(forTimeInterval: 2.0)   // the video poster is made off the main thread
        return app
    }

    func testTheNoteSmallByDefaultThenScrolled() {
        let app = openNote()
        capture(app, "phone-1-note")
        app.swipeUp()
        capture(app, "phone-2-note-scrolled")
    }

    func testTheNoteAllLarge() {
        let app = openNote(["-seedAttachmentLarge"])
        capture(app, "phone-3-large")
        app.swipeUp()
        capture(app, "phone-4-large-scrolled")
    }

    func testTheHoldMenuOnTheVideo() {
        let app = openNote()
        // The video block sits under the first paragraph, about halfway down the screen.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.52)).press(forDuration: 0.8)
        capture(app, "phone-5-hold-menu")
    }
}
