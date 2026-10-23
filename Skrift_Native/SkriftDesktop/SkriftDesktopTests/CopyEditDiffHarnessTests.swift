import XCTest

/// Q423 (gate+): the copy-edit harness's shared half — the twin of `BodyDiffHarnessTests` and
/// `ReconcileDiffHarnessTests`. MLX-free.
///
/// C7 / C286: every model call was recorded once by the MLX app as
/// `test-fixtures/corpus/goldens/model/<sha256(prompt+input)>.txt`; v1's shipped title, summary
/// and body per note stay as `goldens/v1-copyedit/<slug>.txt`, the reference every engine is
/// classed against (C5). v1 itself was deleted after the `v1-copyedit` tag (Q427, C2); the one
/// engine left is copy-edit v2 (`CopyEditV2HarnessTests`), which runs C5, C30 and C35 over the
/// corpus. This file keeps the corpus paths, the cache, the C30 / C35 rules and C40.
///
/// Re-record (synthetic corpus only, in-memory store, MLX app built in Debug):
/// `"<derived data>/Build/Products/Debug/Skrift Dev.app/Contents/MacOS/Skrift Dev"
///  -isolatedRun -recordcopyeditv2 <repo>/test-fixtures/corpus`
@MainActor
final class CopyEditDiffHarnessTests: XCTestCase {

    // MARK: - the engine protocol

    /// One copy-edit implementation runnable over the corpus (copy-edit v2 is the one left).
    protocol CopyEditEngine {
        var name: String { get }
        @MainActor func run(corpus: URL, cache: ModelOutputCache, scratch: URL) async throws -> [CopyEditCorpusRun.Result]
    }

