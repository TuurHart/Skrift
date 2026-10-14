import XCTest
import SwiftData
@testable import SkriftMobile

/// Q446 (C55, C56, C193, C239): the iPad/phone twin of the Mac's `PicAtStartExportTests`. A
/// note whose body OPENS with a picture (`pic-at-start` in the corpus) keeps its frontmatter
/// through `ObsidianPublisher`; the Q13 fallback ran over the whole compiled markdown, fused
/// the closing `---` onto the first sentence and dropped the stamp.
final class PicAtStartPublisherTests: XCTestCase {
    private var sandbox: URL!
    private var portfolioRoot: URL!
    private var ledger: ExportLedger!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("q446-\(UUID().uuidString)")
        portfolioRoot = sandbox.appendingPathComponent("portfolio")
        try FileManager.default.createDirectory(at: sandbox.appendingPathComponent("vault"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: portfolioRoot, withIntermediateDirectories: true)
        ledger = ExportLedger(fileURL: sandbox.appendingPathComponent("ledger.json"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: sandbox) }

    /// The corpus `pic-at-start` memo, seeded through the phone's own loader.
    @MainActor
    private func corpusMemo() throws -> (Memo, [String: Data]) {
        let root = CorpusSeed.fixtureRoot(file: #filePath)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path),
                          "corpus not generated")
        let repo = NotesRepository(inMemory: true)
        let recordings = sandbox.appendingPathComponent("rec")
        try CorpusSeed.seed(from: root, into: repo.context, recordingsDirectory: recordings)
        let id = try XCTUnwrap(UUID(uuidString: "7E246814-C6AF-50EB-BC38-4851EA4F45BC"))
        let memo = try XCTUnwrap(repo.allMemosIncludingTrashed().first { $0.id == id }, "pic-at-start in the corpus")
        var photos: [String: Data] = [:]
        for a in repo.assets(forMemo: id) where a.kind == MemoAsset.Kind.photo { photos[a.filename] = a.blob }
        XCTAssertFalse(photos.isEmpty, "the corpus note carries its picture")
        return (memo, photos)
    }

    private func publisher(photos: [String: Data]) -> ObsidianPublisher {
        ObsidianPublisher(
            vaultProvider: { self.sandbox.appendingPathComponent("vault") },
            portfolioFolderProvider: { d in
                d.portfolioFolder.map { self.portfolioRoot.appendingPathComponent($0, isDirectory: true) }
            },
            portfolioScopeRoot: { self.portfolioRoot },
            manageScope: false,
            author: "Tiuri", peopleProvider: { [] },
            photosProvider: { _ in photos },
            ledgerOverride: ledger)
    }

    private func written(_ report: PublishReport, under root: URL) throws -> String {
        guard case .written = report.outcome else { XCTFail("expected .written, got \(report.outcome)"); return "" }
        let home = report.relativePath
        let found = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.first { $0.lastPathComponent == (home as NSString).lastPathComponent }
        return try String(contentsOf: try XCTUnwrap(found, "file for \(home)"), encoding: .utf8)
    }

    @MainActor
    func testBodyOpeningWithAPictureKeepsItsFrontmatterOnBothProfiles() throws {
        for (destination, label, root, embed) in [
            (NoteDestination.personal, "vault", sandbox.appendingPathComponent("vault"), "![["),
            (.portfolio, "portfolio", portfolioRoot!, "![](")] {
            let (memo, photos) = try corpusMemo()
            memo.destination = destination
            memo.tags = []
            let report = try publisher(photos: photos).publishReport(memo)
            let md = try written(report, under: root!)

            let lines = md.components(separatedBy: "\n")
            XCTAssertEqual(lines.first, "---", "\(label): opens with a fence")
            XCTAssertTrue(lines.dropFirst().contains("---"), "\(label): closing --- on its own line:\n\(md)")
            let fm = try XCTUnwrap(VaultStamp.frontmatter(md), "\(label): frontmatter parses:\n\(md)")
            XCTAssertNotNil(VaultStamp.value(of: VaultStamp.idKey, in: fm), "\(label): skriftID")
            XCTAssertFalse((VaultStamp.value(of: VaultStamp.hashKey, in: fm) ?? "").isEmpty, "\(label): skriftHash")
            XCTAssertFalse(md.contains("--- "), "\(label): nothing fused onto the fence")
            XCTAssertTrue(md.contains("This is what the blue looks like at cone five"), "\(label): words kept")
            XCTAssertFalse(md.contains("[[img_"), "\(label): no literal marker")
            let parts = md.components(separatedBy: "\n---\n")
            XCTAssertEqual(parts.count, 2, "\(label): exactly one closing fence")
            XCTAssertTrue(parts.last?.trimmingCharacters(in: .newlines).hasPrefix(embed) == true,
                          "\(label): the body opens with the picture:\n\(md)")
            try? FileManager.default.removeItem(at: root!)
            try FileManager.default.createDirectory(at: root!, withIntermediateDirectories: true)
            ledger = ExportLedger(fileURL: sandbox.appendingPathComponent("ledger-\(label).json"))
        }
    }

    @MainActor
    func testPublishingTwiceWritesNothingTheSecondTime() throws {
        // C55: the stamp survives, so the second publish is recognised as ours and unchanged.
        let (memo, photos) = try corpusMemo()
        let p = publisher(photos: photos)
        guard case .written = try p.publish(memo) else { return XCTFail("first publish should write") }
        XCTAssertEqual(try p.publish(memo), .skippedUnchanged)
    }
}
