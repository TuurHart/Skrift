import XCTest
@testable import SkriftMobile

/// Q556 (D227): a Portfolio note exports from the Mac only. The phone and iPad read, edit, rate
/// and flip it; they never write it, and they keep no Portfolio folder.
@MainActor
final class PortfolioFromMacTests: XCTestCase {
    private var sandbox: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("skrift-q556-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: sandbox) }

    private func coordinator() -> PublishCoordinator {
        let publisher = ObsidianPublisher(vaultProvider: { self.sandbox }, manageScope: false,
                                          author: "T", peopleProvider: { [] },
                                          ledgerOverride: ExportLedger(fileURL: sandbox.appendingPathComponent("l.json")))
        return PublishCoordinator(
            publisher: publisher, obsidianEnabled: { true },
            enhancementProvider: { MemoEnhancement(memoID: $0, copyedit: "P.", title: "T", summary: "S") })
    }

    private func memo(_ destination: NoteDestination) -> Memo {
        let m = Memo(title: "T", transcript: "Body.", significance: 0.5)
        m.destination = destination
        return m
    }

    func testIosGateGivesAPortfolioNoteTheMacLineNotAFolderComplaint() {
        let c = coordinator()
        let m = memo(.portfolio)
        XCTAssertEqual(c.gateFailure(m), .exportsFromMac)
        XCTAssertEqual(c.exportRefusal(m), "Exports from the Mac")
        XCTAssertFalse(c.exportRefusal(m)!.contains("No portfolio folder"))
        XCTAssertFalse(c.shouldPublish(m))
    }

    func testGateAnswersTheSameWithNoVaultToo() {
        let f = ExportGate.Facts(destinationIsPortfolio: true, folderConfigured: false)
        XCTAssertEqual(ExportGate.check(f, device: .ipad), .exportsFromMac)
        XCTAssertEqual(ExportGate.check(f, device: .mac), .noPortfolioFolder, "the Mac's own message stays")
    }

    func testPersonalExportIsUnchanged() throws {
        let c = coordinator()
        let m = memo(.personal)
        XCTAssertNil(c.gateFailure(m))
        let report = try XCTUnwrap(try c.publishReportIfEligible(m))
        if case .written = report.outcome {} else { XCTFail("Personal still writes: \(report.outcome)") }
    }

    func testPublisherWritesNothingForAPortfolioNote() throws {
        let c = coordinator()
        let report = try c.publisher.publishReport(memo(.portfolio))
        XCTAssertEqual(report.outcome, .noVault)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: sandbox.path).isEmpty,
                      "nothing is written for a Portfolio note")
        XCTAssertNil(PublishCoordinator.ledger(for: memo(.portfolio)))
    }

    func testStalePortfolioBookmarkIsClearedAndLeavesTheSwitchAlone() {
        let defaults = UserDefaults(suiteName: "q556-\(UUID().uuidString)")!
        defaults.set(Data([1, 2, 3]), forKey: DestinationSettings.portfolioRootKey)
        defaults.set(true, forKey: "skrift.destinations.enabled")
        DestinationSettings.dropPhonePortfolioFolder(defaults: defaults)
        XCTAssertNil(defaults.data(forKey: DestinationSettings.portfolioRootKey))
        XCTAssertTrue(DestinationSettings.storedEnabled(defaults: defaults), "the synced switch stays")
        DestinationSettings.dropPhonePortfolioFolder(defaults: defaults)   // idempotent
    }

    func testIosSettingsHelpHasNoFolderWording() {
        XCTAssertFalse(SettingsCopy.destinationsHelp(on: true).contains("Pick a portfolio folder"))
        XCTAssertTrue(SettingsCopy.destinationsHelp(on: true).contains("export from your Mac"))
    }
}
