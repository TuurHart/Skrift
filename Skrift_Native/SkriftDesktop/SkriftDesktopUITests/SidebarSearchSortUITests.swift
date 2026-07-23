import XCTest

/// Live verification of the sidebar SEARCH + SORT controls. The sidebar can't be
/// rendered by the `-snapshot` ImageRenderer harness (its `FilePromiseDropCatcher`
/// NSViewRepresentable / `.dropDestination` make ImageRenderer draw the whole
/// column as a placeholder), so these controls are verified by driving the real
/// app under `-demo` (which seeds the queue).
final class SidebarSearchSortUITests: XCTestCase {

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Skrift"].waitForExistence(timeout: 15), "brand should appear")
        return app
    }

    /// The search field and sort control render, and typing a query that matches
    /// nothing actually FILTERS the queue to the "No matches" state (not just shows
    /// the field). Clearing restores the queue.
    func testSearchFiltersTheQueue() {
        let app = launch()

        let search = app.textFields["sidebar.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), "search field missing")
        XCTAssertTrue(app.buttons["sidebar.filter"].waitForExistence(timeout: 5), "filter control missing")

        search.click()
        search.typeText("zzzznomatchqqq")
        XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 5),
                      "a non-matching query should filter the queue to 'No matches'")

        app.buttons["Clear search"].click()
        XCTAssertFalse(app.staticTexts["No matches"].waitForExistence(timeout: 2),
                       "clearing the search should restore the queue")
    }

    /// The Filter control opens a popover of sort options, and picking one
    /// dismisses it — the single Filter button replaced the old cycle (2026-07-23).
    func testFilterControlOpensSortOptions() {
        let app = launch()
        let filter = app.buttons["sidebar.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5), "filter control missing")
        filter.click()
        let oldest = app.buttons["Oldest first"]
        XCTAssertTrue(oldest.waitForExistence(timeout: 5), "sort options should appear in the filter popover")
        oldest.click()
        XCTAssertTrue(filter.exists, "filter control should remain after picking a sort")
    }
}
