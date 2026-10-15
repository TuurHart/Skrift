import XCTest
@testable import SkriftMobile

/// Q458 (D213): the PDF reading view measured on real-shaped PDFs. `test-fixtures/pdf/` holds six
/// generated, fictional PDFs (`generate.py`) — two-column paper, report with running headers and
/// page numbers, figure + caption, 5-column table, scanned page (pixels only), plain book page —
/// each with `<name>.expect.md`, the reading text a careful human wants.
///
/// Per fixture this runs today's reading view (`LibraryPDF.readingDoc(url:)`, PDFKit text layer →
/// `PDFReflow`) and scores two things:
/// - order: word-order similarity to the expected text, 2·LCS(words) / (|expected| + |actual|).
///   Passes at `minSimilarity`. No reading view at all scores 0.
/// - leak: running header / footer / page-number strings (`fixtures.json`) found in the reading
///   view. Passes at 0. The view's own "Page N" markers are not counted (they are not the PDF's).
/// Results go to `plan/reads/pdf-reading-baseline.md`. Known failures are registered in
/// `test-fixtures/pdf/expected-failures.json` (C5 style): an unregistered failure fails, and so
/// does a registered failure that now passes — the item that fixes it removes its registration.
final class PDFReadingGoldenTests: XCTestCase {

    static let minSimilarity = 0.9

    static let repoRoot: URL = {
        // .../Skrift_Native/SkriftMobile/SkriftMobileTests/PDFReadingGoldenTests.swift -> 4 up.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url
    }()
    static let fixtureDir = repoRoot.appendingPathComponent("test-fixtures/pdf")

    struct Score {
        let name: String
        let offered: Bool
        let blocks: Int
        let similarity: Double
        let leaks: [String]
        let text: String
        var failing: [String] {
            var out: [String] = []
            if similarity < PDFReadingGoldenTests.minSimilarity { out.append("order") }
            if !leaks.isEmpty { out.append("leak") }
            return out
        }
    }

    // MARK: - Metrics (pure)

    /// Lowercased runs of letters and digits; everything else (markdown, punctuation) separates.
    static func words(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
    }

    /// The expected text as words: markdown marks drop out, a figure marker keeps only its caption.
    static func expectedWords(_ md: String) -> [String] {
        words(md.replacingOccurrences(of: "[figure: ", with: " "))
    }

