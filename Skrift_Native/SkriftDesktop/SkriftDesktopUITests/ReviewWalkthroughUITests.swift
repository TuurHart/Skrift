import XCTest

/// Pilot/walkthrough of the live app. Launches with `-demo` (seeds sample notes
/// and skips the first-launch wizard), then drives sidebar chrome + the Settings
/// round-trip via accessibility identifiers — data-independent so it's stable.
///
/// NOTE: XCUITest is TCC-blocked in the headless automation context (needs a
/// one-time macOS Automation grant); run from Xcode or a granted machine. The
/// harness + ids compile as part of `build-for-testing`. Extend with Process →
/// Ready and resolver flows once the engines can be stubbed for UI tests
/// (launch hooks `-stubEnhancement` / `-seedTranscript`, per plan §5).
final class ReviewWalkthroughUITests: XCTestCase {
    func testSidebarAndSettingsWalkthrough() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()

        // Sidebar chrome renders.
        XCTAssertTrue(app.staticTexts["Skrift"].waitForExistence(timeout: 15), "brand should appear")
        XCTAssertTrue(app.buttons["sidebar.process"].waitForExistence(timeout: 5), "Process button")

        // Open Settings via the gear, confirm it appears, then close it.
        let gear = app.buttons["sidebar.settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 5), "settings gear")
        gear.click()

        let settingsOpened = app.otherElements["settings.root"].waitForExistence(timeout: 5)
            || app.staticTexts["Settings"].waitForExistence(timeout: 5)
        XCTAssertTrue(settingsOpened, "Settings sheet should open")

        let done = app.buttons["settings.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Settings Done button")
        done.click()
        XCTAssertFalse(app.buttons["settings.done"].waitForExistence(timeout: 2), "Settings should close")
    }
}
