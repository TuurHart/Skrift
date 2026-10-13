import XCTest

/// Q395 / D204: Personal and Portfolio are ONE tap pill, like the rating pill. A tap flips the
/// value in place; there is no dropdown, no expanded segment row, no sheet. The view is SwiftUI
/// and this bundle is host-less, so the tests drive the pure tap step (`NoteDestination.tapped`)
/// and read the shared view's source to prove the menu path is gone.
final class DestinationPillTests: XCTestCase {

    // MARK: - The tap flips the value

    func testTapFlipsPersonalToPortfolioAndBack() {
        XCTAssertEqual(NoteDestination.personal.toggled, .portfolio)
        XCTAssertEqual(NoteDestination.portfolio.toggled, .personal)
    }

    func testTwoTapsReturnToTheStart() {
        for d in NoteDestination.allCases {
            XCTAssertEqual(d.toggled.toggled, d)
            XCTAssertNotEqual(d.toggled, d, "a tap must always change the value")
        }
    }

    func testTapCommitsTheNewValueExactlyOnce() {
        var stored = NoteDestination.personal
        var picks: [NoteDestination] = []
        let next = NoteDestination.tapped(&stored) { picks.append($0) }
        XCTAssertEqual(next, .portfolio)
        XCTAssertEqual(stored, .portfolio, "the synced field is written in place")
        XCTAssertEqual(picks, [.portfolio], "onPick fires once, with the new value")

        _ = NoteDestination.tapped(&stored) { picks.append($0) }
        XCTAssertEqual(stored, .personal)
        XCTAssertEqual(picks, [.portfolio, .personal])
    }

    func testPortfolioKeepsItsInboxFolder() {
        XCTAssertEqual(NoteDestination.personal.toggled.portfolioFolder, "_inbox")
        XCTAssertNil(NoteDestination.portfolio.toggled.portfolioFolder)
    }

    // MARK: - No menu path left

    private static var sharedViewSource: String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SkriftDesktopTests
            .deletingLastPathComponent()   // SkriftDesktop
            .deletingLastPathComponent()   // Skrift_Native
        return (try? String(contentsOf: root.appendingPathComponent("Shared/UI/DestinationRowView.swift"),
                            encoding: .utf8)) ?? ""
    }

    func testSharedViewHasNoMenuDropdownOrExpandedSegments() throws {
        let src = Self.sharedViewSource
        try XCTSkipIf(src.isEmpty, "source tree not readable from the test host")
        // Strip comments so the doctrine text may name what was removed.
        let code = src.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        for banned in ["Menu", "Picker", "confirmationDialog", ".sheet", ".popover", "startExpanded",
                       "expanded", "segments", "familyLabels", "familyDivider", "chevron.down",
                       "destination-chip", "destination-personal", "destination-portfolio"] {
            XCTAssertFalse(code.contains(banned), "DestinationRowView still carries the menu path: \(banned)")
        }
        XCTAssertTrue(code.contains("destination-pill"), "the pill is the one control")
        XCTAssertTrue(code.contains("toggled") || code.contains("tapped"),
                      "a tap goes through the shared flip")
    }
}
