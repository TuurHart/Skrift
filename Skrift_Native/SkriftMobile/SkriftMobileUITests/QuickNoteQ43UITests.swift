import XCTest

/// Q43 visual check ONLY — screenshots the quick-note screen against the signed mock
/// `mocks/quick-note.html`. Launches on the SYNTHETIC corpus in an in-memory store
/// (`-inMemoryStore -corpus …`, C4) — never the live Dev store. Not a durable
/// regression test; its job is the screenshot for `plan/reads/quicknote-q43/`.
final class QuickNoteQ43UITests: XCTestCase {

    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // Derived from `#filePath` (compiled inside THIS worktree), not hardcoded — a
    // hardcoded sibling worktree path dies once that worktree is cleaned up (Q36 lesson).
    private var corpusPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SkriftMobileUITests
            .deletingLastPathComponent()   // SkriftMobile
            .deletingLastPathComponent()   // Skrift_Native
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("test-fixtures/corpus").path
    }

    /// Tap the app's own ✎ (verbRow, "ipad-new-note-button" — it's on the phone row
    /// too) and confirm the quick-note screen opens keyboard-up, cursor in the body.
    func testQuickNoteOpensEmptyKeyboardUp() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-corpus", corpusPath]
        app.launch()

        let newNote = app.buttons["ipad-new-note-button"]
        XCTAssertTrue(newNote.waitForExistence(timeout: 20), "the ✎ new-note button never appeared")
        newNote.tap()

        let screen = app.descendants(matching: .any).matching(identifier: "quick-note-view").firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 10), "the quick-note screen did not open")
        let body = app.descendants(matching: .any).matching(identifier: "quick-note-body-textview").firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 5), "the quick-note body text view is missing")
        capture(app, "phone-quick-note-empty")
    }
}
