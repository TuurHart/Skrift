import XCTest
@testable import SkriftMobile

/// Q459 (D213): the pure layout rules of the PDF reading view (`PDFReflow` layout extension), on
/// hand-made page geometry. The real-shaped PDFs are measured by `PDFReadingGoldenTests`.
final class PDFLayoutReflowTests: XCTestCase {

    /// A line of words starting at `x`, 5 pt a character and 3 pt a space, `h` tall with its bottom at `y`.
    private func line(_ text: String, x: Double, y: Double, h: Double = 10) -> PDFReflow.Line {
        var words: [PDFReflow.Word] = []
        var cursor = x
        for w in text.split(separator: " ") {
            let width = Double(w.count) * 5
            words.append(PDFReflow.Word(text: String(w), minX: cursor, maxX: cursor + width))
            cursor += width + 3
        }
        return PDFReflow.Line(words: words, minY: y, maxY: y + h)
    }

    /// A table line: each cell's words placed from its own x.
    private func row(_ cells: [(String, Double)], y: Double, h: Double = 10) -> PDFReflow.Line {
        let parts = cells.map { line($0.0, x: $0.1, y: y, h: h) }
        return PDFReflow.Line(words: parts.flatMap(\.words), minY: y, maxY: y + h)
    }

    private func page(_ lines: [PDFReflow.Line]) -> PDFReflow.PageLayout {
        PDFReflow.PageLayout(width: 600, height: 800, lines: lines)
    }

    /// 222 pt wide: a column line on a 600 pt page.
    private func colLine(_ tag: String) -> String { "\(tag) words fill this column line from edge to edge" }

    func testATwoColumnPageReadsTheLeftColumnThenTheRight() {
        var lines = [line("A Title Across The Page", x: 200, y: 720, h: 16)]
        // The two columns share baselines and arrive interleaved (left, right, left, right…).
        for i in 0..<4 {
            let y = 680 - Double(i) * 13
            lines.append(line(colLine("L\(i)"), x: 60, y: y))
            lines.append(line(colLine("R\(i)"), x: 320, y: y))
        }
        lines.append(line("A footnote that runs the full width of the text area, under both columns.", x: 60, y: 560))
        let order = PDFReflow.readingOrder(lines).map { $0.line.words.first!.text }
        XCTAssertEqual(order, ["A", "L0", "L1", "L2", "L3", "R0", "R1", "R2", "R3", "A"])
        XCTAssertEqual(PDFReflow.readingOrder(lines).map(\.column), [0, 1, 1, 1, 1, 2, 2, 2, 2, 0])
    }

    func testAOneColumnPageKeepsItsLinesAndJoinsASharedBaseline() {
        let lines = [line("Second line of the text here", x: 60, y: 680),
                     line("First", x: 60, y: 700), line("half of the first line", x: 300, y: 700)]
        let placed = PDFReflow.readingOrder(lines)
        XCTAssertEqual(placed.map(\.line.text), ["First half of the first line", "Second line of the text here"])
        XCTAssertEqual(placed.map(\.column), [0, 0])
    }

    func testRunningHeadersFootersAndPageNumbersAreDropped() {
        let body = (0..<5).map { line("Body text line number one of the page goes here \($0)", x: 60, y: 600 - Double($0) * 13) }
        let pages = (1...3).map { n in
            page([line("Harbour Report 2025", x: 60, y: 760, h: 8), line("Draft", x: 500, y: 760, h: 8)]
                 + (n == 1 ? [line("Only On The First Page", x: 60, y: 745, h: 8)] : [])
                 + body
                 + [line("Page \(n) of 3", x: 280, y: 30, h: 8), line("\(n + 112)", x: 540, y: 30, h: 8)])
        }
        let kept = PDFReflow.dropFurniture(pages)
        XCTAssertEqual(kept[0].map(\.text).first, "Only On The First Page", "a line on one page of three is not running")
        for k in kept {
            XCTAssertFalse(k.contains { ["Harbour Report 2025", "Draft"].contains($0.text) || $0.text.hasPrefix("Page ") })
            XCTAssertFalse(k.contains { PDFReflow.isBarePageNumber($0.text) })
        }
        XCTAssertEqual(kept[1].count, 5, "the body stays")
        // A number in the body is text, not a folio.
        let single = PDFReflow.dropFurniture([page([line("42", x: 60, y: 400), line("7", x: 300, y: 20)])])
        XCTAssertEqual(single[0].map(\.text), ["42"])
    }

    func testBarePageNumbers() {
        for s in ["12", "- 12 -", "Page 3", "page 3 of 9", "3 / 9", "(4)"] { XCTAssertTrue(PDFReflow.isBarePageNumber(s), s) }
        for s in ["12 apples", "Chapter 3", "Table 2", "1,840"] { XCTAssertFalse(PDFReflow.isBarePageNumber(s), s) }
    }

    func testAWideTableKeepsItsRows() {
        let xs: [Double] = [100, 200, 260, 320, 400]
        let table = [["Site", "Visits", "Hours", "Cost (EUR)", "Notes"],
                     ["North quay", "412", "690", "1,840", "Ladder sound"],
                     ["Total", "940", "1,480", "5,910", "Within budget"]]
        var lines = [line("Site costs", x: 60, y: 700, h: 12),
                     line("The table below lists each survey site with its costs for the year.", x: 60, y: 680)]
        for (i, cells) in table.enumerated() {
            lines.append(row(Array(zip(cells, xs)), y: 650 - Double(i) * 14))
        }
        lines.append(line("The east steps cost the most for the fewest visits this season.", x: 60, y: 590))
        let blocks = PDFReflow.blocks(of: PDFReflow.readingOrder(lines), page: 1)
        XCTAssertEqual(blocks.map(\.kind), [.heading, .paragraph, .row, .row, .row, .paragraph])
        XCTAssertEqual(blocks.filter { $0.kind == .row }.map(\.cells), table)
    }

    func testVerticalSpaceEndsAParagraphAndStartsAHeading() {
        // Full-width lines (so the short-line rule never fires), 13 pt apart; a 25 pt gap before "Money".
        let full = "word word word word word word word word word word word word word word"
        let lines = [line(full + " one", x: 60, y: 700), line(full + " two.", x: 60, y: 687),
                     line("Money", x: 60, y: 662), line(full + " three", x: 60, y: 645), line(full + " four.", x: 60, y: 632)]
        let blocks = PDFReflow.blocks(of: PDFReflow.readingOrder(lines), page: 1)
        XCTAssertEqual(blocks.map(\.kind), [.paragraph, .heading, .paragraph])
        XCTAssertEqual(blocks[1].text, "Money")
    }

    func testAFullWidthColumnLineIsNeverAHeading() {
        // The first line of a paragraph right after a heading fills its column: text, not a heading.
        var lines = [line("Results", x: 60, y: 700, h: 12)]
        lines.append(line("Every logger drifted the worst by nine centimetres", x: 60, y: 684))
        lines.append(line("over the winter and the best by under two.", x: 60, y: 671))
        let blocks = PDFReflow.blocks(of: PDFReflow.readingOrder(lines), page: 1)
        XCTAssertEqual(blocks.map(\.kind), [.heading, .paragraph])
    }
}
