import Foundation
import PDFKit
import UIKit

/// Q463 (D212, D214 as corrected 2026-10-16): the Library PDF ITSELF carries his highlights and
/// comments as real PDF annotations (a highlight per line, the comment as its `/Contents`, the field
/// other apps read, plus a sticky-note pin in the right margin beside a commented highlight, the Q462
/// mock's page view), so he reads his alterations in any app. They are written when he leaves the
/// reader, only when they changed (a large file re-uploads less often), atomically (temp + replace),
/// always redrawn from the untouched original, which is kept once as a hidden backup beside the file
/// before the first write. Share asks every time: the annotated Library file, or that clean backup.
enum PDFAnnotationExport {
    enum Variant: Equatable { case annotated, clean }

    enum ExportError: Error { case unreadable, writeFailed }

    static let highlightColor = UIColor(red: 1, green: 0.8, blue: 0, alpha: 0.42)
    static let pinColor = UIColor(red: 1, green: 0.82, blue: 0.25, alpha: 1)
    static let pinSize: CGFloat = 18
    /// The author (`/T`) on every annotation Skrift writes into the file: the reader strips these
    /// when it opens the file and draws the live list instead, so they never show twice.
    static let persistedAuthor = "Skrift"

    /// The shared file's name: the Library title, plus "(highlights)" for the annotated copy.
    static func fileName(title: String, variant: Variant) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty ? "Document" : cleaned
        return variant == .annotated ? "\(base) (highlights).pdf" : "\(base).pdf"
    }

    // MARK: - The Library file

    /// The untouched original, hidden beside the Library file (made once, before the first write).
    static func backupURL(for file: URL) -> URL {
        file.deletingLastPathComponent().appendingPathComponent(".original-" + file.lastPathComponent)
    }

    /// What the last write drew, so leaving the reader with nothing changed writes nothing.
    static func stampURL(for file: URL) -> URL {
        file.deletingLastPathComponent().appendingPathComponent(".annotations-" + file.lastPathComponent + ".json")
    }

    /// The file as imported: the backup once there is one, else the Library file (never written yet).
    static func pristine(_ file: URL) -> URL {
        let backup = backupURL(for: file)
        return FileManager.default.fileExists(atPath: backup.path) ? backup : file
    }

    private struct Stamp: Codable, Equatable {
        let id: UUID; let text: String; let page: Int?; let comment: String?
    }

    private static func stamp(_ highlights: [SourceHighlight]) -> Data {
        let rows = highlights.map { Stamp(id: $0.id, text: $0.text, page: $0.page, comment: $0.commentText) }
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        return (try? enc.encode(rows)) ?? Data()
    }

    /// Writes the highlights into the Library PDF. Returns false when nothing changed since the last
    /// write (or there is nothing to write into a never-touched file). A failed write leaves the file
    /// as it was: the new PDF is written to a temp file beside it and only then swapped in.
    @discardableResult
    static func writeBack(file: URL, highlights: [SourceHighlight]) throws -> Bool {
        let fm = FileManager.default
        let backup = backupURL(for: file)
        let stampFile = stampURL(for: file)
        let next = stamp(highlights)
        if !fm.fileExists(atPath: backup.path) {
            guard !highlights.isEmpty else { return false }
            try fm.copyItem(at: file, to: backup)
        } else if (try? Data(contentsOf: stampFile)) == next {
            return false
        }
        guard let doc = PDFDocument(url: backup) else { throw ExportError.unreadable }
        annotate(doc, with: highlights) { _ in persistedAuthor }
        let temp = file.deletingLastPathComponent().appendingPathComponent(".writing-\(UUID().uuidString).pdf")
        guard doc.write(to: temp) else {
            try? fm.removeItem(at: temp)
            throw ExportError.writeFailed
        }
        do {
            _ = try fm.replaceItemAt(file, withItemAt: temp)
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
        try? next.write(to: stampFile, options: .atomic)
        return true
    }

    // MARK: - Share

    /// The copy handed to the share sheet, in `directory` (a fresh folder per share): the annotated
    /// Library file (brought up to date first), or the clean original.
    static func share(file: URL, highlights: [SourceHighlight], variant: Variant, title: String,
                      into directory: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let out = directory.appendingPathComponent(fileName(title: title, variant: variant))
        try? fm.removeItem(at: out)
        switch variant {
        case .clean:
            try fm.copyItem(at: pristine(file), to: out)
        case .annotated:
            try writeBack(file: file, highlights: highlights)
            try fm.copyItem(at: file, to: out)
        }
        return out
    }

    /// A fresh folder in tmp for one share (the share sheet reads the file after we return).
    static func shareDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pdf-share-\(UUID().uuidString)", isDirectory: true)
    }

    /// Adds one highlight annotation per line of each stored highlight; the first line carries the
    /// comment (so a comment list shows it once). A commented highlight also gets a margin pin.
    /// `tag` names each annotation (`userName`): the reader tags its in-memory drawing with the
    /// highlight's id so a tap finds it; the shared copy leaves them untagged. One drawing, so the
    /// page view shows what the shared file will.
    static func annotate(_ doc: PDFDocument, with highlights: [SourceHighlight],
                         tag: ((SourceHighlight) -> String)? = nil) {
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
                if let tag { a.userName = tag(h) }
                page.addAnnotation(a)
            }
            if let comment {
                let pin = PDFAnnotation(bounds: pinRect(beside: first.bounds(for: page), on: page),
                                        forType: .text, withProperties: nil)
                pin.iconType = .comment
                pin.color = pinColor
                pin.contents = comment
                if let tag { pin.userName = tag(h) }
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
