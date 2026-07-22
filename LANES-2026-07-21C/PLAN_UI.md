# PLAN_UI — true-text read-along + verbatim captures + attach-ePub UX

Base SHA: `340ccc8de418b7aa54ba83bb5b37aa2008738376` (verified via `LANES-2026-07-21C/BASE.md`
present in worktree). Read `LANE_PLAYBOOK.md`, `BASE.md`, `LANE_UI.md`, plus the call sites
I'm editing (read-only pass first): `QuoteCaptureProcessor.swift` (`BufferSentence`,
`buildSentences`, `WindowTranscript`), `ReadAlongView.swift` (`ReadAlongModel.reloadIfNeeded`),
`MergedCaptureView.swift` (`load()`'s `.sidecar` branch), `AudiobookLibraryView.swift`
(context menu + existing `fileImporter`/alert idioms), `BookTranscriptStore.swift`,
`Audiobook.swift` (`AudiobookLibraryStore.update`), `AlignmentCoreTests.swift` (test style),
`AudiobookPlayerView.swift` (the toast idiom I'm reusing verbatim in `AudiobookLibraryView`).

LANE_CORE's `BookAlignment.swift` (the types `AlignedSentence`/`FileAlignment`/`ChapterMark`/
`BookAlignmentStore`/`BookAlignmentRunner`) does NOT exist in this worktree — it's being
written in parallel in LANE_CORE's own worktree. I build against BASE.md's pinned contract
verbatim; compile-correctness is by-eye + the conductor's merge-gate `xcodebuild`, per the
playbook (EDIT-ONLY lane, no simulators here).

## 1. `AlignedSentenceSource.swift` (new)

Pure `enum`, no I/O, no MainActor (mirrors `QuoteCaptureProcessor.buildSentences`'s
`nonisolated static` — callable from anywhere). `confidenceFloor = 0.5` as a named constant
(BASE.md-pinned value, both lanes quote it).

- Guard: `alignment != nil && isFresh && alignment.verdict == AlignmentCore.Verdict.aligned.rawValue`
  else return `nil`. (`AlignmentCore` is already compiled into the module — pre-shipped spike
  4/5 — so I reference the real enum rather than the magic string `"aligned"`.)
- Otherwise `flatMap` over `alignment.sentences`:
  - `confidence >= confidenceFloor` → one `BufferSentence` straight from the `AlignedSentence`
    (text/start/end/words), `isInInitialSpan` computed with the EXACT formula
    `QuoteCaptureProcessor.buildSentences` uses (`end > snappedStart && start < snappedEnd`).
  - `confidence < confidenceFloor` → clamp `wordStart..<wordEnd` into `transcriptWords`
    (defensive against stale/out-of-range indices — never traps), slice it, and re-run
    `QuoteCaptureProcessor.buildSentences(from: slice, snappedStart:, snappedEnd:)` so a
    mis-segmented splice still yields well-formed sentence(s), not one raw block. An
    empty/out-of-range slice contributes nothing (never a garbled partial line — consistent
    with "better no info than bad info").
- Final `.sorted { $0.start < $1.start }` (Swift's sort is stable) — the output-sorted +
  deterministic requirement, regardless of the input array's order or how many sentences one
  low-confidence splice fans out into.

## 2. `ReadAlongView.swift` — `ReadAlongModel.reloadIfNeeded`

Add `private let alignmentStore = BookAlignmentStore(directory: AudiobookLibraryStore.shared.directory)`
alongside the existing `store` (transcripts). At the ONE line that builds `sentences` (currently
`QuoteCaptureProcessor.buildSentences(from: ft.words, snappedStart: 0, snappedEnd: 0)`): look up
`alignmentStore.fileAlignment(bookID:fileIndex:)`, resolve freshness via
`alignmentStore.isFresh(_:bookID:fileIndex:audioURL:)` when a `FileAlignment` exists, then

```swift
sentences = AlignedSentenceSource.sentences(
    alignment: fa, isFresh: fresh, transcriptWords: ft.words, snappedStart: 0, snappedEnd: 0
) ?? QuoteCaptureProcessor.buildSentences(from: ft.words, snappedStart: 0, snappedEnd: 0)
```

Everything else in `reloadIfNeeded` (the frontier peek, `loadedUpTo`, `covered` from
`!sentences.isEmpty`, the guard at the top) is untouched — alignment freshness rides the exact
same reload triggers, no new invalidation path.

## 3. `MergedCaptureView.swift` — `load()`'s sidecar branch

Same lookup (own `alignmentStore` property). Pass the FULL `ft.words` (not the windowed slice)
to `AlignedSentenceSource.sentences` — the alignment's `wordStart`/`wordEnd` splice indices are
into the whole file's transcript, matching `ReadAlongView`'s usage; the low-confidence path
only ever slices its own small span, so this isn't the "NLTokenizer over the whole book" cost
the windowing comment warns about (that cost was per-load sentence *splitting*, which the
aligned path never does — the split already happened once when LANE_CORE wrote the sidecar).
When the aligned list comes back non-nil, filter it to the SAME `[winStart−30, winEnd+150]`
overlap window the un-aligned path already transcribes (`$0.end > lo && $0.start < hi`,
mirroring `FileTranscript.words(inWindow:end:)`'s own predicate) before the existing
`capIdx`/`displayLo`/`displayHi` math — keeps that math's rare empty-window fallback identical
either way instead of falling back to "last sentence in the whole file" in an edge case.
Falls back to the existing `windowed` + `buildSentences` call when alignment isn't
available/fresh/aligned. `capIdx`/`sel`/`displayLo`/`displayHi`/`state = .ready(.sidecar(all))`
all unchanged downstream — trim math, audio export, karaoke rebase stay in file-local time
either way (`AlignedSentence` already is).

## 4. `AudiobookLibraryView.swift` — attach verb

New `@State`: `attachBook`, `showAttachImporter`, `attachError`, `attachRejected`,
`attachToast`. Context-menu button beside "Transcribe book", label switches on
`book.epubFilename != nil` ("Replace book text…" / "Attach book text…"), icon
`doc.badge.plus` (distinct from Transcribe's `text.book.closed`, a plain well-known SF Symbol
— avoiding the "bad symbol renders nothing" trap since I can't render this lane-side).
`.fileImporter` (single-URL overload, NOT the multi-select one `showImporter` already uses)
with `allowedContentTypes = [UTType(filenameExtension: "epub") ?? UTType("org.idpf.epub-container"), .plainText].compactMap`
shape per BASE.md. On pick → `BookAlignmentRunner.attach(bookFileAt:bookID:)` → branch on
`AttachSummary`:
- `totalFiles == 0` → toast "Attached — aligns after transcription" (reusing
  `AudiobookPlayerView`'s exact toast idiom — capsule Text overlay + 1.6s auto-dismiss — copied
  into this view since it's a per-view idiom here, not a shared component; confirmed by
  grepping for a shared Toast type, there isn't one).
- `alignedFiles == 0 && totalFiles > 0` → `attachRejected = book`, driving a `presenting:`
  alert (title pinned by the brief) with `Keep anyway` (`role: .cancel` — the native way an
  `Alert` renders a bold/default button) and `Remove` (`role: .destructive`, clears
  `epubFilename`/`epubChapters` via `AudiobookLibraryStore.shared.update`, sidecars untouched).
- else (`alignedFiles > 0`) → toast "Aligned N of M files".
- thrown error from `attach` (couldn't read/copy the picked file) → separate `attachError`
  alert, standard OK button — kept distinct from the existing "Import failed" alert (that one's
  copy is audio-import-specific; reusing it risks a wrong title showing for an unrelated flow).

No new designed surfaces anywhere in this step — two `.alert`s (one already-patterned
`presenting:` style matching this file's `confirmationDialog`), one `.fileImporter`, one copied
toast.

## 5. `AlignedSentenceSourceTests.swift` (new)

`@testable import SkriftMobile`, fixtures built inline (`makeSentence`/`makeAlignment` helpers),
no store IO, no ZIPFoundation. Covers: nil on missing alignment / stale / verdict `partial` or
`rejected`; full-aligned mapping incl. the `isInInitialSpan` formula at both a "true" and
"false" span, and the confidence `== 0.5` boundary (trusted, not spliced); the confidence `<
0.5` splice returning literal ASR words (proving it diverges from the untrustworthy book text)
including a multi-sentence splice (one low-confidence `AlignedSentence` whose word slice
contains an internal sentence break) to check ordering is preserved; a mixed list fed to
`sentences()` in scrambled input order asserting the output re-sorts by `start`; determinism
(two calls, same input, `XCTAssertEqual`).

## Self-check (EDIT-ONLY lane — no xcodebuild/simulator here)

Careful re-read of every edited call site against the file as it stands on disk (not memory of
older mocks) + the pinned contract's exact field names/types. `AlignedSentenceSource.swift` and
its test file are typecheckable in isolation only by hand (they depend on module-internal types
— `BufferSentence`, `WordTiming`, and LANE_CORE's not-yet-existing types — so a standalone
`swiftc -typecheck` isn't meaningful here, unlike a Foundation-only file). Real gate is the
conductor's merge-time build.

## Uncertain decisions (see wrap table)
- Attach-alert body copy (not pinned by the brief, only the title + button labels are).
- `doc.badge.plus` as the attach icon (brief left the icon unspecified beyond "system chrome").
- Filtering the aligned sentence list to the capture window in `MergedCaptureView` (not
  strictly required for correctness, but keeps the existing fallback-on-empty-window behavior
  identical to the pre-alignment code instead of a rare last-sentence-of-file fallback).
- Reusing `AudiobookLibraryStore.shared.directory` (not `BookTranscriptStore().directory`) as
  the `BookAlignmentStore` root in both edited views — same value, picked the singleton already
  live in the app over constructing a throwaway store.
