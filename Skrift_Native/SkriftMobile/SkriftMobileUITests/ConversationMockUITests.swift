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

    /// Tapping a speaker → naming it relabels all that speaker's turns (assign + correct).
    func testTagSpeakerRenamesTurns() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedConversationMemo", "-skipOnboarding", "-appTheme", "dark"]
        app.launch()
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()

        // The speaker has multiple turns (so multiple identical tag buttons) — tap the first.
        let tag = app.buttons.matching(identifier: "tag-speaker-Speaker 2").firstMatch
        XCTAssertTrue(tag.waitForExistence(timeout: 5)); tag.tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Roksana")
        app.alerts.buttons["Set"].tap()

        XCTAssertTrue(app.staticTexts["Roksana"].waitForExistence(timeout: 5), "renamed speaker didn't appear")
        XCTAssertFalse(app.buttons["tag-speaker-Speaker 2"].exists, "old Speaker 2 label still present after rename")
    }

    /// Recording with conversation mode ON diarizes (SeededDiarizer in sim) + fuses →
    /// the saved memo renders speaker turns.
    func testRecordingInConversationModeSplitsSpeakers() throws {
        let app = XCUIApplication()
        let seed = (1...20).map { "word\($0)" }.joined(separator: " ")   // ~6s → spans 2 seeded speakers
        app.launchArguments = ["-seedTranscript", seed, "-conversationDefault", "1", "-appTheme", "dark"]
        app.launch()
        app.buttons["new-recording-button"].tap()
        let record = app.buttons["record-button"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()
        XCTAssertTrue(app.buttons["pause-button"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.6)
        record.tap()   // stop → save → diarize → detail

        // Speaker turns appear once diarization (mock) finishes.
        XCTAssertTrue(app.buttons["tag-speaker-Speaker 1"].waitForExistence(timeout: 10),
                      "conversation-mode recording didn't render speaker turns")
        XCTAssertTrue(app.buttons["tag-speaker-Speaker 2"].exists, "second speaker turn missing")
    }
}
