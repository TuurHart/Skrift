import XCTest

/// PROBE, not a regression test: drives Safari → Share → Skrift Dev and
/// screenshots every step to /tmp/skrift-share-shots so the share-extension
/// experience can be inspected exactly as a user sees it. Run explicitly via
/// -only-testing:SkriftMobileUITests/ShareFlowProbeUITests — excluded from
/// normal runs by the leading underscore-free but Safari-dependent nature.
final class ShareFlowProbeUITests: XCTestCase {

    private let shotDir = "/tmp/skrift-share-shots"

    override func setUpWithError() throws {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(atPath: shotDir, withIntermediateDirectories: true)
    }

    private func snap(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: "\(shotDir)/\(name).png"))
    }

    private func dumpTree(_ app: XCUIApplication, _ name: String) {
        let desc = app.debugDescription
        try? desc.write(toFile: "\(shotDir)/\(name).txt", atomically: true, encoding: .utf8)
    }

    func testSafariShareToSkrift() throws {
        // Opt-in only: drives Safari + needs live network (wikipedia.org) —
        // too environment-dependent for the regular gate. Run with:
        //   TEST_RUNNER_RUN_SHARE_PROBE=1 xcodebuild test ... \
        //     -only-testing:SkriftMobileUITests/ShareFlowProbeUITests
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_SHARE_PROBE"] == "1",
                          "share-flow probe is opt-in (set TEST_RUNNER_RUN_SHARE_PROBE=1)")

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.launch()
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 20))
        sleep(2)
        snap("01-safari-launched")

        // Navigate to a real page (title matters for the link card).
        let addressCapsule = safari.textFields["Address"].firstMatch
        if addressCapsule.waitForExistence(timeout: 5) {
            addressCapsule.tap()
        } else {
            // iOS 26 bottom bar variant
            let bar = safari.buttons["Address"].firstMatch
            if bar.waitForExistence(timeout: 5) { bar.tap() }
            else { dumpTree(safari, "tree-no-address"); snap("01b-no-address") }
        }
        sleep(1)
        safari.typeText("https://en.wikipedia.org/wiki/Stoicism\n")
        sleep(6)
        snap("02-page-loaded")

        // Share lives behind the "More" (•••) menu on iOS 26 Safari.
        let share = safari.buttons["ShareButton"].firstMatch
        if share.waitForExistence(timeout: 3) {
            share.tap()
        } else {
            let more = safari.buttons["More"].firstMatch
            XCTAssertTrue(more.waitForExistence(timeout: 5), "no More button")
            more.tap()
            sleep(1)
            snap("02c-more-menu")
            dumpTree(safari, "tree-more-menu")
            let shareItem = safari.buttons["Share"].firstMatch
            let shareCell = safari.cells["Share"].firstMatch
            let shareText = safari.staticTexts["Share"].firstMatch
            var sharedTapped = false
            for candidate in [shareItem, shareCell, shareText] {
                if candidate.waitForExistence(timeout: 3) { candidate.tap(); sharedTapped = true; break }
            }
            if !sharedTapped { dumpTree(safari, "tree-no-share"); snap("02b-no-share-button"); XCTFail("no share item") }
        }
        sleep(3)
        snap("03-share-sheet")
        dumpTree(safari, "tree-share-sheet")

        // Find Skrift Dev in the sheet (apps row cell or action row).
        let skriftCell = safari.cells["Skrift Dev"].firstMatch
        let skriftButton = safari.buttons["Skrift Dev"].firstMatch
        let skriftText = safari.staticTexts["Skrift Dev"].firstMatch

        var tapped = false
        for candidate in [skriftCell, skriftButton, skriftText] {
            if candidate.waitForExistence(timeout: 4) {
                candidate.tap(); tapped = true; break
            }
        }
        if !tapped {
            // Swipe the sheet up to reveal the action list, look again.
            safari.swipeUp()
            sleep(1)
            snap("03b-sheet-expanded")
            dumpTree(safari, "tree-sheet-expanded")
            for candidate in [skriftCell, skriftButton, skriftText] {
                if candidate.waitForExistence(timeout: 3) {
                    candidate.tap(); tapped = true; break
                }
            }
        }
        XCTAssertTrue(tapped, "Skrift Dev never appeared in the share sheet")
        sleep(3)
        snap("04-extension-open")
        dumpTree(safari, "tree-extension-open")

        // Try the annotation field.
        let annotation = safari.textViews.firstMatch
        if annotation.waitForExistence(timeout: 5) {
            annotation.tap()
            sleep(1)
            snap("05-keyboard-up")
            safari.typeText("Probe annotation: testing the share flow end to end.")
            sleep(1)
            snap("06-annotation-typed")
        } else {
            snap("05b-no-annotation-field")
        }

        // Tap significance circle 4 (0.4) if reachable.
        let circle = safari.otherElements["significance-circle-4"].firstMatch
        let circleBtn = safari.buttons["significance-circle-4"].firstMatch
        if circle.waitForExistence(timeout: 3) { circle.tap() }
        else if circleBtn.waitForExistence(timeout: 2) { circleBtn.tap() }
        sleep(1)
        snap("07-significance-set")

        // Save.
        let save = safari.buttons["capture-save-button"].firstMatch
        let saveByLabel = safari.buttons["Save"].firstMatch
        if save.waitForExistence(timeout: 3) { save.tap() }
        else if saveByLabel.waitForExistence(timeout: 3) { saveByLabel.tap() }
        else { dumpTree(safari, "tree-no-save"); snap("07b-no-save") }
        sleep(2)
        snap("08-after-save")

        // Open the app and let the inbox drain; see the capture row + detail.
        let app = XCUIApplication()
        app.launch()
        sleep(4)
        snap("09-app-launched")
        dumpTree(app, "tree-app-list")

        // Open the capture row (by its shared-link title) and inspect the detail.
        let captureRow = app.staticTexts["Stoicism - Wikipedia"].firstMatch
        if captureRow.waitForExistence(timeout: 5) {
            captureRow.tap()
            sleep(2)
            snap("10-capture-detail")
            dumpTree(app, "tree-capture-detail")
        } else {
            snap("10b-no-capture-row")
        }
    }
}
