import XCTest

/// Q342: the screen names the Mac's feedback carries (`.feedbackScreen`), so a note says
/// where it came from. The kit itself is not linked into this host-less bundle.
final class MacFeedbackScreensTests: XCTestCase {
    func testNotesListWhenNoNoteIsOpen() {
        XCTAssertEqual(MacFeedbackScreens.main(isReview: false, hasOpenNote: false), "Notes")
    }

    func testNoteWhenOneIsOpen() {
        XCTAssertEqual(MacFeedbackScreens.main(isReview: false, hasOpenNote: true), "Note")
    }

    func testReviewWinsOverAnOpenNote() {
        XCTAssertEqual(MacFeedbackScreens.main(isReview: true, hasOpenNote: true), "Review")
        XCTAssertEqual(MacFeedbackScreens.main(isReview: true, hasOpenNote: false), "Review")
    }

    func testTheSheetNames() {
        XCTAssertEqual(MacFeedbackScreens.settings, "Settings")
        XCTAssertEqual(MacFeedbackScreens.names, "Names")
    }
}
