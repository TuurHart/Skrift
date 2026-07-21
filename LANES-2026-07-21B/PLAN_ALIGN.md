# PLAN_ALIGN — AlignmentCore

Base SHA: `a58c0d0ad9302a4092ebe532f8f51b627637f4d3` (verified via `LANES-2026-07-21B/BASE.md`
present in worktree). Read `LANE_PLAYBOOK.md`, `BASE.md`, `LANE_ALIGN.md`, plus reference
files (read-only): `Shared/Pipeline/Karaoke.swift`, `SkriftMobile/Services/Audiobooks/
ChapterDetector.swift` (`parseNumber`/`spelledValue`/`dutchGlued`/`core`), `RunFile.anchorDrift`.
Confirmed via project.yml: desktop `SkriftDesktopTests` compiles `Shared/Pipeline` host-lessly
(no `@testable import`, matches `KaraokeAlignmentTests.swift`); mobile compiles Pipeline into
the app target, so `SkriftMobileTests` needs `@testable import SkriftMobile` (matches
`KaraokeTests.swift`). Both twin test files inherit that convention (identical bodies,
different import headers only).

## Algorithm (pure Foundation, no I/O)

1. **Flatten book** `[Block]` → one global book-word list, each entry carrying
   `(sourceFile, localIndex, text)` — tokenized on whitespace, preserving raw text for
   previews/display; matching happens on `normalizeKey`.
2. **normalizeKey**: casefold → number-word canonicalization (ported single-token subset
   of `ChapterDetector.units/teens/tens/dutchGlued`, EN+NL, incl. the `ë→e` Dutch-glued
   fix) → else strip non-alphanumerics. Display text is never touched — this only builds
   match keys. Deliberate duplication noted in a doc comment (conductor consolidates later
   per BASE.md).
3. **Anchors**: unique n-gram (`Config.anchorN`, default 4) keys — indexed via two
   Dictionary passes (count + first-index), NOT a linear scan per token — a key counted
   exactly once in both the transcript and the book is a candidate anchor
   `(transcriptStart, bookStart)`. Windows containing an empty normalized token (pure
   punctuation) are skipped.
4. **Monotonicity**: O(n log n) patience/binary-search LIS over candidates (already sorted
   by transcript index; book indices are pairwise-unique by construction) → surviving
   anchors are increasing in both dimensions. `anchorCount` = candidates found;
   `monotonicFraction` = survivors / candidates (matches the probe's "6,515 anchors, 96%
   monotonic" framing).
5. **Banded DP per gap**: between consecutive surviving anchors (plus the two edge gaps),
   NOT a global N×M matrix — each gap is its own small dense DP bounded by
   `Config.maxGapProduct` (default 250k cells); a gap that exceeds the cap is left fully
   unmatched rather than processed (this doubles as the "wrong book" fast-reject path: zero
   surviving anchors ⇒ zero DP ⇒ near-zero coverage, no expensive full-matrix attempt).
   Ops: match/substitute (cost 0/1), insert (transcript-only, cost 1), delete (book-only,
   cost 1), and TWO zero-cost glue ops (2 transcript↔1 book, 1 transcript↔2 book) gated by
   `gluesMatch` (exact concat OR concat with one seam character eaten either side — the
   `works.eep`←"works."+"keep" class). Overlapping surviving-anchor windows (rare, unique
   n-grams starting close together) are handled by clamping each anchor's fresh span to
   `max(anchorStart, prevCoveredEnd)` in lockstep on both axes.
6. **Number-merge reuses glue, not a separate pass**: "twenty"+"twelve" normalize
   independently to "20"/"12"; the SAME glue mechanism (2 transcript tokens → 1 book token
   "2012") that tolerates ASR seam-gluing also resolves this multi-token year form, no
   extra machinery. Documented as an uncertain-decision below.
7. **Interpolation**: after DP, scan the flat (book-order, cross-block) time array for nil
   runs bounded by timed neighbors on both sides; runs ≤ `Config.maxInterpolateWords` get
   linear interpolation, longer runs stay untimed. Deliberately NOT scoped per source-file —
   the audio timeline is continuous across ePub XHTML-file boundaries even though reporting
   (`MatchedRange`/`BookSpan`) is split per `sourceFile` for readability.
8. **Output**: `coverageBook`/`coverageTranscript` = fraction of words with an assigned
   time / matched flag; `matchedRanges` = per-block contiguous timed runs; top-10 (config
   knob) largest unmatched spans each side by length desc (deterministic tie-break: earlier
   start wins), with a short joined-word preview; verdict via the locked thresholds.

## Determinism discipline
Never iterate a Dictionary/Set for output-order-sensitive results — anchor candidates are
built by re-scanning the original arrays by index; span sorts use an explicit tie-break
comparator (not relying on `sorted` stability alone).

## Files
- `Skrift_Native/Shared/Pipeline/AlignmentCore.swift` (new)
- `Skrift_Native/SkriftDesktop/SkriftDesktopTests/AlignmentCoreTests.swift` (new)
- `Skrift_Native/SkriftMobile/SkriftMobileTests/AlignmentCoreTests.swift` (new, twin)

## Self-check (no xcodebuild — EDIT-ONLY lane)
`swiftc -swift-version 5 -typecheck` on the standalone Foundation-only source as a private
authoring aid (not the project build, not a simulator/device — the real gate is the
conductor's merge-time `xcodebuild`). If this isn't available/safe, fall back to careful
manual review only and say so in the wrap.

## Uncertain decisions (flagging for conductor tuning — see wrap table)
- Coverage definition = post-interpolation timed-word fraction (not raw anchor-span ratio).
- `maxGapProduct` cap value (250k) — untuned against the real pair.
- Glue-based number-merge instead of a dedicated multi-token number pass.
- Result's nested span/range types are NOT pinned by BASE.md (only `Result`/`Verdict` are)
  — my own naming (`Result.MatchedRange`, `.TranscriptSpan`, `.BookSpan`).
