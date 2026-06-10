import XCTest
@testable import SkriftMobile

/// The list rows' quick "Copy" content rule: transcript first, title as the
/// fallback, nil when the memo has neither.
final class MemoCopyTextTests: XCTestCase {

    @MainActor
    func testPrefersTranscript() {
        let memo = Memo(audioFilename: "m.m4a", title: "A title", transcript: "the words")
        XCTAssertEqual(memo.copyableText, "the words")
    }

    @MainActor
    func testFallsBackToTitleWhenTranscriptMissingOrEmpty() {
        XCTAssertEqual(Memo(audioFilename: "m.m4a", title: "A title", transcript: nil).copyableText, "A title")
        XCTAssertEqual(Memo(audioFilename: "m.m4a", title: "A title", transcript: "").copyableText, "A title")
    }

    @MainActor
    func testNilWhenNothingToCopy() {
        XCTAssertNil(Memo(audioFilename: "m.m4a").copyableText)
        XCTAssertNil(Memo(audioFilename: "m.m4a", title: "", transcript: "").copyableText)
    }
}
