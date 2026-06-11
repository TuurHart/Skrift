import XCTest
import Foundation

final class CompilerTests: XCTestCase {

    private func makeFile() -> PipelineFile {
        PipelineFile(id: "1", filename: "memo.m4a", path: "/tmp/x", size: 0, sourceType: .audio)
    }

    func testFrontmatterAndBodyPrecedence() {
        let pf = makeFile()
        pf.transcript = "raw transcript"
        pf.enhancedCopyedit = "clean copy"
        pf.sanitised = "linked [[Nick Jansen]] copy"
        pf.enhancedTitle = "My Title"
        pf.enhancedSummary = "A short summary."
        pf.tags = ["work", "ideas"]
        pf.significance = 0.7

        let md = Compiler.compile(file: pf, author: "Tiuri", date: "2026-06-06")
        XCTAssertTrue(md.contains("title: My Title"))
        XCTAssertTrue(md.contains("date: 2026-06-06"))
        XCTAssertTrue(md.contains("author: Tiuri"))
        XCTAssertTrue(md.contains("source: Voice-memo"))
        XCTAssertTrue(md.contains("significance: 0.7"))
        XCTAssertTrue(md.contains("summary: A short summary."))
        XCTAssertTrue(md.contains("- work"))
        XCTAssertTrue(md.contains("- ideas"))
        XCTAssertTrue(md.hasSuffix("linked [[Nick Jansen]] copy"))   // sanitised wins
    }

    func testBodyFallsBackToCopyedit() {
        let pf = makeFile()
        pf.transcript = "raw"
        pf.enhancedCopyedit = "edited body"
        let md = Compiler.compile(file: pf, author: "T", date: "2026-01-01")
        XCTAssertTrue(md.hasSuffix("edited body"))
    }

