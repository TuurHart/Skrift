import XCTest

/// Phase 0 smoke test: the app launches in the Simulator and shows its root.
/// Proves the xcodegen + xcodebuild + XCUITest toolchain end to end. Later
/// phases add real walk-throughs (see MOBILE_NATIVE_REWRITE_PLAN.md §5).
final class SmokeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesAndShowsTitle() throws {
        let app = XCUIApplication()
        app.launch()

        // Dismiss any leftover system "Open in <app>?" URL-scheme dialog that can
        // linger from a previous deep-link (the RN dev client shares the `skrift`
        // scheme + bundle id). Harmless no-op when absent.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let cancel = springboard.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 2) { cancel.tap() }

        // Query by the visible label (robust) — identifier-based queries on a
        // SwiftUI Text can be flaky on first render.
        let title = app.staticTexts["Skrift"]
        XCTAssertTrue(
            title.waitForExistence(timeout: 15),
            "Root title 'Skrift' never appeared — app did not launch cleanly"
        )

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "01-launch"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
