import XCTest

/// Q11 (gate+): body v2 registered in the Q10 harness. Runs `BodyV2.committed` over BOTH
/// corpus mapping sets (`manifest.json` + `expected-differences.json`, and Q23's additive
/// `manifest-q23.json` + `expected-differences-q23.json`) and classes every note against v1's
/// recorded golden exactly as `BodyDiffHarnessTests` does (C5): identical / expected-different /
/// unexplained, plus the mirror failure (a registered R row v2 leaves equal to v1). Kept as its
/// own file because `BodyDiffHarnessTests.engines` is a protected `let`.
///
/// Beyond the golden: v2 must equal every `expect_body.txt` (the settled v2 text), must be
/// idempotent on EVERY note (no snap-gap excuses — C17 deletes the snap), and must keep every
/// picture its own paragraph and every word of the input.
final class BodyV2HarnessTests: XCTestCase {

    // MARK: - the engine

    struct V2Engine: BodyDiffHarnessTests.BodyEngine {
        let name = "v2"
        func body(for note: CorpusSeed.Note, folder: URL) throws -> String {
            BodyV2.committed(try Self.input(for: note, folder: folder))
        }

        static func input(for note: CorpusSeed.Note, folder: URL, text: String? = nil) throws -> BodyV2.Input {
            var words: [WordTiming] = []
            if let wt = note.wordTimings {
                words = try JSONDecoder().decode([WordTiming].self, from: Data(contentsOf: folder.appendingPathComponent(wt)))
            }
            var manifest: [ImageManifestEntry] = []
            if let data = note.metadata.data, let meta = try? JSONDecoder().decode(MemoMetadata.self, from: data) {
                manifest = meta.imageManifest ?? []
            }
            let source: BodyV2.Source = note.kind == "typed" ? .typed : note.kind == "capture" ? .shareCapture : .speech
            return BodyV2.Input(text: text ?? note.transcript ?? "", words: words, manifest: manifest,
                                source: source, userEdited: note.transcriptUserEdited)
        }
    }

    // MARK: - the corpus rows

    struct Row {
        let slug: String
        let folder: URL
        let note: CorpusSeed.Note
        let golden: String
        let expectBody: String?
        let rIDs: [String]        // Q10 / Q23 registrations
        let clauseIDs: [String]   // Q11 additive registrations
    }

    static func loadClauseDifferences() throws -> [String: [String]] {
        let url = BodyGoldenTests.corpusRoot.appendingPathComponent("expected-differences-q11.json")
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        var out: [String: [String]] = [:]
        for (key, value) in obj where !key.hasPrefix("_") { out[key] = (value as? [String]) ?? [] }
        return out
    }