    func testPhoneMetadataFrontmatter() {
        let pf = makeFile()
        pf.transcript = "hi"
        pf.audioMetadataJSON = Data(#"{"location":{"placeName":"Amsterdam"},"weather":{"conditions":"Cloudy","temperature":12,"temperatureUnit":"°C"},"steps":4200,"recordedAt":"2026-06-05T08:00:00.000Z"}"#.utf8)
        let md = Compiler.compile(file: pf, author: "T")   // date from recordedAt
        XCTAssertTrue(md.contains("location: \"Amsterdam\""))
        XCTAssertTrue(md.contains("weather: \"Cloudy, 12°C\""))   // 12 not 12.0
        XCTAssertTrue(md.contains("steps: 4200"))
        XCTAssertTrue(md.contains("date: 2026-06-05"))
    }

    func testSignificanceRoundsToOneDecimal() {
        let pf = makeFile()
        pf.transcript = "body"
        pf.significance = 0.7000000000000001   // float noise the slider produced (E3)
        let md = Compiler.compile(file: pf, author: "T", date: "2026-01-01")
        XCTAssertTrue(md.contains("significance: 0.7"), "rounded to one decimal")
        XCTAssertFalse(md.contains("0.70000"), "no float-noise decimals in YAML")
    }

    func testEmptySignificanceAndSummaryAreBareKeys() {
        let pf = makeFile()
        pf.transcript = "body"
        let md = Compiler.compile(file: pf, author: "T", date: "2026-01-01")
        XCTAssertTrue(md.contains("\nsignificance:\n"))
        XCTAssertTrue(md.contains("\nsummary:\n"))
    }

    // MARK: - Audiobook quote-capture (contract C2 + spec 7)

    private let bookJSON = #"{"recordedAt":"2026-06-11T10:00:00.000Z","bookTitle":"The Beginning of Infinity","bookAuthor":"David Deutsch","bookChapter":"4"}"#
    private let captureBody = "> Optimism is a way of explaining failure.\n> Problems are soluble.\n\nThis maps onto how I think about debugging."

    func testPhoneMetadataDecodesWithoutBookFields() throws {
        // Old phone builds / non-capture memos: absent keys must decode to nil.
        let old = Data(#"{"steps":12,"recordedAt":"2026-06-05T08:00:00.000Z"}"#.utf8)
        let meta = try JSONDecoder().decode(PhoneMetadata.self, from: old)
        XCTAssertNil(meta.bookTitle)
        XCTAssertNil(meta.bookAuthor)
        XCTAssertNil(meta.bookChapter)
        XCTAssertEqual(meta.steps, 12)
    }

    func testPhoneMetadataDecodesWithBookFields() throws {
        let meta = try JSONDecoder().decode(PhoneMetadata.self, from: Data(bookJSON.utf8))
        XCTAssertEqual(meta.bookTitle, "The Beginning of Infinity")
        XCTAssertEqual(meta.bookAuthor, "David Deutsch")
        XCTAssertEqual(meta.bookChapter, "4")
    }

    func testPhoneMetadataEncodeOmitsAbsentBookFields() throws {
        // Byte-compat the other direction: a metadata without book fields encodes
        // WITHOUT the keys (encodeIfPresent), so nothing new rides old memos.
        let meta = try JSONDecoder().decode(PhoneMetadata.self, from: Data(#"{"steps":3}"#.utf8))
        let json = String(decoding: try JSONEncoder().encode(meta), as: UTF8.self)
        XCTAssertFalse(json.contains("bookTitle"))
        XCTAssertFalse(json.contains("bookAuthor"))
        XCTAssertFalse(json.contains("bookChapter"))
    }

    func testAudiobookSourceAndFrontmatter() {
        let pf = makeFile()
        pf.transcript = captureBody
        pf.audioMetadataJSON = Data(bookJSON.utf8)
        let md = Compiler.compile(file: pf, author: "Tiuri")
        XCTAssertTrue(md.contains("source: Audiobook-quote"))
        XCTAssertFalse(md.contains("source: Voice-memo"))
        XCTAssertTrue(md.contains("book: \"The Beginning of Infinity\""))
        XCTAssertTrue(md.contains("bookAuthor: \"David Deutsch\""))
        XCTAssertTrue(md.contains("chapter: \"4\""))
        XCTAssertTrue(md.contains("author: Tiuri"), "the note author key is untouched")
    }

    func testNoBookMetadataKeepsVoiceMemoSource() {
        let pf = makeFile()
        pf.transcript = captureBody   // a quote block alone is NOT an audiobook capture
        let md = Compiler.compile(file: pf, author: "T", date: "2026-01-01")
        XCTAssertTrue(md.contains("source: Voice-memo"))
        XCTAssertFalse(md.contains("book:"))
        XCTAssertTrue(md.contains("> Optimism is a way"), "body untouched without book metadata")
        XCTAssertFalse(md.contains("> *"))
        XCTAssertFalse(md.contains("> — "))
    }

    func testAudiobookBodyItalicsAndAttribution() {
        let pf = makeFile()
        pf.transcript = captureBody
        pf.audioMetadataJSON = Data(bookJSON.utf8)
        let md = Compiler.compile(file: pf, author: "T")
        XCTAssertTrue(md.contains("> *Optimism is a way of explaining failure.*"), "quote lines italicised")
        XCTAssertTrue(md.contains("> *Problems are soluble.*"))
        XCTAssertTrue(md.contains("> — [[David Deutsch]], *The Beginning of Infinity*, ch. 4"))
        XCTAssertTrue(md.hasSuffix("This maps onto how I think about debugging."), "ramble preserved after the block")
        let attr = md.range(of: "> — [[David Deutsch]]")!
        let ramble = md.range(of: "This maps onto")!
        XCTAssertTrue(attr.lowerBound < ramble.lowerBound, "attribution sits between quote and ramble")
    }

    func testAttributionOmitsMissingChapter() {
        let pf = makeFile()
        pf.transcript = "> A line.\n\nramble"
        pf.audioMetadataJSON = Data(#"{"bookTitle":"Some Book","bookAuthor":"Jane Doe"}"#.utf8)
        let md = Compiler.compile(file: pf, author: "T", date: "2026-01-01")
        XCTAssertTrue(md.contains("> — [[Jane Doe]], *Some Book*"))
        XCTAssertFalse(md.contains("ch. "))
        XCTAssertFalse(md.contains("chapter:"))
    }

    func testAttributionOmitsMissingAuthor() {
        let pf = makeFile()
        pf.transcript = "> A line.\n\nramble"
        pf.audioMetadataJSON = Data(#"{"bookTitle":"Some Book","bookChapter":"12"}"#.utf8)
        let md = Compiler.compile(file: pf, author: "T", date: "2026-01-01")
        XCTAssertTrue(md.contains("> — *Some Book*, ch. 12"))
        XCTAssertFalse(md.contains("[["), "no author → no wikilink anywhere")
        XCTAssertFalse(md.contains("bookAuthor:"))
    }

    func testAudiobookBodyWithoutQuoteBlockIsUntouched() {
        let pf = makeFile()
        pf.transcript = "just a ramble, the quote got lost upstream"
        pf.audioMetadataJSON = Data(#"{"bookTitle":"Some Book"}"#.utf8)
        let md = Compiler.compile(file: pf, author: "T", date: "2026-01-01")
        XCTAssertTrue(md.contains("source: Audiobook-quote"), "frontmatter still book-aware")
        XCTAssertTrue(md.hasSuffix("just a ramble, the quote got lost upstream"))
        XCTAssertFalse(md.contains("> — "), "no attribution without a quote block")
    }

    func testAudiobookBodyDoesNotDoubleItalicise() {
        // A body whose quote lines are ALREADY wrapped (hand edit) keeps one pair.
        let out = Compiler.audiobookBody("> *already italic*\n\nramble",
                                         book: "B", author: nil, chapter: nil)
        XCTAssertTrue(out.contains("> *already italic*"))
        XCTAssertFalse(out.contains("**already italic**"))
    }
}
