import XCTest
import UIKit
@testable import SkriftMobile

/// Q460 (D213): figures in the PDF reading view. A caption line ("Figure 1. …") next to an area
/// that holds only small labels is a figure: the reading view shows the area cropped from the page
/// as a picture, in its place, with its caption under it; the labels inside the drawing leave the
/// text. Also times the reading view of a generated 300-page text PDF (each word costs one
/// PDFSelection since Q459) and appends the number to `plan/reads/pdf-reading-structure.md`.
///
/// An extension of `PDFReadingGoldenTests`, so `plan/mtest.sh PDFReadingGoldenTests` runs it. The
/// timing test's name sorts after `testFixtureStructureMatchesItsRegisteredBaseline`, which rewrites
/// that file first, so the timing section lands under the structure table.
extension PDFReadingGoldenTests {

    private func word(_ t: String, _ x: Double, _ w: Double) -> PDFReflow.Word {
        PDFReflow.Word(text: t, minX: x, maxX: x + w)
    }

    /// One line of words starting at x 72, 6 points a character, `size` points tall at baseline `y`.
    private func line(_ text: String, y: Double, size: Double = 12, x: Double = 72) -> PDFReflow.Line {
        var words: [PDFReflow.Word] = []
        var at = x
        for t in text.split(separator: " ") {
            words.append(word(String(t), at, Double(t.count) * size * 0.5))
            at += Double(t.count + 1) * size * 0.5
        }
        return PDFReflow.Line(words: words, minY: y, maxY: y + size)
    }

    func testCaptionUnderAnAreaOfLabelsIsAFigure() {
        let body = "Counts follow the light more than the weather and the tally climbs from February onward"
        let page = PDFReflow.PageLayout(width: 612, height: 792, lines: [
            line(body, y: 700), line(body, y: 686), line(body, y: 672),
            line("60", y: 640, size: 7), line("Visits", y: 650, size: 7, x: 60),
            line("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", y: 520, size: 7, x: 100),
            line("Figure 1. Monthly visits to the north pier.", y: 500, size: 11, x: 180),
            line(body, y: 470), line(body, y: 456),
        ])
        let blocks = PDFReflow.reflow(layout: [page])
        XCTAssertEqual(blocks.map(\.kind), [.paragraph, .figure, .paragraph])
        let figure = blocks[1]
        XCTAssertEqual(figure.text, "Figure 1. Monthly visits to the north pier.")
        let r = try? XCTUnwrap(figure.region)
        XCTAssertEqual(r?.minY ?? 0, 512, accuracy: 0.5, "the area starts at the caption's top")
        XCTAssertEqual(r?.maxY ?? 0, 671, accuracy: 0.5, "and ends under the body line above it")
        XCTAssertLessThanOrEqual(r?.minX ?? 999, 60, "as wide as the text area and the labels")
        let text = blocks.map(\.text).joined(separator: " ")
        XCTAssertFalse(text.contains("Jan Feb"), "labels inside the figure leave the text")
        XCTAssertFalse(text.contains("Visits"), "the axis title too")
    }

    func testCaptionAboveItsAreaIsAFigureToo() {
        let body = "The winter months are thin but never empty and a handful of regular walkers come down"
        let page = PDFReflow.PageLayout(width: 612, height: 792, lines: [
            line(body, y: 700), line(body, y: 686),
            line("Fig. 2: Boats moored per week.", y: 660, size: 11, x: 200),
            line("Week 1 2 3 4", y: 600, size: 7, x: 120),
            line(body, y: 560), line(body, y: 546),
        ])
        let blocks = PDFReflow.reflow(layout: [page])
        XCTAssertEqual(blocks.map(\.kind), [.paragraph, .figure, .paragraph])
        XCTAssertEqual(blocks[1].region?.maxY ?? 0, 659, accuracy: 0.5)
        XCTAssertEqual(blocks[1].region?.minY ?? 0, 573, accuracy: 0.5)
    }

