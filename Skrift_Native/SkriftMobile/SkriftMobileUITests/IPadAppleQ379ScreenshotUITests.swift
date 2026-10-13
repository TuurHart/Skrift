import XCTest

/// Q379 visual check against the signed mock Q378-ipad-apple (tabs option A): list + note,
/// Aa, attach, list hidden, portrait. Run on an iPad Pro 13" simulator; screenshots land in
/// `plan/reads/ipad-apple/` via `SKRIFT_SHOT_DIR` (pass `TEST_RUNNER_SKRIFT_SHOT_DIR`), or the
/// xcresult attachments. Skips on a phone.
final class IPadAppleQ379ScreenshotUITests: XCTestCase {

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

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func testIPadListNoteAaAttachHiddenPortrait() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad layout only") }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedDemoMemos", "-selectFirstMemo", "-destinationsOn"]
        app.launch()

        // Tabs option A: the control tops the list column; the note's tools sit in its top bar.
        XCTAssertTrue(element(app, "ipad-tab-control").waitForExistence(timeout: 30), "tab control missing")
        XCTAssertTrue(element(app, "ipad-tab-Notes").exists)
        XCTAssertTrue(element(app, "ipad-note-tools").waitForExistence(timeout: 15), "note toolbar missing")
        capture(app, "ipad-1-list-note")

        // Aa: the full list drops from the button (D197).
        element(app, "ipad-tool-format").tap()
        XCTAssertTrue(element(app, "format-panel").waitForExistence(timeout: 5), "Aa popover missing")
        XCTAssertTrue(element(app, "format-Monostyled").exists, "Monostyled row missing")
        XCTAssertTrue(element(app, "format-Block Quote").exists, "Block Quote missing")
        capture(app, "ipad-2-aa")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.95)).tap()   // dismiss

        // Attach: Apple's menu minus Record Audio, under "Add to this note" (D198).
        element(app, "ipad-tool-attach").tap()
        XCTAssertTrue(app.buttons["Choose Photo or Video"].waitForExistence(timeout: 5), "attach menu missing")
        XCTAssertFalse(app.buttons["Record Audio"].exists)
        capture(app, "ipad-3-attach")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.95)).tap()   // dismiss

        // List hidden: the note takes the screen, the tabs leave with the list.
        element(app, "ipad-toggle-list").tap()
        capture(app, "ipad-4-list-hidden")
        element(app, "ipad-toggle-list").tap()

        // Portrait: the list stays open.
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1.5)
        capture(app, "ipad-5-portrait")
    }
}
