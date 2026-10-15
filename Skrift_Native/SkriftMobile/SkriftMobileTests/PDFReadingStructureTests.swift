import XCTest
@testable import SkriftMobile

/// Q459 (D213): the STRUCTURE metric of the PDF reading goldens. Word order and leakage
/// (`PDFReadingGoldenTests`) cannot see structure: a table read as paragraphs, a heading swallowed
/// into a paragraph or a figure's axis labels merged into the text all score well on order. This
/// compares, per fixture, the reading view's headings, figures and table rows (in order) with the
/// ones in `<name>.expect.md`:
/// - `# t` / `## t` is a heading `t` (the level is not compared: the reading view has one kind);
/// - `[figure: c]` is a figure with caption `c`: a reading-view block of kind `figure` or `image`
///   whose text is the caption (the reading view has no such block before Q460, so a figure
///   fixture fails until then);
/// - `| a | b |` is a row with cells `a`, `b`.
/// Paragraphs and "Page N" markers are not compared. Cell and heading text is whitespace-collapsed.
///
/// An extension of `PDFReadingGoldenTests`, so `plan/mtest.sh PDFReadingGoldenTests` runs it.
/// Known failures are registered under `"_structure"` in `test-fixtures/pdf/expected-failures.json`
/// (a list of fixture names; the `_` key keeps it out of the order/leak registrations). As with
/// order and leak, an unregistered failure fails and so does a registered one that now passes.
/// Results go to `plan/reads/pdf-reading-structure.md`.
extension PDFReadingGoldenTests {

    enum StructureItem: Equatable, CustomStringConvertible {
        case heading(String)
        case figure(String)
        case row([String])

        var description: String {
            switch self {
            case .heading(let t): return "heading \"\(t)\""
            case .figure(let c): return "figure \"\(c)\""
            case .row(let cells): return "row | " + cells.joined(separator: " | ") + " |"
            }
        }
    }

    static func collapsed(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The headings, figures and rows of an `expect.md`, in order.
    static func expectedStructure(_ md: String) -> [StructureItem] {
        var out: [StructureItem] = []
        for raw in md.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                out.append(.heading(collapsed(String(line.drop(while: { $0 == "#" })))))
            } else if line.hasPrefix("[figure: "), line.hasSuffix("]") {
                out.append(.figure(collapsed(String(line.dropFirst("[figure: ".count).dropLast()))))
            } else if line.hasPrefix("|"), line.hasSuffix("|"), line.count > 1 {
                let cells = line.dropFirst().dropLast().components(separatedBy: "|").map(collapsed)
                out.append(.row(cells))
            }
        }
        return out
    }

    /// The headings, figures and rows of a reading view, in order.
    static func actualStructure(_ blocks: [ArticleDoc.Block]) -> [StructureItem] {
        blocks.compactMap { b in
            switch b.kind {
            case .heading: return .heading(collapsed(b.text))
            case .row: return .row(b.text.components(separatedBy: "\t").map(collapsed))
            default:
                return ["figure", "image"].contains(b.kind.rawValue) ? .figure(collapsed(b.text)) : nil
            }
        }
    }

    /// nil when the two match; otherwise the first difference, in words.
    static func structureDifference(expected: [StructureItem], actual: [StructureItem]) -> String? {
        for i in 0..<max(expected.count, actual.count) {
            let e = i < expected.count ? expected[i].description : "(nothing)"
            let a = i < actual.count ? actual[i].description : "(nothing)"
            if e != a { return "item \(i + 1): expected \(e), got \(a)" }
        }
        return nil
    }

    func testStructureMetricOnHandMadeStrings() {
        let md = "# Title\n\nText.\n\n## 1 Intro\n\n[figure: Figure 1. A chart.]\n\n| a | b  c |\n| 1 | 2 |\n"
        XCTAssertEqual(Self.expectedStructure(md),
                       [.heading("Title"), .heading("1 Intro"), .figure("Figure 1. A chart."), .row(["a", "b c"]), .row(["1", "2"])])
        let blocks = [ArticleDoc.Block(kind: .heading, text: "Title"), ArticleDoc.Block(kind: .paragraph, text: "Text."),
                      ArticleDoc.Block(kind: .page, text: "Page 2"), ArticleDoc.Block(kind: .row, text: "a\tb c")]
        XCTAssertEqual(Self.actualStructure(blocks), [.heading("Title"), .row(["a", "b c"])])
        XCTAssertNil(Self.structureDifference(expected: [.heading("A")], actual: [.heading("A")]))
        XCTAssertEqual(Self.structureDifference(expected: [.heading("A"), .row(["1"])], actual: [.heading("A")]),
                       "item 2: expected row | 1 |, got (nothing)")
    }

    static func registeredStructureFailures() throws -> Set<String> {
        let data = try Data(contentsOf: fixtureDir.appendingPathComponent("expected-failures.json"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Set((obj["_structure"] as? [String]) ?? [])
    }

    func testFixtureStructureMatchesItsRegisteredBaseline() throws {
        let fixtures = try Self.fixtureNames()
        let registered = try Self.registeredStructureFailures()
        XCTAssertEqual(registered.subtracting(fixtures.keys), [], "a _structure registration names no fixture")
        var report = """
        # PDF reading view — structure on the real-shaped fixtures (Q459, D213)

        Generated by `PDFReadingGoldenTests.testFixtureStructureMatchesItsRegisteredBaseline` (phone). \
        Structure = the reading view's headings, figures and table rows, in order, against `<name>.expect.md`. \
        "Registered" is `_structure` in `test-fixtures/pdf/expected-failures.json`.

        | Fixture | Expected items | Got items | Structure | Registered | First difference |
        |---|---|---|---|---|---|

        """
        for name in fixtures.keys.sorted() {
            let pdf = Self.fixtureDir.appendingPathComponent("\(name).pdf")
            let md = try String(contentsOf: Self.fixtureDir.appendingPathComponent("\(name).expect.md"), encoding: .utf8)
            let want = Self.expectedStructure(md)
            let got = Self.actualStructure(LibraryPDF.readingDoc(url: pdf)?.blocks ?? [])
            let diff = Self.structureDifference(expected: want, actual: got)
            let isRegistered = registered.contains(name)
            if diff == nil, isRegistered {
                XCTFail("\(name): registered structure failure now passes — remove it from _structure in expected-failures.json")
            }
            if let diff, !isRegistered {
                XCTFail("\(name): structure fails and is not registered — \(diff)")
            }
            report += "| \(name) | \(want.count) | \(got.count) | \(diff == nil ? "pass" : "fail") | "
                + "\(isRegistered ? "yes" : "—") | \(diff.map { $0.replacingOccurrences(of: "|", with: "\\|") } ?? "—") |\n"
        }
        let url = Self.repoRoot.appendingPathComponent("plan/reads/pdf-reading-structure.md")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try report.write(to: url, atomically: true, encoding: .utf8)
    }
}
