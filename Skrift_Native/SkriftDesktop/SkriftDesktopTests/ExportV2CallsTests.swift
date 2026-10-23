import XCTest

/// Q436: Tuur's four export calls (plan/reads/export-v2.md), each one line in `ExportV2`. The
/// defaults are the read's recommendations; every alternative is tested here so flipping a line
/// is the whole change.
final class ExportV2CallsTests: XCTestCase {
    typealias F = ExportV2.Frontmatter

    func testTheDefaults() {
        XCTAssertFalse(ExportV2.durationAsClock)
        XCTAssertEqual(ExportV2.pictureTextStyle, .hidden)
        XCTAssertTrue(ExportV2.escapesUnknownLinks)
        XCTAssertTrue(ExportV2.quotesPortfolioLocation)
    }

    func testDurationSecondsOrClock() {
        XCTAssertEqual(F.duration(280.6, clock: false), "281")
        XCTAssertEqual(F.duration(280.6, clock: true), "\"4:41\"")
        XCTAssertEqual(F.duration(3725, clock: true), "\"1:02:05\"")
        XCTAssertEqual(F.duration(7, clock: true), "\"0:07\"")
    }

    func testPictureTextHiddenVisibleOrNone() {
        XCTAssertEqual(ExportV2.pictureTextLines(" GREY BODY €18 ", style: .hidden), "\n%% GREY BODY €18 %%")
        XCTAssertEqual(ExportV2.pictureTextLines("GREY BODY\n€18", style: .visible),
                       "\n> [!quote] Text in the picture\n> GREY BODY\n> €18")
        XCTAssertEqual(ExportV2.pictureTextLines("GREY BODY", style: .none), "")
        XCTAssertEqual(ExportV2.pictureTextLines("  ", style: .visible), "", "no text, no block")
    }

    func testPortfolioLocationQuotedOrPlain() {
        XCTAssertEqual(F.portfolioLocation("Studio: Lisbon", quoted: true), "\"Studio: Lisbon\"")
        XCTAssertEqual(F.portfolioLocation("Studio: Lisbon", quoted: false), "Studio - Lisbon")
    }

    func testAnUnknownLinkIsEscapedInTheVault() {
        var note = ExportV2.Note(input: CompilerInput(filename: "n.md", transcript: "Fire [[the kiln]] tonight.", sourceType: .note),
                                 title: "Kiln")
        note.people = []
        let md = ExportV2.compile(note, profile: .obsidian, stem: "Kiln").markdown
        XCTAssertTrue(md.contains("\\[\\[the kiln\\]\\]"), md)
    }
}
