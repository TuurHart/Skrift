import XCTest
import Foundation

final class TagMatcherTests: XCTestCase {

    func testSpokenHashtags() {
        let out = TagMatcher.spokenHashtags(in: "today #work and #side-project, more #work then #123 and #ok")
        XCTAssertEqual(out, ["work", "side-project", "ok"])   // deduped, numeric-leading dropped
    }

    func testMatchTagsFrequencyGate() {
        // Repeated identical words keep the count robust regardless of lemma vs surface.
        let out = TagMatcher.matchTags(in: "coffee coffee tea", matchable: ["coffee", "tea"], minOccurrences: 2)
        XCTAssertEqual(out, ["coffee"])   // coffee x2 passes, tea x1 fails
    }

    func testSuggestCombinesMatchedAndSpoken() {
        let s = TagMatcher.suggest(text: "code code code and #side-project", whitelist: ["code", "design"])
        XCTAssertEqual(s.matched, ["code"])
        XCTAssertEqual(s.spoken, ["side-project"])
    }

    func testSuggestCaps() {
        let s = TagMatcher.suggest(text: "x", whitelist: [], maxMatched: 1, maxSpoken: 1)
        XCTAssertTrue(s.matched.isEmpty)
        XCTAssertTrue(s.spoken.isEmpty)
    }
}
