import Foundation
import PDFKit

/// Embedded-text extraction for shared PDFs — SHARED phone↔Mac. The phone runs
/// this on capture-drain (A6) so a shared PDF is searchable like a doc-scan (which
/// OCRs via the photo pipeline); the extracted text rides `sharedContent.text` in
/// the synced metadata. A scanned (image-only) PDF yields nil and stays findable
/// by filename. Capped so a book-length PDF doesn't bloat the synced record.
///
/// PDFKit is available on both iOS and macOS, so the Mac can apply the SAME
/// extraction once the document blob syncs (`MemoAsset.Kind.document`, follow-up
/// 3b) — today the Mac has only the phone-extracted text, never the file.
enum PDFTextExtract {
    /// Max characters kept (a book-length PDF would otherwise bloat the record).
    static let characterCap = 120_000

    /// Trim, drop-if-empty, and cap raw extracted text — the pure, host-testable
    /// core (no file needed). nil for missing/blank text.
    static func normalize(_ raw: String?) -> String? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return String(s.prefix(characterCap))
    }

    /// The trimmed, capped embedded text of a PDF, or nil if unreadable /
    /// image-only / empty. Synchronous + pure — call it off the main thread.
    static func text(of url: URL) -> String? {
        normalize(PDFDocument(url: url)?.string)
    }
}
