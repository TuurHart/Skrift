import XCTest
import Foundation

/// The C2 book-fields accessor (`PipelineFile.bookCapture`) + the presentation
/// helpers it carries: the plain-text attribution caption and the leading-quote
/// line ranges the review body's styling uses. Pure logic — host-less.
final class BookCaptureTests: XCTestCase {

    private func makeFile(metadata: String? = nil) -> PipelineFile {
        let pf = PipelineFile(id: "1", filename: "memo.m4a", path: "/tmp/x", size: 0, sourceType: .audio)
        if let metadata { pf.audioMetadataJSON = Data(metadata.utf8) }
        return pf
    }

    // ── Decoding ────────────────────────────────────────────

    func testDecodesC2FieldsAlongsidePhoneMetadata() {
        let pf = makeFile(metadata: #"{"location":{"placeName":"Bristol"},"recordedAt":"2026-06-11T21:00:00.000Z","bookTitle":"Steal Like an Artist","bookAuthor":"Austin Kleon","bookChapter":"3"}"#)
        let book = pf.bookCapture
        XCTAssertEqual(book?.title, "Steal Like an Artist")
        XCTAssertEqual(book?.author, "Austin Kleon")
        XCTAssertEqual(book?.chapter, "3")
    }

    func testNilWithoutBookTitle() {
        XCTAssertNil(makeFile().bookCapture, "no metadata blob at all")
        XCTAssertNil(makeFile(metadata: #"{"steps":4200}"#).bookCapture, "older-build metadata without book keys")
        XCTAssertNil(makeFile(metadata: #"{"bookTitle":"  ","bookAuthor":"A"}"#).bookCapture, "whitespace title is not a capture")
        XCTAssertNil(makeFile(metadata: "not json").bookCapture, "garbage blob decodes to nil, not a trap")
    }

    func testTrimsFieldsAndDropsEmptyOnes() {
        let pf = makeFile(metadata: #"{"bookTitle":" Steal Like an Artist ","bookAuthor":"  ","bookChapter":""}"#)
        let book = pf.bookCapture
        XCTAssertEqual(book?.title, "Steal Like an Artist")
        XCTAssertNil(book?.author, "whitespace author drops to nil")
        XCTAssertNil(book?.chapter, "empty chapter drops to nil")
    }

    /// The accessor and the Compiler must agree on what counts as a book capture —
    /// the source identity shown in the app matches the exported `source:`.
    func testAgreesWithCompilerSourceLine() {
        let capture = makeFile(metadata: #"{"bookTitle":"Steal Like an Artist"}"#)
        capture.transcript = "> Quote.\n\nRamble."
        XCTAssertNotNil(capture.bookCapture)
        XCTAssertTrue(Compiler.compile(file: capture, author: "T", date: "2026-06-11")
            .contains("source: Audiobook-quote"))

        let plain = makeFile()
        plain.transcript = "hello"
        XCTAssertNil(plain.bookCapture)
        XCTAssertTrue(Compiler.compile(file: plain, author: "T", date: "2026-06-11")
            .contains("source: Voice-memo"))
    }

    // ── Attribution caption ─────────────────────────────────

    func testAttributionFull() {
        let book = BookCapture(title: "Steal Like an Artist", author: "Austin Kleon", chapter: "3")
        XCTAssertEqual(book.attribution, "— Austin Kleon, Steal Like an Artist · ch. 3")
    }

    func testAttributionOmitsMissingPieces() {
        XCTAssertEqual(BookCapture(title: "Steal Like an Artist", author: nil, chapter: "3").attribution,
                       "— Steal Like an Artist · ch. 3")
        XCTAssertEqual(BookCapture(title: "Steal Like an Artist", author: "Austin Kleon", chapter: nil).attribution,
                       "— Austin Kleon, Steal Like an Artist")
        XCTAssertEqual(BookCapture(title: "Steal Like an Artist", author: nil, chapter: nil).attribution,
                       "— Steal Like an Artist")
    }

    /// An m4b chapter NAME shows as-is; only purely numeric chapters get "ch. " —
    /// mirrors the phone's `bookCaptionLabel`.
    func testAttributionNamedChapterShowsAsIs() {
        let book = BookCapture(title: "The Beginning of Infinity", author: "David Deutsch", chapter: "The Reality of Abstractions")
        XCTAssertEqual(book.attribution, "— David Deutsch, The Beginning of Infinity · The Reality of Abstractions")
    }

    // ── Quote line ranges (editor styling geometry) ─────────

    func testQuoteLineRangesEmptyForNonQuoteText() {
        XCTAssertEqual(BookCapture.quoteLineRanges(in: "plain transcript"), [])
        XCTAssertEqual(BookCapture.quoteLineRanges(in: ""), [])
        XCTAssertEqual(BookCapture.quoteLineRanges(in: " > not at offset 0"), [])
    }

    func testQuoteLineRangesSingleLine() {
        let text = "> A quote.\n\nMy ramble."
        let ranges = BookCapture.quoteLineRanges(in: text)
        XCTAssertEqual(ranges, [NSRange(location: 0, length: 10)])
        XCTAssertEqual((text as NSString).substring(with: ranges[0]), "> A quote.")
    }

    func testQuoteLineRangesMultiLineMapToLines() {
        let text = "> First line.\n> Second line.\n>\n> Fourth.\n\nRamble starts."
        let ranges = BookCapture.quoteLineRanges(in: text)
        let ns = text as NSString
        XCTAssertEqual(ranges.count, 4)
        XCTAssertEqual(ns.substring(with: ranges[0]), "> First line.")
        XCTAssertEqual(ns.substring(with: ranges[1]), "> Second line.")
        XCTAssertEqual(ns.substring(with: ranges[2]), ">")
        XCTAssertEqual(ns.substring(with: ranges[3]), "> Fourth.")
        // The block the ranges span is exactly what QuoteProtection protects.
        let quote = QuoteProtection.splitLeadingQuote(text)!.quote
        XCTAssertEqual(NSMaxRange(ranges.last!), (quote as NSString).length)
    }

    /// NSRange coords are UTF-16: non-BMP characters in the quote must not skew
    /// the line ranges (they'd misplace the italics + bar in the editor).
    func testQuoteLineRangesAreUTF16Safe() {
        let text = "> Optimism 🙂 is a stance.\n> Second.\n\nRamble"
        let ranges = BookCapture.quoteLineRanges(in: text)
        let ns = text as NSString
        XCTAssertEqual(ns.substring(with: ranges[0]), "> Optimism 🙂 is a stance.")
        XCTAssertEqual(ns.substring(with: ranges[1]), "> Second.")
    }

    func testQuoteLineRangesQuoteOnlyBody() {
        let text = "> Just the quote, no ramble yet."
        let ranges = BookCapture.quoteLineRanges(in: text)
        XCTAssertEqual(ranges, [NSRange(location: 0, length: (text as NSString).length)])
    }
}