    func testAReferenceToAFigureInsideTheTextIsNotAFigure() {
        let body = "The count climbs from February as the evenings lengthen and holds through summer"
        let page = PDFReflow.PageLayout(width: 612, height: 792, lines: [
            line(body, y: 700), line("Figure 1. shows the count climbing from February into the summer", y: 686),
            line(body, y: 672),
        ])
        XCTAssertFalse(PDFReflow.reflow(layout: [page]).contains { $0.kind == .figure })
        XCTAssertTrue(PDFReflow.isCaptionStart("Figure 12: Visits"))
        XCTAssertTrue(PDFReflow.isCaptionStart("Fig. 3a. Detail"))
        XCTAssertFalse(PDFReflow.isCaptionStart("Figures show visits"))
    }

    func testFigureFixtureShowsItsPictureInPlace() throws {
        let pdf = Self.fixtureDir.appendingPathComponent("figure-caption.pdf")
        let doc = try XCTUnwrap(LibraryPDF.readingDoc(url: pdf))
        let figures = doc.blocks.filter { $0.kind == .figure }
        XCTAssertEqual(figures.count, 1)
        let figure = try XCTUnwrap(figures.first)
        XCTAssertTrue(figure.text.hasPrefix("Figure 1. Monthly visits"))
        let image = try XCTUnwrap(figure.image.flatMap { UIImage(data: $0) }, "the figure carries its picture")
        XCTAssertGreaterThan(image.size.width, 300)
        XCTAssertGreaterThan(image.size.height, 100)
        XCTAssertFalse(doc.plainText.contains("Jan Feb"), "the chart's month labels are inside the picture, not the text")
        // The reader's word index skips the picture: its count is the doc's.
        let built = ArticleLayout.build(doc, fontSize: 17, lineHeight: 1.5, noteQuotes: [], highlights: [],
                                        header: false, width: 360)
        XCTAssertEqual(built.wordStarts.count, doc.wordCount)
        XCTAssertTrue(built.text.containsAttachments(in: NSRange(location: 0, length: built.text.length)))
    }

    /// Q460 (Q459 doubt): the reading view of a 300-page text PDF, timed.
    func testReadingViewTimingOn300PagesAppendsToTheStructureRead() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("q460-300-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let sentence = "The harbour count climbs from February as the evenings lengthen and holds through the summer. "
        let font = UIFont(name: "Times New Roman", size: 11) ?? .systemFont(ofSize: 11)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style]
        let pageText = (0..<4).map { _ in String(repeating: sentence, count: 6) }.joined(separator: "\n\n")
        try UIGraphicsPDFRenderer(bounds: bounds).writePDF(to: url) { ctx in
            for n in 1...300 {
                ctx.beginPage()
                ("Chapter \(n)" as NSString).draw(at: CGPoint(x: 72, y: 60), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 14)])
                (pageText as NSString).draw(in: CGRect(x: 72, y: 90, width: 468, height: 640), withAttributes: attrs)
            }
        }
        let words = 300 * (4 * 6 * sentence.split(separator: " ").count + 2)
        let start = Date()
        let doc = LibraryPDF.readingDoc(url: url)
        let seconds = Date().timeIntervalSince(start)
        XCTAssertNotNil(doc)
        let section = """

        ## Timing (Q460)

        Generated by `PDFReadingGoldenTests.testReadingViewTimingOn300PagesAppendsToTheStructureRead` (phone, \
        iPhone 17 simulator). `LibraryPDF.readingDoc(url:)` on a generated 300-page text PDF \
        (\(words) words, one PDFSelection a word): **\(String(format: "%.2f", seconds)) s**.

        """
        let read = Self.repoRoot.appendingPathComponent("plan/reads/pdf-reading-structure.md")
        var existing = (try? String(contentsOf: read, encoding: .utf8)) ?? ""
        if let r = existing.range(of: "\n## Timing (Q460)") { existing = String(existing[..<r.lowerBound]) }
        try (existing + section).write(to: read, atomically: true, encoding: .utf8)
        print("Q460 timing: 300 pages, \(words) words, \(seconds) s")
    }
}
