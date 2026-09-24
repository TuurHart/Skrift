import XCTest

/// Q34: a foreign file already owning our attachment's preferred name means the write
/// lands under the id8-disambiguated name (`VaultAttachmentOwnership`, C58) — the note's
/// markdown embed must follow that same name, not the one it was compiled against
/// (C54/C56). Everything here runs against a temp directory standing in for the vault.
final class AttachmentEmbedNameTests: XCTestCase {

    private var root: URL!
    private var writer: VaultWriter!
    private let id = UUID(uuidString: "7C3F2A1B-0000-4000-8000-0000000000AA")!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("embed-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        writer = VaultWriter(root: root,
                             ledger: ExportLedger(fileURL: root.appendingPathComponent(".ledger.json")))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func md(embedding name: String) -> String {
        "---\ntitle: \"A note\"\nlastTouched:\nauthor: Tuur\ntags:\n  - work\n---\n\nSee the photo.\n\n![[\(name)]]\n"
    }

    private var disambiguated: String { "IMG_0001 \(id.uuidString.prefix(8)).jpg" }

    /// `.data` source (the phone's lane): a foreign `IMG_0001.jpg` already sits in
    /// `Images/` when our photo is written under the SAME preferred name.
    func testDataAttachmentCollisionRenamesTheEmbedToo() throws {
        let imagesDir = root.appendingPathComponent("Images", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        let foreign = Data("a foreign photo, not ours".utf8)
        try foreign.write(to: imagesDir.appendingPathComponent("IMG_0001.jpg"))

        guard case .proceed(let rel, _) = writer.assess(id: id, title: "A note", filenameFallback: "memo.m4a") else {
            return XCTFail("expected to proceed")
        }
        let ours = Data("our own photo bytes".utf8)
        let markdown = md(embedding: "IMG_0001.jpg")
        let result = try writer.commit(markdown: markdown, id: id, relativePath: rel,
                                       attachments: [VaultAsset(name: "IMG_0001.jpg", source: .data(ours))])

        // The foreign file was never touched.
        XCTAssertEqual(try Data(contentsOf: imagesDir.appendingPathComponent("IMG_0001.jpg")), foreign)
        // Our photo landed under the disambiguated name, holding OUR bytes.
        let writtenURL = imagesDir.appendingPathComponent(disambiguated)
        XCTAssertEqual(try? Data(contentsOf: writtenURL), ours)
        // The note's embed points at the name actually written, not the original.
        let noteText = try XCTUnwrap(VaultWriter.readCoordinated(result.markdownURL))
        XCTAssertTrue(noteText.contains("![[\(disambiguated)]]"),
                     "embed must use the written name; got:\n\(noteText)")
        XCTAssertFalse(noteText.contains("![[IMG_0001.jpg]]"),
                       "embed must NOT still point at the foreign-owned original name")
    }

    /// `.file` source (the Mac's lane): same collision, sourced from a file on disk
    /// rather than in-memory bytes.
    func testFileAttachmentCollisionRenamesTheEmbedToo() throws {
        let imagesDir = root.appendingPathComponent("Images", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        let foreign = Data("a foreign photo, not ours".utf8)
        try foreign.write(to: imagesDir.appendingPathComponent("IMG_0001.jpg"))

        let srcDir = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        let srcFile = srcDir.appendingPathComponent("original.jpg")
        try Data("our own photo bytes on disk".utf8).write(to: srcFile)

        guard case .proceed(let rel, _) = writer.assess(id: id, title: "A note", filenameFallback: "memo.m4a") else {
            return XCTFail("expected to proceed")
        }
        let markdown = md(embedding: "IMG_0001.jpg")
        let result = try writer.commit(markdown: markdown, id: id, relativePath: rel,
                                       attachments: [VaultAsset(name: "IMG_0001.jpg", source: .file(srcFile))])

        XCTAssertEqual(try Data(contentsOf: imagesDir.appendingPathComponent("IMG_0001.jpg")), foreign)
        let writtenURL = imagesDir.appendingPathComponent(disambiguated)
        XCTAssertEqual(try? Data(contentsOf: writtenURL), try Data(contentsOf: srcFile))
        let noteText = try XCTUnwrap(VaultWriter.readCoordinated(result.markdownURL))
        XCTAssertTrue(noteText.contains("![[\(disambiguated)]]"),
                     "embed must use the written name; got:\n\(noteText)")
        XCTAssertFalse(noteText.contains("![[IMG_0001.jpg]]"))
    }

    /// No collision at all: the preferred name is free, so nothing needs to move — the
    /// embed the caller compiled stands unchanged.
    func testNoCollisionLeavesTheEmbedAlone() throws {
        guard case .proceed(let rel, _) = writer.assess(id: id, title: "Another note", filenameFallback: "memo.m4a") else {
            return XCTFail("expected to proceed")
        }
        let markdown = md(embedding: "IMG_0002.jpg")
        let ours = Data("our own photo bytes".utf8)
        let result = try writer.commit(markdown: markdown, id: id, relativePath: rel,
                                       attachments: [VaultAsset(name: "IMG_0002.jpg", source: .data(ours))])
        let noteText = try XCTUnwrap(VaultWriter.readCoordinated(result.markdownURL))
        XCTAssertTrue(noteText.contains("![[IMG_0002.jpg]]"))
        let imagesDir = root.appendingPathComponent("Images", isDirectory: true)
        XCTAssertEqual(try? Data(contentsOf: imagesDir.appendingPathComponent("IMG_0002.jpg")), ours)
    }
}
