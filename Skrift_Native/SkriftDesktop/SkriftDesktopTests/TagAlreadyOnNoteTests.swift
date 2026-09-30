import XCTest
@testable import SkriftDesktop

/// Q81 / mock `tag-ui-revamp.html`: the "already on this note as #x" line, driven by
/// the same fold rules (`TagRules.resolveSpelling`, `TagRules.fold`).
final class TagAlreadyOnNoteTests: XCTestCase {
    func testCaseVariantReportsTheNotesOwnSpelling() {
        XCTAssertEqual(TagRules.alreadyOnNote(["LISBON"], existing: ["Lisbon", "furniture"], library: []), "Lisbon")
    }
    func testExactRepeatAlsoReports() {
        XCTAssertEqual(TagRules.alreadyOnNote(["furniture"], existing: ["furniture"], library: []), "furniture")
    }
    func testNewTagReportsNothing() {
        XCTAssertNil(TagRules.alreadyOnNote(["wood"], existing: ["Lisbon"], library: ["Wood"]))
    }
    func testSameBatchVariantReportsFirstSpelling() {
        XCTAssertEqual(TagRules.alreadyOnNote(["Wood", "wood"], existing: [], library: []), "Wood")
    }
    func testLibrarySpellingFoldedTagCountsAsOnNoteForALaterVariant() {
        // "LISBON" is added as the library's "Lisbon"; the next "lisbon" then repeats it.
        XCTAssertEqual(TagRules.alreadyOnNote(["LISBON", "lisbon"], existing: [], library: ["Lisbon"]), "Lisbon")
    }
    func testTypedLineIgnoresOneHashAndCase() {
        XCTAssertEqual(TagRules.typedAlreadyOnNote("#lisBON", existing: ["Lisbon"]), "Lisbon")
        XCTAssertNil(TagRules.typedAlreadyOnNote("lis", existing: ["Lisbon"]))
        XCTAssertNil(TagRules.typedAlreadyOnNote("  ", existing: ["Lisbon"]))
    }
}
