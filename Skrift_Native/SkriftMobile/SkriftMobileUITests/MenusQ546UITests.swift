import XCTest

/// Q546 (Tuur 2026-11-04, FeedbackKit 93899eb0): the phone's ⋯ and attach menus open out of the button
/// that was tapped (a real Menu), not as a page-level dialog bubble with a tail. Screenshots land in
/// `SKRIFT_SHOT_DIR` (pass `TEST_RUNNER_SKRIFT_SHOT_DIR`), or the xcresult.
final class MenusQ546UITests: XCTestCase {

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

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func openNote(_ seed: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", seed, "-skipOnboarding", "-appTheme", "light"]
            + (seed == "-seedBareNote" ? ["-seedDemoMemos"] : [])
        app.launch()
        let row = any(app, seed == "-seedBareNote" ? "memo-row-1" : "memo-row-0")
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the list never showed the note")
        row.tap()
        XCTAssertTrue(app.textViews["transcript-editor"].waitForExistence(timeout: 25), "editor missing")
        Thread.sleep(forTimeInterval: 1.5)
        return app
    }

    private func menuItem(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    /// Reading: the ⋯ opens a menu with every item; Find, Set All to Small and Lock each run once.
    func testMoreMenuReading() {
        let app = openNote("-seedPictureSizes")
        let more = any(app, "detail-menu")
        XCTAssertTrue(more.waitForExistence(timeout: 10), "⋯ missing")
        more.tap()
        XCTAssertTrue(menuItem(app, "Find in Note").waitForExistence(timeout: 5), "Find in Note missing")
        for t in ["Set All to Small", "Set All to Large", "Share", "Copy", "Delete"] {
            XCTAssertTrue(menuItem(app, t).exists, "\(t) missing from the ⋯ menu")
        }
        capture(app, "q546-1-more-reading")

        // Find in Note → the find bar.
        menuItem(app, "Find in Note").tap()
        Thread.sleep(forTimeInterval: 1.0)
        capture(app, "q546-2-find-ran")
        app.typeText("\n")   // leave the find field if it took focus
        if app.buttons["Done"].firstMatch.exists { app.buttons["Done"].firstMatch.tap() }

        // Set All to Large, then Small: the pictures change size.
        if !more.exists { app.tap() }
        more.tap()
        XCTAssertTrue(menuItem(app, "Set All to Large").waitForExistence(timeout: 5))
        menuItem(app, "Set All to Large").tap()
        capture(app, "q546-3-set-all-large")
        more.tap()
        XCTAssertTrue(menuItem(app, "Set All to Small").waitForExistence(timeout: 5))
        menuItem(app, "Set All to Small").tap()
        capture(app, "q546-4-set-all-small")

        // Lock.
        more.tap()
        let lock = menuItem(app, "Lock")
        XCTAssertTrue(lock.waitForExistence(timeout: 5), "Lock missing")
        lock.tap()
        capture(app, "q546-5-lock-ran")
    }

    /// Typing: the ⋯ still opens its menu with the keyboard up.
    func testMoreMenuTyping() {
        let app = openNote("-seedBareNote")
        let editor = app.textViews["transcript-editor"]
        editor.tap()
        XCTAssertTrue(any(app, "accessory-done").waitForExistence(timeout: 5), "bar missing")
        any(app, "detail-menu").tap()
        XCTAssertTrue(menuItem(app, "Find in Note").waitForExistence(timeout: 5), "Find in Note missing while typing")
        capture(app, "q546-6-more-typing")
    }

    /// Typing: the 📷 in the bar opens its menu out of the button; the keyboard stays up and the caret stays.
    func testPhotoMenuTyping() {
        let app = openNote("-seedBareNote")
        let editor = app.textViews["transcript-editor"]
        editor.tap()
        let photo = any(app, "accessory-photo")
        XCTAssertTrue(photo.waitForExistence(timeout: 5), "photo button missing")
        photo.tap()
        let choose = menuItem(app, "Choose Photo or Video")
        XCTAssertTrue(choose.waitForExistence(timeout: 5), "Choose Photo or Video missing")
        XCTAssertTrue(menuItem(app, "Attach File").exists, "Attach File missing")
        XCTAssertGreaterThan(app.keyboards.count, 0, "the menu dismissed the keyboard")
        capture(app, "q546-7-photo-menu-typing")

        // Choose runs: the photo library opens.
        choose.tap()
        Thread.sleep(forTimeInterval: 2.0)
        capture(app, "q546-8-choose-ran")
    }
}
