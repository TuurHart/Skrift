import Foundation
import PDFKit

/// Q404 (Q6 mock "PDF reader", D207): the PDF's reading view. A PDF with a usable text layer
/// (`PDFReflow.isUsable`) reads as reflowed text in the article reader's text view; the real page
/// is one tap away. A scan or a garbled extraction has no reading view and no toggle.
extension LibraryPDF {
    /// Each page's text layer, in page order. nil when the file is not a readable PDF.
    static func pageStrings(url: URL) -> [String]? {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { return nil }
        return (0..<doc.pageCount).map { doc.page(at: $0)?.string ?? "" }
    }

    /// The reading view's text as the article reader's doc, or nil (real page only). Synchronous;
    /// call it off the main thread for a long PDF.
    static func readingDoc(url: URL) -> ArticleDoc? {
        guard let pages = pageStrings(url: url) else { return nil }
        return readingDoc(pages: pages)
    }

    static func readingDoc(pages: [String]) -> ArticleDoc? {
        guard PDFReflow.isUsable(pages: pages) else { return nil }
        let blocks = PDFReflow.reflow(pages: pages).map { b -> ArticleDoc.Block in
            let kind: ArticleDoc.Block.Kind
            switch b.kind {
            case .heading: kind = .heading
            case .paragraph: kind = .paragraph
            case .row: kind = .row
            case .page: kind = .page
            }
            return ArticleDoc.Block(kind: kind, text: b.text, page: b.page)
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
