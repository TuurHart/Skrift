import XCTest

/// Settings → Destinations: the one switch and the one portfolio-folder pick.
///
/// Off is the shipped default and must look like nothing changed; on reveals the folder
/// row; configured shows what Skrift will actually do with that folder BEFORE it does it.
/// Screenshots because a settings section reviewed from source is one nobody has looked at.
final class DestinationSettingsUITests: XCTestCase {

    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 1.0)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Launch STRAIGHT into Settings via `-openTab`. Not `app.tabBars.buttons["Settings"]`:
    /// the tab bar here is a custom floating pill, so `app.tabBars` matches nothing and the
    /// tap silently does nothing — the run then screenshots the Notes list and fails on a
    /// missing switch that was never off-screen in the first place.
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedDemoMemos", "-openTab", "settings"] + extra
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let cancel = springboard.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 2) { cancel.tap() }
        return app
    }

    /// Scroll the Settings form until `element` is on screen (Destinations sits below
    /// Obsidian, which is already well down the list).
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        // Short drags (~15% of the screen), not `swipeUp()`: a full swipe can carry a row from
        // behind the floating tab bar (exists, not hittable) straight past the top, and the test
        // then never sees it hittable. The section changed height with D189, which moved the stops.
        for _ in 0..<30 {
            if element.exists && element.isHittable { return }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.47))
            from.press(forDuration: 0.05, thenDragTo: to)
        }
    }

    /// The default state, then the switch on. Nothing is pre-configured here, so the
    /// footer must say what to do next rather than promising what it can't yet do.
    func testSwitchOffThenOn() {
        let app = launch(["-resetDestinations"])
        let toggle = app.switches["destinations-toggle"]
        reveal(app, toggle)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "the Destinations switch is missing")
        XCTAssertFalse(app.buttons["portfolio-folder"].exists,
                       "off means off — no folder row until the switch is on")
        capture(app, "settings-off")

        // Tap the SWITCH, not the row. A SwiftUI Toggle in a Form reports the whole row as
        // the element, so `toggle.tap()` lands on the label and changes nothing — the value
        // stayed "0" and the failure read like a broken binding.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1", "the switch should now read on")
        let folder = app.buttons["portfolio-folder"]
        reveal(app, folder)   // the new row can land below the fold on a small screen
        XCTAssertTrue(folder.waitForExistence(timeout: 5),
                      "on reveals the portfolio folder pick")
        capture(app, "settings-on-unconfigured")
    }

    /// Configured: the `_inbox` folder Portfolio notes land in is shown read-only, so what the
    /// folder is about to be used for is visible before anything is written to it.
    func testConfiguredShowsTheInboxFolder() {
        let app = launch(["-destinationsOn", "-seedPortfolioFolder"])
        let folderRow = app.buttons["portfolio-folder"]
        reveal(app, folderRow)
        XCTAssertTrue(folderRow.waitForExistence(timeout: 5))
        let inbox = app.staticTexts["portfolio-path-portfolio"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 5),
                      "the resolved subfolder must be shown, not just promised")
        // `LabeledContent` reads its label and value as ONE element ("Portfolio, portfolio/_inbox"),
        // which is the right thing for VoiceOver — so match the path inside it.
        XCTAssertTrue(inbox.label.hasSuffix("portfolio/_inbox"), inbox.label)
        capture(app, "settings-configured")
    }
}
