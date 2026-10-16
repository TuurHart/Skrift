import Foundation
import PDFKit
import UIKit

/// Q463 (D212, D214): the PDF he shares. "With my highlights and comments" writes a FRESH copy of
/// the Library PDF with each highlight as a real PDF highlight annotation (the comment is the
/// annotation's contents, the PDF `/Contents` field other apps read) and a sticky-note pin in the
/// right margin beside a commented highlight (the Q462 mock's page view). "Clean" copies the file
/// as imported. The Library file itself is only ever read (D214, C273 spirit).
enum PDFAnnotationExport {
    enum Variant: Equatable { case annotated, clean }

    enum ExportError: Error { case unreadable, writeFailed }

    static let highlightColor = UIColor(red: 1, green: 0.8, blue: 0, alpha: 0.42)
    static let pinColor = UIColor(red: 1, green: 0.82, blue: 0.25, alpha: 1)
    static let pinSize: CGFloat = 18

    /// The shared file's name: the Library title, plus "(highlights)" for the annotated copy.
    static func fileName(title: String, variant: Variant) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty ? "Document" : cleaned
        return variant == .annotated ? "\(base) (highlights).pdf" : "\(base).pdf"
    }

    /// Writes the copy into `directory` (a fresh folder per share) and returns its URL.
    static func write(source: URL, highlights: [SourceHighlight], variant: Variant, title: String,
                      into directory: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let out = directory.appendingPathComponent(fileName(title: title, variant: variant))
        try? fm.removeItem(at: out)
        switch variant {
        case .clean:
            try fm.copyItem(at: source, to: out)
        case .annotated:
            guard let doc = PDFDocument(url: source) else { throw ExportError.unreadable }
            annotate(doc, with: highlights)
            guard doc.write(to: out) else { throw ExportError.writeFailed }
        }
        return out
    }

    /// A fresh folder in tmp for one share (the share sheet reads the file after we return).
    static func shareDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pdf-share-\(UUID().uuidString)", isDirectory: true)
    }

    /// Adds one highlight annotation per line of each stored highlight; the first line carries the
    /// comment (so a comment list shows it once). A commented highlight also gets a margin pin.
    static func annotate(_ doc: PDFDocument, with highlights: [SourceHighlight]) {
        for h in highlights {
            guard let number = h.page, let page = doc.page(at: number - 1),
                  let match = doc.findString(h.text, withOptions: [.caseInsensitive]).first(where: { $0.pages.first == page })
            else { continue }
            let lines = match.selectionsByLine()
            guard let first = lines.first else { continue }
            let comment = h.commentText
            for (i, line) in lines.enumerated() {
                let a = PDFAnnotation(bounds: line.bounds(for: page), forType: .highlight, withProperties: nil)
                a.color = highlightColor
                if i == 0, let comment { a.contents = comment }
                if i == 0 { a.modificationDate = h.commentedAt ?? h.createdAt }
                page.addAnnotation(a)
            }
            if let comment {
                let pin = PDFAnnotation(bounds: pinRect(beside: first.bounds(for: page), on: page),
                                        forType: .text, withProperties: nil)
                pin.iconType = .comment
                pin.color = pinColor
                pin.contents = comment
                page.addAnnotation(pin)
            }
        }
    }

    /// The pin's square in the right margin, level with the highlight's first line.
    static func pinRect(beside line: CGRect, on page: PDFPage) -> CGRect {
        let box = page.bounds(for: .cropBox)
        let x = box.maxX - pinSize - 10
        let y = min(max(box.minY + 4, line.midY - pinSize / 2), box.maxY - pinSize - 4)
        return CGRect(x: x, y: y, width: pinSize, height: pinSize)
    }

    /// "3 highlights, 2 comments" (the share sheet's line under the file name).
    static func summary(_ highlights: [SourceHighlight]) -> String {
        let n = highlights.count, c = highlights.filter { $0.commentText != nil }.count
        let hl = n == 1 ? "1 highlight" : "\(n) highlights"
        let cm = c == 1 ? "1 comment" : "\(c) comments"
        return "\(hl), \(cm)"
    }
}
