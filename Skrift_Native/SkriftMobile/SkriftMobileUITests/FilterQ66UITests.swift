import XCTest

/// Q66 visual check ONLY — screenshots the notes list's chip row after Q66
/// (option A of `mocks/Q49-one-filter.html`): the four status chips, then
/// Date + Unsynced, then the sort word, and the Date chip's own sheet with a
/// range live — against the SYNTHETIC corpus in an in-memory store
/// (`-inMemoryStore -corpus …`, C4), never the live Dev store. Not a durable
/// regression test (no assertions beyond "the control exists"); its job is
/// the screenshots for `plan/reads/filter-q66/`.
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

    func testFilterRowAndDateChip() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-corpus", corpusPath]
        app.launch()

        let list = app.descendants(matching: .any).matching(identifier: "memos-list").firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 20), "the notes list never appeared — did the corpus seed?")
        capture(app, "phone-chip-row")

        // Date/Unsynced/the sort word sit past the right edge on a 390pt
        // phone (the mock's own admission) — swipe the row to reach them. A
        // raw coordinate drag at the chip row's height (SwiftUI's horizontal
        // ScrollView doesn't surface its own queryable AX element here).
        let rowY = 0.25
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: rowY))
            .press(forDuration: 0.05,
                    thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: rowY)))

        // The sort word steps to the next order on tap.
        let sortWord = app.descendants(matching: .any).matching(identifier: "sort-cycle-word").firstMatch
        XCTAssertTrue(sortWord.waitForExistence(timeout: 5), "sort word missing")
        sortWord.tap()
        capture(app, "phone-sort-stepped")

        // The Date chip opens its own sheet — arm a From date so a live range
        // shows on the chip once dismissed.
        let dateChip = app.descendants(matching: .any).matching(identifier: "chip-date").firstMatch
        XCTAssertTrue(dateChip.waitForExistence(timeout: 5), "Date chip missing")
        dateChip.tap()
        let fromToggle = app.switches.matching(NSPredicate(format: "label CONTAINS 'From'")).firstMatch
        XCTAssertTrue(fromToggle.waitForExistence(timeout: 5), "Date sheet's From toggle missing")
        // Tap the switch control (trailing edge), not the wide row center —
        // same finding as `MemosListUITests.testFilterUnsyncedHidesSynced`.
        fromToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(fromToggle.value as? String, "1", "From toggle didn't flip on")
        app.buttons["sortfilter-done"].tap()
        capture(app, "phone-date-active")
    }
}
