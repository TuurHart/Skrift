import XCTest

/// Q535 (Rox, TestFlight 199): after a share import the tab bar was gone on Library. The import
/// switches the tab (`TabSelectionBridge.select(.books)`) while the Notes stack still holds a
/// pushed note that hides the bar (D200). Here `-switchTabLater books` mounts a debug tap target
/// that fires that switch once the note is open. Screenshots land in `SKRIFT_SHOT_DIR`.
final class TabBarAfterShareImportUITests: XCTestCase {

    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.8)
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SKRIFT_SHOT_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    func testTabBarBackOnLibraryAfterImportSwitchesTabFromAnOpenNote() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedPolished", "-selectFirstMemo", "-destinationsOn",
                               "-skipOnboarding", "-routeViaList", "-appTheme", "light",
                               "-seedLibraryShelf", "-switchTabLater", "books"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "list row missing")
        row.tap()
        XCTAssertTrue(app.textViews["transcript-editor"].waitForExistence(timeout: 25), "editor missing")
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: tabBar)
        waitForExpectations(timeout: 8)
        XCTAssertFalse(tabBar.exists, "a normally opened note still hides the tab bar")
        capture(app, "q535-note-open")

        // The import's tab switch lands: Library must carry the bar.
        app.buttons["debug-switch-tab"].tap()
        XCTAssertTrue(app.staticTexts["Library"].waitForExistence(timeout: 10), "Library screen shown")
        capture(app, "q535-library-after-switch")
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "tab bar must exist on Library after the switch")
    }
}
