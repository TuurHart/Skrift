import XCTest

/// Q551: after a picture goes into a note the caret waits on its own empty line below it, so the
/// next word is a new paragraph and not glued to the picture. The note is opened from the list
/// (a real push). Screenshots land in `SKRIFT_SHOT_DIR` (pass `TEST_RUNNER_SKRIFT_SHOT_DIR`).
final class PhotoCaretQ551UITests: XCTestCase {

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

    private func editorValue(_ app: XCUIApplication) -> String {
        (app.textViews["transcript-editor"].value as? String) ?? ""
    }

    func testTypingAfterAPictureStartsANewParagraph() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedPhotoMoveVoice", "-skipOnboarding", "-routeViaList",
                               "-appTheme", "light", "-fakePhotoPick"]
        app.launch()
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "list row missing")
        row.tap()
        let editor = app.textViews["transcript-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 25), "editor missing")
        Thread.sleep(forTimeInterval: 1.5)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.30)).tap()
        XCTAssertTrue(app.buttons["accessory-photo"].waitForExistence(timeout: 5), "keyboard bar missing")
        let before = editorValue(app)
        capture(app, "q551-1-start")

        app.buttons["accessory-photo"].tap()
        let choose = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Choose Photo")).firstMatch
        XCTAssertTrue(choose.waitForExistence(timeout: 5), "attach menu missing")
        choose.tap()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertNotEqual(editorValue(app), before, "the picture landed in the note")
        capture(app, "q551-2-picture-in")

        app.typeText("OMEGA")
        Thread.sleep(forTimeInterval: 0.6)
        let after = editorValue(app)
        capture(app, "q551-3-typed-word")
        let ns = after as NSString
        let word = ns.range(of: "OMEGA")
        XCTAssertNotEqual(word.location, NSNotFound, "the word was typed: \(after)")
        XCTAssertGreaterThanOrEqual(word.location, 2)
        XCTAssertEqual(ns.substring(with: NSRange(location: word.location - 2, length: 2)), "\n\n",
                       "the word starts a new paragraph below the picture: \(after.debugDescription)")
    }
}
