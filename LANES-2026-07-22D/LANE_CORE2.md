# LANE_CORE2 — schema-3 multi-source sidecars + summary/remove APIs

Read `LANE_PLAYBOOK.md` then `LANES-2026-07-22D/BASE.md` (ownership, pinned contract — you
IMPLEMENT it verbatim). Write `LANES-2026-07-22D/PLAN_CORE2.md`, commit, execute. You are
EVOLVING `BookAlignment.swift` (batches C + the fix waves) — read it fully first; its
existing tests are your regression net (update expectations only where schema 3 requires).

## Build (small commits, explicit paths)

1. **Schema 3 types** (BASE contract): `AlignmentSource`, `FileAlignment.sources`,
   `AlignedSentence.textFile`, `currentSchema = 3` (doc the bump: multi-text). Coverage:
   `AlignmentCore.Result.coverageBook` is already returned by `alignFile` — thread it into
   the source entry.
2. **Multi-text attach/align.** `attach(bookFileAt:bookID:)` becomes additive: copy the file,
   append to `epubFilenames` (create the array from the legacy slot on first touch; KEEP
   `epubFilename` = first entry), then run THIS text against every covered transcript file
   and MERGE into the existing sidecars: keep other texts' sentences; this text's previous
   sentences (same `textFile`) are replaced wholesale; collisions per BASE (overlap in
   time → higher confidence wins, tie → earlier attach order). Per-file verdict/coverage
   for this text recorded in `sources`. `alignIfNeeded` iterates `attachedTextFilenames`
   and re-runs any text whose sidecar contribution is stale (transcript signature) or
   missing — the schema-3 gate makes every v2 sidecar "missing" once, which re-aligns all
   attached texts on the first open after update.
3. **Chapters across texts:** `assignChapterMarks` currently takes one TOC — call it per
   text (each text's TOC against ITS OWN sentences only — filter by `textFile`), union the
   marks (they can't collide: marks point at concrete sentences). `epubChapters` + the
   detected-merge stay as they are (they read marks/sentences agnostically); verify the
   aligned-span computation for the detected-merge now derives from sentences' actual
   spans rather than whole files IF a file is only partially covered — if that's a bigger
   change than it sounds, keep whole-file spans and TABLE it.
4. **`textSummary(bookID:)`** (BASE shape): global spans per text = merge that text's
   sentences' `[fileStart + start, fileStart + end]` intervals (gap-bridge ≤ 30 s so a
   span reads as one segment, not confetti); `fileNumbers` from sources with verdict
   aligned; titles from the stored `AlignmentSource.title`.
5. **`removeText(filename:bookID:)`** (BASE): strip from book record (array + legacy slot
   fixup), strip its sentences/marks/sources from sidecars, delete the file on disk,
   re-derive chapters (existing finishAlign-style pass). Never touches other texts.
6. **Cloud signature only** in `AudiobookCloudSync.swift`: `cloudSignaturePart()` gains the
   per-text dimension (e.g. `"<fileIndex>:<textCount>:<sentenceCount>"` — pick something
   stable and cheap); the send/receive/restamp machinery itself is UNTOUCHED (sidecars
   sync as whole files regardless of what's inside them). Receivers' derive path already
   runs through the shared functions you're editing.
7. **Tests** (extend `BookAlignmentTests.swift`): schema-3 round-trip + v2-rejected ·
   two-text merge on one file (disjoint spans coexist; collision → higher confidence wins;
   tie → attach order) · re-attach same filename replaces only its own sentences ·
   `textSummary` spans/gap-bridging/fileNumbers/titles · `removeText` strips exactly one
   text + legacy-slot fixup · per-text chapter marks union. Keep every existing green test
   green (update only what schema 3 legitimately changes).

## Wrap
Playbook wrap block + uncertain-decisions table (gap-bridge threshold, collision tie-break
edge cases, and the partial-file-span question from step 3 are the ones to table).
