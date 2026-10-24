import XCTest

/// Q436: Tuur's four export calls (plan/reads/export-v2.md), each one line in `ExportV2`, set by
/// D216; every alternative is tested here so flipping a line is the whole change.
final class ExportV2CallsTests: XCTestCase {
    typealias F = ExportV2.Frontmatter

    func testTheDefaults() {
        XCTAssertTrue(ExportV2.durationAsClock)
        XCTAssertEqual(ExportV2.pictureTextStyle, .hidden)
        XCTAssertFalse(ExportV2.escapesUnknownLinks)
        XCTAssertTrue(ExportV2.quotesPortfolioLocation)
    }

    func testDurationSecondsOrClock() {
        XCTAssertEqual(F.duration(280.6, clock: false), "281")
        XCTAssertEqual(F.duration(280.6, clock: true), "\"00:04:41\"")
        XCTAssertEqual(F.duration(3725, clock: true), "\"01:02:05\"")
        XCTAssertEqual(F.duration(7, clock: true), "\"00:00:07\"")
        XCTAssertEqual(F.duration(280.6), "\"00:04:41\"", "D216: the clock is the default")
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

    func testAnUnknownLinkStaysALinkInTheVault() {
        var note = ExportV2.Note(input: CompilerInput(filename: "n.md", transcript: "Fire [[the kiln]] tonight.", sourceType: .note),
                                 title: "Kiln")
        note.people = []
        let md = ExportV2.compile(note, profile: .obsidian, stem: "Kiln").markdown
        XCTAssertTrue(md.contains("Fire [[the kiln]] tonight."), "D216: as Obsidian does\n\(md)")
        XCTAssertEqual(ExportV2.Body.escapingUnresolved("Fire [[the kiln]].", people: []), "Fire \\[\\[the kiln\\]\\].",
                       "the alternative still escapes")
    }

    func testALinkToADeletedPersonStaysALink() {
        var note = ExportV2.Note(input: CompilerInput(filename: "n.md", transcript: "Ask [[Lotte Vos]].", sourceType: .note),
                                 title: "Ask")
        var lotte = Person(canonical: "[[Lotte Vos]]", aliases: [], short: "Lotte", lastModifiedAt: "2026-01-01T00:00:00.000Z")
        lotte.deleted = true
        note.people = [lotte]
        let md = ExportV2.compile(note, profile: .obsidian, stem: "Ask").markdown
        XCTAssertTrue(md.contains("Ask [[Lotte Vos]]."), "D216: a person later deleted from names stays a link\n\(md)")
    }
}