    static func lcs(_ a: [String], _ b: [String]) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var prev = [Int](repeating: 0, count: b.count + 1)
        var cur = prev
        for i in 1...a.count {
            for j in 1...b.count {
                cur[j] = a[i - 1] == b[j - 1] ? prev[j - 1] + 1 : max(prev[j], cur[j - 1])
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    static func similarity(expected: [String], actual: [String]) -> Double {
        let total = expected.count + actual.count
        return total == 0 ? 1 : 2 * Double(lcs(expected, actual)) / Double(total)
    }

    /// Leak strings found in `text` as whole words (so a folio "113" never matches "1130").
    static func leaks(_ candidates: [String], in text: String) -> [String] {
        candidates.filter { leak in
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: leak) + "(?![\\p{L}\\p{N}])"
            return text.range(of: pattern, options: .regularExpression) != nil
        }
    }

    func testMetricsOnHandMadeStrings() {
        XCTAssertEqual(Self.words("## 1 Introduction — it's €1,840."), ["1", "introduction", "it", "s", "1", "840"])
        XCTAssertEqual(Self.expectedWords("[figure: Figure 1. Visits.]"), ["figure", "1", "visits"])
        XCTAssertEqual(Self.similarity(expected: ["a", "b", "c"], actual: ["a", "b", "c"]), 1)
        XCTAssertEqual(Self.similarity(expected: ["a", "b", "c"], actual: []), 0)
        XCTAssertEqual(Self.similarity(expected: ["a", "b", "c", "d"], actual: ["c", "d", "a", "b"]), 0.5,
                       "two halves swapped keep half the order")
        XCTAssertEqual(Self.leaks(["113", "Page 1 of 2"], in: "costs 1130 here. Page 1 of 2"), ["Page 1 of 2"])
    }

    // MARK: - Fixtures

    static func fixtureNames() throws -> [String: [String]] {
        let data = try Data(contentsOf: fixtureDir.appendingPathComponent("fixtures.json"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var out: [String: [String]] = [:]
        for (key, value) in obj where !key.hasPrefix("_") {
            out[key] = ((value as? [String: Any])?["leaks"] as? [String]) ?? []
        }
        return out
    }

    static func registeredFailures() throws -> [String: [String]] {
        let data = try Data(contentsOf: fixtureDir.appendingPathComponent("expected-failures.json"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var out: [String: [String]] = [:]
        for (key, value) in obj where !key.hasPrefix("_") { out[key] = (value as? [String]) ?? [] }
        return out
    }

    static func score(_ name: String, leakStrings: [String]) throws -> Score {
        let pdf = fixtureDir.appendingPathComponent("\(name).pdf")
        let md = try String(contentsOf: fixtureDir.appendingPathComponent("\(name).expect.md"), encoding: .utf8)
        let doc = LibraryPDF.readingDoc(url: pdf)
        let text = (doc?.blocks ?? []).filter { $0.kind != .page }.map(\.text).joined(separator: "\n")
        return Score(name: name, offered: doc != nil, blocks: doc?.blocks.count ?? 0,
                     similarity: similarity(expected: expectedWords(md), actual: words(text)),
                     leaks: leaks(leakStrings, in: text), text: text)
    }

    func testFixturesMatchTheirRegisteredBaseline() throws {
        let fixtures = try Self.fixtureNames()
        XCTAssertGreaterThanOrEqual(fixtures.count, 6, "six real-shaped fixtures")
        let registered = try Self.registeredFailures()
        XCTAssertEqual(Set(registered.keys).subtracting(fixtures.keys), [], "a registration names no fixture")
        var scores: [Score] = []
        for name in fixtures.keys.sorted() {
            XCTAssertTrue(FileManager.default.fileExists(atPath: Self.fixtureDir.appendingPathComponent("\(name).pdf").path),
                          "\(name).pdf missing: run test-fixtures/pdf/generate.py")
            let s = try Self.score(name, leakStrings: fixtures[name] ?? [])
            scores.append(s)
            let want = Set(registered[name] ?? []), got = Set(s.failing)
            for fixed in want.subtracting(got).sorted() {
                XCTFail("\(name): registered '\(fixed)' failure now passes — remove it from expected-failures.json")
            }
            for broke in got.subtracting(want).sorted() {
                XCTFail("\(name): '\(broke)' fails and is not registered (similarity \(Self.pct(s.similarity)), leaks \(s.leaks))")
            }
        }
        try Self.writeBaseline(scores, registered: registered)
    }

    // MARK: - plan/reads/pdf-reading-baseline.md

    static func pct(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }

    static func writeBaseline(_ scores: [Score], registered: [String: [String]]) throws {
        var md = """
        # PDF reading view — baseline on the real-shaped fixtures (Q458, D213)

        Generated by `PDFReadingGoldenTests` (phone) from `test-fixtures/pdf/`. Order = word-order \
        similarity to `<name>.expect.md` (2·LCS / total words, pass ≥ \(pct(minSimilarity))). \
        Leaks = running header, footer or page-number strings that reached the reading view (pass = 0). \
        "Registered" is `expected-failures.json`: the failures a later item flips.

        | Fixture | Reading view | Blocks | Order | Leaks | Fails | Registered |
        |---|---|---|---|---|---|---|

        """
        for s in scores {
            let leakCell = s.leaks.isEmpty ? "0" : "\(s.leaks.count): " + s.leaks.map { "`\($0)`" }.joined(separator: ", ")
            md += "| \(s.name) | \(s.offered ? "yes" : "no") | \(s.blocks) | \(pct(s.similarity)) | \(leakCell) | "
                + "\(s.failing.isEmpty ? "—" : s.failing.joined(separator: ", ")) | "
                + "\((registered[s.name] ?? []).joined(separator: ", ").isEmpty ? "—" : (registered[s.name] ?? []).joined(separator: ", ")) |\n"
        }
        md += "\n## What the reading view shows today\n\nOne block per line, \"Page N\" markers left out.\n"
        for s in scores {
            md += "\n### \(s.name)\n\n"
            md += s.text.isEmpty ? "> (no reading view: real page only)\n"
                : s.text.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n>\n") + "\n"
        }
        let url = repoRoot.appendingPathComponent("plan/reads/pdf-reading-baseline.md")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try md.write(to: url, atomically: true, encoding: .utf8)
    }
}
