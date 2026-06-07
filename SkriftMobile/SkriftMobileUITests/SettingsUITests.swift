import XCTest

/// Phase 7.6: Settings + Bonjour Pair-a-Mac. Uses `-seedDiscoveredMacs` to inject
/// fake discovered Macs (the sim can't see the real one); the manual-connect path
/// is fully exercised.
final class SettingsUITests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    func testPairMacDiscoveryAndManualConnect() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedDemoMemos", "-seedDiscoveredMacs"]
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let cancel = springboard.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 2) { cancel.tap() }

        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.staticTexts["Live transcription"].waitForExistence(timeout: 5), "capture toggle missing")

        let pair = app.descendants(matching: .any).matching(identifier: "pair-mac-link").firstMatch
        XCTAssertTrue(pair.waitForExistence(timeout: 5))
        pair.tap()

        // Seeded Bonjour discovery list shows.
        XCTAssertTrue(app.staticTexts["Skrift Desktop"].waitForExistence(timeout: 5),
                      "discovered Mac missing")

        // Manual fallback connects.
        let host = app.textFields["pair-host-field"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        host.tap()
        host.typeText("10.0.0.9")
        app.buttons["manual-connect-button"].tap()

        // Back in Settings, the connection status reflects the manual host.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["10.0.0.9"].waitForExistence(timeout: 5),
                      "connection status didn't update after manual connect")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "settings"; shot.lifetime = .keepAlways; add(shot)
    }

    /// Multi-Mac disambiguation: each discovered Mac shows its host/IP per row,
    /// and the "Looking for more Macs…" spinner caps to a "Search again" button
    /// once discovery settles (seeded settle = 2s).
    func testDiscoveredMacsShowIPAndSpinnerCaps() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedDemoMemos", "-seedDiscoveredMacs"]
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let cancel = springboard.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 2) { cancel.tap() }

        app.buttons["settings-button"].tap()
        let pair = app.descendants(matching: .any).matching(identifier: "pair-mac-link").firstMatch
        XCTAssertTrue(pair.waitForExistence(timeout: 5))
        pair.tap()

        // Each discovered Mac shows its resolved host/IP per row (so two Macs on
        // the same network are distinguishable).
        let ip = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "192.168.1.22")).firstMatch
        XCTAssertTrue(ip.waitForExistence(timeout: 5), "discovered Mac IP not shown per row")
        let host = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "studio.local")).firstMatch
        XCTAssertTrue(host.exists, "second discovered Mac host not shown per row")
        // Port must render as a bare 8000, not locale-grouped "8.000" (a buggy
        // "8.000" label contains no "8000" substring, so this discriminates).
        let port = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "8000")).firstMatch
        XCTAssertTrue(port.exists, "port should render as 8000, not a locale-grouped 8.000")

        // The spinner caps: after the settle window the row becomes "Search again".
        let searchAgain = app.buttons["discovery-search-again"]
        XCTAssertTrue(searchAgain.waitForExistence(timeout: 6), "discovery spinner never capped to Search again")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "pair-mac-disambiguation"; shot.lifetime = .keepAlways; add(shot)
    }
}
