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

        let openNames = app.buttons["open-names-button"]
        XCTAssertTrue(openNames.waitForExistence(timeout: 15))
        openNames.tap()

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

        app.buttons["open-names-button"].tap()

        // Jane is seeded with a voice embedding → "Voice enrolled"; Bob isn't.
        XCTAssertTrue(app.staticTexts["Voice enrolled"].waitForExistence(timeout: 5),
                      "enrolled voice state missing")

        // Open Bob's detail → the Add voice affordance is present.
        app.staticTexts["Bob Smith"].tap()
        XCTAssertTrue(app.staticTexts["person-detail-name"].waitForExistence(timeout: 5)
                      || app.staticTexts["Bob Smith"].waitForExistence(timeout: 5))
        let addVoice = app.buttons["add-voice-button"]
        XCTAssertTrue(addVoice.waitForExistence(timeout: 5), "Add voice affordance missing")
        addVoice.tap()
        XCTAssertTrue(app.staticTexts["Voice enrollment"].waitForExistence(timeout: 5),
                      "enroll sheet didn't appear")
    }
}
