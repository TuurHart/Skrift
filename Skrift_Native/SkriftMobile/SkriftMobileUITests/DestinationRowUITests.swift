import XCTest

/// Drives the SHARED `DestinationRowView` on a real note and writes PNGs, because a
/// destination row reviewed from source is a destination row nobody has looked at
/// (memory `feedback_ui_review_vision`). Three states, matching the signed mock
/// `mocks/note-destination-tags.html` version B:
///
///   B1  resting, Personal      — a quiet chip, no folder, no notice
///   B3  expanded               — PRIVATE | PORTFOLIO over four segments
///   B2  resting, Idea          — the amber chip PLUS the folder it writes into
///
/// PNGs land in `SKRIFT_SHOT_DIR` when the runner passes one, so the orchestrator can
/// open them; otherwise they are attached to the result bundle as usual.
final class DestinationRowUITests: XCTestCase {

    private func shotDir() -> URL? {
        ProcessInfo.processInfo.environment["SKRIFT_SHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        // Let the layout settle before the shutter. A screenshot taken the instant an
        // element exists catches the chips FlowLayout mid-pass, which reads as a clipping
        // bug that isn't there.
        Thread.sleep(forTimeInterval: 1.0)
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = shotDir() {
            try? shot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
        }
    }

    func testDestinationRowStates() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedPolished", "-selectFirstMemo",
                               "-destinationsOn"]
        app.launch()

        let chip = app.buttons["destination-chip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 20),
                      "the collapsed chip is the resting state of the row")
        capture(app, "B1-resting-personal")

        chip.tap()
        let idea = app.buttons["destination-idea"]
        XCTAssertTrue(idea.waitForExistence(timeout: 5), "tapping the chip expands to all four")
        XCTAssertTrue(app.buttons["destination-personal"].exists)
        XCTAssertTrue(app.buttons["destination-project"].exists)
        XCTAssertTrue(app.buttons["destination-inspiration"].exists)
        capture(app, "B3-expanded")

        idea.tap()
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "picking collapses it again")
        XCTAssertFalse(app.buttons["destination-idea"].exists, "…back to one chip, not four")
        capture(app, "B2-resting-idea")
    }
}
