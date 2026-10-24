import XCTest
import SwiftData
@testable import SkriftMobile

/// Q519 (C196, C57): with export v2 routed, the phone's vault publish drops the embed of a picture
/// this device does not hold, as the Mac and the Export all zip do (corpus `pic-missing-file`:
/// a manifest entry whose photo never synced). The words stay; no file is written for it.
final class PhoneMissingPictureTests: XCTestCase {
    private var sandbox: URL!
    private var ledger: ExportLedger!
    /// Kept alive: a SwiftData model traps once its context is gone.
    private var repo: NotesRepository!
    private let missingID = UUID(uuidString: "177D06AE-6E17-55D4-A5E4-571A82F8AC69")!

    override func setUpWithError() throws {
        ExportV2.routingOverride = true
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("q519-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox.appendingPathComponent("vault"), withIntermediateDirectories: true)
        ledger = ExportLedger(fileURL: sandbox.appendingPathComponent("ledger.json"))
    }

    override func tearDownWithError() throws {
        ExportV2.routingOverride = nil
        try? FileManager.default.removeItem(at: sandbox)
    }

    private var vault: URL { sandbox.appendingPathComponent("vault") }

    @MainActor
    private func corpusMemo() throws -> Memo {
        let root = CorpusSeed.fixtureRoot(file: #filePath)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path),
                          "corpus not generated")
        repo = NotesRepository(inMemory: true)
        try CorpusSeed.seed(from: root, into: repo.context, recordingsDirectory: sandbox.appendingPathComponent("rec"))
        let memo = try XCTUnwrap(repo.allMemosIncludingTrashed().first { $0.id == missingID }, "pic-missing-file")
        memo.destination = .personal
        return memo
    }

    private func publisher(photos: [String: Data], names: ((UUID) -> Set<String>)? = nil) -> ObsidianPublisher {
        ObsidianPublisher(vaultProvider: { self.vault }, manageScope: false, author: "Tiuri",
                          peopleProvider: { [] }, photoNamesProvider: names,
                          photosProvider: { _ in photos }, ledgerOverride: ledger)
    }

    private func written(_ report: PublishReport) throws -> String {
        guard case .written = report.outcome else { XCTFail("expected .written, got \(report.outcome)"); return "" }
        let name = (report.relativePath as NSString).lastPathComponent
        let found = FileManager.default.enumerator(at: vault, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.first { $0.lastPathComponent == name }
        return try String(contentsOf: try XCTUnwrap(found, "file for \(report.relativePath)"), encoding: .utf8)
    }

    private func images() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: vault.appendingPathComponent("Skrift/Images").path)) ?? []
    }

    @MainActor
    func testAPictureThisDeviceDoesNotHoldLosesItsEmbed() throws {
        let memo = try corpusMemo()
        XCTAssertTrue(repo.photoNames(forMemo: memo.id).isEmpty, "the corpus photo never synced")
        let report = try publisher(photos: [:], names: { self.repo.photoNames(forMemo: $0) }).publishReport(memo)
        let md = try written(report)

        XCTAssertFalse(md.contains("!["), "no embed for a picture that is not here:\n\(md)")
        XCTAssertFalse(md.contains("[[img_"), "the marker does not leak either")
        XCTAssertTrue(md.contains("The photo for this one never made it across."), "the words stay")
        XCTAssertTrue(images().isEmpty, "nothing written for it")
    }

    @MainActor
    func testThePictureOnceHereIsEmbeddedAndCopied() throws {
        let memo = try corpusMemo()
        let source = try XCTUnwrap(memo.metadata?.imageManifest?.first?.filename)
        let report = try publisher(photos: [source: Data([0xFF, 0xD8, 0xFF])]).publishReport(memo)
        let md = try written(report)

        let stem = ((report.relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
        XCTAssertTrue(md.contains("![[\(stem)_001.jpg]]"), md)
        XCTAssertEqual(images(), ["\(stem)_001.jpg"])
    }

    @MainActor
    func testPhotoNamesReadsTheNamesWithoutTheBytes() throws {
        repo = NotesRepository(inMemory: true)
        let id = UUID()
        repo.context.insert(MemoAsset(memoID: id, kind: MemoAsset.Kind.photo, filename: "photo_a_001.jpg", blob: Data([1])))
        repo.context.insert(MemoAsset(memoID: id, kind: MemoAsset.Kind.audio, filename: "memo_a.m4a", blob: Data([2])))
        repo.context.insert(MemoAsset(memoID: UUID(), kind: MemoAsset.Kind.photo, filename: "photo_b_001.jpg", blob: Data([3])))
        try repo.context.save()
        XCTAssertEqual(repo.photoNames(forMemo: id), ["photo_a_001.jpg"])
    }
}
