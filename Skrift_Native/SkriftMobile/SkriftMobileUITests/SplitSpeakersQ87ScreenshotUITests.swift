import XCTest

/// Q87 visual check ONLY — screenshots for `plan/reads/split-q87/phone/`: the phone half of the
/// Split speakers mock (`SkriftDesktop/mocks/Q86-split-speakers.html`): the ⋯ sheet with
/// Flatten / "Split speakers…", the Flatten confirm, "How many speakers?" with Auto explained,
/// and the naming sheet's "Move just this line" wording. Seeded conversation memo, in-memory
/// store. Not a durable regression test.
final class SplitSpeakersQ87ScreenshotUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func snap(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.7)
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testPhoneSplitAndFlattenFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedConversationMemo", "-skipOnboarding", "-resetNames", "-appTheme", "dark"]
        app.launch()
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()

        // A split note: turns, "+ name" on the un-named speaker.
        let tag = app.buttons.matching(identifier: "tag-speaker-Speaker 2").firstMatch
        XCTAssertTrue(tag.waitForExistence(timeout: 8))
        snap(app, "1-split-note")

        // "Who is Speaker 2?" — the merge line now says "Move just this line…".
        tag.tap()
        XCTAssertTrue(app.staticTexts["Wrong split? Move just this line to another speaker."].waitForExistence(timeout: 5),
                      "the merge section must use the shared wording")
        snap(app, "2-assign-sheet")
        app.buttons["Cancel"].firstMatch.tap()

        // The ⋯ sheet on a split note: Flatten in its slot.
        app.buttons["detail-menu"].tap()
        let flatten = app.buttons["Flatten to monologue"]
        XCTAssertTrue(flatten.waitForExistence(timeout: 5), "a split note's ⋯ sheet must offer Flatten")
        snap(app, "3-menu-split-note")
        flatten.tap()

        // The confirm says what stays.
        XCTAssertTrue(app.alerts["Flatten to monologue?"].waitForExistence(timeout: 5))
        snap(app, "4-flatten-confirm")
        app.alerts["Flatten to monologue?"].buttons["Flatten"].tap()

        // Plain again; the sheet now says Split speakers… in words.
        XCTAssertTrue(tag.waitForNonExistence(timeout: 8), "the turns must be gone after Flatten")
        snap(app, "5-plain-again")
        app.buttons["detail-menu"].tap()
        let split = app.buttons["Split speakers…"]
        XCTAssertTrue(split.waitForExistence(timeout: 5), "an unsplit note's ⋯ sheet must say Split speakers…")
        snap(app, "6-menu-plain-note")
        split.tap()

        // "How many speakers?" with Auto explained + the edits warning.
        XCTAssertTrue(app.staticTexts["Auto finds the number itself. Pick one if you know it. Edits you made to this transcript are replaced."]
            .waitForExistence(timeout: 5))
        snap(app, "7-how-many-speakers")
    }
}
