import XCTest

/// Q501 (C34, C116, D215): copy-edit v2 keeps his headings and his bold/italic labels. Heading
/// lines are held aside like checkboxes; bold/italic markup is held aside and the words inside
/// reach the model bare, then wrap back; an edit that loses a span's words ships his words.
/// The short-note sentence rule now covers exactly 40 words, so no length falls between it and
/// the C33 shrink guard. MLX-free: the corpus half replays the outputs `-recordcopyeditv2` recorded.
@MainActor
final class CopyEditV2FormattingTests: XCTestCase {
    typealias H = CopyEditDiffHarnessTests
    typealias G = CopyEditV2.Gate

    final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [String] = []
        func add(_ i: String) { lock.lock(); list.append(i); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return list }
    }

    // MARK: - headings

    func testHeadingLinesNeverReachTheModelAndComeBack() async throws {
        let body = "# Touring bike build\n\nBudget all in, maybe two thousand.\n\n## Frame\n\nlugged steel from the guy in Porto"
        let seen = Seen()
        let r = try await CopyEditV2.copyEdit(body, spoken: false, prompt: "P") { _, t, _ in
            seen.add(t); return "Budget all in: maybe two thousand.\n\nLugged steel from the guy in Porto."
        }
        XCTAssertEqual(seen.all, ["Budget all in, maybe two thousand.\n\nlugged steel from the guy in Porto"])
        XCTAssertNil(r.fallback)
        XCTAssertEqual(r.text, "# Touring bike build\n\nBudget all in: maybe two thousand.\n\n## Frame\n\nLugged steel from the guy in Porto.")
    }

    func testAHeadingInsideAParagraphKeepsItsLine() async throws {
        let body = "### Before\nbuy the clay and the glaze"
        let r = try await CopyEditV2.copyEdit(body, spoken: false, prompt: "P") { _, _, _ in "Buy the clay and the glaze." }
        XCTAssertEqual(r.text, "### Before\nBuy the clay and the glaze.")
    }

    func testAHeadingOnlyNoteNeedsNoModel() async throws {
        let r = try await CopyEditV2.copyEdit("# Just a heading", spoken: false, prompt: "P") { _, _, _ in "x" }
        XCTAssertFalse(r.calledModel)
        XCTAssertEqual(r.text, "# Just a heading")
    }

    func testAHashtagIsNotAHeading() {
        XCTAssertFalse(CopyEditV2.HeldLines.isHeld("#bikes and #project", typed: false))
        XCTAssertTrue(CopyEditV2.HeldLines.isHeld("## Frame", typed: false))
    }

    // MARK: - bold and italic

    func testBoldLabelsComeBackAroundTheirWords() async throws {
        let body = "**Pros:** it will last forever.\n**Cons:** it will take forever."
        let seen = Seen()
        let r = try await CopyEditV2.copyEdit(body, spoken: false, prompt: "P") { _, t, _ in
            seen.add(t); return "Pros: it will last forever.\nCons: it will take forever, honestly."
        }
        XCTAssertEqual(seen.all, ["Pros: it will last forever.\nCons: it will take forever."], "no markup reaches the model")
        XCTAssertNil(r.fallback)
        XCTAssertEqual(r.text, "**Pros:** it will last forever.\n**Cons:** it will take forever, honestly.")
    }

    func testItalicAndUnderscoreSpans() async throws {
        let body = "the *first* cut is the _cleanest_ one"
        let r = try await CopyEditV2.copyEdit(body, spoken: false, prompt: "P") { _, t, _ in
            XCTAssertEqual(t, "the first cut is the cleanest one")
            return "The first cut is the cleanest one."
        }
        XCTAssertEqual(r.text, "The *first* cut is the _cleanest_ one.")
    }

    func testAnEditThatLosesABoldSpanShipsHisWords() async throws {
        let body = "**Pros:** it will last forever. **Cons:** it will take forever."
        let r = try await CopyEditV2.copyEdit(body, spoken: false, prompt: "P") { _, _, _ in
            "Pro: it will last forever. Con: it will take forever."
        }
        XCTAssertEqual(r.fallback, .formattingLost)
        XCTAssertEqual(r.text, body, "his words, his markup")
    }

    func testSnakeCaseListMarkersAndLoneStarsAreNotEmphasis() {
        for s in ["call file_name_here today", "rate it 5 * 3 times", "my__init__file", "a*b*c"] {
            XCTAssertTrue(CopyEditV2.HeldEmphasis(s).spans.isEmpty, s)
            XCTAssertEqual(CopyEditV2.HeldEmphasis(s).prose, s)
        }
        XCTAssertEqual(CopyEditV2.HeldEmphasis("__really__ good").spans,
                       [.init(marker: "__", text: "really")])
    }

    // MARK: - the 40-word gap

    func testANoteOfExactlyFortyWordsIsCoveredByOneRule() {
        let kept = "The blue glaze is closer at cone five than at cone six and the kiln runs hot on the top shelf"
        let lost = "Lotte wants the spare wheel back before the long trip up north on Saturday morning early"
        let input = kept + ". " + lost + ". Bring the box."
        XCTAssertEqual(input.split(whereSeparator: \.isWhitespace).count, 40)
        let output = kept + ". Bring the box."
        XCTAssertFalse(PolishPrompts.lostTooMuch(input: input, output: output), "the shrink guard starts above 40")
        XCTAssertEqual(G.lostSentences(input: input, output: output), [lost + "."], "so the sentence rule covers 40")
    }

    // MARK: - the corpus note that showed it (applenote-headings-checklist)

    func testCorpusAppleNoteKeepsHeadingsAndBoldLabels() async throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: H.corpusRoot.appendingPathComponent("manifest.json").path),
                          "corpus not generated")
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("q501_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let list = try await CopyEditV2HarnessTests.V2Engine(calls: CopyEditV2HarnessTests.Calls())
            .run(corpus: H.corpusRoot, cache: H.cache, scratch: scratch)
        let bySlug = Dictionary(list.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })

        let note = try XCTUnwrap(bySlug["applenote-headings-checklist"]?.body)
        for line in ["# Touring bike build", "## Frame", "## Parts"] {
            XCTAssertTrue(note.components(separatedBy: "\n").contains(line), "keeps \(line)\n\(note)")
        }
        XCTAssertTrue(note.contains("**Pros:**") && note.contains("**Cons:**"), note)
        XCTAssertEqual(note.components(separatedBy: "\n").filter { $0.hasPrefix("- [") }.count, 4, note)

        let workshop = try XCTUnwrap(bySlug["typed-headings-and-tags"]?.body)
        for line in ["# October workshop", "## Before", "## Materials"] {
            XCTAssertTrue(workshop.components(separatedBy: "\n").contains(line), "keeps \(line)\n\(workshop)")
        }
    }
}
