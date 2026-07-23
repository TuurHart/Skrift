import XCTest

/// Device-verify workhorse (📖 round 8, 2026-07-23): launches the REAL app (real data
/// container) with `-resumeBook` and simply HOLDS — the test harness disables auto-lock
/// for its duration, which is exactly what the 13 h Odyssey's schema-5 re-align needs
/// (~2–3 min of the app staying alive; plain `devicectl launch` runs died at every
/// auto-lock). Not part of any verification suite — run it alone, on demand:
/// `-only-testing:SkriftMobileUITests/OdysseyAlignHoldUITests`.
final class OdysseyAlignHoldUITests: XCTestCase {
    func testHoldWhileBookRealigns() throws {
        // Env-gated like OdysseyRealDataDiagnostics: a 5-minute hold must never ride a
        // normal suite run. Set SKRIFT_DEVICE_HOLD=1 (TEST_RUNNER_ prefix via xcodebuild).
        try XCTSkipIf(ProcessInfo.processInfo.environment["SKRIFT_DEVICE_HOLD"] != "1",
                      "on-demand device-verify hold only")
        let app = XCUIApplication()
        app.launchArguments = ["-resumeBook"]
        app.launch()
        // The align logs its completion to the devlog; the orchestrating session
        // polls that. Here we only keep the process alive and the screen awake.
        for _ in 0..<10 {
            sleep(30)
            XCTAssertEqual(app.state, .runningForeground, "app must stay alive for the re-align")
        }
    }
}
