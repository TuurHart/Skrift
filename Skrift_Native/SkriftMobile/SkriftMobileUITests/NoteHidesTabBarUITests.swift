import XCTest

/// Q387 (D200): on the phone the open note hides the tab bar, like Apple Notes; the list shows
/// it again. Screenshots land in `SKRIFT_SHOT_DIR` (plan/reads/editor-apple/tabbar-*.png).
final class NoteHidesTabBarUITests: XCTestCase {

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

    func testOpenNoteHidesTabBarAndBackBringsItBack() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedPolished", "-selectFirstMemo", "-destinationsOn",
                               "-skipOnboarding", "-routeViaList", "-appTheme", "light"]
        app.launch()

        let tabBar = app.tabBars.firstMatch
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "list row missing")
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "tab bar missing on the list")
        capture(app, "tabbar-list-before")

        row.tap()
        XCTAssertTrue(app.textViews["transcript-editor"].waitForExistence(timeout: 25), "editor missing")
        XCTAssertTrue(app.buttons["note-back-button"].waitForExistence(timeout: 5), "‹ Notes missing")
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: tabBar)
        waitForExpectations(timeout: 8)
        XCTAssertFalse(tabBar.exists, "tab bar must be hidden while a note is open")
        capture(app, "tabbar-note-open")

        app.buttons["note-back-button"].tap()
        XCTAssertTrue(tabBar.waitForExistence(timeout: 8), "tab bar must return on the list")
        capture(app, "tabbar-list-after")
    }
}
