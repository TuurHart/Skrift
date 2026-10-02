import XCTest
import SwiftData
import Foundation

/// Q117 (C194): the Process / Export / Re-export button and the export outcome line take
/// their inputs from ONE place in Shared, so the Mac and the iPad cannot disagree about the
/// same note. The iPad twin of this class lives in SkriftMobileTests.
final class NoteWorkStateInputsTests: XCTestCase {
    private var sandbox: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("skrift-nwsi-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    private func cloudContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Memo.self, MemoAsset.self, MemoEnhancement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func settings() -> AppSettings {
        var s = AppSettings()
        s.noteFolder = sandbox.appendingPathComponent("vault").path
        return s
    }

    // ── the shared rule ──

    func testEmptyPassCountsAsProcessedAndTitleAloneDoesNot() {
        let id = UUID()
        let pass = MemoEnhancement(memoID: id, processedAt: Date())
        XCTAssertTrue(NoteWorkState.Inputs.from(ledgerID: id, enhancement: pass, ledger: nil).hasPolish)
        let retitled = MemoEnhancement(memoID: id, title: "Chosen")
        XCTAssertFalse(NoteWorkState.Inputs.from(ledgerID: id, enhancement: retitled, ledger: nil).hasPolish)
    }

    func testLedgerEntryMeansExported() {
        let id = UUID()
        let ledger = ExportLedger(fileURL: sandbox.appendingPathComponent("l.json"))
        let pass = MemoEnhancement(memoID: id, processedAt: Date())
        XCTAssertEqual(NoteWorkState.Inputs.from(ledgerID: id, enhancement: pass, ledger: ledger).state,
                       .readyToExport)
        ledger.set(.init(relativePath: "A.md", exportedAt: Date()), for: id)
        XCTAssertEqual(NoteWorkState.Inputs.from(ledgerID: id, enhancement: pass, ledger: ledger).state,
                       .exported)
    }

    // ── the Mac's call ──

    /// A note the iPad polished (processedAt, nothing the Mac itself ran) reads as processed
    /// on the Mac exactly as it does on the iPad, even after an EMPTY pass.
    func testMacReadsTheSyncedEnhancementLikeTheIPadDoes() throws {
        let ctx = try cloudContext()
        let id = UUID()
        let memo = Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", title: "A", transcript: "Body.")
        ctx.insert(memo)
        ctx.insert(MemoEnhancement(memoID: id, processedAt: Date()))
        try ctx.save()
        let pf = PipelineFile(id: id.uuidString, filename: "memo_\(id.uuidString).m4a")

        let inputs = VaultExporter.workInputs(for: pf, cloud: ctx, settings: settings())
        XCTAssertTrue(inputs.hasPolish, "the iPad's empty pass is processed here too")
        XCTAssertEqual(inputs.state, .readyToExport)
    }

    func testMacWithoutCloudFallsBackToItsOwnRowAndRule() throws {
        let pf = PipelineFile(id: UUID().uuidString, filename: "a.m4a")
        XCTAssertEqual(VaultExporter.workInputs(for: pf, cloud: nil, settings: settings()).state,
                       .needsProcessing)
        pf.enhancedTitle = "t"; pf.enhancedCopyedit = "c"
        XCTAssertFalse(VaultExporter.workInputs(for: pf, cloud: nil, settings: settings()).hasPolish,
                       "two parts are not a polish")
        pf.enhancedSummary = "s"
        XCTAssertTrue(VaultExporter.workInputs(for: pf, cloud: nil, settings: settings()).hasPolish)
        let done = PipelineFile(id: UUID().uuidString, filename: "b.m4a")
        done.enhanceStatus = .done
        XCTAssertTrue(VaultExporter.workInputs(for: done, cloud: nil, settings: settings()).hasPolish,
                      "this Mac's own pass counts before it syncs")
    }

    /// `steps.export == .done` no longer decides it — the ledger of the destination folder does.
    func testMacExportedComesFromTheLedgerNotTheStepFlag() throws {
        let s = settings()
        let pf = PipelineFile(id: UUID().uuidString, filename: "a.m4a")
        pf.enhanceStatus = .done
        pf.exportStatus = .done
        XCTAssertEqual(VaultExporter.workInputs(for: pf, cloud: nil, settings: s).state, .readyToExport,
                       "flag alone, no ledger entry: not exported")

        let home = try XCTUnwrap(VaultExporter.exportHome(for: pf, settings: s))
        ExportLedger.default(for: home).set(.init(relativePath: "a.md", exportedAt: Date()),
                                            for: VaultExporter.ledgerID(for: pf))
        XCTAssertEqual(VaultExporter.workInputs(for: pf, cloud: nil, settings: s).state, .exported)
    }

    func testMacWithNoVaultIsNeverExported() {
        let pf = PipelineFile(id: UUID().uuidString, filename: "a.m4a")
        pf.enhanceStatus = .done
        pf.exportStatus = .done
        XCTAssertFalse(VaultExporter.workInputs(for: pf, cloud: nil, settings: AppSettings()).isExported)
    }

    // ── the outcome line ──

    /// One name rule: the stem of the file the engine named, with the file count when > 0.
    func testOutcomeLineQuotesTheFileStemAndCountsAssets() {
        let m = ExportOutcomeCopy.message(for: .created(relativePath: "Notes/Hotel Du Vin.md"), assetCount: 2)
        XCTAssertEqual(m.text, "Exported “Hotel Du Vin” · 2 files")
        XCTAssertFalse(m.isRefusal)
        XCTAssertEqual(ExportOutcomeCopy.message(for: .unchanged(relativePath: "A.md")).text,
                       "“A” is already up to date")
    }

    func testLegacyAndForeignKeepSeparateRefusalSentences() {
        let legacy = ExportOutcomeCopy.message(for: .blockedLegacy(relativePath: "A.md"))
        let foreign = ExportOutcomeCopy.message(for: .blockedForeign(relativePath: "A.md"))
        XCTAssertTrue(legacy.isRefusal && foreign.isRefusal)
        XCTAssertNotEqual(legacy.text, foreign.text)
        XCTAssertTrue(legacy.text.contains("predates Skrift's stamp"))
    }
}
