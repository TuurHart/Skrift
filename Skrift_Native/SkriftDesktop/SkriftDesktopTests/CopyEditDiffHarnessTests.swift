import XCTest

/// Q423 (gate+): the copy-edit harness — the copy-edit twin of `BodyDiffHarnessTests` and
/// `ReconcileDiffHarnessTests`. MLX-free.
///
/// C7 / C286: every model call v1 made over the synthetic corpus was recorded once by the MLX
/// app (`-recordcopyedit`) as `test-fixtures/corpus/goldens/model/<sha256(prompt+input)>.txt`;
/// v1's shipped title, summary and body per note are `goldens/v1-copyedit/<slug>.txt`.
/// C5: every registered engine replays those outputs over the seeded corpus and each note is
/// classed identical / expected-different / unexplained against v1's golden; a cache miss
/// fails and prints its key. C30, C35, C40 are pinned on top.
///
/// Re-record (v1 only, synthetic corpus only, in-memory store, MLX app built in Debug):
/// `"<derived data>/Build/Products/Debug/Skrift Dev.app/Contents/MacOS/Skrift Dev"
///  -isolatedRun -corpus <repo>/test-fixtures/corpus -recordcopyedit <repo>/test-fixtures/corpus/goldens`
@MainActor
final class CopyEditDiffHarnessTests: XCTestCase {

    // MARK: - the engine protocol

    /// One copy-edit implementation runnable over the corpus (v1 today; v2 registers here).
    protocol CopyEditEngine {
        var name: String { get }
        @MainActor func run(corpus: URL, cache: ModelOutputCache, scratch: URL) async throws -> [CopyEditCorpusRun.Result]
    }

    /// v1 = the shipping `BatchRunner` + `CopyEditPipeline` with the recorded outputs replayed.
    struct V1CopyEditEngine: CopyEditEngine {
        let name = "v1"
        func run(corpus: URL, cache: ModelOutputCache, scratch: URL) async throws -> [CopyEditCorpusRun.Result] {
            try await CopyEditCorpusRun.run(corpus: corpus, enhancer: GenerateEnhancer(generate: cache.replay),
                                            scratch: scratch)
        }
    }

    static let engines: [CopyEditEngine] = [V1CopyEditEngine()]

