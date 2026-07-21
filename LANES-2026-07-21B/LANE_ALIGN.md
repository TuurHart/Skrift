# LANE_ALIGN — spike 5: AlignmentCore, transcript ↔ book-text word alignment

Read `LANE_PLAYBOOK.md` then `LANES-2026-07-21B/BASE.md` first (base check, ownership,
pinned names, pure-Foundation rule). Then this brief. Then write your PLAN, commit, execute.

## The question
Given ASR transcript words WITH timestamps and book text WITHOUT, put timestamps on the book
words — tolerating ASR mishears, glued seam tokens, narrator skips/additions, and the
wrong-book case. Pure text alignment, no ML. The probe (BASE.md) fixed the expected shape:
right book ≈ 98% coverage / dense monotonic anchors; wrong book ≈ noise. Reproduce that.

## Contract (from the locked design, backlog 📖 item 1 + 6 + probe findings)

1. **API** (pinned names in BASE.md):
   `AlignmentCore.align(transcript: [Word], book: [Block], config: Config = .init()) -> Result`.
   `Word { text, start, end }` (seconds). `Block { text, sourceFile }`. Everything
   deterministic, no I/O. `Config` carries thresholds + band width with defaults.
2. **Internal normalization for MATCH KEYS ONLY** (display text stays untouched — Tuur
   locked aligner-internal over wiring FluidAudio's TextNormalizer): casefold; strip
   non-alphanumerics; number canonicalization EN+NL — PORT the minimal needed subset from
   `SkriftMobile/Services/Audiobooks/ChapterDetector.swift` `parseNumber` (READ-ONLY
   reference; note the deliberate duplication in a comment — conductor consolidates later).
   NOT needed (research verdict): filler stripping, contraction expansion, hyphen rules.
3. **Glued-token tolerance** (#683 class, ~1 per 4.5 h on device): an unmatched transcript
   token that equals the concatenation of the next two book words (normalized) matches BOTH
   (and the reverse: two transcript tokens ↔ one book word). Also tolerate a glued token
   with ONE leading/trailing character eaten (`works.eep` = "works."+"eep" ← "keep").
4. **Pipeline:** unique n-gram anchors (n=4 worked on the real pair; make n a Config knob) →
   longest-increasing-subsequence filter for monotonicity (patience-diff trick; drop
   off-diagonal anchors) → banded word-level DP (match/substitute/insert/delete; band spans
   the gap between surviving neighbor anchors) in each gap → matched book words inherit the
   transcript word's times; interpolate holes ≤ `Config.maxInterpolateWords` linearly
   between timed neighbors; larger holes stay untimed.
5. **Efficiency:** indexed shingle/next-occurrence lookups — NO linear scans per token (the
   in-repo triplicate's known sin). Target: 10k × 10k words well under a second in Debug;
   the DP is banded, never full N×M.
6. **Result** carries: `coverageBook` + `coverageTranscript` (fraction of words matched),
   `anchorCount`, `monotonicFraction`, per-block matched ranges with times, the 10 largest
   unmatched TRANSCRIPT spans and 10 largest unmatched BOOK spans (word ranges + a short
   text preview — this feeds the conductor's `-aligncheck` report directly), and
   `verdict: aligned | partial | rejected`. Default thresholds from the probe's 150:1
   separation: `aligned` ≥ 0.35 coverageBook AND monotonicFraction ≥ 0.8; `rejected` <
   0.05 coverageBook OR monotonicFraction < 0.3; else `partial`. All Config-overridable —
   the conductor tunes against real pairs.
7. **Optional timestamps BOTH directions** (design lock): transcript-only spans (narrator
   credits) simply stay unmatched transcript spans; book-only spans (front matter,
   copyright) stay untimed book words — both must come out of `align` cleanly, no special
   cases at call sites.

## Tests (twin files, identical bodies)
Synthetic fixtures built in-code from a base text you write (public-domain-style prose you
author yourself, ~300+ words; NO real book text): identity alignment (coverage ≈ 1,
verdict aligned) · scattered substitutions (ASR mishears — still aligned, holes timed by
interpolation) · glued pairs (two words → one token) + the eaten-letter variant · a deleted
book span (narrator skip → untimed book words, verdict stays aligned) · an inserted
transcript span (credits → unmatched transcript span reported) · reordered front matter
(monotonicity filter survives) · number forms ("2012" ↔ "twenty twelve"; one NL case,
e.g. "negentien" ↔ "19") · WRONG BOOK: shuffled/unrelated text → verdict rejected,
coverage ≈ 0 · determinism (same input twice → identical Result) · the 10-largest-spans
reporting · band-efficiency smoke (a few thousand words completes fast).

## Wrap
Playbook wrap block, uncertain-decisions table included — threshold choices and tie-breaks
in the DP are exactly the decisions to table for the conductor's real-pair tuning.
