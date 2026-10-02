import XCTest
import Foundation

/// C172 / C31 / C21: on the Mac the whole body is one text view, so the quote block of a
/// capture is protected per edit by `CaptureQuote.editVerdict` (what the editor's
/// `shouldChangeTextIn` asks). Pure logic — host-less; no UI is driven.
final class MacQuoteReadOnlyTests: XCTestCase {

    private let capture = "> The only way out is through.\n> — a second line\n\nMy ramble here."

    private func verdict(_ body: String, _ loc: Int, _ len: Int, _ text: String?) -> CaptureQuoteEdit {
        CaptureQuote.editVerdict(body: body, range: NSRange(location: loc, length: len), replacement: text)
    }

    /// Apply an allowed edit the way the text view would, for the exact-prefix assertions.
    private func apply(_ body: String, _ loc: Int, _ len: Int, _ text: String) -> String {
        (body as NSString).replacingCharacters(in: NSRange(location: loc, length: len), with: text)
    }

    func testEditsInsideTheQuoteAreRejected() {
        XCTAssertEqual(verdict(capture, 0, 0, "x"), .reject, "insert at the very start")
        XCTAssertEqual(verdict(capture, 5, 0, "x"), .reject, "insert mid-quote")
        XCTAssertEqual(verdict(capture, 4, 3, ""), .reject, "delete inside the quote")
        XCTAssertEqual(verdict(capture, 0, (capture as NSString).length, "gone"), .reject,
                       "select-all + type must not wipe the quote")
        XCTAssertEqual(verdict(capture, 0, 20, ""), .reject, "delete a range that starts in the quote")
    }

    func testEditAtTheSeparatorIsRejected() {
        let readOnly = CaptureQuote.readOnlyLength(in: capture)
        // Backspace at the start of the ramble would eat the newline that joins it to the quote.
        XCTAssertEqual(verdict(capture, readOnly - 1, 1, ""), .reject)
        // A range that begins in the ramble but reaches back across the boundary is the same.
        XCTAssertEqual(verdict(capture, readOnly - 2, 3, ""), .reject)
    }

    func testRambleEditsAreAllowed() {
        let readOnly = CaptureQuote.readOnlyLength(in: capture)
        XCTAssertEqual(verdict(capture, readOnly, 0, "Prefix: "), .allow, "typing at the ramble's first character")
        XCTAssertEqual(verdict(capture, readOnly + 3, 4, ""), .allow, "deleting inside the ramble")
        XCTAssertEqual(verdict(capture, (capture as NSString).length, 0, " more"), .allow, "appending")
        XCTAssertEqual(verdict(capture, readOnly, (capture as NSString).length - readOnly, "new"), .allow,
                       "replacing the whole ramble")
    }

    func testAnEditedRambleKeepsTheRawQuoteBlockAsAnExactPrefix() {
        let quote = CaptureQuote.split(capture)!
        let readOnly = CaptureQuote.readOnlyLength(in: capture)
        XCTAssertEqual(verdict(capture, readOnly + 2, 0, "INSERTED "), .allow)
        let edited = apply(capture, readOnly + 2, 0, "INSERTED ")
        XCTAssertTrue(edited.hasPrefix(quote.rawBlock), "C21: the quote block is still the exact prefix")
        XCTAssertEqual(CaptureQuote.split(edited)?.rawBlock, quote.rawBlock)
        XCTAssertEqual(CaptureQuote.split(edited)?.displayText, quote.displayText)
    }

    func testAttributeOnlyChangesAreAllowedEvenOverTheQuote() {
        XCTAssertEqual(verdict(capture, 0, 10, nil), .allow)
    }

    func testBodyWithoutAQuoteIsNeverRestricted() {
        let plain = "Just a note.\n\nSecond paragraph."
        XCTAssertEqual(CaptureQuote.readOnlyLength(in: plain), 0)
        XCTAssertEqual(verdict(plain, 0, 0, "x"), .allow)
        XCTAssertEqual(verdict(plain, 0, (plain as NSString).length, ""), .allow)
        // A quote that is not at the top is ordinary prose.
        let late = "Intro line\n\n> a quote further down\n\nafter"
        XCTAssertEqual(verdict(late, 14, 0, "x"), .allow)
        XCTAssertEqual(verdict("", 0, 0, "x"), .allow)
    }

    func testIndentedMarkersFollowTheSharedSplitterRule() {
        // Indent tolerance is decided once, in `CaptureQuote.split`: an indented `>` is a quote.
        let indented = "  > indented quote\n\nramble"
        XCTAssertEqual(verdict(indented, 4, 0, "x"), .reject)
        XCTAssertEqual(verdict(indented, CaptureQuote.readOnlyLength(in: indented), 0, "x"), .allow)
    }

    func testQuoteOnlyBodyTakesAFirstRambleOnItsOwnParagraph() {
        let quoteOnly = "> a quote with no ramble yet"
        let end = (quoteOnly as NSString).length
        XCTAssertEqual(CaptureQuote.readOnlyLength(in: quoteOnly), end, "the whole body is the block")
        XCTAssertEqual(verdict(quoteOnly, 3, 0, "x"), .reject)
        XCTAssertEqual(verdict(quoteOnly, end, 0, "hello"), .allowAfterSeparator("\n\n"),
                       "typing at the end must not extend the quote's last line")
        XCTAssertEqual(verdict(quoteOnly + "\n", end + 1, 0, "hello"), .allowAfterSeparator("\n"))
        XCTAssertEqual(verdict(quoteOnly + "\n\n", end + 2, 0, "hello"), .allow)
        // The re-entrant pass (separator already in the replacement) must settle, not loop.
        XCTAssertEqual(verdict(quoteOnly, end, 0, "\n\nhello"), .allow)
        XCTAssertEqual(verdict(quoteOnly, end, 0, "\nhello"), .allowAfterSeparator("\n"))
        // Whitespace alone is not a ramble.
        XCTAssertEqual(verdict(quoteOnly, end, 0, "\n"), .allow)
        // Applying the separator verdict yields a body whose block is the original, exactly.
        let typed = apply(quoteOnly, end, 0, "\n\nhello")
        XCTAssertTrue(typed.hasPrefix(CaptureQuote.split(quoteOnly)!.rawBlock), "quote bytes stay an exact prefix")
        XCTAssertEqual(CaptureQuote.split(typed)?.displayText, CaptureQuote.split(quoteOnly)?.displayText)
        XCTAssertEqual(CaptureQuote.split(typed)?.ramble, "hello")
    }

    func testUTF16QuoteBlockLengthsAreCountedInUTF16() {
        // Emoji and curly quotes are multi-unit in UTF-16; the NSRange the text view hands over
        // is UTF-16, so the boundary must be too.
        let body = "> “Café 🙂” — said\n\nramble"
        let readOnly = CaptureQuote.readOnlyLength(in: body)
        XCTAssertEqual(verdict(body, readOnly, 0, "x"), .allow)
        XCTAssertEqual(verdict(body, readOnly - 1, 0, "x"), .reject)
        XCTAssertEqual((body as NSString).substring(from: readOnly), "ramble")
    }
}
