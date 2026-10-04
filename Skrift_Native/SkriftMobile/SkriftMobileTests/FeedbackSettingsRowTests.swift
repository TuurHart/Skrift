import XCTest
@testable import SkriftMobile

/// Q301 / D179: the Settings "Send feedback" row opens FeedbackKit (the old Mail-based
/// screen is deleted). The row's action is `FeedbackKitWiring.openFeedback()`, which goes
/// through the `presenter` seam (defaults to `FeedbackKit.present()`).
@MainActor
final class FeedbackSettingsRowTests: XCTestCase {

    func testOpenFeedbackCallsTheKitPresenter() {
        let original = FeedbackKitWiring.presenter
        defer { FeedbackKitWiring.presenter = original }
        var calls = 0
        FeedbackKitWiring.presenter = { calls += 1 }
        FeedbackKitWiring.openFeedback()
        XCTAssertEqual(calls, 1)
    }

    func testSettingsRowIsWiredToTheKitNotTheOldScreen() throws {
        let features = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Features")
        let settings = try String(contentsOf: features.appendingPathComponent("Settings/SettingsView.swift"),
                                  encoding: .utf8)
        XCTAssertTrue(settings.contains("FeedbackKitWiring.openFeedback()"))
        XCTAssertFalse(settings.contains("FeedbackCaptureView"))
        for gone in ["FeedbackCaptureView", "FeedbackMailComposer", "FeedbackStore"] {
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: features.appendingPathComponent("Feedback/\(gone).swift").path), "\(gone) should be deleted")
        }
    }
}
