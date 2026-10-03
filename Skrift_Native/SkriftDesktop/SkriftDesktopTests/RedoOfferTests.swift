import XCTest

/// Q295 (D176): the Mac offers Redo only after a real polish ran. A title Tuur chose himself
/// lands in `enhancedTitle` too, so a chosen-title-only note offers Polish, not Redo.
final class RedoOfferTests: XCTestCase {

    private func file() -> PipelineFile { PipelineFile(filename: "a.m4a") }

    func testChosenTitleOnlyDoesNotOfferRedo() {
        let f = file()
        f.enhancedTitle = "My own title"
        XCTAssertFalse(MacNoteMenu.hasRealPolish(f))
        XCTAssertFalse(MacNoteMenu.redoOffered(f, locked: false))
    }

    func testGeneratedTitleOffersRedo() {
        let f = file()
        f.enhancedTitle = "Model title"
        f.titleSuggested = "Model title"
        XCTAssertTrue(MacNoteMenu.redoOffered(f, locked: false))
    }

    func testAGeneratedTitleStillCountsAfterTuurRetitles() {
        let f = file()
        f.titleSuggested = "Model title"
        f.enhancedTitle = "My own title"
        XCTAssertTrue(MacNoteMenu.redoOffered(f, locked: false))
    }

    func testSummaryOffersRedo() {
        let f = file()
        f.enhancedSummary = "A summary."
        XCTAssertTrue(MacNoteMenu.redoOffered(f, locked: false))
    }

    func testTagsOfferRedo() {
        let f = file()
        f.enhancedTitle = "My own title"
        f.tags = ["pottery"]
        XCTAssertTrue(MacNoteMenu.redoOffered(f, locked: false))
    }

    func testBlankPartsDoNotCount() {
        let f = file()
        f.enhancedTitle = "My own title"
        f.titleSuggested = "  "
        f.enhancedSummary = "\n"
        f.tags = [" "]
        XCTAssertFalse(MacNoteMenu.redoOffered(f, locked: false))
    }

    func testLockedNoteNeverOffersRedo() {
        let f = file()
        f.enhancedSummary = "A summary."
        XCTAssertFalse(MacNoteMenu.redoOffered(f, locked: true))
    }

    func testChosenTitleOnlyNoteMenuStateHidesRedo() {
        let f = file()
        f.enhancedTitle = "My own title"
        XCTAssertFalse(MacNoteMenu.state(for: f, locked: false, canUndoTidyUp: false).redoOffered)
    }
}
