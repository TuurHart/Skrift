import XCTest
@testable import SkriftMobile

/// Q156 (C61, C194): the iPad's `PublishCoordinator` asks the SAME predicate the Mac asks
/// (`ExportGate`) and says every refusal in `ExportOutcomeCopy`'s words. The Mac twin of this
/// class lives in SkriftDesktopTests.
@MainActor
final class ExportGateParityTests: XCTestCase {
    private var sandbox: URL!
    private var ledger: ExportLedger!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("skrift-gateparity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        ledger = ExportLedger(fileURL: sandbox.appendingPathComponent("ledger.json"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: sandbox) }

    private func coordinator(vault: Bool = true, portfolio: Bool = true,
                             processed: Bool = true) -> PublishCoordinator {
        let publisher = ObsidianPublisher(vaultProvider: { self.sandbox }, manageScope: false,
                                          author: "T", peopleProvider: { [] },
                                          ledgerOverride: ledger)
        return PublishCoordinator(
            memosProvider: { [] }, publisher: publisher,
            obsidianEnabled: { vault },
            portfolioConfigured: { portfolio },
            enhancementProvider: { id in
                processed ? MemoEnhancement(memoID: id, copyedit: "P.", title: "T", summary: "S") : nil
            })
    }

    private func memo(_ configure: (Memo) -> Void = { _ in }) -> Memo {
        let m = Memo(title: "T", transcript: "Body.", significance: 0.5)
        configure(m)
        return m
    }

    /// The coordinator's answer is the shared gate's answer, and its sentence is the shared sentence.
    func testIpadRefusalIsTheSharedGateInTheSharedWords() {
        let cases: [(Memo, PublishCoordinator, ExportGate.Failure)] = [
            (memo(), coordinator(vault: false), .noVaultFolder),
            (memo { $0.destination = .idea }, coordinator(portfolio: false), .noPortfolioFolder),
            (memo { $0.deletedAt = Date() }, coordinator(), .trashed),
            (memo { $0.locked = true }, coordinator(), .locked),
            (memo { $0.significance = 0 }, coordinator(), .unrated),
            (memo { $0.transcript = nil; $0.title = nil }, coordinator(), .nothingToExport),
            (memo(), coordinator(processed: false), .unprocessed),
        ]
        for (m, c, failure) in cases {
            XCTAssertEqual(c.gateFailure(m), failure)
            XCTAssertEqual(c.exportRefusal(m), ExportOutcomeCopy.refusal(failure, device: .ipad).text, "\(failure)")
            XCTAssertFalse(c.shouldPublish(m), "\(failure)")
        }
        XCTAssertNil(coordinator().gateFailure(memo()))
        XCTAssertTrue(coordinator().shouldPublish(memo()))
    }

    /// The memo channel through `ExportGate` directly gives the same answers as the facts form.
    func testMemoFormMatchesFactsForm() {
        let m = memo { $0.locked = true }
        XCTAssertEqual(ExportGate.check(memo: m, device: .ipad, folderConfigured: true, processed: true), .locked)
        XCTAssertEqual(ExportGate.check(memo: m, device: .ipad, folderConfigured: false, processed: true),
                       .noVaultFolder)
    }

    /// setexp-75: the two-versions hold is Mac-only; the iPad exports a note the Mac would hold.
    func testIpadDoesNotHoldTwoVersions() {
        let m = memo()
        XCTAssertNil(ExportGate.check(memo: m, device: .ipad, folderConfigured: true, processed: true,
                                      twoVersionsHeld: true))
        XCTAssertEqual(ExportGate.check(memo: m, device: .mac, folderConfigured: true, processed: true,
                                        twoVersionsHeld: true), .twoVersions)
    }

    /// One locked wording on both devices; the folder refusal differs only in the Settings pointer.
    func testWordingMatchesTheMac() {
        XCTAssertEqual(ExportOutcomeCopy.refusal(.locked, device: .ipad).text,
                       ExportOutcomeCopy.refusal(.locked, device: .mac).text)
        XCTAssertEqual(ExportOutcomeCopy.refusal(.noVaultFolder, device: .ipad).text,
                       "No vault folder is set on this device yet. Pick one in Settings → Obsidian.")
        for failure in ExportGate.Failure.allCases {
            XCTAssertTrue(ExportOutcomeCopy.refusal(failure, device: .ipad).isRefusal, "\(failure) is sticky")
        }
    }
}
