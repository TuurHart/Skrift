import XCTest
@testable import SkriftMobile

/// ObsidianPublisher (standalone Phase 2) — one-way create-only publish into <vault>/Skrift/,
/// with sticky paths + content-hash idempotency. Tests run against a temp directory (no real
/// vault / security scope).
final class ObsidianPublisherTests: XCTestCase {
    private var sandbox: URL!
    private var vaultRoot: URL!
    private var store: ExportStateStore!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("skrift-pub-\(UUID().uuidString)")
        vaultRoot = sandbox.appendingPathComponent("vault")
        try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
        store = ExportStateStore(fileURL: sandbox.appendingPathComponent("export_state.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    private func publisher(people: [Person] = []) -> ObsidianPublisher {
        ObsidianPublisher(vaultProvider: { self.vaultRoot }, manageScope: false,
                          stateStore: store, author: "Tiuri", peopleProvider: { people })
    }

    func testWritesUnderSkriftSubfolder() throws {
        let memo = Memo(title: "My Idea", transcript: "Body text.")
        guard case let .written(rel) = try publisher().publish(memo) else {
            return XCTFail("expected .written")
        }
        XCTAssertTrue(rel.hasPrefix("Skrift/Voice Memos/"), "must write under Skrift/ — got \(rel)")
        XCTAssertTrue(rel.hasSuffix(".md"))
        let written = vaultRoot.appendingPathComponent(rel)
        XCTAssertTrue(FileManager.default.fileExists(atPath: written.path))
        XCTAssertTrue(try String(contentsOf: written, encoding: .utf8).contains("title: \"My Idea\""))
    }

    func testIdempotentSkipWhenUnchanged() throws {
        let memo = Memo(title: "Note", transcript: "Body.")
        _ = try publisher().publish(memo)
        XCTAssertEqual(try publisher().publish(memo), .skippedUnchanged)
    }

    func testRenameKeepsSamePathAndOverwrites() throws {
        let memo = Memo(title: "Original", transcript: "Body.")
        guard case let .written(first) = try publisher().publish(memo) else { return XCTFail() }
        memo.title = "Renamed Title"
        guard case let .written(second) = try publisher().publish(memo) else {
            return XCTFail("a content change must re-write")
        }
        XCTAssertEqual(first, second, "rename must keep the original file path (single owner per file)")
        XCTAssertTrue(try String(contentsOf: vaultRoot.appendingPathComponent(second), encoding: .utf8)
            .contains("title: \"Renamed Title\""))
    }

    func testNoVault() throws {
        let p = ObsidianPublisher(vaultProvider: { nil }, manageScope: false, stateStore: store,
                                  author: "T", peopleProvider: { [] })
        XCTAssertEqual(try p.publish(Memo(transcript: "x")), .noVault)
    }

    func testRewriteWhenFileDeletedExternally() throws {
        let memo = Memo(title: "Note", transcript: "Body.")
        guard case let .written(rel) = try publisher().publish(memo) else { return XCTFail() }
        try FileManager.default.removeItem(at: vaultRoot.appendingPathComponent(rel))
        // Same content hash, but our file is gone → must rewrite, not skip.
        XCTAssertEqual(try publisher().publish(memo), .written(relativePath: rel))
    }

    func testSubfolderBySource() {
        XCTAssertEqual(ObsidianPublisher.subfolder(for: Memo(transcript: "x")), "Voice Memos")
        XCTAssertEqual(ObsidianPublisher.subfolder(for: Memo(transcript: "x",
            metadata: MemoMetadata(tags: [], bookTitle: "Dune"))), "Audiobook Quotes")
        XCTAssertEqual(ObsidianPublisher.subfolder(for: Memo(
            sharedContent: SharedContent(type: .url, url: "https://e.com"))), "Captures")
    }

    func testSanitizeFilename() {
        XCTAssertEqual(ObsidianPublisher.sanitizeFilename("a/b:c*?"), "a b c")
        XCTAssertEqual(ObsidianPublisher.sanitizeFilename("   "), "Untitled")
    }
}
