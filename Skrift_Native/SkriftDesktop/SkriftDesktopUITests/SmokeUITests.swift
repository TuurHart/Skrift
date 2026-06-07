import XCTest

final class SmokeUITests: XCTestCase {
    func testAppLaunchesAndShowsSidebar() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        XCTAssertTrue(
            app.staticTexts["Skrift"].waitForExistence(timeout: 15),
            "the Skrift sidebar brand should appear at launch"
        )
    }
}
