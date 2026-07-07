# Embedding bake-off — P8 chunk 0 (RESULT: EmbeddingGemma wins)

Standalone SwiftPM spike (not part of either app target) that ran the
`JOURNAL_RETRIEVAL_PLAN.md` chunk-0 gate on the Mac, 2026-07-07. 15 Skrift-style docs
(EN/NL/mixed + distractors + one long memo with a buried tail), 10 queries with known
expected top-1.

## Run

```
swift run -c release bakeoff          # both dims (see quirk below)
swift run -c release bakeoff 512     # one dim — the reliable way
```

First run downloads Apple's NL assets + EmbeddingGemma (295 MB → `Models/`, gitignored).

## Results (M4, macOS 26 — quality carries to iOS; speed/memory re-measured on device later)

| engine | top-1 | margin (expected−distractor μ cos) | cross-lang | buried-tail query | ms/embed |
|---|---|---|---|---|---|
| NLContextualEmbedding (latin, d512) | **5/10** | +0.073 (0.818 vs 0.744) | 1/3 | full@7, tail@9 — missed | ~16 |
| EmbeddingGemma-300M d768 | **10/10** | +0.387 | 3/3 | tail@1 | ~5 |
| EmbeddingGemma-300M d512 | **10/10** | +0.369 | 3/3 | tail@1 | ~5–8 |

Bar was: ≥8/10 top-1, clear margin, cross-lang holds, tail beats full.

**Verdict: EmbeddingGemma-300M at dim 512** (Matryoshka; same accuracy as 768, smaller index).
Apple's `NLContextualEmbedding` is eliminated: every pair scores ~0.85 cosine (anisotropy —
no discrimination), EN↔NL barely works, and it can't find content buried in a long memo.
Also **the chunking decision is validated by data**: even the good model ranks the long memo
7th while its tail chunk ranks 1st for a tail query — full-memo vectors bury the tail.

## Notes for the production port

- One dim per loaded instance: running encode at 768 then 512 on one `EmbeddingGemma`
  instance in one process was flaky in this harness (silent skip / SIGSEGV). Each dim alone
  is 100% stable across runs. Production picks 512 at load and never switches.
- `import CoreMLLLM`, `.package(url: "https://github.com/john-rocky/CoreML-LLM", from: "1.9.0")`,
  `EmbeddingGemma.downloadAndLoad(modelsDir:)`, `encode(text:task:dim:)` with
  `.retrievalQuery` / `.retrievalDocument` — port `Engines.swift` + `Eval.swift` from here.
- SkriftMobile's deployment target is already iOS 18.0 — CoreML-LLM's minimum. No gating.
- `String(format: "%s", swiftString)` segfaults — cost this spike an hour. Use `%@` or padding.
