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
        XCTAssertTrue(app.descendants(matching: .any)["sidebar.chip.Date"].waitForExistence(timeout: 5), "Date chip missing")
        XCTAssertTrue(app.descendants(matching: .any)["sidebar.sort-word"].exists, "sort word missing")

        search.click()
        search.typeText("zzzznomatchqqq")
        XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 5),
                      "a non-matching query should filter the queue to 'No matches'")

        app.buttons["Clear search"].click()
        XCTAssertFalse(app.staticTexts["No matches"].waitForExistence(timeout: 2),
                       "clearing the search should restore the queue")
    }

    /// The sort word at the end of the chip row cycles to the next sort on one tap
    /// (Q66/D148 option A replaced the Filter button + Sort & Date popover).
    func testSortWordCyclesSort() {
        let app = launch()
        let word = app.descendants(matching: .any)["sidebar.sort-word"]
        XCTAssertTrue(word.waitForExistence(timeout: 5), "sort word missing")
        let before = word.label
        word.click()
        XCTAssertNotEqual(word.label, before, "one tap should move to the next sort")
        XCTAssertTrue(word.exists, "sort word should remain after cycling")
    }
}
