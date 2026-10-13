import XCTest

/// Q341: every top-level screen tags itself for FeedbackKit, so the feedback sheet says
/// "From the <name> screen". Needs the key from `~/.config/feedback-kit/skrift.xcconfig`:
/// without it FeedbackKit shows no button and these tests fail on the button wait.
final class FeedbackQ341ScreenTagUITests: XCTestCase {

    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-skipOnboarding", "-inMemoryStore", "-seedDemoMemos", "-seedDemoNames"] + extra
        app.launch()
        return app
    }

    private func assertSheetSays(_ screen: String, in app: XCUIApplication,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons["Feedback"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 30), "feedback button missing (no key?)", file: file, line: line)
        button.tap()
        let from = app.staticTexts["From the \(screen) screen"].firstMatch
        XCTAssertTrue(from.waitForExistence(timeout: 10),
                      "sheet does not read 'From the \(screen) screen'", file: file, line: line)
    }

    func testNotesListSaysNotes() throws {
        assertSheetSays("Notes", in: launch())
    }

    func testLibrarySaysLibrary() throws {
        assertSheetSays("Library", in: launch(extra: ["-openTab", "books"]))
    }

    func testSettingsSaysSettings() throws {
        assertSheetSays("Settings", in: launch(extra: ["-openTab", "settings"]))
    }

    func testNamesSaysNames() throws {
        let app = launch(extra: ["-openTab", "settings"])
        let link = app.descendants(matching: .any).matching(identifier: "names-link").firstMatch
        // The Library section sits far down the Settings form; scroll until it is on screen.
        var swipes = 0
        while !link.waitForExistence(timeout: 2) && swipes < 8 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(link.exists, "names-link not found after scrolling")
        link.tap()
        XCTAssertTrue(app.staticTexts["Jane Doe"].waitForExistence(timeout: 5))
        assertSheetSays("Names", in: app)
    }
}
