import XCTest

/// Screenshots the conversation-mode design mock (bold-name speaker turns + per-speaker
/// color + tag-as-you-go) for design review, in dark + light.
final class ConversationMockUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    func testConversationMock() throws {
        for theme in ["dark", "light"] {
            let app = XCUIApplication()
            app.launchArguments = ["-conversationMock", "-appTheme", theme]
            app.launch()
            Thread.sleep(forTimeInterval: 0.6)
            snap("conversation-mock-\(theme)")
            app.terminate()
        }
    }

    /// The REAL detail view rendering a seeded `**Name:**` conversation transcript via
    /// SpeakerTurnsView (not the static mock).
    func testRealConversationMemoRendersTurns() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedConversationMemo", "-skipOnboarding", "-appTheme", "dark"]
        app.launch()
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        // A named speaker renders as bold text; an un-named one offers "+ name".
        XCTAssertTrue(app.staticTexts["Tiuri Hartog"].waitForExistence(timeout: 5), "named speaker turn didn't render")
        XCTAssertTrue(app.buttons["tag-speaker-Speaker 2"].exists, "un-named speaker's tag affordance missing")
        snap("conversation-real-detail")
    }
}
