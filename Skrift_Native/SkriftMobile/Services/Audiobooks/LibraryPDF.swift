import Combine
import Foundation
import PDFKit
import UIKit

/// Q354 (Q6 mock "Share a PDF from Mail" / "PDF reader", D126 / D135 / D138): a PDF as a Library
/// source. It is an `Audiobook` record with `kind == .pdf`, so the shelf, the sync carrier and the
/// ❝ N note join all keep working with no schema change. For a PDF the audio fields count PAGES:
/// `duration` = page count, `position` = the page he is on (0 = never opened, which reads as page 1),
/// `files` = the one PDF inside the book's folder. The tile's progress bar is `position / duration`
/// for free.
enum LibraryPDF {

    // MARK: - Toast copy (D126)

    static let toastText = "Added to Library"
    static let toastAction = "Add to a note instead"
    /// The whole line, for VoiceOver and the log: "Added to Library · add to a note instead".
    static var toastLine: String { "\(toastText) · add to a note instead" }

    /// The file inside the book's folder.
    static let fileName = "document.pdf"

    // MARK: - Share routing

    /// True when a PDF shared with this display name / thought / rating belongs in the Library.
    static func routesToLibrary(displayName: String?, thought: String?, significance: Double) -> Bool {
        CaptureInboxEntry.routesPDFToLibrary(displayName: displayName, thought: thought, significance: significance)
    }

    // MARK: - Import

    /// Copy `url` into a new Library source. nil when the file is not a readable PDF (the caller
    /// keeps it as a note attachment instead; a share is never lost). `id` lets the drain reuse the
    /// inbox entry id, so a re-drain after a crash finds the book and does not add it twice.
    @MainActor
    static func importPDF(from url: URL, displayName: String?, store: AudiobookLibraryStore,
                          id: UUID = UUID(), now: Date = Date()) -> Audiobook? {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { return nil }
        let folder = store.folder(for: id)
        let dest = folder.appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
        // Page 1 as the tile's cover (the mock draws a paper swatch; the real first page is better).
        var hasCover = false
        if let page = doc.page(at: 0) {
            let bounds = page.bounds(for: .cropBox)
            let width: CGFloat = 512
            let size = CGSize(width: width, height: max(1, bounds.height * width / max(1, bounds.width)))
            if let jpeg = page.thumbnail(of: size, for: .cropBox).jpegData(compressionQuality: 0.8) {
                hasCover = (try? jpeg.write(to: folder.appendingPathComponent("cover.jpg"))) != nil
            }
        }
        let pages = Double(doc.pageCount)
        var book = Audiobook(
            id: id, files: [fileName], fileDurations: [pages],
            title: title(forDisplayName: displayName, fallback: url), author: "",
            duration: pages, hasCover: hasCover, importedAt: now, position: 0, modifiedAt: now)
        book.kind = .pdf
        store.add(book)
        return book
    }

    /// "Sensor budget, revised.pdf" -> "Sensor budget, revised".
    static func title(forDisplayName name: String?, fallback url: URL) -> String {
        let raw = (name?.isEmpty == false ? name! : url.lastPathComponent) as NSString
        let stem = (raw.lastPathComponent as NSString).deletingPathExtension.trimmingCharacters(in: .whitespaces)
        return stem.isEmpty ? "PDF" : stem
    }

    // MARK: - Pages

    static func pageCount(of book: Audiobook) -> Int { max(0, Int(book.duration)) }

    /// The page he is on, 1-based (an unopened PDF is on page 1).
    static func page(of book: Audiobook) -> Int {
        let count = max(1, pageCount(of: book))
        return min(max(1, Int(book.position)), count)
    }

    /// Persist the page (clamped to the document) and count it as use, for the recents sort.
    @MainActor
    static func savePage(_ page: Int, bookID: UUID, store: AudiobookLibraryStore) {
        guard let book = store.book(id: bookID) else { return }
        let count = max(1, pageCount(of: book))
        store.updateProgress(id: bookID, position: Double(min(max(1, page), count)))
    }

