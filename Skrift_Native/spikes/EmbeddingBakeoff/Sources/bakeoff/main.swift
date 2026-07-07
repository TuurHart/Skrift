import Foundation

// P8 chunk-0 bake-off (JOURNAL_RETRIEVAL_PLAN.md): NLContextualEmbedding vs
// EmbeddingGemma-300M on the fixed Skrift eval. Run: swift run -c release bakeoff

setvbuf(stdout, nil, _IONBF, 0) // crash-proof output when piped
print("Embedding bake-off · \(corpus.count) docs · \(queries.count) queries")
var summaries: [EvalSummary] = []

do {
    let apple = try AppleEmbedder()
    try await apple.prepare()
    summaries.append(try runEval(apple))
} catch {
    print("⚠️ Apple engine failed: \(error)")
}

// Pass dims as args (e.g. `bakeoff 512`) — default runs 768 then 512 on one instance.
// (First full run SIGSEGV'd partway through the second dim pass; probing whether
// re-encoding with a different dim on one loaded instance is the culprit.)
let dims = CommandLine.arguments.dropFirst().compactMap { Int($0) }
do {
    let gemma = try await GemmaEmbedder.load()
    print("gemma loaded ok; dims to run: \(dims.isEmpty ? [768, 512] : dims)")
    for dim in (dims.isEmpty ? [768, 512] : dims) {
        print("running dim \(dim)…")
        summaries.append(try runEval(GemmaEmbedder(model: gemma, dim: dim)))
    }
} catch {
    FileHandle.standardError.write("⚠️ Gemma engine failed: \(error)\n".data(using: .utf8)!)
    print("⚠️ Gemma engine failed: \(error)")
}

print("\n════ FINAL ════")
for s in summaries {
    let name = s.engine.padding(toLength: 34, withPad: " ", startingAt: 0)
    print(name + String(format: " top-1 %2d/%d · margin %+.3f · cross-lang %d/%d · %4.0f ms/embed · tail>full %@",
                        s.top1, s.queryCount, s.expectedMean - s.distractorMean,
                        s.crossLangHits, s.crossLangCount, s.msPerEmbed, s.tailBeatsFull ? "yes" : "NO"))
}
print("Bar: top-1 ≥ 8/10, clear positive margin, cross-lang holds, tail must beat full (chunking).")
