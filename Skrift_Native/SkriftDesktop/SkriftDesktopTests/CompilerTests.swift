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
        XCTAssertTrue(md.contains("title: \"My Title\""))
        XCTAssertTrue(md.contains("date: 2026-06-06"))
        XCTAssertTrue(md.contains("author: Tiuri"))
        XCTAssertTrue(md.contains("source: Voice-memo"))
        XCTAssertTrue(md.contains("significance: 0.7"))
        XCTAssertTrue(md.contains("summary: \"A short summary.\""))
        XCTAssertTrue(md.contains("- work"))
        XCTAssertTrue(md.contains("- ideas"))
        XCTAssertTrue(md.contains("people: [[Nick Jansen]]"))   // opt-in: the linked person
        XCTAssertTrue(md.hasSuffix("linked [[Nick Jansen]] copy"))   // sanitised wins
    }

    // MARK: people: frontmatter (opt-in naming) — derived from the body's linked canonicals

    func testPeopleListFromBodyLinks() {
        // Distinct canonicals in reading order; alias-display links resolve to the canonical;
        // a repeated person appears once; `[[img_NNN]]` markers are excluded.
        let pf = makeFile()
        pf.sanitised = "[[img_001]] [[Hendri Van Niekerk]] met [[Bruno Aragorn|Bruno]], then [[Hendri Van Niekerk|Henry]] again."
        let md = Compiler.compile(file: pf, author: "T", date: "2026-01-01")
        XCTAssertTrue(md.contains("people: [[Hendri Van Niekerk]], [[Bruno Aragorn]]"),
                      "distinct canonicals in reading order, img marker excluded; got: \(md)")
    }

    func testPeopleEmptyWhenNobodyLinked() {
        let pf = makeFile()
        pf.sanitised = "A plain note about Henry and Bruno, nobody linked."
        let md = Compiler.compile(file: pf, author: "T", date: "2026-01-01")
        XCTAssertTrue(md.contains("\npeople:\n"), "empty people key when no links; got: \(md)")
        XCTAssertFalse(md.contains("people: [["), "no people values on an unlinked note")
    }

    /// A video import (sourceType .audio + mediaSource "video") must export
    /// `source: Video` in the frontmatter — not "Voice-memo".
    func testVideoSourceFrontmatter() {
        let pf = makeFile()
        pf.mediaSource = "video"
        pf.transcript = "advice to my future self"
        let md = Compiler.compile(file: pf, author: "T", date: "2026-06-14")
        XCTAssertTrue(md.contains("source: Video"), "video import should export source: Video")
        XCTAssertFalse(md.contains("source: Voice-memo"))
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

// MARK: - C3 Capture compile tests

final class CaptureCompilerTests: XCTestCase {

    private func makeCapture(type: String, sc: [String: Any], annotation: String = "") -> PipelineFile {
        let pf = PipelineFile(id: "c-\(UUID().uuidString)", filename: "capture_test",
                              path: "/tmp/cap", size: 0, sourceType: .capture)
        var meta: [String: Any] = ["sharedContent": sc, "recordedAt": "2026-06-11T14:02:00Z"]
        if let url = sc["url"] as? String { meta["url"] = url }
        pf.audioMetadataJSON = try? JSONSerialization.data(withJSONObject: meta)
        pf.transcript = annotation
        pf.sanitised = annotation.isEmpty ? nil : annotation
        return pf
    }

    // MARK: URL capture

    func testUrlCaptureSourceKey() {
        let pf = makeCapture(type: "url",
            sc: ["type": "url", "url": "https://swiftwithmajid.com/2026/05/rich-text-editing",
                 "urlTitle": "Rich text editing in SwiftUI — strategies that work"],
            annotation: "Try this for the body editor.")
        let md = Compiler.compile(file: pf, author: "T", date: "2026-06-11")
        XCTAssertTrue(md.contains("source: capture-url"), "source key must be capture-url")
    }

    func testUrlCaptureFrontmatterUrlKey() {
        let pf = makeCapture(type: "url",
            sc: ["type": "url", "url": "https://swiftwithmajid.com/2026/05/rich-text-editing",
                 "urlTitle": "Rich text editing in SwiftUI — strategies that work"],
            annotation: "A note.")
        let md = Compiler.compile(file: pf, author: "T", date: "2026-06-11")
        XCTAssertTrue(md.contains("url: https://swiftwithmajid.com/2026/05/rich-text-editing"),
                      "url: key in frontmatter for url captures")
    }

    func testUrlCaptureSharedBlockAboveBody() {
        let pf = makeCapture(type: "url",
            sc: ["type": "url", "url": "https://swiftwithmajid.com/2026/05/rich-text-editing",
                 "urlTitle": "Rich text editing in SwiftUI — strategies that work"],
            annotation: "My annotation.")
        let md = Compiler.compile(file: pf, author: "T", date: "2026-06-11")
        // The shared block must appear BEFORE the annotation.
        let boldTitle = "**Rich text editing in SwiftUI — strategies that work**"
        let urlLine = "https://swiftwithmajid.com/2026/05/rich-text-editing"
        XCTAssertTrue(md.contains(boldTitle), "bold title in shared block")
        XCTAssertTrue(md.contains(urlLine), "URL line in shared block")
        let blockRange = md.range(of: boldTitle)!
        let bodyRange = md.range(of: "My annotation.")!
        XCTAssertLessThan(blockRange.lowerBound, bodyRange.lowerBound, "shared block before body")
    }

    func testUrlCaptureNoAudioLine() {
        let pf = makeCapture(type: "url",
            sc: ["type": "url", "url": "https://example.com", "urlTitle": "Example"],
            annotation: "Note.")
        let md = Compiler.compile(file: pf, author: "T", date: "2026-06-11")
        XCTAssertFalse(md.contains("audio:"), "no audio key for captures")
    }

    // MARK: Text capture

    func testTextCaptureBlockquote() {
        let pf = makeCapture(type: "text",
            sc: ["type": "text", "text": "The key insight is that async/await composes naturally."],
            annotation: "This is exactly what we saw with the upload flow.")
        let md = Compiler.compile(file: pf, author: "T", date: "2026-06-11")
        XCTAssertTrue(md.contains("source: capture-text"))
        XCTAssertTrue(md.contains("> The key insight is that async/await composes naturally."),
                      "text snippet as blockquote")
        // blockquote before annotation
        let bqRange = md.range(of: "> The key insight")!
        let bodyRange = md.range(of: "This is exactly")!
        XCTAssertLessThan(bqRange.lowerBound, bodyRange.lowerBound, "blockquote before body")
    }

    // MARK: Image capture

    func testImageCaptureEmbed() {
        let pf = makeCapture(type: "image",
            sc: ["type": "image", "fileName": "whiteboard.jpg", "mimeType": "image/jpeg"],
            annotation: "The sync flow diagram from Nick's session.")
        let md = Compiler.compile(file: pf, author: "T", date: "2026-06-11")
        XCTAssertTrue(md.contains("source: capture-image"))
        XCTAssertTrue(md.contains("![[whiteboard.jpg]]"), "image embed in shared block")
        let embedRange = md.range(of: "![[whiteboard.jpg]]")!
        let bodyRange = md.range(of: "The sync flow diagram")!
        XCTAssertLessThan(embedRange.lowerBound, bodyRange.lowerBound, "embed before body")
    }

    // MARK: captureSharedBlock unit tests

    func testCaptureSharedBlockUrl() {
        let sc = SharedContent(type: "url",
                               url: "https://example.com",
                               urlTitle: "Example Page")
        let block = Compiler.captureSharedBlock(sc)
        XCTAssertTrue(block.contains("**Example Page**"))
        XCTAssertTrue(block.contains("https://example.com"))
    }

    func testCaptureSharedBlockText() {
        let sc = SharedContent(type: "text", text: "A quoted snippet.")
        let block = Compiler.captureSharedBlock(sc)
        XCTAssertTrue(block.hasPrefix("> A quoted snippet."))
    }

    func testCaptureSharedBlockImage() {
        let sc = SharedContent(type: "image", fileName: "photo.jpg")
        let block = Compiler.captureSharedBlock(sc)
        XCTAssertTrue(block.contains("![[photo.jpg]]"))
    }

    func testCaptureSharedBlockUnknownTypeIsEmpty() {
        let sc = SharedContent(type: "file")
        let block = Compiler.captureSharedBlock(sc)
        XCTAssertTrue(block.isEmpty, "unknown type → no pinned block")
    }
}
