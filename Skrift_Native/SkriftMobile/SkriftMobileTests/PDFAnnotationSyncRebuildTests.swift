import PDFKit
import UIKit
import XCTest
@testable import SkriftMobile

/// Q473 (D212, D214): the annotated Library PDF is the same on every device. The book-file sync
/// uploads the file once, so the annotated file never travels: each device rebuilds its own
/// Library PDF from the hidden untouched original plus the synced `Audiobook.highlights`, when the
/// list changes by sync and on first download. Two devices = two library stores sharing one
/// in-memory repository (the carrier) and one in-memory transport (the file cloud).
@MainActor
final class PDFAnnotationSyncRebuildTests: XCTestCase {

    private let line = "Sensor integration and field tests: €18,000"
    private let comment = "Ask Rui if the second test site is still Sines."

    private var dir: URL!
    private var libA: AudiobookLibraryStore!, libB: AudiobookLibraryStore!
    private var repo: NotesRepository!
    private var transport: InMemoryAudiobookTransport!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("q473_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        libA = AudiobookLibraryStore(directory: dir.appendingPathComponent("A", isDirectory: true))
        libB = AudiobookLibraryStore(directory: dir.appendingPathComponent("B", isDirectory: true))
        repo = NotesRepository(inMemory: true)
        transport = InMemoryAudiobookTransport()
        suiteName = "q473_\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// A generated three-page PDF with the budget line on page 2 (never one of his files).
    private func samplePDF() throws -> URL {
        let url = dir.appendingPathComponent("sample.pdf")
        let font = UIFont.systemFont(ofSize: 13)
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { ctx in
            for p in 1...3 {
                ctx.beginPage()
                ("Page \(p) heading" as NSString).draw(at: CGPoint(x: 56, y: 60), withAttributes: [.font: font])
                if p == 2 {
                    ((line + " covers two test sites") as NSString).draw(at: CGPoint(x: 56, y: 120), withAttributes: [.font: font])
                    ("Travel: €3,200" as NSString).draw(at: CGPoint(x: 56, y: 160), withAttributes: [.font: font])
                }
            }
        }
        try data.write(to: url)
        return url
    }

    private func reconcile(_ library: AudiobookLibraryStore) async {
        await AudiobookCloudSync.reconcile(library: library, repository: repo, defaults: defaults, transport: transport)
    }

    private func file(_ id: UUID, in library: AudiobookLibraryStore) throws -> URL {
        library.audioURL(of: try XCTUnwrap(library.book(id: id)), fileIndex: 0)
    }

    private func highlights(onPage2 url: URL) throws -> [PDFAnnotation] {
        let page = try XCTUnwrap(PDFDocument(url: url)?.page(at: 1), "the Library PDF still opens")
        return page.annotations.filter { $0.type == "Highlight" }
    }

    /// The item's check: a highlight list arriving by sync rewrites the receiver's Library file so
    /// PDFKit reads back the annotation and its comment; the hidden original stays byte-identical;
    /// an unchanged list writes nothing.
    func testHighlightsArrivingBySyncRewriteTheLocalPDF() async throws {
        let sample = try samplePDF()
        let original = try Data(contentsOf: sample)
        let book = try XCTUnwrap(LibraryPDF.importPDF(from: sample, displayName: "GFR grant.pdf", store: libA))
        AudiobookCloudSync.enableSync(book: book, repository: repo)
        await reconcile(libA)                       // device A uploads the file
        await reconcile(libB)                       // device B downloads it, nothing to draw yet
        let fileB = try file(book.id, in: libB)
        XCTAssertEqual(try Data(contentsOf: fileB), original, "B starts with the clean original")
        XCTAssertTrue(try highlights(onPage2: fileB).isEmpty)

        // A highlights and comments, leaves the reader (A's own file), and syncs the list.
        let hid = try XCTUnwrap(LibraryHighlights.add(line, page: 2, word: 0, bookID: book.id, store: libA))
        LibraryHighlights.setComment(comment, audio: nil, on: hid, bookID: book.id, store: libA)
        _ = await LibraryHighlights.writeIntoPDF(bookID: book.id, store: libA)
        await reconcile(libA)

        await reconcile(libB)                       // the list arrives on B
        XCTAssertEqual(libB.book(id: book.id)?.highlights?.count, 1)
        let found = try highlights(onPage2: fileB)
        XCTAssertEqual(found.count, 1, "one highlight, drawn once")
        XCTAssertEqual(found.first?.contents, comment, "B's Library PDF carries the comment PDFKit reads back")
        let backup = PDFAnnotationExport.backupURL(for: fileB)
        XCTAssertEqual(try Data(contentsOf: backup), original, "the hidden original stays byte-identical")
        XCTAssertEqual(PDFAnnotationExport.pristine(fileB), backup)

        // Nothing changed: another sync pass, and a direct rebuild, write nothing.
        let bytes = try Data(contentsOf: fileB)
        let mtime = try FileManager.default.attributesOfItem(atPath: fileB.path)[.modificationDate] as? Date
        await reconcile(libB)
        let rebuilt = await LibraryHighlights.rebuildPDFFromSync(bookID: book.id, store: libB, fileIsFresh: false)
        XCTAssertFalse(rebuilt, "an unchanged list writes nothing")
        XCTAssertEqual(try Data(contentsOf: fileB), bytes)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: fileB.path)[.modificationDate] as? Date, mtime)
        XCTAssertEqual(try Data(contentsOf: backup), original)

        // The highlight is removed on A: B's file goes back to clean pages.
        LibraryHighlights.remove(hid, bookID: book.id, store: libA)
        await reconcile(libA)
        await reconcile(libB)
        XCTAssertTrue(try highlights(onPage2: fileB).isEmpty, "a removal by sync clears B's file too")
        XCTAssertEqual(try Data(contentsOf: backup), original)
    }

    /// First download: a device that highlighted (and wrote its own file) before syncing uploads
    /// the clean original, and the receiver draws the list once, making its own hidden backup.
    func testFirstDownloadDrawsTheSyncedListOnceAndKeepsTheOriginal() async throws {
        let sample = try samplePDF()
        let original = try Data(contentsOf: sample)
        let book = try XCTUnwrap(LibraryPDF.importPDF(from: sample, displayName: "GFR grant.pdf", store: libA))
        let hid = try XCTUnwrap(LibraryHighlights.add(line, page: 2, word: 0, bookID: book.id, store: libA))
        LibraryHighlights.setComment(comment, audio: nil, on: hid, bookID: book.id, store: libA)
        let wroteA = await LibraryHighlights.writeIntoPDF(bookID: book.id, store: libA)
        XCTAssertTrue(wroteA, "A's own Library file is annotated before it ever syncs")

        AudiobookCloudSync.enableSync(book: try XCTUnwrap(libA.book(id: book.id)), repository: repo)
        await reconcile(libA)
        await reconcile(libB)

        let fileB = try file(book.id, in: libB)
        let found = try highlights(onPage2: fileB)
        XCTAssertEqual(found.count, 1, "drawn once, never doubled by an annotated upload")
        XCTAssertEqual(found.first?.contents, comment)
        XCTAssertEqual(try Data(contentsOf: PDFAnnotationExport.backupURL(for: fileB)), original,
                       "B's hidden backup is the untouched original")
    }
}
