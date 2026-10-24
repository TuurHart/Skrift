import XCTest
@testable import SkriftMobile

/// Q493 (C289): an ePub import reads every part or names each part it skipped and why — never a
/// silent partial ingest. Fixture `test-fixtures/epub/skip-report.epub` (synthetic, see its
/// generate.py): a damaged mid-file chapter, a malformed-but-readable chapter, a manifest item
/// missing from the zip, a spine idref missing from the manifest, and an image-only cover.
final class EpubSkipReportTests: XCTestCase {

    private func fixtureURL(_ name: String) -> URL {
        // .../Skrift_Native/SkriftMobile/SkriftMobileTests/<file> -> repo root is 4 up.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("test-fixtures/epub/\(name)")
    }

    /// The real attach parse path (ZIPFoundation unzip + EPubParse) on the fixture.
    private func parsedFixture() throws -> EPubBook {
        let src = fixtureURL("skip-report.epub")
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("skip_\(UUID().uuidString).epub")
        try FileManager.default.copyItem(at: src, to: copy)
        addTeardownBlock { try? FileManager.default.removeItem(at: copy) }
        return try BookAlignmentRunner.parseBookFile(at: copy)
    }

    func testDamagedChapterIsReportedNotDroppedAndTheRestIsRead() throws {
        let book = try parsedFixture()
        let text = book.blocks.map(\.text).joined(separator: " ")
        XCTAssertTrue(text.contains("lighthouse keeper"), "chapter 1 must be read")
        XCTAssertTrue(text.contains("boats went out again"), "malformed chapter 3 must be read by the lenient pass")
        XCTAssertFalse(text.contains("harbour froze"), "the damaged chapter's bytes must not leak in")

        let byPart = Dictionary(uniqueKeysWithValues: book.skipped.map { ($0.part, $0.reason) })
        XCTAssertEqual(byPart["OEBPS/chapter2.xhtml"], "damaged inside the ePub file")
        XCTAssertEqual(byPart["OEBPS/chapter4.xhtml"], "missing from the ePub file")
        XCTAssertEqual(byPart["ghost"], "listed in the reading order but missing from the book’s manifest")
        XCTAssertNil(byPart["OEBPS/cover.xhtml"], "an image-only page is not a skipped part")
        XCTAssertEqual(book.skipped.count, 3)
    }

    func testSkipsKeepSpineOrder() throws {
        let book = try parsedFixture()
        XCTAssertEqual(book.skipped.map(\.part), ["OEBPS/chapter2.xhtml", "ghost", "OEBPS/chapter4.xhtml"])
    }

    func testOutcomeAlertNamesEverySkippedPart() throws {
        let book = try parsedFixture()
        let summary = BookAlignmentRunner.AttachSummary(alignedFiles: 1, totalFiles: 1, skippedParts: book.skipped)
        let text = try XCTUnwrap(BookTextFlow.outcomeText(summary))
        XCTAssertTrue(text.contains("Skrift skipped 3 parts of this ePub"), text)
        XCTAssertTrue(text.contains("chapter2.xhtml (damaged inside the ePub file)"), text)
        XCTAssertTrue(text.contains("chapter4.xhtml (missing from the ePub file)"), text)
        XCTAssertTrue(text.contains("ghost (listed in the reading order"), text)
    }

    func testCleanImportSaysNothingAboutSkips() throws {
        let summary = BookAlignmentRunner.AttachSummary(alignedFiles: 1, totalFiles: 1)
        let text = try XCTUnwrap(BookTextFlow.outcomeText(summary))
        XCTAssertFalse(text.contains("skipped"))
        XCTAssertNil(EPubSkip.summary([]))
    }

    /// Pure parser: an unreadable well-formed-looking part (strict parse fails, lenient finds no
    /// text) is reported; a well-formed empty part is not.
    func testUnreadablePartIsReported() throws {
        let entries: [String: Data] = [
            "META-INF/container.xml": Data("""
            <?xml version="1.0"?><container><rootfiles><rootfile full-path="c.opf"/></rootfiles></container>
            """.utf8),
            "c.opf": Data("""
            <package><manifest><item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>\
            <item id="b" href="b.xhtml" media-type="application/xhtml+xml"/>\
            <item id="e" href="e.xhtml" media-type="application/xhtml+xml"/></manifest>\
            <spine><itemref idref="a"/><itemref idref="b"/><itemref idref="e"/></spine></package>
            """.utf8),
            "a.xhtml": Data("<html><body><p>Readable words.</p></body></html>".utf8),
            "b.xhtml": Data("<html><body><p><img src='x'></body>".utf8),
            "e.xhtml": Data("<html><body><img src='x'/></body></html>".utf8),
        ]
        let book = try EPubParse.parse(entries: entries)
        XCTAssertEqual(book.skipped, [EPubSkip(part: "b.xhtml", reason: "couldn’t be read as text")])
        XCTAssertEqual(book.blocks.map(\.text), ["Readable words."])
    }
}
