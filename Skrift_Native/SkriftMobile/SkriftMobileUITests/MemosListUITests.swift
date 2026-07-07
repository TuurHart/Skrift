import XCTest

/// Phase 7.4: the memos list — search, Sort & Filter, and multi-select delete
/// over seeded demo memos.
final class MemosListUITests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedDemoMemos"]
        app.launch()
        return app
    }

    private let harbor = "First seeded memo about the harbor at dawn."
    private let plumber = "Second seeded memo, a quick reminder to call the plumber."

    /// Device rounds 3–4: "photo search finds nothing" — user-directed sim
    /// reproduction of the WHOLE path: a seeded memo carries a real photo of
    /// printed text with NO OCR yet → the launch sweep must index it (real
    /// Vision) → typing in the list search field must surface exactly that
    /// memo. Covers sweep trigger, Vision, manifest write-back, the search
    /// binding, matches(), and live re-filtering when the OCR lands.
    func testPhotoTextSearchEndToEnd() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedPhotoTextMemo"]
        app.launch()
        XCTAssertTrue(app.staticTexts[harbor].waitForExistence(timeout: 10))

        let field = app.textFields["memo-search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("zuurkool")

        // The word exists ONLY inside the photo. The row may appear a beat
        // later (the Vision pass writes back → the list re-filters live).
        let photoMemoRow = app.staticTexts["Snapped the tram stop sign on the way home."]
        XCTAssertTrue(photoMemoRow.waitForExistence(timeout: 12),
                      "a memo must be findable by the text INSIDE its photo")
        XCTAssertFalse(app.staticTexts[harbor].exists, "non-matching memos filter out")
    }

    /// Device round 1 (build 31): a long-press on a row started the list
    /// drifting as if scrolling and the context menu never opened — the row's
    /// .onTapGesture fought the lift on iOS 26. The row is a Button now; the
    /// long-press must present the menu.
    func testLongPressOpensContextMenu() throws {
        let app = launch()
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.press(forDuration: 0.9)
        XCTAssertTrue(app.buttons["context-remind-button"].waitForExistence(timeout: 4),
                      "long-press must open the row's context menu")
        // Dismiss without acting; the list must still be intact.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(app.staticTexts[harbor].waitForExistence(timeout: 4))
    }

    func testSearchFiltersMemos() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts[harbor].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[plumber].exists)

        let field = app.textFields["memo-search"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("harbor")

        XCTAssertTrue(app.staticTexts[harbor].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[plumber].exists, "plumber memo should be filtered out by search")
    }

    func testFilterUnsyncedHidesSynced() throws {
        let app = launch()
        // demo2 (plumber) is seeded Synced; the others are Waiting.
        XCTAssertTrue(app.staticTexts[plumber].waitForExistence(timeout: 10))

        app.buttons["sort-filter-button"].tap()
        let unsynced = app.switches["filter-unsynced"]
        XCTAssertTrue(unsynced.waitForExistence(timeout: 5))
        // Tap the switch control (trailing edge), not the wide row center.
        unsynced.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(unsynced.value as? String, "1", "unsynced toggle didn't flip on")
        app.buttons["sortfilter-done"].tap()

        // Wait for the list to re-filter after the sheet dismisses.
        XCTAssertTrue(app.staticTexts[plumber].waitForNonExistence(timeout: 4),
                      "synced memo should be hidden by 'unsynced only'")
        XCTAssertTrue(app.staticTexts[harbor].exists, "waiting memo should remain")
    }

    func testStatusPillsShowTranscribingAndError() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Synced"].waitForExistence(timeout: 10))   // demo2

        // demo4 (.transcribing) + demo5 (.failed) are the oldest, so scroll the
        // LazyVStack until the Error pill materializes. (Re-transcribe was removed;
        // a failed memo shows an informational "Error" pill — no Retry button.)
        var errorPill = app.staticTexts["Error"]
        var tries = 0
        while !errorPill.exists && tries < 4 { app.swipeUp(); tries += 1; errorPill = app.staticTexts["Error"] }
        XCTAssertTrue(errorPill.exists, "Error status pill missing")
        XCTAssertTrue(app.staticTexts["Transcribing"].exists, "Transcribing pill missing")
    }

    func testSelectAndDelete() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts[harbor].waitForExistence(timeout: 10))

        app.buttons["select-button"].tap()
        app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch.tap()
        let del = app.buttons["delete-selected-button"]
        XCTAssertTrue(del.waitForExistence(timeout: 5))
        del.tap()

        XCTAssertFalse(app.staticTexts[harbor].waitForExistence(timeout: 3), "deleted memo should be gone")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "memos-list"; shot.lifetime = .keepAlways; add(shot)
    }

    func testSwipeToDelete() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts[harbor].waitForExistence(timeout: 10))

        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()

        // Native .swipeActions reveal a "Delete" button; a full swipe commits
        // directly. Handle both so the test isn't sensitive to swipe distance.
        let del = app.buttons["Delete"].firstMatch
        if del.waitForExistence(timeout: 2) { del.tap() }

        XCTAssertTrue(app.staticTexts[harbor].waitForNonExistence(timeout: 4),
                      "swiped memo should be deleted")
    }
}
