import XCTest

/// Q539: "+ tag" opens the field already focused (keyboard up), Return adds the tag and the field
/// stays focused for the next one. Nothing here taps the field itself.
final class TagFocusQ539UITests: XCTestCase {

    private func chip(_ app: XCUIApplication, _ tag: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "tag-chip-\(tag)").firstMatch
    }

    func testPlusTagTypesWithoutTappingTheFieldAndStaysFocusedAfterReturn() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedPolished", "-selectFirstMemo"]
        app.launch()

        let addTag = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'add-tag-button'")).firstMatch
        XCTAssertTrue(addTag.waitForExistence(timeout: 20), "the + tag control is missing")
        addTag.tap()

        let field = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'tag-input'")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the inline tag field did not open")
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        expectation(for: focused, evaluatedWith: field)
        waitForExpectations(timeout: 5)

        // First tag: typed straight into the app, no tap on the field.
        app.typeText("qalpha\n")
        XCTAssertTrue(chip(app, "qalpha").waitForExistence(timeout: 5), "first tag did not land")
        XCTAssertTrue(field.exists, "the field closed after Return")
        expectation(for: focused, evaluatedWith: field)
        waitForExpectations(timeout: 5)

        // Second tag, again with no tap.
        app.typeText("qbeta\n")
        XCTAssertTrue(chip(app, "qbeta").waitForExistence(timeout: 5), "second tag did not land")
        XCTAssertTrue(chip(app, "qalpha").exists, "first tag vanished")
        expectation(for: focused, evaluatedWith: field)
        waitForExpectations(timeout: 5)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "q539-two-tags-field-focused"
        shot.lifetime = .keepAlways
        add(shot)

        // Empty Return closes the field and the keyboard.
        app.typeText("\n")
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: field)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "empty Return should close the field")
    }
}
