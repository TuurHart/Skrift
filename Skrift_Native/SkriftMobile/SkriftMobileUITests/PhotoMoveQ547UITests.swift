import XCTest

/// Q547: dragging a picture in a voice note keeps the paragraphs, draws the picture once, lands
/// where the line showed, and can be undone. The note is opened from the list (a real push).
/// Screenshots land in `SKRIFT_SHOT_DIR` (pass `TEST_RUNNER_SKRIFT_SHOT_DIR`).
final class PhotoMoveQ547UITests: XCTestCase {

    private func capture(_ app: XCUIApplication, _ name: String) {
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

    private func openNote() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedPhotoMoveVoice", "-skipOnboarding", "-routeViaList", "-appTheme", "light"]
        app.launch()
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "list row missing")
        row.tap()
        XCTAssertTrue(app.textViews["transcript-editor"].waitForExistence(timeout: 25), "editor missing")
        Thread.sleep(forTimeInterval: 1.5)
        return app
    }

    /// Drag the picture (bottom of the note) to just under the first paragraph; the screenshot
    /// during the hold comes from a second thread (the drag call blocks this one).
    func testDragPictureUpKeepsParagraphsAndUndoes() {
        let app = openNote()
        capture(app, "q547-1-before")
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.13, dy: 0.50))
        // Between paragraph 1 (y ~0.28) and paragraph 2 (y ~0.34): the upper half of paragraph 2.
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.315))
        let during = expectation(description: "shot during the drag")
        DispatchQueue.global().asyncAfter(deadline: .now() + 3.4) {
            self.capture(app, "q547-2-during")
            during.fulfill()
        }
        from.press(forDuration: 0.8, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 2.5)
        wait(for: [during], timeout: 10)
        Thread.sleep(forTimeInterval: 1.0)
        capture(app, "q547-3-after")

        // Undo: put the caret in the text (keyboard up), tap the bar's undo.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.30)).tap()
        let undo = app.buttons["accessory-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "keyboard bar missing")
        capture(app, "q547-4-keyboard-up")
        undo.tap()
        Thread.sleep(forTimeInterval: 1.0)
        capture(app, "q547-5-after-undo")
    }

    /// Above the first paragraph: the line sits over it and the picture lands first.
    func testDragPictureAboveTheFirstParagraph() {
        let app = openNote()
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.13, dy: 0.50))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.27))
        let during = expectation(description: "shot during the drag")
        DispatchQueue.global().asyncAfter(deadline: .now() + 3.4) {
            self.capture(app, "q547-6-top-during")
            during.fulfill()
        }
        from.press(forDuration: 0.8, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 2.5)
        wait(for: [during], timeout: 10)
        Thread.sleep(forTimeInterval: 1.0)
        capture(app, "q547-7-top-after")
    }

    /// D224 with the keyboard up: a tap on the picture opens it (it used to put the caret
    /// against the picture's edge and show Paste / Select).
    func testTapOnAPictureWithTheKeyboardUpOpensIt() {
        let app = openNote()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.28)).tap()
        XCTAssertTrue(app.buttons["accessory-undo"].waitForExistence(timeout: 5), "keyboard bar missing")
        capture(app, "q547-8-keyboard-up")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.47)).tap()
        Thread.sleep(forTimeInterval: 1.5)
        capture(app, "q547-9-after-tap")
    }
}
