import XCTest

/// Q451 visual check: a brand-new note and the same note reopened are one screen (title, grey
/// meta line, then `○○○ Not rated · Personal · + tag` on ONE row) and the tab bar never shows.
/// Screenshots land in `plan/reads/note-parity/` via `SKRIFT_SHOT_DIR` (pass it as
/// TEST_RUNNER_SKRIFT_SHOT_DIR), or the xcresult attachments.
final class NoteParityQ451ScreenshotUITests: XCTestCase {

    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.8)
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SKRIFT_SHOT_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    private var corpusPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test-fixtures/corpus").path
    }

    private func assertNoTabBar(_ app: XCUIApplication, _ when: String) {
        let bar = app.tabBars.firstMatch
        XCTAssertFalse(bar.exists && bar.isHittable, "the tab bar shows over the note \(when)")
    }

    func testNewNoteAndReopenedNoteMatch() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-corpus", corpusPath, "-destinationsOn", "-skipOnboarding"]
        app.launch()
        let newNote = app.buttons["ipad-new-note-button"]
        XCTAssertTrue(newNote.waitForExistence(timeout: 20), "the new-note button never appeared")
        newNote.tap()
        XCTAssertTrue(app.buttons["note-back-button"].waitForExistence(timeout: 10), "‹ Notes missing on the new note")
        let tip = app.buttons["Continue"]
        if tip.waitForExistence(timeout: 2) { tip.tap() }
        XCTAssertTrue(app.buttons["rating-pill"].waitForExistence(timeout: 5), "rating pill missing")
        capture(app, "1-new-note-empty")
        assertNoTabBar(app, "on a new note")

        let title = app.descendants(matching: .any).matching(identifier: "detail-title").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "the new note has no title field")
        title.tap()
        title.typeText("Test 2")
        let body = app.textViews["transcript-editor"]
        body.tap()
        body.typeText("A first line")
        capture(app, "2-new-note-typing")

        let done = app.buttons["accessory-done"]
        if done.waitForExistence(timeout: 3) { done.tap() }
        capture(app, "3-new-note-after-done")
        assertNoTabBar(app, "after Done")
        XCTAssertTrue(app.buttons["detail-menu"].waitForExistence(timeout: 3), "⋯ missing once the note exists")

        app.buttons["note-back-button"].tap()
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the new note is not listed")
        row.tap()
        XCTAssertTrue(app.buttons["note-back-button"].waitForExistence(timeout: 10))
        capture(app, "4-reopened-note")
        assertNoTabBar(app, "on the reopened note")
    }
}
