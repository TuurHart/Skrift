import XCTest
@testable import SkriftMobile

/// Q468 (C63, D210): the iPad/phone publisher puts a video note's poster frame in the vault in
/// place of the kept movie (which never goes there), through the same shared conversion as the Mac.
final class PublisherVideoFrameTests: XCTestCase {
    private var sandbox: URL!
    private var picked: URL!
    private var ledger: ExportLedger!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("q468-\(UUID().uuidString)")
        picked = sandbox.appendingPathComponent("vault")
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        ledger = ExportLedger(fileURL: sandbox.appendingPathComponent("ledger.json"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: sandbox) }

    private func videoMemo() -> Memo {
        let memo = Memo(title: "Kiln", transcript: "")
        let kept = NoteAttachment.keptMovieEntry(filename: VideoKeep.filename(memoID: memo.id, sourceExtension: "mov"),
                                                 originalName: "Video", byteCount: 3, durationSeconds: 6)
        var meta = memo.metadata ?? MemoMetadata()
        meta.attachmentManifest = [kept]
        memo.metadata = meta
        memo.transcript = "[[vid_001]]\n\nSaid something."
        return memo
    }

    private func publisher(poster: Data?) -> ObsidianPublisher {
        var p = ObsidianPublisher(vaultProvider: { self.picked }, manageScope: false,
                                  author: "Tiuri", peopleProvider: { [] }, ledgerOverride: ledger)
        p.posterProvider = { _ in poster }
        return p
    }

    private func files() -> [URL] {
        (FileManager.default.enumerator(at: picked, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? [])
            .filter { !$0.hasDirectoryPath }
    }

    func testTheKeptMoviesMarkerBecomesItsFrameEmbedAndTheFrameIsWritten() throws {
        let frame = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])
        _ = try publisher(poster: frame).publish(videoMemo())
        let all = files()
        let note = try XCTUnwrap(all.first { $0.pathExtension == "md" })
        let stem = (note.lastPathComponent as NSString).deletingPathExtension
        let md = try String(contentsOf: note, encoding: .utf8)
        XCTAssertTrue(md.contains("![[\(stem)_frame.jpg]]"), md)
        XCTAssertFalse(md.contains("[[vid_"), md)
        let written = try XCTUnwrap(all.first { $0.lastPathComponent == "\(stem)_frame.jpg" }, "the frame lands beside the note")
        XCTAssertEqual(try Data(contentsOf: written), frame)
        XCTAssertFalse(all.contains { $0.pathExtension == "mov" }, "the movie is never copied into the vault")
    }

    func testNoMovieOnThisDeviceDropsTheMarkerInsteadOfDangling() throws {
        // No posterProvider and no movie file: nothing to take a frame from.
        var p = ObsidianPublisher(vaultProvider: { self.picked }, manageScope: false,
                                  author: "Tiuri", peopleProvider: { [] }, ledgerOverride: ledger)
        p.movieProvider = { _ in nil }
        _ = try p.publish(videoMemo())
        let note = try XCTUnwrap(files().first { $0.pathExtension == "md" })
        let md = try String(contentsOf: note, encoding: .utf8)
        XCTAssertFalse(md.contains("_frame.jpg"), md)
        XCTAssertFalse(md.contains("[[vid_"), md)
    }
}
