import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import SwiftData

/// Q136 (C77, C72, C73, D19, D22): the Mac accepts what the phone's share accepts: a `.txt`, a
/// PDF and a web link (with link enrichment, a PDF link, a Maps place). Every network call goes
/// through the injected `LinkFetching` stub and the PDF text through `PDFTextExtracting`, so no
/// test touches the network.
@MainActor
final class MacImportDoorsTests: XCTestCase {

    // MARK: - Stubs

    /// Answers `"GET https://…"` / `"HEAD https://…"` from a table and records every call.
    private final class StubFetcher: LinkFetching, @unchecked Sendable {
        private let lock = NSLock()
        private var table: [String: LinkFetchResponse]
        private var calls: [String] = []
        init(_ table: [String: LinkFetchResponse] = [:]) { self.table = table }
        var recorded: [String] { lock.lock(); defer { lock.unlock() }; return calls }
        func fetch(_ url: URL, method: String, timeout: TimeInterval) async -> LinkFetchResponse? {
            let key = "\(method) \(url.absoluteString)"
            lock.lock(); calls.append(key); let hit = table[key]; lock.unlock()
            return hit
        }
    }

    private struct StubPDFText: PDFTextExtracting {
        var text: String?
        func text(of url: URL) -> String? { text }
    }

    // MARK: - Fixtures

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: PipelineFile.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func service(_ work: URL, fetcher: StubFetcher = StubFetcher(),
                         pdfText: String? = nil) -> IngestService {
        var s = IngestService(outputDir: work.appendingPathComponent("out"))
        s.linkFetcher = fetcher
        s.pdfExtractor = StubPDFText(text: pdfText)
        return s
    }

    /// A tiny real PNG, so the thumbnail path decodes and downsamples for real.
    private func pngBytes() -> Data {
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    private func html(_ s: String) -> LinkFetchResponse {
        LinkFetchResponse(data: Data(s.utf8), contentType: "text/html; charset=utf-8")
    }

    /// The ONE row a single-item drop makes.
    private func ingestOne(_ svc: IngestService, _ urls: [URL]) async throws -> PipelineFile {
        let rows = try await svc.ingest(localURLs: urls, into: try makeContext())
        return try XCTUnwrap(rows.first)
    }

    private func shared(_ pf: PipelineFile) throws -> SharedContent {
        try XCTUnwrap(SharedContent.decode(from: pf.audioMetadataJSON), "the row carries sharedContent")
    }

    /// The title the SHARED ladder gives this row, exactly what both apps' lists call.
    private func title(_ pf: PipelineFile) throws -> String {
        let sc = try shared(pf)
        return NoteTitle.display(userTitle: nil, suggestedTitle: pf.enhancedTitle,
                                 body: pf.transcript, shared: sc, emptyFallback: "Capture")
    }

    // MARK: - .txt (D22)

    func testTxtDropIsATextCaptureWhoseBodyIsTheFile() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let f = work.appendingPathComponent("notes.txt")
        try "Buy milk\nand eggs for Friday".write(to: f, atomically: true, encoding: .utf8)

        let report = try await service(work).ingestReport(localURLs: [f], into: try makeContext())
        XCTAssertTrue(report.skipped.isEmpty, "a .txt is no longer 'Couldn't import'")
        let pf = try XCTUnwrap(report.created.first)
        XCTAssertEqual(pf.sourceType, .capture)
        XCTAssertEqual(try shared(pf).type, .text)
        XCTAssertEqual(try shared(pf).fileName, "notes.txt")
        XCTAssertEqual(pf.transcript, "Buy milk\nand eggs for Friday")
        XCTAssertEqual(pf.transcribeStatus, .done)
        // Same title as the phone: it reads the same ladder over the same body + sharedContent.
        XCTAssertEqual(try title(pf), "Buy milk")
    }

    func testOversizedTxtStaysADocumentCapture() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let f = work.appendingPathComponent("novel.txt")
        try String(repeating: "word ", count: SharedTextFile.byteCap / 4).write(to: f, atomically: true, encoding: .utf8)

