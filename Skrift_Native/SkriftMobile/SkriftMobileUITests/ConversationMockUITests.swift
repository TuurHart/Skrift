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
}