    static var corpusRoot: URL { CorpusSeed.fixtureRoot(file: #filePath) }
    static var goldenDir: URL { corpusRoot.appendingPathComponent("goldens/v1-copyedit", isDirectory: true) }
    static var cache: ModelOutputCache {
        ModelOutputCache(directory: corpusRoot.appendingPathComponent("goldens/model", isDirectory: true))
    }

    /// slug → [SPEC id] where an engine is expected to differ from v1's golden (C5).
    static func loadExpectedDifferences() throws -> [String: [String]] {
        let url = corpusRoot.appendingPathComponent("expected-differences-copyedit.json")
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        var out: [String: [String]] = [:]
        for (key, value) in obj where !key.hasPrefix("_") { out[key] = (value as? [String]) ?? [] }
        return out
    }

    /// C7: the key is sha256(prompt + input), and a miss names its key instead of passing silently.
    func testCacheKeyAndMiss_C7() async throws {
        XCTAssertEqual(ModelOutputCache.key(prompt: "", input: ""),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(ModelOutputCache.key(prompt: "ab", input: "c"), ModelOutputCache.key(prompt: "a", input: "bc"))
        let empty = ModelOutputCache(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("q423_empty_\(UUID().uuidString)"))
        do {
            _ = try await empty.replay("prompt", "input", 64)
            XCTFail("a miss must throw")
        } catch let miss as ModelOutputCache.Miss {
            XCTAssertEqual(miss.key, ModelOutputCache.key(prompt: "prompt", input: "input"))
            XCTAssertTrue(miss.localizedDescription.contains(miss.key))
        }
        // C286: the baseline exists and every recorded file is a sha256 name.
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.cache.directory.path)
        XCTAssertGreaterThan(files.count, 100)
        for f in files { XCTAssertNotNil(f.range(of: "^[0-9a-f]{64}\\.txt$", options: .regularExpression), f) }
    }

    // MARK: - C30: each picture returns after the same-index paragraph

    private static let pictureLine = "^\\[\\[img_\\d+\\]\\]$"

    /// Each picture marker → the number of text paragraphs it returns after, and whether it
    /// stands as its own paragraph. A picture paragraph returns after the text paragraphs before
    /// it; a marker inline in text paragraph i (v1's Mac rows keep phone markers inline) belongs
    /// to that paragraph, so it returns after i + 1.
    static func pictureIndex(_ text: String) -> [String: (after: Int, standalone: Bool)] {
        var out: [String: (after: Int, standalone: Bool)] = [:]
        var textParas = 0
        for block in text.components(separatedBy: "\n\n") {
            let t = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if t.range(of: pictureLine, options: .regularExpression) != nil {
                out[t] = (textParas, true); continue
            }
            textParas += 1
            for m in t.matches(of: #/\[\[img_\d+\]\]/#) { out[String(t[m.range])] = (textParas, false) }
        }
        return out
    }

    /// The C30 rule on one note: every picture of the input is its own paragraph in the output,
    /// after the same number of text paragraphs (clamped to the output's paragraph count).
    static func c30Violations(input: String, output: String) -> [String] {
        let inIdx = pictureIndex(input), outIdx = pictureIndex(output)
        let outText = output.components(separatedBy: "\n\n").filter {
            let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !t.isEmpty && t.range(of: pictureLine, options: .regularExpression) == nil
        }.count
        var bad: [String] = []
        for (marker, want) in inIdx.sorted(by: { $0.key < $1.key }) {
            guard let got = outIdx[marker] else { bad.append("\(marker) missing"); continue }
            guard got.standalone else { bad.append("\(marker) inside a paragraph"); continue }
            let k = min(want.after, outText)
            if got.after != k { bad.append("\(marker) after paragraph \(got.after), input had \(k)") }
        }
        return bad
    }

    static let c30Slugs = ["pic-wall", "pic-three-spread"]

    /// The rule itself, on a hand-made case (so the pin is not only as good as v1's data).
    func testC30RuleOnAHandMadeCase() {
        let input = "One two.\n\n[[img_001]]\n\nThree four.\n\nFive.\n\n[[img_002]]"
        XCTAssertEqual(Self.c30Violations(input: input, output: "One.\n\n[[img_001]]\n\nThree.\n\nFive.\n\n[[img_002]]"), [])
        XCTAssertEqual(Self.c30Violations(input: input, output: "One.\n\n[[img_001]]\n\nThree five.\n\n[[img_002]]"), [],
                       "fewer output paragraphs: clamped to the end")
        XCTAssertEqual(Self.c30Violations(input: input, output: "One.\n\nThree.\n\n[[img_001]]\n\nFive.\n\n[[img_002]]"),
                       ["[[img_001]] after paragraph 2, input had 1"])
        XCTAssertEqual(Self.c30Violations(input: input, output: "One [[img_001]] two.\n\nThree.\n\nFive."),
                       ["[[img_001]] inside a paragraph", "[[img_002]] missing"])
        // A marker inline in input paragraph 1 returns after output paragraph 1 (v1's Mac rows).
        let inline = "One [[img_001]] two. Three [[img_002]] four."
        XCTAssertEqual(Self.c30Violations(input: inline, output: "One two.\n\n[[img_001]]\n\n[[img_002]]\n\nThree four."), [])
        XCTAssertEqual(Self.c30Violations(input: inline, output: "One two.\n\n[[img_001]]\n\nThree four.\n\n[[img_002]]"),
                       ["[[img_002]] after paragraph 2, input had 1"])
    }

    // MARK: - C35: numbers, names and every non-filler word survive

    static let fillers: Set<String> = ["um", "uh", "eh", "uhm", "erm", "hmm", "mm"]

    /// Lower-cased words, `[[Target|shown]]` / `[[Target]]` read as what the reader sees.
    static func words(_ s: String) -> [String] {
        let shown = s.replacing(#/\[\[(?:[^\]|]*\|)?([^\]]*)\]\]/#) { String($0.output.1) }
        return shown.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'’")).inverted)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'’")) }
            .filter { !$0.isEmpty }
    }

    static func c35Lost(input: String, output: String) -> [String] {
        let kept = Set(words(output))
        var seen = Set<String>(), lost: [String] = []
        for w in words(input) where !fillers.contains(w) && seen.insert(w).inserted && !kept.contains(w) {
            lost.append(w)
        }
        return lost
    }

    static let c35Slugs = ["voice-en-pricing-ramble", "voice-mix-code-switch"]

    func testC35RuleOnAHandMadeCase() {
        XCTAssertEqual(Self.c35Lost(input: "Um, Jack said fifteen, uh, fifteen percent", output: "[[Jack Smith|Jack]] said fifteen percent."), [])
        XCTAssertEqual(Self.c35Lost(input: "zes mensen, six people", output: "six people"), ["zes", "mensen"])
    }

    // MARK: - C40: Process on an unrated note floors it to 0.1; nothing is re-polished

    func testProcessOnUnratedFloorsAndNeverRePolishes_C40() async throws {
        let manifest = try JSONDecoder().decode(CorpusSeed.Manifest.self,
                                                from: Data(contentsOf: Self.corpusRoot.appendingPathComponent("manifest.json")))
        var unrated: [String] = []
        for entry in manifest.notes {
            let note = try JSONDecoder().decode(CorpusSeed.Note.self, from: Data(contentsOf: Self.corpusRoot
                .appendingPathComponent("notes").appendingPathComponent(entry.folder).appendingPathComponent("note.json")))
            if note.deletedAt == nil, !NoteConsent.isRated(note.significance) { unrated.append(entry.slug) }
        }
        XCTAssertGreaterThanOrEqual(unrated.count, 3, "the corpus carries unrated notes")
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("q427_c40_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let list = try await CopyEditV2HarnessTests.V2Engine(calls: CopyEditV2HarnessTests.Calls())
            .run(corpus: Self.corpusRoot, cache: Self.cache, scratch: scratch)
        let recs = Dictionary(list.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
        for slug in unrated {
            let r = try XCTUnwrap(recs[slug], slug)
            XCTAssertEqual(r.significance ?? -1, NoteConsent.processFloor, "\(slug): Process floors to 0.1")
            XCTAssertTrue(r.hasRow, "\(slug): a floored note gets its Mac row")
        }
        for (slug, r) in recs where r.hasRow {
            XCTAssertFalse(r.needsProcessingAfter && r.error == nil,
                           "\(slug): processed, yet the Mac would pick it up again (C40)")
        }
        // A rated note is never lowered by Process.
        XCTAssertEqual(NoteConsent.flooredByProcess(0.7), 0.7)
        XCTAssertEqual(NoteConsent.flooredByProcess(nil), NoteConsent.processFloor)
        XCTAssertEqual(NoteConsent.flooredByProcess(0), NoteConsent.processFloor)
    }
}
