import XCTest

/// Phase 5: the Names screen lists seeded people and can add a new one.
/// `-seedDemoNames` overwrites names.json with a known set each launch.
final class NamesUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testNamesListShowsSeededAndAddsPerson() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedDemoNames"]
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let cancel = springboard.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 2) { cancel.tap() }

        app.buttons["settings-button"].tap()
        let namesLink = app.descendants(matching: .any).matching(identifier: "names-link").firstMatch
        XCTAssertTrue(namesLink.waitForExistence(timeout: 15))
        namesLink.tap()

        XCTAssertTrue(app.staticTexts["Jane Doe"].waitForExistence(timeout: 5), "seeded person missing")

        app.buttons["add-person-button"].tap()
        let nameField = app.textFields["person-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Carl Jung")
        app.buttons["save-person-button"].tap()

        XCTAssertTrue(app.staticTexts["Carl Jung"].waitForExistence(timeout: 5), "added person missing")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "names-list"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testVoiceStatesAndPersonDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedDemoNames"]
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let cancel = springboard.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 2) { cancel.tap() }

        app.buttons["settings-button"].tap()
        let namesLink = app.descendants(matching: .any).matching(identifier: "names-link").firstMatch
        XCTAssertTrue(namesLink.waitForExistence(timeout: 10))
        namesLink.tap()

        // Jane is seeded with a voice embedding → "Voice enrolled"; Bob isn't.
        XCTAssertTrue(app.staticTexts["Voice enrolled"].waitForExistence(timeout: 5),
                      "enrolled voice state missing")

        // Open Bob's detail → the Add voice affordance is present. Query the row
        // as a button (the NavigationLink is the button; the id also propagates
        // to its child texts, which are not buttons).
        let bobRow = app.buttons["person-Bob Smith"]
        XCTAssertTrue(bobRow.waitForExistence(timeout: 5))
        bobRow.tap()
        let addVoice = app.buttons["add-voice-button"]
        XCTAssertTrue(addVoice.waitForExistence(timeout: 5), "Add voice affordance missing")
        addVoice.tap()
        XCTAssertTrue(app.staticTexts["Voice enrollment"].waitForExistence(timeout: 5),
                      "enroll sheet didn't appear")
    }
}
