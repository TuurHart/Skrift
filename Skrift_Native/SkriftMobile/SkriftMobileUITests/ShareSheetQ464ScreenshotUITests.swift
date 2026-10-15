import XCTest

/// Q464 visual check: every state of the calm share sheet (mock `mocks/Q455-share-sheet.html`,
/// option A) rendered by the extension's real views through the DEBUG `-shareSheetDemo` host.
/// Screenshots land in `SKRIFT_SHOT_DIR` (pass it as TEST_RUNNER_SKRIFT_SHOT_DIR), or the
/// xcresult attachments.
final class ShareSheetQ464ScreenshotUITests: XCTestCase {

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

    private func launch(_ state: String, dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-skipOnboarding", "-shareSheetDemo", state]
            + (dark ? ["-shareSheetDemoDark"] : [])
        app.launch()
        return app
    }

    func testEveryShareSheetState() {
        for dark in [false, true] {
            let tag = dark ? "dark" : "light"
            for state in ["voice", "video", "link", "photo"] {
                let app = launch(state, dark: dark)
                XCTAssertTrue(app.buttons["capture-save-button"].waitForExistence(timeout: 20), "\(state): no Save")
                capture(app, "q464-\(state)-\(tag)")
                if state == "voice" {
                    let from = app.textFields["share-sender-field"]
                    XCTAssertTrue(from.waitForExistence(timeout: 5), "the From row is missing on a chat share")
                    from.tap()
                    from.typeText("Ma")
                    XCTAssertTrue(app.buttons["share-sender-suggestion"].firstMatch.waitForExistence(timeout: 5),
                                  "no roster suggestions for \"Ma\"")
                    capture(app, "q464-voice-from-typing-\(tag)")
                }
                if state == "link" {
                    app.buttons["capture-choice-note"].tap()
                    capture(app, "q464-link-note-\(tag)")
                }
                if state == "photo" {
                    XCTAssertTrue(app.textFields["share-sender-field"].exists, "a WhatsApp photo offers From")
                    app.buttons["capture-save-button"].tap()
                    XCTAssertTrue(app.buttons["capture-saved-button"].waitForExistence(timeout: 5), "no Saved receipt")
                    capture(app, "q464-photo-saved-\(tag)")
                }
                app.terminate()
            }
            for state in ["already", "cant"] {
                let app = launch(state, dark: dark)
                XCTAssertTrue(app.buttons["share-feedback-close"].waitForExistence(timeout: 20), "\(state): no Done")
                capture(app, "q464-\(state)-\(tag)")
                app.terminate()
            }
        }
    }
}
