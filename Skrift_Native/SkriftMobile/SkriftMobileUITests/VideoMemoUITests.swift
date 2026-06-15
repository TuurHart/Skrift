import XCTest

/// Video-import memo: with `-seedVideoMemo` a memo carrying a REAL landscape
/// (16:9) frame is seeded, so we can (1) assert the video source glyph renders
/// and (2) screenshot the row + detail to /tmp/skrift-video-shots to eyeball the
/// thumbnail's aspect handling (the "landscape squished into a square" bug — the
/// seeded frame draws a centered circle that distorts to an ellipse if squished).
final class VideoMemoUITests: XCTestCase {

    private let shotDir = "/tmp/skrift-video-shots"

    override func setUpWithError() throws {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(atPath: shotDir, withIntermediateDirectories: true)
    }

    private func snap(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: "\(shotDir)/\(name).png"))
    }

    func testVideoMemoShowsSourceGlyphAndThumbnail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedVideoMemo", "-skipOnboarding", "-appTheme", "dark"]
        app.launch()

        // The video source is shown on the row (bug #3). The leading glyph is a
        // decorative SF Symbol XCUITest can't reliably query, so assert the
        // user-visible "Video" source chip — it only renders for a video import.
        // (The glyph itself is screenshot-verified in 01-list.png.)
        let videoChip = app.staticTexts["Video"].firstMatch
        XCTAssertTrue(videoChip.waitForExistence(timeout: 10), "video source chip missing on the memo row")
        snap("01-list")

        // Open the memo → the inline frame embed (bug #2 aspect check).
        let row = app.descendants(matching: .any).matching(identifier: "memo-row-0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        sleep(1)
        snap("02-detail")
    }
}
