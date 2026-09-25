import XCTest

/// Q47 visual check ONLY — screenshots the full-note-screen quick note (D145:
/// date/tags/importance visible from the moment it opens, not "just a text
/// field"). Launches on the SYNTHETIC corpus in an in-memory store
/// (`-inMemoryStore -corpus …`, C4) — never the live Dev store. Not a durable
/// regression test; its job is the screenshot for `plan/reads/quicknote-q47/`.
final class QuickNoteQ47UITests: XCTestCase {

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

    /// The ✎ tap → the full note screen, keyboard up, with the date chip,
    /// the tag row, and the importance circles all visible before any word
    /// is typed — the D145 gap ("just a text field seems strange").
    func testQuickNoteShowsFullChromeBeforeTyping() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-corpus", corpusPath]
        app.launch()

        let newNote = app.buttons["ipad-new-note-button"]
        XCTAssertTrue(newNote.waitForExistence(timeout: 20), "the ✎ new-note button never appeared")
        newNote.tap()

        let back = app.buttons["quick-note-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 10), "the quick-note screen did not open")

        let dateChip = app.descendants(matching: .any).matching(identifier: "quick-note-date").firstMatch
        XCTAssertTrue(dateChip.waitForExistence(timeout: 5), "the date chip is missing")

        let continueTip = app.buttons["Continue"]
        if continueTip.waitForExistence(timeout: 2) { continueTip.tap() }

        capture(app, "phone-quick-note-full-chrome-empty")

        // Type a line so the Memo exists, then confirm the chrome carries
        // straight through (no reset, no flicker back to "just a text field").
        let body = app.descendants(matching: .any).matching(identifier: "quick-note-body").firstMatch
        if body.waitForExistence(timeout: 5) { body.tap(); body.typeText("Tram 28 idea") }

        capture(app, "phone-quick-note-full-chrome-typed")
    }
}
