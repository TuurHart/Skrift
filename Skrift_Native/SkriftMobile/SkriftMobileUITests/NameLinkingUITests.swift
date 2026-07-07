import XCTest

/// In-place name-linking (mocks/phone-name-linking.html): verifies tapping a name in the
/// always-editable transcript opens the resolve sheet (NOT the keyboard), and that "New
/// person…" routes to the editable person card. Screenshots both for the vision review.
final class NameLinkingUITests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedNameLinking", "-skipOnboarding", "-appTheme", "dark"]
        app.launch()
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let s = XCTAttachment(screenshot: app.screenshot())
        s.name = name; s.lifetime = .keepAlways; add(s)
    }

    func testTapNameOpensResolveSheetThenEditor() throws {
        let app = launch()
        let editor = app.textViews["transcript-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "name-linking transcript didn't render")
        shot(app, "namelink-detail")

        // Tap the ambiguous "Jack" ("Met up with Jack…", first transcript line).
        // The editor element spans the WHOLE page body with the metadata header
        // scrolling inside it (note-editing re-foundation), so the first text
        // line is ANCHORED off the importance card's bottom edge — not a guessed
        // fraction. Sweep a few x-positions along that line and stop when the
        // resolve sheet appears. A name tap must open the sheet, not the keyboard.
        let importance = app.otherElements["significance-circles"].firstMatch
        XCTAssertTrue(importance.waitForExistence(timeout: 5), "importance card missing from the header")
        let firstLineY = importance.frame.maxY + 26          // centre of the first text line
        let dy = (firstLineY - editor.frame.minY) / editor.frame.height
        let newPerson = app.buttons["New person…"]
        for (i, dx) in [0.24, 0.21, 0.27, 0.18, 0.30].enumerated() {
            editor.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
            if newPerson.waitForExistence(timeout: 2) { break }
            if i == 0 { shot(app, "namelink-after-tap") }   // capture the first attempt's state
            if app.keyboards.element.exists { app.swipeDown() }   // a plain-text tap → dismiss + retry
        }
        XCTAssertTrue(newPerson.exists, "tapping a name didn't open the resolve sheet")
        XCTAssertTrue(app.buttons["Keep as plain text"].exists, "missing keep-as-plain action")
        XCTAssertFalse(app.keyboards.element.exists, "a name tap must NOT raise the keyboard")
        shot(app, "namelink-resolve-sheet")

        // New person… → the editable person card (mock state 5).
        newPerson.tap()
        XCTAssertTrue(app.buttons["person-editor-done"].waitForExistence(timeout: 5),
                      "New person didn't open the person editor")
        shot(app, "namelink-person-editor")
    }

    func testPeopleInNoteChipBar() throws {
        let app = launch()
        let row = app.buttons["people-in-note-row"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "people-in-note row missing")
        row.tap()
        XCTAssertTrue(app.buttons["people-someone-else"].waitForExistence(timeout: 5),
                      "people-in-note chip sheet didn't open")
        // Both Jacks + Hendri + Rose are candidate chips.
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS 'Hendri'")).firstMatch.exists)
        shot(app, "namelink-people-sheet")
    }
}
