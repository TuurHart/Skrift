import XCTest

/// Non-gating screenshot gallery. Renders the app's key screens in light + dark
/// and attaches them to the test result so a remote (Linux / web) session with no
/// Mac can eyeball the real rendered UI from the CI run's artifacts. Driven by the
/// `Screenshots` workflow, which pulls the attachments out of the `.xcresult` with
/// `xcparse`.
///
/// Reuses the app's deterministic seed launch-args (`-seedDemoMemos` /
/// `-seedDemoNames` / `-skipOnboarding`) and the same stable identifiers the
/// functional UITests use (`memo-row-0`, tab bar `Notes`/`Settings`, `models-link`,
/// `transcript-editor`). Navigation is SOFT on purpose — a screen that can't be
/// reached is skipped, never asserted — because this is a capture pass, not a
/// pass/fail gate. Each screen group runs from its own fresh launch so one missing
/// screen can't starve the rest.
final class ScreenshotGalleryUITests: XCTestCase {

    override func setUpWithError() throws {
        // Capture as much as possible: keep going past any single missing element.
        continueAfterFailure = true
    }

    func testGalleryLight() throws { captureGallery(theme: "light") }
    func testGalleryDark()  throws { captureGallery(theme: "dark") }

    // MARK: - Gallery

    private func captureGallery(theme: String) {
        // Group A — memos list + memo detail (detail is one push off the list).
        do {
            let app = launch(theme: theme)
            let row0 = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
            if row0.waitForExistence(timeout: 15) {
                snap(app, "1-memos", theme)
                row0.tap()
                if app.textViews["transcript-editor"].waitForExistence(timeout: 8) {
                    snap(app, "2-memo-detail", theme)
                }
            }
            app.terminate()
        }

        // Group B — Settings + Models (models is one push off the Settings tab).
        do {
            let app = launch(theme: theme)
            let settings = app.tabBars.buttons["Settings"]
            if settings.waitForExistence(timeout: 10) {
                settings.tap()
                _ = app.navigationBars.firstMatch.waitForExistence(timeout: 5)
                snap(app, "3-settings", theme)

                // The Models row sits below the fold in the Settings form, and SwiftUI
                // instantiates list rows lazily — so `models-link` isn't in the tree
                // until it's scrolled into view (the functional SettingsUITests swipe up
                // for the same reason). Reveal it with a bounded scroll, then push in.
                let models = app.descendants(matching: .any).matching(identifier: "models-link").firstMatch
                var scrolls = 0
                while !models.waitForExistence(timeout: 2) && scrolls < 3 {
                    app.swipeUp()
                    scrolls += 1
                }
                if models.exists {
                    models.tap()
                    if app.staticTexts["Transcription"].waitForExistence(timeout: 8) {
                        snap(app, "4-models", theme)
                    }
                }
            }
            app.terminate()
        }
    }

    // MARK: - Helpers

    private func launch(theme: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedDemoMemos", "-seedDemoNames",
                               "-skipOnboarding", "-appTheme", theme]
        app.launch()
        dismissLingeringSpringboardDialog()
        return app
    }

    private func snap(_ app: XCUIApplication, _ name: String, _ theme: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "\(name)-\(theme)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// A leftover system "Open in <app>?" URL-scheme dialog can linger from a prior
    /// deep-link and steal the first tap. Harmless no-op when absent.
    private func dismissLingeringSpringboardDialog() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let cancel = springboard.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 2) { cancel.tap() }
    }
}
