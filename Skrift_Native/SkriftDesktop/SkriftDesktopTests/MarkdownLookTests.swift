import XCTest
import Foundation

/// Q380 (C239): the ONE rule for which ranges of a body get the editor's markdown look — the
/// phone's `NoteBodyView` and the Mac's `BodyTextView` both draw `MarkdownLook.spans`.
final class MarkdownLookTests: XCTestCase {

    private func texts(_ text: String, _ role: MarkdownLook.Role, floor: Int = 0) -> [String] {
        let ns = text as NSString
        return MarkdownLook.spans(in: text, quoteFloor: floor).filter { $0.role == role }.map { ns.substring(with: $0.range) }
    }

    func testHeadingWordsAndTheirMark() {
        let t = "# Plan\nbody"
        XCTAssertEqual(texts(t, .heading(1)), ["Plan"])
        XCTAssertTrue(texts(t, .mark).contains { $0.hasPrefix("#") })
    }

    func testInlinePairsStyleTheWordsAndDimBothMarks() {
        let t = "a **bold** and ~~gone~~"
        XCTAssertEqual(texts(t, .inline(.bold)), ["bold"])
        XCTAssertEqual(texts(t, .inline(.strike)), ["gone"])
        XCTAssertEqual(texts(t, .mark).filter { $0 == "**" }.count, 2)
        XCTAssertEqual(texts(t, .mark).filter { $0 == "~~" }.count, 2)
    }

    func testBlockQuoteDimsTheMarkAndKeepsTheWords() {
        let t = "intro\n> said once\nafter"
        XCTAssertEqual(texts(t, .quoteText), ["said once"])
        XCTAssertTrue(texts(t, .mark).contains("> "))
    }

    func testQuoteFloorLeavesTheLeadingQuoteAlone() {
        let t = "> the book's words\n\n> my quote later"
        let floor = (t as NSString).range(of: "\n\n").location
        XCTAssertEqual(texts(t, .quoteText, floor: floor), ["my quote later"])
    }

    func testPlainTextHasNoSpans() {
        XCTAssertTrue(MarkdownLook.spans(in: "just words, nothing marked").isEmpty)
    }
}
