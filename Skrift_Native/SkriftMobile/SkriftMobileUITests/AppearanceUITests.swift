import XCTest

/// Captures light-mode screenshots for design review. The `sk*` palette is now
/// adaptive (UIColor dynamic provider) and `.preferredColorScheme` is driven by
/// Settings → Theme; passing `-appTheme light` (NSUserDefaults arg domain) forces
/// the light variant so we can eyeball the palette without a device.
final class AppearanceUITests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(theme: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedDemoMemos", "-seedDemoNames",
                               "-skipOnboarding", "-appTheme", theme]
        app.launch()
        return app
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testLightModeScreens() throws {
        let app = launch(theme: "light")

        let row0 = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row0.waitForExistence(timeout: 10))
        snap(app, "light-1-memos-list")

        // Settings (form rows/controls on light).
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["pair-mac-link"].waitForExistence(timeout: 5))
        snap(app, "light-2-settings")
        // Back to the memos list (Settings is a root tab now, not a sheet).
        app.tabBars.buttons["Notes"].tap()

        // Memo detail (cards, transcript, significance slider, glass player bar).
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        // Transcript is now an always-editable text view (its text is the value).
        let editor = app.textViews["transcript-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        snap(app, "light-3-memo-detail")
    }
}
