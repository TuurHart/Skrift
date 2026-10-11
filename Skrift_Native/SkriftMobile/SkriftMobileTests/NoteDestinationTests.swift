import XCTest
@testable import SkriftMobile

/// `NoteDestination` — the one-of-two rule in code (D189, Tuur 2026-10-08).
///
/// The rule under test is a PRIVACY rule, not a tidiness rule (Tuur, 2026-08-26): his own
/// thoughts must never be read by AI, his ideas and inspirations deliberately are. So a note
/// carries exactly one destination (Personal or Portfolio) and an unreadable one degrades to the
/// PRIVATE side. idea / inspiration / project are ordinary tags and route nothing.
final class NoteDestinationTests: XCTestCase {

    // MARK: - The two

    func testPersonalIsTheDefaultAndTheOnlyPrivateOne() {
        XCTAssertEqual(Memo(title: "T").destination, .personal,
                       "an existing memo, and every new one, means today's behaviour")
        XCTAssertFalse(NoteDestination.personal.isPortfolio)
        XCTAssertTrue(NoteDestination.portfolio.isPortfolio, "Portfolio leaves for a repo an AI reads")
    }

    /// D189: the words are Personal · Portfolio, in that display order, and the stored raw values
    /// are the same words lower-cased. The old values are NOT cases any more; they decode as
    /// Portfolio plus a tag (`NoteDestination.decode`, covered by `TwoDestinationsTests`).
    func testLabelsOrderAndRawValues() {
        XCTAssertEqual(NoteDestination.allCases.map(\.label), ["Personal", "Portfolio"])
        XCTAssertEqual(NoteDestination.allCases.map(\.rawValue), ["personal", "portfolio"])
        XCTAssertNil(NoteDestination(rawValue: "idea"), "idea is a tag now, not a destination")
    }

    func testPortfolioFoldersMatchTheSpec() {
        XCTAssertNil(NoteDestination.personal.portfolioFolder, "personal uses the vault bookmark")
        XCTAssertEqual(NoteDestination.portfolio.portfolioFolder, "_inbox")
    }

    // MARK: - One-of-two

    func testSettingADestinationReplacesTheLastOne() {
        let m = Memo(title: "T")
        m.destination = .portfolio
        m.destination = .personal
        XCTAssertEqual(m.destination, .personal, "one destination at a time: setting replaces")
    }

    /// An unreadable value must never be guessed as one that LEAVES. Degrading to `.personal`
    /// is the only safe direction.
    func testUnknownRawValueDegradesToPersonal() {
        let m = Memo(title: "T")
        m.destinationRaw = "portfolio-something-from-a-future-build"
        XCTAssertEqual(m.destination, .personal)
        m.destinationRaw = ""
        XCTAssertEqual(m.destination, .personal)
    }

    func testRoundTripsThroughTheStoredRawValue() {
        for d in NoteDestination.allCases {
            let m = Memo(title: "T")
            m.destination = d
            XCTAssertEqual(m.destinationRaw, d.rawValue)
            XCTAssertEqual(m.destination, d)
        }
    }

    // MARK: - The export verb names its destination

    /// Tuur, 2026-08-27: *"if I set it to Inspiration it should not say export to Obsidian at
    /// the top right."* A button that promises the wrong destination is the same class of wrong
    /// as one that promises what it cannot do.
    func testExportVerbNamesWhereTheNoteIsActuallyGoing() {
        XCTAssertEqual(NoteWorkState.readyToExport.label(for: .personal), "Export to Obsidian")
        XCTAssertEqual(NoteWorkState.readyToExport.label(for: .portfolio), "Export to portfolio",
                       "Portfolio does not go to Obsidian")
        // The other two states are destination-agnostic on purpose: processing happens before
        // anywhere is chosen, and "Re-export" already means "again, to wherever it went".
        XCTAssertEqual(NoteWorkState.exported.label(for: .portfolio), "Re-export")
        XCTAssertEqual(NoteWorkState.needsProcessing.label(for: .portfolio), SharedCopy.processVerb)
    }

    // MARK: - Tags never route

    /// D189: typing `idea` (or any destination-looking word) in the free tag field is just a tag.
    /// A tag is not a destination, so it can never move a note across the privacy line.
    func testTagsNeverRouteANote() {
        let m = Memo(title: "T")
        m.tags = ["idea", "inspiration", "project", "portfolio"]
        XCTAssertEqual(m.destination, .personal)
    }
}
