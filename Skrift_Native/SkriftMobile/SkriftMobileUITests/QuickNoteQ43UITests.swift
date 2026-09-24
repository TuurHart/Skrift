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

        // "quick-note-view" (the screen's own accessibilityIdentifier) is a
        // container with no AX node of its own — SwiftUI leaked THAT identifier
        // onto every descendant AX element when it was present, clobbering
        // "quick-note-title"/"quick-note-body" too, so the screen is confirmed
        // via its back button instead (Q43 fix: dropped the container identifier).
        let back = app.buttons["quick-note-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 10), "the quick-note screen did not open")
        // The wrapper's own `.accessibilityIdentifier("quick-note-body")` (SwiftUI)
        // wins over the UIKit-level `tv.accessibilityIdentifier` set inside
        // `makeUIView` — the AX tree only ever shows the outer one.
        let body = app.descendants(matching: .any).matching(identifier: "quick-note-body").firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 5), "the quick-note body text view is missing")

        // A fresh simulator's first-ever keyboard appearance shows Apple's
        // one-time "slide to type" tip over the keys — dismiss it so the
        // screenshot shows the real keyboard, like the mock.
        let continueTip = app.buttons["Continue"]
        if continueTip.waitForExistence(timeout: 2) { continueTip.tap() }

        capture(app, "phone-quick-note-empty")
    }
}
