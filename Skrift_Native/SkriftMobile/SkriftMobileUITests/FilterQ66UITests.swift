import XCTest

/// Q66 visual check — screenshots the notes list's chip row after Q66 (option A
/// of `mocks/Q49-one-filter.html`): four status chips, then Date + Unsynced,
/// the sort word pinned at the end, and the Date strip with a range live —
/// against the SYNTHETIC corpus in an in-memory store (`-inMemoryStore -corpus
/// …`, C4), never the live Dev store. Its job is the screenshots for
/// `plan/reads/filter-q66/`; the assertions only prove the controls exist and
/// that a tap steps the sort word.
final class FilterQ66UITests: XCTestCase {

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

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func testFilterRowAndDateStrip() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-corpus", corpusPath]
        app.launch()

        XCTAssertTrue(any(app, "memos-list").waitForExistence(timeout: 20),
                      "the notes list never appeared — did the corpus seed?")
        capture(app, "phone-chip-row")

        // The sort word is pinned at the row's end; one tap steps it.
        let sortWord = any(app, "sort-cycle-word")
        XCTAssertTrue(sortWord.waitForExistence(timeout: 5), "sort word missing")
        let before = sortWord.label
        sortWord.tap()
        XCTAssertNotEqual(sortWord.label, before, "the sort word did not step")
        capture(app, "phone-sort-stepped")

        // Date opens a strip under the row; arm From so a live range shows.
        let dateChip = any(app, "chip-date")
        XCTAssertTrue(dateChip.waitForExistence(timeout: 5), "Date chip missing")
        dateChip.tap()
        let from = any(app, "date-from")
        XCTAssertTrue(from.waitForExistence(timeout: 5), "Date strip's From pill missing")
        from.tap()
        capture(app, "phone-date-active")
    }
}
