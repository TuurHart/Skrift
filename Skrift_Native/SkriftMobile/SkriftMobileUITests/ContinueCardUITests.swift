import XCTest

/// The Notes continue-listening card's three tap targets are INDEPENDENT —
/// regression net for the build-50 List-row hijack, where buttons in a List row
/// without `.borderless` fired their siblings (tapping × auto-played the book).
final class ContinueCardUITests: XCTestCase {

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-seedDemoMemos", "-seedAudiobookIdle"]
        app.launch()
        return app
    }

    /// × hides the card for today and must NOT start playback (no pill, no session).
    func testDismissDoesNotPlay() {
        let app = launch()
        let card = app.otherElements["continue-listening-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "seeded continue card missing")

        app.buttons["continue-card-dismiss"].tap()

        XCTAssertTrue(waitGone(card, timeout: 5), "card should hide on ×")
        // The pill only exists when a session started — × must never start one.
        XCTAssertFalse(app.otherElements["audiobook-mini-pill"].waitForExistence(timeout: 2),
                       "dismissing the card started a playback session (List-row tap hijack)")
    }

    /// ▶ starts the session: card yields to the pill.
    func testPlayShowsPill() {
        let app = launch()
        let card = app.otherElements["continue-listening-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))

        app.buttons["continue-card-play"].tap()

        XCTAssertTrue(app.otherElements["audiobook-mini-pill"].waitForExistence(timeout: 5),
                      "▶ should start a session and show the pill")
        XCTAssertTrue(waitGone(card, timeout: 5), "card should yield once the session is live")
    }

    private func waitGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            usleep(200_000)
        }
        return !element.exists
    }
}
