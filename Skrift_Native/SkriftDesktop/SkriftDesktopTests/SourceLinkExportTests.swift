import XCTest
import Foundation

/// Q372 (D138): a "Send to a note" / "Move to Library" note is capture metadata (`bookID` +
/// `bookPosition`, a PDF page as "p. N" in `bookChapter`) with NO quote. The ONE shared rule
/// (`SourceKind.sourceLink`) tells it apart from a captured quote, so the Mac card and both
/// exporters call it a link to its source and export a link line (`— *Title*, p. N` /
/// `— *Show*, episode, mm:ss`) with `source:` naming the source kind, never an empty quote.
final class SourceLinkExportTests: XCTestCase {

    private let bookID = UUID()

    /// The metadata shape `LibraryHatch.linkMetadata` writes.
    private func linkMemo(title: String, author: String? = nil, chapter: String?, position: Double,
                          kind: String?, words: String? = nil) -> Memo {
        var dict: [String: Any] = ["tags": [String](), "bookTitle": title,
                                   "bookID": bookID.uuidString, "bookPosition": position]
        if let author { dict["bookAuthor"] = author }
        if let chapter { dict["bookChapter"] = chapter }
        if let kind { dict["bookKind"] = kind }
        let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        return Memo(recordedAt: Date(), title: "Linked", transcript: words,
                    transcriptStatus: .done, significance: 0.5, metadataData: data)
    }

    private func pdfLink(words: String? = nil) -> Memo {
        linkMemo(title: "GFR grant application, draft 3", chapter: "p. 4", position: 4, kind: "pdf", words: words)
    }
    private func episodeLink() -> Memo {
        linkMemo(title: "Joris Luyendijk: Ik zit in een rouwproces", author: "NRC Het Uur",
                 chapter: nil, position: 1421, kind: "episode")
    }
    private func bookLink() -> Memo {
        linkMemo(title: "Four Thousand Weeks", author: "Oliver Burkeman", chapter: "3", position: 4325, kind: "book")
    }

    private func macMarkdown(_ m: Memo) -> String {
        Compiler.compile(file: MemoNoteProjection.file(for: m), author: "Me", date: "2026-10-13")
    }

    private func sourceLine(_ md: String) -> String? {
        md.components(separatedBy: "\n").first { $0.hasPrefix("source: ") }
    }

    // MARK: - The shared classifier

    func testTheClassifierSeesALinkNotAQuote() {
        XCTAssertEqual(SourceKind.of(pdfLink()), .pdfLink)
        XCTAssertEqual(SourceKind.of(episodeLink()), .episodeLink)
        XCTAssertEqual(SourceKind.of(bookLink()), .audiobookLink)
        XCTAssertEqual(SourceKind.pdfLink.label, "PDF link")
        XCTAssertEqual(SourceKind.episodeLink.label, "Episode link")
        XCTAssertEqual(SourceKind.audiobookLink.label, "Audiobook link")
    }

    func testTheMacRowClassifiesTheSameWay() {
        XCTAssertEqual(MemoNoteProjection.file(for: pdfLink()).sourceKind, .pdfLink)
        XCTAssertEqual(MemoNoteProjection.file(for: episodeLink()).sourceKind, .episodeLink)
        XCTAssertEqual(MemoNoteProjection.file(for: bookLink()).sourceKind, .audiobookLink)
    }

    func testHisWordsUnderTheLinkKeepItALink() {
        XCTAssertEqual(SourceKind.of(pdfLink(words: "Landlord wants an answer by Friday.")), .pdfLink)
    }

    func testACapturedQuoteStaysAQuote() {
        let quoted = linkMemo(title: "Four Thousand Weeks", author: "Oliver Burkeman", chapter: "3",
                              position: 4325, kind: nil, words: "> The day will never come.\n\nSo true.")
        XCTAssertEqual(SourceKind.of(quoted), .audiobookQuote)
        let pdfQuote = linkMemo(title: "GFR", chapter: "p. 4", position: 4, kind: nil,
                                words: "> Sensor integration: €18,000")
        XCTAssertEqual(SourceKind.of(pdfQuote), .pdfQuote)
    }

    func testAnOlderLinkWithoutAKindFallsBackOnThePlace() {
        XCTAssertEqual(SourceKind.of(linkMemo(title: "GFR", chapter: "p. 2", position: 2, kind: nil)), .pdfLink)
        XCTAssertEqual(SourceKind.of(linkMemo(title: "Book", chapter: nil, position: 60, kind: nil)), .audiobookLink)
    }

    // MARK: - The exported markdown

    func testAPdfLinkExportsALinkLine() {
        let md = macMarkdown(pdfLink(words: "Landlord wants an answer by Friday."))
        XCTAssertEqual(sourceLine(md), "source: PDF-link", md)
        XCTAssertTrue(md.contains("\n— *GFR grant application, draft 3*, p. 4\n\nLandlord wants an answer by Friday."), md)
        XCTAssertFalse(md.contains("PDF-quote"), md)
        XCTAssertFalse(md.contains("\n>"), "never a quote block: \(md)")
    }

    func testAnEpisodeLinkExportsShowEpisodeAndTime() {
        let md = macMarkdown(episodeLink())
        XCTAssertEqual(sourceLine(md), "source: Episode-link", md)
        XCTAssertTrue(md.contains("\n— *NRC Het Uur*, Joris Luyendijk: Ik zit in een rouwproces, 23:41"), md)
        XCTAssertFalse(md.contains("Audiobook-quote"), md)
        XCTAssertFalse(md.contains("\n>"), md)
    }

    func testABookLinkExportsAuthorTitleChapterAndTime() {
        let md = macMarkdown(bookLink())
        XCTAssertEqual(sourceLine(md), "source: Audiobook-link", md)
        XCTAssertTrue(md.contains("\n— [[Oliver Burkeman]], *Four Thousand Weeks*, ch. 3, 1:12:05"), md)
        XCTAssertFalse(md.contains("Audiobook-quote"), md)
        XCTAssertFalse(md.contains("\n>"), md)
    }

    func testAQuoteStillExportsAsAQuote() {
        let quoted = linkMemo(title: "Four Thousand Weeks", author: "Oliver Burkeman", chapter: "3",
                              position: 4325, kind: nil, words: "> The day will never come.\n\nSo true.")
        let md = macMarkdown(quoted)
        XCTAssertEqual(sourceLine(md), "source: Audiobook-quote", md)
        XCTAssertTrue(md.contains("> *The day will never come.*"), md)
    }

    /// The phone's exporter feeds the same Compiler with `SourceKind.of(memo)`; the line matches.
    func testPhoneAndMacInputsAgree() {
        let m = pdfLink(words: "Words.")
        let phone = Compiler.compile(CompilerInput.make(
            filename: "memo", raw: m.transcript, copyedit: nil, title: m.title, summary: nil,
            tags: m.tags, significance: m.significance, sourceType: .audio, mediaSource: nil,
            metadata: CompilerMetadata(bookTitle: "GFR grant application, draft 3", bookChapter: "p. 4",
                                       bookPosition: 4),
            sharedContent: nil, rawRecordedAt: nil, destination: m.destination,
            spoken: false, kind: SourceKind.of(m)), author: "Me", date: "2026-10-13")
        XCTAssertEqual(sourceLine(phone), "source: PDF-link", phone)
        XCTAssertTrue(phone.contains("\n— *GFR grant application, draft 3*, p. 4\n\nWords."), phone)
    }
}
