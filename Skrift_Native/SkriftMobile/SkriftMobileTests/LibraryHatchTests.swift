import UIKit
import XCTest
@testable import SkriftMobile

/// Q356 (Q6 mock "A capture note" / "A note with a PDF", D90 / D138): the two hatches between
/// Library and Notes, the PDF quote label + export, the share-sheet podcast route, the notes row
/// under the player and reader, the shelf's type chips and the drawn cover.
final class LibraryHatchTests: XCTestCase {

    // MARK: - Fixtures

    @MainActor
    private func makeStore() -> AudiobookLibraryStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("audiobooks_\(UUID().uuidString)", isDirectory: true)
        return AudiobookLibraryStore(directory: dir)
    }

    private func makePDF(pages: Int, named name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hatch_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        let data = renderer.pdfData { ctx in
            for p in 1...pages {
                ctx.beginPage()
                ("Lease page \(p)" as NSString)
                    .draw(at: CGPoint(x: 72, y: 72), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
            }
        }
        try data.write(to: url)
        return url
    }

    private func book(_ title: String, author: String = "Oliver Burkeman", kind: LibrarySourceKind? = nil,
                      duration: TimeInterval = 20_000, position: TimeInterval = 4325) -> Audiobook {
        var b = Audiobook(audioFilename: "a.m4b", title: title, author: author, duration: duration, position: position)
        b.kind = kind
        return b
    }

    // MARK: - Send to a note (D138: the source stays, the note links back)

    @MainActor
    func testSendToANoteKeepsTheSourceAndMakesALinkedNote() throws {
        let store = makeStore()
        let repo = NotesRepository(inMemory: true)
        let b = book("Four Thousand Weeks")
        store.add(b)

        let id = try XCTUnwrap(LibraryHatch.sendToNote(book: b, repository: repo))

        XCTAssertNotNil(store.book(id: b.id), "Send to a note keeps the source in Library")
        let memo = try XCTUnwrap(repo.memo(id: id))
        XCTAssertEqual(memo.metadata?.bookID, b.id)
        XCTAssertEqual(memo.metadata?.bookTitle, "Four Thousand Weeks")
        XCTAssertEqual(memo.metadata?.bookAuthor, "Oliver Burkeman")
        XCTAssertEqual(memo.metadata?.bookPosition, 4325)
        XCTAssertNil(memo.captureQuote, "a sent note holds no quote, only the link card")
        XCTAssertTrue(LibraryHatch.isSourceLink(memo))
        XCTAssertEqual(BookNotesJoin.jumpTarget(for: memo), BookNotesJoin.JumpTarget(bookID: b.id, position: 4325))
        XCTAssertEqual(BookNotesJoin.counts(in: [memo])[b.id], 1, "it counts as a note from this source")
    }

    @MainActor
    func testSendToANoteFromAPdfLinksToItsPage() throws {
        let repo = NotesRepository(inMemory: true)
        let pdf = book("GFR grant application, draft 3", author: "", kind: .pdf, duration: 18, position: 4)
        let memo = try XCTUnwrap(repo.memo(id: try XCTUnwrap(LibraryHatch.sendToNote(book: pdf, repository: repo))))
        XCTAssertEqual(memo.metadata?.bookChapter, "p. 4")
        XCTAssertEqual(memo.metadata?.bookPosition, 4)
        XCTAssertNil(memo.metadata?.bookAuthor, "an empty author is not written")
    }

    @MainActor
    func testAnUnopenedPdfLinksToPageOne() throws {
        let repo = NotesRepository(inMemory: true)
        let pdf = book("Sensor budget, revised", author: "", kind: .pdf, duration: 6, position: 0)
        let memo = try XCTUnwrap(repo.memo(id: try XCTUnwrap(LibraryHatch.sendToNote(book: pdf, repository: repo))))
        XCTAssertEqual(memo.metadata?.bookChapter, "p. 1")
        XCTAssertEqual(memo.metadata?.bookPosition, 1)
    }

    func testTheLinkCardSaysKindPlaceAndWhereItOpens() {
        XCTAssertEqual(LibraryHatch.cardDetail(for: book("Four Thousand Weeks")),
                       "Audiobook · 1:12:05 · open in Library ›")
        XCTAssertEqual(LibraryHatch.cardDetail(for: book("Het Uur", kind: .episode, duration: 3713, position: 1421)),
                       "Episode · 23:41 · open in Library ›")
        XCTAssertEqual(LibraryHatch.cardDetail(for: book("GFR", kind: .pdf, duration: 18, position: 4)),
                       "PDF · p. 4 of 18 · open in Library ›")
    }

    func testSentToastNamesTheSourceThatStays() {
        XCTAssertEqual(LibraryHatch.sentToast(title: "Four Thousand Weeks"),
                       "Sent to Notes. Four Thousand Weeks stays in Library.")
        XCTAssertEqual(LibraryHatch.sendLabel, "Send to a note")
    }

    // MARK: - Move to Library (a note with a PDF)

    @MainActor
    private func pdfNote(repo: NotesRepository, words: String?) throws -> Memo {
        let src = try makePDF(pages: 12, named: "Studio lease, Rua da Rosa.pdf")
        let id = UUID()
        let destName = "file_\(id.uuidString).pdf"
        let dest = AppPaths.recordingsDirectory.appendingPathComponent(destName)
        try FileManager.default.createDirectory(at: AppPaths.recordingsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: src, to: dest)
        let shared = SharedContent(type: .file, filePath: destName,
                                   fileName: "Studio lease, Rua da Rosa.pdf", mimeType: "application/pdf")
        let memo = Memo.make(id: id, recordedAt: Date(), syncStatus: .waiting,
                             transcriptStatus: .done, sharedContent: shared)
        memo.annotationText = words
        repo.insert(memo)
        return memo
    }

    @MainActor
    func testMoveToLibraryIsOfferedOnlyOnANoteThatHoldsAPdf() throws {
        let repo = NotesRepository(inMemory: true)
        XCTAssertTrue(LibraryHatch.canMoveToLibrary(try pdfNote(repo: repo, words: "x")))
        let typed = Memo.make(id: UUID(), recordedAt: Date(), syncStatus: .waiting, transcript: "plain",
                              transcriptStatus: .done)
        XCTAssertFalse(LibraryHatch.canMoveToLibrary(typed))
        let image = Memo.make(id: UUID(), recordedAt: Date(), syncStatus: .waiting, transcriptStatus: .done,
                              sharedContent: SharedContent(type: .image, filePath: "img.jpg"))
        XCTAssertFalse(LibraryHatch.canMoveToLibrary(image))
        XCTAssertEqual(LibraryHatch.moveLabel, "Move to Library")
    }

    @MainActor
    func testMoveToLibraryMovesThePdfAndKeepsHisWordsAsALinkedNote() throws {
        let store = makeStore()
        let repo = NotesRepository(inMemory: true)
        let words = "Landlord wants an answer by Friday."
        let memo = try pdfNote(repo: repo, words: words)
        let file = try XCTUnwrap(memo.sharedFileURL)

        let moved = try XCTUnwrap(LibraryHatch.moveToLibrary(memo: memo, store: store, repository: repo))

        XCTAssertEqual(moved.sourceKind, .pdf)
        XCTAssertEqual(moved.title, "Studio lease, Rua da Rosa")
        XCTAssertEqual(LibraryPDF.pageCount(of: moved), 12)
        XCTAssertNotNil(store.book(id: moved.id), "the PDF is on the shelf")
        XCTAssertNil(memo.sharedContent, "the PDF left the note")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "the note's copy is gone")
        XCTAssertEqual(memo.transcript, words, "his words stay in Notes")
        XCTAssertNil(memo.annotationText)
        XCTAssertEqual(memo.metadata?.bookID, moved.id)
        XCTAssertEqual(memo.metadata?.bookChapter, "p. 1")
        XCTAssertTrue(LibraryHatch.isSourceLink(memo), "the note now links to the source")
        XCTAssertEqual(LibraryHatch.movedToast, "Moved to Library. Your words stay in Notes, linked to it.")
    }

    // MARK: - A PDF capture is a PDF quote (Q354 carry-over, D138)

    @MainActor
    func testAPdfCaptureLabelsAsAPdfQuote() throws {
        let repo = NotesRepository(inMemory: true)
        let pdf = book("GFR grant application, draft 3", author: "", kind: .pdf, duration: 18, position: 4)
        let id = try XCTUnwrap(LibraryPDF.saveCapture(quote: "Sensor integration: €18,000", book: pdf, page: 4,
                                                      significance: 0.4, repository: repo))
        let memo = try XCTUnwrap(repo.memo(id: id))
        XCTAssertEqual(SourceKind.of(memo), .pdfQuote)
        XCTAssertEqual(SourceKind.pdfQuote.label, "PDF quote")
        XCTAssertEqual(SourceKind.pdfQuote.glyph, "doc.text")
        XCTAssertEqual(SourceKind.classify(hasBook: true, media: nil, sharedType: nil, hasAudio: false),
                       .audiobookQuote, "a book quote is still an audiobook quote")
    }

    @MainActor
    func testAPdfCaptureExportsAsAPdfQuote() throws {
        let repo = NotesRepository(inMemory: true)
        let pdf = book("GFR grant application, draft 3", author: "", kind: .pdf, duration: 18, position: 4)
        let id = try XCTUnwrap(LibraryPDF.saveCapture(quote: "Sensor integration: €18,000", book: pdf, page: 4,
                                                      significance: 0.4, repository: repo))
        let md = ExportV2Test.markdown(for: try XCTUnwrap(repo.memo(id: id)), people: [])
        XCTAssertTrue(md.contains("source: PDF-quote"), md)
        XCTAssertFalse(md.contains("Audiobook-quote"), md)
        XCTAssertTrue(md.contains("> — *GFR grant application, draft 3*, p. 4"), md)
    }

    // MARK: - A podcast link shared from another app goes to Library (D90 doors)

    func testAPodcastLinkSharedBareGoesToLibrary() {
        XCTAssertTrue(CaptureInboxEntry.routesPodcastToLibrary(
            url: "https://podcasts.apple.com/nl/podcast/het-uur/id1517414426?i=1000714500000", thought: nil, significance: 0))
        XCTAssertTrue(CaptureInboxEntry.routesPodcastToLibrary(
            url: "https://open.spotify.com/episode/4rOoJ6Egrf8K2IrywzwOMk?si=x", thought: "  ", significance: 0))
        XCTAssertTrue(CaptureInboxEntry.routesPodcastToLibrary(
            url: "https://open.spotify.com/show/2MAi0BvDc6GTFvKFPXnkCL", thought: nil, significance: 0))
    }

    func testOtherLinksAndWordsOrARatingStayANote() {
        XCTAssertFalse(CaptureInboxEntry.routesPodcastToLibrary(
            url: "https://www.inkandswitch.com/local-first/", thought: nil, significance: 0),
            "an article or any other link is not a podcast")
        XCTAssertFalse(CaptureInboxEntry.routesPodcastToLibrary(
            url: "https://open.spotify.com/track/abc", thought: nil, significance: 0), "music stays out")
        XCTAssertFalse(CaptureInboxEntry.routesPodcastToLibrary(
            url: "https://open.spotify.com/episode/abc", thought: "Listen from 20 min", significance: 0),
            "his words make it a note, the same rule as a shared PDF")
        XCTAssertFalse(CaptureInboxEntry.routesPodcastToLibrary(
            url: "https://open.spotify.com/episode/abc", thought: nil, significance: 0.3))
        XCTAssertFalse(CaptureInboxEntry.routesPodcastToLibrary(url: nil, thought: nil, significance: 0))
    }

    // MARK: - The notes row under the player and the reader

    func testNotesRowSaysHowManyAndFromWhat() {
        XCTAssertEqual(LibraryHatch.notesRowTitle(count: 3, kind: .episode), "3 notes from this episode")
        XCTAssertEqual(LibraryHatch.notesRowTitle(count: 1, kind: .pdf), "1 note from this PDF")
        XCTAssertEqual(LibraryHatch.notesRowTitle(count: 2, kind: .book), "2 notes from this book")
        XCTAssertEqual(LibraryHatch.notesRowTitle(count: 0, kind: .pdf), "No notes yet")
        XCTAssertEqual(LibraryHatch.notesRowEmptyDetail, "Add note saves a quote and your voice from here.")
        XCTAssertEqual(LibraryHatch.notesRowDetail(newestTitle: "Rouw zonder datum", when: "Mon 21 Sep"),
                       "Newest: Rouw zonder datum · Mon 21 Sep")
    }

    // MARK: - Type chips on the shelf (one per kind present)

    func testTypeChipsShowAllPlusOnePerKindPresent() {
        let books = [book("A"), book("B", kind: .pdf, duration: 3, position: 0), book("C", kind: .book)]
        XCTAssertEqual(LibraryTypeFilter.chips(for: books), [.all, .kind(.book), .kind(.pdf)])
        XCTAssertEqual(LibraryTypeFilter.chips(for: [book("A")]), [],
                       "one kind on the shelf = no chips (nothing to filter)")
        XCTAssertEqual(LibraryTypeFilter.chips(for: []), [])
        XCTAssertEqual(LibraryTypeFilter.all.label, "All")
        XCTAssertEqual(LibraryTypeFilter.kind(.book).label, "Books")
        XCTAssertEqual(LibraryTypeFilter.kind(.episode).label, "Episodes")
        XCTAssertEqual(LibraryTypeFilter.kind(.pdf).label, "PDFs")
        XCTAssertEqual(LibraryTypeFilter.kind(.article).label, "Articles")
    }

    func testATypeChipFiltersTheShelf() {
        let books = [book("A"), book("B", kind: .pdf, duration: 3, position: 0), book("E", kind: .episode)]
        XCTAssertEqual(LibraryTypeFilter.kind(.pdf).apply(books).map(\.title), ["B"])
        XCTAssertEqual(LibraryTypeFilter.kind(.book).apply(books).map(\.title), ["A"], "nil kind reads as a book")
        XCTAssertEqual(LibraryTypeFilter.all.apply(books).count, 3)
    }

    // MARK: - The cover as the mock draws it (title + author on the cover)

    func testTheDrawnCoverCarriesTitleAndAuthor() {
        XCTAssertEqual(BookCoverText.lines(for: book("Four Thousand Weeks")),
                       BookCoverText(title: "Four Thousand Weeks", byline: "Oliver Burkeman"))
        XCTAssertEqual(BookCoverText.lines(for: book("Joris Luyendijk: Ik zit…", author: "NRC Het Uur", kind: .episode)),
                       BookCoverText(title: "NRC Het Uur", byline: "podcast"),
                       "an episode's cover shows the show, like the mock's 'Het Uur · NRC · podcast'")
        XCTAssertEqual(BookCoverText.lines(for: book("GFR grant application", author: "", kind: .pdf)),
                       BookCoverText(title: "GFR grant application", byline: nil))
        XCTAssertEqual(BookCoverText.lines(for: book("Untitled", author: "  ")).byline, nil)
    }
}
