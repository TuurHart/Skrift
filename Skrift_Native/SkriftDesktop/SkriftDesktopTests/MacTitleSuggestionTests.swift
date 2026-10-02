import XCTest

/// Q115 / C181 / C25: the Mac "From recording" title is the transcript's first line cut to
/// 60, never the filename — a phone memo's `memo_<uuid>.m4a` must not become the title.
final class MacTitleSuggestionTests: XCTestCase {

    func testMemoFilenameNeverProducesTheTitle() {
        let name = "memo_\(UUID().uuidString).m4a"
        let pf = PipelineFile(id: UUID().uuidString, filename: name, path: "", size: 1, sourceType: .audio)
        pf.transcript = "Remember to call the dentist tomorrow morning."
        let value = MacTitleSuggestion.fromRecording(transcript: pf.transcript)
        XCTAssertEqual(value, "Remember to call the dentist tomorrow morning.")
        XCTAssertFalse(value.hasPrefix("memo_"))
        XCTAssertNotEqual(value, SkriftFormat.cleanFilename(name))
    }

    func testNoTranscriptOffersNothing() {
        XCTAssertEqual(MacTitleSuggestion.fromRecording(transcript: nil), "")
        XCTAssertEqual(MacTitleSuggestion.fromRecording(transcript: "  \n \n"), "")
    }

    func testCutsToSixtyAndStripsMarkers() {
        let long = String(repeating: "word ", count: 30)
        XCTAssertLessThanOrEqual(MacTitleSuggestion.fromRecording(transcript: long).count, 60)
        XCTAssertEqual(MacTitleSuggestion.fromRecording(transcript: "**Speaker 1:** hello [[Anna]] there"),
                       "Speaker 1: hello Anna there")
        XCTAssertEqual(MacTitleSuggestion.fromRecording(transcript: "\n\n  second\nthird"), "second")
    }

    func testChooserOnlyWhenTheTwoDiffer() {
        XCTAssertTrue(MacTitleSuggestion.showChooser(suggested: "A plan", recording: "Remember the dentist"))
        XCTAssertFalse(MacTitleSuggestion.showChooser(suggested: "Same", recording: "Same"))
        XCTAssertFalse(MacTitleSuggestion.showChooser(suggested: "", recording: "x"))
        XCTAssertFalse(MacTitleSuggestion.showChooser(suggested: "x", recording: ""))
    }
}
