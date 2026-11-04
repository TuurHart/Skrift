import XCTest

/// Q545 visual check against mock Q542 "Picture sizes" (phone): a note with a wide and a tall photo, a
/// video, a PDF and a DXF, small (the default) and large, plus the hold menu. Screenshots land in
/// `SKRIFT_SHOT_DIR` (pass `TEST_RUNNER_SKRIFT_SHOT_DIR`). Invented note, placeholder pictures.
final class PictureSizesQ545ScreenshotUITests: XCTestCase {

    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 1.0)
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

    private func openNote(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedPictureSizes", "-selectFirstMemo", "-skipOnboarding",
                               "-routeViaList", "-appTheme", "light"] + extra
        app.launch()
        let editor = app.textViews["transcript-editor"]
        if !editor.waitForExistence(timeout: 6) {
            let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
            if row.waitForExistence(timeout: 10) { row.tap() }
        }
        XCTAssertTrue(editor.waitForExistence(timeout: 25), "editor missing")
        Thread.sleep(forTimeInterval: 2.0)   // the video poster is made off the main thread
        return app
    }

    func testSmallByDefault() {
        let app = openNote()
        capture(app, "q545-1-small")
        app.swipeUp()
        capture(app, "q545-2-small-scrolled")
    }

    func testAllLarge() {
        let app = openNote(["-seedAttachmentLarge"])
        capture(app, "q545-3-large")
        app.swipeUp()
        capture(app, "q545-4-large-scrolled")
    }

    func testTheHoldMenuOnAPhotoHasTheSizeSwitchFirst() {
        let app = openNote()
        // The wide photo sits under the first paragraph, near the top.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.36)).press(forDuration: 0.8)
        capture(app, "q545-5-hold-menu")
    }
}
