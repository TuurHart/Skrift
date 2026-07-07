import XCTest

/// Smoke test: the app launches in the Simulator and shows the memos root.
/// Proves the xcodegen + xcodebuild + XCUITest toolchain end to end. Uses an
/// in-memory store so the launch is deterministic (no leftover sim data).
final class SmokeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesAndShowsMemosRoot() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore"]
        app.launch()

        // Dismiss any leftover system "Open in <app>?" URL-scheme dialog that can
        // linger from a previous deep-link (the RN dev client shares the `skrift`
        // scheme + bundle id). Harmless no-op when absent.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let cancel = springboard.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 2) { cancel.tap() }

        let appeared = app.staticTexts["Notes"].waitForExistence(timeout: 15)
            || app.navigationBars["Notes"].waitForExistence(timeout: 5)
        XCTAssertTrue(appeared, "Memos root never appeared — app did not launch cleanly")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "01-launch"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
