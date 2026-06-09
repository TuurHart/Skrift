import XCTest

/// Phase 7.3: memo detail. Seeds demo memos, opens one, and checks the transcript
/// + playback controls render, tags can be added, and delete works. Swipe paging
/// + real playback are exercised on device; here the seeded memos have no audio
/// file so the player loads disabled (still present).
final class MemoDetailUITests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedDemoMemos"]
        app.launch()
        return app
    }

    func testOpenMemoShowsTranscriptAndPlayer() throws {
        let app = launch()
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        // Transcript is an always-editable text view now (its text is the value).
        let editor = app.textViews["transcript-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "transcript editor didn't render in detail")
        XCTAssertTrue((editor.value as? String ?? "").contains("First seeded memo about the harbor at dawn."),
                      "transcript text missing")
        XCTAssertTrue(app.buttons["play-button"].exists, "play control missing")
        XCTAssertTrue(app.buttons["speed-button"].exists, "speed control missing")
        XCTAssertTrue(app.buttons["skip-back-button"].exists)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "memo-detail"; shot.lifetime = .keepAlways; add(shot)
    }

    func testSwipeBetweenMemos() throws {
        let app = launch()
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        let firstEditor = app.textViews["transcript-editor"]
        XCTAssertTrue(firstEditor.waitForExistence(timeout: 5))
        XCTAssertTrue((firstEditor.value as? String ?? "").contains("First seeded memo"))
        app.swipeLeft()
        // Off-screen pages are accessibilityHidden, so the visible editor now holds memo 2.
        let secondShown = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "Second seeded memo")).firstMatch
        XCTAssertTrue(secondShown.waitForExistence(timeout: 5), "swipe didn't page to the next memo")
    }

    /// Opening a non-first memo must land ON that memo, not page 0. This guards the
    /// paging ScrollView's initial scroll (the `.scrollPosition(id:)` initial value
    /// isn't reliably honoured on first layout — a ScrollViewReader does the jump).
    /// Asserts *hittability* (on-screen), not mere existence: the LazyHStack realises
    /// adjacent pages, but only the visible page's text is hittable.
    func testOpenNonFirstMemoLandsOnIt() throws {
        let app = launch()
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-1").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        // Off-screen pages are accessibilityHidden, so only the landed page's editor is
        // in the tree — opening row-1 must show memo 2 and NOT memo 1.
        let second = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "Second seeded memo")).firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 5), "opening memo-row-1 didn't land on the second memo")
        XCTAssertFalse(app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "First seeded memo")).firstMatch.exists,
                       "page 0 is on-screen — detail opened on the wrong page")
    }

    func testAddTagInDetail() throws {
        let app = launch()
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        let addTag = app.buttons["add-tag-button"]
        XCTAssertTrue(addTag.waitForExistence(timeout: 5))
        addTag.tap()

        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("harbor")
        app.alerts.buttons["Add"].tap()

        // The applied tag chip is a tappable (remove) button, so query buttons.
        XCTAssertTrue(app.buttons["#harbor"].waitForExistence(timeout: 5),
                      "added tag chip didn't appear")
    }

    func testEditTranscriptInDetail() throws {
        let app = launch()
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        // The transcript is always editable in place — no Edit button.
        let editor = app.textViews["transcript-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "transcript should be editable in place")
        editor.tap()
        editor.typeText(" Edited on phone.")
        XCTAssertTrue((editor.value as? String ?? "").contains("Edited on phone."),
                      "typed text didn't land in the always-editable transcript")
    }

    func testDeleteMemoFromDetail() throws {
        let app = launch()
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        let editor = app.textViews["transcript-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String ?? "").contains("First seeded memo"))

        app.buttons["detail-menu"].tap()
        app.buttons["Delete"].tap()

        // Selection moves to the next memo; the deleted one's transcript is gone.
        let secondShown = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "Second seeded memo")).firstMatch
        XCTAssertTrue(secondShown.waitForExistence(timeout: 5), "detail didn't move to the next memo after delete")
        XCTAssertFalse(app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "First seeded memo")).firstMatch.exists,
                       "deleted memo's transcript still present")
    }
}
