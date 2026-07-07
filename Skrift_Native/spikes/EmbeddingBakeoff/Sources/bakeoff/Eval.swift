import Foundation

// The P8 chunk-0 bake-off eval: realistic Skrift-style memos (EN / NL / mixed) with
// distractors, and queries whose expected top-1 is known. Bar (JOURNAL_RETRIEVAL_PLAN.md):
// >= 8/10 queries top-1 in the expected set, clear same-topic vs unrelated margin,
// cross-language pairs land near same-language ones.

struct Bail: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

protocol SpikeEmbedder {
    var name: String { get }
    func embed(_ text: String, isQuery: Bool) throws -> [Float]
}

struct Doc {
    let id: String
    let distractor: Bool
    let text: String
}

struct Query {
    let text: String
    let expected: Set<String>
    let note: String
}

let corpus: [Doc] = [
    Doc(id: "pricing-en", distractor: false, text:
        "Should Skrift cost money? People don't value free tools, but charging for my own note-taking app feels weird. Maybe a tiny one-time price is the honest middle ground."),
    Doc(id: "pricing-nl", distractor: false, text:
        "Besloten: 69 cent, geen in-app aankopen. Goedkoop genoeg dat niemand twijfelt over de aankoop, duur genoeg dat het geen gratis-app-verwachting wekt. Eenmalig betalen, klaar."),
    Doc(id: "subs-en", distractor: false, text:
        "Subscriptions feel wrong for a notes app. A tool that holds your thoughts shouldn't stop working when you stop paying. One-time purchase or nothing."),
    Doc(id: "fiets-nl", distractor: false, text:
        "Fietslease uitzoeken voor het derde kwartaal. Of ik de fiets zakelijk via de zaak moet leasen of toch privé kopen. De maandbedragen lijken mee te vallen maar verzekering zit er niet bij."),
    Doc(id: "cloudkit-en", distractor: false, text:
        "Standup ramble: CloudKit sync latency is seconds, not instant like Apple Notes. Push on edit helped but the reconcile on the Mac still adds delay. Question is whether seconds is fine."),
    Doc(id: "airpods-en", distractor: false, text:
        "The AirPods recording bug again. The audio tap has to be validated with the input format, not the output format, otherwise the recording comes out silent after a route change."),
    Doc(id: "sourdough-en", distractor: false, text:
        "Dinner with Jack and Jack at Hotel du Vin. Jack's sourdough starter theory again: you don't own a starter, you just host it for a while. Great evening, too much wine."),
    Doc(id: "sapiens-quote", distractor: false, text:
        "From Sapiens: there are no gods, no nations, no money and no human rights, except in our collective imagination. My ramble: money as a shared fiction — believing in the value is what creates the value."),
    Doc(id: "walk-en", distractor: false, text:
        "Walk ramble in Jardim da Estrela: the standalone bet. The phone alone has to be the whole product, no Mac required. Mac and Obsidian become optional sinks, not requirements."),
    Doc(id: "apartment-mix", distractor: false, text:
        "Bezichtiging in Campo de Ourique vanmiddag. The landlord wants three months deposit which is steep, maar de lichtinval is ongelooflijk. Kitchen is small but the office room faces the garden."),
    Doc(id: "garden-nl", distractor: true, text:
        "De tomatenplanten op het balkon krijgen te weinig zon. Misschien moet ik ze verplaatsen naar de andere hoek en de basilicum binnen zetten. Water geven blijft lastig met deze hitte."),
    Doc(id: "workout-en", distractor: true, text:
        "Gym plan for the week: push pull legs, then two rest days. Bench felt heavy on Monday, probably the bad sleep. Add face pulls for the shoulder and stretch after every session."),
    Doc(id: "recipe-nl", distractor: true, text:
        "Recept voor stamppot boerenkool met rookworst zoals oma hem maakte. Aardappels niet te fijn stampen, flinke klont boter, spekjes apart uitbakken en de jus bewaren."),
    // One long memo where the payoff is buried at the END — the chunking test.
    // "long-full" = whole memo embedded as one vector; "long-tail" = just its final chunk.
    Doc(id: "long-full", distractor: false, text: longMemo),
    Doc(id: "long-tail", distractor: false, text: longMemoTail),
]

let longMemoTail =
    "Which brings me to the real decision: Skrift needs an Export All button. One action that dumps every note to Markdown so you can walk away with all your data. Portability is the escape hatch that makes the paid app fair."

let longMemo =
    """
    Long walk today, lots of loose threads. First the sync pill thing, the status still says waiting sometimes even though everything already arrived on the Mac, cosmetic but it erodes trust in the app. Then I was thinking about the reading mode font sizes, the serif option feels more book-like but the line spacing needs work at the biggest size. Had a call with Marco about the studio space, he thinks the rent is negotiable if we take the longer contract, need to see the numbers first. The tomatoes on the balcony are struggling again which is annoying but predictable. Also the onboarding still mentions pairing a Mac which is outdated now that everything goes through iCloud, someone should rewrite those three screens. Random idea during the walk: what if the record button had a tiny long-press menu for conversation mode instead of the toggle buried in settings. Anyway most of this is noise. \(longMemoTail)
    """

