import XCTest

/// Q246: the id8 name is itself occupied by different bytes.
final class VaultEmbedNameCollisionTests: XCTestCase {
    private var root: URL!
    private var writer: VaultWriter!
    private let id = UUID(uuidString: "7C3F2A1B-0000-4000-8000-0000000000AA")!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("q246-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        writer = VaultWriter(root: root,
                             ledger: ExportLedger(fileURL: root.appendingPathComponent(".ledger.json")))
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root); super.tearDown() }

    func testEmbedFollowsTheNameWrittenWhenId8NameIsAlsoTaken() throws {
        let imagesDir = root.appendingPathComponent("Images", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        let foreignA = Data("foreign A".utf8), foreignB = Data("foreign B".utf8)
        try foreignA.write(to: imagesDir.appendingPathComponent("IMG_0001.jpg"))
        try foreignB.write(to: imagesDir.appendingPathComponent("IMG_0001 7C3F2A1B.jpg"))

        guard case .proceed(let rel, _) = writer.assess(id: id, title: "A note", filenameFallback: "memo.m4a") else {
            return XCTFail("expected to proceed")
        }
        let ours = Data("our own photo bytes".utf8)
        let md = "---\ntitle: \"A note\"\nlastTouched:\nauthor: Tuur\ntags:\n  - work\n---\n\n![[IMG_0001.jpg]]\n"
        let result = try writer.commit(markdown: md, id: id, relativePath: rel,
                                       attachments: [VaultAsset(name: "IMG_0001.jpg", source: .data(ours))])
        XCTAssertEqual(try Data(contentsOf: imagesDir.appendingPathComponent("IMG_0001.jpg")), foreignA)
        XCTAssertEqual(try Data(contentsOf: imagesDir.appendingPathComponent("IMG_0001 7C3F2A1B.jpg")), foreignB)
        let noteText = try XCTUnwrap(VaultWriter.readCoordinated(result.markdownURL))
        // The embed's target must exist and hold OUR bytes.
        let line = try XCTUnwrap(noteText.split(separator: "\n").first { $0.hasPrefix("![[") })
        let name = String(line.dropFirst(3).dropLast(2))
        XCTAssertEqual(try? Data(contentsOf: imagesDir.appendingPathComponent(name)), ours,
                       "embed points at \(name)")
    }
}
