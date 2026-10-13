import PDFKit
import UIKit
import XCTest
@testable import SkriftMobile

/// Q354 (Q6 mock "Share a PDF from Mail" / "PDF reader", D126 / D135 / D138): a PDF shared from
/// another app becomes a Library source (kind `pdf`) with the toast "Added to Library · add to a
/// note instead"; the reader keeps the page; a capture carries source + page and exports
/// `— *Title*, p. N`.
final class LibraryPDFTests: XCTestCase {

    // MARK: - Fixtures

    @MainActor
    private func makeStore() -> AudiobookLibraryStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("audiobooks_\(UUID().uuidString)", isDirectory: true)
        return AudiobookLibraryStore(directory: dir)
    }

    /// A real PDF with `pages` pages, each carrying text (embedded, not rasterised).
    private func makePDF(pages: Int, named name: String = "Sensor budget, revised.pdf") throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pdfsrc_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        let data = renderer.pdfData { ctx in
            for p in 1...pages {
                ctx.beginPage()
                ("Page \(p) flamingo budget" as NSString)
                    .draw(at: CGPoint(x: 72, y: 72), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
            }
        }
        try data.write(to: url)
        return url
    }

    @MainActor
    private func cleanInbox() throws {
        guard let inbox = CaptureInbox.inboxURL else { throw XCTSkip("no App Group container in this test host") }
        try? FileManager.default.removeItem(at: inbox)
    }

    // MARK: - Share routing

    func testSharedPdfWithNoThoughtAndNoRatingGoesToTheLibrary() {
        XCTAssertTrue(LibraryPDF.routesToLibrary(displayName: "Sensor budget, revised.pdf", thought: nil, significance: 0))
        XCTAssertTrue(LibraryPDF.routesToLibrary(displayName: "SCAN.PDF", thought: "  \n", significance: 0),
                      "extension case and blank thought do not matter")
    }

    func testATypedThoughtOrARatingMakesItANoteWithTheFileAttached() {
        XCTAssertFalse(LibraryPDF.routesToLibrary(displayName: "a.pdf", thought: "Look at table 2", significance: 0),
                       "his words in the share sheet = a note (D126: the + / sheet thought attaches it)")
        XCTAssertFalse(LibraryPDF.routesToLibrary(displayName: "a.pdf", thought: nil, significance: 0.3),
                       "a rated share is a note")
    }

    func testOtherFilesNeverGoToTheLibrary() {
        XCTAssertFalse(LibraryPDF.routesToLibrary(displayName: "notes.md", thought: nil, significance: 0))
        XCTAssertFalse(LibraryPDF.routesToLibrary(displayName: "photo.png", thought: nil, significance: 0))
        XCTAssertFalse(LibraryPDF.routesToLibrary(displayName: nil, thought: nil, significance: 0))
    }

    func testTheEntryFlagIsOptionalSoOlderEntriesStillDecode() throws {
        let id = UUID()
        var entry = CaptureInboxEntry(
            id: id, type: "file", url: nil, urlTitle: nil, text: nil, imageFileName: nil,
            mimeType: "application/pdf", annotationText: nil, significance: 0,
            sharedAt: ISO8601.string(from: Date()))
        XCTAssertNil(entry.routeToLibrary)
        entry.routeToLibrary = true
        let back = try JSONDecoder().decode(CaptureInboxEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(back.routeToLibrary, true)
        let plain = try JSONEncoder().encode(CaptureInboxEntry(
            id: id, type: "file", url: nil, urlTitle: nil, text: nil, imageFileName: nil,
            mimeType: nil, annotationText: nil, significance: 0, sharedAt: "x"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: plain) as? [String: Any])
        json.removeValue(forKey: "routeToLibrary")
        let old = try JSONSerialization.data(withJSONObject: json)
        XCTAssertNil(try JSONDecoder().decode(CaptureInboxEntry.self, from: old).routeToLibrary)
    }

    func testToastCopy() {
        XCTAssertEqual(LibraryPDF.toastLine, "Added to Library · add to a note instead")
        XCTAssertEqual(LibraryPDF.toastText, "Added to Library")
        XCTAssertEqual(LibraryPDF.toastAction, "Add to a note instead")
    }

    @MainActor
    func testTheDrainTurnsARoutedPdfIntoALibrarySourceNotANote() async throws {
        try cleanInbox()
        let repo = NotesRepository(inMemory: true)
        let store = makeStore()
        let saved = CaptureInboxDrainer.libraryStore
        CaptureInboxDrainer.libraryStore = store
        defer { CaptureInboxDrainer.libraryStore = saved }
        LibraryPDFArrival.shared.clear()

        let pdf = try makePDF(pages: 6)
        let id = UUID()
        let entry = CaptureInboxEntry(
            id: id, type: "file", url: nil, urlTitle: nil, text: nil, imageFileName: nil,
            mimeType: "application/pdf", annotationText: nil, significance: 0,
            sharedAt: ISO8601.string(from: Date()),
            fileName: "file_\(id.uuidString).pdf", fileDisplayName: "Sensor budget, revised.pdf",
            routeToLibrary: true)
        XCTAssertTrue(CaptureInbox.write(entry, fileSourceURL: pdf))

        await CaptureInboxDrainer.drain(into: repo)

        XCTAssertTrue(CaptureInbox.pendingEntries().isEmpty, "entry consumed")
        XCTAssertNil(repo.memo(id: id), "no note was made")
        XCTAssertEqual(store.books.count, 1)
        let book = try XCTUnwrap(store.books.first)
        XCTAssertEqual(book.sourceKind, .pdf)
        XCTAssertEqual(book.title, "Sensor budget, revised")
        XCTAssertEqual(LibraryPDFArrival.shared.pending?.bookID, book.id, "the toast has something to show")
    }

    @MainActor
    func testAnUnroutedPdfStaysANoteWithTheFileAttachedAsToday() async throws {
        try cleanInbox()
        let repo = NotesRepository(inMemory: true)
        let store = makeStore()
        let saved = CaptureInboxDrainer.libraryStore
        CaptureInboxDrainer.libraryStore = store
        defer { CaptureInboxDrainer.libraryStore = saved }

        let pdf = try makePDF(pages: 2)
        let id = UUID()
        let entry = CaptureInboxEntry(
            id: id, type: "file", url: nil, urlTitle: nil, text: nil, imageFileName: nil,
            mimeType: "application/pdf", annotationText: "my thought", significance: 0,
            sharedAt: ISO8601.string(from: Date()),
            fileName: "file_\(id.uuidString).pdf", fileDisplayName: "a.pdf")
        XCTAssertTrue(CaptureInbox.write(entry, fileSourceURL: pdf))

        await CaptureInboxDrainer.drain(into: repo)

        let memo = try XCTUnwrap(repo.memo(id: id))
        XCTAssertEqual(memo.sharedContent?.type, .file)
        XCTAssertTrue(store.books.isEmpty)
        if let f = memo.sharedFileURL { try? FileManager.default.removeItem(at: f) }
    }

    // MARK: - Import

    @MainActor
    func testImportMakesAPdfSourceWithPagesAndACover() throws {
        let store = makeStore()
        let pdf = try makePDF(pages: 6)
        let book = try XCTUnwrap(LibraryPDF.importPDF(from: pdf, displayName: "Sensor budget, revised.pdf", store: store))
        XCTAssertEqual(book.kind, .pdf)
        XCTAssertEqual(book.title, "Sensor budget, revised")
        XCTAssertEqual(LibraryPDF.pageCount(of: book), 6)
        XCTAssertEqual(LibraryPDF.page(of: book), 1, "an unread PDF opens on page 1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.audioURL(of: book, fileIndex: 0).path),
                      "the file is copied into the book folder")
        XCTAssertTrue(book.hasCover)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(store.coverURL(of: book)).path))
        XCTAssertEqual(store.books.map(\.id), [book.id])
    }

    @MainActor
    func testImportRefusesSomethingThatIsNotAPdf() throws {
        let store = makeStore()
        let junk = FileManager.default.temporaryDirectory.appendingPathComponent("junk_\(UUID().uuidString).pdf")
        try Data("not a pdf".utf8).write(to: junk)
        XCTAssertNil(LibraryPDF.importPDF(from: junk, displayName: "junk.pdf", store: store))
        XCTAssertTrue(store.books.isEmpty)
    }

    // MARK: - The page is kept

    @MainActor
    func testThePageSurvivesARelaunch() throws {
        let store = makeStore()
        let book = try XCTUnwrap(LibraryPDF.importPDF(from: try makePDF(pages: 18), displayName: "Grant.pdf", store: store))
        LibraryPDF.savePage(4, bookID: book.id, store: store)

        let relaunched = AudiobookLibraryStore(directory: store.directory)
        let back = try XCTUnwrap(relaunched.book(id: book.id))
        XCTAssertEqual(LibraryPDF.page(of: back), 4)
        XCTAssertEqual(back.progress, 4.0 / 18.0, accuracy: 0.001, "the tile's bar reads pages")
        XCTAssertNotNil(back.lastPlayedAt, "opening a PDF counts as use, for the recents sort")
        XCTAssertEqual(LibraryPDF.progressLine(back), "p. 4 of 18")
        XCTAssertEqual(LibraryPDF.leftLine(back), "14 pages left")
    }

    @MainActor
    func testAShortPdfIsNotFinishedUntilItsLastPage() throws {
        let store = makeStore()
        let book = try XCTUnwrap(LibraryPDF.importPDF(from: try makePDF(pages: 6), displayName: "T.pdf", store: store))
        XCTAssertFalse(book.isFinished, "page 1 of 6 must not read as finished (the audio tail is seconds)")
        LibraryPDF.savePage(5, bookID: book.id, store: store)
        XCTAssertFalse(try XCTUnwrap(store.book(id: book.id)).isFinished)
        LibraryPDF.savePage(6, bookID: book.id, store: store)
        XCTAssertTrue(try XCTUnwrap(store.book(id: book.id)).isFinished)
    }

    @MainActor
    func testAPageOutsideTheDocumentIsClamped() throws {
        let store = makeStore()
        let book = try XCTUnwrap(LibraryPDF.importPDF(from: try makePDF(pages: 3), displayName: "T.pdf", store: store))
        LibraryPDF.savePage(99, bookID: book.id, store: store)
        XCTAssertEqual(LibraryPDF.page(of: try XCTUnwrap(store.book(id: book.id))), 3)
        LibraryPDF.savePage(-2, bookID: book.id, store: store)
        XCTAssertEqual(LibraryPDF.page(of: try XCTUnwrap(store.book(id: book.id))), 1)
    }

    // MARK: - Capture carries source + page

    @MainActor
    func testACaptureCarriesTheSourceAndThePage() throws {
        let store = makeStore()
        let repo = NotesRepository(inMemory: true)
        let book = try XCTUnwrap(LibraryPDF.importPDF(from: try makePDF(pages: 18), displayName: "GFR grant application, draft 3.pdf", store: store))

        let id = try XCTUnwrap(LibraryPDF.saveCapture(
            quote: "Sensor integration and field tests: €18,000", book: book, page: 4, significance: 0.4,
            repository: repo))
        let memo = try XCTUnwrap(repo.memo(id: id))

        XCTAssertEqual(memo.transcript, "> Sensor integration and field tests: €18,000")
        XCTAssertEqual(memo.metadata?.bookID, book.id)
        XCTAssertEqual(memo.metadata?.bookTitle, "GFR grant application, draft 3")
        XCTAssertEqual(memo.metadata?.bookChapter, "p. 4")
        XCTAssertEqual(memo.metadata?.bookPosition, 4)
        XCTAssertEqual(memo.significance, 0.4, accuracy: 0.001)
        XCTAssertTrue(memo.transcriptUserEdited, "the Mac must not re-transcribe a typed quote")

        // The join the Library tile's "❝ N" pill and the jump-back read.
        XCTAssertEqual(BookNotesJoin.counts(in: [memo])[book.id], 1)
        let target = try XCTUnwrap(BookNotesJoin.jumpTarget(for: memo))
        XCTAssertEqual(target, BookNotesJoin.JumpTarget(bookID: book.id, position: 4))
        XCTAssertEqual(BookNotesJoin.jumpLabel(page: 4), "Back to it at p. 4 in Library")
    }

    @MainActor
    func testAnEmptySelectionMakesNoNote() throws {
        let store = makeStore()
        let repo = NotesRepository(inMemory: true)
        let book = try XCTUnwrap(LibraryPDF.importPDF(from: try makePDF(pages: 2), displayName: "T.pdf", store: store))
        XCTAssertNil(LibraryPDF.saveCapture(quote: "  \n ", book: book, page: 1, significance: 0, repository: repo))
        XCTAssertTrue(repo.allMemos().isEmpty)
    }

    // MARK: - Export (D138)

    func testExportAttributionIsTitleAndPage() {
        let body = "> Sensor integration and field tests: €18,000\n\nMy thought."
        let out = Compiler.audiobookBody(body, book: "GFR grant application, draft 3", author: nil, chapter: "p. 4")
        XCTAssertTrue(out.contains("> — *GFR grant application, draft 3*, p. 4"), out)
        XCTAssertTrue(out.contains("> *Sensor integration and field tests: €18,000*"), out)
    }

    // MARK: - Add to a note instead (D126)

    @MainActor
    func testAddToANoteInsteadMovesThePdfOutOfTheLibraryAsAnAttachment() throws {
        let store = makeStore()
        let repo = NotesRepository(inMemory: true)
        let book = try XCTUnwrap(LibraryPDF.importPDF(from: try makePDF(pages: 6), displayName: "Sensor budget, revised.pdf", store: store))

        let id = try XCTUnwrap(LibraryPDF.moveToNote(book: book, store: store, repository: repo))

        XCTAssertNil(store.book(id: book.id), "it left Library")
        let memo = try XCTUnwrap(repo.memo(id: id))
        XCTAssertEqual(memo.sharedContent?.type, .file)
        XCTAssertEqual(memo.sharedContent?.fileName, "Sensor budget, revised.pdf")
        let file = try XCTUnwrap(memo.sharedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(memo.sharedContent?.text?.contains("flamingo") == true, "text extracted like a drained share")
        try? FileManager.default.removeItem(at: file)
    }

    // MARK: - The door

    func testTheEpubOrPdfDoorIsBuilt() {
        XCTAssertTrue(LibraryDoor.epubOrPDF.isBuilt)
        XCTAssertTrue(LibraryDoor.visible.contains(.epubOrPDF))
    }
}