let queries: [Query] = [
    Query(text: "how should skrift cost money",
          expected: ["pricing-en", "pricing-nl", "subs-en"], note: "EN → EN/NL pricing cluster"),
    Query(text: "waarom voelt een abonnement verkeerd voor een notitie app",
          expected: ["subs-en", "pricing-nl", "pricing-en"], note: "NL query → EN doc (cross-lang)"),
    Query(text: "bike lease through the company or private",
          expected: ["fiets-nl"], note: "EN query → NL doc (cross-lang)"),
    Query(text: "why is sync between my devices slow",
          expected: ["cloudkit-en"], note: "paraphrase, no shared keywords"),
    Query(text: "bluetooth earbuds recording problem",
          expected: ["airpods-en"], note: "AirPods never named"),
    Query(text: "what did that book say about money being made up",
          expected: ["sapiens-quote"], note: "quote retrieval"),
    Query(text: "that dinner conversation about baking bread",
          expected: ["sourdough-en"], note: "episodic memory phrasing"),
    Query(text: "kan ik al mijn notities exporteren en meenemen",
          expected: ["long-tail", "long-full"], note: "NL → buried tail of a long memo"),
    Query(text: "my training schedule this week",
          expected: ["workout-en"], note: "distractor should win here"),
    Query(text: "will the app work without a mac",
          expected: ["walk-en"], note: "standalone bet"),
]

// ── math ──

func normalize(_ v: [Float]) -> [Float] {
    let n = sqrt(v.reduce(Float(0)) { $0 + $1 * $1 })
    guard n > 0 else { return v }
    return v.map { $0 / n }
}

func cosine(_ a: [Float], _ b: [Float]) -> Float {
    zip(a, b).reduce(Float(0)) { $0 + $1.0 * $1.1 } // both unit-normalized
}

// ── runner ──

struct EvalSummary {
    let engine: String
    let top1: Int
    let queryCount: Int
    let expectedMean: Float
    let distractorMean: Float
    let crossLangHits: Int
    let crossLangCount: Int
    let msPerEmbed: Double
    let tailBeatsFull: Bool
}

func runEval(_ engine: SpikeEmbedder) throws -> EvalSummary {
    print("\n════ \(engine.name) ════")
    var docVecs: [String: [Float]] = [:]
    let t0 = Date()
    for doc in corpus { docVecs[doc.id] = try engine.embed(doc.text, isQuery: false) }
    var embeds = corpus.count

    var top1 = 0
    var expectedSims: [Float] = []
    var distractorSims: [Float] = []
    var crossLangHits = 0, crossLangCount = 0
    var tailBeatsFull = false

    for q in queries {
        let qv = try engine.embed(q.text, isQuery: true)
        embeds += 1
        let ranked = corpus
            .map { ($0.id, cosine(qv, docVecs[$0.id]!)) }
            .sorted { $0.1 > $1.1 }
        let (winner, score) = ranked[0]
        let hit = q.expected.contains(winner)
        if hit { top1 += 1 }
        let isCross = q.note.contains("cross-lang") || q.note.contains("NL →")
        if isCross { crossLangCount += 1; if hit { crossLangHits += 1 } }

        // expected vs distractor sims for the margin metric
        for d in corpus {
            let s = cosine(qv, docVecs[d.id]!)
            if q.expected.contains(d.id) { expectedSims.append(s) }
            else if d.distractor { distractorSims.append(s) }
        }
        if q.expected.contains("long-tail") {
            let tail = ranked.firstIndex { $0.0 == "long-tail" } ?? 99
            let full = ranked.firstIndex { $0.0 == "long-full" } ?? 99
            tailBeatsFull = tail < full
            print(String(format: "  %@ [%@] «%@» → %@ (%.3f)  tail@%d full@%d",
                         hit ? "✓" : "✗", q.note, q.text, winner, score, tail + 1, full + 1))
        } else {
            print(String(format: "  %@ [%@] «%@» → %@ (%.3f)  runner-up %@ (%.3f)",
                         hit ? "✓" : "✗", q.note, q.text, winner, score, ranked[1].0, ranked[1].1))
        }
    }

    let ms = Date().timeIntervalSince(t0) * 1000 / Double(embeds)
    let eMean = expectedSims.reduce(0, +) / Float(expectedSims.count)
    let dMean = distractorSims.reduce(0, +) / Float(distractorSims.count)
    let summary = EvalSummary(engine: engine.name, top1: top1, queryCount: queries.count,
                              expectedMean: eMean, distractorMean: dMean,
                              crossLangHits: crossLangHits, crossLangCount: crossLangCount,
                              msPerEmbed: ms, tailBeatsFull: tailBeatsFull)
    print(String(format: "  → top-1 %d/%d · expected μ %.3f vs distractor μ %.3f (margin %.3f) · cross-lang %d/%d · %.0f ms/embed · tail>full: %@",
                 summary.top1, summary.queryCount, eMean, dMean, eMean - dMean,
                 crossLangHits, crossLangCount, ms, tailBeatsFull ? "yes" : "NO"))
    return summary
}
