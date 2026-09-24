import XCTest

/// The inline tag row (D139 signed mock `mocks/tag-ui-revamp.html`, Q28/Q36 revamp).
/// Rewritten from the old `TagSheetUITests`, which drove a Tags SHEET that no longer
/// exists (`+ tag` now turns into a field in the row itself, D139 pick 1) and asserted
/// the pre-2026-08-27 rule that a destination word (`inspiration`) gets refused as a
/// tag — C93 now says all four destination words ARE tags (Q36 brief).
final class TagSheetUITests: XCTestCase {

    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 1.0)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAddTagOpensInlineFieldNoSheetAndAcceptsADestinationWord() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedPolished", "-selectFirstMemo"]
        app.launch()

        let addTag = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'add-tag-button'")).firstMatch
        XCTAssertTrue(addTag.waitForExistence(timeout: 20), "the ＋ tag control is missing")
        addTag.tap()

        // No sheet: the field lands INLINE, in the tag row itself.
        let field = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'tag-input'")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the inline tag field did not open")
        XCTAssertFalse(app.navigationBars["Tags"].exists, "a Tags sheet appeared — D139 replaced it with the inline row")
        capture(app, "tag-row-field-open")

        // A destination word IS a tag now (C93 revamp) — it becomes a real chip, not a refusal.
        field.tap()
        field.typeText("inspiration\n")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'tag-chip-inspiration'")).firstMatch
            .waitForExistence(timeout: 5), "\"inspiration\" should have landed as a tag chip (C93)")
        capture(app, "tag-destination-word-accepted")
    }
}
