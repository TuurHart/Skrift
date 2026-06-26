import XCTest

/// Phase 4 — the phone surfaces the Mac's polish (mocks/phone-polished-display.html). Verifies
/// the polished copy-edit (not the raw fillers) is the editable body, the summary + provenance
/// show, and the title chooser offers the Mac's suggestion + your own.
final class PolishedDisplayUITests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedPolished", "-skipOnboarding", "-appTheme", "dark"]
        app.launch()
        return app
    }

    func testPolishedBodyAndTitleChooser() throws {
        let app = launch()
        let editor = app.textViews["transcript-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "polished body editor didn't render")

        // The body shows the Mac's COPY-EDIT (clean), not the raw um-filled transcript.
        let body = editor.value as? String ?? ""
        XCTAssertTrue(body.contains("ran the whole set twice"), "polished copy-edit missing — got: \(body)")
        XCTAssertFalse(body.lowercased().contains("um,"), "raw fillers leaked into the polished body")

        // Summary + provenance.
        XCTAssertTrue(app.staticTexts["SUMMARY"].exists, "summary card missing")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Polished on your Mac'")).firstMatch.exists,
                      "provenance caption missing")

        let s = XCTAttachment(screenshot: app.screenshot())
        s.name = "polished-detail"; s.lifetime = .keepAlways; add(s)

        // Title chooser → Suggested (Mac) + Type your own…
        let chooser = app.buttons["title-chooser-button"]
        XCTAssertTrue(chooser.exists, "title chooser button missing")
        chooser.tap()
        XCTAssertTrue(app.buttons["Type your own…"].waitForExistence(timeout: 5),
                      "title chooser didn't open")
        let s2 = XCTAttachment(screenshot: app.screenshot())
        s2.name = "polished-title-chooser"; s2.lifetime = .keepAlways; add(s2)
    }
}
