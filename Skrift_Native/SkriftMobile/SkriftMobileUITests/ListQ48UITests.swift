import XCTest

/// Q48 visual check ONLY — screenshots the notes list's verb row (Import ·
/// Record · ✎, now a11y-floor-tall) and the filter chip bar before/after a
/// chip switch, against the SYNTHETIC corpus in an in-memory store
/// (`-inMemoryStore -corpus …`, C4) — never the live Dev store. Not a durable
/// regression test (no assertions beyond "the control exists"); its job is
/// the screenshots for `plan/reads/list-q48/`.
final class ListQ48UITests: XCTestCase {

    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private var corpusPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SkriftMobileUITests
            .deletingLastPathComponent()   // SkriftMobile
            .deletingLastPathComponent()   // Skrift_Native
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("test-fixtures/corpus").path
    }

    func testListChipsAndVerbRow() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-corpus", corpusPath]
        app.launch()

        let list = app.descendants(matching: .any).matching(identifier: "memos-list").firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 20), "the notes list never appeared — did the corpus seed?")
        capture(app, "phone-all-chip")

        // Switch to each chip in turn — one consistent, quick highlight move,
        // no per-section fly-in (Q48/D145: was different per chip).
        for chip in ["Needs Work", "Done", "Unrated", "All"] {
            let button = app.descendants(matching: .any).matching(identifier: "ipad-chip-\(chip)").firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), "chip \(chip) is missing")
            button.tap()
            capture(app, "phone-chip-\(chip.replacingOccurrences(of: " ", with: "-"))")
        }

        // The taller verb row (44pt floor) — captured on its own for a close crop.
        let recordButton = app.buttons["ipad-record-button"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "Record button missing")
        let importButton = app.descendants(matching: .any).matching(identifier: "ipad-import-button").firstMatch
        let newNoteButton = app.buttons["ipad-new-note-button"]
        // Frame heights land in the test log — proof the 44pt floor actually
        // took, not just "looks bigger" from the screenshot alone.
        print("Q48 verb-row frames: import=\(importButton.frame) record=\(recordButton.frame) newNote=\(newNoteButton.frame)")
        XCTAssertGreaterThanOrEqual(recordButton.frame.height, 44, "Record button under the 44pt tap-target floor")
        XCTAssertGreaterThanOrEqual(newNoteButton.frame.height, 44, "New-note button under the 44pt tap-target floor")
        capture(app, "phone-verb-row")
    }
}
