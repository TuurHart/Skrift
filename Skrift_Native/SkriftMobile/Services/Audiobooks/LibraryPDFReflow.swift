import Foundation
import PDFKit
import UIKit

/// Q404 (Q6 mock "PDF reader", D207): the PDF's reading view. A PDF with a usable text layer
/// (`PDFReflow.isUsable`) reads as reflowed text in the article reader's text view; the real page
/// is one tap away. Q461: a scanned or garbled page is read by on-device text recognition first
/// (`LibraryPDFScan.swift`); only when that too yields no usable text is there no reading view.
extension LibraryPDF {
    /// Each page's text layer, in page order. nil when the file is not a readable PDF.
    static func pageStrings(url: URL) -> [String]? {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { return nil }
        return (0..<doc.pageCount).map { doc.page(at: $0)?.string ?? "" }
    }

    /// Q459 (D213): one page's printed lines with their word positions, for `PDFReflow`'s layout
    /// rules. PDFKit's own line selections give the lines; each word's box comes from a selection
    /// of its character range (`page.characterBounds(at:)` does not share `page.string`'s indices).
    /// x from the page box's left edge, y from its bottom edge.
    static func layout(of page: PDFPage) -> PDFReflow.PageLayout {
        let box = page.bounds(for: .mediaBox)
        let full = (page.string ?? "") as NSString
        func isSpace(_ i: Int) -> Bool {
            UnicodeScalar(full.character(at: i)).map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false
        }
        var lines: [PDFReflow.Line] = []
        for sel in page.selection(for: box)?.selectionsByLine() ?? [] {
            var words: [PDFReflow.Word] = []
            for t in 0..<sel.numberOfTextRanges(on: page) {
                let range = sel.range(at: t, on: page)
                guard range.location != NSNotFound, NSMaxRange(range) <= full.length else { continue }
                var i = range.location
                while i < NSMaxRange(range) {
                    if isSpace(i) { i += 1; continue }
                    var j = i
                    while j < NSMaxRange(range), !isSpace(j) { j += 1 }
                    let word = NSRange(location: i, length: j - i)
                    if let b = page.selection(for: word)?.bounds(for: page), !b.isNull, !b.isEmpty {
                        words.append(PDFReflow.Word(text: full.substring(with: word),
                                                    minX: Double(b.minX - box.minX), maxX: Double(b.maxX - box.minX)))
                    }
                    i = j
                }
            }
            let r = sel.bounds(for: page)
            guard !words.isEmpty, !r.isNull else { continue }
            lines.append(PDFReflow.Line(words: words, minY: Double(r.minY - box.minY), maxY: Double(r.maxY - box.minY)))
        }
        return PDFReflow.PageLayout(width: Double(box.width), height: Double(box.height), lines: lines)
    }

    /// The reading view's text as the article reader's doc, or nil (real page only). Synchronous;
    /// call it off the main thread for a long PDF. Q459: shaped from each page's line geometry
    /// (column order, no running headers/footers, tables as rows); the quality check still reads
    /// the raw text layer.
    static func readingDoc(url: URL, scanCache: URL? = nil) -> ArticleDoc? {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { return nil }
        let pages = (0..<doc.pageCount).compactMap { doc.page(at: $0) }
        let image: (PDFReflow.Block) -> Data? = { block in
            guard let region = block.region, block.page >= 1, block.page <= pages.count else { return nil }
            return figureImage(page: pages[block.page - 1], region: region)
        }
        // Q461: a scanned or garbled page reads by on-device text recognition (LibraryPDFScan.swift).
        if let scanned = scannedLayouts(url: url, pages: pages, texts: pages.map { $0.string ?? "" }, cache: scanCache) {
            guard PDFReflow.isUsable(pages: scanned.map(PDFReflow.pageText)) else { return nil }
            return readingDoc(blocks: PDFReflow.reflow(layout: scanned), image: image)
        }
        guard PDFReflow.isUsable(pages: pages.map { $0.string ?? "" }) else { return nil }
        return readingDoc(blocks: PDFReflow.reflow(layout: pages.map(layout(of:))), image: image)
    }

