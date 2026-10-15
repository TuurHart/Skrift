import PDFKit
import SwiftUI
import XCTest
@testable import SkriftMobile

/// Q461 (D213, C120): a scanned PDF reads by on-device text recognition (`LibraryPDFScan.swift`).
/// The order/leak/structure goldens score the `scanned-page` fixture's reading text; these pin the
/// page rule, the recognised geometry, the cache beside the library item and the progress line.
/// An extension of `PDFReadingGoldenTests`, so `plan/mtest.sh PDFReadingGoldenTests` runs it.
extension PDFReadingGoldenTests {

    static var scanFixture: URL { fixtureDir.appendingPathComponent("scanned-page.pdf") }

    func testScanPageRuleReadsMissingGarbledAndSparsePages() {
        let text = Array(repeating: "harbour", count: 40).joined(separator: " ")
        XCTAssertEqual(LibraryPDF.pagesToRecognise([text, text]), [], "a text PDF is never recognised")
        XCTAssertEqual(LibraryPDF.pagesToRecognise([text, "", text]), [1], "a page with no text layer is")
        XCTAssertEqual(LibraryPDF.pagesToRecognise([text, "\u{FFFD}\u{FFFD} \u{E001}x"]), [1], "a garbled page is")
        XCTAssertEqual(LibraryPDF.pagesToRecognise(["12", "13"]), [0, 1], "a scan with a page-number layer is")
        XCTAssertEqual(LibraryPDF.pagesToRecognise([text, "Chapter two", text]), [],
                       "a short title page in a text PDF keeps its text layer")
    }

    func testEvenedHeightsKeepBodyLinesOneTypeAndHeadingsLarger() {
        func line(_ minY: Double, _ maxY: Double) -> PDFReflow.Line {
            PDFReflow.Line(words: [PDFReflow.Word(text: "w", minX: 0, maxX: 10)], minY: minY, maxY: maxY)
        }
        let out = LibraryPDF.evenedHeights([line(700, 716), line(680, 690), line(660, 670), line(640, 650.5),
                                            line(620, 630)])
        XCTAssertEqual(out[0].maxY - out[0].minY, 16, "the heading's larger type stays larger")
        XCTAssertEqual(out[1], line(680, 690))
        XCTAssertEqual(out[3].maxY - out[3].minY, 10, accuracy: 1e-9, "a body line gets the median height")
        XCTAssertEqual((out[3].minY + out[3].maxY) / 2, 645.25, accuracy: 1e-9, "around its own centre")
    }

    /// The scanned letter reads as heading + three paragraphs, like its expect.md.
    func testScannedLetterReadsAsItsParagraphs() throws {
        let doc = try XCTUnwrap(LibraryPDF.readingDoc(url: Self.scanFixture))
        let page = try XCTUnwrap(PDFDocument(url: Self.scanFixture)?.page(at: 0))
        let geometry = LibraryPDF.recognisedLayout(of: page).lines.sorted { $0.maxY > $1.maxY }
            .map { String(format: "%.1f–%.1f %@", $0.minY, $0.maxY, String($0.text.prefix(24))) }
        XCTAssertEqual(doc.blocks.map(\.kind), [.heading, .paragraph, .paragraph, .paragraph],
                       (doc.blocks.map(\.text) + geometry).joined(separator: "\n"))
    }

    func testScannedPageIsRecognisedIntoLinesTopDown() throws {
        let doc = try XCTUnwrap(PDFDocument(url: Self.scanFixture))
        let page = try XCTUnwrap(doc.page(at: 0))
        XCTAssertEqual((page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines), "", "the fixture is pixels only")
        let layout = LibraryPDF.recognisedLayout(of: page)
        XCTAssertGreaterThanOrEqual(layout.lines.count, 8, "the letter's lines")
        let first = try XCTUnwrap(layout.lines.max { $0.maxY < $1.maxY })
        XCTAssertEqual(first.text, "Letter to the harbour office", "the top line is the heading")
        for line in layout.lines {
            XCTAssertLessThan(line.minY, line.maxY)
            XCTAssertTrue(line.minY >= 0 && line.maxY <= layout.height + 1, "y in page points")
            for w in line.words { XCTAssertTrue(w.minX < w.maxX && w.maxX <= layout.width + 1, "x in page points: \(w)") }
        }
        let words = try XCTUnwrap(layout.lines.first { $0.words.count > 5 }).words
        XCTAssertEqual(words.map(\.minX), words.map(\.minX).sorted(), "words left to right")
    }

    func testScanIsCachedBesideTheItemAndReused() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Q461-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pdf = dir.appendingPathComponent("book.pdf")
        try FileManager.default.copyItem(at: Self.scanFixture, to: pdf)
        let cache = LibraryPDF.scanCacheURL(for: pdf)
        XCTAssertEqual(cache.deletingLastPathComponent().standardizedFileURL, dir.standardizedFileURL, "beside the item")

        XCTAssertTrue(LibraryPDF.needsRecognition(url: pdf, cache: cache))
        let first = try XCTUnwrap(LibraryPDF.readingDoc(url: pdf, scanCache: cache), "a scan gets a reading view")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertFalse(LibraryPDF.needsRecognition(url: pdf, cache: cache), "read once")
        let signature = AudiobookPaths.signature(forFileAt: pdf)
        var pages = try XCTUnwrap(LibraryPDF.loadScanCache(cache, signature: signature))
        XCTAssertNil(LibraryPDF.loadScanCache(cache, signature: signature + "x"), "another file's cache is ignored")
        XCTAssertEqual(first.blocks.map(\.text), LibraryPDF.readingDoc(url: pdf, scanCache: cache)?.blocks.map(\.text),
                       "the cached read gives the same reading view")

        // A second open reads the cache, not the pixels: a doctored cache shows through.
        var page = try XCTUnwrap(pages[0])
        page.lines[0].words[0].text = "Doctored"
        pages[0] = page
        LibraryPDF.saveScanCache(pages, signature: signature, to: cache)
        let again = try XCTUnwrap(LibraryPDF.readingDoc(url: pdf, scanCache: cache))
        XCTAssertTrue(again.blocks.contains { $0.text.contains("Doctored") }, "the cache is used")
    }

    func testTextPDFNeedsNoRecognition() {
        XCTAssertFalse(LibraryPDF.needsRecognition(url: Self.fixtureDir.appendingPathComponent("book-page.pdf"), cache: nil))
    }

    @MainActor
    func testRenderTheReadingTheScanLine() throws {
        let view = PDFScanProgressLine()
            .frame(width: 390, height: 120)
            .background(Color.skBg)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(PDFScanProgressLine.label, "Reading the scan…")
        XCTAssertEqual(image.size.width, 390)
        let dir = ProcessInfo.processInfo.environment["SKRIFT_RENDER_DIR"] ?? NSTemporaryDirectory()
        try XCTUnwrap(image.pngData()).write(to: URL(fileURLWithPath: dir).appendingPathComponent("pdf-reading-scan.png"))
    }
}
