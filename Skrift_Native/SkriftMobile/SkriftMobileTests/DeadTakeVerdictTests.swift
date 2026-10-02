import XCTest
import AVFoundation
@testable import SkriftMobile

/// Q164 (C222/C224, recsj-014): the phone calls the same dead-take verdict as the Mac
/// (`RecordingCore.deadTakeVerdict`) and shows the Mac's typed refusal. The simulator cannot
/// prove the mic path; the device check stays with Tuur.
@MainActor
final class DeadTakeVerdictTests: XCTestCase {

    func testSignalAndAudioKeepsTheTake() {
        XCTAssertNil(RecordingCore.deadTakeVerdict(fileBytes: 40_000, sawSignal: true, deviceName: "iPhone Microphone"))
    }

    func testLongSilentTakeIsADeadTake() {
        XCTAssertEqual(RecordingCore.deadTakeVerdict(fileBytes: 400_000, sawSignal: false, deviceName: "iPhone Microphone"),
                       .recordedSilence("iPhone Microphone"))
    }

    func testEmptyFileIsNothingCaptured() {
        XCTAssertEqual(RecordingCore.deadTakeVerdict(fileBytes: 900, sawSignal: true, deviceName: "AirPods"),
                       .nothingCaptured("AirPods"))
    }

    func testDeniedAndRestrictedMicOfferOpenSettings() {
        XCTAssertEqual(RecordingCore.permissionRefusal(for: .denied), .permissionDenied)
        XCTAssertEqual(RecordingCore.permissionRefusal(for: .restricted), .permissionRestricted)
        XCTAssertNil(RecordingCore.permissionRefusal(for: .authorized))
        XCTAssertNil(RecordingCore.permissionRefusal(for: .notDetermined))
        XCTAssertTrue(RecordingCore.Refusal.permissionDenied.fixedInPrivacySettings)
        XCTAssertTrue(RecordingCore.Refusal.permissionRestricted.fixedInPrivacySettings)
        XCTAssertFalse(RecordingCore.Refusal.recordedSilence("x").fixedInPrivacySettings)
    }

    func testPhoneWordingNeverSaysMac() {
        let all: [RecordingCore.Refusal] = [
            .noInputDevice, .permissionDenied, .permissionRestricted, .noUsableFormat,
            .engineFailed("boom"), .nothingCaptured("AirPods"), .recordedSilence("AirPods"),
        ]
        for r in all { XCTAssertFalse(r.phoneMessage.contains("Mac"), "\(r)") }
    }

    /// A mock take (no mic involved) never carries a refusal, so UI tests and the seeded
    /// transcript path keep working.
    func testMockTakeCarriesNoRefusal() throws {
        let service = LiveRecordingService(mock: true, liveTranscription: false)
        try service.start()
        XCTAssertNil(service.startRefusal)
        let result = try XCTUnwrap(service.stop())
        XCTAssertNil(result.refusal)
        try? FileManager.default.removeItem(at: result.url)
    }
}
