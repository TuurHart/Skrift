import CoreGraphics
import Foundation
import PDFKit
import Vision

/// Q461 (D213, C120): a scanned or image-only PDF page reads by ON-DEVICE text recognition. When a
/// page's PDFKit text layer is missing or garbled, the page is drawn to an image and Vision's
/// `VNRecognizeTextRequest` (accurate, English + Dutch) reads its lines; those lines go through
/// the same `PDFReflow.reflow(layout:)` rules as a born-digital page. Vision runs on the device:
/// no network call is made here, ever (C120). The result is cached beside the library item
/// (`pdf_scan.json` in the book's folder), keyed by the PDF's size + mtime, so a scan is read once.
extension LibraryPDF {
    /// The languages asked of Vision, in order. Those the device does not support are dropped.
    static let recognitionLanguages = ["en-US", "nl-NL"]
    /// The page image's long side in pixels (a Letter page at about 220 dpi).
    static let recognitionLongSide: CGFloat = 2400
    static let scanCacheName = "pdf_scan.json"

    /// The cache beside a library PDF: the book's folder.
    static func scanCacheURL(for pdf: URL) -> URL {
        pdf.deletingLastPathComponent().appendingPathComponent(scanCacheName)
    }

    /// The 0-based pages to read by text recognition. A page whose text layer is missing or garbled
    /// always; on a PDF whose text layer as a whole is not usable (a scan with a page-number
    /// layer), also every page too sparse to be text on its own.
    static func pagesToRecognise(_ texts: [String]) -> [Int] {
        let docUsable = PDFReflow.isUsable(pages: texts)
        return texts.indices.filter { i in
            let page = [texts[i]]
            if PDFReflow.garbledRatio(pages: page) > PDFReflow.maxGarbledRatio { return true }
            return !docUsable && PDFReflow.wordsPerPage(pages: page) < PDFReflow.minWordsPerPage
        }
    }

    /// True when opening this PDF will run text recognition (some page needs it and the cache does
    /// not hold it): the reader shows "Reading the scan…" while it runs.
    static func needsRecognition(url: URL, cache: URL?) -> Bool {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { return false }
        let texts = (0..<doc.pageCount).map { doc.page(at: $0)?.string ?? "" }
        let wanted = pagesToRecognise(texts)
        guard !wanted.isEmpty else { return false }
        let cached = cache.flatMap { loadScanCache($0, signature: AudiobookPaths.signature(forFileAt: url)) } ?? [:]
        return wanted.contains { cached[$0] == nil }
    }

    /// Every page's layout when at least one page needs recognition (text-layer pages from
    /// `layout(of:)`, the others recognised or from the cache); nil when none does.
    static func scannedLayouts(url: URL, pages: [PDFPage], texts: [String], cache: URL?) -> [PDFReflow.PageLayout]? {
        let wanted = Set(pagesToRecognise(texts))
        guard !wanted.isEmpty else { return nil }
        let signature = AudiobookPaths.signature(forFileAt: url)
        var cached = cache.flatMap { loadScanCache($0, signature: signature) } ?? [:]
        var fresh = false
        let layouts = pages.enumerated().map { i, page -> PDFReflow.PageLayout in
            guard wanted.contains(i) else { return layout(of: page) }
            if let hit = cached[i] { return hit }
            let read = recognisedLayout(of: page)
            cached[i] = read
            fresh = true
            return read
        }
        if fresh, let cache { saveScanCache(cached, signature: signature, to: cache) }
        return layouts
    }

    // MARK: - Recognition

