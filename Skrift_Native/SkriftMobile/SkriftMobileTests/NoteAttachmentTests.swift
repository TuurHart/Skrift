import XCTest
import SwiftData
@testable import SkriftMobile

/// Q385 (D199, D202, mock Q384-note-attachments): the attach menu puts a real video or file in a
/// note, as a `[[vid_NNN]]` / `[[file_NNN]]` block that syncs as a `MemoAsset`, draws small by
/// default and switches small/large per block or all at once.
@MainActor
final class NoteAttachmentTests: XCTestCase {

    private let fm = FileManager.default
    private var cleanup: [URL] = []
    override func tearDown() { cleanup.forEach { try? fm.removeItem(at: $0) }; cleanup = [] }

    private func picked(_ name: String, bytes: Int = 32) throws -> URL {
        let dir = fm.temporaryDirectory.appendingPathComponent("nat_\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data(repeating: 3, count: bytes).write(to: url)
        cleanup.append(dir)
        return url
    }

    // MARK: markers (Shared, one rule both apps)

    func testMarkersAreBlockMarkersLikePhotos() {
        XCTAssertEqual(NoteAttachment.literal(kind: NoteAttachment.Kind.video, number: 1), "[[vid_001]]")
        XCTAssertEqual(NoteAttachment.literal(kind: NoteAttachment.Kind.file, number: 12), "[[file_012]]")
        let found = NoteAttachment.markers(in: "a\n\n[[vid_002]]\n\nb [[img_001]]\n\n[[file_1]]")
        XCTAssertEqual(found.map(\.kind), [NoteAttachment.Kind.video, NoteAttachment.Kind.file])
        XCTAssertEqual(found.map(\.number), [2, 1])
    }

    func testInsertPutsTheBlockInItsOwnParagraphAfterTheSentence() {
        let body = "Rui opened the bonnet. Listen for the tick.\n\nSecond paragraph."
        let caret = (body as NSString).range(of: "the bonnet").location
        let r = NoteAttachment.inserting(kind: NoteAttachment.Kind.video, number: 1, into: body, atOffset: caret)
        XCTAssertEqual(r.text, "Rui opened the bonnet.\n\n[[vid_001]]\n\nListen for the tick.\n\nSecond paragraph.")
        XCTAssertEqual((r.text as NSString).substring(with: NSRange(location: r.markerOffset, length: 11)), "[[vid_001]]")
        let end = NoteAttachment.inserting(kind: NoteAttachment.Kind.file, number: 2, into: r.text,
                                           atOffset: (r.text as NSString).length)
        XCTAssertTrue(end.text.hasSuffix("Second paragraph.\n\n[[file_002]]"), end.text)
    }

    // MARK: the attach menu inserts a real video / file

    func testAttachFileCopiesItIntoTheNoteWithItsNameAndType() throws {
        let memo = Memo.make(audioFilename: "")
        let added = try XCTUnwrap(NoteAttachmentStore.add(fileURL: try picked("orcamento-oficina-out.xlsx", bytes: 38), to: memo))
        cleanup.append(NoteAttachmentStore.fileURL(added.entry))
        XCTAssertEqual(added.number, 1)
        XCTAssertEqual(added.entry.kind, NoteAttachment.Kind.file)
        XCTAssertEqual(added.entry.name, "orcamento-oficina-out.xlsx")
        XCTAssertEqual(added.entry.uti, "org.openxmlformats.spreadsheetml.sheet")
        XCTAssertEqual(added.entry.byteCount, 38)
        XCTAssertEqual(added.entry.filename, "file_\(memo.id.uuidString)_001.xlsx")
        XCTAssertTrue(NoteAttachmentStore.fileExists(added.entry))
        XCTAssertEqual(memo.metadata?.attachmentManifest, [added.entry])
    }

    func testChooseVideoIsAVideoAttachment() throws {
        let memo = Memo.make(audioFilename: "")
        let added = try XCTUnwrap(NoteAttachmentStore.add(fileURL: try picked("IMG_0467.MOV"), uti: "com.apple.quicktime-movie", to: memo))
        cleanup.append(NoteAttachmentStore.fileURL(added.entry))
        XCTAssertEqual(added.entry.kind, NoteAttachment.Kind.video)
        XCTAssertEqual(added.entry.filename, "video_\(memo.id.uuidString)_001.mov")
        XCTAssertEqual(NoteAttachment.kindLabel(added.entry), "Video")
    }

    // MARK: sync (MemoAsset kinds, no new record type)

    func testTheSweepSyncsEachAttachmentAsAMemoAssetOfItsKind() throws {
        let repo = NotesRepository(inMemory: true)
        let memo = Memo.make(audioFilename: "")
        repo.insert(memo)
        let file = try XCTUnwrap(NoteAttachmentStore.add(fileURL: try picked("loom.dxf"), to: memo))
        let video = try XCTUnwrap(NoteAttachmentStore.add(fileURL: try picked("tick.mov"), to: memo))
        cleanup += [NoteAttachmentStore.fileURL(file.entry), NoteAttachmentStore.fileURL(video.entry)]

        AssetMaterializer.captureMissing(repo)

        let assets = repo.assets(forMemo: memo.id)
        XCTAssertEqual(Set(assets.map(\.kind)), [MemoAsset.Kind.file, MemoAsset.Kind.video])
        XCTAssertEqual(Set(assets.map(\.filename)), [file.entry.filename, video.entry.filename])
        XCTAssertEqual(MemoAsset.Kind.file, "file")
    }

    // MARK: small / large (D202)

    func testEveryAttachmentIsSmallByDefaultAndSwitchesOnItsOwn() throws {
        let memo = Memo.make(audioFilename: "")
        let a = try XCTUnwrap(NoteAttachmentStore.add(fileURL: try picked("a.mov"), to: memo))
        let b = try XCTUnwrap(NoteAttachmentStore.add(fileURL: try picked("b.pdf"), to: memo))
        cleanup += [NoteAttachmentStore.fileURL(a.entry), NoteAttachmentStore.fileURL(b.entry)]
        XCTAssertEqual(NoteAttachment.size(of: a.entry.filename, large: memo.metadata?.largeAttachments), .small)

        NoteAttachmentStore.setSize(.large, filename: a.entry.filename, memo: memo)
        XCTAssertEqual(NoteAttachment.size(of: a.entry.filename, large: memo.metadata?.largeAttachments), .large)
        XCTAssertEqual(NoteAttachment.size(of: b.entry.filename, large: memo.metadata?.largeAttachments), .small)

        NoteAttachmentStore.setSize(.large, filename: nil, memo: memo)       // ⋯ Set All to Large
        XCTAssertEqual(Set(memo.metadata?.largeAttachments ?? []), [a.entry.filename, b.entry.filename])
        NoteAttachmentStore.setSize(.small, filename: nil, memo: memo)       // ⋯ Set All to Small
        XCTAssertNil(memo.metadata?.largeAttachments)
        XCTAssertEqual(NoteAttachment.setAllSmallTitle, "Set All to Small")
        XCTAssertEqual(NoteAttachment.setAllLargeTitle, "Set All to Large")
    }

    // MARK: the look (mock picks 2, 4, 5, 8)

    func testATallVideoIsCutAt420OnThePhone() {
        XCTAssertEqual(NoteAttachment.videoHeight(width: 362, natural: CGSize(width: 1080, height: 1920),
                                                  maxHeight: NoteAttachment.phoneVideoMaxHeight), 420)
        XCTAssertEqual(NoteAttachment.videoHeight(width: 362, natural: CGSize(width: 1920, height: 1080),
                                                  maxHeight: NoteAttachment.phoneVideoMaxHeight), 204)
        XCTAssertEqual(NoteAttachment.wideMediaMaxWidth, 720)
    }

    func testTheFileCardSaysKindAndSizeAndTheVideoItsDuration() {
        let file = NoteAttachmentEntry(kind: NoteAttachment.Kind.file, filename: "f", name: "fan-loom-bracket-rev-c.dxf",
                                       uti: NoteAttachment.uti(forFilename: "x.dxf"), byteCount: 412_000)
        XCTAssertTrue(NoteAttachment.subtitle(file).hasSuffix("· 412 KB"), NoteAttachment.subtitle(file))
        XCTAssertEqual(NoteAttachment.badge(file), "DXF")
        let video = NoteAttachmentEntry(kind: NoteAttachment.Kind.video, filename: "v", name: "v.mov",
                                        uti: "com.apple.quicktime-movie", byteCount: 1000, durationSeconds: 42)
        XCTAssertEqual(NoteAttachment.durationLabel(video), "0:42")
    }
}
