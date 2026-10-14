import PDFKit
import UIKit
import XCTest
@testable import SkriftMobile

/// Q404 (Q6 mock "PDF reader", D207): a PDF with a usable text layer opens as a reflowed reading
/// view (headings, paragraphs, two-column rows, "Page N" at each page break) with "Original page"
/// one tap away. No text layer or a poor extraction → the real page only, no toggle.
final class PDFReflowTests: XCTestCase {

    private let budgetPage = """
    4. Budget
    The project runs for eighteen months. Costs below are for the first phase only;
    phase two is costed in Annex B.

    Sensor integration and field tests: €18,000 covers two test sites
    and the replacement parts we expect to burn through.

    Personnel €42,000
    Sensor integration and field tests €18,000
    Travel €3,200
    Total phase one €63,200

    We ask the panel to note that the field tests carry most of the technical risk.
    """

    // MARK: - Reflow

    func testReflowKeepsOrderAndMarksEveryPageBreak() {
        let pages = [budgetPage, "Annex B lists the second phase, which starts after the field tests end and runs a year.", "The team is four people, two of them part time, all of them in Lisbon for the whole project."]
        let blocks = PDFReflow.reflow(pages: pages)
        let kinds = blocks.map(\.kind)
        XCTAssertEqual(kinds.first, .heading, "the page's first short line is its heading")
        XCTAssertEqual(blocks.first?.text, "4. Budget")
        let markers = blocks.filter { $0.kind == .page }
        XCTAssertEqual(markers.map(\.text), ["Page 2", "Page 3"], "a marker at each page break, none before page 1")
        XCTAssertEqual(markers.map(\.page), [2, 3])
        // Order: every block of page 1 comes before the page-2 marker, page 2 before page 3.
        XCTAssertEqual(blocks.map(\.page), blocks.map(\.page).sorted(), "blocks stay in page order")
        let text = blocks.map(\.text).joined(separator: "\n")
        let a = text.range(of: "eighteen months")!.lowerBound
        let b = text.range(of: "replacement parts")!.lowerBound
        let c = text.range(of: "Annex B lists")!.lowerBound
        let d = text.range(of: "four people")!.lowerBound
        XCTAssertTrue(a < b && b < c && c < d, "the reading order is the page order")
    }

    func testLinesJoinIntoParagraphsAndABlankLineSplitsThem() {
        let blocks = PDFReflow.reflow(pages: [budgetPage]).filter { $0.kind == .paragraph }
        XCTAssertEqual(blocks.first?.text,
                       "The project runs for eighteen months. Costs below are for the first phase only; phase two is costed in Annex B.")
        XCTAssertEqual(blocks.dropFirst().first?.text,
                       "Sensor integration and field tests: €18,000 covers two test sites and the replacement parts we expect to burn through.")
        XCTAssertEqual(blocks.last?.text,
                       "We ask the panel to note that the field tests carry most of the technical risk.")
    }

    func testAWordBrokenAcrossALineIsMendedWhenTheHyphenEndsTheLine() {
        let blocks = PDFReflow.reflow(pages: ["We tested the replace-\nment parts on both sites before the panel met in May."])
        XCTAssertEqual(blocks.map(\.text), ["We tested the replacement parts on both sites before the panel met in May."])
    }

    func testASimpleTwoColumnTableBecomesRows() {
        let rows = PDFReflow.reflow(pages: [budgetPage]).filter { $0.kind == .row }
        XCTAssertEqual(rows.map(\.cells), [["Personnel", "€42,000"],
                                           ["Sensor integration and field tests", "€18,000"],
                                           ["Travel", "€3,200"],
                                           ["Total phase one", "€63,200"]])
    }

    func testOneLineEndingInANumberInsideProseStaysProse() {
        let blocks = PDFReflow.reflow(pages: ["The first field test ran from March to the end of 2019\nand the second one is planned for the spring."])
        XCTAssertEqual(blocks.map(\.kind), [.paragraph], "a lone amount-shaped line is not a table")
    }

    // MARK: - Quality: when the reading view is offered

    func testAGoodTextLayerIsUsable() {
        XCTAssertTrue(PDFReflow.isUsable(pages: [budgetPage, budgetPage]))
    }

