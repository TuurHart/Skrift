import XCTest

/// Q88 visual check: the quick note wears the note screen's header — rating pill, the
/// orange fading line once the row exists, destination row under it. Screenshots land in
/// `plan/reads/pill-q88/` via `SKRIFT_SHOT_DIR` (pass it as TEST_RUNNER_SKRIFT_SHOT_DIR).
final class QuickNoteHeaderQ88UITests: XCTestCase {

    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.7)
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SKRIFT_SHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    private var corpusPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test-fixtures/corpus").path
    }

    func testQuickNoteHeaderPill() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-corpus", corpusPath, "-destinationsOn"]
        app.launch()
        let newNote = app.buttons["ipad-new-note-button"]
        XCTAssertTrue(newNote.waitForExistence(timeout: 20), "the new-note button never appeared")
        newNote.tap()
        XCTAssertTrue(app.buttons["quick-note-back"].waitForExistence(timeout: 10))
        let tip = app.buttons["Continue"]
        if tip.waitForExistence(timeout: 2) { tip.tap() }

        let pill = app.buttons["rating-pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "rating pill missing from the quick note")
        capture(app, "quicknote-1-rest")

        pill.tap()   // Not rated -> Passing (pre-memo, D91: still no row)
        capture(app, "quicknote-2-tap-passing")
        pill.tap()
        pill.tap()   // ... -> Important -> back to Not rated
        pill.tap()
        XCTAssertTrue(pill.label.contains("Not rated") || pill.label.contains("Importance"))

        let body = app.descendants(matching: .any).matching(identifier: "quick-note-body").firstMatch
        body.tap()
        body.typeText("a first line")
        capture(app, "quicknote-3-typed-unrated-line")
    }
}
