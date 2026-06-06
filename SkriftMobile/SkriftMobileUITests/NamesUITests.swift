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
}
