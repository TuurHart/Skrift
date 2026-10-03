import XCTest
import AVFoundation

/// Q164 (C222/C224, recsj-014): "a take with no signal is a dead take" is ONE rule in
/// `RecordingCore`, called by both the Mac recorder and the phone's. The phone has the same
/// class name in `SkriftMobileTests`.
final class DeadTakeVerdictTests: XCTestCase {

    func testATakeWithSignalAndAudioIsKept() {
        XCTAssertNil(RecordingCore.deadTakeVerdict(fileBytes: 40_000, sawSignal: true, deviceName: "Mic"))
    }

    func testBigFileButNeverAnySignalIsRecordedSilence() {
        XCTAssertEqual(RecordingCore.deadTakeVerdict(fileBytes: 40_000, sawSignal: false, deviceName: "Chonky pods"),
                       .recordedSilence("Chonky pods"))
    }

    func testTinyFileIsNothingCaptured() {
        XCTAssertEqual(RecordingCore.deadTakeVerdict(fileBytes: 1024, sawSignal: true, deviceName: "Mic"),
                       .nothingCaptured("Mic"), "1024 bytes is the boundary: ≤ 1024 is dead")
        XCTAssertEqual(RecordingCore.deadTakeVerdict(fileBytes: 0, sawSignal: false, deviceName: "Mic"),
                       .nothingCaptured("Mic"))
    }

    func testJustOverTheBoundaryWithSignalIsKept() {
        XCTAssertNil(RecordingCore.deadTakeVerdict(fileBytes: 1025, sawSignal: true, deviceName: "Mic"))
    }

    func testFailFastIsOneAndAHalfSecondsWithNoBuffer() {
        XCTAssertEqual(RecordingCore.failFastSeconds, 1.5)
        XCTAssertTrue(RecordingCore.shouldFailFast(elapsedSinceStart: 1.5, hasReceivedBuffer: false))
        XCTAssertFalse(RecordingCore.shouldFailFast(elapsedSinceStart: 1.4, hasReceivedBuffer: false))
        XCTAssertFalse(RecordingCore.shouldFailFast(elapsedSinceStart: 9, hasReceivedBuffer: true))
    }

    func testPermissionStatusMapsToTheTypedRefusal() {
        XCTAssertNil(RecordingCore.permissionRefusal(for: .authorized))
        XCTAssertNil(RecordingCore.permissionRefusal(for: .notDetermined), "not asked yet: the prompt is still to come")
        XCTAssertEqual(RecordingCore.permissionRefusal(for: .denied), .permissionDenied)
        XCTAssertEqual(RecordingCore.permissionRefusal(for: .restricted), .permissionRestricted)
    }

    func testDeniedAndRestrictedOfferSettingsOthersDoNot() {
        XCTAssertTrue(RecordingCore.Refusal.permissionDenied.fixedInPrivacySettings)
        XCTAssertTrue(RecordingCore.Refusal.permissionRestricted.fixedInPrivacySettings)
        XCTAssertFalse(RecordingCore.Refusal.recordedSilence("x").fixedInPrivacySettings)
    }

    func testPhoneWordingNamesTheDeviceAndNeverSaysMac() {
        let all: [RecordingCore.Refusal] = [
            .noInputDevice, .permissionDenied, .permissionRestricted, .noUsableFormat,
            .engineFailed("boom"), .nothingCaptured("AirPods"), .recordedSilence("AirPods"),
        ]
        for r in all {
            XCTAssertFalse(r.phoneMessage.isEmpty)
            XCTAssertFalse(r.phoneMessage.contains("Mac"), "\(r) phone wording must not say Mac")
        }
        XCTAssertTrue(RecordingCore.Refusal.recordedSilence("AirPods").phoneMessage.contains("AirPods"))
    }

    func testMacRecorderUsesTheSharedType() {
        XCTAssertEqual(MacRecorder.Refusal.permissionDenied, RecordingCore.Refusal.permissionDenied)
        XCTAssertTrue(MacRecorder.shouldFailFast(elapsedSinceStart: 1.5, hasReceivedBuffer: false))
    }
}
