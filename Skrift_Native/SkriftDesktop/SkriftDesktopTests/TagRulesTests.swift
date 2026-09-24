import XCTest

/// The C93 tag-entry rules, single-sourced (Q28/C241 revamp) — split/refuse and the
/// D139 library-wide case fold. Covers the three BUGS §4 leads this item fixes:
/// Mac `commitOne` lowercasing, no case fold anywhere, and `#` stripped more than once.
final class TagRulesTests: XCTestCase {

    // ── split ──────────────────────────────────────────────
    func testCommaAndNewlineSplit() {
        let s = TagRules.split("Lisbon, market\nwood")
        XCTAssertEqual(s.accepted, ["Lisbon", "market", "wood"])
        XCTAssertTrue(s.refused.isEmpty)
    }

    func testHashStrippedOnceCaseKept() {
        let s = TagRules.split("#design")
        XCTAssertEqual(s.accepted, ["design"])
        // A tag that starts with a second literal `#` keeps it — only the LEADING
        // hashtag marker is a marker; a second `#` is part of the word.
        let s2 = TagRules.split("##design")
        XCTAssertEqual(s2.accepted, ["#design"], "# stripped ONCE, not every #")
        let s3 = TagRules.split("Wood")
        XCTAssertEqual(s3.accepted, ["Wood"], "case kept")
    }

    func testPunctuationOnlyIsRefusedNotDropped() {
        let s = TagRules.split("[]")
        XCTAssertTrue(s.accepted.isEmpty)
        XCTAssertEqual(s.refused, ["[]"], "refused input is reported, not silently swallowed")
    }

    func testBlankPiecesDropSilently() {
        let s = TagRules.split("  ,  ,  ")
        XCTAssertTrue(s.accepted.isEmpty)
        XCTAssertTrue(s.refused.isEmpty, "an empty piece (just whitespace) isn't a refusal, just nothing")
    }

    // ── resolveSpelling (D139) ─────────────────────────────
    func testNewTagKeepsTypedCaseWhenNewToLibrary() {
        XCTAssertEqual(TagRules.resolveSpelling("Wood", library: ["furniture", "design"]), "Wood")
    }

    func testCaseVariantFoldsToLibrarySpellingEverywhere() {
        XCTAssertEqual(TagRules.resolveSpelling("Wood", library: ["furniture", "wood"]), "wood",
                       "typing Wood when wood exists anywhere reuses the existing spelling")
        XCTAssertEqual(TagRules.resolveSpelling("LISBON", library: ["Lisbon"]), "Lisbon")
    }

    // ── fold (batch add against note + library) ────────────
    func testFoldAddsNewTagsAsTyped() {
        let r = TagRules.fold(["Lisbon", "market"], existing: [], library: ["furniture"])
        XCTAssertEqual(r.toAdd, ["Lisbon", "market"])
        XCTAssertTrue(r.folds.isEmpty)
    }

    func testFoldReusesLibrarySpellingAndSkipsDuplicate() {
        let r = TagRules.fold(["LISBON"], existing: [], library: ["Lisbon", "furniture"])
        XCTAssertTrue(r.toAdd.isEmpty, "Lisbon already exists in the library under a different case")
        XCTAssertEqual(r.folds, [TagRules.Fold(typed: "LISBON", kept: "Lisbon")])
    }

    func testFoldSkipsWhatsAlreadyOnTheNoteExactly() {
        let r = TagRules.fold(["furniture"], existing: ["furniture"], library: [])
        XCTAssertTrue(r.toAdd.isEmpty)
        XCTAssertTrue(r.folds.isEmpty, "no fold record for an exact repeat, just a no-op")
    }

    func testFoldNeverRewritesTagsAlreadyOnTheNote() {
        // The fold applies to NEW input only — an existing note tag's spelling is
        // never touched by this call (the caller's `existing` array is read, not mutated).
        let existing = ["Wood"]
        let r = TagRules.fold(["wood"], existing: existing, library: [])
        XCTAssertTrue(r.toAdd.isEmpty)
        XCTAssertEqual(existing, ["Wood"], "existing array untouched")
    }

    func testFoldWithinOneBatchDedupesToFirstSpelling() {
        let r = TagRules.fold(["Wood", "wood"], existing: [], library: [])
        XCTAssertEqual(r.toAdd, ["Wood"], "first spelling in the batch wins for the rest of the batch")
        XCTAssertEqual(r.folds, [TagRules.Fold(typed: "wood", kept: "Wood")])
    }
}
