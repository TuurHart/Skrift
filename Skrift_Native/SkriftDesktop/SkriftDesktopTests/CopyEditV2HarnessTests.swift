import XCTest

/// Q424 (gate+): copy-edit v2 registered in the Q423 harness. Its own file because
/// `CopyEditDiffHarnessTests.engines` is a protected `let` (the Q11 precedent). MLX-free: the
/// recorded model outputs replay (C7); a miss fails and names its key.
///
/// C5: every note is classed against v1's golden — identical / expected-different / unexplained —
/// with the registrations of `expected-differences-copyedit.json` (Q423) plus the additive
/// `expected-differences-copyedit-v2.json`; a registered note v2 leaves equal to v1 fails.
/// On top: C30 and C35 with NO v1 carve-outs, C34's paragraph ledger, C29/C178 on every model
/// input, and the rules of C31/C32/C33/C36/C37/C38/C177 on hand-made cases.
@MainActor
final class CopyEditV2HarnessTests: XCTestCase {
    typealias H = CopyEditDiffHarnessTests

    /// Every model call v2 made in the replayed corpus run: (prompt, input).
    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [(prompt: String, input: String)] = []
        func add(_ p: String, _ i: String) { lock.lock(); list.append((p, i)); lock.unlock() }
        var all: [(prompt: String, input: String)] { lock.lock(); defer { lock.unlock() }; return list }
    }

    struct V2Engine: CopyEditDiffHarnessTests.CopyEditEngine {
        let name = "v2"
        let calls: Calls
        func run(corpus: URL, cache: ModelOutputCache, scratch: URL) async throws -> [CopyEditCorpusRun.Result] {
            let replay = cache.replay, calls = calls
            let generate: CopyEditV2.Generate = { prompt, text, cap in
                calls.add(prompt, text)
                return try await replay(prompt, text, cap)
            }
            return try await CopyEditCorpusRun.run(corpus: corpus, enhancer: GenerateEnhancer(generate: generate),
                                                   scratch: scratch, step: CopyEditV2Mac.corpusStep(generate: generate))
        }
    }

    private static let calls = Calls()
    private static var cached: [String: CopyEditCorpusRun.Result]?

    private func results() async throws -> [String: CopyEditCorpusRun.Result] {
        if let done = Self.cached { return done }
        try XCTSkipUnless(FileManager.default.fileExists(atPath: H.corpusRoot.appendingPathComponent("manifest.json").path),
                          "corpus not generated")
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("q424_v2_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        do {
            let list = try await V2Engine(calls: Self.calls).run(corpus: H.corpusRoot, cache: H.cache, scratch: scratch)
            let bySlug = Dictionary(list.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
            Self.cached = bySlug
            return bySlug
        } catch let miss as ModelOutputCache.Miss {
            print("CopyEditV2Harness CACHE MISS key=\(miss.key)")
            XCTFail(miss.localizedDescription)
            throw miss
        }
    }

    static func additiveDifferences() throws -> [String: [String]] {
        let url = H.corpusRoot.appendingPathComponent("expected-differences-copyedit-v2.json")
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        var out: [String: [String]] = [:]
        for (key, value) in obj where !key.hasPrefix("_") { out[key] = (value as? [String]) ?? [] }
        return out
    }

    static func manifest() throws -> CorpusSeed.Manifest {
        try JSONDecoder().decode(CorpusSeed.Manifest.self, from: Data(contentsOf: H.corpusRoot.appendingPathComponent("manifest.json")))
    }

    static func note(_ entry: CorpusSeed.Manifest.Entry) throws -> CorpusSeed.Note {
        try JSONDecoder().decode(CorpusSeed.Note.self, from: Data(contentsOf: H.corpusRoot
            .appendingPathComponent("notes").appendingPathComponent(entry.folder).appendingPathComponent("note.json")))
    }

    // MARK: - C5: classed against v1's golden

    func testEveryNoteAgainstV1Golden_C5() async throws {
        let recs = try await results()
        var expected = try H.loadExpectedDifferences()
        for (slug, ids) in try Self.additiveDifferences() { expected[slug, default: []] += ids }
        var identical = 0, expectedDifferent = 0
        var unexplained: [String] = [], matchedBug: [String] = [], missing: [String] = []
        for entry in try Self.manifest().notes {
            guard let golden = try? String(contentsOf: H.goldenDir.appendingPathComponent("\(entry.slug).txt"), encoding: .utf8)
            else { missing.append(entry.slug); continue }
            let mine = try XCTUnwrap(recs[entry.slug], entry.slug).record
            let registered = expected[entry.slug] ?? []
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
        print("CopyEditDiffHarness[v2]: identical \(identical), expected-different \(expectedDifferent), unexplained \(unexplained.count)")
        XCTAssertTrue(missing.isEmpty, "no golden for \(missing)")
        XCTAssertTrue(unexplained.isEmpty, "v2 unexplained (C5):\n" + unexplained.joined(separator: "\n"))
        XCTAssertTrue(matchedBug.isEmpty, "v2 unfixed registered bugs (C5):\n" + matchedBug.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(identical + expectedDifferent, 100)
    }

    // MARK: - C30 / C35 with no carve-outs

    func testPicturesReturnAfterSameIndexParagraph_C30() async throws {
        let recs = try await results()
        for slug in H.c30Slugs {
            let r = try XCTUnwrap(recs[slug], slug)
            let input = try XCTUnwrap(r.input, slug), body = try XCTUnwrap(r.body, slug)
            XCTAssertEqual(H.c30Violations(input: input, output: body), [], "v2 \(slug) breaks C30\n\(body)")
        }
    }

    /// C35 as D209 reads it: names and numbers survive; a dropped ordinary word is the price of a model.
    func testNumbersNamesAndWordsSurvive_C35() async throws {
        let recs = try await results()
        for slug in H.c35Slugs {
            let r = try XCTUnwrap(recs[slug], slug)
            let input = try XCTUnwrap(r.input, slug), body = try XCTUnwrap(r.body, slug)
            XCTAssertNil(r.error, slug)
            XCTAssertEqual(CopyEditV2.Gate.lostNamesOrNumbers(input: CopyEditV2.prose(input), output: CopyEditV2.prose(body)), [],
                           "v2 \(slug) lost a name or a number (C35, D209)\n\(body)")
        }
    }

    // MARK: - C34: the paragraph ledger on the corpus

    func testParagraphLedger_C34() async throws {
        let recs = try await results()
        func textParas(_ s: String) -> Int {
            CopyEditV2.paragraphs(s).filter { $0.range(of: #"^\[\[img_\d+\]\]$"#, options: .regularExpression) == nil }.count
        }
        for entry in try Self.manifest().notes {
            guard let r = recs[entry.slug], r.hasRow, let input = r.input, let body = r.body, r.error == nil else { continue }
            let kind = try Self.note(entry).kind
            guard kind != "capture", kind != "conversation" else { continue }   // no copy-edit (C36)
            if kind == "typed" {
                XCTAssertEqual(textParas(body), textParas(input), "\(entry.slug): a typed note is never re-paragraphed")
            } else {
                XCTAssertGreaterThanOrEqual(textParas(body), textParas(input), "\(entry.slug): shipped ≥ in")
            }
        }
        let wall = try XCTUnwrap(recs["voice-en-asr-wall"]?.body)
        XCTAssertGreaterThan(textParas(wall), 1, "the spoken wall is broken")
        let typed = try XCTUnwrap(recs["typed-wall-7k"])
        XCTAssertEqual(textParas(try XCTUnwrap(typed.body)), textParas(try XCTUnwrap(typed.input)))
    }

    // MARK: - C29 / C178: what the model saw

    func testNoLinkNoPictureNoQuoteReachesTheModel_C29_C178() async throws {
        _ = try await results()
        let calls = Self.calls.all
        XCTAssertGreaterThan(calls.count, 100)
        for c in calls {
            XCTAssertFalse(c.input.contains("[["), "a [[ ]] reached the model:\n\(c.input)")
            if c.prompt == PolishPrompts.copyEdit {
                XCTAssertNil(QuoteProtection.splitLeadingQuote(c.input), "a quote block reached the copy-edit:\n\(c.input)")
            }
        }
    }

    func testShareAndConversationGetNoCopyEdit_C36() async throws {
        let recs = try await results()
        for entry in try Self.manifest().notes {
            let kind = try Self.note(entry).kind
            guard let r = recs[entry.slug], r.hasRow, let input = r.input, let body = r.body else { continue }
            if kind == "conversation" || kind == "capture" {
                // Name-linking may wrap "Nadia's" as "[[Nadia Okafor]]'s": read possessives as their name.
                let lost = H.c35Lost(input: input, output: body).filter { w in
                    !(w.hasSuffix("'s") && H.words(body).contains(String(w.dropLast(2))))
                }
                XCTAssertEqual(lost, [], "\(entry.slug): its words are untouched")
            }
        }
        XCTAssertEqual(CopyEditCorpusRun.Result.fields(of: try XCTUnwrap(recs["voice-en-three-words"]).record)["summary"], "",
                       "three words: no summary (C36)")
    }

    // MARK: - hand-made cases

    /// An identity model, a recording model, a fixed answer.
    static func echo(_ calls: Calls? = nil) -> CopyEditV2.Generate {
        { p, t, _ in calls?.add(p, t); return t }
    }
    static func answer(_ s: String) -> CopyEditV2.Generate { { _, _, _ in s } }

    func testIdentityRoundTripsEveryEscrow_C29() async throws {
        let body = "> The quote, kept.\n\nSee [[memo:6F9619FF-8B86-D011-B42D-00C04FC964FF|the kiln note]] and [[Lotte Vos|Lotte]].\n\n[[img_001]]\n\nSecond [[Bruno Castel]] part."
        let calls = Calls()
        let r = try await CopyEditV2.copyEdit(body, spoken: true, prompt: "P", generate: Self.echo(calls))
        XCTAssertNil(r.fallback)
        XCTAssertEqual(r.text, body)
        XCTAssertEqual(calls.all.map(\.input), ["See the kiln note and Lotte.\n\nSecond Bruno Castel part."])
    }

    func testPicturesByIndexAndAnchorsGone_C30() async throws {
        let body = "One. [[img_001]] Two.\n\n[[img_002]]\n\nThree."
        let held = CopyEditV2.Held(body)
        XCTAssertEqual(held.pictures, [.init(marker: "[[img_001]]", after: 1), .init(marker: "[[img_002]]", after: 1)])
        XCTAssertEqual(held.placePictures("One. Two.\n\nThree."), "One. Two.\n\n[[img_001]]\n\n[[img_002]]\n\nThree.")
        XCTAssertEqual(CopyEditV2.Held("[[img_001]]\n\nText.").placePictures("Text."), "[[img_001]]\n\nText.")
        let r = try await CopyEditV2.copyEdit("[[img_001]]", spoken: true, prompt: "P", generate: Self.answer("x"))
        XCTAssertFalse(r.calledModel, "a picture-only body has nothing to edit")
    }

    func testLostLinkOrChangedQuoteShipsUnedited_C31() async throws {
        let body = "Ask [[Lotte Vos|Lotte]] about it, she knows the answer."
        let r = try await CopyEditV2.copyEdit(body, spoken: true, prompt: "P",
                                              generate: Self.answer("Ask her about it, she knows the answer."))
        XCTAssertEqual(r.text, body)
        XCTAssertNotNil(r.fallback)
        let quoted = "> Kept quote.\n\nmy ramble about it"
        let q = try await CopyEditV2.copyEdit(quoted, spoken: true, prompt: "P", generate: Self.answer("> Changed quote.\n\nmy ramble about it"))
        XCTAssertTrue(q.text.hasPrefix("> Kept quote.\n\n"), "the quote is the original bytes, never the model's")
        let only = try await CopyEditV2.copyEdit("> Only a quote.", spoken: true, prompt: "P", generate: Self.answer("x"))
        XCTAssertFalse(only.calledModel, "a quote-only capture never calls the model")
    }

    func testTruncatedAndShrunkShipTheOriginal_C32_C33() async throws {
        let long = Array(repeating: "word", count: 60).joined(separator: " ")
        let cap = PolishPrompts.copyEditTokenBudget(forInput: long)
        XCTAssertEqual(cap, 1024)
        let cut = try await CopyEditV2.copyEdit(long, spoken: true, prompt: "P",
                                                generate: Self.answer(String(repeating: "x", count: cap * 4)))
        XCTAssertEqual(cut.text, long)
        XCTAssertEqual(cut.fallback, .truncated)
        let shrunk = try await CopyEditV2.copyEdit(long, spoken: true, prompt: "P", generate: Self.answer("word word"))
        XCTAssertEqual(shrunk.text, long)
        XCTAssertEqual(shrunk.fallback, .shrank)
    }

    func testWallBreakIsSpokenOnly_C34() async throws {
        let wall = Array(repeating: "This sentence keeps the wall going on and on.", count: 16).joined(separator: " ")
        let spoken = try await CopyEditV2.copyEdit(wall, spoken: true, prompt: "P", generate: Self.echo())
        XCTAssertGreaterThan(CopyEditV2.paragraphs(spoken.text).count, 1)
        XCTAssertEqual(spoken.ledger, .init(input: 1, model: 1, shipped: CopyEditV2.paragraphs(spoken.text).count))
        let typed = try await CopyEditV2.copyEdit(wall, spoken: false, prompt: "P", generate: Self.echo())
        XCTAssertEqual(typed.text, wall, "a typed wall is never re-paragraphed")
        let merged = try await CopyEditV2.copyEdit("One thing.\n\nTwo things.", spoken: true, prompt: "P",
                                                   generate: Self.answer("One thing. Two things."))
        XCTAssertEqual(merged.fallback, .paragraphsLost)
    }

    func testPostConditions_C177_C35() {
        let mix = "Dus ik zat te denken, the Saturday workshop, like properly clean, so that's six people, zes mensen."
        XCTAssertTrue(CopyEditV2.Gate.languageFlipped(input: mix, output: "Dus ik zat te denken, de zaterdag workshop, echt schoon, dat zijn zes mensen."))
        XCTAssertFalse(CopyEditV2.Gate.languageFlipped(input: mix, output: mix))
        XCTAssertEqual(CopyEditV2.Gate.newProperNouns(input: "i told lotte about it", output: "I told Lotte and Bruno about it."), ["Bruno"])
        XCTAssertEqual(CopyEditV2.Gate.newProperNouns(input: "so we met. then home", output: "We met. Then home."), [])
        XCTAssertEqual(CopyEditV2.Gate.lostWords(input: "Okay so, um, fifteen percent. Yeah.", output: "Fifteen percent."),
                       ["okay", "so", "yeah"])
        XCTAssertEqual(CopyEditV2.Gate.lostWords(input: "Um, uh, fifteen, fifteen percent", output: "Fifteen percent."), [])
    }

    func testPassRules_C36_C37_C38() async throws {
        let calls = Calls()
        let short = try await CopyEditV2.runPass(.init(body: "Three words here.", source: .spoken), generate: Self.echo(calls))
        XCTAssertEqual(short.summary, "", "under 75 words: no summary")
        XCTAssertEqual(calls.all.count, 2, "copy-edit + title")
        let forced = try await CopyEditV2.runPass(.init(body: "Three words here.", source: .spoken, forceSummary: true),
                                                  generate: Self.echo())
        XCTAssertFalse(forced.summary.isEmpty, "manual Redo forces the summary")
        let share = try await CopyEditV2.runPass(.init(body: "A link I liked.", source: .share), generate: Self.echo())
        XCTAssertNil(share.edit)
        XCTAssertEqual(share.copyedit, "")
        let bare = try await CopyEditV2.runPass(.init(body: "  ", source: .share, fallbackTitle: "Example.com"), generate: Self.answer("x"))
        XCTAssertEqual(bare.title, "Example.com")
        let conv = try await CopyEditV2.runPass(.init(body: "**Lotte:** hi there", source: .conversation), generate: Self.answer("T"))
        XCTAssertEqual(conv.copyedit, "**Lotte:** hi there")
        let kept = try await CopyEditV2.runPass(.init(body: "Hello.", source: .typed, currentTitle: "Mine"), generate: Self.answer("Hello."))
        XCTAssertEqual(kept.title, "Mine")
        XCTAssertEqual(kept.titleSuggested, "Hello.")
        // C37: one stamped enhancement per pass, even an empty one.
        let empty = try await CopyEditV2.runPass(.init(body: "", source: .spoken), generate: Self.answer("x"))
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let e = try XCTUnwrap(CopyEditV2.enhancement(of: empty, deviceID: "mac", now: now))
        XCTAssertEqual(e.processedAt, now)
        XCTAssertTrue(e.isProcessed)
        // C38: an edit during the run discards it; nothing is written.
        let edited = try await CopyEditV2.runPass(.init(body: "Hello.", source: .spoken), generate: Self.echo()) { true }
        XCTAssertTrue(edited.discarded)
        XCTAssertNil(CopyEditV2.enhancement(of: edited, deviceID: "mac", now: now))
        XCTAssertEqual(CopyEditV2.work(for: .process, polished: false), .polish)
        XCTAssertEqual(CopyEditV2.work(for: .process, polished: true), .nothing)
        XCTAssertEqual(CopyEditV2.work(for: .phoneEdit, polished: true), .relinkAndCompile)
    }

    func testTailOrder_C178() {
        var order: [String] = []
        let tags = CopyEditV2.runTail(working: "w", tagText: "t", .init(
            tags: { order.append("tags:\($0)"); return ["a"] },
            nameLink: { order.append("link:\($0)") },
            compile: { order.append("compile") }))
        XCTAssertEqual(order, ["tags:t", "link:w", "compile"])
        XCTAssertEqual(tags, ["a"])
    }

    func testOnePromptSource_C39() {
        XCTAssertEqual(CopyEditV2.Prompts.standard,
                       .init(copyEdit: PolishPrompts.copyEdit, title: PolishPrompts.title, summary: PolishPrompts.summary))
    }
}
