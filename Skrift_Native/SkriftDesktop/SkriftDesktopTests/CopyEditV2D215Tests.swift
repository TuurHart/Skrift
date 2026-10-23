import XCTest

/// Q478 (gate+): D215 — the copy-edit keeps tasks, sentences, spelling and lists. Checkbox lines
/// never reach the model (held like pictures, put back in place); a note under 40 words that
/// loses a whole sentence falls back to his words; his spelling stays (the prompt says so, and
/// a respelled word falls back); a typed list stays a list (its lines are held too). Fillers and
/// "okay so" may still go. MLX-free: the corpus half replays the outputs `-recordcopyeditv2` recorded.
@MainActor
final class CopyEditV2D215Tests: XCTestCase {
    typealias H = CopyEditDiffHarnessTests
    typealias G = CopyEditV2.Gate

    static func answer(_ s: String) -> CopyEditV2.Generate { { _, _, _ in s } }

    final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [(prompt: String, input: String)] = []
        func add(_ p: String, _ i: String) { lock.lock(); list.append((p, i)); lock.unlock() }
        var all: [(prompt: String, input: String)] { lock.lock(); defer { lock.unlock() }; return list }
    }

    // MARK: - (1) checkbox lines are held like pictures

    func testCheckboxLinesNeverReachTheModelAndComeBackInPlace() async throws {
        let body = "Deze week\n\n- [ ] Marco bellen over de bedrading\n- [x] Order the grey clay body\n- [ ] Rose the website"
        let seen = Seen()
        let r = try await CopyEditV2.copyEdit(body, spoken: true, prompt: "P") { p, t, _ in
            seen.add(p, t); return "Deze week:"
        }
        XCTAssertEqual(seen.all.map(\.input), ["Deze week"], "no checkbox line reaches the model")
        XCTAssertNil(r.fallback)
        XCTAssertEqual(r.text, "Deze week:\n\n- [ ] Marco bellen over de bedrading\n- [x] Order the grey clay body\n- [ ] Rose the website",
                       "every box and its state, byte for byte")
    }

    func testCheckboxLinesInsideAParagraphKeepTheirLine() async throws {
        let body = "To do today:\n- [x] call the bank\nthen the rest:\n- [ ] post the parcel"
        let seen = Seen()
        let r = try await CopyEditV2.copyEdit(body, spoken: true, prompt: "P") { p, t, _ in
            seen.add(p, t); return "To do today:\nThen the rest:"
        }
        XCTAssertEqual(seen.all.map(\.input), ["To do today:\nthen the rest:"])
        XCTAssertEqual(r.text, "To do today:\n- [x] call the bank\nThen the rest:\n- [ ] post the parcel")
        // A model that reflows the paragraph: the boxes return at its edges, never lost.
        let reflowed = try await CopyEditV2.copyEdit(body, spoken: true, prompt: "P", generate: Self.answer("To do today, then the rest."))
        XCTAssertEqual(reflowed.text, "To do today, then the rest.\n- [x] call the bank\n- [ ] post the parcel")
    }

    func testCheckboxLinesBesideAPicture() async throws {
        let body = "Parts to order:\n\n- [ ] chain, 1/8\n- [ ] the rear hub, this one [[img_001]]\n- [x] new bell"
        let seen = Seen()
        let r = try await CopyEditV2.copyEdit(body, spoken: true, prompt: "P") { p, t, _ in
            seen.add(p, t); return "Parts to order:"
        }
        XCTAssertEqual(seen.all.map(\.input), ["Parts to order:"])
        XCTAssertEqual(r.text, "Parts to order:\n\n- [ ] chain, 1/8\n- [ ] the rear hub, this one\n- [x] new bell\n\n[[img_001]]")
    }

    func testAllCheckboxesNeedNoModel() async throws {
        let r = try await CopyEditV2.copyEdit("- [ ] one\n- [x] two", spoken: false, prompt: "P", generate: Self.answer("x"))
        XCTAssertFalse(r.calledModel)
        XCTAssertEqual(r.text, "- [ ] one\n- [x] two")
    }

    func testCheckboxesSurviveAFallback() async throws {
        let body = "Ask Lotte first.\n\n- [x] sand the frame"
        let r = try await CopyEditV2.copyEdit(body, spoken: true, prompt: "P", generate: Self.answer("Ask her first."))
        XCTAssertEqual(r.fallback, .nameOrNumberLost)
        XCTAssertEqual(r.text, body)
    }

    // MARK: - (2) a short note that loses a whole sentence

    func testAShortNoteLosingASentenceFallsBack() async throws {
        let body = "First thought. The blue is closer at cone five than at six.\n\nThird. Lotte's birthday is in three weeks."
        let edit = "The blue is closer at cone five than at six.\n\nLotte's birthday is in three weeks."
        let r = try await CopyEditV2.copyEdit(body, spoken: true, prompt: "P", generate: Self.answer(edit))
        XCTAssertEqual(r.fallback, .sentenceLost)
        XCTAssertEqual(r.text, body, "his words")
        XCTAssertEqual(G.lostSentences(input: body, output: edit), ["First thought.", "Third."])
        let raw = "A voice note whose stored title looks like a raw filename. The list must not show memo_ garbage."
        XCTAssertEqual(G.lostSentences(input: raw, output: "The list must not show memo garbage; a raw title loses."),
                       ["A voice note whose stored title looks like a raw filename."])
    }

    func testFillersAndOkaySoMayStillGo() async throws {
        let body = "Okay so, um, walking back from the shop and I think I've decided. Yeah. Okay."
        let r = try await CopyEditV2.copyEdit(body, spoken: true, prompt: "P",
                                              generate: Self.answer("Walking back from the shop, I think I've decided."))
        XCTAssertNil(r.fallback, "a sentence of fillers and discourse words may go (D215)")
        let long = Array(repeating: "The kiln ran hot today and the glaze crawled.", count: 5).joined(separator: " ") + " Third."
        XCTAssertEqual(G.lostSentences(input: long, output: "The kiln ran hot today."), [],
                       "40 words and up: the C33 shrink guard looks, not this rule")
    }

    // MARK: - (3) his spelling stays

    func testTheModelIsToldToKeepHisSpelling() async throws {
        let seen = Seen()
        _ = try await CopyEditV2.copyEdit("The colour is fine.", spoken: true, prompt: PolishPrompts.copyEdit) { p, t, _ in
            seen.add(p, t); return t
        }
        let prompt = try XCTUnwrap(seen.all.first?.prompt)
        XCTAssertTrue(prompt.hasPrefix(PolishPrompts.copyEdit), "the ONE prompt source (C39)")
        XCTAssertTrue(prompt.hasSuffix(PolishPrompts.keepSpelling))
        XCTAssertEqual(PolishPrompts.keepingSpelling(prompt), prompt, "added once")
        XCTAssertTrue(PolishPrompts.keepSpelling.contains("colour"))
    }

    func testARespelledWordFallsBack() async throws {
        let body = "Rose gold is not a colour for a bike shop."
        let r = try await CopyEditV2.copyEdit(body, spoken: true, prompt: "P",
                                              generate: Self.answer("Rose gold is not a color for a bike shop."))
        XCTAssertEqual(r.fallback, .respelled)
        XCTAssertEqual(r.text, body)
        XCTAssertEqual(G.respelled(input: "stop apologising to customers", output: "Stop apologizing to customers."),
                       ["apologising→apologizing"])
        XCTAssertEqual(G.respelled(input: "the centre of the grey travelling show", output: "The center of the gray traveling show."),
                       ["centre→center", "grey→gray", "travelling→traveling"])
        XCTAssertEqual(G.respelled(input: "I realize my favorite", output: "I realise my favourite."),
                       ["favorite→favourite", "realize→realise"], "either direction")
        XCTAssertEqual(G.respelled(input: "four hours for your tour", output: "For hours, for you."), [],
                       "four/for is not a spelling pair")
        XCTAssertEqual(G.respelled(input: "teh colour is off", output: "The colour is off."), [], "a typo fix is allowed")
    }

    // MARK: - (4) a typed list stays a list

    func testATypedListIsHeldAside() async throws {
        let body = "Boodschappen voor zaterdag\n\n- kaas\n- iets voor tante Ria haar verjaardag\n* bier voor Jack\n1. brood\n\nNiet vergeten: de fietstassen."
        let seen = Seen()
        let r = try await CopyEditV2.copyEdit(body, spoken: false, prompt: "P") { p, t, _ in
            seen.add(p, t); return "Boodschappen voor zaterdag:\n\nNiet vergeten: de fietstassen."
        }
        XCTAssertEqual(seen.all.map(\.input), ["Boodschappen voor zaterdag\n\nNiet vergeten: de fietstassen."])
        XCTAssertNil(r.fallback)
        XCTAssertEqual(r.text, "Boodschappen voor zaterdag:\n\n- kaas\n- iets voor tante Ria haar verjaardag\n* bier voor Jack\n1. brood\n\nNiet vergeten: de fietstassen.")
    }

    func testASpokenListIsStillEdited() async throws {
        let body = "Shopping:\n\n- cheese from the market"
        let seen = Seen()
        _ = try await CopyEditV2.copyEdit(body, spoken: true, prompt: "P") { p, t, _ in seen.add(p, t); return t }
        XCTAssertEqual(seen.all.map(\.input), [body], "only a typed note's plain list lines are held")
        XCTAssertEqual(CopyEditV2.HeldLines("no list here", typed: true).prose, "no list here")
    }

    func testNoQuoteReachesTheCopyEdit_C29() async throws {
        let seen = Seen()
        _ = try await CopyEditV2.copyEdit("> Kept quote.\n\nmy ramble about it", spoken: true, prompt: PolishPrompts.copyEdit) { p, t, _ in
            seen.add(p, t); return t
        }
        XCTAssertEqual(seen.all.map(\.input), ["my ramble about it"])
    }

    // MARK: - the corpus: the four notes of plan/reads/copyedit-v2.md

    private static var cached: [String: CopyEditCorpusRun.Result]?

    private func results() async throws -> [String: CopyEditCorpusRun.Result] {
        if let done = Self.cached { return done }
        try XCTSkipUnless(FileManager.default.fileExists(atPath: H.corpusRoot.appendingPathComponent("manifest.json").path),
                          "corpus not generated")
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("q478_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let list = try await CopyEditV2HarnessTests.V2Engine(calls: CopyEditV2HarnessTests.Calls())
            .run(corpus: H.corpusRoot, cache: H.cache, scratch: scratch)
        let bySlug = Dictionary(list.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
        Self.cached = bySlug
        return bySlug
    }

    static func lines(_ s: String, matching pattern: String) -> [String] {
        s.components(separatedBy: "\n").filter { $0.range(of: pattern, options: .regularExpression) != nil }
    }

    func testCorpusTypedTasksKeepsEveryBox() async throws {
        let r = try XCTUnwrap(try await results()["typed-tasks"])
        let input = try XCTUnwrap(r.input), body = try XCTUnwrap(r.body)
        let boxes = #"^\s*- \[[ xX]\]"#
        XCTAssertEqual(Self.lines(input, matching: boxes).count, 6)
        // Name-linking may wrap "Mariam" in the shipped body; the box and its state are what D215 keeps.
        XCTAssertEqual(Self.lines(body, matching: boxes).map { String($0.prefix(5)) },
                       Self.lines(input, matching: boxes).map { String($0.prefix(5)) }, body)
        let pic = try XCTUnwrap(try await results()["pic-in-task-list"]?.body)
        XCTAssertEqual(Self.lines(pic, matching: boxes).count, 4, pic)
    }

    func testCorpusShortNotesKeepEverySentence() async throws {
        let recs = try await results()
        for slug in ["voice-en-paragraphed-by-pauses", "voice-en-raw-title"] {
            let r = try XCTUnwrap(recs[slug], slug)
            let input = CopyEditV2.prose(try XCTUnwrap(r.input, slug)), body = CopyEditV2.prose(try XCTUnwrap(r.body, slug))
            XCTAssertEqual(G.lostSentences(input: input, output: body), [], "\(slug)\n\(body)")
        }
    }

    func testCorpusSpellingStays() async throws {
        let recs = try await results()
        for (slug, word) in [("voice-en-names-all-tiers", "colour"), ("typed-blockquote-ordinary", "apologising")] {
            let body = try XCTUnwrap(recs[slug]?.body, slug)
            XCTAssertTrue(H.words(body).contains(word), "\(slug) keeps \(word)\n\(body)")
        }
    }

    func testCorpusTypedListStaysAList() async throws {
        let r = try XCTUnwrap(try await results()["typed-dutch-boodschappen"])
        let body = try XCTUnwrap(r.body)
        XCTAssertEqual(Self.lines(body, matching: #"^- "#).count, 5, body)
        XCTAssertTrue(body.contains("haar verjaardag"), "his words in the list stay his (\"Ria haar\" never becomes \"Ria's\")")
    }
}
