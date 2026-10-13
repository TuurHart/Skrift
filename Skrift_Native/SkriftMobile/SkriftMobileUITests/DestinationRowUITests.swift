import XCTest

/// Drives the SHARED `DestinationRowView` on a real note and writes PNGs, because a
/// destination row reviewed from source is a destination row nobody has looked at
/// (memory `feedback_ui_review_vision`). Two states of the D204 tap pill:
///
///   B1  Personal      — the quiet accent pill
///   B2  Portfolio     — the amber pill, after one tap
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

        let pill = app.buttons["destination-pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 20), "the pill is the whole control (D204)")
        XCTAssertEqual(pill.label, "Destination: Personal")
        capture(app, "B1-resting-personal")

        pill.tap()
        XCTAssertEqual(pill.label, "Destination: Portfolio", "one tap flips it in place")
        XCTAssertEqual(app.buttons.matching(identifier: "destination-pill").count, 1, "nothing opens")
        capture(app, "B2-resting-portfolio")
    }
}
