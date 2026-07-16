import XCTest

/// The pure half of the body's inline `#` tag popup (Obsidian idiom):
/// prefix matching over most-used-first candidates + the `#word` caret-context
/// detection that decides when the popup opens.
final class TagCompleteTests: XCTestCase {

    func testPrefixMatchOrderCapAndSpaceExclusion() {
        let cands = ["testing", "more tags", "testflight", "Testy", "work",
                     "test1", "test2", "test3", "test4", "test5", "test6", "test7"]
        let out = TagComplete.completions(partial: "te", candidates: cands)
        XCTAssertEqual(out.first, "testing", "caller order (most-used-first) is preserved")
        XCTAssertFalse(out.contains("more tags"), "spaced tags can't be inline hashtags")
        XCTAssertFalse(out.contains("work"), "prefix mismatch is excluded")
        XCTAssertEqual(out.count, 8, "capped so the list stays a menu")
        XCTAssertTrue(out.contains("Testy"), "case-insensitive match keeps original casing")
    }

    func testDedupesCaseInsensitivelyKeepingFirstCasing() {
        XCTAssertEqual(TagComplete.completions(partial: "t", candidates: ["Todo", "todo", "TODO"]),
                       ["Todo"])
    }

    func testHashtagPartialRangeContexts() {
        func range(_ s: String, caret: Int? = nil) -> NSRange? {
            TagComplete.hashtagPartialRange(in: s, caret: caret ?? (s as NSString).length)
        }
        XCTAssertEqual(range("note #te"), NSRange(location: 6, length: 2))
        XCTAssertEqual(range("#te"), NSRange(location: 1, length: 2), "start of text is a boundary")
        XCTAssertNil(range("C#te"), "mid-word # (C#) never triggers")
        XCTAssertNil(range("# heading"), "a markdown heading has no word char after #")
        XCTAssertNil(range("plain text"))
        XCTAssertNil(range("tag #done ", caret: 10), "caret after the space → out of the run")
        XCTAssertEqual(range("a #inbox/to", caret: 11), NSRange(location: 3, length: 8),
                       "nested / stays inside the tag")
    }
}
