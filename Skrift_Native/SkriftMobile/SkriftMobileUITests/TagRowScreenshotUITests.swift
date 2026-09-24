import XCTest

/// Q36 visual check ONLY — screenshots the tag row against the D139 signed mock
/// `mocks/tag-ui-revamp.html`. Launches on the SYNTHETIC corpus in an in-memory store
/// (`-inMemoryStore -corpus …`, C4) — never the live Dev store. Not a durable regression
/// test (no assertions beyond "the control exists"); its job is the screenshots for
/// `plan/reads/tags-q36/`.
final class TagRowScreenshotUITests: XCTestCase {

    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testTagRowStates() {
        let app = XCUIApplication()
        // Path to the synthetic corpus (C4) — never the live Dev store. Derived from
        // `#filePath` (compiled inside THIS worktree) rather than hardcoded, since a
        // hardcoded sibling worktree path dies the moment that worktree is cleaned up
        // (Q36 left one pointing at a since-removed worktree).
        let corpus = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SkriftMobileUITests
            .deletingLastPathComponent()   // SkriftMobile
            .deletingLastPathComponent()   // Skrift_Native
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("test-fixtures/corpus").path
        app.launchArguments = ["-inMemoryStore", "-corpus", corpus, "-selectFirstMemo"]
        app.launch()

        // Phone is a NavigationStack (unlike the iPad split view, `-selectFirstMemo`
        // doesn't auto-open a detail there) — tap the first row to land on it.
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the first memo row never appeared — did the corpus seed?")
        row.tap()

        // EXACT identifier (no suffix) — the pager keeps an off-screen neighbour page
        // mounted with an "-offscreen" suffixed copy of every tag control (see
        // TagEditorRow's `idSuffix` doc); BEGINSWITH would match either one.
        let addTag = app.buttons["add-tag-button"]
        XCTAssertTrue(addTag.waitForExistence(timeout: 20), "the + tag control is missing")
        addTag.tap()

        let field = app.textFields["tag-input"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the inline tag field did not open")
        field.tap()
        field.typeText("harbor\n")   // commits, field stays open+empty (D139: Return keeps it open)
        // The Return keystroke above can drop simulator keyboard focus before SwiftUI's
        // own re-focus lands — re-tap before the second (closing) Return.
        if field.exists { field.tap(); field.typeText("\n") }   // Return on an empty field closes it

        // The chip is an `.onTapGesture` HStack, not a `Button` — XCUITest exposes it
        // as a StaticText-with-tap, not a Button (confirmed via app.debugDescription).
        let chip = app.staticTexts["tag-chip-harbor"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "#harbor chip did not land")
        capture(app, "phone-header-with-tags")

        chip.tap()   // arms it (phone: tap-arms-then-removes)
        capture(app, "phone-armed-remove")

        chip.tap()   // second tap removes → floating Undo toast
        capture(app, "phone-undo-toast")
    }
}
