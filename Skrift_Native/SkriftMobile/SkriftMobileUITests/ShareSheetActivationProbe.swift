import XCTest

/// Diagnostic probe for the share-extension ACTIVATION RULE (not part of the
/// regular suite — run explicitly via -only-testing). Drives sim-Safari's share
/// sheet and asserts Skrift appears. Exists because the rule is write-only
/// otherwise: a bad predicate silently removes Skrift from every share sheet.
///
/// The host script must `simctl openurl booted <url>` BEFORE the PDF probe (the
/// address-bar typing path is the flaky part; openurl is deterministic).
final class ShareSheetActivationProbe: XCTestCase {

    private var safari: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    }

    /// Open Safari's share sheet — direct ShareButton on older Safari; on iOS 26
    /// Share lives under the bottom-bar "···" menu.
    private func openShareSheet(_ app: XCUIApplication) {
        let direct = app.buttons["ShareButton"]
        if direct.waitForExistence(timeout: 5) { direct.tap(); return }
        let more = app.buttons.matching(NSPredicate(
            format: "identifier CONTAINS[c] 'more' OR label CONTAINS[c] 'more' OR identifier CONTAINS[c] 'menu'")).firstMatch
        if more.waitForExistence(timeout: 5) {
            more.tap()
            let share = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'share'")).firstMatch
            if share.waitForExistence(timeout: 5) { share.tap(); return }
            let shareCell = app.cells.matching(NSPredicate(format: "label BEGINSWITH[c] 'share'")).firstMatch
            if shareCell.waitForExistence(timeout: 3) { shareCell.tap(); return }
        }
        print("PROBE buttons: \(app.buttons.allElementsBoundByIndex.prefix(40).map { "\($0.identifier)|\($0.label)" })")
        XCTFail("could not open the share sheet")
    }

    /// Safari is already showing the target page (host openurl'd it). Tap share,
    /// then require Skrift in the sheet — dumping every visible cell label on
    /// failure so the miss is diagnosable from the log.
    func testSkriftAppearsForCurrentSafariPage() throws {
        let app = safari
        app.activate()
        openShareSheet(app)

        // The activity sheet's app row: cells labeled with app/extension names.
        let skrift = app.cells.matching(NSPredicate(format: "label CONTAINS[c] 'Skrift'")).firstMatch
        let appeared = skrift.waitForExistence(timeout: 12)

        if !appeared {
            let labels = app.cells.allElementsBoundByIndex.prefix(30).map(\.label)
            print("PROBE share-sheet cells: \(labels)")
        }
        XCTAssertTrue(appeared, "Skrift missing from the share sheet for this page")
    }

    /// End-to-end: open the sheet, pick Skrift, tap Save, and require the
    /// Saved ✓ state — proves the extension's WRITE path, not just activation.
    func testShareSavesThroughTheSheet() throws {
        let app = safari
        app.activate()
        openShareSheet(app)

        let skrift = app.cells.matching(NSPredicate(format: "label CONTAINS[c] 'Skrift'")).firstMatch
        XCTAssertTrue(skrift.waitForExistence(timeout: 12), "Skrift missing from the sheet")
        skrift.tap()

        let save = app.buttons["capture-save"].exists
            ? app.buttons["capture-save"]
            : app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Save to Skrift'")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10), "share sheet did not present")
        save.tap()

        // Saved ✓ flashes ~0.9s; the error state ("Couldn't save this") sticks.
        let saved = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Saved'")).firstMatch
        let failed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] \"Couldn't save\"")).firstMatch
        let deadline = Date().addingTimeInterval(10)
        var outcome = "timeout"
        while Date() < deadline {
            if saved.exists { outcome = "saved"; break }
            if failed.exists { outcome = "failed"; break }
            usleep(200_000)
        }
        print("PROBE save outcome: \(outcome)")
        XCTAssertEqual(outcome, "saved", "the write path must land on Saved ✓")
    }
}
