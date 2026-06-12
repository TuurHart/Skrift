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
        let aligned = VocabularyBooster.alignWords(
            original: ["the", "script", "app", "works"],
            rescoredText: "the Skrift app works")
        XCTAssertEqual(aligned, ["the", "Skrift", "app", "works"])
    }

    func testAlignWordsNilWhenCountsDiverge() {
        XCTAssertNil(VocabularyBooster.alignWords(
            original: ["one", "two"],
            rescoredText: "one two three"))
    }

    func testAlignWordsHandlesNewlines() {
        let aligned = VocabularyBooster.alignWords(
            original: ["hello", "world"],
            rescoredText: "hello\nSkrift")
        XCTAssertEqual(aligned, ["hello", "Skrift"])
    }
}
