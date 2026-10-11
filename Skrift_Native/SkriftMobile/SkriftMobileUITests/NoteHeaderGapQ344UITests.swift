import XCTest

/// Q344: the note body must start BELOW the last header row, whatever the destination row is
/// doing. The header lives inside the text view's scroll content and the text's top inset is
/// the header's measured height; the row expanding/collapsing (its own @State) or the Portfolio
/// preset chips appearing used to resize the header without re-measuring, so the body slid
/// under the Personal / Portfolio buttons. `note-body-first-line` is a DEBUG probe sitting at the
/// top of the first text line.
/// PNGs land in `SKRIFT_SHOT_DIR` when the runner passes one.
final class NoteHeaderGapQ344UITests: XCTestCase {

    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 1.0)
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SKRIFT_SHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    /// The body's first line starts below the destination row's bottom edge, with a gap.
    private func assertBodyBelowRow(_ app: XCUIApplication, _ label: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let row = app.descendants(matching: .any)["destination-row"]
        let probe = app.descendants(matching: .any)["note-body-first-line"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "\(label): row exists", file: file, line: line)
        XCTAssertTrue(probe.waitForExistence(timeout: 10), "\(label): probe exists", file: file, line: line)
        // The re-measure is async (geometry callback, then the next layout pass): poll briefly.
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, probe.frame.minY < row.frame.maxY + 4 {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertGreaterThanOrEqual(probe.frame.minY, row.frame.maxY + 4,
            "\(label): body first line (\(probe.frame.minY)) must sit below the destination row (\(row.frame.maxY)) with a gap",
            file: file, line: line)
        // The gap below the row is the SAME in every state (a summary card may sit in it).
        let gap = probe.frame.minY - row.frame.maxY
        if let first = firstGap {
            XCTAssertEqual(gap, first, accuracy: 2, "\(label): gap below the row changed", file: file, line: line)
        } else { firstGap = gap }
    }

    private var firstGap: CGFloat?

    func testBodyStaysBelowDestinationRowWhileToggling() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedPolished", "-selectFirstMemo", "-destinationsOn"]
        if let theme = ProcessInfo.processInfo.environment["SKRIFT_THEME"] {
            app.launchArguments += ["-skipOnboarding", "-appTheme", theme]
        }
        app.launch()

        let chip = app.buttons["destination-chip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 20))
        assertBodyBelowRow(app, "collapsed personal")
        capture(app, "Q344-1-collapsed")

        chip.tap()
        XCTAssertTrue(app.buttons["destination-portfolio"].waitForExistence(timeout: 5))
        assertBodyBelowRow(app, "expanded")
        capture(app, "Q344-2-expanded")

        for round in 1...3 {
            app.buttons["destination-portfolio"].tap()
            XCTAssertTrue(app.buttons["tag-preset-idea"].waitForExistence(timeout: 5), "presets on Portfolio")
            assertBodyBelowRow(app, "round \(round) portfolio collapsed (presets)")
            if round == 1 { capture(app, "Q344-3-portfolio-collapsed") }

            app.buttons["destination-chip"].tap()
            XCTAssertTrue(app.buttons["destination-personal"].waitForExistence(timeout: 5))
            assertBodyBelowRow(app, "round \(round) expanded on portfolio")
            if round == 1 { capture(app, "Q344-4-expanded-on-portfolio") }

            app.buttons["destination-personal"].tap()
            XCTAssertTrue(app.buttons["destination-chip"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["tag-preset-idea"].exists, "presets leave with Personal")
            assertBodyBelowRow(app, "round \(round) personal collapsed")

            app.buttons["destination-chip"].tap()
            XCTAssertTrue(app.buttons["destination-portfolio"].waitForExistence(timeout: 5))
            assertBodyBelowRow(app, "round \(round) expanded on personal")
        }
        capture(app, "Q344-5-after-toggling")
    }
}
