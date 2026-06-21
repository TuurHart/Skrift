import XCTest
@testable import SkriftMobile

/// MemoExporter (standalone Phase 2) — Memo → Obsidian markdown / plain text / PDF / quote
/// card, reusing the shared Compiler + on-device MemoLinking. Markdown/text assertions are
/// the meaningful coverage; PDF/card are smoke (binary output).
final class MemoExporterTests: XCTestCase {

    private let hendri = Person(canonical: "[[Hendri van Niekerk]]",
                               aliases: ["Hendri van Niekerk", "Hendri"], short: "Hendri",
                               lastModifiedAt: "2026-01-01T00:00:00Z")
    private let fixedDate = Date(timeIntervalSince1970: 1_781_000_000)

    // MARK: Markdown

    func testMarkdownFrontmatterAndLinkedBody() {
        let memo = Memo(recordedAt: fixedDate, tags: ["idea"], title: "Coffee with Hendri",
                        transcript: "Met up with Hendri today.", significance: 0.5,
                        metadata: MemoMetadata(location: LocationInfo(latitude: 1, longitude: 2, placeName: "Lisbon"),
                                               tags: []))
        let md = MemoExporter.markdown(for: memo, people: [hendri], author: "Tiuri")

        XCTAssertTrue(md.hasPrefix("---\n"), "starts with YAML frontmatter")
        XCTAssertTrue(md.contains("title: \"Coffee with Hendri\""))
        XCTAssertTrue(md.contains("author: Tiuri"))
        XCTAssertTrue(md.contains("source: Voice-memo"))
        XCTAssertTrue(md.contains("location: \"Lisbon\""))
        XCTAssertTrue(md.contains("- idea"))
        XCTAssertTrue(md.contains("date: \(MemoExporter.dateString(fixedDate))"))
        XCTAssertTrue(md.contains("[[Hendri van Niekerk]]"), "body should be name-linked — got: \(md)")
        XCTAssertTrue(md.contains("people: [[Hendri van Niekerk]]"), "people: frontmatter from the linked body")
    }

    func testCaptureMarkdownUrlSource() {
        let sc = SharedContent(type: .url, url: "https://example.com", urlTitle: "Example")
        let memo = Memo(recordedAt: fixedDate, title: "Saved link",
                        sharedContent: sc, annotationText: "Worth reading.")
        XCTAssertTrue(memo.isShareCapture, "fixture must be a share-capture")
        let md = MemoExporter.markdown(for: memo, people: [], author: "T")
        XCTAssertTrue(md.contains("source: capture-url"))
        XCTAssertTrue(md.contains("url: https://example.com"))
        XCTAssertTrue(md.contains("**Example**"))
        XCTAssertTrue(md.contains("Worth reading."))
    }

    // MARK: Plain text + link flattening

    func testPlainTextFlattensLinksAndStripsImageMarkers() {
        let memo = Memo(title: "Note", transcript: "[[img_001]] Met Hendri there.")
        let txt = MemoExporter.plainText(for: memo, people: [hendri])
        XCTAssertFalse(txt.contains("[["), "no wiki syntax in plain text — got: \(txt)")
        XCTAssertTrue(txt.contains("Hendri"))
        XCTAssertTrue(txt.hasPrefix("Note\n\n"))
    }

    func testFlattenLinks() {
        XCTAssertEqual(MemoExporter.flattenLinks("[[Nick]] and [[Tiuri Hartog|Tuur]]"), "Nick and Tuur")
        XCTAssertEqual(MemoExporter.flattenLinks("[[img_001]]hello"), "hello")
        XCTAssertEqual(MemoExporter.flattenLinks("no links"), "no links")
    }

    // MARK: Title fallback

    func testExportTitleFallback() {
        XCTAssertEqual(MemoExporter.exportTitle(for: Memo(title: "My Title", transcript: "body"), people: []), "My Title")
        XCTAssertEqual(MemoExporter.exportTitle(for: Memo(transcript: "First line here.\nSecond."), people: []), "First line here.")
        XCTAssertEqual(MemoExporter.exportTitle(for: Memo(), people: []), "Untitled Memo")
    }

    // MARK: Binary smoke

    @MainActor
    func testPdfAndQuoteCardProduceOutput() {
        let memo = Memo(title: "Title", transcript: "Some body text for the card and pdf.")
        XCTAssertGreaterThan(MemoExporter.pdf(for: memo, people: []).count, 500, "PDF should have content")
        XCTAssertNotNil(MemoExporter.quoteCardImage(for: memo, people: []), "quote card should render")
    }

    // MARK: Mac enhancement (CloudKit write-back) preference

    func testMarkdownPrefersMacEnhancement() {
        let memo = Memo(recordedAt: fixedDate, title: "raw title",
                        transcript: "um so i met hendri today you know")
        let enh = MemoEnhancement(memoID: memo.id, copyedit: "I met Hendri today.",
                                  title: "Meeting Hendri", summary: "A short note about meeting Hendri.")
        let md = MemoExporter.markdown(for: memo, people: [hendri], author: "T", enhancement: enh)
        XCTAssertTrue(md.contains("title: \"Meeting Hendri\""), "uses the Mac title")
        XCTAssertTrue(md.contains("summary: \"A short note about meeting Hendri.\""), "uses the Mac summary")
        XCTAssertTrue(md.contains("I met [[Hendri van Niekerk]] today."),
                      "polished body, re-linked on-device — got: \(md)")
        XCTAssertFalse(md.contains("um so"), "raw transcript dropped when enhanced")
    }

    func testEmptyEnhancementFallsBackToRaw() {
        let memo = Memo(title: "T", transcript: "Met Hendri today.")
        let md = MemoExporter.markdown(for: memo, people: [hendri], enhancement: MemoEnhancement(memoID: memo.id))
        XCTAssertTrue(md.contains("Met [[Hendri van Niekerk]] today."), "empty enhancement → raw linked body")
    }
}