    func testNoTextOrTooFewWordsPerPageIsNotUsable() {
        XCTAssertFalse(PDFReflow.isUsable(pages: ["", "", ""]), "a scan has no text layer")
        XCTAssertFalse(PDFReflow.isUsable(pages: []))
        XCTAssertFalse(PDFReflow.isUsable(pages: ["Page 1", "Page 2", "Page 3", "Page 4"]),
                       "two words a page is a page number, not a text layer")
    }

    func testAGarbledExtractionIsNotUsable() {
        let garbled = String(repeating: "\u{FFFD}\u{FFFD}x \u{E001}\u{E002}q %$#@ ", count: 40)
        XCTAssertGreaterThan(PDFReflow.garbledRatio(pages: [garbled]), PDFReflow.maxGarbledRatio)
        XCTAssertFalse(PDFReflow.isUsable(pages: [garbled]))
        XCTAssertLessThan(PDFReflow.garbledRatio(pages: [budgetPage]), 0.05)
    }

    // MARK: - The reader: toggle only with a usable text layer

    private func makePDF(draw: (UIGraphicsPDFRendererContext) -> Void) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("reflow_\(UUID().uuidString).pdf")
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData(actions: draw)
        try data.write(to: url)
        return url
    }

    func testAScannedPDFHasNoReadingViewAndNoToggle() throws {
        // An image-only page: pixels, no text layer.
        let url = try makePDF { ctx in
            for _ in 0..<3 {
                ctx.beginPage()
                UIColor.darkGray.setFill()
                for row in 0..<20 { UIRectFill(CGRect(x: 56, y: CGFloat(60 + row * 24), width: 480, height: 10)) }
            }
        }
        XCTAssertNil(LibraryPDF.readingDoc(url: url), "a scan opens on the real page")
        XCTAssertFalse(PDFReaderMode.showsToggle(hasReadingView: false))
        XCTAssertEqual(PDFReaderMode.resolved(hasReadingView: false, prefersOriginal: false), .original)
    }

    func testATextPDFOpensReflowedWithTheToggle() throws {
        let line = "The project runs for eighteen months and the costs below are for the first phase only."
        let url = try makePDF { ctx in
            for p in 1...3 {
                ctx.beginPage()
                ("Section \(p)" as NSString).draw(at: CGPoint(x: 56, y: 60),
                                                  withAttributes: [.font: UIFont.boldSystemFont(ofSize: 15)])
                for i in 0..<4 {
                    (line as NSString).draw(at: CGPoint(x: 56, y: 96 + CGFloat(i) * 20),
                                            withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
                }
            }
        }
        let doc = try XCTUnwrap(LibraryPDF.readingDoc(url: url))
        XCTAssertEqual(doc.blocks.filter { $0.kind == .page }.map(\.text), ["Page 2", "Page 3"])
        XCTAssertTrue(PDFReaderMode.showsToggle(hasReadingView: true))
        XCTAssertEqual(PDFReaderMode.resolved(hasReadingView: true, prefersOriginal: false), .reading)
        XCTAssertEqual(PDFReaderMode.resolved(hasReadingView: true, prefersOriginal: true), .original)
        // Word places map back to pages: the page-3 marker's word is on page 3, the first word on page 1.
        let page3 = LibraryPDF.startWord(page: 3, in: doc)
        XCTAssertEqual(LibraryPDF.page(atWord: page3, in: doc), 3)
        XCTAssertEqual(LibraryPDF.page(atWord: 0, in: doc), 1)
        XCTAssertEqual(LibraryPDF.startWord(page: 1, in: doc), 0)
    }

    func testOriginalPageIsRememberedPerPDF() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "reflow_\(UUID().uuidString)"))
        let a = UUID(), b = UUID()
        XCTAssertFalse(PDFReaderMode.prefersOriginal(bookID: a, defaults: defaults), "reading view by default")
        PDFReaderMode.setPrefersOriginal(true, bookID: a, defaults: defaults)
        XCTAssertTrue(PDFReaderMode.prefersOriginal(bookID: a, defaults: defaults))
        XCTAssertFalse(PDFReaderMode.prefersOriginal(bookID: b, defaults: defaults), "per PDF, not global")
        PDFReaderMode.setPrefersOriginal(false, bookID: a, defaults: defaults)
        XCTAssertFalse(PDFReaderMode.prefersOriginal(bookID: a, defaults: defaults))
    }
}
