import XCTest

/// Visual check for the Liquid Glass player bar. The iPhone 17 sim runs iOS 26, so
/// `.glassEffect` renders here — we seed ONE long memo, scroll transcript/image
/// content under the bottom bar, and screenshot so the refraction can be eyeballed
/// (the bar is a `.safeAreaInset`, so scroll content is behind it in the same
/// backdrop — the fix for "glass shows nothing").
final class GlassUITests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testGlassRefractsScrollContent() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedLongMemo", "-skipOnboarding", "-appTheme", "dark"]
        app.launch()

        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.buttons["play-button"].waitForExistence(timeout: 5))

        // Scroll text into the bottom region so it sits behind the glass bar.
        app.swipeUp()
        snap("glass-dark-over-text")

        // Scroll further toward the image placeholder for a high-contrast refraction.
        app.swipeUp()
        app.swipeUp()
        snap("glass-dark-over-image")
    }
}