    /// "p. 4 of 18" (the mock's tile line and reader dock).
    static func progressLine(_ book: Audiobook) -> String {
        "p. \(page(of: book)) of \(pageCount(of: book))"
    }

    /// "14 pages left".
    static func leftLine(_ book: Audiobook) -> String { "\(leftPhrase(book)) left" }

    /// "14 pages" (the VoiceOver label adds " left" itself).
    static func leftPhrase(_ book: Audiobook) -> String {
        let left = max(0, pageCount(of: book) - Int(book.position))
        return "\(left) page\(left == 1 ? "" : "s")"
    }

    /// "p. 4" — rides `MemoMetadata.bookChapter`, which the export prints as it is when it is not
    /// a bare number (`CaptureQuote.chapterLabel`), giving `— *Title*, p. 4` (D138).
    static func pageLabel(_ page: Int) -> String { "p. \(page)" }

    /// True for a `bookChapter` written by `pageLabel` ("p. 4"): the note came from a PDF.
    static func isPageLabel(_ chapter: String?) -> Bool {
        guard let c = chapter, c.hasPrefix("p. ") else { return false }
        let n = c.dropFirst(3)
        return !n.isEmpty && n.allSatisfy(\.isNumber)
    }

    // MARK: - Capture (quote + his voice)

    /// The note a PDF capture starts as: the selected text as the quote block, the source and the
    /// page in the metadata. His voice is then appended by the normal recorder (`appendTo:`), the
    /// same way an audiobook quote's ramble is. nil for an empty selection.
    @MainActor
    @discardableResult
    static func saveCapture(quote: String, book: Audiobook, page: Int, significance: Double,
                            repository: NotesRepository = .shared, now: Date = Date()) -> UUID? {
        let transcript = QuoteFormatting.blockquote(quote)
        guard !transcript.isEmpty else { return nil }
        let id = UUID()
        let author = book.author.trimmingCharacters(in: .whitespaces)
        repository.insert(Memo.make(
            id: id,
            audioFilename: "",
            recordedAt: now,
            syncStatus: .waiting,
            transcript: transcript,
            transcriptStatus: .done,
            transcriptUserEdited: true,   // deliberate quote: the Mac must not re-transcribe
            significance: significance,
            metadata: MemoMetadata(
                bookTitle: book.title,
                bookAuthor: author.isEmpty ? nil : author,
                bookChapter: pageLabel(page),
                bookID: book.id,
                bookPosition: Double(page))))
        return id
    }

    // MARK: - "Add to a note instead" (D126)

    /// Turn the Library source back into a note with the PDF attached, exactly what the share
    /// made before this change. The source leaves Library. nil when the file is missing.
    @MainActor
    @discardableResult
    static func moveToNote(book: Audiobook, store: AudiobookLibraryStore,
                           repository: NotesRepository = .shared, now: Date = Date()) -> UUID? {
        let src = store.audioURL(of: book, fileIndex: 0)
        guard FileManager.default.fileExists(atPath: src.path) else { return nil }
        let memoID = UUID()
        let destName = "file_\(memoID.uuidString).pdf"
        let dest = AppPaths.recordingsDirectory.appendingPathComponent(destName)
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: src, to: dest)
        } catch {
            return nil
        }
        var shared = SharedContent(type: .file, filePath: destName,
                                   fileName: book.title + ".pdf", mimeType: "application/pdf")
        shared.text = PDFTextExtract.text(of: dest)   // searchable, like a drained share
        repository.insert(Memo.make(
            id: memoID, recordedAt: now, syncStatus: .waiting,
            transcriptStatus: .done, sharedContent: shared))
        store.remove(book)
        return memoID
    }
}

/// Q354: the "a PDF just arrived" signal from the share drain to the Library tab, which shows the
/// toast. One pending arrival; `clear()` when the toast goes.
@MainActor
final class LibraryPDFArrival: ObservableObject {
    static let shared = LibraryPDFArrival()
    struct Arrival: Equatable, Identifiable {
        let bookID: UUID
        var id: UUID { bookID }
    }
    @Published private(set) var pending: Arrival?
    func post(bookID: UUID) { pending = Arrival(bookID: bookID) }
    func clear() { pending = nil }
}
