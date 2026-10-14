import XCTest
import Foundation

/// Q419 (C255 / C256 / C260, R69 / R68 / R65): the shared name matcher's edge cases.
///  - a Dutch bare possessive on an alias (`Wims`, `Lottes`) links like `Wim's`, unless that word
///    is itself a roster alias;
///  - matching folds diacritics both ways (Ines/Inés, Månsson/Mansson);
///  - an inline `#tag` is never split or linked, even when it equals an alias.
/// Fixtures: test-fixtures/corpus/notes/edge-name-{dutch-possessive,diacritics,is-tag}/note.json
/// (listed in manifest-q419.json). Each carries `expect.cases`; this runs them all through
/// `Sanitiser.process`.
final class NameMatcherEdgeTests: XCTestCase {

    private struct RosterEntry: Decodable {
        let canonical: String
        let aliases: [String]
        let short: String?
        var person: Person {
            Person(canonical: canonical, aliases: aliases, short: short, lastModifiedAt: "2026-09-01T09:00:00Z")
        }
    }
    private struct Case: Decodable {
        let name: String
        let text: String
        let roster: [RosterEntry]?
        let sanitised: String
        let ambiguous: Int?
    }
    private struct Expect: Decodable {
        let roster: [RosterEntry]?
        let cases: [Case]
    }
    private struct Note: Decodable { let expect: Expect }
    private struct Manifest: Decodable {
        struct Entry: Decodable { let folder: String }
        let notes: [Entry]
    }

    private func root() -> URL { CorpusSeed.fixtureRoot(file: #filePath) }

    private func note(_ slug: String) throws -> Note {
        let url = root().appendingPathComponent("notes/\(slug)/note.json")
        return try JSONDecoder().decode(Note.self, from: Data(contentsOf: url))
    }

    private func run(_ slug: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let n = try note(slug)
        XCTAssertFalse(n.expect.cases.isEmpty, "\(slug) has cases", file: file, line: line)
        for c in n.expect.cases {
            let roster = (c.roster ?? n.expect.roster ?? []).map(\.person)
            XCTAssertFalse(roster.isEmpty, "\(slug) / \(c.name): a roster", file: file, line: line)
            let r = Sanitiser.process(text: c.text, people: roster)
            XCTAssertEqual(r.sanitised, c.sanitised, "\(slug) / \(c.name)", file: file, line: line)
            XCTAssertEqual(r.ambiguous.count, c.ambiguous ?? 0, "\(slug) / \(c.name): suggestions", file: file, line: line)
        }
    }

    func testManifestListsTheThreeFixtures() throws {
        let m = try JSONDecoder().decode(Manifest.self,
            from: Data(contentsOf: root().appendingPathComponent("manifest-q419.json")))
        XCTAssertEqual(m.notes.map(\.folder).sorted(),
                       ["edge-name-diacritics", "edge-name-dutch-possessive", "edge-name-is-tag"])
    }

    // C255 / R69: `edge-name-dutch-possessive` links "Wims auto".
    func testDutchBarePossessive() throws { try run("edge-name-dutch-possessive") }

    // C256 / R68: `edge-name-diacritics`, both directions.
    func testDiacriticsFoldBothWays() throws { try run("edge-name-diacritics") }

    // C260 / R65: `edge-name-is-tag`.
    func testTagIsNeverSplit() throws { try run("edge-name-is-tag") }

    // The phone's in-place spans make the same decisions: the span is the bare name, the
    // bare `s` stays outside it, and a tag yields no span.
    func testNameSpansAgree() {
        let wim = Person(canonical: "[[Wim Jansen]]", aliases: ["Wim"], short: "Wim", lastModifiedAt: "2026-09-01T09:00:00Z")
        let raw = "#Wim noteert: Wims auto."
        let spans = Sanitiser.nameSpans(inRaw: raw, people: [wim])
        XCTAssertEqual(spans.count, 1)
        guard let s = spans.first else { return }
        XCTAssertEqual(s.tier, .linked)
        XCTAssertEqual((raw as NSString).substring(with: s.range), "Wim", "bare name, no trailing s")
        XCTAssertGreaterThan(s.offset, 4, "the #Wim tag is not the span")
    }

    // A pruned person's alias is a dotted suggestion; the span still excludes the bare s.
    func testSuggestionSpanDropsBareS() {
        let sams = [
            Person(canonical: "[[Sam Ruiz]]", aliases: ["Sam"], short: "Sam", lastModifiedAt: "2026-09-01T09:00:00Z"),
            Person(canonical: "[[Sam Lindqvist]]", aliases: ["Sam"], short: "Sam", lastModifiedAt: "2026-09-01T09:00:00Z"),
        ]
        let raw = "Sams fiets en #Sam."
        let spans = Sanitiser.nameSpans(inRaw: raw, people: sams)
        XCTAssertEqual(spans.count, 1, "the tag yields no span")
        XCTAssertEqual(spans.first.map { (raw as NSString).substring(with: $0.range) }, "Sam")
        XCTAssertEqual(spans.first?.tier, .ambiguous)
    }

    // A real alias ending in `s` is not stripped.
    func testAliasEndingInSKeepsItsS() {
        let chris = Person(canonical: "[[Chris Dale]]", aliases: ["Chris"], short: "Chris", lastModifiedAt: "2026-09-01T09:00:00Z")
        let r = Sanitiser.process(text: "Chris kwam. Chriss auto.", people: [chris])
        XCTAssertEqual(r.sanitised, "[[Chris Dale]] kwam. Chriss auto.")
    }
}
