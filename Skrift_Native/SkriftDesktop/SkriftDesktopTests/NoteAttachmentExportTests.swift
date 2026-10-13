import XCTest
import Foundation
import SwiftData

/// Q385 (D199, D202, mock Q384-note-attachments): a video or file inside a note body is added on
/// the Mac, lands on disk from sync, and exports beside the note as an embed, like a photo.
final class NoteAttachmentExportTests: XCTestCase {

    private var work: URL!
    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("nae_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: work) }

    private func memContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Memo.self, MemoAsset.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func sourceFile(_ name: String, bytes: Int = 64) throws -> URL {
        let dir = work.appendingPathComponent("picked", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data(repeating: 7, count: bytes).write(to: url)
        return url
    }

    private func vaultFiles(_ vault: URL) -> [String] {
        let e = FileManager.default.enumerator(at: vault, includingPropertiesForKeys: nil)
        return (e?.allObjects as? [URL] ?? []).map(\.lastPathComponent)
    }

    // MARK: adding on the Mac

    func testAddCopiesTheFileWritesTheManifestAndTellsTheMemo() throws {
        let ctx = try memContext()
        let memo = Memo(id: UUID(), audioFilename: "m.m4a", transcript: "t")
        ctx.insert(memo)
        let noteFolder = work.appendingPathComponent("note", isDirectory: true)
        try FileManager.default.createDirectory(at: noteFolder, withIntermediateDirectories: true)
        let pf = PipelineFile(id: memo.id.uuidString, filename: "m.m4a",
                              path: noteFolder.appendingPathComponent("original.m4a").path, sourceType: .audio)

        let added = try XCTUnwrap(MacNoteAttachments.add(fileURL: try sourceFile("fan-loom-bracket-rev-c.dxf", bytes: 412),
                                                         to: pf, memo: memo, context: ctx))

        XCTAssertEqual(added.number, 1)
        XCTAssertEqual(added.entry.kind, NoteAttachment.Kind.file)
        XCTAssertEqual(added.entry.name, "fan-loom-bracket-rev-c.dxf")
        XCTAssertEqual(added.entry.byteCount, 412)
        XCTAssertEqual(added.entry.filename, "file_\(memo.id.uuidString)_001.dxf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: added.fileURL.path))
        XCTAssertEqual(MacNoteAttachments.manifest(in: noteFolder), [added.entry])
        XCTAssertEqual(memo.metadata?.attachmentManifest, [added.entry])
        let rows = try ctx.fetch(FetchDescriptor<MemoAsset>())
        XCTAssertEqual(rows.map(\.kind), [MemoAsset.Kind.file])
        XCTAssertEqual(rows.map(\.filename), [added.entry.filename])
    }

    func testAMovieIsAVideoAttachment() throws {
        let noteFolder = work.appendingPathComponent("note2", isDirectory: true)
        try FileManager.default.createDirectory(at: noteFolder, withIntermediateDirectories: true)
        let pf = PipelineFile(id: UUID().uuidString, filename: "m.m4a",
                              path: noteFolder.appendingPathComponent("original.m4a").path, sourceType: .audio)
        let added = try XCTUnwrap(MacNoteAttachments.add(fileURL: try sourceFile("engine.mov"), to: pf, memo: nil, context: nil))
        XCTAssertEqual(added.entry.kind, NoteAttachment.Kind.video)
        XCTAssertTrue(added.entry.filename.hasPrefix("video_"))
        XCTAssertTrue(MacNoteAttachments.isAttachment(URL(fileURLWithPath: "/x/engine.mov")))
        XCTAssertFalse(MacNoteAttachments.isAttachment(URL(fileURLWithPath: "/x/photo.jpg")))
    }

    // MARK: sync heal

    func testASyncedAttachmentLandsOnDiskWithItsManifest() throws {
        let ctx = try memContext()
        let memo = Memo(id: UUID(), audioFilename: "m.m4a", transcript: "[[file_001]]")
        let entry = NoteAttachment.makeEntry(owner: memo.id, number: 1, originalName: "quote.xlsx", byteCount: 3)
        var meta = MemoMetadata()
        meta.attachmentManifest = [entry]
        memo.metadata = meta
        ctx.insert(memo)
        let asset = MemoAsset(memoID: memo.id, kind: MemoAsset.Kind.file, filename: entry.filename, blob: Data([1, 2, 3]))
        ctx.insert(asset)
        let noteFolder = work.appendingPathComponent("note3", isDirectory: true)
        try FileManager.default.createDirectory(at: noteFolder, withIntermediateDirectories: true)
        let pf = PipelineFile(id: memo.id.uuidString, filename: "m.m4a",
                              path: noteFolder.appendingPathComponent("original.m4a").path, sourceType: .audio)

        XCTAssertTrue(MacNoteAttachments.materializeMissing(memo: memo, pf: pf, fetchAssets: { [asset] }))
        XCTAssertNotNil(MacNoteAttachments.fileURL(entry, working: noteFolder))
        XCTAssertEqual(MacNoteAttachments.manifest(in: noteFolder), [entry])
        XCTAssertFalse(MacNoteAttachments.materializeMissing(memo: memo, pf: pf, fetchAssets: { XCTFail("no fetch once healed"); return [] }),
                       "idempotent: nothing written, no blob fetched")
    }

    // MARK: export (D199: beside the note, like photos)

    func testExportCopiesTheFileBesideTheNoteAndEmbedsIt() throws {
        let noteFolder = work.appendingPathComponent("note4", isDirectory: true)
        try FileManager.default.createDirectory(at: noteFolder, withIntermediateDirectories: true)
        let audio = noteFolder.appendingPathComponent("original.m4a")
        try Data([1, 2, 3]).write(to: audio)
        let pf = PipelineFile(id: UUID().uuidString, filename: "memo.m4a", path: audio.path, size: 3, sourceType: .audio)
        let file = try XCTUnwrap(MacNoteAttachments.add(fileURL: try sourceFile("quote.xlsx"), to: pf, memo: nil, context: nil))
        let video = try XCTUnwrap(MacNoteAttachments.add(fileURL: try sourceFile("tick.mov"), to: pf, memo: nil, context: nil))
        pf.enhancedTitle = "Engine tick"
        pf.sanitised = "Listen for the tick.\n\n\(NoteAttachment.literal(kind: video.entry.kind, number: 2))\n\nHis quote:\n\n\(NoteAttachment.literal(kind: file.entry.kind, number: 1))"

        let vault = work.appendingPathComponent("vault")
        var settings = AppSettings.default
        settings.noteFolder = vault.path
        let r = try VaultExporter.export(pf, settings: settings)

        let md = try String(contentsOf: r.markdownURL, encoding: .utf8)
        XCTAssertTrue(md.contains("![[Engine tick - quote.xlsx]]"), md)
        XCTAssertTrue(md.contains("![[Engine tick_video_002.mov]]"), md)
        XCTAssertFalse(md.contains("[[file_"), md)
        XCTAssertFalse(md.contains("[[vid_"), md)
        let files = vaultFiles(vault)
        XCTAssertTrue(files.contains("Engine tick - quote.xlsx"), "\(files)")
        XCTAssertTrue(files.contains("Engine tick_video_002.mov"), "\(files)")
    }

    func testADanglingAttachmentMarkerIsDroppedNotPrinted() {
        let r = NoteAttachment.convertMarkers("A\n\n[[file_003]]\n\nB", manifest: [], stem: "N", profile: .obsidian) { _, n in n }
        XCTAssertEqual(r.placed, 0)
        XCTAssertFalse(r.markdown.contains("[[file_"))
    }

    func testAMarkerOfTheWrongKindStaysTheAuthorsText() {
        let e = NoteAttachment.makeEntry(owner: UUID(), number: 1, originalName: "a.pdf", byteCount: 1)
        XCTAssertNil(NoteAttachment.entry(kind: NoteAttachment.Kind.video, number: 1, manifest: [e]))
        XCTAssertEqual(NoteAttachment.slot(kind: NoteAttachment.Kind.video, number: 1, manifest: [e],
                                           fileExists: { _ in true }, hasAsset: { _ in true }), .text)
    }

    // MARK: small / large (D202)

    func testSetSizeIsSyncedNoteStateAndSetAllCoversEveryAttachment() throws {
        let ctx = try memContext()
        let memo = Memo(id: UUID(), audioFilename: "m.m4a", transcript: "t")
        ctx.insert(memo)
        MacNoteAttachments.setSize(.large, filename: "a.mov", memo: memo, allFilenames: ["a.mov", "b.pdf"], context: ctx)
        XCTAssertEqual(memo.metadata?.largeAttachments, ["a.mov"])
        XCTAssertEqual(NoteAttachment.size(of: "b.pdf", large: memo.metadata?.largeAttachments), .small)
        MacNoteAttachments.setSize(.large, filename: nil, memo: memo, allFilenames: ["a.mov", "b.pdf"], context: ctx)
        XCTAssertEqual(memo.metadata?.largeAttachments, ["a.mov", "b.pdf"])
        MacNoteAttachments.setSize(.small, filename: nil, memo: memo, allFilenames: ["a.mov", "b.pdf"], context: ctx)
        XCTAssertNil(memo.metadata?.largeAttachments, "all small = the default, stored as absent")
    }
}
