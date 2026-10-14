import XCTest
@testable import SkriftMobile

/// C274 / R87 `voice-annotation-empty-transcript-kept`: a voice annotation whose
/// transcription returns no text keeps its clip and says "No words heard"; the success
/// haptic never deletes it. (`CaptureVoiceAnnotate` used to remove the clip and fire
/// the success haptic unconditionally.)
final class EmptyTranscriptKeptTests: XCTestCase {

    func testEmptyLiveAndFullKeepsTheClipAndFiresNoSuccess() {
        let o = VoiceAnnotationOutcome.resolve(live: "", full: "")
        XCTAssertEqual(o, .keepNoWordsHeard)
        XCTAssertFalse(o.deletesClip)
        XCTAssertFalse(o.firesSuccessHaptic)
    }

    func testWhitespaceOnlyCountsAsEmpty() {
        XCTAssertEqual(VoiceAnnotationOutcome.resolve(live: " \n", full: "  "), .keepNoWordsHeard)
    }

    func testFullPassThrowingWithEmptyLiveCaptionStillKeeps() {
        XCTAssertEqual(VoiceAnnotationOutcome.resolve(live: "", full: nil), .keepNoWordsHeard)
    }

    func testFullPassWinsOverLiveCaption() {
        XCTAssertEqual(VoiceAnnotationOutcome.resolve(live: "hello wor", full: " hello world "),
                       .append("hello world"))
    }

    func testLiveCaptionIsTheFallbackWhenTheFullPassIsEmpty() {
        let o = VoiceAnnotationOutcome.resolve(live: "from the caption", full: "")
        XCTAssertEqual(o, .append("from the caption"))
        XCTAssertTrue(o.deletesClip)
        XCTAssertTrue(o.firesSuccessHaptic)
    }

    func testNoWordsHeardLineText() {
        XCTAssertEqual(VoiceAnnotationOutcome.noWordsHeardLine, "No words heard")
    }

    /// The view must route through the outcome: no unconditional remove of the clip.
    func testViewSourceNoLongerDeletesUnconditionally() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Features/MemoDetail/CaptureVoiceAnnotate.swift")
        let src = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(src.contains("VoiceAnnotationOutcome.resolve"))
        XCTAssertTrue(src.contains("if outcome.deletesClip"))
    }
}
