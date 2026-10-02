import XCTest

/// Q121 visual check: the iPad note dock shows back · play · forward (the Mac order) and the
/// speed button reads the shared label. Run on an iPad destination; PNGs land in
/// `plan/reads/note-p-player/` (via `SKRIFT_SHOT_DIR` or the xcresult attachments).
final class PlayerQ121ScreenshotUITests: XCTestCase {

    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.8)
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SKRIFT_SHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func testIPadDockTransportOrder() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedPolished", "-selectFirstMemo"]
        app.launch()
        let play = el(app, "play-button")
        XCTAssertTrue(play.waitForExistence(timeout: 30), "dock missing")
        capture(app, "ipad-dock-rest")
        let back = el(app, "skip-back-button")
        let fwd = el(app, "skip-fwd-button")
        print("Q121 frames back=\(back.frame) play=\(play.frame) fwd=\(fwd.frame)")
        if app.windows.firstMatch.frame.width > 700 {
            XCTAssertLessThan(back.frame.minX, play.frame.minX, "iPad dock: back skip must sit left of play")
            XCTAssertLessThan(play.frame.minX, fwd.frame.minX, "iPad dock: forward skip must sit right of play")
        }
        let speed = el(app, "speed-button")
        XCTAssertTrue(speed.exists)
        speed.tap()
        capture(app, "ipad-dock-speed-1.25x")
        print("Q121 speed label after one tap = \(speed.label)")
    }
}
