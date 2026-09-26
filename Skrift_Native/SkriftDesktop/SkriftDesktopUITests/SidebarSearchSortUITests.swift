import XCTest

/// Live verification of the sidebar SEARCH + chip row. The sidebar can't be
/// rendered by the `-snapshot`/`-snapshot-shell` ImageRenderer harness (its
/// `FilePromiseDropCatcher` NSViewRepresentable / `.dropDestination` make
/// ImageRenderer draw the whole column as a placeholder — and, past Q66, the
/// chip row's own horizontal `ScrollView` doesn't lay out its off-screen
/// content in that offscreen renderer either), so these controls are
/// verified by driving the real app under `-demo` (which seeds the queue).
final class SidebarSearchSortUITests: XCTestCase {

    /// Q66 visual check — screenshots for `plan/reads/filter-q66/`.
    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.4)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Skrift"].waitForExistence(timeout: 15), "brand should appear")
        return app
    }

    /// The search field renders, and typing a query that matches nothing
    /// actually FILTERS the queue to the "No matches" state (not just shows
    /// the field). Clearing restores the queue.
    func testSearchFiltersTheQueue() {
        let app = launch()

        let search = app.textFields["sidebar.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), "search field missing")
        XCTAssertTrue(app.staticTexts["sidebar.chip.All"].waitForExistence(timeout: 5)
                      || app.buttons["sidebar.chip.All"].waitForExistence(timeout: 5),
                      "chip row missing")

        search.click()
        search.typeText("zzzznomatchqqq")
        XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 5),
                      "a non-matching query should filter the queue to 'No matches'")

        app.buttons["Clear search"].click()
        XCTAssertFalse(app.staticTexts["No matches"].waitForExistence(timeout: 2),
                       "clearing the search should restore the queue")
    }

    /// Q66/D148 (option A): the chip row carries everything now — the old
    /// icon-only Filter button + its Sort/Date popover are gone. The Date
    /// chip opens its own popover (just the range), and the sort word steps
    /// to the next order on click, no popover at all.
    func testDateChipOpensDatePopoverAndSortWordSteps() {
        let app = launch()

        capture(app, "mac-chip-row")

        let dateChip = app.descendants(matching: .any).matching(identifier: "sidebar.chip.Date").firstMatch
        XCTAssertTrue(dateChip.waitForExistence(timeout: 5), "Date chip missing")
        dateChip.click()
        XCTAssertTrue(app.staticTexts["Filter by date"].waitForExistence(timeout: 5),
                      "Date chip should open its own date-range popover")
        capture(app, "mac-date-popover")
        // Dismiss by clicking elsewhere on the sidebar.
        app.staticTexts["Skrift"].click()

        let sortWord = app.descendants(matching: .any).matching(identifier: "sidebar.sort-word").firstMatch
        XCTAssertTrue(sortWord.waitForExistence(timeout: 5), "sort word missing")
        let before = sortWord.title
        sortWord.click()
        XCTAssertTrue(sortWord.waitForExistence(timeout: 5))
        XCTAssertNotEqual(sortWord.title, before, "the sort word should step to the next order on click")
        capture(app, "mac-sort-stepped")
    }
}
