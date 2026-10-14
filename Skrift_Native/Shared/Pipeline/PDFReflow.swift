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
