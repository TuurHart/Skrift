import XCTest

/// Q543: a tap on a header chip must not make the note BODY first responder (keyboard + bar rise),
/// and "+ tag" must open and focus its field when the body already has the keyboard (a typed new
/// note starts that way). Notes are opened by tapping them in the list (Q540: a note launched
/// straight into behaves differently). Asserts on focus and the keyboard only; the top-bar
/// buttons are moving into the keyboard bar (Q544).
final class TagFocusQ543UITests: XCTestCase {

    private func hasFocus(_ el: XCUIElement) -> Bool {
        (el.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    private func chip(_ app: XCUIApplication, _ tag: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "tag-chip-\(tag)").firstMatch
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    private func launchAndOpenFromList() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedDemoMemos", "-seedBareNote"]
        app.launch()
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-1").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "memo-row-1 never appeared")
        row.tap()
        return app
    }

    private func addTagButton(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'add-tag-button'")).firstMatch
    }

    private func tagField(_ app: XCUIApplication) -> XCUIElement {
        app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'tag-input'")).firstMatch
    }

    /// Adds one tag, then closes the field with an empty Return so the keyboard drops.
    private func addOneTag(_ app: XCUIApplication, _ tag: String) {
        let add = addTagButton(app)
        XCTAssertTrue(add.waitForExistence(timeout: 20), "the + tag control is missing")
        add.tap()
        let field = tagField(app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the inline tag field did not open")
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        expectation(for: focused, evaluatedWith: field)
        waitForExpectations(timeout: 5)
        app.typeText("\(tag)\n")
        XCTAssertTrue(chip(app, tag).waitForExistence(timeout: 5), "#\(tag) chip did not land")
        app.typeText("\n")   // empty Return closes the field
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: field)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "empty Return should close the field")
        // Let the keyboard finish going down before the test taps a chip.
        let kbGone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter().wait(for: [kbGone], timeout: 5), .completed, "the keyboard should be down after the tag field closes")
    }

    /// Tapping a chip arms it; the body must stay unfocused and the keyboard down, on the first
    /// tap and on the second (remove).
    func testTappingTagChipDoesNotFocusBody() {
        let app = launchAndOpenFromList()
        addOneTag(app, "qchip")
        let body = app.textViews["transcript-editor"]
        XCTAssertTrue(body.exists, "the note body is missing")
        XCTAssertFalse(hasFocus(body), "the body should not have focus before any chip tap")

        chip(app, "qchip").tap()   // arms it
        Thread.sleep(forTimeInterval: 1.0)
        shot(app, "q543-a-armed-chip")
        XCTAssertFalse(hasFocus(body), "tapping a header chip made the note body first responder")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "tapping a header chip raised the keyboard")

        chip(app, "qchip").tap()   // second tap removes it
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertFalse(chip(app, "qchip").exists, "the second tap should remove the tag")
        XCTAssertFalse(hasFocus(body), "removing a tag made the note body first responder")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "removing a tag raised the keyboard")
    }

    /// A typed new note starts with the body focused. "+ tag" must still open its field and take focus.
    func testPlusTagWithBodyFocusedOpensAndFocusesField() {
        let app = launchAndOpenFromList()
        let add = addTagButton(app)
        XCTAssertTrue(add.waitForExistence(timeout: 20), "the + tag control is missing")
        let body = app.textViews["transcript-editor"]
        XCTAssertTrue(body.waitForExistence(timeout: 10), "the note body is missing")
        // Tap low in the body so the tap lands on text/blank body, not on the header.
        body.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
        let bodyFocused = expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: body)
        XCTAssertEqual(XCTWaiter().wait(for: [bodyFocused], timeout: 5), .completed, "fixture: the body should have focus first")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "fixture: the keyboard should be up")
        shot(app, "q543-b-body-focused")

        XCTAssertTrue(add.waitForExistence(timeout: 5), "the + tag control vanished once the body had focus")
        add.tap()
        let field = tagField(app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the inline tag field did not open")
        let fieldFocused = expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: field)
        XCTAssertEqual(XCTWaiter().wait(for: [fieldFocused], timeout: 5), .completed, "focus did not move to the tag field")
        // Hold past the 350 ms grace close: a focus lost and re-won would show here.
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(field.exists, "the tag field closed by itself")
        XCTAssertTrue(hasFocus(field), "the tag field lost focus")
        XCTAssertFalse(hasFocus(body), "the body still has focus beside the tag field")
        shot(app, "q543-b-field-open")

        app.typeText("qfocus\n")
        XCTAssertTrue(chip(app, "qfocus").waitForExistence(timeout: 5), "tag typed into the field did not land")
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(hasFocus(tagField(app)), "the field lost focus after Return")
    }
}
