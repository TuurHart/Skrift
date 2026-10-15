import Foundation

/// Q404 (Q6 mock "PDF reader", D207): the text-shaping rules that turn a PDF's text layer (one
/// string per page, PDFKit's `page.string`) into a reading view: headings, paragraphs, simple
/// two-column tables as rows, and a "Page N" marker at each page break. Plus the quality rule
/// that decides whether the reading view is offered at all (a scan or a garbled extraction keeps
/// the real page only). SHARED phone and Mac, pure Foundation, so both apps shape a PDF the same.
enum PDFReflow {
    struct Block: Equatable, Sendable {
        enum Kind: String, Sendable { case heading, paragraph, row, page }
        var kind: Kind
        /// A row's cells are joined by a tab.
        var text: String
        /// 1-based page the block comes from.
        var page: Int

        var cells: [String] { kind == .row ? text.components(separatedBy: "\t") : [text] }
    }

    /// Fewer words a page than this is a scan with page numbers, not a text layer.
    static let minWordsPerPage = 15.0
    /// More than this share of garbled tokens is a broken extraction (wrong font encoding).
    static let maxGarbledRatio = 0.25

    static func pageMarker(_ page: Int) -> String { "Page \(page)" }

    // MARK: - Quality

    static func wordsPerPage(pages: [String]) -> Double {
        guard !pages.isEmpty else { return 0 }
        let words = pages.reduce(0) { $0 + $1.split(whereSeparator: \.isWhitespace).count }
        return Double(words) / Double(pages.count)
    }

    /// Share of whitespace-split tokens that are not text: a replacement or private-use character,
    /// a control character, or fewer than half letters and digits. 1 for no tokens at all.
    static func garbledRatio(pages: [String]) -> Double {
        var total = 0, bad = 0
        for page in pages {
            for token in page.split(whereSeparator: \.isWhitespace) {
                total += 1
                if isGarbled(token) { bad += 1 }
            }
        }
        return total == 0 ? 1 : Double(bad) / Double(total)
    }

    static func isGarbled(_ token: Substring) -> Bool {
        var textual = 0, count = 0
        for s in token.unicodeScalars {
            count += 1
            let v = s.value
            if v == 0xFFFD || (0xE000...0xF8FF).contains(v) || s.properties.generalCategory == .control { return true }
            if CharacterSet.alphanumerics.contains(s) { textual += 1 }
        }
        return count == 0 || Double(textual) / Double(count) < 0.5
    }

    /// True when the reading view is worth offering for these pages.
    static func isUsable(pages: [String]) -> Bool {
        !pages.isEmpty && wordsPerPage(pages: pages) >= minWordsPerPage
            && garbledRatio(pages: pages) <= maxGarbledRatio
    }

    // MARK: - Reflow

    static func reflow(pages: [String]) -> [Block] {
        var out: [Block] = []
        for (i, page) in pages.enumerated() {
            if i > 0 { out.append(Block(kind: .page, text: pageMarker(i + 1), page: i + 1)) }
            out.append(contentsOf: blocks(of: page, page: i + 1))
        }
        return out
    }

    /// One page: rows first (a run of two or more label + value lines), then headings and
    /// paragraphs. A paragraph ends at a blank line, or at a line that ends a sentence and is
    /// clearly shorter than the page's longest line.
    static func blocks(of text: String, page: Int) -> [Block] {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let rowCells = lines.map(rowCells(_:))
        var isRow = Array(repeating: false, count: lines.count)
        var i = 0
        while i < lines.count {
            var j = i
            while j < lines.count, rowCells[j] != nil { j += 1 }
            if j - i >= 2 { for k in i..<j { isRow[k] = true } }
            i = max(j, i + 1)
        }
        let longest = lines.enumerated().filter { !isRow[$0.offset] }.map(\.element.count).max() ?? 0

        var out: [Block] = []
        var para: [String] = []
        func flush() {
            guard !para.isEmpty else { return }
            out.append(Block(kind: .paragraph, text: join(para), page: page))
            para = []
        }
        for (n, line) in lines.enumerated() {
            if line.isEmpty { flush(); continue }
            if isRow[n], let cells = rowCells[n] {
                flush()
                out.append(Block(kind: .row, text: cells.joined(separator: "\t"), page: page))
                continue
            }
            if para.isEmpty, isHeading(line) {
                out.append(Block(kind: .heading, text: collapse(line), page: page))
                continue
            }
            para.append(line)
            if endsSentence(line), Double(line.count) < Double(longest) * 0.8 { flush() }
        }
        flush()
        return out
    }

