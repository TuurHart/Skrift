import XCTest

/// C58 / R7 / R77: no attachment lane may remove a vault file it doesn't own. Every
/// lane that copies a binary asset into the vault — the Mac `VaultExporter`'s three
/// image/attachment copiers and the shared `VaultWrite.writeAsset` `.file` branch —
/// routes through `VaultAttachmentOwnership`, which never `removeItem`s an existing
/// file: a foreign occupant is left alone and ours lands under a disambiguated name.
final class AttachmentOwnershipTests: XCTestCase {

    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("attach-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private let id = UUID(uuidString: "7C3F2A1B-0000-4000-8000-000000000001")!

    // MARK: - VaultAttachmentOwnership (the shared primitive)

    func testCopyOwnedCreatesWhenNothingThere() throws {
        let src = root.appendingPathComponent("src.jpg")
        try Data([1, 2, 3]).write(to: src)
        let dir = root.appendingPathComponent("dest", isDirectory: true)

        let written = VaultAttachmentOwnership.copyOwned(from: src, preferredName: "photo.jpg", into: dir, id: id)

        XCTAssertEqual(written?.lastPathComponent, "photo.jpg")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(written)), Data([1, 2, 3]))
    }

    /// Re-exporting the SAME bytes over what we already wrote is a safe no-op — no
    /// delete, no rewrite, matching the markdown lane's `unchanged` outcome.
    func testCopyOwnedNoOpsWhenByteIdentical() throws {
        let dir = root.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("photo.jpg")
        try Data([1, 2, 3]).write(to: dest)
        let modBefore = try FileManager.default.attributesOfItem(atPath: dest.path)[.modificationDate] as? Date

        let src = root.appendingPathComponent("src.jpg")
        try Data([1, 2, 3]).write(to: src)

        let written = VaultAttachmentOwnership.copyOwned(from: src, preferredName: "photo.jpg", into: dir, id: id)

        XCTAssertEqual(written, dest)
        let modAfter = try FileManager.default.attributesOfItem(atPath: dest.path)[.modificationDate] as? Date
        XCTAssertEqual(modBefore, modAfter, "byte-identical content must not be rewritten")
    }

    /// The heart of R7/R77: a DIFFERENT file already occupies the preferred name. It is
    /// never removed; ours is written under a disambiguated name instead.
    func testCopyOwnedNeverDeletesAForeignFile() throws {
        let dir = root.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("photo.jpg")
        let foreignBytes = Data([9, 9, 9, 9])
        try foreignBytes.write(to: dest)

        let src = root.appendingPathComponent("src.jpg")
        let ourBytes = Data([1, 2, 3])
        try ourBytes.write(to: src)

        let written = VaultAttachmentOwnership.copyOwned(from: src, preferredName: "photo.jpg", into: dir, id: id)

        // The foreign file at the original name is completely untouched.
        XCTAssertEqual(try Data(contentsOf: dest), foreignBytes, "a file this device doesn't own must never be removed")
        // Ours landed under a disambiguated name instead.
        let writtenURL = try XCTUnwrap(written)
        XCTAssertNotEqual(writtenURL, dest)
        XCTAssertTrue(writtenURL.lastPathComponent.contains(id.uuidString.prefix(8).lowercased())
                      || writtenURL.lastPathComponent.contains(String(id.uuidString.prefix(8))),
                      "disambiguated name should carry the note's id8")
        XCTAssertEqual(try Data(contentsOf: writtenURL), ourBytes)
    }

    // MARK: - VaultWrite.writeAsset .file branch (R77)

    func testCommitAttachmentNeverDeletesAForeignVaultFile() throws {
        let vaultRoot = root.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
        let writer = VaultWriter(root: vaultRoot,
                                 ledger: ExportLedger(fileURL: vaultRoot.appendingPathComponent(".ledger.json")))

        // First write: creates the note + its attachment "photo.jpg".
        let src1 = root.appendingPathComponent("src1.jpg")
        try Data([1, 2, 3]).write(to: src1)
        guard case .proceed(let rel, _) = writer.assess(id: id, title: "A note", filenameFallback: "memo.m4a") else {
            return XCTFail("expected a fresh note to proceed")
        }
        let md = "---\ntitle: \"A note\"\nlastTouched:\n---\n\nBody.\n"
        _ = try writer.commit(markdown: md, id: id, relativePath: rel,
                              attachments: [VaultAsset(name: "photo.jpg", source: .file(src1))])
        let attPath = vaultRoot.appendingPathComponent("photo.jpg")
        XCTAssertEqual(try Data(contentsOf: attPath), Data([1, 2, 3]))

        // Now something ELSE occupies that same attachment name in the vault (a file
        // this device never wrote there — could be the user's own picture).
        let foreignBytes = Data([255, 255, 255])
        try foreignBytes.write(to: attPath)

        // A later commit under a DIFFERENT asset with the same name must not delete it.
        let src2 = root.appendingPathComponent("src2.jpg")
        try Data([4, 5, 6]).write(to: src2)
        _ = try writer.commit(markdown: md + " ", id: id, relativePath: rel,
                              attachments: [VaultAsset(name: "photo.jpg", source: .file(src2))])

        XCTAssertEqual(try Data(contentsOf: attPath), foreignBytes,
                       "the writeAsset .file branch must never remove a file it doesn't own")
    }

    // MARK: - VaultExporter attachment lanes (R7)

    /// `convertImageMarkers` — a foreign file already sits at the name the exporter
    /// would use for the note's own image; it is left alone, ours is written under a
    /// disambiguated name, and the embed in the exported markdown is rewritten to match.
    func testConvertImageMarkersNeverDeletesAForeignFile() throws {
        let work = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let noteFolder = work.appendingPathComponent("note")
        let imagesDir = noteFolder.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        let audio = noteFolder.appendingPathComponent("original.m4a")
        try Data([1, 2, 3]).write(to: audio)
        try Data([9, 9]).write(to: imagesDir.appendingPathComponent("img_001.jpg"))
        let vault = work.appendingPathComponent("vault")

        let pf = PipelineFile(id: "1", filename: "memo.m4a", path: audio.path, size: 3, sourceType: .audio)
        pf.enhancedTitle = "Trip"
        pf.sanitised = "Look: [[img_001]]"

        // Pre-occupy the destination the exporter will pick — `Trip_001.jpg` — with a
        // FOREIGN file this device never wrote.
        let attDir = vault.appendingPathComponent("Skrift/Images", isDirectory: true)
        try FileManager.default.createDirectory(at: attDir, withIntermediateDirectories: true)
        let foreignPath = attDir.appendingPathComponent("Trip_001.jpg")
        let foreignBytes = Data([250, 250, 250])
        try foreignBytes.write(to: foreignPath)

        var settings = AppSettings.default
        settings.noteFolder = vault.path
        let r = try VaultExporter.export(pf, settings: settings)

        // The foreign file is untouched.
        XCTAssertEqual(try Data(contentsOf: foreignPath), foreignBytes,
                       "convertImageMarkers must never remove a file it doesn't own")
        // The note's image landed under a disambiguated name, and the embed matches it.
        let md = try String(contentsOf: r.markdownURL, encoding: .utf8)
        XCTAssertFalse(md.contains("![[Trip_001.jpg]]"), "must not claim the foreign file as its own embed")
        XCTAssertTrue(md.contains(".jpg]]"), "should still embed SOME image reference")
        XCTAssertEqual(r.imageCount, 1)
    }
}
