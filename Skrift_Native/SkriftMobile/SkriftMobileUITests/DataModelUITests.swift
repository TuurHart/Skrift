import XCTest

/// Phase 1: with `-inMemoryStore -seedDemoMemos`, the seeded memos render in the
/// list. Exercises the SwiftData model + repository + seeder + metadata decode
/// end to end through the UI.
final class DataModelUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func snap(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testSeededMemosRender() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedDemoMemos"]
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let cancel = springboard.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 2) { cancel.tap() }

        // Root showed.
        XCTAssertTrue(
            app.staticTexts["Notes"].waitForExistence(timeout: 15)
                || app.navigationBars["Notes"].waitForExistence(timeout: 5),
            "Memos root never appeared"
        )

        // A seeded transcript is visible → the model + repository + seeder worked.
        XCTAssertTrue(
            app.staticTexts["First seeded memo about the harbor at dawn."].waitForExistence(timeout: 5),
            "Seeded memo text never rendered"
        )

        // The empty state must NOT be showing.
        XCTAssertFalse(app.otherElements["memos-empty"].exists)

        snap("memos-seeded")

        // Print visible text for the test log (Pike-style dump).
        let texts = app.staticTexts.allElementsBoundByIndex
            .filter { $0.exists }.map { $0.label }.filter { !$0.isEmpty }
        print("SCREEN[memos]: " + texts.joined(separator: " | "))
    }
}
