import XCTest

/// Q556 (D227): a Portfolio note on the phone and iPad reads and types as before, offers no export
/// action (one quiet line instead), and Settings has no Portfolio folder row. Screenshots land in
/// `SKRIFT_SHOT_DIR` (pass `TEST_RUNNER_SKRIFT_SHOT_DIR`), or the xcresult.
final class PortfolioFromMacQ556UITests: XCTestCase {

    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 1.0)
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

    private func menuItem(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    private func openPortfolioNote(portfolio: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        // `-fakePolishEngine`: the simulator has no engine, and the export verb only shows where one exists.
        app.launchArguments = ["-inMemoryStore", "-seedPolished", "-routeViaList", "-destinationsOn",
                               "-fakePolishEngine", "-skipOnboarding", "-appTheme", "light"]
        app.launch()
        let row = any(app, "memo-row-0")
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the list never showed the note")
        row.tap()
        XCTAssertTrue(app.textViews["transcript-editor"].waitForExistence(timeout: 25), "editor missing")
        let pill = app.buttons["destination-pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "destination pill missing")
        if portfolio {
            if pill.label != "Destination: Portfolio" { pill.tap() }
            XCTAssertEqual(pill.label, "Destination: Portfolio", "one tap flips it (the pill still works)")
        }
        Thread.sleep(forTimeInterval: 1.0)
        return app
    }

    private func byLabel(_ app: XCUIApplication, beginsWith text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
    }

    /// Reading: the pill works, no Export / Re-export anywhere, the quiet line stands in. On the
    /// iPad it sits in the header; on the phone it is the first row of the ⋯ menu.
    func testPortfolioNoteReading() {
        let app = openPortfolioNote()
        capture(app, "q556-1-portfolio-reading")
        XCTAssertFalse(byLabel(app, beginsWith: "Export to").exists, "no Export button on a Portfolio note")
        XCTAssertFalse(byLabel(app, beginsWith: "Re-export").exists, "no Re-export button on a Portfolio note")
        let more = any(app, "detail-menu")
        if more.waitForExistence(timeout: 3) {
            more.tap()
            Thread.sleep(forTimeInterval: 0.8)
            XCTAssertFalse(byLabel(app, beginsWith: "Export to").exists, "no Export item in the menu")
            XCTAssertFalse(byLabel(app, beginsWith: "Re-export").exists, "no Re-export item in the menu")
            XCTAssertTrue(byLabel(app, beginsWith: "Exports from the Mac").exists, "the quiet line is missing")
            capture(app, "q556-2-portfolio-more-menu")
        } else {
            XCTAssertTrue(byLabel(app, beginsWith: "Exports from the Mac").exists, "the quiet line is missing")
        }
    }

    /// Personal is unchanged: the export verb is still offered (header on iPad, ⋯ menu on phone).
    func testPersonalNoteStillOffersExport() {
        let app = openPortfolioNote(portfolio: false)
        capture(app, "q556-5-personal-reading")
        if byLabel(app, beginsWith: "Export to Obsidian").exists { return }
        let more = any(app, "detail-menu")
        XCTAssertTrue(more.waitForExistence(timeout: 5), "no ⋯ menu and no inline Export")
        more.tap()
        XCTAssertTrue(byLabel(app, beginsWith: "Export to Obsidian").waitForExistence(timeout: 5),
                      "Personal lost its Export item")
        capture(app, "q556-6-personal-more-menu")
    }

    /// Typing: the editor still takes text on a Portfolio note.
    func testPortfolioNoteTyping() {
        let app = openPortfolioNote()
        let editor = app.textViews["transcript-editor"]
        editor.tap()
        Thread.sleep(forTimeInterval: 1.0)
        app.typeText(" Typed on the phone.")
        capture(app, "q556-3-portfolio-typing")
        XCTAssertTrue((editor.value as? String ?? "").contains("Typed on the phone."), "the text did not land")
    }

    /// Settings: switch on, and no Portfolio folder row; the footer says the Mac exports.
    func testSettingsHasNoPortfolioFolder() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedDemoMemos", "-openTab", "settings",
                               "-destinationsOn", "-skipOnboarding", "-appTheme", "light"]
        app.launch()
        let toggle = app.switches["destinations-toggle"]
        for _ in 0..<30 {
            if toggle.exists && toggle.isHittable { break }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.47))
            from.press(forDuration: 0.05, thenDragTo: to)
        }
        XCTAssertTrue(toggle.exists, "the Destinations switch is missing")
        // Bring the section to mid-screen so the footer shows too.
        for _ in 0..<2 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
            from.press(forDuration: 0.05, thenDragTo: to)
        }
        if toggle.value as? String != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        XCTAssertEqual(toggle.value as? String, "1", "the switch should read on")
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertFalse(app.buttons["portfolio-folder"].exists, "the phone has no Portfolio folder row")
        capture(app, "q556-4-settings-destinations")
    }
}
