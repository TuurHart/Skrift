import XCTest
@testable import SkriftMobile

/// Q181: the iPad Connections panel now feeds the shared why-chip derivation the REAL name
/// lists (it passed `[]`, so no person chip ever showed). The phone stores no `sanitised`,
/// so the names come from the shared linker run over the local names DB.
final class ConnectionsWhyNamesQ181Tests: XCTestCase {
    private let hendri = Person(canonical: "[[Hendri van Niekerk]]",
                                aliases: ["Hendri van Niekerk", "Hendri"],
                                short: "Hendri",
                                lastModifiedAt: "2026-01-01T00:00:00Z")

    func testLinkedNamesFindsAKnownPerson() {
        let names = ConnectionsPanelLogic.linkedNames(body: "Met up with Hendri today.", people: [hendri])
        XCTAssertEqual(names, ["Hendri van Niekerk"])
    }

    func testNoPeopleOrNoBodyMeansNoNames() {
        XCTAssertEqual(ConnectionsPanelLogic.linkedNames(body: "Met up with Hendri today.", people: []), [])
        XCTAssertEqual(ConnectionsPanelLogic.linkedNames(body: "", people: [hendri]), [])
    }

    func testSharedPersonBecomesAPersonChipFirst() {
        let mine = ConnectionsPanelLogic.linkedNames(body: "Hendri liked the plan.", people: [hendri])
        let theirs = ConnectionsPanelLogic.linkedNames(body: "Dinner with Hendri on Friday.", people: [hendri])
        let chips = ConnectionWhyDerivation.chips(
            currentNames: mine, currentTags: [], currentBody: "",
            otherNames: theirs, otherTags: [], otherBody: "")
        XCTAssertEqual(chips, [ConnectionWhy(kind: .person, text: "Hendri van Niekerk")])
    }

    func testPanelWidthIsTheSharedConstant() {
        XCTAssertEqual(Adaptive.sidePanelWidth, ConnectionsPanelSpec.panelWidth)
        XCTAssertEqual(ConnectionsPanelSpec.panelWidth, 300)
    }
}
