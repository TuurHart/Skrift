import XCTest

/// Q554: tapping Done leaves the pictures in the order they were added. The note is opened from the
/// list (a real push), two drawn pictures go in through Choose Photo, and the editor's text is read
/// before and after Done. The file leg needs the system document picker, which a UI test cannot
/// drive; `NoteBodyBlockOrderTests` and `BodyCommitKeepsBlockOrderTests` cover it on the real
/// coordinator. Screenshots land in `SKRIFT_SHOT_DIR` (pass `TEST_RUNNER_SKRIFT_SHOT_DIR`).
final class BlockOrderQ554UITests: XCTestCase {

    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SKRIFT_SHOT_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    private func editorValue(_ app: XCUIApplication) -> String {
        (app.textViews["transcript-editor"].value as? String) ?? ""
    }

    func testDoneKeepsTheOrderOfThePicturesAdded() {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedPhotoMoveVoice", "-skipOnboarding", "-routeViaList",
                               "-appTheme", "light", "-fakePhotoPick"]
        app.launch()
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "list row missing")
        row.tap()
        let editor = app.textViews["transcript-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 25), "editor missing")
        Thread.sleep(forTimeInterval: 1.5)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.30)).tap()
        XCTAssertTrue(app.buttons["accessory-photo"].waitForExistence(timeout: 5), "keyboard bar missing")
        for _ in 0..<2 {
            app.buttons["accessory-photo"].tap()
            let choose = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Choose Photo")).firstMatch
            XCTAssertTrue(choose.waitForExistence(timeout: 5), "attach menu missing")
            choose.tap()
            Thread.sleep(forTimeInterval: 1.5)
        }
        capture(app, "q554-1-before-done")
        let before = editorValue(app)

        app.buttons["accessory-done"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        capture(app, "q554-2-after-done")
        let after = editorValue(app)

        func pictures(_ s: String) -> Int { s.filter { $0 == "\u{FFFC}" }.count }
        XCTAssertEqual(pictures(after), pictures(before), "Done kept every picture")
        XCTAssertEqual(after.replacingOccurrences(of: "\n", with: ""), before.replacingOccurrences(of: "\n", with: ""),
                       "Done kept the text and the pictures in the same order")
    }
}
