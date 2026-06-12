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
}
