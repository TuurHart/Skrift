import XCTest
@testable import SkriftMobile

/// Q467 (C57, C58, C61, C239): the iPad/phone `ObsidianPublisher` converts `[[vid_NNN]]` and
/// `[[file_NNN]]` markers through the same shared step as the Mac (`ExportV2.compile`), copying the
/// file beside the note under the ownership rule. It used to print the markers as raw text.
final class PublisherAttachmentMarkerTests: XCTestCase {
    private var sandbox: URL!
    private var picked: URL!
    private var ledger: ExportLedger!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("q467-\(UUID().uuidString)")
        picked = sandbox.appendingPathComponent("vault")
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        ledger = ExportLedger(fileURL: sandbox.appendingPathComponent("ledger.json"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: sandbox) }

    private let fileBytes = Data("spreadsheet bytes".utf8)
    private let videoBytes = Data("movie bytes".utf8)

    /// A note holding one file and one video, in manifest order (file = 1, video = 2).
    private func memo() -> (Memo, [String: Data]) {
        let memo = Memo(title: "Attached", transcript: "Intro line.")
        let file = NoteAttachment.makeEntry(owner: memo.id, number: 1, originalName: "quote.xlsx", byteCount: fileBytes.count)
        let video = NoteAttachment.makeEntry(owner: memo.id, number: 2, originalName: "clip.mov", byteCount: videoBytes.count)
        var meta = memo.metadata ?? MemoMetadata()
        meta.attachmentManifest = [file, video]
        memo.metadata = meta
        memo.transcript = "Intro line.\n\n[[file_001]]\n\nMiddle line.\n\n[[vid_002]]\n\nClosing line."
        return (memo, [file.filename: fileBytes, video.filename: videoBytes])
    }

    private func publisher(blobs: [String: Data]) -> ObsidianPublisher {
        ObsidianPublisher(vaultProvider: { self.picked }, manageScope: false,
                          author: "Tiuri", peopleProvider: { [] },
                          attachmentProvider: { _, entry in blobs[entry.filename].map { .data($0) } },
                          ledgerOverride: ledger)
    }

    private func files(under root: URL) -> [URL] {
        (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? [])
            .filter { !$0.hasDirectoryPath }
    }

    func testFileAndVideoMarkersBecomeEmbedsAndTheFilesAreCopied() throws {
        let (memo, blobs) = memo()
        let report = try publisher(blobs: blobs).publishReport(memo)
        guard case .written = report.outcome else { return XCTFail("expected .written, got \(report.outcome)") }

        let all = files(under: picked)
        let note = try XCTUnwrap(all.first { $0.pathExtension == "md" }, "the note")
        let md = try String(contentsOf: note, encoding: .utf8)
        XCTAssertFalse(md.contains("[[file_"), "no raw file marker:\n\(md)")
        XCTAssertFalse(md.contains("[[vid_"), "no raw video marker:\n\(md)")

        let stem = (note.lastPathComponent as NSString).deletingPathExtension
        XCTAssertTrue(md.contains("![[\(stem) - quote.xlsx]]"), "file embed:\n\(md)")
        XCTAssertTrue(md.contains("![[\(stem)_video_002.mov]]"), "video embed:\n\(md)")

        let copiedFile = try XCTUnwrap(all.first { $0.lastPathComponent == "\(stem) - quote.xlsx" }, "file copied beside the note")
        let copiedVideo = try XCTUnwrap(all.first { $0.lastPathComponent == "\(stem)_video_002.mov" }, "video copied beside the note")
        XCTAssertEqual(try Data(contentsOf: copiedFile), fileBytes)
        XCTAssertEqual(try Data(contentsOf: copiedVideo), videoBytes)
        XCTAssertEqual(report.assetCount, 2)
    }

    func testAMarkerWithNoManifestEntryIsDroppedNotPrinted() throws {
        let memo = Memo(title: "Dangling", transcript: "Intro line.\n\n[[file_003]]\n\nClosing line.")
        _ = try publisher(blobs: [:]).publish(memo)
        let note = try XCTUnwrap(files(under: picked).first { $0.pathExtension == "md" })
        let md = try String(contentsOf: note, encoding: .utf8)
        XCTAssertFalse(md.contains("[[file_"), md)
    }

    /// C63 / D210: the note's own kept movie never reaches the vault; its marker drops.
    func testTheKeptMovieMarkerIsDroppedAndItsFileNotCopied() throws {
        let memo = Memo(title: "Kept", transcript: "")
        let kept = NoteAttachmentEntry(kind: NoteAttachment.Kind.video, filename: "video_\(memo.id.uuidString).mov",
                                       name: "clip.mov", uti: "com.apple.quicktime-movie", byteCount: 3)
        var meta = memo.metadata ?? MemoMetadata()
        meta.attachmentManifest = [kept]
        memo.metadata = meta
        memo.transcript = "[[vid_001]]\n\nSaid something."
        _ = try publisher(blobs: [kept.filename: Data("mov".utf8)]).publish(memo)
        let all = files(under: picked)
        let md = try String(contentsOf: XCTUnwrap(all.first { $0.pathExtension == "md" }), encoding: .utf8)
        XCTAssertFalse(md.contains("[[vid_"), md)
        XCTAssertFalse(md.contains("_video_"), "no embed of the kept movie:\n\(md)")
        XCTAssertFalse(all.contains { $0.pathExtension == "mov" }, "the movie is not copied into the vault")
    }

    /// C58: a foreign file already at the target name is left alone; ours lands under a suffix.
    func testAForeignFileAtTheTargetNameIsNeverClobbered() throws {
        let (memo, blobs) = memo()
        let first = try publisher(blobs: blobs).publishReport(memo)
        guard case .written = first.outcome else { return XCTFail("setup write") }
        let note = try XCTUnwrap(files(under: picked).first { $0.pathExtension == "md" })
        let stem = (note.lastPathComponent as NSString).deletingPathExtension
        let copied = try XCTUnwrap(files(under: picked).first { $0.lastPathComponent == "\(stem) - quote.xlsx" })

        // Someone replaces that file with their own, then the note changes and re-exports.
        let theirs = Data("theirs".utf8)
        try theirs.write(to: copied)
        memo.transcript = (memo.transcript ?? "") + "\n\nOne more line."
        _ = try publisher(blobs: blobs).publish(memo)

        XCTAssertEqual(try Data(contentsOf: copied), theirs, "the foreign bytes survive")
        let md = try String(contentsOf: note, encoding: .utf8)
        XCTAssertFalse(md.contains("[[file_"), md)
    }
}
