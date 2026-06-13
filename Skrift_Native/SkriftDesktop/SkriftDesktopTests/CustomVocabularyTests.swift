import XCTest

final class CustomVocabularyTests: XCTestCase {

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

    /// A settings.json written BEFORE customVocabulary existed must still decode
    /// (the field is optional for exactly this) and read as an empty list.
    func testLegacySettingsDecodeWithoutCustomVocabulary() throws {
        let legacy = """
        {"noteFolder":"/tmp/v","audioFolder":"","attachmentsFolder":"","authorName":"T",
         "enhancementModelRepo":"r","prompts":{"copyEdit":"c","summary":"s","title":"t"},
         "highpassFreqHz":80}
        """
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        XCTAssertNil(s.customVocabulary)
        XCTAssertEqual(s.customWords, [])
    }

    func testCustomWordsRoundTrip() throws {
        var s = AppSettings.default
        s.customVocabulary = ["Skrift", "Tiuri"]
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(back.customWords, ["Skrift", "Tiuri"])
    }

    // MARK: - Term parsing (canonical + aliases)

    func testParseBareWordHasNoAliases() {
        XCTAssertEqual(VocabularyTermParsing.parse("Skrift"),
                       .init(canonical: "Skrift", aliases: []))
    }

    func testParseCanonicalWithAliases() {
        XCTAssertEqual(VocabularyTermParsing.parse("Skrift: script, scrift"),
                       .init(canonical: "Skrift", aliases: ["script", "scrift"]))
    }

    func testParseTrimsAndDropsEmptyAliases() {
        XCTAssertEqual(VocabularyTermParsing.parse("  Skrift :  script ,, , scrift  "),
                       .init(canonical: "Skrift", aliases: ["script", "scrift"]))
    }

    func testParseDedupesAliasesCaseInsensitivelyAndDropsCanonicalEcho() {
        XCTAssertEqual(VocabularyTermParsing.parse("Skrift: Script, script, SKRIFT, scrift"),
                       .init(canonical: "Skrift", aliases: ["Script", "scrift"]))
    }

    func testParseEmptyCanonicalFallsBackToRawEntry() {
        // "  : foo" would yield an empty canonical — feed the raw text instead so
        // we never tokenize an empty term.
        XCTAssertEqual(VocabularyTermParsing.parse(": foo"),
                       .init(canonical: ": foo", aliases: []))
    }

    func testCanonicalHelper() {
        XCTAssertEqual(VocabularyTermParsing.canonical("Skrift: script"), "Skrift")
        XCTAssertEqual(VocabularyTermParsing.canonical("Tiuri"), "Tiuri")
    }

    // MARK: - Tuning defaults (release path returns the passed-in default)

    func testTuningReturnsDefaultsWithoutEnvOverride() {
        // No env override set in the test process → defaults pass through.
        if ProcessInfo.processInfo.environment["SKRIFT_VOCAB_CBW"] == nil {
            XCTAssertEqual(VocabularyTuning.cbw(default: 4.5), 4.5)
        }
        if ProcessInfo.processInfo.environment["SKRIFT_VOCAB_MINSIM"] == nil {
            XCTAssertEqual(VocabularyTuning.minSimilarity(default: 0.5), 0.5)
        }
    }

    // MARK: - Similarity (Levenshtein, mirrors FluidAudio's 1 - dist/maxLen)

    func testSimilarityScriptVsSkrift() {
        // The user's real pair: edit-distance 2 over 6 chars → 0.667. Above the
        // 0.50 floor, so a ready booster surfaces the candidate via Route 1 alone.
        XCTAssertEqual(VocabularySimilarity.similarity("script", "skrift"), 0.6667, accuracy: 0.001)
    }

    func testSimilarityIdenticalAndDisjoint() {
        XCTAssertEqual(VocabularySimilarity.similarity("Skrift", "skrift"), 1.0, accuracy: 0.0001)
        XCTAssertEqual(VocabularySimilarity.similarity("room", "rox"), 0.5, accuracy: 0.0001)  // r,o common; o,m vs x → dist 2 / 4
    }

    // MARK: - Trust guard (drops distant spotter-rescue false positives)

    func testTrustKeepsCloseCanonical() {
        // script → Skrift (0.667) is trusted with no aliases needed.
        XCTAssertTrue(VocabularyTrust.isTrusted(original: "script", canonical: "Skrift", aliases: []))
    }

    func testTrustKeepsAliasHit() {
        // jack → Jacques (sim ~0.43, below floor) is trusted ONLY because "jack"
        // is an explicit alias — the documented escape hatch for distant mishearings.
        XCTAssertFalse(VocabularyTrust.isTrusted(original: "jack", canonical: "Jacques", aliases: []))
        XCTAssertTrue(VocabularyTrust.isTrusted(original: "jack", canonical: "Jacques", aliases: ["jack"]))
    }

    func testTrustDropsDistantSpotterRescue() {
        // The 2026-06-13 Mac false positives: distant acoustic-only guesses with
        // no alias → dropped, so ordinary speech isn't mangled.
        XCTAssertFalse(VocabularyTrust.isTrusted(original: "room", canonical: "Rox", aliases: []))
        XCTAssertFalse(VocabularyTrust.isTrusted(original: "its alias", canonical: "Tiuri", aliases: []))
    }
}
