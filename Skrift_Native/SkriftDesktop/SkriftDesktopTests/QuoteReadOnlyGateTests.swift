import XCTest
import Foundation

/// D175 / C172: the Mac locks a leading `> ` block only for a real captured quote (the note
/// carries the book fields); a hand-typed blockquote stays editable. Pure logic — no UI.
final class QuoteReadOnlyGateTests: XCTestCase {

    private let body = "> The only way out is through.\n\nMy ramble."

    private func verdict(locked: Bool, _ loc: Int, _ len: Int, _ text: String?) -> CaptureQuoteEdit {
        CaptureQuote.editVerdict(body: body, range: NSRange(location: loc, length: len),
                                 replacement: text, locked: locked)
    }

    private func file(metadata: String?) -> PipelineFile {
        var pf = PipelineFile(id: UUID().uuidString, filename: "x", path: "/tmp/x", size: 0, sourceType: .audio)
        pf.audioMetadataJSON = metadata.flatMap { $0.data(using: .utf8) }
        return pf
    }

    func testLockedGateRejectsEditsInTheQuote() {
        XCTAssertEqual(verdict(locked: true, 3, 0, "x"), .reject)
        XCTAssertEqual(verdict(locked: true, 0, 5, ""), .reject)
    }

    func testUnlockedGateLetsAHandTypedBlockquoteEdit() {
        XCTAssertEqual(verdict(locked: false, 3, 0, "x"), .allow)
        XCTAssertEqual(verdict(locked: false, 0, 5, ""), .allow)
        XCTAssertEqual(verdict(locked: false, 0, (body as NSString).length, "gone"), .allow)
    }

    func testDefaultStaysLocked() {
        XCTAssertEqual(CaptureQuote.editVerdict(body: body, range: NSRange(location: 3, length: 0), replacement: "x"),
                       .reject)
    }

    func testOnlyBookCapturesAreLocked() {
        XCTAssertTrue(file(metadata: #"{"bookTitle":"Walden","bookAuthor":"Thoreau"}"#).hasLockedQuote)
        XCTAssertFalse(file(metadata: #"{"bookTitle":"   "}"#).hasLockedQuote)
        XCTAssertFalse(file(metadata: #"{"dayPeriod":"morning"}"#).hasLockedQuote)
        XCTAssertFalse(file(metadata: nil).hasLockedQuote, "a plain note that opens with '> ' is not a capture")
    }
}
