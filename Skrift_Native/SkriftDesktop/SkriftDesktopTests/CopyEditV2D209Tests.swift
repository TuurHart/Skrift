import XCTest

/// Q449 (gate+): D209 — the copy-edit falls back to the unedited words only on real damage: a
/// translation (language flip), a lost name or number, an invented proper noun, a re-paragraphed
/// typed note, or the C33 shrink guard. A dropped ordinary word ships with the edit. MLX-free:
/// the corpus half replays the outputs Q423/Q424 recorded.
@MainActor
final class CopyEditV2D209Tests: XCTestCase {
    typealias H = CopyEditDiffHarnessTests
    typealias G = CopyEditV2.Gate

    static func answer(_ s: String) -> CopyEditV2.Generate { { _, _, _ in s } }

    // MARK: - hand-made cases

    func testADroppedOrdinaryWordShipsTheEdit_D209() async throws {
        let body = "Okay so, um, walking back from the shop and I think I've decided. Yeah."
        let edit = "Walking back from the shop, I think I've decided."
        let r = try await CopyEditV2.copyEdit(body, spoken: true, prompt: "P", generate: Self.answer(edit))
        XCTAssertNil(r.fallback, "small dropped words are the price of a model (D209)")
        XCTAssertEqual(r.text, edit)
        XCTAssertEqual(Set(G.lostWords(input: body, output: edit)), ["okay", "so", "and", "yeah"], "still reported")
    }

    func testFillersAreRemovable_C35() async throws {
        let body = "Um, uh, eh, the kiln is fine."
        let r = try await CopyEditV2.copyEdit(body, spoken: true, prompt: "P", generate: Self.answer("The kiln is fine."))
        XCTAssertNil(r.fallback)
        XCTAssertEqual(r.text, "The kiln is fine.")
    }

    func testALostNumberFallsBack_D209() async throws {
        let body = "Overhauls go to one sixty and tune-ups stay at 45 euros."
        let lostWord = try await CopyEditV2.copyEdit(body, spoken: true, prompt: "P",
                                                     generate: Self.answer("Overhauls go up and tune-ups stay at 45 euros."))
        XCTAssertEqual(lostWord.fallback, .nameOrNumberLost)
        XCTAssertEqual(lostWord.text, body, "the words ship unedited")
        let lostDigits = try await CopyEditV2.copyEdit(body, spoken: true, prompt: "P",
                                                       generate: Self.answer("Overhauls go to one sixty and tune-ups stay the same."))
        XCTAssertEqual(lostDigits.fallback, .nameOrNumberLost)
        XCTAssertEqual(G.lostNamesOrNumbers(input: "zes mensen en vier planken", output: "mensen en planken"), ["zes", "vier"])
    }

    func testALostNameFallsBack_D209() async throws {
        let body = "Then I told Lotte about the trailer and Jack said fine."
        let r = try await CopyEditV2.copyEdit(body, spoken: true, prompt: "P",
                                              generate: Self.answer("Then I told her about the trailer and Jack said fine."))
        XCTAssertEqual(r.fallback, .nameOrNumberLost)
        XCTAssertEqual(r.text, body)
        // A possessive keeps its name; a sentence-initial capital is not read as a name.
        XCTAssertEqual(G.lostNamesOrNumbers(input: "I asked Mariam's colleagues.", output: "I asked Mariam."), [])
        XCTAssertEqual(G.lostNamesOrNumbers(input: "Okay. So it went well.", output: "It went well."), [])
        XCTAssertEqual(G.lostNamesOrNumbers(input: "we met Bruno Castel there", output: "We met Bruno there."), ["castel"])
    }

    func testAnInventedNameOrATranslationFallsBack_C177() async throws {
        let invented = try await CopyEditV2.copyEdit("i told lotte about it", spoken: true, prompt: "P",
                                                     generate: Self.answer("I told Lotte and Bruno about it."))
        XCTAssertEqual(invented.fallback, .newProperNoun)
        let mix = "Dus ik zat te denken, the Saturday workshop, like properly clean, so that's six people, zes mensen."
        let flipped = try await CopyEditV2.copyEdit(mix, spoken: true, prompt: "P",
                                                    generate: Self.answer("Dus ik zat te denken, de Saturday workshop, echt schoon, dat zijn zes mensen."))
        XCTAssertNotNil(flipped.fallback)
        XCTAssertEqual(flipped.text, mix)
    }

    func testATypedNoteIsNeverReparagraphed_C34() async throws {
        let typed = "One thing.\n\nTwo things."
        let r = try await CopyEditV2.copyEdit(typed, spoken: false, prompt: "P", generate: Self.answer("One thing. Two things."))
        XCTAssertEqual(r.fallback, .typedReparagraphed)
        XCTAssertEqual(r.text, typed)
    }

    // MARK: - the corpus

    /// One line per copy-edited note: what shipped and why — the source of plan/reads/copyedit-v2.md.
    func testCorpusFallsBackOnlyOnRealDamage_D209() async throws {
        let manifestURL = H.corpusRoot.appendingPathComponent("manifest.json")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: manifestURL.path), "corpus not generated")
        let manifest = try JSONDecoder().decode(CorpusSeed.Manifest.self, from: Data(contentsOf: manifestURL))
        var fellBack: [String: CopyEditV2.Fallback] = [:]
        var shipped = 0
        for entry in manifest.notes {
            let note = try JSONDecoder().decode(CorpusSeed.Note.self, from: Data(contentsOf: H.corpusRoot
                .appendingPathComponent("notes").appendingPathComponent(entry.folder).appendingPathComponent("note.json")))
            guard note.kind != "capture", note.kind != "conversation" else { continue }   // no copy-edit (C36)
            let body = note.transcript ?? ""
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            var output = ""
            let replay = H.cache.replay
            let generate: CopyEditV2.Generate = { p, t, cap in
                let o = try await replay(p, t, cap)
                if p == PolishPrompts.copyEdit { output = o }
                return o
            }
            let r: CopyEditV2.Result
            do {
                r = try await CopyEditV2.copyEdit(body, spoken: note.kind != "typed", prompt: PolishPrompts.copyEdit,
                                                  generate: generate)
            } catch is ModelOutputCache.Miss {
                continue   // a body the corpus "ASR" rewrote before the model read it: covered by the harness
            }
            guard r.calledModel else { continue }
            let input = CopyEditV2.prose(QuoteProtection.splitLeadingQuote(body)?.ramble ?? body)
            let out = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let dropped = G.lostWords(input: input, output: out)
            let damage = G.lostNamesOrNumbers(input: input, output: out) + G.newProperNouns(input: input, output: out)
            if let why = r.fallback {
                fellBack[entry.slug] = why
                print("D209 FALLBACK \(entry.slug): \(why.rawValue) | names/numbers: \(damage) | dropped: \(dropped)")
            } else {
                shipped += 1
                print("D209 EDIT \(entry.slug) | dropped: \(dropped)")
            }
        }
        print("D209: edit ships \(shipped), falls back \(fellBack.count)")
        XCTAssertNil(fellBack["voice-en-pricing-ramble"], "the pricing ramble ships the model's edit")
        XCTAssertNotNil(fellBack["voice-mix-code-switch"], "the code-switch translation is still caught")
    }
}
