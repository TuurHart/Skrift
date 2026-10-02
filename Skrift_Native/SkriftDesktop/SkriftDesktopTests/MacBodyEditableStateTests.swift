import XCTest

/// Q124 (C173): the Mac note body is read-only while its transcription runs — the phone's
/// `NoteBody.mode` precedence on the Mac's step columns.
final class MacBodyEditableStateTests: XCTestCase {
    func testIdleNoteIsEditable() {
        for s in [StepStatus.pending, .done, .error, .skipped] {
            let m = MacBodyEditableState.of(isPlaying: false, transcribe: s)
            XCTAssertEqual(m, .editing, "\(s)")
            XCTAssertTrue(m.isEditable)
        }
    }

    func testTranscribingIsReadOnly() {
        let m = MacBodyEditableState.of(isPlaying: false, transcribe: .processing)
        XCTAssertEqual(m, .reading)
        XCTAssertFalse(m.isEditable)
    }

    func testSplitRunIsReadOnly() {
        let m = MacBodyEditableState.of(isPlaying: false, transcribe: .done, splitting: true)
        XCTAssertEqual(m, .reading)
        XCTAssertFalse(m.isEditable)
    }

    func testPlaybackWinsOverEverything() {
        XCTAssertEqual(MacBodyEditableState.of(isPlaying: true, transcribe: .processing, splitting: true), .playing)
        XCTAssertFalse(MacBodyEditableState.playing.isEditable)
    }

    func testPillOnlyWhileTranscribing() {
        XCTAssertEqual(MacBodyEditableState.pillLabel(transcribe: .processing), "Transcribing")
        for s in [StepStatus.pending, .done, .error, .skipped] {
            XCTAssertNil(MacBodyEditableState.pillLabel(transcribe: s))
        }
    }
}