    /// Q460 (D213): a figure's picture: its page drawn at `scale` points-to-pixels, cropped to the
    /// figure's region (PDF points from the page box's bottom-left corner). PNG, nil when empty.
    static func figureImage(page: PDFPage, region: PDFReflow.Block.Region, scale: CGFloat = 2) -> Data? {
        let box = page.bounds(for: .mediaBox)
        guard region.width >= 1, region.height >= 1, box.width >= 1, box.height >= 1 else { return nil }
        let size = CGSize(width: region.width, height: region.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let cg = ctx.cgContext
            // UIKit is y-down, PDF y-up: flip, then put the region's bottom-left at the origin.
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            cg.translateBy(x: -CGFloat(region.minX), y: -CGFloat(region.minY))
            page.draw(with: .mediaBox, to: cg)
        }
        return image.pngData()
    }

    /// The text-only path (no geometry): `page.string` per page.
    static func readingDoc(pages: [String]) -> ArticleDoc? {
        guard PDFReflow.isUsable(pages: pages) else { return nil }
        return readingDoc(blocks: PDFReflow.reflow(pages: pages))
    }

    private static func readingDoc(blocks reflowed: [PDFReflow.Block],
                                   image: (PDFReflow.Block) -> Data? = { _ in nil }) -> ArticleDoc? {
        let blocks = reflowed.map { b -> ArticleDoc.Block in
            let kind: ArticleDoc.Block.Kind
            switch b.kind {
            case .heading: kind = .heading
            case .paragraph: kind = .paragraph
            case .row: kind = .row
            case .page: kind = .page
            case .figure: kind = .figure
            }
            return ArticleDoc.Block(kind: kind, text: b.text, page: b.page,
                                    image: b.kind == .figure ? image(b) : nil)
        }
        guard !blocks.isEmpty else { return nil }
        return ArticleDoc(url: "", title: "", site: "", publisher: nil, byline: nil, published: nil, blocks: blocks)
    }

    private static func words(_ s: String) -> Int { s.split(whereSeparator: \.isWhitespace).count }

    /// Words of the reading view before page `page` starts (its "Page N" marker). 0 for page 1.
    static func startWord(page: Int, in doc: ArticleDoc) -> Int {
        var seen = 0
        for block in doc.blocks {
            if (block.page ?? 1) >= page { return seen }
            seen += words(block.text)
        }
        return seen
    }

    /// The page the word `word` of the reading view is on.
    static func page(atWord word: Int, in doc: ArticleDoc) -> Int {
        var seen = 0
        for block in doc.blocks {
            let n = words(block.text)
            if word < seen + n { return block.page ?? 1 }
            seen += n
        }
        return doc.blocks.last?.page ?? 1
    }
}

/// Q404: which face of the PDF the reader shows. The reading view by default when it exists;
/// "Original page" is remembered per PDF (local to the device: a view preference, not content).
enum PDFReaderMode {
    enum Mode: Equatable { case reading, original }

    static func showsToggle(hasReadingView: Bool) -> Bool { hasReadingView }

    static func resolved(hasReadingView: Bool, prefersOriginal: Bool) -> Mode {
        hasReadingView && !prefersOriginal ? .reading : .original
    }

    static func key(_ bookID: UUID) -> String { "pdfOriginalPage.\(bookID.uuidString)" }

    static func prefersOriginal(bookID: UUID, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key(bookID))
    }

    static func setPrefersOriginal(_ on: Bool, bookID: UUID, defaults: UserDefaults = .standard) {
        if on { defaults.set(true, forKey: key(bookID)) } else { defaults.removeObject(forKey: key(bookID)) }
    }
}
