import XCTest

/// Q330 / D184: select a word the app does not know ("studio", not on the roster) in the note
/// and screenshot the text menu with its "New person…" item, then the prefilled editor.
final class NewPersonFromSelectionQ330ScreenshotUITests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let s = XCTAttachment(screenshot: app.screenshot())
        s.name = name; s.lifetime = .keepAlways; add(s)
    }

    func testSelectingAnUnknownWordOffersNewPerson() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedNameLinking", "-skipOnboarding", "-appTheme", "dark"]
        app.launch()
        let editor = app.textViews["transcript-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let importance = app.buttons["rating-pill"].firstMatch
        XCTAssertTrue(importance.waitForExistence(timeout: 5))
        let newPerson = app.menuItems["New person…"]
        // First line: "Met up with Jack this morning at the studio and we ran…". Sweep the
        // line; a double-tap on a plain word selects it and raises the edit menu.
        let y = importance.frame.maxY + 26
        let dy = (y - editor.frame.minY) / editor.frame.height
        for dx in [0.62, 0.58, 0.66, 0.70, 0.54, 0.74] {
            editor.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).doubleTap()
            if newPerson.waitForExistence(timeout: 2) { break }
            if app.buttons["Keep as plain text"].exists { app.swipeDown() }
        }
        shot(app, "q330-menu")
        XCTAssertTrue(newPerson.exists, "selecting an unknown word didn't offer New person…")
        newPerson.tap()
        XCTAssertTrue(app.buttons["person-editor-done"].waitForExistence(timeout: 5),
                      "New person… didn't open the person editor")
        shot(app, "q330-editor")
    }
}
