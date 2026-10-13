import UIKit
import XCTest
@testable import SkriftMobile

/// Q372 (D90 / D138): "Move to Library" MOVES the PDF, so the note's synced `document`
/// MemoAsset goes once the Library copy exists, never before (no data loss if the move fails
/// midway). And a link note is a link on the phone too: the shared classifier names it and the
/// phone exporter writes a link line, never an empty quote block.
final class LibraryHatchMoveTests: XCTestCase {

    @MainActor
    private func makeStore(directory: URL? = nil) -> AudiobookLibraryStore {
        let dir = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("audiobooks_\(UUID().uuidString)", isDirectory: true)
        return AudiobookLibraryStore(directory: dir)
    }

    private func pdfData(pages: Int) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { ctx in
            for p in 1...pages {
                ctx.beginPage()
                ("Lease page \(p)" as NSString)
                    .draw(at: CGPoint(x: 72, y: 72), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
            }
        }
    }

    /// A note holding a PDF, with its `document` asset captured the way the sweep does.
    @MainActor
    private func pdfNote(repo: NotesRepository, bytes: Data) throws -> Memo {
        let id = UUID()
        let destName = "file_\(id.uuidString).pdf"
        try FileManager.default.createDirectory(at: AppPaths.recordingsDirectory, withIntermediateDirectories: true)
        try bytes.write(to: AppPaths.recordingsDirectory.appendingPathComponent(destName))
        let shared = SharedContent(type: .file, filePath: destName,
                                   fileName: "Studio lease, Rua da Rosa.pdf", mimeType: "application/pdf")
        let memo = Memo.make(id: id, recordedAt: Date(), syncStatus: .waiting,
                             transcriptStatus: .done, sharedContent: shared)
        memo.annotationText = "Landlord wants an answer by Friday."
        repo.insert(memo)
        AssetMaterializer.capture(memoID: id, repository: repo)
        return memo
    }

    @MainActor
    private func documentAssets(_ memo: Memo, _ repo: NotesRepository) -> [MemoAsset] {
        repo.assets(forMemo: memo.id).filter { $0.kind == MemoAsset.Kind.document }
    }

    // MARK: - The asset goes only after the Library copy is written

    @MainActor
    func testMoveRemovesTheDocumentAssetOnceTheLibraryCopyExists() throws {
        let store = makeStore()
        let repo = NotesRepository(inMemory: true)
        let memo = try pdfNote(repo: repo, bytes: pdfData(pages: 3))
        XCTAssertEqual(documentAssets(memo, repo).count, 1, "fixture: the PDF is a synced asset")

        let book = try XCTUnwrap(LibraryHatch.moveToLibrary(memo: memo, store: store, repository: repo))

        let copy = store.folder(for: book.id).appendingPathComponent(try XCTUnwrap(book.files.first))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path), "the Library copy is written")
        XCTAssertEqual(documentAssets(memo, repo).count, 0, "the note's document asset is removed")
        XCTAssertTrue(LibraryHatch.isSourceLink(memo))
    }

    @MainActor
    func testAnUnreadablePdfLeavesTheAssetAndTheNote() throws {
        let store = makeStore()
        let repo = NotesRepository(inMemory: true)
        let memo = try pdfNote(repo: repo, bytes: Data("not a pdf".utf8))

        XCTAssertNil(LibraryHatch.moveToLibrary(memo: memo, store: store, repository: repo))

        XCTAssertEqual(documentAssets(memo, repo).count, 1, "nothing moved, nothing removed")
        XCTAssertNotNil(memo.sharedContent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(memo.sharedFileURL).path))
    }

    @MainActor
    func testAFailedLibraryWriteLeavesTheAssetAndTheNote() throws {
        // The Library directory sits under a regular FILE, so the copy can never be written.
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("blocker_\(UUID().uuidString)")
        try Data("x".utf8).write(to: blocker)
        let store = makeStore(directory: blocker.appendingPathComponent("audiobooks", isDirectory: true))
        let repo = NotesRepository(inMemory: true)
        let memo = try pdfNote(repo: repo, bytes: pdfData(pages: 2))

        XCTAssertNil(LibraryHatch.moveToLibrary(memo: memo, store: store, repository: repo))

        XCTAssertEqual(documentAssets(memo, repo).count, 1, "the asset stays when the copy failed")
        XCTAssertNotNil(memo.sharedContent, "the note still holds its PDF")
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(memo.sharedFileURL).path))
        XCTAssertTrue(store.books.isEmpty)
    }

    // MARK: - A link note is a link on the phone (the shared rule)

    private func source(_ title: String, author: String = "", kind: LibrarySourceKind,
                        duration: TimeInterval, position: TimeInterval) -> Audiobook {
        var b = Audiobook(audioFilename: "a.m4b", title: title, author: author, duration: duration, position: position)
        b.kind = kind
        return b
    }

    @MainActor
    func testASentNoteClassifiesAndExportsAsALink() throws {
        let repo = NotesRepository(inMemory: true)
        let pdf = source("GFR grant application, draft 3", kind: .pdf, duration: 18, position: 4)
        let memo = try XCTUnwrap(repo.memo(id: try XCTUnwrap(LibraryHatch.sendToNote(book: pdf, repository: repo))))
        XCTAssertEqual(memo.metadata?.bookKind, "pdf")
        XCTAssertEqual(SourceKind.of(memo), .pdfLink)

        let md = MemoExporter.markdown(for: memo, people: [])
        XCTAssertTrue(md.contains("source: PDF-link"), md)
        XCTAssertTrue(md.contains("— *GFR grant application, draft 3*, p. 4"), md)
        XCTAssertFalse(md.contains("PDF-quote"), md)
        XCTAssertFalse(md.contains("\n>"), "never an empty quote block: \(md)")
    }

    @MainActor
    func testASentEpisodeExportsShowEpisodeAndTime() throws {
        let repo = NotesRepository(inMemory: true)
        let ep = source("Joris Luyendijk: Ik zit in een rouwproces", author: "NRC Het Uur",
                        kind: .episode, duration: 3713, position: 1421)
        let memo = try XCTUnwrap(repo.memo(id: try XCTUnwrap(LibraryHatch.sendToNote(book: ep, repository: repo))))
        XCTAssertEqual(SourceKind.of(memo), .episodeLink)
        let md = MemoExporter.markdown(for: memo, people: [])
        XCTAssertTrue(md.contains("source: Episode-link"), md)
        XCTAssertTrue(md.contains("— *NRC Het Uur*, Joris Luyendijk: Ik zit in een rouwproces, 23:41"), md)
    }
}
