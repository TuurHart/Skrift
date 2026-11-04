import XCTest

/// Q550: the keyboard bar's Undo walks back through everything done in a note, a typed word, a
/// picture, another typed word, and Redo walks forward again. The note is opened from the list
/// (a real push). Screenshots land in `SKRIFT_SHOT_DIR` (pass `TEST_RUNNER_SKRIFT_SHOT_DIR`).
final class UndoSequenceQ550UITests: XCTestCase {

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

    func testUndoWalksBackThroughTextPhotoTextAndRedoForward() {
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

        // Caret into the first paragraph; the keyboard bar appears.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.30)).tap()
        let undo = app.buttons["accessory-undo"]
        let redo = app.buttons["accessory-redo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "keyboard bar missing")
        let start = editorValue(app)
        capture(app, "q550-1-start")

        app.typeText(" ALPHA")
        Thread.sleep(forTimeInterval: 0.6)
        let afterFirstWord = editorValue(app)
        XCTAssertTrue(afterFirstWord.contains("ALPHA"), "the first word was typed: \(afterFirstWord)")

        // A picture from the bar's attach menu.
        app.buttons["accessory-photo"].tap()
        let choose = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Choose Photo")).firstMatch
        XCTAssertTrue(choose.waitForExistence(timeout: 5), "attach menu missing")
        choose.tap()
        Thread.sleep(forTimeInterval: 1.5)
        let afterPhoto = editorValue(app)
        XCTAssertNotEqual(afterPhoto, afterFirstWord, "the picture landed in the note")

        app.typeText("OMEGA")
        Thread.sleep(forTimeInterval: 0.6)
        let end = editorValue(app)
        XCTAssertTrue(end.contains("OMEGA"), "the second word was typed: \(end)")
        capture(app, "q550-2-typed-photo-typed")

        // Undo, step by step, until the bar says there is nothing left.
        var back: [String] = []
        for i in 0..<12 where undo.isEnabled {
            undo.tap()
            Thread.sleep(forTimeInterval: 0.5)
            back.append(editorValue(app))
            if i == 0 { capture(app, "q550-3-undo-1") }
            if i == 1 { capture(app, "q550-4-undo-2") }
        }
        capture(app, "q550-5-undo-all")
        XCTAssertFalse(back.isEmpty, "Undo was available")
        XCTAssertFalse(back.last?.contains("ALPHA") ?? true, "Undo reached before the first word: \(back)")
        XCTAssertFalse(back.last?.contains("OMEGA") ?? true)
        XCTAssertEqual(back.last, start, "Undo walked all the way back to the note as it was; trail \(back)")
        XCTAssertTrue(back.contains(afterFirstWord), "Undo stopped on the text before the picture: \(back)")
        XCTAssertTrue(back.contains(afterPhoto), "Undo stopped on the text with the picture: \(back)")

        // Redo, step by step, back to the end.
        var forward: [String] = []
        for i in 0..<12 where redo.isEnabled {
            redo.tap()
            Thread.sleep(forTimeInterval: 0.5)
            forward.append(editorValue(app))
            if i == 0 { capture(app, "q550-6-redo-1") }
        }
        capture(app, "q550-7-redo-all")
        XCTAssertEqual(forward.last, end, "Redo walked all the way forward; trail \(forward)")
    }
}
