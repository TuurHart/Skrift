import XCTest
@testable import SkriftMobile

/// The memos-list display accessors for audiobook quote captures
/// (`Models/MemoDisplay.swift`): C2 detection via `metadata.bookTitle`, and C1
/// quote-block parsing ("> " lines at the top, blank line, then the ramble).
final class BookCaptureDisplayTests: XCTestCase {

    /// A capture memo per the C1/C2 contracts. Sets the book fields by
    /// assignment (not init parameters) so the test only relies on the C2
    /// FIELDS existing, not on any particular init signature.
    private func captureMemo(
        transcript: String?,
        title: String? = nil,
        book: String? = "The Beginning of Infinity",
        chapter: String? = nil
    ) -> Memo {
        var meta = MemoMetadata()
        meta.bookTitle = book
        meta.bookChapter = chapter
        return Memo.make(title: title, transcript: transcript, metadata: meta)
    }

    private let c1Transcript = """
    > Optimism is not the belief that things will go well,
    > but a way of explaining failure.

    My take: this reframes the retro — treat the failure as input, not verdict.
    Second ramble line that should not appear in the snippet.
    """

    // MARK: - Detection (C2)

    func testIsBookCaptureRequiresANonBlankBookTitle() {
        XCTAssertTrue(captureMemo(transcript: nil).isBookCapture)
        XCTAssertFalse(captureMemo(transcript: nil, book: nil).isBookCapture)
        XCTAssertFalse(captureMemo(transcript: nil, book: "   ").isBookCapture)
        XCTAssertFalse(Memo().isBookCapture, "no metadata at all → not a capture")
        XCTAssertFalse(Memo(transcript: "> quoted\n\nramble").isBookCapture,
                       "a blockquote alone doesn't make a capture — the C2 book metadata does")
    }

    // MARK: - Quote block (C1)

    func testQuoteSnippetJoinsTheLeadingBlockquoteLines() {
        let memo = captureMemo(transcript: c1Transcript)
        XCTAssertEqual(
            memo.quoteSnippet,
            "Optimism is not the belief that things will go well, but a way of explaining failure."
        )
    }

    func testQuoteSnippetStopsAtTheFirstNonQuoteLine() {
        // A ">" later in the ramble must NOT be folded into the quote.
        let memo = captureMemo(transcript: "> The quote.\n\nRamble first.\n> not part of it")
        XCTAssertEqual(memo.quoteSnippet, "The quote.")
    }

    func testQuoteSnippetNilWithoutALeadingBlockquote() {
        XCTAssertNil(captureMemo(transcript: "Plain transcript, no quote block.").quoteSnippet)
        XCTAssertNil(captureMemo(transcript: nil).quoteSnippet)
        XCTAssertNil(captureMemo(transcript: "").quoteSnippet)
    }

    func testQuoteSnippetToleratesBareAndPaddedMarkers() {
        // ">" with no space, and a blank ">" spacer line inside the block.
        let memo = captureMemo(transcript: ">First.\n>\n> Second.\n\nRamble.")
        XCTAssertEqual(memo.quoteSnippet, "First. Second.")
    }

    // MARK: - Ramble (the row's dim second line)

    func testRambleSnippetIsTheFirstLineBelowTheQuote() {
        let memo = captureMemo(transcript: c1Transcript)
        XCTAssertEqual(
            memo.rambleSnippet,
            "My take: this reframes the retro — treat the failure as input, not verdict."
        )
    }

    func testRambleSnippetNilForAQuoteOnlyCapture() {
        // "Save & keep listening" without recording thoughts → no ramble yet.
        XCTAssertNil(captureMemo(transcript: "> Just the quote.").rambleSnippet)
    }

    func testRambleSnippetStripsImageMarkers() {
        let memo = captureMemo(transcript: "> Q.\n\n[[img_001]] thoughts here")
        XCTAssertEqual(memo.rambleSnippet, "thoughts here")
    }

    // MARK: - Book caption ("Book · ch. N")

    func testBookCaptionLabelFormatsNumericChaptersAndPassesNamesThrough() {
        XCTAssertEqual(captureMemo(transcript: nil, chapter: "4").bookCaptionLabel,
                       "The Beginning of Infinity · ch. 4")
        XCTAssertEqual(captureMemo(transcript: nil, chapter: "The Spark").bookCaptionLabel,
                       "The Beginning of Infinity · The Spark")
        XCTAssertEqual(captureMemo(transcript: nil).bookCaptionLabel,
                       "The Beginning of Infinity")
        XCTAssertNil(Memo().bookCaptionLabel)
    }
}
