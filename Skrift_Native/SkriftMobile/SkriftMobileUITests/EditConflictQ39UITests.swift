import XCTest

/// Q39 visual check ONLY — screenshots the edit-conflict prompt, banner and list pill
/// against the signed mock `mocks/Q4-edit-conflict.html` (C242/D139). Launches on the
/// SYNTHETIC corpus in an in-memory store with `-forceEditConflict`, which manufactures ONE
/// conflict on the first row (`EditConflicts.debugForceConflict`, C4) — never the live Dev
/// store. Not a durable regression test; its job is the screenshots for
/// `plan/reads/conflict-q39/`.
final class EditConflictQ39UITests: XCTestCase {

    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // Derived from `#filePath` (compiled inside THIS worktree), not hardcoded — a
    // hardcoded sibling worktree path dies once that worktree is cleaned up (Q36 lesson).
    private var corpusPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SkriftMobileUITests
            .deletingLastPathComponent()   // SkriftMobile
            .deletingLastPathComponent()   // Skrift_Native
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("test-fixtures/corpus").path
    }

    /// Phone: the list row's amber "2 versions" pill, the prompt that opens on note open,
    /// and the banner that replaces it after "Later".
    func testConflictPromptBannerPill() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-corpus", corpusPath, "-forceEditConflict"]
        app.launch()

        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the conflicted row never appeared — did the seed run?")
        let pill = app.staticTexts["2 versions"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "the '2 versions' pill is missing on the list row")
        capture(app, "phone-list-pill")

        row.tap()

        let laterButton = app.buttons["conflict-later"]
        XCTAssertTrue(laterButton.waitForExistence(timeout: 10), "the conflict prompt did not open on note open (D139)")
        capture(app, "phone-prompt")

        laterButton.tap()
        let banner = app.descendants(matching: .any).matching(identifier: "conflict-banner").firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "the amber banner did not appear after Later")
        capture(app, "phone-banner-after-later")
    }

    /// iPad workbench: the prompt opens on the auto-selected note, and after "Later" the
    /// note stays read-only until picked (typing now would make a third version).
    func testConflictBlocksEditingOnIPadWorkbench() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-corpus", corpusPath, "-forceEditConflict", "-selectFirstMemo"]
        app.launch()

        let laterButton = app.buttons["conflict-later"]
        XCTAssertTrue(laterButton.waitForExistence(timeout: 20), "the conflict prompt did not open on the workbench")
        laterButton.tap()

        let banner = app.descendants(matching: .any).matching(identifier: "conflict-banner").firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "the amber banner did not appear on the workbench after Later")
        capture(app, "ipad-workbench-blocked")

        // The pager keeps an adjacent page realised (a different memo, its OWN "detail-title"
        // field) — two matches for the identifier, so pick the CURRENT page's (index 0; the
        // conflicted memo is page 0 since `-selectFirstMemo` selects the newest, and the pager
        // realises the current page before its neighbour).
        let title = app.descendants(matching: .any).matching(identifier: "detail-title").element(boundBy: 0)
        XCTAssertTrue(title.waitForExistence(timeout: 5), "the note title field is missing")
        XCTAssertFalse(title.isEnabled, "the note stayed editable with an unresolved conflict — a third version could land")
    }
}
