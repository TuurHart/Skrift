import XCTest

/// Q85 visual check: the note header's rating pill on a voice note (seedPolished, starts
/// Useful) and a typed note (synthetic corpus, first note), tapped through the full cycle
/// Not rated → Passing → Useful → Important → Not rated. Screenshots + measured frames land
/// in `plan/reads/header-q85/` (via `SKRIFT_SHOT_DIR` or the xcresult attachments).
final class HeaderQ85UITests: XCTestCase {

    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.7)
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SKRIFT_SHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    private var corpusPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test-fixtures/corpus").path
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func frames(_ app: XCUIApplication, _ tag: String) {
        for id in ["rating-pill", "detail-lifecycle-line", "destination-chip", "add-tag-button"] {
            let e = el(app, id)
            if e.exists { print("Q85 \(tag) \(id) frame=\(e.frame)") }
        }
    }

    private func cycle(_ app: XCUIApplication, prefix: String, taps: Int) {
        let pill = app.buttons["rating-pill"]
        for i in 1...taps {
            pill.tap()
            capture(app, "\(prefix)-tap\(i)")
            frames(app, "\(prefix)-tap\(i)")
        }
    }

    func testVoiceNotePillCycle() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedPolished", "-selectFirstMemo", "-destinationsOn"]
        app.launch()
        XCTAssertTrue(app.buttons["rating-pill"].waitForExistence(timeout: 20), "pill missing")
        capture(app, "voice-rest-useful")
        frames(app, "voice-rest")
        // Useful -> Important -> Not rated (fading line appears) -> Passing
        cycle(app, prefix: "voice", taps: 3)
    }

    func testTypedNotePillCycle() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-corpus", corpusPath, "-selectFirstMemo", "-destinationsOn"]
        app.launch()
        // The list opens first on the phone; open the first typed note.
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Call the clay supplier'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "corpus row missing")
        row.tap()
        XCTAssertTrue(app.buttons["rating-pill"].waitForExistence(timeout: 20), "pill missing")
        capture(app, "typed-rest")
        frames(app, "typed-rest")
        cycle(app, prefix: "typed", taps: 4)
    }
}