        let pf = try await ingestOne(service(work), [f])
        let sc = try shared(pf)
        XCTAssertEqual(sc.type, .file, "a novel-length .txt is not a note body (phone rule)")
        XCTAssertEqual(sc.fileName, "novel.txt")
        XCTAssertEqual(pf.transcript, "")
    }

    func testMarkdownStaysANote() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let f = work.appendingPathComponent("n.md")
        try "# T\n\nbody".write(to: f, atomically: true, encoding: .utf8)
        let pf = try await ingestOne(service(work), [f])
        XCTAssertEqual(pf.sourceType, .note, "the .md question is its own decision")
    }

    // MARK: - PDF (C73)

    func testPdfDropIsAFileCaptureWithItsText() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let f = work.appendingPathComponent("contract.pdf")
        try Data("%PDF-1.4 fake".utf8).write(to: f)

        let svc = service(work, pdfText: "Services agreement between the parties for the year ahead")
        let report = try await svc.ingestReport(localURLs: [f], into: try makeContext())
        XCTAssertTrue(report.skipped.isEmpty)
        let pf = try XCTUnwrap(report.created.first)
        XCTAssertEqual(pf.sourceType, .capture)
        let sc = try shared(pf)
        XCTAssertEqual(sc.type, .file)
        XCTAssertEqual(sc.fileName, "contract.pdf")
        XCTAssertEqual(sc.mimeType, "application/pdf")
        XCTAssertEqual(sc.text, "Services agreement between the parties for the year ahead")
        XCTAssertEqual(pf.captureDocumentURL?.lastPathComponent, sc.filePath, "the real file is under files/")
        XCTAssertNotNil(pf.captureDocumentURL.flatMap { try? Data(contentsOf: $0) })
        // Phone ladder: no annotation -> the extracted text's first eight words.
        XCTAssertEqual(try title(pf), "Services agreement between the parties for the year…")
    }

    func testPdfDropWithNoTextIsTitledByItsFileName() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let f = work.appendingPathComponent("scan.pdf")
        try Data("%PDF-1.4".utf8).write(to: f)
        let pf = try await ingestOne(service(work, pdfText: nil), [f])
        XCTAssertNil(try shared(pf).text)
        XCTAssertEqual(try title(pf), "scan.pdf")
    }

    // MARK: - Links (C72)

    func testLinkDropIsEnrichedWithTitleDescriptionThumbnail() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let page = """
        <html><head><title>Fallback</title>
        <meta property="og:title" content="The Real Title">
        <meta property="og:description" content="A short description.">
        <meta property="og:image" content="https://example.com/hero.png"></head><body></body></html>
        """
        let fetcher = StubFetcher([
            "HEAD https://example.com/post": LinkFetchResponse(contentType: "text/html"),
            "GET https://example.com/post": html(page),
            "GET https://example.com/hero.png": LinkFetchResponse(data: pngBytes(), contentType: "image/png"),
        ])
        let url = URL(string: "https://example.com/post")!
        let report = try await service(work, fetcher: fetcher).ingestReport(localURLs: [url], into: try makeContext())
        XCTAssertTrue(report.skipped.isEmpty)
        let pf = try XCTUnwrap(report.created.first)
        XCTAssertEqual(pf.sourceType, .capture)
        let sc = try shared(pf)
        XCTAssertEqual(sc.type, .url)
        XCTAssertEqual(sc.url, "https://example.com/post")
        XCTAssertEqual(sc.urlTitle, "The Real Title")
        XCTAssertEqual(sc.urlDescription, "A short description.")
        XCTAssertNotNil(pf.captureThumbnailURL, "the thumbnail is a LOCAL file in the capture folder")
        XCTAssertEqual(try title(pf), "The Real Title")
    }

    func testFailedFetchTitlesTheCardByItsHostNeverTheUrl() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let url = URL(string: "https://www.metro.example.org/a/very/long/path?x=1")!
        let pf = try await ingestOne(service(work, fetcher: StubFetcher()), [url])
        let sc = try shared(pf)
        XCTAssertEqual(sc.type, .url, "the link is kept even when the page could not be read")
        XCTAssertEqual(sc.urlTitle, "metro.example.org")
        XCTAssertEqual(try title(pf), "metro.example.org")
    }

    func testLinkThatPointsAtAPdfDownloadsTheFile() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let fetcher = StubFetcher([
            "HEAD https://arxiv.example/pdf/2406.19741": LinkFetchResponse(contentType: "application/pdf; qs=0.001"),
            "GET https://arxiv.example/pdf/2406.19741":
                LinkFetchResponse(data: Data("%PDF-1.5 body".utf8), contentType: "application/pdf"),
        ])
        let url = URL(string: "https://arxiv.example/pdf/2406.19741")!
        let pf = try await ingestOne(service(work, fetcher: fetcher, pdfText: "Attention is all you need today"), [url])
        let sc = try shared(pf)
        XCTAssertEqual(sc.type, .file, "a link to a PDF lands as a file capture (C73)")
        XCTAssertEqual(sc.text, "Attention is all you need today")
        XCTAssertNotNil(pf.captureDocumentURL)
    }

    func testPdfLinkWithoutMagicBytesFallsBackToTheLinkCard() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let fetcher = StubFetcher([
            "GET https://example.com/fake.pdf": LinkFetchResponse(data: Data("<html>nope</html>".utf8),
                                                                 contentType: "text/html"),
        ])
        let url = URL(string: "https://example.com/fake.pdf")!
        let pf = try await ingestOne(service(work, fetcher: fetcher), [url])
        XCTAssertEqual(try shared(pf).type, .url, "content-type lies, the %PDF check is the gate")
        XCTAssertNil(pf.captureDocumentURL)
    }

    func testMapsLinkBecomesAPlaceWithoutAnyFetch() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let fetcher = StubFetcher()
        let url = URL(string: "https://maps.apple.com/?ll=38.7223,-9.1393&q=Hotel%20Du%20Vin")!
        let pf = try await ingestOne(service(work, fetcher: fetcher), [url])
        XCTAssertEqual(try shared(pf).urlTitle, "Hotel Du Vin")
        let meta = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(pf.audioMetadataJSON)) as? [String: Any])
        let loc = try XCTUnwrap(meta["location"] as? [String: Any])
        XCTAssertEqual(loc["latitude"] as? Double, 38.7223)
        XCTAssertEqual(loc["placeName"] as? String, "Hotel Du Vin")
        XCTAssertTrue(fetcher.recorded.isEmpty, "a Maps link is its own enrichment (D6): nothing is fetched")
    }

    func testNonHttpUrlIsReportedNotDropped() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let mail = URL(string: "mailto:someone@example.com")!
        let report = try await service(work).ingestReport(localURLs: [mail], into: try makeContext())
        XCTAssertTrue(report.created.isEmpty)
        XCTAssertEqual(report.skipped, [mail])
        // Q137: the banner names the link and says why, not "vanished".
        let banner = report.importReport
        XCTAssertEqual(banner.skipped.map(\.name), ["mailto:someone@example.com"])
        XCTAssertEqual(banner.skipped.map(\.reason), [ImportReport.notAWebLink])
    }

    func testALinkAndAFileInOneDropAreBothImported() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let f = work.appendingPathComponent("a.txt")
        try "hello there".write(to: f, atomically: true, encoding: .utf8)
        let link = URL(string: "https://example.com/x")!
        let report = try await service(work).ingestReport(localURLs: [f, link], into: try makeContext())
        XCTAssertEqual(report.created.count, 2)
        XCTAssertTrue(report.skipped.isEmpty)
        XCTAssertTrue(report.created.allSatisfy { $0.sourceType == .capture })
    }

    // MARK: - The phone gets the same kind back (author)

    func testAuthoredMemoCarriesTheSharedContentAndTheDocument() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let f = work.appendingPathComponent("contract.pdf")
        try Data("%PDF-1.4 fake".utf8).write(to: f)
        let pf = try await ingestOne(service(work, pdfText: "Some contract words here"), [f])

        let cloud = ModelContext(try ModelContainer(
            for: Memo.self, MemoAsset.self, MemoEnhancement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let memo = try XCTUnwrap(try MacMemoAuthor.author(for: pf, audioURL: nil, into: cloud))
        XCTAssertEqual(memo.sharedContent?.type, .file)
        XCTAssertEqual(memo.sharedContent?.fileName, "contract.pdf")
        XCTAssertEqual(memo.audioFilename, "", "no audio: a capture, as on the phone")
        let kinds = try cloud.fetch(FetchDescriptor<MemoAsset>()).map(\.kind)
        XCTAssertEqual(kinds, [MemoAsset.Kind.document], "the file itself rides along")
    }

    // MARK: - The shared pure rules

    func testHostTitleDropsWww() {
        XCTAssertEqual(LinkCard.hostTitle(URL(string: "https://www.Example.com/x")!), "example.com")
        XCTAssertNil(LinkCard.hostTitle(URL(string: "mailto:a@b.c")!))
    }

    func testSharedTextFileRule() {
        XCTAssertEqual(SharedTextFile.body(of: Data("  hi \n".utf8)), "hi")
        XCTAssertNil(SharedTextFile.body(of: Data("   ".utf8)))
        XCTAssertNil(SharedTextFile.body(of: Data([0xFF, 0xFE, 0x00])), "not UTF-8")
        XCTAssertNil(SharedTextFile.body(of: Data(count: SharedTextFile.byteCap + 1)))
    }
}
