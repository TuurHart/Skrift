import XCTest

/// Q161 (C110, C232): the Mac can withdraw semantic-index consent, and the feature has
/// ONE name — both read from the shared `RetrievalGate`.
final class MacIndexConsentTests: XCTestCase {
    func testSwitchOnEnablesAndOffWithdraws() {
        XCTAssertEqual(RetrievalGate.consentAction(wasEnabled: false, nowEnabled: true), .enable)
        XCTAssertEqual(RetrievalGate.consentAction(wasEnabled: true, nowEnabled: false), .withdraw,
                       "consent must be withdrawable on the Mac, not only grantable")
        XCTAssertEqual(RetrievalGate.consentAction(wasEnabled: true, nowEnabled: true), .none)
        XCTAssertEqual(RetrievalGate.consentAction(wasEnabled: false, nowEnabled: false), .none)
    }

    func testOneNameForTheFeature() {
        let name = RetrievalGate.Copy.featureName
        XCTAssertEqual(RetrievalGate.Copy.settingTitle, name)
        XCTAssertEqual(RetrievalGate.Copy.summonLabel, name)
        XCTAssertTrue(RetrievalGate.Copy.gateCTA.contains(name))
        XCTAssertFalse(RetrievalGate.Copy.settingTitle.localizedCaseInsensitiveContains("semantic"),
                       "the old 'Semantic journal index' name is retired")
    }

    func testWithdrawnConsentDerivesTheGate() {
        let off = RetrievalGate.derive(enabled: false, modelDownloaded: true, downloadFraction: nil,
                                       sweeping: false, sweepProgress: nil, hasRows: false, querying: false)
        XCTAssertEqual(off, .gate, "consent off → the panel shows the consent gate again, never rows")
    }
}
