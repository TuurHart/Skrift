import XCTest
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers

/// Q325 (mock Q128-mac-note-photos, D181/D182): a photo is added at the caret, and a marker
/// whose file has not arrived draws the phone's card instead of raw marker text.
final class MacNotePhotoTests: XCTestCase {

    private var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("mnp_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    // MARK: insert at the caret

    private let body = "Cable tray has to move. About twenty centimetres left.\n\nSecond paragraph here."

    func testInsertAtAParagraphBoundaryWritesTheMarkerAtTheCaretOffset() {
        let caret = (body as NSString).range(of: "\n\nSecond").location          // end of paragraph one
        let r = NotePhoto.inserting(number: 1, into: body, atOffset: caret, manifestCount: 1)
        XCTAssertEqual(r.text, "Cable tray has to move. About twenty centimetres left.\n\n[[img_001]]\n\nSecond paragraph here.")
        XCTAssertEqual(r.markerOffset, caret + 2, "the marker sits in its own paragraph right at the caret")
    }

    func testInsertAtTheStartPutsThePhotoOnTop() {
        let r = NotePhoto.inserting(number: 1, into: body, atOffset: 0, manifestCount: 1)
        XCTAssertTrue(r.text.hasPrefix("[[img_001]]\n\nCable tray"), r.text)
        XCTAssertEqual(r.markerOffset, 0)
    }

    func testInsertMidSentenceLandsAfterThatSentenceNotInsideIt() {
        // Pick 2 of the signed mock: never splits a sentence; the phone's save step does the same.
        let caret = (body as NSString).range(of: "has to").location + 3
        let r = NotePhoto.inserting(number: 1, into: body, atOffset: caret, manifestCount: 1)
        XCTAssertTrue(r.text.hasPrefix("Cable tray has to move.\n\n[[img_001]]\n\nAbout twenty"), r.text)
    }

    func testInsertAtTheEndAppendsAndKeepsEarlierPhotos() {
        let withOne = "Intro sentence.\n\n[[img_001]]\n\nTail sentence."
        let r = NotePhoto.inserting(number: 2, into: withOne, atOffset: (withOne as NSString).length, manifestCount: 2)
        XCTAssertEqual(r.text, "Intro sentence.\n\n[[img_001]]\n\nTail sentence.\n\n[[img_002]]")
        XCTAssertEqual(BodyV2Marker.numbers(in: r.text), [1, 2])
    }

    func testFilenameFollowsThePhoneConvention() {
        let id = UUID()
        XCTAssertEqual(NotePhoto.filename(owner: id, number: 3, ext: "png"), "photo_\(id.uuidString)_003.png")
        XCTAssertEqual(NotePhoto.filename(owner: id, number: 12, ext: ""), "photo_\(id.uuidString)_012.jpg")
    }

    // MARK: a marker whose file has not arrived

    func testMissingFileWithASyncedRowIsTheDownloadingCard() {
        let slot = NotePhoto.slot(number: 2, manifest: ["a.jpg", "b.jpg"],
                                  fileExists: { $0 == "a.jpg" }, hasAsset: { _ in true })
        XCTAssertEqual(slot, .downloading)
        XCTAssertEqual(NotePhoto.downloadingCopy, "Downloading from iCloud…")
        XCTAssertEqual(NotePhoto.cardHeight, 160)
    }

    func testMissingFileWithNoRowIsThePlainPhotoCard() {
        XCTAssertEqual(NotePhoto.slot(number: 1, manifest: ["a.jpg"], fileExists: { _ in false }, hasAsset: { _ in false }),
                       .missing)
    }

    func testPresentFileIsThePhoto() {
        XCTAssertEqual(NotePhoto.slot(number: 1, manifest: ["a.jpg"], fileExists: { _ in true }, hasAsset: { _ in false }),
                       .present)
    }

    func testAMarkerWithNoManifestEntryStaysText() {
        XCTAssertEqual(NotePhoto.slot(number: 3, manifest: ["a.jpg"], fileExists: { _ in false }, hasAsset: { _ in true }), .text)
        XCTAssertEqual(NotePhoto.slot(number: 0, manifest: ["a.jpg"], fileExists: { _ in false }, hasAsset: { _ in true }), .text)
    }

    func testSlotReadsTheWorkingFolderManifestAndFiles() throws {
        try writeManifest(["p_001.jpg", "p_002.jpg"])
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("images"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appendingPathComponent("images/p_001.jpg"))
        XCTAssertEqual(MacNotePhotos.slot(number: 1, folder: folder, hasAsset: { _ in false }), .present)
        XCTAssertEqual(MacNotePhotos.slot(number: 2, folder: folder, hasAsset: { $0 == "p_002.jpg" }), .downloading)
        XCTAssertEqual(MacNotePhotos.slot(number: 2, folder: folder, hasAsset: { _ in false }), .missing)
        XCTAssertEqual(MacNotePhotos.slot(number: 3, folder: folder, hasAsset: { _ in true }), .text)
        XCTAssertEqual(MacNotePhotos.slot(number: 1, folder: nil, hasAsset: { _ in true }), .text)
    }

    // MARK: storing the photo

    func testAddStoresTheFileAndManifestEntry() throws {
        let pf = PipelineFile(id: UUID().uuidString, filename: "m.m4a",
                              path: folder.appendingPathComponent("original.m4a").path, sourceType: .audio)
        let first = try XCTUnwrap(MacNotePhotos.add(imageData: try pngData(), to: pf, memo: nil, context: nil))
        let second = try XCTUnwrap(MacNotePhotos.add(imageData: try pngData(), to: pf, memo: nil, context: nil))
        XCTAssertEqual([first.number, second.number], [1, 2])
        XCTAssertEqual(second.manifestCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.fileURL.path))
        XCTAssertEqual(MacNotePhotos.manifest(in: folder).map(\.filename), [first.filename, second.filename])
        XCTAssertEqual(MacNotePhotos.fileURL(number: 2, folder: folder), second.fileURL, "marker 2 resolves to the new file")
    }

