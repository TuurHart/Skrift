import XCTest
@testable import SkriftMobile

/// `NoteDestination` + the reserved-word guard — the one-of-four rule in code.
///
/// The rule under test is a PRIVACY rule, not a tidiness rule (Tuur, 2026-08-26): his own
/// thoughts must never be read by AI, his ideas and inspirations deliberately are. So a note
/// carries exactly one destination, an unreadable one degrades to the PRIVATE side, and the
/// four words can't be smuggled in as tags.
final class NoteDestinationTests: XCTestCase {

    // MARK: - The four

    func testPersonalIsTheDefaultAndTheOnlyPrivateOne() {
        XCTAssertEqual(Memo(title: "T").destination, .personal,
                       "an existing memo, and every new one, means today's behaviour")
        XCTAssertFalse(NoteDestination.personal.isPortfolio)
        for d in [NoteDestination.project, .idea, .inspiration] {
            XCTAssertTrue(d.isPortfolio, "\(d.label) leaves for a repo an AI reads")
        }
    }

    /// D156: the words are Personal · Inspiration · Idea · Project, in that display order, and
    /// the stored raw values are the same words lower-cased. No old word survives anywhere.
    func testLabelsOrderAndRawValues() {
        XCTAssertEqual(NoteDestination.allCases.map(\.label),
                       ["Personal", "Inspiration", "Idea", "Project"])
        XCTAssertEqual(NoteDestination.allCases.map(\.rawValue),
                       ["personal", "inspiration", "idea", "project"])
        XCTAssertNil(NoteDestination(rawValue: "made"), "no migration: the old raw value is gone")
    }

    func testPortfolioFoldersMatchTheSpec() {
        XCTAssertNil(NoteDestination.personal.portfolioFolder, "personal uses the vault bookmark")
        XCTAssertEqual(NoteDestination.project.portfolioFolder, "_projects")
        XCTAssertEqual(NoteDestination.idea.portfolioFolder, "_ideas")
        XCTAssertEqual(NoteDestination.inspiration.portfolioFolder, "_inspiration")
    }

    // MARK: - One-of-four

    func testSettingADestinationReplacesTheLastOne() {
        let m = Memo(title: "T")
        m.destination = .inspiration
        m.destination = .idea
        XCTAssertEqual(m.destination, .idea,
                       "one-of-four: idea + inspiration is meaningless — the line is authorship")
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
        for d in [NoteDestination.project, .idea, .inspiration] {
            XCTAssertEqual(NoteWorkState.readyToExport.label(for: d), "Export to portfolio",
                           "\(d.label) does not go to Obsidian")
        }
        // The other two states are destination-agnostic on purpose: processing happens before
        // anywhere is chosen, and "Re-export" already means "again, to wherever it went".
        XCTAssertEqual(NoteWorkState.exported.label(for: .idea), "Re-export")
        XCTAssertEqual(NoteWorkState.needsProcessing.label(for: .idea), SharedCopy.processVerb)
    }

    // MARK: - Reserved words in the free tag field

    func testReservedMatchesCaseAndHashInsensitively() {
        XCTAssertEqual(NoteDestination.reserved("idea"), .idea)
        XCTAssertEqual(NoteDestination.reserved("#Idea"), .idea)
        XCTAssertEqual(NoteDestination.reserved("  INSPIRATION "), .inspiration)
        XCTAssertEqual(NoteDestination.reserved("personal"), .personal)
        XCTAssertEqual(NoteDestination.reserved("project"), .project)
        XCTAssertNil(NoteDestination.reserved("ideas"), "only the exact word is reserved")
        XCTAssertNil(NoteDestination.reserved("lisbon"))
    }

    /// REVERSED 2026-08-27. The words were refused as tags for a day on Tuur's instruction
    /// ("if I select idea and type in inspiration, that should probably not be possible"), and
    /// his real workflow needs exactly that: "if I see a cool thing that inspires me… it's just
    /// an idea with a hashtag inspiration as well." The refusal also protected nothing — the
    /// destination is a stored field, so a tag can never re-route a note.
    func testDestinationWordsAreAcceptedAsTags() {
        let split = Memo.splitTagInput("lisbon, inspiration, furniture")
        XCTAssertEqual(split.accepted, ["lisbon", "inspiration", "furniture"],
                       "#inspiration on an Idea is a real thing he does")
        XCTAssertEqual(split.reserved, [.inspiration],
                       "…and it is still REPORTED, because it raises the credit need")
    }

    func testAnOrdinaryTagReportsNothingReserved() {
        let split = Memo.splitTagInput("lisbon, furniture")
        XCTAssertEqual(split.accepted, ["lisbon", "furniture"])
        XCTAssertTrue(split.reserved.isEmpty)
    }

    func testRepeatedReservedWordIsReportedOnce() {
        let split = Memo.splitTagInput("idea, #idea, IDEA")
        XCTAssertEqual(split.accepted, ["idea", "idea", "IDEA"], "all kept as typed")
        XCTAssertEqual(split.reserved, [.idea], "reported once, not three times")
    }
}
