import XCTest
import Foundation

/// Q171 (C239/C240): wording and keys the two apps used to type twice, now one copy in Shared/UI.
final class TwinUICopyQ171Tests: XCTestCase {
    func testFadingLineIsOneSuffix() {
        XCTAssertEqual(SharedCopy.fadingLine("starts fading 25 Oct"), "starts fading 25 Oct — rate it to keep it")
    }

    func testDateChipText() {
        let cal = Calendar(identifier: .gregorian)
        let a = cal.date(from: DateComponents(year: 2026, month: 9, day: 22))!
        let b = cal.date(from: DateComponents(year: 2026, month: 9, day: 25))!
        XCTAssertEqual(DateChipText.title(from: nil, to: nil), "Date \u{25BE}")
        XCTAssertEqual(DateChipText.range(from: a, to: b), "22\u{2013}25 Sep")
        XCTAssertEqual(DateChipText.range(from: a, to: nil), "from 22 Sep")
        XCTAssertEqual(DateChipText.range(from: nil, to: b), "to 25 Sep")
        XCTAssertEqual(DateChipText.title(from: a, to: b), "Date \u{00B7} 22\u{2013}25 Sep \u{25BE}")
    }

    func testConnectionsSubCaption() {
        XCTAssertEqual(ConnectionsPanelSpec.subCaption(byDate: true, firstMentioned: "12 Mar", shown: 3, total: 9),
                       "the arc of this idea · first mentioned 12 Mar")
        XCTAssertEqual(ConnectionsPanelSpec.subCaption(byDate: false, firstMentioned: "", shown: 3, total: 9),
                       "best match first · showing 3 of 9")
        XCTAssertEqual(ConnectionsPanelSpec.subCaption(byDate: false, firstMentioned: "", shown: 9, total: 9),
                       "best match first · odd matches sink to the bottom")
    }

    func testHiddenPairsKeyAndRoundTrip() {
        XCTAssertEqual(ConnectionsPanelSpec.hiddenPairsDefaultsKey, "connectionsHiddenPairs")
        let defaults = UserDefaults(suiteName: "TwinUICopyQ171Tests")!
        defaults.removePersistentDomain(forName: "TwinUICopyQ171Tests")
        ConnectionsPanelSpec.hidePair(note: "n1", neighbour: "x", defaults: defaults)
        ConnectionsPanelSpec.hidePair(note: "n1", neighbour: "y", defaults: defaults)
        XCTAssertEqual(ConnectionsPanelSpec.hiddenNeighbours(of: "n1", defaults: defaults), ["x", "y"])
        XCTAssertEqual(ConnectionsPanelSpec.hiddenNeighbours(of: "n2", defaults: defaults), [])
        defaults.removePersistentDomain(forName: "TwinUICopyQ171Tests")
    }
}
