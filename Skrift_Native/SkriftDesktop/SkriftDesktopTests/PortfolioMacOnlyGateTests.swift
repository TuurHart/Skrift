import XCTest
import Foundation

/// Q556 (D227): the phone and iPad stop exporting Portfolio notes; the Mac's gate is unchanged.
final class PortfolioMacOnlyGateTests: XCTestCase {

    func testMacGateStillAsksForThePortfolioFolderAndThenPasses() {
        var f = ExportGate.Facts(destinationIsPortfolio: true, folderConfigured: false)
        XCTAssertEqual(ExportGate.check(f, device: .mac), .noPortfolioFolder)
        f.folderConfigured = true
        XCTAssertNil(ExportGate.check(f, device: .mac))
    }

    func testIpadGateRefusesAPortfolioNoteWithTheMacLine() {
        let f = ExportGate.Facts(destinationIsPortfolio: true)
        XCTAssertEqual(ExportGate.check(f, device: .ipad), .exportsFromMac)
        XCTAssertEqual(ExportOutcomeCopy.refusal(.exportsFromMac, device: .ipad).text, "Exports from the Mac")
        XCTAssertNil(ExportGate.check(.init(), device: .ipad), "a Personal note still passes")
    }

    func testMacKeepsItsPortfolioFolderWording() {
        XCTAssertTrue(SettingsCopy.destinationsHelp(on: true, hasFolder: false).contains("Pick a portfolio folder"))
        XCTAssertEqual(SettingsCopy.portfolioFolderLabel, "Portfolio folder")
    }
}
