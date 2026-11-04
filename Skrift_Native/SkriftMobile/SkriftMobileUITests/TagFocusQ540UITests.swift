import XCTest

/// Q540: Q539 passed here and failed on the real iPhone because its fixture was a RATED note that
/// already had a tag. This runs on what a fresh voice note is: unrated, no tags, no Mac polish.
/// "+ tag" must open the field with the keyboard up, Return must keep it focused, and nothing here
/// ever taps the field itself.
final class TagFocusQ540UITests: XCTestCase {

    private func chip(_ app: XCUIApplication, _ tag: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "tag-chip-\(tag)").firstMatch
    }

    private func hasFocus(_ el: XCUIElement) -> Bool {
        (el.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIApplication().screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testTaglessUnratedNote_plusTagFocusesTypesAndStaysFocusedAfterReturn() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedPolished", "-seedBareNote", "-selectFirstMemo"]
        app.launch()

        let addTag = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'add-tag-button'")).firstMatch
        XCTAssertTrue(addTag.waitForExistence(timeout: 20), "the + tag control is missing")
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'tag-chip-'")).firstMatch.exists,
                       "fixture should start with no tags")
        shot("q540-0-before-plus-tag")
        addTag.tap()

        let field = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'tag-input'")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the inline tag field did not open")
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        expectation(for: focused, evaluatedWith: field)
        waitForExpectations(timeout: 5)
        // Hold longer than the 350 ms grace close: a focus that was lost and re-won would show here.
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(field.exists, "the field closed by itself after opening")
        XCTAssertTrue(hasFocus(field), "the field lost focus after opening (keyboard needed a second tap)")
        shot("q540-1-field-open-empty")

        // First tag, typed straight into the app, no tap on the field.
        app.typeText("qalpha\n")
        XCTAssertTrue(chip(app, "qalpha").waitForExistence(timeout: 5), "first tag did not land")
        Thread.sleep(forTimeInterval: 1.0)   // past the 350 ms grace close and any re-flow
        XCTAssertTrue(field.exists, "the field closed after Return")
        XCTAssertTrue(hasFocus(field), "the field lost focus after Return (Tuur had to tap the tag control again)")

        // Second tag, again with no tap.
        app.typeText("qbeta\n")
        XCTAssertTrue(chip(app, "qbeta").waitForExistence(timeout: 5), "second tag did not land")
        XCTAssertTrue(chip(app, "qalpha").exists, "first tag vanished")
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(field.exists, "the field closed after the second Return")
        XCTAssertTrue(hasFocus(field), "the field lost focus after the second Return")
        shot("q540-2-two-tags-field-beside-chip")

        // Empty Return closes the field; then arm a chip for the armed-chip screenshot.
        app.typeText("\n")
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: field)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "empty Return should close the field")
        chip(app, "qalpha").tap()
        Thread.sleep(forTimeInterval: 0.5)
        shot("q540-3-armed-chip")
    }
}
