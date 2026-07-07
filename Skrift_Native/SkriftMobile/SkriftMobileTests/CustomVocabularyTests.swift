import XCTest
@testable import SkriftMobile

final class CustomVocabularyTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "CustomVocabularyTests")!
        defaults.removePersistentDomain(forName: "CustomVocabularyTests")
    }

    func testStoreSavesTrimmedDeduplicated() {
        CustomVocabularyStore.save(["  Skrift ", "skrift", "Gemma", "", "Gemma"], defaults: defaults)
        XCTAssertEqual(CustomVocabularyStore.words(defaults: defaults), ["Skrift", "Gemma"])
    }

    func testStoreEmptyByDefault() {
        XCTAssertEqual(CustomVocabularyStore.words(defaults: defaults), [])
    }

    func testAlignWordsSwapsPositionally() {
        let aligned = BPEMerge.alignWords(
            original: ["the", "script", "app", "works"],
            rescoredText: "the Skrift app works")
        XCTAssertEqual(aligned, ["the", "Skrift", "app", "works"])
    }

    func testAlignWordsNilWhenCountsDiverge() {
        XCTAssertNil(BPEMerge.alignWords(
            original: ["one", "two"],
            rescoredText: "one two three"))
    }

    func testAlignWordsHandlesNewlines() {
        let aligned = BPEMerge.alignWords(
            original: ["hello", "world"],
            rescoredText: "hello\nSkrift")
        XCTAssertEqual(aligned, ["hello", "Skrift"])
    }

    // MARK: - Term parsing (canonical + aliases) — mirrors the desktop suite

    func testParseBareWord() {
        XCTAssertEqual(VocabularyTermParsing.parse("Skrift"), .init(canonical: "Skrift", aliases: []))
    }

    func testParseCanonicalWithAliases() {
        XCTAssertEqual(VocabularyTermParsing.parse("Skrift: script, scrift"),
                       .init(canonical: "Skrift", aliases: ["script", "scrift"]))
    }

    func testParseDedupesAndTrims() {
        XCTAssertEqual(VocabularyTermParsing.parse("  Skrift : Script, script ,, SKRIFT, scrift "),
                       .init(canonical: "Skrift", aliases: ["Script", "scrift"]))
    }

    // MARK: - Similarity + trust guard

    func testSimilarityScriptVsSkrift() {
        XCTAssertEqual(VocabularySimilarity.similarity("script", "skrift"), 0.6667, accuracy: 0.001)
    }

    func testTrustKeepsCloseCanonicalAndAlias() {
        XCTAssertTrue(VocabularyTrust.isTrusted(original: "script", canonical: "Skrift", aliases: []))
        XCTAssertFalse(VocabularyTrust.isTrusted(original: "jack", canonical: "Jacques", aliases: []))
        XCTAssertTrue(VocabularyTrust.isTrusted(original: "jack", canonical: "Jacques", aliases: ["jack"]))
    }

    func testTrustDropsDistantSpotterRescue() {
        // The 2026-06-13 Mac false positives — dropped so ordinary speech is intact.
        XCTAssertFalse(VocabularyTrust.isTrusted(original: "room", canonical: "Rox", aliases: []))
        XCTAssertFalse(VocabularyTrust.isTrusted(original: "its alias", canonical: "Tiuri", aliases: []))
    }
}
