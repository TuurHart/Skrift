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

        XCTAssertTrue(app.staticTexts["First seeded memo about the harbor at dawn."].waitForExistence(timeout: 5),
                      "transcript didn't render in detail")
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

        XCTAssertTrue(app.staticTexts["First seeded memo about the harbor at dawn."].waitForExistence(timeout: 5))
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["Second seeded memo, a quick reminder to call the plumber."].waitForExistence(timeout: 5),
                      "swipe didn't page to the next memo")
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

        let edit = app.buttons["edit-transcript-button"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "Edit button missing")
        edit.tap()

        let editor = app.textViews["transcript-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "transcript editor didn't appear")
        editor.tap()
        editor.typeText(" Edited on phone.")
        app.buttons["edit-transcript-button"].tap()   // now labelled "Done"

        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Edited on phone."))
                        .firstMatch.waitForExistence(timeout: 5),
                      "hand-edited transcript didn't render")
    }

    func testDeleteMemoFromDetail() throws {
        let app = launch()
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        XCTAssertTrue(app.staticTexts["First seeded memo about the harbor at dawn."].waitForExistence(timeout: 5))

        app.buttons["detail-menu"].tap()
        app.buttons["Delete"].tap()

        // Selection moves to the next memo; the deleted one's transcript is gone.
        XCTAssertTrue(app.staticTexts["Second seeded memo, a quick reminder to call the plumber."].waitForExistence(timeout: 5),
                      "detail didn't move to the next memo after delete")
        XCTAssertFalse(app.staticTexts["First seeded memo about the harbor at dawn."].exists,
                       "deleted memo's transcript still present")
    }
}
