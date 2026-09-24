import XCTest

/// Q44 visual check ONLY — proves the tag-removal Undo toast (`TagUndoToastView`,
/// hoisted Q41) anchors above the player (keyboard down) / above the keyboard's
/// accessory bar (keyboard up), never mid-screen over note content (Q41 finding).
/// Launches on the SYNTHETIC corpus in an in-memory store (`-inMemoryStore -corpus
/// …`, C4) — never the live Dev store. Screenshots land in `plan/reads/tags-q44/`.
final class TagToastQ44UITests: XCTestCase {

    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Adds a tag, arms + removes it (raising the Undo toast), captures.
    /// `dismissKeyboard`: closing the tag field's own keyboard hands focus back to
    /// the body editor (Q41 finding — the fixture opens with it focused), so the
    /// keyboard-DOWN case must also tap the body editor's own accessory "Done"
    /// (`accessory-done`, `NoteAccessoryBar`) before the remove.
    private func addAndRemoveTag(_ app: XCUIApplication, tag: String, shot: String, dismissKeyboard: Bool) {
        let addTag = app.buttons["add-tag-button"]
        XCTAssertTrue(addTag.waitForExistence(timeout: 20), "the + tag control is missing")
        addTag.tap()

        let field = app.textFields["tag-input"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the inline tag field did not open")
        field.tap()
        field.typeText("\(tag)\n")   // commits, field stays open+empty (D139)
        if field.exists { field.tap(); field.typeText("\n") }   // Return on empty field closes it

        if dismissKeyboard {
            let done = app.buttons["accessory-done"]
            if done.waitForExistence(timeout: 3) { done.tap() }
            Thread.sleep(forTimeInterval: 0.4)
        }

        let chip = app.staticTexts["tag-chip-\(tag)"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "#\(tag) chip did not land")
        chip.tap()   // arms it
        chip.tap()   // removes → floating Undo toast
        capture(app, shot)
    }

    func testTagToastAnchorsKeyboardDownAndUp() {
        let app = XCUIApplication()
        let corpus = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SkriftMobileUITests
            .deletingLastPathComponent()   // SkriftMobile
            .deletingLastPathComponent()   // Skrift_Native
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("test-fixtures/corpus").path
        app.launchArguments = ["-inMemoryStore", "-corpus", corpus, "-selectFirstMemo"]
        app.launch()

        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the first memo row never appeared — did the corpus seed?")
        row.tap()

        // KEYBOARD UP: the body editor picks up focus (device-observed default on
        // this fixture, Q41 finding) and the tag field's own keyboard stays live
        // through the remove — capture the toast while it's up.
        addAndRemoveTag(app, tag: "harbor", shot: "phone-toast-keyboard-up", dismissKeyboard: false)

        // KEYBOARD DOWN: tap the body editor's own accessory "Done" before removing.
        addAndRemoveTag(app, tag: "dock", shot: "phone-toast-keyboard-down", dismissKeyboard: true)
    }
}
