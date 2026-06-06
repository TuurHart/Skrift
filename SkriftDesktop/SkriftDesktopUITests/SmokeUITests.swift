import XCTest

final class SmokeUITests: XCTestCase {
    func testAppLaunchesAndShowsWelcome() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        XCTAssertTrue(
            app.staticTexts["welcome.title"].waitForExistence(timeout: 15),
            "welcome.title should appear at launch"
        )
    }
}
