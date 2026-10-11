import XCTest

/// Q338 / D189: the two-chip destination row and the Portfolio tag presets, on a real note.
/// PNGs land in `SKRIFT_SHOT_DIR` when the runner passes one (so they can be looked at), and
/// are attached to the result bundle either way.
final class TwoDestinationsUITests: XCTestCase {

    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 1.0)   // let the chip FlowLayout settle before the shutter
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SKRIFT_SHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    func testPersonalThenPortfolioWithPresets() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedPolished", "-selectFirstMemo", "-destinationsOn"]
        app.launch()

        let chip = app.buttons["destination-chip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["tag-preset-idea"].exists, "Personal shows no presets")
        capture(app, "T1-personal")

        chip.tap()
        XCTAssertTrue(app.buttons["destination-portfolio"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["destination-personal"].exists)
        XCTAssertFalse(app.buttons["destination-idea"].exists, "no third chip")
        capture(app, "T2-expanded")

        app.buttons["destination-portfolio"].tap()
        let idea = app.buttons["tag-preset-idea"]
        XCTAssertTrue(idea.waitForExistence(timeout: 5), "Portfolio offers the presets")
        XCTAssertTrue(app.buttons["tag-preset-inspiration"].exists)
        XCTAssertTrue(app.buttons["tag-preset-project"].exists)
        capture(app, "T3-portfolio-presets")

        idea.tap()
        XCTAssertTrue(app.otherElements["tag-chip-idea"].waitForExistence(timeout: 5)
                      || app.staticTexts["#idea"].waitForExistence(timeout: 5), "the preset became a tag")
        XCTAssertFalse(app.buttons["tag-preset-idea"].exists, "a used preset leaves the strip")
        capture(app, "T4-idea-tagged")
    }
}
