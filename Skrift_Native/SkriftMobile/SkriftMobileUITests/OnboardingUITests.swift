import XCTest

/// Phase 7.7: first-run onboarding. `-forceOnboarding` shows it (other tests pass
/// `-inMemoryStore` and auto-skip). Permission grants + the model download are
/// device-owed — the test just checks the screen renders and "Get started" lands
/// on Memos.
final class OnboardingUITests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    func testOnboardingGetStartedLandsOnMemos() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-forceOnboarding"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Welcome to Skrift"].waitForExistence(timeout: 10),
                      "onboarding didn't show")
        XCTAssertTrue(app.staticTexts["Microphone & Camera"].exists)
        XCTAssertTrue(app.staticTexts["Transcription model"].exists)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "onboarding"; shot.lifetime = .keepAlways; add(shot)

        let getStarted = app.buttons["get-started-button"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5))
        getStarted.tap()

        XCTAssertTrue(
            app.navigationBars["Notes"].waitForExistence(timeout: 10)
                || app.staticTexts["Notes"].waitForExistence(timeout: 5),
            "didn't land on Memos after Get started"
        )
    }
}
