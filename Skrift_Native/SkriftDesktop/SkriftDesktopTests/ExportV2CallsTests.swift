import XCTest

/// Q436 / D216: Tuur's four export calls (plan/reads/export-v2.md). The alternatives were deleted
/// with v1 (Q437); these pin the answers.
final class ExportV2CallsTests: XCTestCase {
    typealias F = ExportV2.Frontmatter

    func testDurationIsAPaddedClock() {
        XCTAssertEqual(F.duration(280.6), "\"00:04:41\"")
        XCTAssertEqual(F.duration(3725), "\"01:02:05\"")
        XCTAssertEqual(F.duration(7), "\"00:00:07\"")
    }

    func testPictureTextIsAHiddenComment() {
        XCTAssertEqual(ExportV2.pictureTextComment(" GREY BODY €18 "), "\n%% GREY BODY €18 %%")
        XCTAssertEqual(ExportV2.pictureTextComment("  "), "", "no text, no comment")
    }

    func testPortfolioLocationIsQuoted() {
        var input = CompilerInput(filename: "n.md", transcript: "Words.", sourceType: .note)
        input.metadata = CompilerMetadata(location: .init(placeName: "Studio: Lisbon"))
        let md = ExportV2.compile(ExportV2.Note(input: input, title: "N"), profile: .portfolio, stem: "n").markdown
        XCTAssertTrue(md.contains("\nlocation: \"Studio: Lisbon\"\n"), md)
    }

    func testAnUnknownLinkStaysALinkInTheVault() {
        var note = ExportV2.Note(input: CompilerInput(filename: "n.md", transcript: "Fire [[the kiln]] tonight.", sourceType: .note),
                                 title: "Kiln")
        note.people = []
        let md = ExportV2.compile(note, profile: .obsidian, stem: "Kiln").markdown
        XCTAssertTrue(md.contains("Fire [[the kiln]] tonight."), "D216: as Obsidian does\n\(md)")
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