    func rows() throws -> [Row] {
        let root = BodyGoldenTests.corpusRoot
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path),
                          "corpus not generated — run test-fixtures/corpus/generate.py")
        let sets: [(URL, [String: [String]])] = [
            (root.appendingPathComponent("manifest.json"), try BodyDiffHarnessTests.loadExpectedDifferences()),
            (BodyGoldenQ23Tests.manifestURL, try BodyGoldenQ23Tests.loadExpectedDifferences()),
        ]
        let clauses = try Self.loadClauseDifferences()
        var out: [Row] = []
        for (manifestURL, expected) in sets {
            let manifest = try JSONDecoder().decode(CorpusSeed.Manifest.self, from: Data(contentsOf: manifestURL))
            for entry in manifest.notes {
                let folder = root.appendingPathComponent("notes").appendingPathComponent(entry.folder)
                let note = try JSONDecoder().decode(CorpusSeed.Note.self,
                                                    from: Data(contentsOf: folder.appendingPathComponent("note.json")))
                let golden = try String(contentsOf: BodyGoldenTests.goldenDir.appendingPathComponent("\(entry.slug).txt"),
                                        encoding: .utf8)
                let expect = (try? String(contentsOf: folder.appendingPathComponent("expect_body.txt"), encoding: .utf8))?
                    .trimmingCharacters(in: .newlines)
                out.append(Row(slug: entry.slug, folder: folder, note: note, golden: golden, expectBody: expect,
                               rIDs: expected[entry.slug] ?? [], clauseIDs: clauses[entry.slug] ?? []))
            }
        }
        return out
    }

    /// Whitespace-blind comparison form: C19, then no space beside a line break.
    static func canonical(_ s: String) -> String {
        BodyV2Text.normalised(s).replacingOccurrences(of: #" ?\n ?"#, with: "\n", options: .regularExpression)
    }

    // MARK: - known conflicts (each self-expiring: the test fails once the conflict is gone)

    /// `pic-in-task-list` was registered for an R row, but the SPEC makes v2 equal v1 here (it's
    /// a list, so C20 leaves it unparagraphed, and D3 puts the picture after the item — exactly
    /// where v1's golden already has it). D141: R95 dropped from `expected-differences.json`
    /// (protected, approved) — nothing left to carve out here.
    static let registrationConflicts: Set<String> = []

    /// D140 resolved three of these (the picture now lands before the sentence, matching
    /// `expect_body.txt`, not after it per the old C11-only reading):
    /// - pic-at-start: 0.40 s is within the first 1.0 s of the only sentence (starts at 0.0) → top.
    /// - pic-ocr-text: 3.02 s is within the first 1.0 s of "Grey body…" (starts 3.015 s) → before it.
    /// - pic-three-spread: img_003 at 13.27 s is within the first 1.0 s of "Friday night job."
    ///   (starts 12.935 s) → before it.
    /// Still open:
    /// - ingress-p3-five-clips-one-picture: 10.70 s is inside "pick" of sentence 4; the fixture
    ///   carries no clip boundaries, so the share-order place (C12) is not in the input.
    static let expectBodyConflicts: Set<String> = [
        "ingress-p3-five-clips-one-picture",
    ]

    // MARK: - C5 classification against v1's golden

    func testV2ClassificationAgainstV1Golden() throws {
        let engine = V2Engine()
        var identical = 0, expectedDifferent = 0
        var unexplained: [String] = [], matchedBug: [String] = [], staleClause: [String] = [], notWhitespaceOnly: [String] = []
        for row in try rows() {
            let v2 = try engine.body(for: row.note, folder: row.folder)
            if v2 == row.golden {
                identical += 1
                if !row.rIDs.isEmpty, !Self.registrationConflicts.contains(row.slug) {
                    matchedBug.append("\(row.slug): still equals v1 on registered \(row.rIDs)")
                }
                if !row.clauseIDs.isEmpty { staleClause.append("\(row.slug): listed for \(row.clauseIDs) but v2 == v1") }
            } else if row.rIDs.isEmpty, row.clauseIDs.isEmpty {
                unexplained.append("\(row.slug): v2 differs from v1 with no registered id")
            } else {
                expectedDifferent += 1
                if row.rIDs.isEmpty, row.clauseIDs == ["C19"], Self.canonical(v2) != Self.canonical(row.golden) {
                    notWhitespaceOnly.append("\(row.slug): registered C19-only but differs beyond whitespace")
                }
            }
        }
        for slug in Self.registrationConflicts {
            let row = try XCTUnwrap(try rows().first { $0.slug == slug })
            XCTAssertEqual(try engine.body(for: row.note, folder: row.folder), row.golden,
                           "\(slug): conflict resolved — remove it from registrationConflicts")
        }
        print("BodyV2 harness: identical \(identical), expected-different \(expectedDifferent), unexplained \(unexplained.count)")
        XCTAssertTrue(unexplained.isEmpty, "unexplained (C5):\n" + unexplained.joined(separator: "\n"))
        XCTAssertTrue(matchedBug.isEmpty, "unfixed registered bugs (C5):\n" + matchedBug.joined(separator: "\n"))
        XCTAssertTrue(staleClause.isEmpty, staleClause.joined(separator: "\n"))
        XCTAssertTrue(notWhitespaceOnly.isEmpty, notWhitespaceOnly.joined(separator: "\n"))
    }

    // MARK: - the settled v2 text

    func testV2MatchesExpectBody() throws {
        let engine = V2Engine()
        var checked = 0
        for row in try rows() {
            guard let expected = row.expectBody else { continue }
            let v2 = try engine.body(for: row.note, folder: row.folder)
            if Self.expectBodyConflicts.contains(row.slug) {
                XCTAssertNotEqual(v2, expected, "\(row.slug): conflict resolved — remove it from expectBodyConflicts")
                continue
            }
            checked += 1
            XCTAssertEqual(v2, expected, row.slug)
        }
        XCTAssertGreaterThan(checked, 10)
    }

    // MARK: - C6 invariants, on every note, no excuses

    func testV2IsIdempotent() throws {
        let engine = V2Engine()
        for row in try rows() {
            let once = try engine.body(for: row.note, folder: row.folder)
            let twice = BodyV2.committed(try V2Engine.input(for: row.note, folder: row.folder, text: once))
            XCTAssertEqual(once, twice, "\(row.slug): v2 is not a fixed point on its own output")
        }
    }

    func testV2PicturesAreOwnParagraphsAndWordsSurvive() throws {
        for row in try rows() {
            let input = try V2Engine.input(for: row.note, folder: row.folder)
            let v2 = BodyV2.committed(input)
            let ns = v2 as NSString
            for m in BodyV2Marker.regex.matches(in: v2, range: NSRange(location: 0, length: ns.length)) {
                let n = Int(ns.substring(with: m.range(at: 1))) ?? 0
                guard n >= 1, n <= input.manifest.count else { continue }       // literal text, not a picture
                let start = m.range.location, end = m.range.location + m.range.length
                XCTAssertTrue(start == 0 || ns.substring(with: NSRange(location: start - 2, length: 2)) == "\n\n",
                              "\(row.slug): [[img_\(n)]] not paragraph-led")
                XCTAssertTrue(end == ns.length || ns.substring(with: NSRange(location: end, length: 2)) == "\n\n",
                              "\(row.slug): [[img_\(n)]] not paragraph-trailed")
            }
            // Every picture the input had is still there; a timed speech note has all of them.
            let inputPics = Set(BodyV2Marker.numbers(in: input.text).filter { $0 >= 1 && $0 <= input.manifest.count })
            let outPics = BodyV2Marker.numbers(in: v2).filter { $0 >= 1 && $0 <= input.manifest.count }
            XCTAssertEqual(outPics.count, Set(outPics).count, "\(row.slug): a picture appears twice")
            XCTAssertTrue(inputPics.isSubset(of: Set(outPics)), "\(row.slug): a picture was dropped")
            if input.source == .speech, !input.userEdited, !input.words.isEmpty {
                XCTAssertEqual(Set(outPics), Set((0..<input.manifest.count).map { $0 + 1 }),
                               "\(row.slug): a timed note must carry every manifest picture")
            }
            // Words in = words out (pictures and whitespace aside).
            func words(_ s: String) -> [String] {
                let pics = BodyV2Marker.runs(in: s, manifestCount: input.manifest.count)
                let (bare, _) = BodyV2.lift(s, runs: pics)
                return bare.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            }
            XCTAssertEqual(words(v2), words(input.text), "\(row.slug): words changed")
        }
    }

    // MARK: - synthetic clause checks

    func testMarkerWidth_C15() {
        XCTAssertEqual(BodyV2Marker.literal(7), "[[img_007]]")
        XCTAssertEqual(BodyV2Marker.literal(1234), "[[img_1234]]")
        XCTAssertEqual(BodyV2Marker.numbers(in: "a [[img_1]] b [[img_0042]] c [[img_1000]]"), [1, 42, 1000])
    }

    func testWhitespaceAtCommit_C19() {
        XCTAssertEqual(BodyV2Text.normalised("a \t b\r\nc\n\n\n\nd\u{00A0}e  \n"), "a b\nc\n\nd e")
    }

    func testParagraphGapIsTwoSeconds_C20() {
        func w(_ word: String, _ s: Double, _ e: Double) -> WordTiming { WordTiming(word: word, start: s, end: e) }
        let short = [w("One.", 0, 1), w("Two.", 2.9, 3.5)]      // 1.9 s pause: no break
        let long = [w("One.", 0, 1), w("Two.", 3.0, 3.5)]       // 2.0 s pause: break
        XCTAssertEqual(BodyV2.committed(.init(text: "One. Two.", words: short, source: .speech)), "One. Two.")
        XCTAssertEqual(BodyV2.committed(.init(text: "One. Two.", words: long, source: .speech)), "One.\n\nTwo.")
        XCTAssertEqual(BodyV2.committed(.init(text: "One. Two.", words: long, source: .typed)), "One. Two.",
                       "typed text is never paragraphed")
        XCTAssertEqual(BodyV2.committed(.init(text: "One.\nTwo.", words: long, source: .speech)), "One.\nTwo.",
                       "text that already has a newline is untouched")
    }

    /// D142: img_001/img_002 at 0.5 s fall inside "A cat."'s first 1.0 s (that sentence starts
    /// at t=0), so D140 puts them BEFORE it — merging with img_003 (offset 0, already top).
    func testTimedPictureAfterSpokenSentence_C11_C13() {
        func w(_ word: String, _ s: Double) -> WordTiming { WordTiming(word: word, start: s, end: s + 0.3) }
        let words = [w("A", 0), w("cat.", 0.4), w("A", 0.8), w("dog.", 1.2)]
        let pics = [ImageManifestEntry(filename: "a", offsetSeconds: 0.5), ImageManifestEntry(filename: "b", offsetSeconds: 0.5),
                    ImageManifestEntry(filename: "c", offsetSeconds: 0)]
        XCTAssertEqual(BodyV2.committed(.init(text: "A cat. A dog.", words: words, manifest: pics, source: .speech)),
                       "[[img_003]]\n\n[[img_001]]\n\n[[img_002]]\n\nA cat. A dog.")
    }

    func testThumbnail_C170() {
        let all: (Int) -> Bool = { _ in true }
        XCTAssertEqual(BodyV2Thumbnail.pick(body: "x\n\n[[img_002]]\n\n[[img_001]]", manifestCount: 2, source: .speech, resolves: all), 2)
        XCTAssertEqual(BodyV2Thumbnail.pick(body: "[[img_001]]\n\n[[img_002]]", manifestCount: 2, source: .speech,
                                            resolves: { $0 == 2 }), 2)
        XCTAssertNil(BodyV2Thumbnail.pick(body: "all markers deleted", manifestCount: 2, source: .speech, resolves: all))
        XCTAssertEqual(BodyV2Thumbnail.pick(body: "no marker", manifestCount: 1, source: .shareCapture, resolves: all), 1)
        XCTAssertNil(BodyV2Thumbnail.pick(body: "[[img_001]]", manifestCount: 1, source: .typed, resolves: all))
    }

    // MARK: - Tuur's read (plan/reads/body-v2.md)

    /// `SKRIFT_WRITE_READS=1` (plain env var, `xcrun xctest` run — see BodyGoldenTests) writes
    /// every note whose v2 body differs from v1's golden, v1 and v2 one after the other.
    func testWriteBodyV2Read() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SKRIFT_WRITE_READS"] == "1", "set SKRIFT_WRITE_READS=1")
        let engine = V2Engine()
        func quoted(_ s: String) -> String {
            s.isEmpty ? "> (empty)" : s.components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n")
        }
        var sections: [String] = []
        var total = 0
        for row in try rows() {
            total += 1
            let v2 = try engine.body(for: row.note, folder: row.folder)
            guard v2 != row.golden else { continue }
            var why = (row.rIDs + row.clauseIDs).joined(separator: ", ")
            if Self.expectBodyConflicts.contains(row.slug) { why += " — v2 differs from expect_body.txt (see top)" }
            sections.append("## \(row.slug)\n\n\(why)\n\n**v1**\n\n\(quoted(row.golden))\n\n**v2**\n\n\(quoted(v2))\n")
        }
        let head = """
        # Body v2 beside v1 — every note whose body changed

        \(sections.count) of \(total) corpus notes change. v1 = the recorded golden (v1's stored body + its display/export snap). \
        v2 = `BodyV2.committed`, what v2 would store. A blank quote line is a paragraph break.

        Read first — ingress-p3 is the one note left where v2 (C11 + D140) and the fixture's expected \
        text disagree: 10.70 s is inside sentence 4; the fixture has no clip boundaries, so v2 cannot \
        know the share-order place (C12). D140 (a picture within the first 1.0 s of the sentence being \
        spoken lands before it, not after) resolved the other three: pic-at-start, pic-ocr-text, \
        pic-three-spread now match `expect_body.txt`. pic-in-task-list is not below: v2 equals v1 there \
        (after the list item, D3); its stale R95 registration was dropped (D141).

        Generated by `BodyV2HarnessTests.testWriteBodyV2Read`.


        """
        let url = BodyGoldenTests.corpusRoot.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("plan/reads/body-v2.md")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (head + sections.joined(separator: "\n")).write(to: url, atomically: true, encoding: .utf8)
    }
}
