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

        // Tap the ambiguous "Jack" (first line, ~28% across). A name tap must open the
        // resolve sheet, not raise the keyboard. Names are narrow targets in a wrapping
        // text view, so try a few nearby points and stop when the sheet appears.
        let newPerson = app.buttons["New person…"]
        let targets = [CGVector(dx: 0.28, dy: 0.08), CGVector(dx: 0.30, dy: 0.07),
                       CGVector(dx: 0.26, dy: 0.09), CGVector(dx: 0.32, dy: 0.08)]
        for (i, t) in targets.enumerated() {
            editor.coordinate(withNormalizedOffset: t).tap()
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
}
