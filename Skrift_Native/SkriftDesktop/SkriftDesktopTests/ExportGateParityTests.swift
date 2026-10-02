import XCTest
import Foundation

/// Q156 (C61, C194): who may export a note is ONE predicate (`ExportGate`) and every refusal
/// sentence is `ExportOutcomeCopy`'s. The iPad twin of this class lives in SkriftMobileTests.
final class ExportGateParityTests: XCTestCase {

    // MARK: the shared predicate

    /// First failing gate wins, in the documented order.
    func testFirstFailingGateWins() {
        var f = ExportGate.Facts(folderConfigured: false, trashed: true, locked: true,
                                 twoVersionsHeld: true, rated: false, hasContent: false,
                                 processed: false)
        XCTAssertEqual(ExportGate.check(f, device: .mac), .noVaultFolder)
        f.destinationIsPortfolio = true
        XCTAssertEqual(ExportGate.check(f, device: .mac), .noPortfolioFolder)
        f.folderConfigured = true
        XCTAssertEqual(ExportGate.check(f, device: .mac), .trashed)
        f.trashed = false
        XCTAssertEqual(ExportGate.check(f, device: .mac), .locked)
        f.locked = false
        XCTAssertEqual(ExportGate.check(f, device: .mac), .twoVersions)
        f.twoVersionsHeld = false
        XCTAssertEqual(ExportGate.check(f, device: .mac), .unrated)
        f.rated = true
        XCTAssertEqual(ExportGate.check(f, device: .mac), .nothingToExport)
        f.hasContent = true
        XCTAssertEqual(ExportGate.check(f, device: .mac), .unprocessed)
        f.processed = true
        XCTAssertNil(ExportGate.check(f, device: .mac))
    }

    /// The one named device difference (setexp-75): the two-versions hold is Mac-only.
    func testTwoVersionsHoldIsMacOnly() {
        let f = ExportGate.Facts(twoVersionsHeld: true)
        XCTAssertEqual(ExportGate.check(f, device: .mac), .twoVersions)
        XCTAssertNil(ExportGate.check(f, device: .ipad), "D139 does not require the hold on the iPad")
    }

    /// The write path's own scope asks folder, lock and the hold, and nothing else.
    func testEngineScopeAsksOnlyWhatTheWritePathEnforces() {
        let bare = ExportGate.Facts(trashed: true, rated: false, hasContent: false, processed: false)
        XCTAssertNil(ExportGate.check(bare, device: .mac, scope: .engine))
        XCTAssertEqual(ExportGate.check(bare, device: .mac, scope: .full), .trashed)
        XCTAssertEqual(ExportGate.check(.init(locked: true), device: .mac, scope: .engine), .locked)
        XCTAssertEqual(ExportGate.check(.init(twoVersionsHeld: true), device: .mac, scope: .engine), .twoVersions)
        XCTAssertEqual(ExportGate.check(.init(folderConfigured: false), device: .mac, scope: .engine), .noVaultFolder)
    }

    // MARK: the shared words

    func testEveryRefusalIsStickyAndNamedOnBothDevices() {
        for failure in ExportGate.Failure.allCases {
            for device in [ExportGate.Device.mac, .ipad] {
                let m = ExportOutcomeCopy.refusal(failure, device: device)
                XCTAssertTrue(m.isRefusal, "\(failure) must stay until dismissed (C194)")
                XCTAssertFalse(m.text.isEmpty)
            }
        }
    }

    /// setexp-73: ONE locked wording. setexp-71/-72: only the Settings pointer follows the device.
    func testLockedHasOneWordingAndFolderRefusalsDifferOnlyInTheSettingsPointer() {
        XCTAssertEqual(ExportOutcomeCopy.refusal(.locked, device: .mac).text,
                       ExportOutcomeCopy.refusal(.locked, device: .ipad).text)
        for failure in ExportGate.Failure.allCases where failure != .noVaultFolder {
            XCTAssertEqual(ExportOutcomeCopy.refusal(failure, device: .mac).text,
                           ExportOutcomeCopy.refusal(failure, device: .ipad).text, "\(failure)")
        }
        let mac = ExportOutcomeCopy.refusal(.noVaultFolder, device: .mac).text
        let ipad = ExportOutcomeCopy.refusal(.noVaultFolder, device: .ipad).text
        XCTAssertTrue(mac.hasPrefix("No vault folder is set on this device yet."))
        XCTAssertTrue(ipad.hasPrefix("No vault folder is set on this device yet."))
        XCTAssertFalse(mac.contains("Obsidian vault path"), "the old Mac sentence is gone")
    }

