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

        // D204 / Q395: ONE tap pill; a tap flips Personal <-> Portfolio in place.
        let pill = app.buttons["destination-pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 20))
        XCTAssertEqual(pill.label, "Destination: Personal")
        XCTAssertFalse(app.buttons["tag-preset-idea"].exists, "Personal shows no presets")
        capture(app, "T1-personal")

        pill.tap()
        XCTAssertEqual(pill.label, "Destination: Portfolio")
        XCTAssertEqual(app.buttons.matching(identifier: "destination-pill").count, 1, "no second control opens")
        let idea = app.buttons["tag-preset-idea"]
        XCTAssertTrue(idea.waitForExistence(timeout: 5), "Portfolio offers the presets")
        XCTAssertTrue(app.buttons["tag-preset-inspiration"].exists)
        XCTAssertTrue(app.buttons["tag-preset-project"].exists)
        capture(app, "T3-portfolio-presets")

        idea.tap()
        XCTAssertTrue(app.descendants(matching: .any)["tag-chip-idea"].waitForExistence(timeout: 5),
                      "the preset became a tag")
        XCTAssertFalse(app.buttons["tag-preset-idea"].exists, "a used preset leaves the strip")
        capture(app, "T4-idea-tagged")

        pill.tap()
        XCTAssertEqual(pill.label, "Destination: Personal", "a second tap flips back")
        XCTAssertFalse(app.buttons["tag-preset-project"].exists, "presets leave with Personal")
    }
}