    /// One page read by Vision: each recognised line with its word boxes, in the same space as
    /// `layout(of:)` (PDF points, x from the left edge, y from the bottom edge).
    static func recognisedLayout(of page: PDFPage) -> PDFReflow.PageLayout {
        let box = page.bounds(for: .mediaBox)
        let width = Double(box.width), height = Double(box.height)
        let empty = PDFReflow.PageLayout(width: width, height: height, lines: [])
        guard let image = pageImage(page) else { return empty }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let languages = recognitionLanguages.filter { supported.contains($0) }
        if !languages.isEmpty { request.recognitionLanguages = languages }
        do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) } catch { return empty }
        let lines = (request.results ?? []).compactMap { line(from: $0, width: width, height: height) }
        return PDFReflow.PageLayout(width: width, height: height, lines: evenedHeights(lines))
    }

    /// A recognised line's box hugs its glyphs, so a line without descenders is shorter than its
    /// neighbour in the same type, and `PDFReflow` would read that as a font change (a paragraph
    /// break). Lines within `sameTypeShare` of the page's median height get the median height
    /// around their own centre; a heading's larger type stays larger.
    static let sameTypeShare = 0.2

    static func evenedHeights(_ lines: [PDFReflow.Line]) -> [PDFReflow.Line] {
        let heights = lines.map { $0.maxY - $0.minY }.sorted()
        guard !heights.isEmpty else { return lines }
        let median = heights[heights.count / 2]
        guard median > 0 else { return lines }
        return lines.map { line in
            let h = line.maxY - line.minY, centre = (line.minY + line.maxY) / 2
            guard abs(h - median) <= median * sameTypeShare else { return line }
            var out = line
            out.minY = centre - median / 2
            out.maxY = centre + median / 2
            return out
        }
    }

    /// The page drawn into a white bitmap, PDF y-up (Vision's normalised boxes are y-up too).
    static func pageImage(_ page: PDFPage) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let scale = recognitionLongSide / max(box.width, box.height)
        let w = Int((box.width * scale).rounded()), h = Int((box.height * scale).rounded())
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    /// A recognised line as a `PDFReflow.Line`. Each word's box is Vision's box for its range;
    /// where Vision answers with the whole line for a word (it can), the words share the line's
    /// width by character count instead.
    static func line(from observation: VNRecognizedTextObservation, width: Double, height: Double) -> PDFReflow.Line? {
        guard let candidate = observation.topCandidates(1).first else { return nil }
        let text = candidate.string
        let lineBox = observation.boundingBox
        let ranges = wordRanges(text)
        guard !ranges.isEmpty else { return nil }
        var boxes: [CGRect?] = ranges.map { (try? candidate.boundingBox(for: $0))?.boundingBox }
        let lineWide = { (b: CGRect?) in (b?.width ?? 0) >= lineBox.width * 0.95 }
        if boxes.contains(where: { $0 == nil }) || (ranges.count > 1 && boxes.contains(where: lineWide)) {
            let total = Double(max(text.count, 1))
            boxes = ranges.map { r in
                let a = Double(text.distance(from: text.startIndex, to: r.lowerBound)) / total
                let b = Double(text.distance(from: text.startIndex, to: r.upperBound)) / total
                return CGRect(x: lineBox.minX + lineBox.width * a, y: lineBox.minY,
                              width: lineBox.width * (b - a), height: lineBox.height)
            }
        }
        let words = zip(ranges, boxes).map { r, b in
            PDFReflow.Word(text: String(text[r]), minX: Double(b!.minX) * width, maxX: Double(b!.maxX) * width)
        }
        return PDFReflow.Line(words: words, minY: Double(lineBox.minY) * height, maxY: Double(lineBox.maxY) * height)
    }

    /// The whitespace-separated words of `text`, as ranges.
    static func wordRanges(_ text: String) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        var start: String.Index?
        for i in text.indices {
            if text[i].isWhitespace {
                if let s = start { out.append(s..<i); start = nil }
            } else if start == nil {
                start = i
            }
        }
        if let s = start { out.append(s..<text.endIndex) }
        return out
    }

    // MARK: - Cache (`pdf_scan.json`)

    struct ScanCache: Codable {
        struct Word: Codable { var text: String; var minX: Double; var maxX: Double }
        struct Line: Codable { var words: [Word]; var minY: Double; var maxY: Double }
        struct Page: Codable { var index: Int; var width: Double; var height: Double; var lines: [Line] }
        static let currentVersion = 1
        var version: Int
        /// `AudiobookPaths.signature` of the PDF the pages were read from.
        var signature: String
        var pages: [Page]
    }

    /// The cached recognised pages by 0-based index; nil when there is no cache for this file.
    static func loadScanCache(_ url: URL, signature: String) -> [Int: PDFReflow.PageLayout]? {
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(ScanCache.self, from: data),
              cache.version == ScanCache.currentVersion, cache.signature == signature else { return nil }
        var out: [Int: PDFReflow.PageLayout] = [:]
        for p in cache.pages {
            out[p.index] = PDFReflow.PageLayout(width: p.width, height: p.height, lines: p.lines.map { l in
                PDFReflow.Line(words: l.words.map { PDFReflow.Word(text: $0.text, minX: $0.minX, maxX: $0.maxX) },
                               minY: l.minY, maxY: l.maxY)
            })
        }
        return out
    }

    static func saveScanCache(_ pages: [Int: PDFReflow.PageLayout], signature: String, to url: URL) {
        let cache = ScanCache(version: ScanCache.currentVersion, signature: signature, pages: pages.keys.sorted().map { i in
            let p = pages[i]!
            return ScanCache.Page(index: i, width: p.width, height: p.height, lines: p.lines.map { l in
                ScanCache.Line(words: l.words.map { ScanCache.Word(text: $0.text, minX: $0.minX, maxX: $0.maxX) },
                               minY: l.minY, maxY: l.maxY)
            })
        })
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
