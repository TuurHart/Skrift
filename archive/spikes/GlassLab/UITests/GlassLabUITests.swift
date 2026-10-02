import XCTest

/// Screenshots the glass scenes so the effect can be eyeballed from the xcresult —
/// the whole point of the lab is that I can drive it fully myself.
final class GlassLabUITests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Four bars (regular / clear / ultraThin / regularMaterial) over a vivid striped
    /// backdrop — directly comparable.
    func testStaticGlass() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-scene", "static"]
        app.launch()
        Thread.sleep(forTimeInterval: 1.0)   // let glass settle
        snap("lab-static")
    }

    /// glassEffect bar via safeAreaInset over a colorful scroll list — mirrors Skrift.
    /// Scroll so rows pass under the bar, then capture.
    func testScrollGlass() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-scene", "scroll"]
        app.launch()
        Thread.sleep(forTimeInterval: 0.5)
        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)
        snap("lab-scroll")
    }

    /// Faithful Skrift replica (dark transcript + photo) with the exact bottomChrome.
    /// Capture text under the bar, then scroll the photo under it.
    func testSkrift() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-scene", "skrift"]
        app.launch()
        Thread.sleep(forTimeInterval: 0.6)
        snap("lab-skrift-text")          // dark transcript under the bar
        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.6)
        snap("lab-skrift-photo")         // photo scrolled under the bar
    }
}
