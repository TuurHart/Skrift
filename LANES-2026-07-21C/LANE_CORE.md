# LANE_CORE — alignment sidecars, runner, triggers, CloudKit sync

Read `LANE_PLAYBOOK.md` then `LANES-2026-07-21C/BASE.md` (ownership, the pinned contract —
you IMPLEMENT it verbatim). Write `PLAN_CORE.md`, commit, execute.

## Build (small commits, explicit paths)

1. **`BookAlignment.swift`** — the BASE contract types + store + runner, mirroring the house
   patterns you can read next door (`BookTranscript.swift` / `BookTranscriptStore.swift`):
   - Store IO: atomic JSON write, decode-tolerant read (schema gate), same directory layout
     as transcripts (`library.folder(for: bookID)`).
   - `attach(bookFileAt:bookID:)`: security-scoped read of the picked URL if needed; copy into
     the book folder (keep the original filename); `.epub` → unzip via ZIPFoundation
     (`Archive(url:accessMode:.read)`, extract entries to `[String: Data]`) → `EPubParse.parse`;
     `.txt`/plain → one `EPubBook`-shaped single-block book, empty TOC, drm none (build the
     blocks directly — do NOT touch EPubParse). Then per file with a covered transcript
     sidecar: `AlignmentCore.align` (defaults) → sentence assembly (below) → `FileAlignment`
     (+ verdict) → save. Derive `epubChapters`: for each TOC entry, the first aligned sentence
     whose `sourceFile` matches → global time = file start offset + sentence.start (file start
     offsets from `book.fileStartTimes`); skip TOC entries with no aligned sentence. Update
     `book.epubFilename`/`book.epubChapters` through the library store's existing update path,
     `modifiedAt` bump included. Rejected-everywhere still writes sidecars (verdict recorded) —
     the UI decides what to tell the user.
   - **Sentence assembly** (pure, unit-tested): split each aligned block's text into sentences
     (. ! ? … followed by space+capital or end; abbreviations like "Dr."/"Mr." best-effort —
     table the edge cases, don't gold-plate). A sentence's words = its book words with
     per-word times taken from AlignmentCore's `matchedRanges`, distributing a range's
     time span linearly across the words inside it; sentence.start/end = first/last timed
     word; `wordStart/wordEnd` = the covering transcript word-index range; confidence =
     directly-matched fraction. Sentences with NO timed words are dropped (they're inside
     unmatched book spans — front matter etc.).
   - `alignIfNeeded(bookID:)`: guards in order — book has `epubFilename` · file's sidecar
     missing-or-stale (`isFresh`) · transcript covered. Then re-runs alignment for stale
     files only. Cheap when there's nothing to do (a stat + a signature string compare).
2. **Triggers** (one line + a comment each, marked additions):
   - `BookTranscriptionJob`: right after the existing `detectChaptersIfNeeded(bookID:force:)`
     finished-path call → `Task { await BookAlignmentRunner.alignIfNeeded(bookID: bookID) }`.
   - `AudiobookSession.open`: beside the existing `detectChaptersIfNeeded` retro line →
     same fire-and-forget.
3. **Sync** (`AudiobookCloudSync.swift` + `AudiobookSyncModels.swift`): mirror the transcript
   sidecar block VERBATIM, renamed for alignments — `alignmentRecordName` = `ab_<id>_al<n>`,
   `alignmentFilename` = `alignment_f<n>.json`, `localAlignmentSignature` (join of
   `"<i>:<verdict>:<sentenceCount>"` per existing sidecar), `sendAlignments` (upload when
   changed vs `record.alignmentSignature`), `receiveAlignments` (pull when the record's
   signature changed + not yet applied — same UserDefaults applied-key idiom), and after
   receive: derive `epubChapters` locally (same derivation as attach; the receiver has no
   ePub file — chapters come from the synced sidecars' chapterMarks). Wire both into the
   same call sites the transcript versions ride (source + receiver paths). Additive
   `alignmentSignature: String = ""` on `AudiobookSyncRecord` with the init default.
   NOTE: alignment sidecars are NOT restamped (they reference transcript CONTENT, which is
   identical across devices; the transcript restamp handles audio staleness) — but only
   APPLY them when the local transcript sidecar for that file exists and matches the
   sidecar's `transcriptSignature` (else hold; the next reconcile after transcripts land
   applies them — the applied-key guard makes the retry free).
4. **Tests** (`BookAlignmentTests.swift`, @testable): store round-trip + schema gate ·
   freshness (matching vs drifted transcript signature) · sentence assembly on a synthetic
   AlignmentCore.Result (times distributed, confidence math, dropped untimed sentence,
   wordStart/wordEnd covering range) · chapterMark → epubChapters derivation incl. the
   skip-unaligned-TOC-entry case and global-time offsets · .txt single-block path ·
   alignment signature string stability. No ZIPFoundation in tests — feed `[String: Data]`
   or pre-built blocks.

## Wrap
Playbook wrap block + uncertain-decisions table (sentence-split edge cases and the
receive-hold rule are where honest tabling beats guessing).
