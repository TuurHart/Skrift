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

    /// Tap a speaker → the assign sheet → type a NEW name → relabels all that speaker's turns.
    func testAssignSpeakerNewNameRelabelsTurns() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedConversationMemo", "-skipOnboarding", "-resetNames", "-appTheme", "dark"]
        app.launch()
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()

        let tag = app.buttons.matching(identifier: "tag-speaker-Speaker 2").firstMatch
        XCTAssertTrue(tag.waitForExistence(timeout: 5)); tag.tap()
        let field = app.textFields["assign-new-name-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Roksana")
        app.buttons["assign-new-name-button"].tap()

        XCTAssertTrue(app.staticTexts["Roksana"].waitForExistence(timeout: 5), "renamed speaker didn't appear")
        XCTAssertFalse(app.buttons["tag-speaker-Speaker 2"].exists, "old Speaker 2 label still present after rename")
    }

    /// Tap a mis-split line → "Merge into" another speaker → ONLY that line folds in
    /// (per-line). The seeded memo has two Speaker 2 turns; merging the first leaves the
    /// second, so it stays a 2-speaker conversation (the bug was merging ALL the turns).
    func testMergeSpeakerIntoAnother() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedConversationMemo", "-skipOnboarding", "-resetNames", "-appTheme", "dark"]
        app.launch()
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()

        let tag = app.buttons.matching(identifier: "tag-speaker-Speaker 2").firstMatch
        XCTAssertTrue(tag.waitForExistence(timeout: 10)); tag.tap()
        Thread.sleep(forTimeInterval: 1.0)   // let the .medium-detent sheet settle (XCUITest won't re-poll its content mid-present)
        let merge = app.buttons["merge-into-Tiuri Hartog"]
        XCTAssertTrue(merge.waitForExistence(timeout: 5)); merge.tap()

        Thread.sleep(forTimeInterval: 1.5)   // sheet dismiss + re-render
        XCTAssertTrue(app.buttons.matching(identifier: "tag-speaker-Tiuri Hartog").firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(identifier: "tag-speaker-Speaker 2").firstMatch.exists,
                      "the OTHER Speaker 2 line must remain — merge is per-line, not whole-speaker")
    }

    /// Tap a speaker → pick an existing PERSON from the Names DB (typo-free, links the voiceprint).
    func testAssignSpeakerToExistingPerson() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedConversationMemo", "-seedDemoNames", "-skipOnboarding", "-appTheme", "dark"]
        app.launch()
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()

        let tag = app.buttons.matching(identifier: "tag-speaker-Speaker 2").firstMatch
        XCTAssertTrue(tag.waitForExistence(timeout: 10)); tag.tap()
        let pick = app.buttons["assign-person-Jane Doe"]   // -seedDemoNames seeds Jane Doe
        XCTAssertTrue(pick.waitForExistence(timeout: 5)); pick.tap()

        XCTAssertTrue(app.staticTexts["Jane Doe"].waitForExistence(timeout: 5), "picked person didn't become the label")
        XCTAssertFalse(app.buttons["tag-speaker-Speaker 2"].exists)
    }

    /// Recording with conversation mode ON diarizes (SeededDiarizer in sim) + fuses →
    /// the saved memo renders speaker turns.
    func testRecordingInConversationModeSplitsSpeakers() throws {
        let app = XCUIApplication()
        let seed = (1...20).map { "word\($0)" }.joined(separator: " ")   // ~6s → spans 2 seeded speakers
        // -resetNames: no enrolled voices, so the seeded diarizer leaves both speakers
        // un-named ("Speaker N") rather than auto-matching a leftover person.
        app.launchArguments = ["-seedTranscript", seed, "-conversationDefault", "1", "-resetNames", "-appTheme", "dark"]
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

    /// The RECOGNIZED half of name-once→recognized: an already-enrolled person is
    /// auto-labeled when they appear in a NEW conversation recording. `-seedDemoNames`
    /// seeds "Jane Doe" WITH a voiceprint (+ un-enrolled Bob); the seeded diarizer mocks
    /// the embedding match by labeling a slot with the enrolled person (the real wespeaker
    /// cosine match is device-tested — the sim has no ANE + mock audio has no voice).
    func testEnrolledPersonAutoLabeledOnNewRecording() throws {
        let app = XCUIApplication()
        let seed = (1...20).map { "word\($0)" }.joined(separator: " ")
        app.launchArguments = ["-seedTranscript", seed, "-conversationDefault", "1", "-seedDemoNames", "-appTheme", "dark"]
        app.launch()
        app.buttons["new-recording-button"].tap()
        let record = app.buttons["record-button"]
        XCTAssertTrue(record.waitForExistence(timeout: 5)); record.tap()
        XCTAssertTrue(app.buttons["pause-button"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.6)
        record.tap()   // stop → save → diarize → detail

        // Slot 0 auto-labeled "Jane Doe" (a named turn → "edit" affordance); the second,
        // un-enrolled speaker stays "Speaker 2".
        XCTAssertTrue(app.buttons["tag-speaker-Jane Doe"].waitForExistence(timeout: 10),
                      "enrolled person wasn't auto-labeled on a new recording")
        XCTAssertTrue(app.buttons["tag-speaker-Speaker 2"].exists, "second (un-enrolled) speaker should stay Speaker 2")
        XCTAssertFalse(app.buttons["tag-speaker-Speaker 1"].exists, "slot 0 should be named, not Speaker 1")
    }
}
