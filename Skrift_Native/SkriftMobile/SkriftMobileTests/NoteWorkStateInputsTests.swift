import XCTest
@testable import SkriftMobile

/// Q117 (C194): the Process / Export / Re-export button and the export outcome line take
/// their inputs from ONE place in Shared, so the iPad and the Mac cannot disagree about the
/// same note. The Mac twin of this class lives in SkriftDesktopTests.
final class NoteWorkStateInputsTests: XCTestCase {
    private var sandbox: URL!
    private var ledger: ExportLedger!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("skrift-nwsi-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        ledger = ExportLedger(fileURL: sandbox.appendingPathComponent("ledger.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    // ── the inputs ──

    func testNoEnhancementNeedsProcessing() {
        let memo = Memo(title: "A", transcript: "Body.")
        let inputs = NoteWorkState.Inputs.from(memo: memo, enhancement: nil, ledger: ledger)
        XCTAssertEqual(inputs, .init(hasPolish: false, isExported: false))
        XCTAssertEqual(inputs.state, .needsProcessing)
    }

    /// A pass that produced nothing is still a pass: processed, with no content.
    func testEmptyPassCountsAsProcessed() {
        let memo = Memo(title: "A", transcript: "Body.")
        let enh = MemoEnhancement(memoID: memo.id, processedAt: Date())
        let inputs = NoteWorkState.Inputs.from(memo: memo, enhancement: enh, ledger: ledger)
        XCTAssertTrue(inputs.hasPolish)
        XCTAssertEqual(inputs.state, .readyToExport)
    }

    /// A merely-retitled note (title only) is NOT processed.
    func testTitleAloneIsNotProcessed() {
        let memo = Memo(title: "A", transcript: "Body.")
        let enh = MemoEnhancement(memoID: memo.id, title: "Chosen")
        XCTAssertFalse(NoteWorkState.Inputs.from(memo: memo, enhancement: enh, ledger: nil).hasPolish)
    }

    func testAllThreePartsWithoutProcessedAtIsProcessed() {
        let memo = Memo(title: "A", transcript: "Body.")
        let enh = MemoEnhancement(memoID: memo.id, copyedit: "c", title: "t", summary: "s")
        XCTAssertTrue(NoteWorkState.Inputs.from(memo: memo, enhancement: enh, ledger: nil).hasPolish)
    }

    func testLedgerEntryMeansExported() {
        let memo = Memo(title: "A", transcript: "Body.")
        let enh = MemoEnhancement(memoID: memo.id, processedAt: Date())
        ledger.set(.init(relativePath: "A.md", exportedAt: Date()), for: memo.id)
        let inputs = NoteWorkState.Inputs.from(memo: memo, enhancement: enh, ledger: ledger)
        XCTAssertTrue(inputs.isExported)
        XCTAssertEqual(inputs.state, .exported)
    }

    func testNoLedgerIsNotExported() {
        let memo = Memo(title: "A", transcript: "Body.")
        let enh = MemoEnhancement(memoID: memo.id, processedAt: Date())
        XCTAssertFalse(NoteWorkState.Inputs.from(memo: memo, enhancement: enh, ledger: nil).isExported)
    }

    /// The Mac's row-level fallback goes through the same rule.
    func testLocalPolishFallbackFollowsTheSameRule() {
        let id = UUID()
        func has(_ local: NoteWorkState.Inputs.LocalPolish) -> Bool {
            NoteWorkState.Inputs.from(ledgerID: id, enhancement: nil, ledger: nil, local: local).hasPolish
        }
        XCTAssertFalse(has(.init(copyedit: "c", title: "t")))
        XCTAssertTrue(has(.init(copyedit: "c", title: "t", summary: "s")))
        XCTAssertTrue(has(.init(passRan: true)))
    }

    // ── the outcome line ──

    private func publisher(photos: [String: Data] = [:]) -> ObsidianPublisher {
        let picked = sandbox.appendingPathComponent("vault")
        try? FileManager.default.createDirectory(at: VaultLayout.home(forPicked: picked),
                                                 withIntermediateDirectories: true)
        return ObsidianPublisher(vaultProvider: { picked }, manageScope: false,
                                 author: "Tiuri", peopleProvider: { [] },
                                 photosProvider: { _ in photos },
                                 audioProvider: { _ in nil },
                                 ledgerOverride: ledger)
    }

    private var home: URL { VaultLayout.home(forPicked: sandbox.appendingPathComponent("vault")) }

    /// A pre-stamp Skrift export at the target stays a LEGACY refusal, with its own sentence.
    func testLegacyFileKeepsItsOwnOutcomeAndSentence() throws {
        _ = publisher() // creates the home
        let legacy = "---\ntitle: \"Old note\"\nlastTouched:\nauthor: Tuur\n---\n\nBody.\n"
        try legacy.write(to: home.appendingPathComponent("Old note.md"), atomically: true, encoding: .utf8)
        let memo = Memo(title: "Old note", transcript: "Body.")

        let report = try publisher().publishReport(memo)
        XCTAssertEqual(report.outcome, .blockedLegacy(relativePath: "Old note.md"))
        let msg = ExportOutcomeCopy.message(for: try XCTUnwrap(report.vaultOutcome), assetCount: report.assetCount)
        XCTAssertTrue(msg.isRefusal)
        XCTAssertTrue(msg.text.contains("predates Skrift's stamp"), msg.text)
        XCTAssertFalse(msg.text.contains("isn't Skrift's"), msg.text)
    }

    func testForeignFileKeepsTheForeignSentence() throws {
        let memo = Memo(title: "Note", transcript: "Body.")
        let first = try publisher().publishReport(memo)
        try "My own note now.\n".write(to: home.appendingPathComponent(first.relativePath),
                                      atomically: true, encoding: .utf8)
        memo.transcript = "changed"
        let report = try publisher().publishReport(memo)
        XCTAssertEqual(report.outcome, .blocked(relativePath: first.relativePath))
        let msg = ExportOutcomeCopy.message(for: try XCTUnwrap(report.vaultOutcome))
        XCTAssertTrue(msg.text.contains("isn't Skrift's"), msg.text)
    }

    /// The line quotes the WRITTEN file's stem (not the note's display title) and counts the
    /// photos placed beside it — the same two inputs the Mac gives the table.
    func testWrittenLineQuotesTheFileStemAndPhotoCount() throws {
        let memo = Memo.make(transcript: "Look. [[img_001]] More.",
                             metadata: MemoMetadata(tags: [], imageManifest: [
                                ImageManifestEntry(filename: "IMG_9001.jpg", offsetSeconds: 1)]))
        memo.title = "Photo note"
        let report = try publisher(photos: ["IMG_9001.jpg": Data([0xFF, 0xD8, 0xFF, 0xE0])])
            .publishReport(memo)
        XCTAssertEqual(report.outcome, .written(relativePath: "Photo note.md"))
        XCTAssertEqual(report.assetCount, 1)
        let msg = ExportOutcomeCopy.message(for: try XCTUnwrap(report.vaultOutcome), assetCount: report.assetCount)
        XCTAssertEqual(msg.text, "Exported “Photo note” · 1 file")
        XCTAssertFalse(msg.isRefusal)
    }

    /// `unchanged` names the file too (it used to be handed an empty path) and never says "Exported".
    func testUnchangedNamesTheFile() throws {
        let memo = Memo(title: "Same", transcript: "Body.")
        _ = try publisher().publishReport(memo)
        let report = try publisher().publishReport(memo)
        XCTAssertEqual(report.outcome, .skippedUnchanged)
        let msg = ExportOutcomeCopy.message(for: try XCTUnwrap(report.vaultOutcome))
        XCTAssertEqual(msg.text, "“Same” is already up to date")
    }

    func testNoVaultHasNoEngineOutcome() throws {
        let p = ObsidianPublisher(vaultProvider: { nil }, manageScope: false, author: "",
                                  peopleProvider: { [] }, photosProvider: { _ in [:] },
                                  audioProvider: { _ in nil }, ledgerOverride: ledger)
        let report = try p.publishReport(Memo(title: "A", transcript: "B"))
        XCTAssertEqual(report.outcome, .noVault)
        XCTAssertNil(report.vaultOutcome)
    }
}