    func testAddRefusesBytesThatAreNotAPicture() {
        let pf = PipelineFile(id: UUID().uuidString, filename: "m.m4a",
                              path: folder.appendingPathComponent("original.m4a").path, sourceType: .audio)
        XCTAssertNil(MacNotePhotos.add(imageData: Data("not an image".utf8), to: pf, memo: nil, context: nil))
        XCTAssertTrue(MacNotePhotos.manifest(in: folder).isEmpty)
    }

    func testAddTellsTheMemoSoThePhoneGetsThePhoto() throws {
        let container = try ModelContainer(for: Memo.self, MemoAsset.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let memo = Memo(id: UUID(), audioFilename: "m.m4a", transcript: "t")
        ctx.insert(memo)
        let pf = PipelineFile(id: memo.id.uuidString, filename: "m.m4a",
                              path: folder.appendingPathComponent("original.m4a").path, sourceType: .audio)

        let added = try XCTUnwrap(MacNotePhotos.add(imageData: try pngData(), to: pf, memo: memo, context: ctx))

        XCTAssertEqual(memo.metadata?.imageManifest?.map(\.filename), [added.filename])
        let rows = try ctx.fetch(FetchDescriptor<MemoAsset>())
        XCTAssertEqual(rows.map(\.filename), [added.filename])
        XCTAssertEqual(rows.first?.kind, MemoAsset.Kind.photo)
        XCTAssertTrue(added.filename.hasPrefix("photo_\(memo.id.uuidString)_001"))
        XCTAssertTrue(MacNotePhotos.hasAsset(filename: added.filename, in: ctx))
        XCTAssertFalse(MacNotePhotos.hasAsset(filename: "nope.jpg", in: ctx))
    }

    func testMarkupSavedUpdatesThePhotoRow() throws {
        let container = try ModelContainer(for: Memo.self, MemoAsset.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let memo = Memo(id: UUID(), audioFilename: "m.m4a", transcript: "t")
        ctx.insert(memo)
        let pf = PipelineFile(id: memo.id.uuidString, filename: "m.m4a",
                              path: folder.appendingPathComponent("original.m4a").path, sourceType: .audio)
        let added = try XCTUnwrap(MacNotePhotos.add(imageData: try pngData(), to: pf, memo: memo, context: ctx))

        try Data("MARKED UP".utf8).write(to: added.fileURL)
        XCTAssertTrue(MacNotePhotos.markupSaved(fileURL: added.fileURL, memo: memo, context: ctx))

        let row = try XCTUnwrap(try ctx.fetch(FetchDescriptor<MemoAsset>()).first)
        XCTAssertEqual(row.blob, Data("MARKED UP".utf8))
        XCTAssertEqual(row.byteCount, 9, "the phone's sweep sees a changed size and re-mirrors")
    }

    // MARK: helpers

    private func writeManifest(_ names: [String]) throws {
        let entries = names.map { ["filename": $0, "offsetSeconds": 0.0] as [String: Any] }
        try JSONSerialization.data(withJSONObject: entries).write(to: folder.appendingPathComponent("image_manifest.json"))
    }

    /// A real 8x8 PNG, so `ImageNormalise` accepts it.
    private func pngData() throws -> Data {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try XCTUnwrap(ctx.makeImage())
        let out = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }
}
