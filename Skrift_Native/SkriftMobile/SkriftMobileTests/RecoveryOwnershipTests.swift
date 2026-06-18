import XCTest
@testable import SkriftMobile

/// Cross-device guard: the stuck-transcription recovery must only act on memos THIS
/// device recorded (or legacy memos with no id) — never re-transcribe a memo that
/// arrived from another device still `.transcribing` (that device owns it; its
/// transcript syncs). Otherwise the two devices race and can clobber the transcript.
@MainActor
final class RecoveryOwnershipTests: XCTestCase {

    func testOwnsForRecovery() {
        let me = "DEVICE-A"
        XCTAssertTrue(MemoSaver.ownsForRecovery(nil, thisDevice: me),
                      "legacy/local memo (no id) is recoverable")
        XCTAssertTrue(MemoSaver.ownsForRecovery("DEVICE-A", thisDevice: me),
                      "a memo this device recorded is recoverable")
        XCTAssertFalse(MemoSaver.ownsForRecovery("DEVICE-B", thisDevice: me),
                       "a memo another device recorded must NOT be re-transcribed here")
    }

    func testNewMemoIsStampedWithThisDevice() {
        let memo = Memo(audioFilename: "memo_x.m4a")
        XCTAssertEqual(memo.recordingDeviceID, DeviceID.current(),
                       "a freshly created memo is stamped with this device's id")
    }
}
