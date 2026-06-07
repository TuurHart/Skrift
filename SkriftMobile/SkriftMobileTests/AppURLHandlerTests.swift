import XCTest
@testable import SkriftMobile

@MainActor
final class AppURLHandlerTests: XCTestCase {

    func testRecordDeepLinkRequestsStart() {
        let before = RecordingIntentBridge.shared.startRequestID
        AppURLHandler.handle(URL(string: "skrift://record")!)
        XCTAssertEqual(RecordingIntentBridge.shared.startRequestID, before + 1,
                       "skrift://record should request a recording start")
    }

    func testUnknownSchemeIsIgnored() {
        let before = RecordingIntentBridge.shared.startRequestID
        AppURLHandler.handle(URL(string: "skrift://somethingelse")!)
        AppURLHandler.handle(URL(string: "https://example.com")!)
        XCTAssertEqual(RecordingIntentBridge.shared.startRequestID, before,
                       "non-record URLs must not start recording")
    }

    func testNonAudioFileIsIgnored() {
        // A non-audio file URL must not start recording (and not crash).
        let before = RecordingIntentBridge.shared.startRequestID
        AppURLHandler.handle(URL(fileURLWithPath: "/tmp/notes.txt"))
        XCTAssertEqual(RecordingIntentBridge.shared.startRequestID, before)
    }
}
