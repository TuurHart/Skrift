# LANE_UI — true-text read-along + verbatim captures + attach-ePub UX

Read `LANE_PLAYBOOK.md` then `LANES-2026-07-21C/BASE.md` (ownership, the pinned contract —
you CONSUME it verbatim; LANE_CORE implements it in parallel, so compile-correctness against
the contract is by-eye + the conductor's merge gate). Write `PLAN_UI.md`, commit, execute.

**UI DISCIPLINE (mock-first rule): NO new designed surfaces.** System chrome + existing
idioms only — a context-menu item, `fileImporter`, a standard alert, the existing toast
style. Anything that needs actual design → ESCALATE.

## Build (small commits, explicit paths)

1. **`AlignedSentenceSource.swift`** — the pure, testable selection layer (this is where the
   design's "per-sentence confidence → per-sentence fallback" lives):
   ```swift
   enum AlignedSentenceSource {
       /// The read-along/capture sentence list for one file: aligned book text where
       /// trustworthy, ASR text where not, nil when alignment shouldn't be used at all.
       static func sentences(alignment: FileAlignment?, isFresh: Bool,
                             transcriptWords: [WordTiming],
                             snappedStart: TimeInterval, snappedEnd: TimeInterval)
           -> [BufferSentence]?
   }
   ```
   Returns nil unless: alignment exists · isFresh · verdict == "aligned". Otherwise maps
   each `AlignedSentence` → `BufferSentence`(text/start/end/words from the aligned sentence;
   `isInInitialSpan` computed against snappedStart/End exactly like the existing builder),
   EXCEPT sentences with `confidence < 0.5` (BASE threshold): those splice
   `transcriptWords[wordStart..<wordEnd]` through the EXISTING
   `QuoteCaptureProcessor.buildSentences` for that span so the ASR text (and its exact
   word timings) shows instead. Keep output sorted by start; deterministic.
2. **ReadAlongView** — at the existing sentence-build site (the one
   `QuoteCaptureProcessor.buildSentences(from: ft.words, …)` call): try
   `AlignedSentenceSource.sentences(…)` first (store read via `BookAlignmentStore` +
   `isFresh`), fall back to the existing line unchanged. `loadedUpTo`/frontier/covered logic
   UNTOUCHED — alignment freshness rides the same reload triggers. No layout changes.
3. **MergedCaptureView** — same swap at its `.sidecar([BufferSentence])` construction: the
   sentences the capture sheet trims against become aligned ones when available (the quote
   text saved is then the VERBATIM published sentence). Trim math, audio export, karaoke
   rebase, `.start/.end/.words` semantics: UNTOUCHED (they stay in file-local time, which
   `AlignedSentence` already is).
4. **AudiobookLibraryView** — the attach verb on the existing per-book context menu (beside
   the existing "Transcribe book" entry): "Attach book text…" → `fileImporter` (UTTypes:
   `.epub` — `UTType(filenameExtension: "epub")` with `org.idpf.epub-container` fallback —
   + `.plainText`) → `BookAlignmentRunner.attach(bookFileAt:bookID:)` → outcome alert:
   - some/all aligned → the existing toast idiom: "Aligned N of M files".
   - `alignedFiles == 0 && totalFiles > 0` → alert "This doesn't look like this audiobook's
     text" with Keep anyway (default) / Remove (Remove = clear `epubFilename` +
     `epubChapters` via the library store; sidecars can stay — verdict rejected is honest
     data). While no transcript exists yet (totalFiles == 0): toast "Attached — aligns
     after transcription" (the triggers handle it).
   - A book with an ePub attached shows the menu item as "Replace book text…" (re-attach
     overwrite is fine; no separate detach verb this spike).
5. **Tests** (`AlignedSentenceSourceTests.swift`, @testable): nil on missing/stale/partial ·
   full-aligned mapping (text/start/end/words + isInInitialSpan) · the confidence<0.5 splice
   (ASR words verbatim from the transcript slice, ordering preserved) · mixed list sorted ·
   determinism. Build FileAlignment fixtures inline; no store IO, no ZIPFoundation.

## Wrap
Playbook wrap block + uncertain-decisions table (fallback granularity + attach-flow copy are
the ones to table).