    /// Lines joined with one space; a word broken by a hyphen at a line end is mended.
    static func join(_ lines: [String]) -> String {
        var s = ""
        for line in lines {
            let next = collapse(line)
            if s.isEmpty { s = next; continue }
            if s.hasSuffix("-"), s.dropLast().last?.isLetter == true, next.first?.isLowercase == true {
                s.removeLast()
                s += next
            } else {
                s += " " + next
            }
        }
        return s
    }

    static func collapse(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func endsSentence(_ line: String) -> Bool {
        guard let last = line.last else { return false }
        return ".!?:;\u{201D}\")".contains(last)
    }

    /// A short line that does not end like a sentence and starts with a capital or a number
    /// ("4. Budget", "Methods").
    static func isHeading(_ line: String) -> Bool {
        let words = line.split(whereSeparator: \.isWhitespace)
        guard let first = line.first, let last = line.last, !words.isEmpty, words.count <= 8, line.count <= 70,
              line.contains(where: \.isLetter) else { return false }
        if ".,;:!?-\u{2013}\u{2014}".contains(last) { return false }
        return first.isUppercase || first.isNumber
    }

    /// A table line's two cells: "label<tab or 2+ spaces>value", or "label amount" where the
    /// amount is a number with an optional currency or percent. The label is short text (8 words
    /// at most), so a sentence ending in a year is never a row.
    static func rowCells(_ line: String) -> [String]? {
        guard !line.isEmpty else { return nil }
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        func label(_ s: String) -> Bool {
            let w = s.split(whereSeparator: \.isWhitespace).count
            return w >= 1 && w <= 8 && s.count <= 60 && s.contains(where: \.isLetter)
        }
        if let m = columnGap.firstMatch(in: line, range: full) {
            let a = collapse(ns.substring(with: m.range(at: 1))), b = collapse(ns.substring(with: m.range(at: 2)))
            if label(a), b.split(whereSeparator: \.isWhitespace).count <= 4 { return [a, b] }
        }
        if let m = trailingAmount.firstMatch(in: line, range: full) {
            let a = collapse(ns.substring(with: m.range(at: 1))), b = ns.substring(with: m.range(at: 2))
            if label(a) { return [a, b] }
        }
        return nil
    }

    private static let columnGap = try! NSRegularExpression(pattern: #"^(\S.*?)(?:\t+|\s{2,})(\S.*)$"#)
    private static let trailingAmount = try! NSRegularExpression(
        pattern: #"^(.*\S)\s+((?:[€$£¥]\s?)?[-+]?\d[\d.,]*(?:\s?(?:%|€|k|K|m|M))?)$"#)
}

// MARK: - Layout (Q459, D213)

/// Q459 (D213): the same reading view, read from the page's LINE GEOMETRY instead of its raw text.
/// The PDFKit side (`LibraryPDF.layout(of:)`) hands over each page's lines with word positions;
/// these rules put a two-column page in reading order (left column, then right), drop running
/// headers/footers and bare page numbers, keep a table of any width as rows (cells = the gaps in a
/// line wider than its type), and break paragraphs on vertical space as well as on short lines.
extension PDFReflow {
    /// One word on a page: its text and horizontal extent, in PDF points from the page's left edge.
    struct Word: Equatable, Sendable {
        var text: String
        var minX: Double
        var maxX: Double
    }

    /// One printed line: its words left to right and its vertical extent, in PDF points from the
    /// page's BOTTOM edge (PDF space: a higher line has a larger y).
    struct Line: Equatable, Sendable {
        var words: [Word]
        var minY: Double
        var maxY: Double

        var minX: Double { words.map(\.minX).min() ?? 0 }
        var maxX: Double { words.map(\.maxX).max() ?? 0 }
        var width: Double { maxX - minX }
        var height: Double { max(maxY - minY, 1) }
        var text: String { PDFReflow.collapse(words.map(\.text).joined(separator: " ")) }
    }

    struct PageLayout: Equatable, Sendable {
        var width: Double
        var height: Double
        var lines: [Line]
    }

    /// Running headers and footers live in this share of the page height, top and bottom.
    static let furnitureBand = 0.10
    /// A gap between two words wider than this many line heights splits a line into table cells
    /// (a justified word space stays under 0.8; a table's column padding is 1.5 and up).
    static let cellGap = 1.2
    /// A column line is at least this share of the page's text width.
    static let columnLineShare = 0.3

    /// The plain text of a page, lines top to bottom (the quality check reads this).
    static func pageText(_ layout: PageLayout) -> String {
        layout.lines.map(\.text).joined(separator: "\n")
    }

    static func reflow(layout pages: [PageLayout]) -> [Block] {
        let kept = dropFurniture(pages)
        var out: [Block] = []
        for i in pages.indices {
            if i > 0 { out.append(Block(kind: .page, text: pageMarker(i + 1), page: i + 1)) }
            out.append(contentsOf: blocks(of: readingOrder(kept[i]), page: i + 1))
        }
        return out
    }

    // MARK: Furniture

    /// A line's identity across pages: lowercased, digits folded ("Page 1 of 2" = "Page 2 of 2").
    static func furnitureKey(_ text: String) -> String {
        collapse(text).lowercased().replacingOccurrences(of: #"\d+"#, with: "#", options: .regularExpression)
    }

    /// "12", "- 12 -", "Page 3", "Page 3 of 9", "3 / 9".
    static func isBarePageNumber(_ text: String) -> Bool {
        collapse(text).range(of: #"^(?i:page\s+)?[-–—(\[]?\s*\d{1,4}\s*[-–—)\]]?(?:\s*(?:/|(?i:of))\s*\d{1,4})?$"#,
                             options: .regularExpression) != nil
    }

    static func inFurnitureBand(_ line: Line, pageHeight: Double) -> Bool {
        line.minY >= pageHeight * (1 - furnitureBand) - 1 || line.maxY <= pageHeight * furnitureBand + 1
    }

    /// Each page's lines without its running headers/footers (a line in the top or bottom band
    /// whose text, digits folded, sits at the same height on at least half the pages, two at
    /// least) and without bare page numbers in those bands.
    static func dropFurniture(_ pages: [PageLayout]) -> [[Line]] {
        struct Mark { let key: String; let y: Double }
        func mark(_ line: Line, _ page: PageLayout) -> Mark {
            Mark(key: furnitureKey(line.text), y: (line.minY + line.maxY) / 2 / max(page.height, 1))
        }
        let marks: [[Mark]] = pages.map { p in
            p.lines.filter { inFurnitureBand($0, pageHeight: p.height) }.map { mark($0, p) }
        }
        let need = max(2, Int((Double(pages.count) / 2).rounded(.up)))
        return pages.map { page in
            page.lines.filter { line in
                guard inFurnitureBand(line, pageHeight: page.height) else { return true }
                if isBarePageNumber(line.text) { return false }
                let m = mark(line, page)
                let repeats = marks.filter { $0.contains { $0.key == m.key && abs($0.y - m.y) <= 0.01 } }.count
                return repeats < need
            }
        }
    }

    // MARK: Reading order

    /// A line in reading order, with the width of the column (or full text area) it sits in.
    struct Placed: Equatable, Sendable {
        var line: Line
        var regionWidth: Double
        /// 0 full width, 1 left column, 2 right column.
        var column: Int
    }

    /// Lines in reading order. A page with a gutter (three or more wide lines entirely on each side
    /// of its centre) reads by column: between two full-width lines, the left column top to bottom,
    /// then the right. Lines that share a baseline inside one column (or on a one-column page) are
    /// one line.
    static func readingOrder(_ lines: [Line]) -> [Placed] {
        guard let areaMin = lines.map(\.minX).min(), let areaMax = lines.map(\.maxX).max() else { return [] }
        let areaWidth = max(areaMax - areaMin, 1), mid = (areaMin + areaMax) / 2
        let wide = lines.filter { $0.width >= areaWidth * columnLineShare }
        let left = wide.filter { $0.maxX < mid }, right = wide.filter { $0.minX > mid }
        let topDown = lines.sorted { $0.maxY != $1.maxY ? $0.maxY > $1.maxY : $0.minX < $1.minX }
        guard left.count >= 3, right.count >= 3,
              let leftEdge = left.map(\.maxX).max(), let rightEdge = right.map(\.minX).min(), leftEdge < rightEdge,
              let leftWidth = left.map(\.width).max(), let rightWidth = right.map(\.width).max() else {
            return mergeBaselines(topDown).map { Placed(line: $0, regionWidth: areaWidth, column: 0) }
        }
        let gutter = (leftEdge + rightEdge) / 2
        var out: [Placed] = []
        var l: [Line] = [], r: [Line] = []
        func flushColumns() {
            out += mergeBaselines(l).map { Placed(line: $0, regionWidth: leftWidth, column: 1) }
            out += mergeBaselines(r).map { Placed(line: $0, regionWidth: rightWidth, column: 2) }
            l = []; r = []
        }
        for line in topDown {
            if line.maxX <= gutter { l.append(line) }
            else if line.minX >= gutter { r.append(line) }
            else {
                flushColumns()
                out.append(Placed(line: line, regionWidth: areaWidth, column: 0))
            }
        }
        flushColumns()
        return out
    }

    /// Lines (top to bottom) that overlap vertically by half the smaller height become one line.
    static func mergeBaselines(_ lines: [Line]) -> [Line] {
        var out: [Line] = []
        for line in lines {
            if let last = out.last,
               min(last.maxY, line.maxY) - max(last.minY, line.minY) >= 0.5 * min(last.height, line.height) {
                var merged = last
                merged.words = (last.words + line.words).sorted { $0.minX < $1.minX }
                merged.minY = min(last.minY, line.minY)
                merged.maxY = max(last.maxY, line.maxY)
                out[out.count - 1] = merged
            } else {
                out.append(line)
            }
        }
        return out
    }

    // MARK: Blocks

    /// A line's table cells: runs of words split where the gap is wider than `cellGap` line heights.
    static func cells(of line: Line) -> [String] {
        var out: [[String]] = []
        var lastMax: Double?
        for w in line.words.sorted(by: { $0.minX < $1.minX }) {
            if let m = lastMax, w.minX - m <= cellGap * line.height { out[out.count - 1].append(w.text) }
            else { out.append([w.text]) }
            lastMax = max(lastMax ?? w.maxX, w.maxX)
        }
        return out.map { collapse($0.joined(separator: " ")) }
    }

    /// One page's placed lines: rows first (a run of two or more lines in one column that split
    /// into cells), then headings and paragraphs. A paragraph ends at a font change, at vertical
    /// space wider than the page's usual line gap, or at a line that ends a sentence and is
    /// clearly shorter than its column.
    static func blocks(of placed: [Placed], page: Int) -> [Block] {
        let rowCells: [[String]?] = placed.map { p in
            let c = cells(of: p.line)
            return c.count >= 2 ? c : PDFReflow.rowCells(p.line.text)
        }
        var isRow = Array(repeating: false, count: placed.count)
        var i = 0
        while i < placed.count {
            var j = i
            while j < placed.count, rowCells[j] != nil, j == i || placed[j].column == placed[i].column { j += 1 }
            if j - i >= 2 { for k in i..<j { isRow[k] = true } }
            i = max(j, i + 1)
        }
        // The page's usual gap between two lines of one column (median), for paragraph spacing.
        var gaps: [Double] = []
        for n in placed.indices.dropFirst() where placed[n].column == placed[n - 1].column {
            let g = placed[n - 1].line.minY - placed[n].line.maxY
            if g >= 0, g < 2 * placed[n].line.height { gaps.append(g) }
        }
        let usualGap = gaps.sorted().dropFirst(gaps.count / 2).first ?? 0

        var out: [Block] = []
        var para: [String] = []
        func flush() {
            guard !para.isEmpty else { return }
            out.append(Block(kind: .paragraph, text: join(para), page: page))
            para = []
        }
        for (n, p) in placed.enumerated() {
            let line = p.line, text = line.text
            if isRow[n], let cells = rowCells[n] {
                flush()
                out.append(Block(kind: .row, text: cells.joined(separator: "\t"), page: page))
                continue
            }
            // From the foot of the left column to the head of the right one, a paragraph runs on.
            if n > 0, !(placed[n - 1].column == 1 && p.column == 2) {
                let prev = placed[n - 1].line
                let gap = prev.minY - line.maxY
                let fontChange = abs(prev.height - line.height) > 0.12 * max(prev.height, line.height)
                if gap > usualGap + 0.4 * line.height || fontChange { flush() }
            }
            // A heading is short for its column: a full-width first line is a paragraph's.
            if para.isEmpty, isHeading(text), line.width < p.regionWidth * 0.8 {
                out.append(Block(kind: .heading, text: text, page: page))
                continue
            }
            para.append(text)
            if endsSentence(text), line.width < p.regionWidth * 0.8 { flush() }
        }
        flush()
        return out
    }
}
