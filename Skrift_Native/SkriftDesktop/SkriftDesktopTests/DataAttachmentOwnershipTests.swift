import XCTest

/// C58 / Q32: `VaultWrite.writeAsset`'s `.data` branch (the phone's `MemoAsset` blobs —
/// photos + audio, no source file on disk to hand `copyOwned`) obeys the same ownership
/// rule as the `.file` branch (R7/R77): byte-identical to what's already there → safe
/// no-op, a foreign file at the target name is never touched, and ours lands under the
/// id8-disambiguated name instead. All temp dirs — never the real vault.
final class DataAttachmentOwnershipTests: XCTestCase {

    private var root: URL!
    private let id = UUID(uuidString: "7C3F2A1B-0000-4000-8000-000000000001")!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("data-attach-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    // MARK: - VaultAttachmentOwnership.writeOwned (the shared primitive, Data flavor)

    func testWriteOwnedCreatesWhenNothingThere() throws {
        let dir = root.appendingPathComponent("dest", isDirectory: true)
        let written = VaultAttachmentOwnership.writeOwned(Data([1, 2, 3]), preferredName: "photo.jpg",
                                                          into: dir, id: id)
        XCTAssertEqual(written?.lastPathComponent, "photo.jpg")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(written)), Data([1, 2, 3]))
    }

    /// Re-exporting the SAME bytes over what we already wrote is a safe no-op.
    func testWriteOwnedNoOpsWhenByteIdentical() throws {
        let dir = root.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("photo.jpg")
        try Data([1, 2, 3]).write(to: dest)
        let modBefore = try FileManager.default.attributesOfItem(atPath: dest.path)[.modificationDate] as? Date

        let written = VaultAttachmentOwnership.writeOwned(Data([1, 2, 3]), preferredName: "photo.jpg",
                                                          into: dir, id: id)

        XCTAssertEqual(written, dest)
        let modAfter = try FileManager.default.attributesOfItem(atPath: dest.path)[.modificationDate] as? Date
        XCTAssertEqual(modBefore, modAfter, "byte-identical content must not be rewritten")
    }

    /// The heart of R7/R77 for in-memory bytes: a DIFFERENT file already occupies the
    /// preferred name. It is never removed; ours is written under a disambiguated name.
    func testWriteOwnedNeverDeletesAForeignFile() throws {
        let dir = root.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("photo.jpg")
        let foreignBytes = Data([9, 9, 9, 9])
        try foreignBytes.write(to: dest)

        let ourBytes = Data([1, 2, 3])
        let written = VaultAttachmentOwnership.writeOwned(ourBytes, preferredName: "photo.jpg",
                                                          into: dir, id: id)

        XCTAssertEqual(try Data(contentsOf: dest), foreignBytes,
                       "a file this device doesn't own must never be removed")
        let writtenURL = try XCTUnwrap(written)
        XCTAssertNotEqual(writtenURL, dest)
        XCTAssertTrue(writtenURL.lastPathComponent.contains(String(id.uuidString.prefix(8))),
                      "disambiguated name should carry the note's id8")
        XCTAssertEqual(try Data(contentsOf: writtenURL), ourBytes)
    }

    // MARK: - VaultWrite.writeAsset .data branch, via VaultWriter.commit (the real path)

    func testCommitDataAttachmentNeverDeletesAForeignVaultFile() throws {
        let vaultRoot = root.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
        let writer = VaultWriter(root: vaultRoot,
                                 ledger: ExportLedger(fileURL: vaultRoot.appendingPathComponent(".ledger.json")))

        // First write: creates the note + its photo blob attachment "photo.jpg".
        guard case .proceed(let rel, _) = writer.assess(id: id, title: "A note", filenameFallback: "memo.m4a") else {
            return XCTFail("expected a fresh note to proceed")
        }
        let md = "---\ntitle: \"A note\"\nlastTouched:\n---\n\nBody.\n"
        _ = try writer.commit(markdown: md, id: id, relativePath: rel,
                              attachments: [VaultAsset(name: "photo.jpg", source: .data(Data([1, 2, 3])))])
        let attPath = vaultRoot.appendingPathComponent(VaultLayout.images).appendingPathComponent("photo.jpg")
        XCTAssertEqual(try Data(contentsOf: attPath), Data([1, 2, 3]))

        // Now something ELSE occupies that same attachment name in the vault (a file
        // this device never wrote there).
        let foreignBytes = Data([255, 255, 255])
        try foreignBytes.write(to: attPath)

        // A later commit with a different photo blob under the same name must not
        // delete the foreign file.
        let r = try writer.commit(markdown: md + " ", id: id, relativePath: rel,
                                  attachments: [VaultAsset(name: "photo.jpg", source: .data(Data([4, 5, 6])))])

        XCTAssertEqual(try Data(contentsOf: attPath), foreignBytes,
                       "the writeAsset .data branch must never remove a file it doesn't own")
        XCTAssertEqual(r.attachmentsWritten, 1, "our blob still lands, just under a disambiguated name")
        // Ours landed under the id8-disambiguated name, byte-correct, foreign file intact.
        let siblings = try FileManager.default.contentsOfDirectory(atPath: vaultRoot.appendingPathComponent(VaultLayout.images).path)
        let ours = try XCTUnwrap(siblings.first { $0 != "photo.jpg" })
        XCTAssertTrue(ours.contains(String(id.uuidString.prefix(8))))
        XCTAssertEqual(try Data(contentsOf: vaultRoot.appendingPathComponent(VaultLayout.images).appendingPathComponent(ours)),
                       Data([4, 5, 6]))
    }

    /// Re-committing the SAME photo blob bytes is a no-op — no needless rewrite of an
    /// attachment we already own untouched.
    func testCommitDataAttachmentNoOpsWhenByteIdentical() throws {
        let vaultRoot = root.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
        let writer = VaultWriter(root: vaultRoot,
                                 ledger: ExportLedger(fileURL: vaultRoot.appendingPathComponent(".ledger.json")))
        guard case .proceed(let rel, _) = writer.assess(id: id, title: "A note", filenameFallback: "memo.m4a") else {
            return XCTFail("expected a fresh note to proceed")
        }
        let md = "---\ntitle: \"A note\"\nlastTouched:\n---\n\nBody.\n"
        _ = try writer.commit(markdown: md, id: id, relativePath: rel,
                              attachments: [VaultAsset(name: "audio.m4a", source: .data(Data([7, 7])))])
        let attPath = vaultRoot.appendingPathComponent(VaultLayout.images).appendingPathComponent("audio.m4a")
        let modBefore = try FileManager.default.attributesOfItem(atPath: attPath.path)[.modificationDate] as? Date

        let r = try writer.commit(markdown: md + " ", id: id, relativePath: rel,
                                  attachments: [VaultAsset(name: "audio.m4a", source: .data(Data([7, 7])))])

        XCTAssertEqual(r.attachmentsWritten, 1)
        let modAfter = try FileManager.default.attributesOfItem(atPath: attPath.path)[.modificationDate] as? Date
        XCTAssertEqual(modBefore, modAfter, "byte-identical re-export must not rewrite the file")
    }
}