    // MARK: the Mac row

    private func row(_ configure: (PipelineFile) -> Void = { _ in }) -> PipelineFile {
        let pf = PipelineFile(id: UUID().uuidString, filename: "Voice Memo.m4a", path: "", size: 0, sourceType: .audio)
        pf.enhancedTitle = "My Note"
        pf.sanitised = "Body."
        pf.significance = 0.5
        configure(pf)
        return pf
    }

    private func settings(vault: String = "", portfolio: String = "") -> AppSettings {
        var s = AppSettings.default
        s.noteFolder = vault
        s.portfolioRoot = portfolio
        return s
    }

    /// setexp-72: a portfolio note with no portfolio root names the PORTFOLIO folder, not the vault.
    func testPortfolioNoteWithoutPortfolioRootThrowsNoPortfolioFolder() {
        let pf = row { $0.destination = .idea }
        XCTAssertThrowsError(try VaultExporter.export(pf, settings: settings(vault: "/tmp/skrift-q156-vault"))) { error in
            XCTAssertEqual(error as? VaultExporter.ExportError, .noPortfolioFolder)
            let text = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertFalse(text.contains("vault path"), text)
            XCTAssertEqual(text, ExportOutcomeCopy.refusal(.noPortfolioFolder, device: .mac).text)
        }
    }

    /// setexp-71/-73: the thrown errors' words ARE the shared table.
    func testThrownErrorsReadFromTheSharedTable() {
        XCTAssertThrowsError(try VaultExporter.export(row(), settings: settings())) { error in
            XCTAssertEqual((error as? LocalizedError)?.errorDescription,
                           ExportOutcomeCopy.refusal(.noVaultFolder, device: .mac).text)
        }
        let locked = row { $0.locked = true }
        XCTAssertThrowsError(try VaultExporter.export(locked, settings: settings(vault: "/tmp/skrift-q156-vault"))) { error in
            XCTAssertEqual(error as? VaultExporter.ExportError, .lockedNote)
            XCTAssertEqual((error as? LocalizedError)?.errorDescription,
                           ExportOutcomeCopy.refusal(.locked, device: .mac).text)
        }
    }

    /// setexp-70: the Mac's full gate now checks rating, trash and processing too.
    func testMacFullGateChecksWhatTheIpadChecks() {
        let s = settings(vault: "/tmp/skrift-q156-vault")
        // Processed locally: a pass ran.
        func processed(_ pf: PipelineFile) -> PipelineFile { pf.steps.enhance = .done; return pf }

        XCTAssertNil(VaultExporter.fullGateFailure(for: processed(row()), cloud: nil, settings: s))
        XCTAssertEqual(VaultExporter.fullGateFailure(for: row(), cloud: nil, settings: s), .unprocessed)
        XCTAssertEqual(VaultExporter.fullGateFailure(
            for: processed(row { $0.significance = 0 }), cloud: nil, settings: s), .unrated)
        XCTAssertEqual(VaultExporter.fullGateFailure(
            for: processed(row { $0.deletedAt = Date() }), cloud: nil, settings: s), .trashed)
        XCTAssertEqual(VaultExporter.fullGateFailure(
            for: processed(row { $0.locked = true }), cloud: nil, settings: s), .locked)
        XCTAssertEqual(VaultExporter.fullGateFailure(
            for: processed(row()), cloud: nil, settings: settings()), .noVaultFolder)
    }

    func testMacHoldSurfacesAsTwoVersions() {
        let pf = processedHeldRow()
        defer { EditConflictHold.ids.remove(pf.id) }
        XCTAssertEqual(VaultExporter.fullGateFailure(for: pf, cloud: nil,
                                                     settings: settings(vault: "/tmp/skrift-q156-vault")),
                       .twoVersions)
    }

    private func processedHeldRow() -> PipelineFile {
        let pf = row()
        pf.steps.enhance = .done
        EditConflictHold.ids.insert(pf.id)
        return pf
    }
}
