import XCTest
import Foundation

/// Q204: ONE word-split rule for karaoke. The Mac editor used its own splitter that read a
/// UTF-16 unit through `UnicodeScalar(c) ?? " "`, so any emoji (a surrogate pair) counted as
/// whitespace and split a word in two, drifting highlight + click-to-seek by one per emoji.
/// The Mac coordinator now calls the shared `KaraokeMap`; this pins that rule.
final class KaraokeMapEmojiTests: XCTestCase {
    func testEmojiInsideAWordDoesNotSplitIt() {
        let text = "great😀day and more" as NSString
        let ranges = KaraokeMap.wordRanges(in: text)
        XCTAssertEqual(ranges.map { text.substring(with: $0) }, ["great😀day", "and", "more"])
    }

    func testStandaloneEmojiIsItsOwnWord() {
        let text = "hello 😀 world" as NSString
        let ranges = KaraokeMap.wordRanges(in: text)
        XCTAssertEqual(ranges.map { text.substring(with: $0) }, ["hello", "😀", "world"])
    }

    func testWordCountMatchesWhitespaceSplit() {
        let s = "a😀b c 🎉 d\u{1F468}\u{200D}\u{1F469} e"
        let want = s.split(whereSeparator: { $0.isWhitespace }).count
        XCTAssertEqual(KaraokeMap.wordRanges(in: s as NSString).count, want)
    }

    func testAttachmentOnlyTokenCountsOnlyWhenAsked() {
        let text = "\u{FFFC} hello there" as NSString
        XCTAssertEqual(KaraokeMap.wordRanges(in: text).count, 2, "phone rule: attachment is not a spoken word")
        let mac = KaraokeMap.wordRanges(in: text, countAttachmentOnlyTokens: true)
        XCTAssertEqual(mac.count, 3, "Mac gutter attachment stands for the `**Name:**` word")
        XCTAssertEqual(mac.first, NSRange(location: 0, length: 1))
    }
}
