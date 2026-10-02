import XCTest
import Foundation

/// Q181 (C239/C240, R58): the Connections panel's chrome is ONE copy for the Mac and the
/// iPad (`Shared/UI/ConnectionsPanelShared.swift`). These pin the numbers and wording the
/// two apps used to disagree on, and the cap + person-chip rules.
final class ConnectionsPanelParityTests: XCTestCase {
    func testOnePanelWidthAndHeaderSize() {
        XCTAssertEqual(ConnectionsPanelSpec.panelWidth, 300, "Mac was 280, iPad 300")
        XCTAssertEqual(ConnectionsPanelSpec.headerTitleSize, 11, "Mac was 10, iPad 11")
        XCTAssertEqual(ConnectionsPanelSpec.headerCountSize, 10)
        XCTAssertEqual(ConnectionsPanelSpec.dateLineSize, 10, "Mac date line was 9 uppercase, iPad 10")
        XCTAssertEqual(ConnectionsPanelSpec.headerTitle, "CONNECTIONS")
    }

    func testOneHideWording() {
        XCTAssertEqual(ConnectionsPanelSpec.hideLabel, "Not related — hide")
        XCTAssertEqual(ConnectionsPanelSpec.closeLabel, "Hide Connections")
    }

    private func chips(_ n: Int) -> [ConnectionWhy] {
        (0..<n).map { ConnectionWhy(kind: .term, text: "word\($0)") }
    }

    func testChipCapIsThreeWithOverflowCount() {
        XCTAssertEqual(ConnectionsPanelSpec.whyChipCap, 3)
        let none = ConnectionWhyPlan([])
        XCTAssertEqual(none.shown, [])
        XCTAssertEqual(none.extra, 0)
        let three = ConnectionWhyPlan(chips(3))
        XCTAssertEqual(three.shown.count, 3)
        XCTAssertEqual(three.extra, 0)
        let four = ConnectionWhyPlan(chips(4))
        XCTAssertEqual(four.shown.map(\.text), ["word0", "word1", "word2"])
        XCTAssertEqual(four.extra, 1)
    }

    func testTermChipsAreQuotedPersonAndTagAreNot() {
        XCTAssertEqual(ConnectionWhy(kind: .term, text: "garden").displayText, "“garden”")
        XCTAssertEqual(ConnectionWhy(kind: .person, text: "Hendri").displayText, "Hendri")
        XCTAssertEqual(ConnectionWhy(kind: .tag, text: "#idea").displayText, "#idea")
    }

    /// With real name lists the person chip comes first (the iPad passed `[]` before).
    func testSharedPersonLeadsTheChips() {
        let chips = ConnectionWhyDerivation.chips(
            currentNames: ["Hendri van Niekerk"], currentTags: ["idea"], currentBody: "",
            otherNames: ["Hendri van Niekerk"], otherTags: ["idea"], otherBody: "")
        XCTAssertEqual(chips.first, ConnectionWhy(kind: .person, text: "Hendri van Niekerk"))
        XCTAssertEqual(chips.map(\.kind), [.person, .tag])
    }

    /// Both apps read a `[[Name]]` link out of a name-linked body the same way.
    func testWikiNamesFromLinkedBody() {
        let names = ConnectionWhyDerivation.wikiNames(
            inSanitised: "Met [[Hendri van Niekerk]] and [[memo:abc|that note]] today.")
        XCTAssertEqual(names, ["Hendri van Niekerk"])
    }
}
