# PLAN_CORE2 — schema-3 multi-source sidecars + summary/remove APIs

Base SHA: `b4ec5d6` (verified via `LANES-2026-07-22D/BASE.md` present in worktree).
Read `BookAlignment.swift` (668 lines) + `BookAlignmentTests.swift` (400 lines) fully first —
this plan evolves both in place. Read `AudiobookCloudSync.swift`, `Audiobook.swift`,
`AlignedSentenceSource.swift`, `ReadAlongView.swift`, `MergedCaptureView.swift`,
`AudiobookLibraryView.swift` (read-only) to confirm every call site this batch must keep
compiling, and `Shared/Pipeline/{AlignmentCore,EPubParse}.swift` for the exact pinned types
(`Result.coverageBook`, `EPubBook.title`, `Verdict`).

## Key findings from the read

- `cloudSignaturePart()` is DEFINED in `BookAlignment.swift` (on `FileAlignment`), not in
  `AudiobookCloudSync.swift` — that file only CALLS it (`localAlignmentSignature`, format-
  agnostic, joins whatever string comes back with "|"). So the "signature part" of my
  `AudiobookCloudSync.swift` grant turns out to need **zero edits** — confirmed by reading
  every reference (`AudiobookSyncModels.swift:35` also mentions the format in a doc comment,
  but that file is outside my ownership; flagged as a background task, not fixed here).
- `AlignedSentenceSource.sentences()` (read-only, untouched) sorts its output by `start` and
  gates entirely on `alignment.verdict == .aligned` — so the merged, multi-text `sentences`
  array just needs to stay internally non-overlapping and the FILE-level `verdict` needs to
  mean "is this file's sentences trustworthy as a whole," not "did every text match."
- `epubChapters`'s partial-match merge (whole-file spans for the aligned-span suppression
  check) is **left as-is** — switching it to real per-sentence spans breaks
  `testPartialMatchKeepsDetectedChaptersOutsideAlignedSpan`'s fixture-built expectations and
  changes single-text behavior too (wider blast radius than this batch). TABLED per the
  brief's own escape hatch; noted in the wrap block.

## Design decisions (the meat)

1. **File-level `verdict` = best-of across `sources`** (aligned > partial > rejected). Read
   sites (`AlignedSentenceSource`, `epubChapters`) both gate on file-level `.aligned` to decide
   whether to trust/show a file's sentences at all — one poorly-matching text must never
   regress what another, better-matching text already achieved for that file.
2. **Collision merge** (`mergeSentences`): an incoming sentence either lands with no time
   overlap, or CONTESTS every currently-kept sentence it overlaps AT ONCE — wins only if its
   confidence beats the toughest of them (tie → earlier attach rank), and winning displaces
   ALL contested entries atomically. Never a partial swap (that would blow a hole in another
   text's coverage for nothing in return).
3. **Chapter marks**: `assignChapterMarks` (unchanged) is called ONCE PER TEXT against that
   text's own sentences (filtered by `textFile`) and that text's own PER-SOURCE verdict
   (not the file's merged verdict — generalizes the phantom-chapters fix: a rejected text's
   junk sentences must never claim TOC entries even when another text made the file overall
   "aligned"). Filtered-array-local `sentenceIndex` is remapped to the full array before
   union (marks always index the full, unfiltered `sentences` array downstream).
   TOCs are re-derived by re-parsing each attached text from disk (not persisted separately —
   `AlignmentSource` is pinned with no `toc` field) — `attach`/`alignIfNeeded` cache the TOC(s)
   they just parsed (`precomputedTOC`) so the common single/refresh case doesn't double-parse;
   `removeText` has nothing cached and always re-parses survivors.
4. **Cross-device gap**: attached text FILES never sync (only sidecars do — existing doc
   comment). If `alignIfNeeded` runs on a device missing some attached text's file locally, its
   TOC can't be re-derived — chapter reconciliation PRESERVES that text's existing on-disk
   marks (filtered by `textFile`) instead of dropping them, which would otherwise wipe-and-
   resync (`sendAlignments` is ungated) the loss to every other device.
5. **`cloudSignaturePart()` format**: `"<fileIndex>:<verdict>:<sentenceCount>:<sources.count>"`
   — keeps the OLD prefix byte-identical (existing behavior/tests mostly survive) and appends
   the text-count dimension per the brief's suggestion, rather than replacing verdict/
   sentenceCount outright.
6. **`textSummary`**: `@MainActor`, gains a defaulted `library: AudiobookLibraryStore = .shared`
   param (matches this codebase's established DI pattern, e.g. `AudiobookCloudSync`) purely for
   test isolation — call sites using the bare `textSummary(bookID:)` are unaffected.
   `coveredSeconds`/`totalCoveredSeconds` are literally "sum of GLOBAL spans" per the pinned
   doc comment (i.e. the gap-bridged numbers, not a raw union) — simplest reading, matches the
   mock's "one segment not confetti" framing.
7. New pure/testable helpers (all `internal static func` on `BookAlignmentRunner`, following
   this file's existing convention of exposing pure pieces for direct unit testing):
   `bestVerdict`, `mergeSentences`, `mergedFileAlignment`, `strippingText`,
   `detachedTextFields`, `perTextChapterMarks`. Orchestration (`attach`, `alignIfNeeded`,
   `mergeAndFinish`, `reconcileChapters`, `removeText`) stays untested directly — matches the
   existing precedent (today's `attach`/`alignIfNeeded` aren't unit tested either, only their
   pure pieces are).

## Build order

1. `AlignedSentence.textFile`, `AlignmentSource`, `FileAlignment.sources`, schema→3,
   `cloudSignaturePart()`.
2. `assembleSentences` gains defaulted `textFile:` param; `alignFile` gains `textFilename:`,
   returns `coverage`.
3. Pure helpers (step 7 above).
4. Rewrite `attach`/`alignIfNeeded` → `mergeAndFinish`/`reconcileChapters` (replaces
   `finishAlign`).
5. `BookTextSummary`/`PerText`, `textSummary(bookID:library:)`.
6. `removeText(filename:bookID:)`.
7. Tests: extend `BookAlignmentTests.swift` per brief step 7.

## Uncertain decisions carried to the wrap block

Gap-bridge threshold (30s, brief's suggestion, not independently re-derived) · collision
tie-break's "atomic all-or-nothing against the toughest competitor" (vs. a per-pair partial
swap, which risks data loss) · the partial-file-span question (TABLED, whole-file spans kept)
· `AudiobookCloudSync.swift` ended up needing zero edits despite the ownership grant.
