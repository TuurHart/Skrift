# PLAN_CORE — 📖 spike 6 alignment sidecars, runner, triggers, CloudKit sync

Base SHA `340ccc8`. Implements `LANES-2026-07-21C/LANE_CORE.md` against the pinned contract
in `BASE.md`. EDIT-ONLY — no build in this lane; conductor compiles at the merge gate.

## Key architectural decision — merge EPubBlocks per-file before aligning

`AlignmentCore.flattenBook` numbers a `MatchedRange.bookWordStart/bookWordEnd` LOCAL TO
EACH INPUT `Block`, resetting to 0 per block. `EPubParse` emits one `EPubBlock` per
paragraph/heading (MANY per spine file, same `sourceFile` repeated). Feeding those straight
into `AlignmentCore.align` (as `RunFile.swift`'s `-aligncheck` CLI probe does, 1:1) means a
matched run spanning two paragraphs of the same file produces bogus/negative word-count math
(`bookWordEnd - bookWordStart` mixes two different blocks' local numbering) — unusable for
"distribute this range's time linearly across its words."

Fix (entirely inside `BookAlignment.swift`, never touches the read-only `AlignmentCore.swift`):
`mergeBlocksByFile` concatenates adjacent same-`sourceFile` `EPubBlock`s into ONE
`AlignmentCore.Block` per epub-internal file before calling `align`. This is semantics-
preserving for the aligner (same flattened token stream, same anchors/DP/coverage/verdict —
only the RE PORTING granularity changes) and makes `bookWordStart/bookWordEnd` valid,
unambiguous, file-global token indices — which `assembleSentences` then uses directly against
its own identical re-tokenization of that same block text. Diverges deliberately from the
`-aligncheck` CLI's simpler 1:1 bridge (a diagnostic tool that only ever prints spans, never
slices by them, so the ambiguity never bit it). Covered by `MergeBlocksByFileTests`.

Alignment itself runs ONE AUDIO FILE's transcript against the WHOLE book's text (all epub
files) per call — `AlignedSentence.sourceFile` is per-sentence because one audio file's
`FileAlignment` can legitimately span many epub-internal files (e.g. a single .m4b against a
40-file epub).

## Sentence assembly

Per epub source file (one merged `Block`): tokenize (whitespace split, ranges tracked) →
`NLTokenizer(unit: .sentence)` over the REAL text for boundaries (reused choice from
`CaptureMath.SentenceSnap`, which already solved "abbreviations/quotes split mid-sentence" for
spoken text — applying the same proven tool to prose beats a hand-rolled regex per the brief's
own baseline). Each `MatchedRange` (filtered to this sourceFile) distributes its `[start,end]`
linearly across its `bookWordEnd - bookWordStart` words (now valid indices, see above). A
sentence's `words` = only the words that landed inside a matched range (WordTiming); its
display `text` is the ORIGINAL substring (preserves real punctuation/spacing). `confidence` =
timed-word-count / total-word-count for the sentence (AlignmentCore doesn't expose direct-vs-
interpolated at the API boundary, so "matched" reads as "got a time from `matchedRanges`" —
noted as a judgment call below). Zero-timed sentences are dropped. `wordStart/wordEnd` (ASR
fallback range) = the transcript word indices overlapping the sentence's resolved time span.

## Chapter derivation

`assignChapterMarks(toc:sentencesByFile:)`: for each TOC entry, first `(file, sentence)` match
scanning files then sentences in order; skip if none. Stored per-file as `ChapterMark` (title +
local sentenceIndex) so a receiver with no epub can rebuild chapters from synced sidecars alone.
`epubChapters(from:fileStartTimes:bookDuration:)`: resolves every `FileAlignment.chapterMarks`
to a global time (`fileStartTimes[i] + sentences[sentenceIndex].start`), sorts, then applies the
SAME duration fixup `ChapterDetector.assemble` uses (`next.start - start`, last → bookDuration)
so the scoped mini-scrubber (`AudiobookPlayerView` reads `chapter.duration`) doesn't collapse to
~0 the way a naive `duration: 0` would. Both are pure, disk/actor-free — reused verbatim by
`attach`, `alignIfNeeded`, and `AudiobookCloudSync.receiveAlignments` (the receiver path, no
epub available) via `finishAlign`'s "reconcile marks globally, then re-derive chapters" step —
important because a PARTIAL re-align (`alignIfNeeded` touching only stale files) must not let a
TOC entry's "first match" go stale relative to files it didn't touch this pass.

## Store, runner, triggers, sync

- `BookAlignmentStore` (final class per the pin): same directory/atomic-write/schema-gate shape
  as `BookTranscriptStore`, sibling `alignment_f<n>.json`. `isFresh` recomputes
  `FileAlignment.signature(forTranscript:)` against the CURRENT local transcript sidecar.
- `BookAlignmentRunner.attach`: copy (security-scoped, materializing) → `.epub` unzip+parse /
  `.txt` single-block → per covered-transcript file: align → assemble sentences → save sidecar
  → `finishAlign` (global chapter-mark reconcile + `epubChapters` + `modifiedAt` bump via
  `library.update`). Heavy work off-actor via `Task.detached`, mirroring
  `AudiobookImporter.importSingleFile`'s exact "copy + parse off main" shape.
- `alignIfNeeded`: cheap guards (has epubFilename → epub file still on disk → any file's sidecar
  missing/stale) before doing anything; re-parses the ALREADY-attached file, realigns only the
  stale indices, then the same `finishAlign` reconcile.
- Triggers: one `Task { await BookAlignmentRunner.alignIfNeeded(bookID:) }` line each, beside
  `detectChaptersIfNeeded` in `BookTranscriptionJob.run`'s finished-path and
  `AudiobookSession.open`'s retro path.
- Sync (`AudiobookCloudSync.swift`): mirrors the transcript block field-for-field —
  `alignmentRecordName`/`alignmentFilename`/`localAlignmentSignature` (joins
  `FileAlignment.cloudSignaturePart()` per file) / `sendAlignments` (ungated by
  `audioUploadedAt`, same as transcripts) / `receiveAlignments`. Deliberate divergence from the
  transcript receiver: alignment sidecars are NEVER restamped (they key off transcript CONTENT,
  not audio mtime), so `receiveAlignments` only sets its applied-key (→ derives `epubChapters`)
  once every downloaded file's sidecar is `isFresh` against THIS device's own transcript; a
  receiver has no epub to realign locally, so an unset key just retries next reconcile for the
  cost of a small JSON re-download. `disableSync`/its UserDefaults cleanup gets the alignment
  record names + applied-key added to its existing sweep; `restoreDownload` is NOT touched
  (alignment doesn't depend on audio mtime, so a redownload doesn't invalidate it).
- `AudiobookSyncRecord.alignmentSignature: String = ""` — additive.

## Tests (`BookAlignmentTests.swift`)

Store round-trip + schema gate · freshness (match / mismatch / no-transcript) ·
`mergeBlocksByFile` (the key fix, adjacent-same-file merge) · `assembleSentences` (linear time
distribution, partial confidence, dropped all-untimed sentence, wrong-sourceFile ranges ignored,
ASR wordStart/wordEnd range) · `assignChapterMarks` (first-match-wins across files, skip
unmatched) · `epubChapters` (global offsets, duration fixup, nil/out-of-range sentenceIndex
skipped) · `.txt` single-block `parseBookFile` path · `cloudSignaturePart` stability. No
ZIPFoundation in tests (the `.epub` branch of `parseBookFile` is exercised only via the app at
the merge gate).

## Uncertain decisions (flagged for the wrap block, not guessed silently)

1. **One-Block-per-epub-file merge** (above) — confident, not a guess, but it's a real
   divergence from the existing `-aligncheck` CLI bridge's pattern; conductor should sanity-check.
2. **`confidence` = timed/total word fraction** (not direct-DP-match/total) since AlignmentCore's
   public `Result` doesn't expose direct-vs-interpolated per word.
3. **Sentence splitter = `NLTokenizer(.sentence)`** over the literal ". ! ? … + capital" spec —
   reuses the exact tool `SentenceSnap` already proved for this class of bug.
4. **TOC "first aligned sentence whose sourceFile matches"** = scan audio files in index order,
   then that file's sentences in order — first hit wins, globally, across the whole book.
5. **`alignIfNeeded` reconciles chapterMarks GLOBALLY** (not just the just-touched files) every
   time it does any work, so the "first match" invariant can't drift between files aligned this
   pass and files aligned earlier.
