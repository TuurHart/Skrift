import XCTest

/// Q544 (signed mock Q542, "One bar at the bottom"): while typing, the bar above the keyboard holds
/// Aa · checklist · photo · note link · undo · redo · Done, and the top bar shows only ‹ Notes and ⋯.
/// The reading state keeps + and ⋯. The note is opened by TAPPING it in the list (a real push,
/// neighbours mounted), the path Q540 showed behaves differently from launching straight into it.
/// Screenshots land in `SKRIFT_SHOT_DIR` (pass `TEST_RUNNER_SKRIFT_SHOT_DIR`), or the xcresult.
final class BottomBarQ544UITests: XCTestCase {

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

    private func button(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private let barIDs = ["accessory-format", "accessory-checklist", "accessory-photo", "accessory-link",
                          "accessory-undo", "accessory-redo", "accessory-done"]

    private func openNoteFromList() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedDemoMemos", "-seedBareNote", "-skipOnboarding"]
        app.launch()
        let row = button(app, "memo-row-1")
        XCTAssertTrue(row.waitForExistence(timeout: 20), "memo-row-1 never appeared")
        row.tap()
        XCTAssertTrue(app.buttons["note-back-button"].waitForExistence(timeout: 10), "the note was not pushed from the list")
        return app
    }

    func testTypingShowsSevenInTheBarAndOnlyNotesAndMoreOnTop() {
        let app = openNoteFromList()
        let editor = app.textViews["transcript-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 20), "editor missing")

        // Reading: + and ⋯ up top, no keyboard bar.
        XCTAssertTrue(button(app, "add-recording-button").waitForExistence(timeout: 5), "reading state lost the + button")
        XCTAssertTrue(button(app, "detail-menu").exists, "reading state lost ⋯")
        XCTAssertFalse(button(app, "accessory-done").exists, "Done showed while only reading")
        capture(app, "q544-1-reading")

        // Typing: tap into the body.
        editor.tap()
        XCTAssertTrue(button(app, "accessory-done").waitForExistence(timeout: 5), "Done missing from the bar")
        XCTAssertTrue(app.keyboards.count > 0, "keyboard not up")
        let screen = app.windows.firstMatch.frame
        for id in barIDs {
            let b = button(app, id)
            XCTAssertTrue(b.exists, "\(id) missing from the bar above the keyboard")
            XCTAssertGreaterThan(b.frame.minY, screen.height * 0.5, "\(id) is not down by the keyboard")
            XCTAssertGreaterThanOrEqual(b.frame.width, 43.5, "\(id) is narrower than 44 pt")
            XCTAssertGreaterThanOrEqual(b.frame.height, 53, "\(id) does not use the bar's full 54 pt")
            XCTAssertFalse(app.navigationBars.buttons[id].exists, "\(id) is still in the top bar")
        }
        // Top bar: only Notes and ⋯.
        XCTAssertTrue(app.buttons["note-back-button"].exists, "‹ Notes missing while typing")
        XCTAssertTrue(button(app, "detail-menu").exists, "⋯ missing while typing")
        XCTAssertFalse(button(app, "add-recording-button").exists, "+ shows while typing")
        let topButtons = app.navigationBars.buttons.allElementsBoundByIndex.filter { $0.frame.minY < screen.height * 0.25 }
        XCTAssertEqual(topButtons.count, 2, "top bar should hold exactly Notes and ⋯, found \(topButtons.map { $0.identifier })")
        capture(app, "q544-2-typing-bar")

        // Done from the bar puts the keyboard away and brings + back.
        button(app, "accessory-done").tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: button(app, "accessory-done"))
        wait(for: [gone], timeout: 5)
        XCTAssertTrue(button(app, "add-recording-button").waitForExistence(timeout: 5), "+ did not return after Done")
        capture(app, "q544-3-after-done")
    }

    func testUndoRedoAndDoneWorkFromTheBar() {
        let app = openNoteFromList()
        let editor = app.textViews["transcript-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 20), "editor missing")
        editor.tap()
        XCTAssertTrue(button(app, "accessory-undo").waitForExistence(timeout: 5), "bar missing")
        let before = (editor.value as? String) ?? ""
        XCTAssertFalse(button(app, "accessory-undo").isEnabled, "undo should dim before any edit")
        XCTAssertFalse(button(app, "accessory-redo").isEnabled, "redo should dim before any undo")

        app.typeText(" qzx")
        Thread.sleep(forTimeInterval: 0.6)
        let typed = (editor.value as? String) ?? ""
        XCTAssertTrue(typed.contains("qzx"), "typing did not land: \(typed)")
        XCTAssertTrue(button(app, "accessory-undo").isEnabled, "undo should light after typing")

        button(app, "accessory-undo").tap()
        Thread.sleep(forTimeInterval: 0.6)
        let undone = (editor.value as? String) ?? ""
        XCTAssertFalse(undone.contains("qzx"), "undo from the bar did not take the typing back: \(undone)")
        // The system groups typed characters its own way, so one undo may take back only part of
        // what was typed; it must still shorten the text, never lengthen or reach before it.
        XCTAssertLessThan(undone.count, typed.count, "undo did not shorten the text")
        XCTAssertGreaterThanOrEqual(undone.count, before.count, "undo reached back before the typing")
        XCTAssertTrue(button(app, "accessory-redo").isEnabled, "redo should light after an undo")

        button(app, "accessory-redo").tap()
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual((editor.value as? String) ?? "", typed, "redo from the bar did not bring the typing back")

        button(app, "accessory-done").tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: button(app, "accessory-done"))
        wait(for: [gone], timeout: 5)
        XCTAssertEqual(app.keyboards.count, 0, "keyboard still up after Done")
    }
}