    static var corpusRoot: URL { CorpusSeed.fixtureRoot(file: #filePath) }
    static var goldenDir: URL { corpusRoot.appendingPathComponent("goldens/v1-copyedit", isDirectory: true) }
    static var cache: ModelOutputCache {
        ModelOutputCache(directory: corpusRoot.appendingPathComponent("goldens/model", isDirectory: true))
    }

    /// slug → [SPEC id] where a NON-v1 engine is expected to differ from v1's golden. v1 is the
    /// golden itself, so the matched-bug rule (C5) applies to every other engine.
    static func loadExpectedDifferences() throws -> [String: [String]] {
        let url = corpusRoot.appendingPathComponent("expected-differences-copyedit.json")
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        var out: [String: [String]] = [:]
        for (key, value) in obj where !key.hasPrefix("_") { out[key] = (value as? [String]) ?? [] }
        return out
    }

    // MARK: - one replayed run per engine (cached: the corpus run is the expensive part)

    private static var runs: [String: [String: CopyEditCorpusRun.Result]] = [:]

    private func results(_ engine: CopyEditEngine) async throws -> [String: CopyEditCorpusRun.Result] {
        if let done = Self.runs[engine.name] { return done }
        try XCTSkipUnless(FileManager.default.fileExists(atPath: Self.corpusRoot.appendingPathComponent("manifest.json").path),
                          "corpus not generated — run test-fixtures/corpus/generate.py")
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("q423_\(engine.name)_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        do {
            let list = try await engine.run(corpus: Self.corpusRoot, cache: Self.cache, scratch: scratch)
            let bySlug = Dictionary(list.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
            Self.runs[engine.name] = bySlug
            return bySlug
        } catch let miss as ModelOutputCache.Miss {
            print("CopyEditDiffHarness[\(engine.name)] CACHE MISS key=\(miss.key)")
            XCTFail("\(engine.name): \(miss.localizedDescription)")
            throw miss
        }
    }

    // MARK: - C5 / C7 / C286: every engine against v1's golden

    func testEveryNoteAgainstV1Golden_C5() async throws {
        let expected = try Self.loadExpectedDifferences()
        let manifest = try JSONDecoder().decode(CorpusSeed.Manifest.self,
                                                from: Data(contentsOf: Self.corpusRoot.appendingPathComponent("manifest.json")))
        for engine in Self.engines {
            let recs = try await results(engine)
            var identical = 0, expectedDifferent = 0
            var unexplained: [String] = [], matchedBug: [String] = [], missing: [String] = []
            for entry in manifest.notes {
                guard let golden = try? String(contentsOf: Self.goldenDir.appendingPathComponent("\(entry.slug).txt"),
                                               encoding: .utf8) else { missing.append(entry.slug); continue }
                let mine = try XCTUnwrap(recs[entry.slug], entry.slug).record
                let registered = engine.name == "v1" ? [] : (expected[entry.slug] ?? [])
                if mine == golden {
                    identical += 1
                    if !registered.isEmpty { matchedBug.append("\(entry.slug): still equals v1 on registered \(registered)") }
                } else if registered.isEmpty {
                    let a = CopyEditCorpusRun.Result.fields(of: mine), b = CopyEditCorpusRun.Result.fields(of: golden)
                    let diffs = Set(a.keys).union(b.keys).filter { a[$0] != b[$0] }.sorted()
                    unexplained.append("\(entry.slug): \(diffs.joined(separator: ", "))")
                } else {
                    expectedDifferent += 1
                }
            }
            print("CopyEditDiffHarness[\(engine.name)]: identical \(identical), expected-different \(expectedDifferent), unexplained \(unexplained.count)")
            XCTAssertTrue(missing.isEmpty, "\(engine.name): no golden for \(missing) — re-record with -recordcopyedit")
            XCTAssertTrue(unexplained.isEmpty, "\(engine.name) unexplained (C5):\n" + unexplained.joined(separator: "\n"))
            XCTAssertTrue(matchedBug.isEmpty, "\(engine.name) unfixed registered bugs (C5):\n" + matchedBug.joined(separator: "\n"))
            XCTAssertGreaterThanOrEqual(identical + expectedDifferent, 100, "\(engine.name): the whole corpus is classed")
        }
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

    /// Each picture marker → how many text paragraphs precede it (nil: not its own paragraph).
    static func pictureIndex(_ text: String) -> [String: Int?] {
        var out: [String: Int?] = [:]
        var textParas = 0
        for block in text.components(separatedBy: "\n\n") {
            let t = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if t.range(of: pictureLine, options: .regularExpression) != nil { out[t] = textParas; continue }
            let markers = t.matches(of: #/\[\[img_\d+\]\]/#).map { String(t[$0.range]) }
            for m in markers { out[m] = .some(nil) }
            textParas += 1
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
        for (marker, k) in inIdx.sorted(by: { $0.key < $1.key }) {
            guard let k else { continue }
            guard let placed = outIdx[marker] else { bad.append("\(marker) missing"); continue }
            guard let got = placed else { bad.append("\(marker) inside a paragraph"); continue }
            if got != min(k, outText) { bad.append("\(marker) after paragraph \(got), input had \(k)") }
        }
        return bad
    }

    static let c30Slugs = ["pic-wall", "pic-three-spread"]

    /// v1's 6-word anchors (R3) break C30 on these notes. Self-expiring: if v1 stops breaking
    /// it on one, the test fails until the entry is removed.
    static let v1KnownC30Violations: Set<String> = ["pic-wall", "pic-three-spread"]

    func testPicturesReturnAfterSameIndexParagraph_C30() async throws {
        for engine in Self.engines {
            let recs = try await results(engine)
            for slug in Self.c30Slugs {
                let r = try XCTUnwrap(recs[slug], slug)
                let input = try XCTUnwrap(r.input, "\(slug): no row"), body = try XCTUnwrap(r.body, slug)
                XCTAssertFalse(Self.pictureIndex(input).isEmpty, "\(slug): the input has pictures")
                let bad = Self.c30Violations(input: input, output: body)
                if engine.name == "v1", Self.v1KnownC30Violations.contains(slug) {
                    XCTAssertFalse(bad.isEmpty, "v1 \(slug): now satisfies C30 — drop it from v1KnownC30Violations")
                } else {
                    XCTAssertEqual(bad, [], "\(engine.name) \(slug) breaks C30")
                }
            }
        }
    }

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

    /// Words v1's recorded copy-edit drops on the C35 notes (self-expiring: a word v1 keeps
    /// again fails the test until removed here).
    static let v1KnownC35Losses: [String: Set<String>] = [:]

    func testNumbersNamesAndWordsSurvive_C35() async throws {
        for engine in Self.engines {
            let recs = try await results(engine)
            for slug in Self.c35Slugs {
                let r = try XCTUnwrap(recs[slug], slug)
                let input = try XCTUnwrap(r.input, "\(slug): no row"), body = try XCTUnwrap(r.body, slug)
                XCTAssertNil(r.error, "\(slug)")
                let lost = Set(Self.c35Lost(input: input, output: body))
                let known = engine.name == "v1" ? (Self.v1KnownC35Losses[slug] ?? []) : []
                XCTAssertEqual(lost.subtracting(known), [], "\(engine.name) \(slug) lost words (C35)\nbody:\n\(body)")
                XCTAssertEqual(known.subtracting(lost), [], "\(engine.name) \(slug): keeps a registered loss again — update v1KnownC35Losses")
            }
        }
    }

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
        for engine in Self.engines {
            let recs = try await results(engine)
            for slug in unrated {
                let r = try XCTUnwrap(recs[slug], slug)
                XCTAssertEqual(r.significance ?? -1, NoteConsent.processFloor, "\(engine.name) \(slug): Process floors to 0.1")
                XCTAssertTrue(r.hasRow, "\(engine.name) \(slug): a floored note gets its Mac row")
            }
            for (slug, r) in recs where r.hasRow {
                XCTAssertFalse(r.needsProcessingAfter && r.error == nil,
                               "\(engine.name) \(slug): processed, yet the Mac would pick it up again (C40)")
            }
        }
        // A rated note is never lowered by Process.
        XCTAssertEqual(NoteConsent.flooredByProcess(0.7), 0.7)
        XCTAssertEqual(NoteConsent.flooredByProcess(nil), NoteConsent.processFloor)
        XCTAssertEqual(NoteConsent.flooredByProcess(0), NoteConsent.processFloor)
    }
}
