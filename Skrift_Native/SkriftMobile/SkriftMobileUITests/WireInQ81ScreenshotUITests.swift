import XCTest

/// Q81 visual check ONLY — screenshots for `plan/reads/wirein-q81/`: the tag editor's
/// "already on this note" lines (mock `tag-ui-revamp.html`) and the note ⋯ "Undo tidy-up"
/// item. Synthetic corpus, in-memory store (C4). Not a durable regression test.
final class WireInQ81ScreenshotUITests: XCTestCase {

    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        let corpus = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test-fixtures/corpus").path
        app.launchArguments = ["-inMemoryStore", "-corpus", corpus, "-selectFirstMemo"]
        app.launch()
        return app
    }

    func testTagAlreadyOnNote() {
        let app = launch()
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        let addTag = app.buttons["add-tag-button"]
        XCTAssertTrue(addTag.waitForExistence(timeout: 20))
        addTag.tap()
        let field = app.textFields["tag-input"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("harbor\n")
        XCTAssertTrue(field.exists, "field closed")
        field.tap()
        field.typeText("HARBOR")
        XCTAssertTrue(app.staticTexts["tag-already-on-note"].waitForExistence(timeout: 5),
                      "typing a case-variant of an on-note tag must show the live line")
        capture(app, "phone-tag-already-typing")
        field.typeText("\n")
        XCTAssertTrue(app.staticTexts["tag-already-hint"].waitForExistence(timeout: 5),
                      "committing it must show 'Already on this note as #harbor.'")
        capture(app, "phone-tag-already-committed")
    }

    func testUndoTidyUpInMenu() {
        let app = launch()
        let search = app.textFields["memo-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap()
        search.typeText("crack runs from the rim")
        let pic = app.buttons["memo-row-0"]
        XCTAssertTrue(pic.waitForExistence(timeout: 20), "the pic-mid-sentence corpus note row never appeared")
        pic.tap()
        let menu = app.buttons["detail-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 1.5)   // first open runs the one-time tidy-up
        menu.tap()
        let undo = app.buttons["Undo tidy-up"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "Undo tidy-up must be offered after the tidy-up ran")
        capture(app, "phone-menu-undo-tidy-up")
        undo.tap()
        Thread.sleep(forTimeInterval: 1.0)
        menu.tap()
        XCTAssertFalse(app.buttons["Undo tidy-up"].waitForExistence(timeout: 2), "gone after the undo")
        capture(app, "phone-menu-after-undo")
    }

    /// iPad (regular width): the ⋯ lives in the workbench chrome, and the tag line in the header.
    func testIPadUndoTidyUpAndTag() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
        let app = launch()
        let search = app.textFields["memo-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 20))
        search.tap()
        search.typeText("crack runs from the rim")
        let pic = app.buttons["memo-row-0"]
        XCTAssertTrue(pic.waitForExistence(timeout: 20))
        pic.tap()
        let menu = app.buttons["More"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 1.5)
        menu.tap()
        if !app.buttons["Undo tidy-up"].waitForExistence(timeout: 3) {   // first tap only dismissed the keyboard
            menu.tap()
        }
        XCTAssertTrue(app.buttons["Undo tidy-up"].waitForExistence(timeout: 5))
        capture(app, "ipad-menu-undo-tidy-up")
    }
}
