# Skrift cleanup audit — dead and overcomplicated code (read 2026-10-02)

Date 2026-10-02. Commit `ea6826de`, read in worktree `session-3-f90c83`.

**Method.** 15 slices x 2 finders ({dead, complexity}) → one adversarial verifier per finder, which re-opened the cited code and confirmed, corrected or refuted each finding and added anything the finder missed → 1 synthesizer (this file). All Sonnet. Read-only: no code, QUEUE.md, SPEC.md or test was touched, nothing was built or run, and no UI test was started. Findings are from reading; nothing was proven by a compile or a test run.

**Counts.** 620 findings kept (confirmed or corrected), 97 refuted, 104 missed-by-finder (added by the verifiers), about 12,344 lines removable as the harness counted them. Failed slices: none. The harness total double-counts items that two slices or both lenses reported; the de-duplicated figure is the sum of section 3 and 4 below, shown in section 2. The synthesizer opened the code itself for the highest-value and highest-risk findings: it re-grepped the symbols behind P1, P12, P18, P23, P26, P27, P28, P32, P35, P43, P46 and P47 across all Swift in `Skrift_Native` and each came back as the verifiers described, and it compared the stray mock and the spike references for P50 (identical file; only archive prose and three code comments mention the spikes). Everything else rests on the verifier's own reading.

**Conventions.** All paths are relative to `Skrift_Native/` unless they start with `plan/`, `archive/` or a repo-root name. Each slice section names its base folder; a bare file name is in that folder. Ids are `<slice>-d<NN>` (dead lens), `<slice>-c<NN>` (complexity lens), and `-m<N>` for a verifier "missed" finding (marked **missed**). `dup of X` means the same code was reported by another finding; the lines are counted once, at the owner. `Q###` means the finding is already queued (QUEUE.md) and is not re-proposed. `(→P#)` points at the queue item in section 6 that carries it. Lines are verifier-corrected estimates of net lines removed (a relocation counts 0). Risk is the verifier's, adjusted where I read the code.

Slice codes: MAS m-audiobook-svc, MAU m-audiobook-ui, MMD m-memodetail, SPL shared-pipeline, DRV d-review, DSH d-shell, DPE d-pipeline-engines, DAU d-app-ui, MRC m-recording-capture-ui, MLJ m-list-journal-settings, MSV m-services, MAM m-app-models-ext, SMU shared-model-ui-body, SRS shared-rest, PER periphery.

## 2. Summary

**Lines removable.** The tables in sections 3 and 4 add up to **8,034 lines** after folding repeats (5,311 from the dead lens, 2,723 from the complexity lens). The harness reported about 12,344 before de-duplication; the difference is findings both lenses or two slices reported, and relocations that count 0 here. Of the 8,034 lines, 6,272 sit in rows that point at a queue item (62 items, section 6); the other 1,762 are not queued, with the reason in section 6 ("Needs Tuur" and "Found but not queued"). These are line estimates from reading; nothing was compiled.

Per slice and per kind (kind is a grouping of the finders' `kind` label: dead code = unreferenced, dead chain, unreachable, never-built case, unread flag, stale workaround; harness = unused DEBUG launch harness or whole spike):

| slice | dead lens | complexity lens | total | dead code | test-only | harness | duplication / simplify | comments | other | queue items |
|---|---|---|---|---|---|---|---|---|---|---|
| MAS m-audiobook-svc | 434 | 128 | 562 | 377 | 0 | 0 | 175 | 0 | 10 | 5 |
| MAU m-audiobook-ui | 342 | 149 | 491 | 232 | 0 | 0 | 233 | 20 | 6 | 3 |
| MMD m-memodetail | 192 | 157 | 349 | 77 | 33 | 62 | 134 | 35 | 8 | 1 |
| SPL shared-pipeline | 374 | 193 | 567 | 158 | 122 | 0 | 231 | 40 | 16 | 6 |
| DRV d-review | 239 | 85 | 324 | 19 | 0 | 156 | 118 | 25 | 6 | 3 |
| DSH d-shell | 379 | 197 | 576 | 25 | 0 | 264 | 257 | 30 | 0 | 5 |
| DPE d-pipeline-engines | 394 | 251 | 645 | 157 | 7 | 0 | 363 | 45 | 73 | 5 |
| DAU d-app-ui | 161 | 179 | 340 | 134 | 0 | 0 | 171 | 25 | 10 | 4 |
| MRC m-recording-capture-ui | 176 | 144 | 320 | 32 | 23 | 0 | 193 | 70 | 2 | 4 |
| MLJ m-list-journal-settings | 251 | 147 | 398 | 113 | 0 | 55 | 161 | 40 | 29 | 4 |
| MSV m-services | 136 | 189 | 325 | 76 | 20 | 0 | 221 | 3 | 5 | 7 |
| MAM m-app-models-ext | 402 | 274 | 676 | 128 | 28 | 143 | 340 | 27 | 10 | 4 |
| SMU shared-model-ui-body | 89 | 223 | 312 | 18 | 64 | 0 | 227 | 0 | 3 | 1 |
| SRS shared-rest | 133 | 202 | 335 | 98 | 33 | 0 | 183 | 0 | 21 | 5 |
| PER periphery | 1609 | 205 | 1814 | 453 | 0 | 682 | 679 | 0 | 0 | 3 |
| **total** | 5311 | 2723 | 8034 | 2097 | 330 | 1362 | 3686 | 360 | 199 | 60, plus 2 cross-cutting (P51, P54) |

PER is large because three one-off items are whole files: the stray root `mockups/Q51.html` (494), `GlassLab/` (313) and `DiarizeSpike/` (198).

**Top 15 by lines x confidence / risk.** All low risk and high confidence unless marked.

| # | finding | lines | item |
|---|---|---|---|
| 1 | PER-d18 byte-identical stray `mockups/Q51.html` | 494 | P50 |
| 2 | MAS-d01/d02 audio-trim machinery in quote capture (`applyTrim`, `TrimResult`, `isUnchangedTrim`, `isInInitialSpan`, `snapped*`) plus 4 tests that call no production code | 335 | P1 |
| 3 | PER-d01 `GlassLab/` throwaway glass harness | 313 | P50 |
| 4 | PER-d06 drain-side half of the retired share dictation, `CaptureDictation` (medium; needs Tuur) | 300 | P42 |
| 5 | MAU-d02 `TranscribeBookView`, duplicated by the Text sheet (medium; port the `.failed` line first, needs Tuur) | 212 | P7 |
| 6 | PER-d02 `DiarizeSpike/` finished spike | 198 | P50 |
| 7 | DRV-d15 second SwiftUI-Text note renderer that exists only for three snapshots (medium; needs Tuur) | 150 | P16 |
| 8 | PER-d13 Mac probes with no invoker: `-asrbench`, `-vaultpreview`, `-audiodate`, `-voiceloop` (the last has no `defer` restore of Dev names.json) | 109 | P19 |
| 9 | MAM-d14 + PER-d05 share-side dictation plumbing that always passes nil, plus a UI test of absent controls | 77 | P41 |
| 10 | PER-d12 `-stubEnhancement` engines and five `stubbedEngines` guards | 62 | P18 |
| 11 | MMD-d01 `ConversationMockView` static mock behind `-conversationMock` | 62 | P9 |
| 12 | MAM-d17 `RecordWidget` and `NewNoteWidget` identical except for strings | 60 | P44 |
| 13 | MAM-d04 `trashCountdownLabel` -> `trashDaysRemaining` -> `MemoLifecycle.goneAt`, reached only by tests | 55 | P43 |
| 14 | DAU-d01 Mac `StatusPill` and `PulseDot`, never constructed | 45 | P28 |
| 15 | SMU-d05 `Memo.splitTagInput`, test-only | 40 | P46 |

**Bugs the audit tripped over** (not dead code; each is a queue item that starts with a failing test): redo strands a queued Process on the Mac (P21), emoji splits a word in Mac karaoke (P17), `Player.showToast` clears the next toast early (P6), `WallPrinter` drops a card enqueued during a drain (P37), onboarding model spinner never clears after a failed download (P37), language picker re-stamps a synced value (P37), camera pinch zoom compounds (P34), media-services reset re-enables the Bluetooth mic (P34), `ObsidianVault.hasPublished` keys the wrong ledger (P40), `GemmaEmbedder` loads the model twice under concurrent `prepare()` (P49), Mac duration prints `125:00` (P30), `-ratetorow` swallows a thrown error (P22), vault attachment name collision (P59), and six suspected ones in P54. All are from reading, none was reproduced.

**Twelve items are `[tuur]`**: P7, P14, P16, P19, P26, P29, P33, P34, P39, P42, P45, P62; there are also the decisions listed at the end of section 6. Twenty-four items edit or delete protected tests and go through `plan/hand-merge.sh` after a one-line yes; section 6 lists them.

## 3. Dead code, per slice

### MAS m-audiobook-svc (base `SkriftMobile/Services/Audiobooks/`)

| id | kind | where | what | lines | risk |
|---|---|---|---|---|---|
| MAS-d01 | dead-chain | QuoteCaptureProcessor.swift:208-296; Tests AudiobookCaptureMathTests:74-193, QuoteCaptureSaveTests:123-212 | `applyTrim`, `TrimResult`, `isUnchangedTrim` have no production caller; four tests re-implement the rebase maths inline. `exportSpan` stays live. (→P1) | 295 | low |
| MAS-d02 | dead-chain | QuoteCaptureProcessor.swift:6-47,97-98,129-206; Features/Audiobooks/AlignedSentenceSource.swift:44-143; ReadAlongView:96; MergedCaptureView:384,393 | After d01: `bufferSentences`, `bufferOffset`, `spanEnd`, `BufferSentence.isInInitialSpan` and the `snappedStart/snappedEnd` params (always 0, 0 in production) are dead. Test edits wider than first said. (→P1) | 40 | medium |
| MAS-d03 | unreferenced | AudiobookSession.swift:375-381 | `sleepLabel`, already Q173 | 0 | low |
| MAS-d04 | test-only | AudiobookSession.swift:606-648; AudiobookInterruptionTests:17-45 | `shouldResumeAfterInterruption` is only called by its 4 tests; the shipped path copies the rule. Fix = make the shipped method call the pure function, do not delete (pins a 2026-07-26 Deezer bug). (→P2) | 0 | low |
| MAS-d05 | unreferenced | AudiobookImporter.swift:86-91 | Single-URL `importBook(from:libraryDirectory:)` overload, no callers (→P2) | 6 | low |
| MAS-d06 | flag-unread | BookBundle.swift:43-45; SkriftMobile/project.yml:227-229 | `BookBundle.typeIdentifier` and Info.plist key `SkriftBookUTI` have no reader (keep `SkriftBookExtension`) (→P2) | 6 | low |
| MAS-d07 | test-only | AudiobookAudioTransport.swift:48-85 | `InMemoryAudiobookTransport` compiled into the app, used only by AudiobookCloudSyncTests. Move to tests (38 lines leave the binary, net 0) (→P2) | 0 | low |
| MAS-d08 | other | BookTranscriptionJob.swift:129,181,242,253,397-402 | `starts` param of `publishValue/publishProgress` never read (→P2) | 4 | low |
| MAS-d09 | flag-unread | BookAlignment.swift:338,421,436-470 | `AttachSummary.rejectedFiles` / `AttachOutcome.rejected` written, never read (→P2) | 5 | low |
| MAS-d10 | flag-unread | BookAlignment.swift:1,136-140,416-470,581-628,859-871,942,970,1452-1454 | `FileAlignment.epubSignature` is hashed (whole ePub read into memory) on every attach/re-align and read nowhere. Persisted, keep the field and Codable shape; stop computing it. Not `AudiobookSyncRecord.epubSignature` (live). (→P3) | 18 | low |
| MAS-d11 | copy-paste | Audiobook.swift:535-546 vs 413-447 | `sortedByRecent` re-implements `BookSort.recentlyPlayed` (→P2) | 8 | low |
| MAS-d12 | copy-paste | AudiobookCloudSync.swift:410-467 vs 602-657 | Transcript and alignment sidecar name/parts/refs/send helpers are twins. CloudKit record-name strings must stay byte-identical. (→P4) | 28 | medium |
| MAS-d13 | unreachable | ChapterDetector.swift:83,188,285,311; BookAlignment.swift:1436-1448 | Redundant `count >= 2` test, unused 999 default on `Heading.init`, duplicated duration fix-up loop (→P2) | 4 | low |
| MAS-d14 | magic-numbers | Audiobook.swift:497; BookTranscriptStore.swift:15,21; BookAlignment.swift:206,210; Bookmark.swift:34,38 | `audiobooks` root and `<root>/<uuid>` folder rule defined four times (→P3) | 6 | low |
| MAS-d15 | history-comments | BookTranscriptStore.swift:161-175 | Doc for `removeTranscripts` merged into the notification's doc, wrong text (→P2) | 0 | low |
| MAS-d16 | two-sources-of-truth | Audiobook.swift:50-52,83-108,189-242; BookBundleManifest.swift:149; BookAlignment.swift:511,715,902-906,995; AudiobookCloudSync.swift:596 | Legacy `epubFilename` mirror of `epubFilenames` written at 5 sites for pre-multi-text builds. Persisted, keep. Stopping the mirror is Tuur's call (see section 6 "Needs Tuur"). | 8 | medium |
| MAS-d-m1 | other (**missed**) | BookBundle.swift:258 | `derivedSidecars(bookID:...)` never uses `bookID` (→P2) | 3 | low |
| MAS-d-m2 | flag-unread (**missed**) | BookTranscriptionJob.swift:79,478 | `levelObserver` token written, never read (→P2) | 1 | low |
| MAS-d-m3 | unreferenced (**missed**) | Audiobook.swift:76-77 | computed `Audiobook.audioFilename` ("Legacy convenience") has no reader; keep the init label (→P2) | 2 | low |
| MAS-d-m4 | two-sources (**missed**) | Features/Audiobooks/ReadAlongView.swift:78 | re-inlines `FileTranscript.isCovered` as `> frontier + 0.05` (→P2) | 0 | low |

### MAU m-audiobook-ui (base `SkriftMobile/Features/Audiobooks/`)

| id | kind | where | what | lines | risk |
|---|---|---|---|---|---|
| MAU-d01 | unreferenced | ChaptersBookmarksSheet.swift:192-272 | `ChaptersBookmarksRail` has no call site. Already Q173; add the comment rewording at 117,128-131,157,171 to Q173. | 0 | low |
| MAU-d02 | dead-chain | TranscribeBookView.swift:1-205; AudiobookPlayerView.swift:22,75-77,165,284; Services/Audiobooks/BookTranscriptionJob.swift:98,135 | `TranscribeBookView` is reachable only from the read-along nudge; `BookTextSheet` Level 1 does the same job. The `.failed(why)` line only exists here (BookTextSheet never reads `.failed`), so port it first. Product call: nudge would open the full Text sheet. (→P7) | 212 | medium |
| MAU-d03 | dead-chain | (trim machinery) | dup of MAS-d01/d02 | 0 | medium |
| MAU-d04 | unreferenced | ChaptersBookmarksSheet.swift:9-24; AudiobookPlayerView.swift:31,90,258,280 | `initialTab` is always `.chapters`; stored property never read (→P6) | 10 | low |
| MAU-d05 | unreferenced | MergedCaptureView.swift:67,71,425; SyncedAudiobooksView.swift:10; AudiobookSyncSheet.swift:14 | `session`, `touched` (written only), `repository`, `dismiss` unused (→P6) | 5 | low |
| MAU-d06 | history-comments | AudiobookLibraryView.swift:425-428,648-660; AudiobookPlayerView.swift:4-10; AudiobookMiniPlayerBar.swift:23-28,81-82; BookTextSheet.swift:586-589; ContinueListeningCard.swift:71 | Orphan "Attach book text (spike 6)" MARK with no function under it, stale player/mini-bar docs, a leftover DevLog (→P6) | 20 | low |
| MAU-d07 | stale-workaround | AudiobookPlayerView.swift:102-113,139-146 | `content(_:)` only forwards to `compactContent(_:)` (the `!isRegular` guard is Q173) (→P6) | 5 | low |
| MAU-d08 | copy-paste | BookShareSheet.swift:163-172 vs Features/MemoDetail/MemoDetailSupportTypes.swift:242-248 | `ShareSheet` and `ActivityShareSheet` are identical UIActivityViewController wrappers (→P6) | 9 | low |
| MAU-d09 | copy-paste | AudiobookLibraryView.swift:683-749 vs EditBookDetailsView.swift:28-64,125-138 | duplicate `field(_:text:id:)` and Cancel/primary row (→P8) | 20 | low |
| MAU-d10 | copy-paste | BookTextSheet.swift:101-132 | two identical bottom toast overlays, mutually exclusive (→P6) | 12 | low |
| MAU-d13 | copy-paste | ReadAlongView.swift:84-99; MergedCaptureView.swift:364-394 | fresh-alignment computation repeated; only that half is shareable (→P6) | 8 | low |
| MAU-d14 | copy-paste | BookShareSheet.swift:76-84; BookImportSheet.swift:78-86; BookTextSheet.swift:315-325; BookShelfTile.swift:85-93; 7 sheets | capsule progress bar x4, 34/36pt drag handle x7 (→P8) | 18 | low |
| MAU-d15 | copy-paste | AudiobookMiniPlayerBar.swift:18-19,86-110,142-143,206-226 | bar and pill repeat glass chrome and the two covers (→P8) | 14 | low |
| MAU-d16 | two-sources | BookShelfTile.swift:19-21,114; Services/Audiobooks/Audiobook.swift:455,466 | "finished" predicate written 3 times (→P6) | 3 | low |
| MAU-d17 | reinvented | AudiobookSyncSheet.swift:27-32; BookShareSheet.swift:179-184 | duration formatters disagree; `BookShareCopy.subtitle` doc promises a format the code does not return (→P6) | 6 | low |
| MAU-d-m1 | dead-chain (**missed**) | Services/Audiobooks/QuoteCaptureProcessor.swift:71 | stale TextCaptureView doc comment (→P1) | 0 | low |

### MMD m-memodetail (base `SkriftMobile/Features/MemoDetail/`)

| id | kind | where | what | lines | risk |
|---|---|---|---|---|---|
| MMD-d01 | unused-harness | ConversationMockView.swift:1-46; App/SkriftApp.swift:290-291; App/LaunchArgs.swift:47-48; SkriftMobileUITests/ConversationMockUITests.swift:13-23 | `-conversationMock` static mock; its test has no assertions (→P9) | 62 | low |
| MMD-d02 | two-sources | SpeakerTurnsView.swift:8-12,31-43; MemoDetailSupportTypes.swift:60-64 | `speakerSlots` default `[]` and `slotForTurn` fallback only run for the mock (→P9) | 10 | low |
| MMD-d03 | flag-unread | MemoDetailView.swift:57-60,255-257,815 | `exportedBump` incremented, never read (→P9) | 6 | low |
| MMD-d04 | case-never-built | MemoDetailSupportTypes.swift:78-126 | `PlayerBar.density` is always `.full`. Q121 names it but never removes it: fold into Q121, not P9. | 14 | low |
| MMD-d05 | needless-abstraction | MemoPageView.swift:23-29,419,757-758,1314,1366 | `QuickLookTarget` built 3x only for `.marker` (→P9) | 9 | low |
| MMD-d06 | unreferenced | NoteBodyView.swift:549-555 | private `displayRange(forRaw:transcript:)` has no caller (→P12 with BodyTransform) | 7 | low |
| MMD-d07 | test-only | NoteBodyView.swift:264-269; NoteBodyTests (11 sites), QuotePresentationTests:177 | `Coordinator.init(memo:onCommit: () -> Void)` convenience, 12 test sites (→P9) | 6 | low |
| MMD-d08 | test-only | ConnectionsPanel.swift:72-77; IPadDetailConnectionsTests:33-53 | `ConnectionsPanelLogic.ordered` only called by tests. Land after Q119/Q181 rework the panel. (not queued) | 27 | low |
| MMD-d10 | other | MemoPageView.swift:132-140,636-743 | page `.task` computes backlinks/related that the regular-width iPad never shows. Perf, not dead; fold into Q119/Q120. | 0 | medium |
| MMD-d11 | unreachable | NoteBodyView.swift:207,215-223,334,1122-1125 | `draftDirty` equals `draftTarget != nil`; the fallback never fires. P0-2026-07-10 area, run NoteBodyTests. (not queued, see section 6) | 5 | medium |
| MMD-d13 | needless-abstraction | MemoPageView.swift:194,196,909,919-921 | `enroll:` always true (→P9) | 3 | low |
| MMD-d14 | other | MemoDetailView.swift:4-6; MemoDetailSupportTypes.swift:2-6; MemoPageView.swift:4 | 8 unused import lines (→P9) | 8 | low |
| MMD-d15 | history-comments | MemoDetailView.swift:663-667,743-745; MemoPageView.swift:45,141,148-155,389-393,1547; NoteBodyView.swift:338,521; ConnectionsPanel.swift:4-16,47-53; MemoDetailSupportTypes.swift:78-82 | stale comments, wrong "Q14 removes it" (Q14 kept it) (→P9) | 35 | low |
| MMD-d16 | stringly-typed | MemoDetailView.swift:462-467 vs 130-133 | compact dialog types "Lock Note" where NoteMenuItem says "Lock note"; Q180 touches this dialog (→P9) | 0 | low |
| MMD-d17 | other | SignificanceCircles.swift (whole file); SkriftMobile/project.yml:415-417 | file name outlives the deleted circles; Mac twin has the same name on purpose. Rename both together only. (not queued) | 0 | low |

### SPL shared-pipeline (base `Shared/Pipeline/`)

| id | kind | where | what | lines | risk |
|---|---|---|---|---|---|
| SPL-d01 | test-only | Paragrapher.swift:20-21,32-79; BodyNormaliseMigrationTests:49; FillerFilter.swift:33 | `paragraphed` and `defaultGap` have no production caller (RUN.md:109 says Q80 kept `paragraphed` as the migration fixture on purpose). Move to a test fixture. (→P10) | 50 | low |
| SPL-d02 | test-only | ImageMarkers.swift:1-63; SkriftMobile/Services/Transcription/TranscriptionService.swift:300-318 | v1 `ImageMarkers.insert` is used in production only by the phone's `SeededTranscriber`; make it call `BodyV2.committed`, move the v1 inserter to the fixture (→P10) | 63 | medium |
| SPL-d03 | case-never-built | MemoSpine.swift:19-165 | `QueuePhase`, `Input.queue`, `Input.macLocalFile` and Station `.processing/.stuck/.ready/.exported` never built by production (→P12) | 32 | medium |
| SPL-d04 | unreferenced | Karaoke.swift:26-38 | `activeWordIndex(_:at:hint:)` overload, no caller (→P11) | 13 | low |
| SPL-d05 | other | TranscribingContract.swift:14; ASRPostProcess.swift:31-69; both TranscriptionService files; StubEngines.swift:18 | `TranscriptionResult.durationMs` written by every engine, read nowhere (22 test/stub sites) (→P11) | 16 | low |
| SPL-d06 | unreferenced | ProcessPile.swift:35-38 (isDone: Q102 owns it); SplitSpeakersCopy.swift:14; ASRLanguageMode.swift:63-65; VocabularyTermParsing.swift:47-49; KaraokeTrack.swift:109; CommitOnceCache.swift:33-37 | six members with no production caller. `isDone` goes inside Q102; `rateFirstShort` is signed Q86 copy, keep unless Tuur says. (→P11, minus those two) | 17 | low |
| SPL-d07 | copy-paste | MemoLifecycle.swift:74-77,189; MemoSpine.swift:221-224; WayOut.swift:37-40 | `daysUntilSweep` has no production caller; ceil-days written 3x (→P12) | 10 | low |
| SPL-d08 | needless-abstraction | AlignmentCore.swift:41-70 | explicit `Config.init` duplicates the memberwise one; only `anchorN` is ever overridden (→P11) | 16 | low |
| SPL-d10 | unreachable | Karaoke.swift:100-105 | two unreachable fallbacks in `wordTimes` (→P11) | 2 | low |
| SPL-d11 | dead-chain | BodyTransform.swift:78-104; NoteBodyView.swift:548-555 | single-range `displayRange(forRaw:in:)` has one test caller after the wrapper dies; `displayLength` ignores its param (→P12) | 30 | low |
| SPL-d12 | flag-unread | VoiceMatcher.swift:20-25 | defaults key `voiceMatchThreshold` is never written by the app; documented manual tuning hook, taste (not queued) | 5 | low |
| SPL-d13 | needless-abstraction | TranscribingContract.swift:23-51 | spill-to-WAV default is reached only by test conformers but the phone `BookTranscriptionJob` dispatches through the shared protocol; keep (not queued) | 14 | medium |
| SPL-d14 | stale-workaround | MemoLifecycle.swift:147-184; RootView.swift:164; SkriftApp.swift:132,201 | one-shot 2026-07-22 one-clock migration; delete only when prod phone and prod Mac have each run it (→P14, tuur) | 42 | medium |
| SPL-d15 | flag-unread | EPubParse.swift:275,292,333-339,500-504 | `EPubTOCEntry.fragment` parsed, never read (→P11) | 9 | low |
| SPL-d16 | history-comments | Karaoke.swift:40-71; AlignmentCore.swift:8-14; Paragrapher.swift:11-15,23-29; MemoSpine.swift:5-9; BodyTransform.swift:74-77,92-93 | stale headers (→P11) | 40 | low |
| SPL-d17 | test-only | Karaoke.swift:118-136; KaraokeTrack.swift:59-69 | `seekTarget`'s `timings` branches reached only by QuoteSeekTests (→P11) | 9 | low |
| SPL-d18 | needless-abstraction | BPEMerge.swift:72-93 | rms/wordCount overload of `shouldDropAsPhantom` called only by itself and tests (→P11) | 6 | low |

### DRV d-review (base `SkriftDesktop/Features/Review/`)

| id | kind | where | what | lines | risk |
|---|---|---|---|---|---|
| DRV-d01 | unreferenced | ConnectionsPanel.swift:50 | `ConnectionsModel.count` no reader (→P15) | 3 | low |
| DRV-d02 | flag-unread | UnratedNotePane.swift:15,19-21,56; Features/Shell/RootView.swift:101-107 | `onRated` called, consumer is a no-op (dup in DSH-d04, DAU) (→P15) | 9 | low |
| DRV-d03 | unreferenced | SignificanceCircles.swift:15-16,20-21 | `MacRatingRow` `enabled`/`fadingLine` never set (→P15) | 3 | low |
| DRV-d04 | unreachable | NoteDisplayView.swift:24-28,233,641 | nil guard in `capabilities` unreachable; line 233 retypes `inspectorOpen` (→P15) | 4 | low |
| DRV-d05 | unreachable | NoteActions.swift:35,91 | `isConversation, file.sourceType == .audio` redundant (→P15) | 0 | low |
| DRV-d06 | copy-paste | NoteActions.swift:75-124 | copy buttons written in both overflow branches (→P15) | 3 | low |
| DRV-d07 | copy-paste | SplitSpeakersRow.swift:57,67 | `editedAt` set twice; leave (guards first render) | 1 | low |
| DRV-d09 | copy-paste | NoteProperties.swift:170-207 | title section duplicates `titleLine` (→P15) | 9 | low |
| DRV-d10 | copy-paste | NoteProperties.swift:125-126 | two `.onChange(of: file.significance)` (→P15) | 1 | low |
| DRV-d11 | history-comments | ReviewHelpers.swift:4-6,35-43; SignificanceCircles.swift:4-7; NoteActions.swift:5-7; NoteProperties.swift:9; ConnectionsPanel.swift:41-42; BodyTextView.swift:14-17,193,505 | tombstones and false statements (→P15) | 25 | low |
| DRV-d12 | other | BodyTextView.swift:5-18,1215-1218; NoteDisplayView.swift:330-331,454-458; NoteActions.swift:54-64 | doc comments on the wrong declaration (→P15) | 0 | low |
| DRV-d13 | other | SignificanceCircles.swift | file name outlives contents; phone twin has same name on purpose (not queued) | 0 | low |
| DRV-d14 | two-sources | BodyTextView.swift:99-103,572-587; NoteBody.swift:167,272-287 | "what is a word" implemented four times, one with a surrogate bug (→P17) | 10 | medium |
| DRV-d15 | unused-harness | NoteBody.swift:15,54-118,189-211,211-288; NoteDisplayView.swift:29-31,287-291,556-569; NoteProperties.swift:179-188,255-262; SplitSpeakersRow.swift:73-76 | second SwiftUI-Text renderer exists only for the ImageRenderer snapshot path; move the three snapshots to the hosted render first (→P16, tuur) | 150 | medium |
| DRV-d16 | unused-harness | BodyTextView.swift:43-46,93-103 | `KaraokePlayback.init(fractionOf:fraction:)` only used by DEBUG snapshots (→P15) | 6 | low |
| DRV-d17 | copy-paste | BodyTextView.swift:597-613,980-999,1165-1182 | three attachment walkers share a type switch (not queued, medium taste) | 10 | medium |
| DRV-d19 | needless-abstraction | NoteDisplayView.swift:586-590 | `sourceLabel(_:)` one caller, inline (→P15) | 5 | low |
| DRV-d-m1 | other (**missed**) | BodyTextView.swift:577-579 | `UnicodeScalar(c) ?? UnicodeScalar(32)` on a UTF-16 unit turns a surrogate half into whitespace, so an emoji splits a word and karaoke index drifts. A bug, not dead code (→P17) | 0 | medium |
| DRV-d-m2 | other (**missed**) | NoteDisplayView.swift:71-93 | `NoteCapabilities: Equatable` conformance unused (→P15) | 0 | low |

### DSH d-shell (base `SkriftDesktop/`)

| id | kind | where | what | lines | risk |
|---|---|---|---|---|---|
| DSH-d01 | unreferenced | Features/Theme/Theme.swift:42 | `Theme.violet` (→P18) | 1 | low |
| DSH-d02 | unreferenced | Features/Shell/LifecycleSweepScheduler.swift:49,57 | `activationObserver` written, never read (→P18) | 2 | low |
| DSH-d03 | dead-chain | Features/Shell/LiveRecordingSession.swift:203-211; Engines/MacRecorder.swift:322-331 | `cancel()` has no caller; QUEUE.md:1225 plans recording recovery and may wire it. Delete, or leave to that item. (not queued) | 19 | low |
| DSH-d04 | unreferenced | Features/Shell/RootView.swift:101-107; Features/Review/UnratedNotePane.swift | dup of DRV-d02 | 0 | low |
| DSH-d05 | unused-harness | Features/Shell/DemoSeed.swift:19-61; RootView.swift:167-177 | `-naming-demo` and `seedNamingDemo`, invoked by nothing (`-snapshot-naming` covers it) (→P18) | 52 | low |
| DSH-d06 | other | Features/Shell/DemoSeed.swift:1-17,63-195; RootView.swift:178-179 | `-demo` branch not under `#if DEBUG`: a Release launch with `-demo` seeds fake notes into an empty real store (→P18) | 0 | low |
| DSH-d07 | unused-harness | Features/Shell/RunFile.swift:7,574-632; App/SkriftDesktopApp.swift:58; project.yml:19-21,161-162 | finished `-aligncheck` spike; only Mac user of ZIPFoundation. Only headless way to run AlignmentCore on a real ePub (→P19, tuur) | 65 | medium |
| DSH-d08 | unused-harness | RunFile.swift:3-4,383-471; SkriftDesktopApp.swift:46 | `-asrsweep` (+ `wer`, `wordCount`, `import CoreML`); two comments cite it as the language-mode evidence (→P19, tuur) | 88 | medium |
| DSH-d09 | unused-harness | RunFile.swift:320-332; SkriftDesktopApp.swift:49 | `-audiodate` probe whose purpose is done. `-asrbench` is cited by FEATURES.md:183, keep (→P19) | 14 | low |
| DSH-d10 | copy-paste | RunFile.swift:21-45 vs 142-174 | `-readalongcheck` re-implements `anchorDrift`; harness must stay (→P22) | 14 | low |
| DSH-d11 | copy-paste | ProcessingCoordinator.swift:669-675,698-702; BatchRunner.swift:278-282; MemoCloudUpdate.swift:152-160 | four copies of the conversation-vs-monologue relink block (→P20) | 8 | medium |
| DSH-d12 | copy-paste | ProcessingCoordinator.swift:144-155,276-283,625-632 | run lifecycle pasted in runProcess, runTranscribe, redo (→P21) | 20 | medium |
| DSH-d13 | unreferenced | ProcessingCoordinator.swift:520,489 | `diarizationSlot(of:in:)` ignores `pf` (→P18) | 0 | low |
| DSH-d14 | needless-abstraction | RootView.swift:9,35-39 | `@State coordinator` has a default and init overwrites it (→P18) | 0 | low |
| DSH-d15 | history-comments | RootView.swift:26-29,211-213; LiveRecordingSession.swift:12-14; Snapshot.swift:495-511; Theme.swift:9-14; RunFile.swift:926-927 | stale comments (→P28) | 30 | low |
| DSH-d16 | needless-abstraction | Features/Shell/AppModel.swift:40-45; Features/Journal/JournalView.swift:181-203,274-276 | single-case `ReviewShelf` is a Bool; The AppModel comment says the single case is deliberate, so this is a style call (→P18) | 10 | low |
| DSH-d17 | unreferenced | AppModel.swift:12-13 | `SidebarSort` raw values never read (→P18) | 1 | low |
| DSH-d18 | flags-not-enum | Snapshot.swift:36-108,1234,1268 | light mode selected two ways; unused `scheme` defaults. Debug-only, low value (not queued) | 8 | low |
| DSH-d19 | unused-harness | Snapshot.swift:41-43,1135-1170,1329-1334; ProcessingCoordinator.swift:68-73 | `-snapshot-wizard`, `-snapshot-run`, `-snapshot-settings` and `ProcessingCoordinator.preview` (→P19, tuur) | 45 | low |
| DSH-d20 | unreachable | ProcessingCoordinator.swift:134,271 | `guard !isRunning` in the two private run functions cannot fire (→P21) | 2 | low |
| DSH-d21 | other | ProcessingCoordinator.swift:110-130,609-632 | **bug**: `redo` sets `isRunning` itself and nothing drains `waiting` afterwards; a request queued during a redo is stranded (→P21) | 0 | medium |

### DPE d-pipeline-engines (base `SkriftDesktop/`)

| id | kind | where | what | lines | risk |
|---|---|---|---|---|---|
| DPE-d01 | unreferenced | Models/FileDTO.swift:1-29 | `StepsDTO`, `FileDTO`, `UploadResponseDTO` reference only each other (→P23) | 29 | low |
| DPE-d02 | flag-unread | Models/AppSettings.swift:8-9; Features/Shell/RunFile.swift:561-562 | `audioFolder`, `attachmentsFolder` never read in production (→P23) | 4 | low |
| DPE-d03 | flag-unread | Models/AppSettings.swift:108-113; Pipeline/Ingest/MemoCloudReconciler.swift:49,139; MemoCloudIngest.swift:27-40; App/MemoCloudReconciler+Wiring.swift:105-107 | `processEverything` / `processAllSyncedMemos`; SPEC D57 already says delete (→P23) | 20 | low |
| DPE-d04 | flag-unread | AppSettings.swift:39-50,159-162; BatchRunner.swift:146 | `conversationMode` is nil-ed on load; its accessor is false in production. Test rewrite for the legacy-key guard (→P23) | 14 | low |
| DPE-d05 | unreferenced | Engines/TranscriptionService.swift:22-195 | `models`, `ready`, `isModelReady`, `liveCaption()`, unused `stitched` half (→P24) | 20 | low |
| DPE-d06 | unreferenced | Engines/EnhancementService.swift:29; MacRecorder.swift:114,130,272,354 | `isModelReady`, `isRecording`, write-only `deviceInput` (→P24) | 6 | low |
| DPE-d07 | unreferenced | Engines/VocabularyBooster.swift:29-32,44,95-96; TranscriptionService.swift:121-123 | `Boosted.replacementCount` never read; phone twin identical (→P24) | 6 | low |
| DPE-d08 | case-never-built | Models/PipelineFile.swift:7; RunReconciler.swift:15,17; QueueDerivations.swift:47 | `StepStatus.skipped` never assigned. Persisted SwiftData column, keep. | 0 | medium |
| DPE-d09 | other | Pipeline/BatchManager/DiarizationSidecar.swift:41-83; BatchRunner.swift:124-126,174-177; SplitSpeakers.swift:58-60; UploadService.swift:195; MemoCloudIngest.swift:207-226 | Mac `diar_<id>.json` sidecar is write-only in production. SPEC C182 names it, so amend SPEC (→P26, tuur) | 57 | medium |
| DPE-d10 | test-only | Pipeline/BatchManager/RunQueue.swift:69 | `isWaitingSplit` (→P24) | 2 | low |
| DPE-d11 | unreferenced | Pipeline/Ingest/MemoCloudReconciler.swift:93,182-191 | `existingFile` zero callers; keep `SweepOutcome.stranded` (test-asserted) (→P24) | 10 | low |
| DPE-d12 | unreferenced | Pipeline/Ingest/MultipartPart.swift:11; MemoCloudIngest.swift:130-167 | `MultipartPart.contentType` never read (→P27) | 5 | low |
| DPE-d13 | needless-abstraction | Pipeline/Ingest/UploadService.swift:9-14,40-123,301-322; MemoCloudIngest.swift:122-171,234-262 | `buildParts` re-encodes a Memo into fake multipart parts that `prepare` parses back; the Bonjour server it mirrored is retired (→P27) | 60 | medium |
| DPE-d14 | dead-chain | UploadService.swift:138-149; IngestService.swift:498-525 | `extractAudioSync` has one caller, a belt-and-braces video branch (→P27) | 40 | medium |
| DPE-d15 | needless-abstraction | Pipeline/WayOutRules.swift:124-134,168-189 | four pure forwarders to Shared `WayOut.*` (→P25) | 25 | low |
| DPE-d16 | history-comments | IngestService.swift:351-355,587-591,615; MemoNoteProjection.swift:22-27; MacRecorder.swift:27-30; MemoCloudReconciler.swift:7-14; MemoCloudIngest.swift:4-20,97,103,207-208; UploadService.swift:9-14,46-59; AppSettings.swift:39-47 | comments contradict current code (→P28) | 45 | low |
| DPE-d17 | copy-paste | Engines/AudioMetadata.swift:17-23; IngestService.swift:568-575; Models/PipelineFile+BodyNormalise.swift:136-143 | three private ISO-8601 parsers beside shared `ISO8601` (→P25) | 16 | low |
| DPE-d18 | needless-abstraction | IngestService.swift:256-420,678-682; VaultExporter.swift:87-90,202-210; AppSettings.swift:121-131 | `makeFolder` tuple never used, `let vault = picked` alias, one-line `noteStem` wrapper, default prompt aliases (→P25) | 14 | low |
| DPE-d19 | other | Pipeline/Ingest/MemoCloudUpdate.swift:73-134 | `why: [String]` DIAG array read only by a DEBUG log (→P29) | 10 | low |
| DPE-d20 | stale-workaround | SkriftDesktop/project.yml:187-190 | redundant `Pipeline/Recording` entry in the test target (→P18) | 3 | low |
| DPE-d21 | two-sources | Models/PipelineFile.swift:19-21; CompilerBridge.swift:53; Shared/Export/CompilerInput.swift:15-17 | `SourceType` and `NoteSourceType` mirror each other; pin with a test (not queued) | 3 | medium |
| DPE-d22 | flag-unread | MemoCloudIngest.swift:247,251 | `tags`/`transcriptMarkersInjected` in metadata blob are byte-compared; persisted, keep | 0 | medium |
| DPE-d23 | test-only | Models/PipelineFile.swift:238-243 | `steps` setter used only by PipelineFileTests (→P24) | 5 | low |

### DAU d-app-ui (base `SkriftDesktop/`)

| id | kind | where | what | lines | risk |
|---|---|---|---|---|---|
| DAU-d01 | dead-chain | Features/Sidebar/SidebarView.swift:1345-1373; QueueDerivations.swift:20-34 | `StatusPill`, `PulseDot`, `QueueStatus.color/.tint` never used (→P28) | 45 | low |
| DAU-d02 | unreferenced | SidebarView.swift:1326-1343 | `sidebarRowSelection` (→P28) | 16 | low |
| DAU-d03 | unreferenced | SidebarView.swift:48 | `queuedCount` (→P28) | 1 | low |
| DAU-d04 | unreferenced | QueueDerivations.swift:136-147 | `SkriftFormat.shortDate`, `shortDF` (→P28) | 12 | low |
| DAU-d05 | unreachable | SidebarView.swift:203-232 | `asRecording` never true (→P28) | 6 | low |
| DAU-d06 | other | SidebarView.swift:486,302 | `actionButton(filled:)` param unread (→P28) | 1 | low |
| DAU-d07 | flag-unread | SidebarView.swift:76 | `showDateStrip` seeded by an argument nothing passes (→P28) | 0 | low |
| DAU-d08 | unreferenced | Features/Journal/JournalView.swift:16; RootView.swift:46; Snapshot.swift:969,979 | `JournalView.coordinator` never read (→P28) | 4 | low |
| DAU-d09 | unreferenced | Features/Journal/UnpipelinedMemoSheet.swift:31-35,128,222,231 | `backlinked` never passed (→P28) | 8 | low |
| DAU-d10 | unreferenced | Features/Recording/RecordingDraftView.swift:19,56,189; Snapshot.swift:531,535; LiveRecordingSession.swift:63 | `RecordingDraftBody.everEdited` never read (→P28) | 7 | low |
| DAU-d11 | test-only | processEverything chain | dup of DPE-d03 | 0 | medium |
| DAU-d12 | flag-unread | AppSettings.swift:8-9 | dup of DPE-d02 | 0 | low |
| DAU-d13 | flag-unread | AppSettings.swift:48-50 | dup of DPE-d04 | 0 | medium |
| DAU-d14 | stale-workaround | App/MemoCloudReconciler+Wiring.swift:45-215; MemoCloudUpdate.swift:130-134 | 2026-07-27 `syncTrace`, self-labelled "delete once the cause is known"; cause fixed in cd086137 but only Tuur can say the relaunch bug is gone (→P29, tuur) | 30 | low |
| DAU-d15 | needless-abstraction | AppModel.swift:44-45; JournalView.swift | dup of DSH-d16 | 0 | low |
| DAU-d16 | history-comments | SidebarView.swift:14,611-616,906,972-976; WayOutColumn.swift:239-241; JournalView.swift:31-33; MemoCloudContainer.swift:14-20; RecordingDraftView.swift:42-44 | false comments and one false empty-state string "click + Upload" (button says Import) (→P28) | 25 | low |
| DAU-d17 | other | App/SkriftDesktopApp.swift:4 | unused `import FluidAudio` (→P28) | 1 | low |
| DAU-d18 | flag-unread | App/NamesCloudSync.swift:28-30,63-65; App/MacCloudEditSync.swift:21,52 | unread `Bool` result, `var debounce` never assigned (→P28) | 3 | low |
| DAU-d-m1 | unreferenced (**missed**) | Features/Settings/PersonEditor.swift:19,39 | stored `request` never read (→P28) | 2 | low |
| DAU-d-m2 | history-comments (**missed**) | App/SkriftDesktopApp.swift:6-7,83-84; MemoCloudContainer.swift:14-16 | "opt-in" cloud sync comments (defaults ON since 2026-07-26) (→P28) | 0 | low |

### MRC m-recording-capture-ui (base `SkriftMobile/`)

| id | kind | where | what | lines | risk |
|---|---|---|---|---|---|
| MRC-d01 | dead-chain | Features/MemosList/NotesBottomChrome.swift:11-55; MemosListView.swift:264-272 | `showRecordButton`/`recordButton`; already Q173 | 0 | low |
| MRC-d02 | unreferenced | Services/Recording/RecordingActivityManager.swift:69 | `isRunning` (→P31) | 1 | low |
| MRC-d03 | flag-unread | Services/Recording/PhotoCaptureService.swift:16,46,68 | `isReady` written, never read (→P31) | 4 | low |
| MRC-d04 | flag-unread | Services/Recording/LiveRecordingService.swift:28-29,448,634,1019-1022,1671-1673 | `level` written every tap callback, read only by mock (→P31) | 7 | low |
| MRC-d05 | flag-unread | Features/QuickNote/QuickNoteView.swift:20-23; MemosListView.swift:217,372 | `draftID` never read (→P31) | 4 | low |
| MRC-d06 | test-only | Features/Recording/MemoSaver.swift:273-279,511-519 | `importVideoAsync` wrapper (4 tests); leave `saveAndTranscribe` (Tuur kept it in Q62) (→P31) | 6 | low |
| MRC-d07 | test-only | Services/Recording/RecordingCheckpoint.swift:14-32 | `RecordingLifecycleLog` mirror read only by a test; low value (not queued) | 11 | low |
| MRC-d08 | flag-unread | Features/Recording/RecordingRecovery.swift:10-21,84 | `RecordingSweepReport.kept` (→P31) | 3 | low |
| MRC-d09 | test-only | Services/QuickNote/NoteRoute.swift:24-27; QuickNoteDraft.swift:39-57 | `isDraft`; `edited` return value (→P31) | 6 | low |
| MRC-d10 | unreachable | MemoSaver.swift:301-311,404-423 | `extractAudio` throws or returns literal true (→P31) | 5 | low |
| MRC-d11 | flag-unread | MemoSaver.swift:526-546; RecordView.swift:568-569 | `duration:` param of `appendRecording*` only logged (→P31) | 3 | low |
| MRC-d13 | needless-abstraction | LiveRecordingService.swift:1436-1463,1312-1317 | `RebuildAction` has 3 cases, only one branched on; decision table in hardware code, skip (not queued) | 10 | medium |
| MRC-d14 | needless-abstraction | LiveRecordingService.swift:1597-1604; LiveCaptionCadenceTests | `captionPollDelay` forwarder (→P31) | 8 | low |
| MRC-d15 | needless-abstraction | RecordView.swift:597-600 | `RecordClock` forwarder (→P31) | 4 | low |
| MRC-d16 | other | LiveRecordingService.swift:734-741; RecoverySweepTests:207-211 | `memoryWarningOrder` restates `MemoryWarningStep` (→P31) | 2 | low |
| MRC-d17 | reinvented | MemoSaver.swift:658-696 | `appendAudio` still uses AVMutableComposition + export; see MRC-c01 (→P33, tuur) | 15 | medium |
| MRC-d18 | two-sources | LiveRecordingService.swift:1246 vs 234-237 | media-services reset sets hard-coded category options, bypassing the HFP policy (→P34, tuur) | 0 | medium |
| MRC-d19 | history-comments | LiveRecordingService.swift:210-218; RecordingIntentBridge.swift:4-9,30; MemosListView.swift:338-340 | orphaned `settleSession` doc, stale bridge header (→P31) | 70 | low |
| MRC-d20 | copy-paste | MemoSaver.swift:91,174,195,328; RecordingRecovery.swift:147; LiveRecordingService.swift:571,688 + 4 outside | `Double(f.length) / f.fileFormat.sampleRate` x11 (→P32) | 14 | low |
| MRC-d21 | stringly-typed | RecordView.swift:52; LiveRecordingService.swift:167,445,469; SettingsView.swift:7,10,15; MemoSaver.swift:30 | UserDefaults key literals (→P51) | 0 | low |
| MRC-d24 | magic-numbers | RecordView.swift:840; LiveRecordingService.swift:33,75 | bar count 40 three times (→P31) | 0 | low |
| MRC-d25 | stale-workaround | MemosListView.swift:317-319 | closed-investigation DevLog (→P31) | 3 | low |
| MRC-d26 | other | RecordingRecovery.swift:79,103,209; RecordingCheckpoint.swift:19 | "rec rec quarantined" log prefix doubled (→P31) | 0 | low |

### MLJ m-list-journal-settings (base `SkriftMobile/`)

| id | kind | where | what | lines | risk |
|---|---|---|---|---|---|
| MLJ-d01 | flag-unread | Features/MemosList/NotesBottomChrome.swift; MemosListView.swift:260-272 | record button chain; already Q173 | 0 | low |
| MLJ-d02 | unreferenced | NotesBottomChrome.swift:58-77 | `SelectableCard` ViewModifier never referenced; add to Q173 or take in P35 (→P35) | 20 | low |
| MLJ-d03 | unreachable | MemosListView.swift:40-52; MemosListView+Derived.swift:158-159 | `MemoFilter.hasPhotosOnly/.place/.isActive`; already in Q110, gated on Tuur | 0 | low |
| MLJ-d04 | unreachable | MemosListView+Row.swift:18-90; MemosListView.swift:505-510 | `quietLine` plumbing always nil on the phone (Mac sets it, keep the Shared field) (→P35) | 16 | low |
| MLJ-d05 | unreachable | Features/Feedback/FeedbackMailComposer.swift:14-95 | `init(items:)` has no caller; multi-item code dead (→P36) | 14 | low |
| MLJ-d06 | unreferenced | Features/Feedback/FeedbackStore.swift:14-123 | `count`, `delete`, observable `items` and the loader chain, `screenshotURL`, `hasScreenshot`, `durationSeconds` unused. Keep the on-disk `metadata.json` shape (the pull-phone-feedback skill reads it) (→P36) | 30 | low |
| MLJ-d07 | flag-unread | App/LaunchArgs.swift:32-40 | `destinationsOn`, `seedPortfolioFolder`, `selectFirstMemo` accessors unread (raw reads at NoteDestination.swift:145 and PortfolioVault.swift:54 stay) (→P35) | 10 | low |
| MLJ-d08 | flag-unread | Features/Root/AppTabView.swift:35-36; LaunchArgs.swift:59-61,90-92 | `-openJournal`/`-openSettings` superseded by `-openTab` (→P35) | 8 | low |
| MLJ-d09 | unused-harness | AppTabView.swift:41-122; LaunchArgs.swift:65-90; AudiobookSeeder.swift | `-showTOCSheet`, `-showTextSheet`, `-showTextPrompt`, `-seedAudiobook`, `-seedDetectedChapters`, `-showFilterSheet` have no invoker; lane briefs say keep (manual screenshot rig). Tuur's call (see "Needs Tuur") | 55 | medium |
| MLJ-d11 | history-comments | MemosListView.swift:99-103; +Header.swift:6-17,304-306; +Actions.swift:78-110; WayOutView.swift:7-8,243-244; JournalHomeView.swift:159-160; PersonDetailView.swift:4-8 | orphan and false comments (NamesListView items are Q113) (→P35) | 40 | low |
| MLJ-d12 | two-sources | Features/Names/NamesListView.swift:22-26,165-206 | `AddPersonView` duplicates `PersonEditorView(canonical: nil)`; fold into Q113 | 0 | medium |
| MLJ-d13 | other | MemosListView.swift:317-337; +Derived.swift:135-140 | closed-investigation diagnostics, DEBUG-only (→P35) | 26 | low |
| MLJ-d14 | needless-abstraction | Features/MemosList/WayOutView.swift:279-312; WayOutViewTests:27-100 | `orderedByImminence`/`oneLiner`/`total` forwarders to Shared `WayOut`; same pass as Q178 (→P52) | 22 | low |
| MLJ-d15 | copy-paste | MemosListView+Derived.swift:44-50; MemoLifecycle.swift:92-100 | `lifecycle(backlinked:)` repeats `MemoLifecycle.partition` (→P52) | 7 | low |
| MLJ-d16 | other | MemosListView.swift:6-37 | `Identifiable` on `MemoSort`/`MemoDateField`, unused raw values (→P35) | 3 | low |
| MLJ-d17 | stringly-typed | WayOutView.swift:54; JournalHomeView.swift:20; ContinueListeningCard:27; ObsidianSettingsSection.swift:27; SettingsView.swift:12-15 | UserDefaults key literals (→P51) | 0 | low |

### MSV m-services (base `SkriftMobile/Services/`)

| id | kind | where | what | lines | risk |
|---|---|---|---|---|---|
| MSV-d01 | unreferenced | Export/PublishCoordinator.swift:23,40; PublishCoordinatorTests:24,33 | `memosProvider` never read (→P38) | 4 | low |
| MSV-d02 | unreachable | PublishCoordinator.swift:15-113; PublishCoordinatorTests; UnratedConsentTests:49-55 | paired-mode and `Policy.all` legs of the export gate cannot fire in production (`isMacPaired { false }`, `.importantOnly`). plan/extraction/code-core.md:260 holds it as needs-verdict (→P39, tuur) | 30 | medium |
| MSV-d03 | two-sources | PublishCoordinator.swift:60-86 vs 94-113; MemoDetailView.swift:769-790 | `shouldPublish` and `exportRefusal` carry the same guard list twice (→P39) | 20 | low |
| MSV-d04 | test-only | NotesRepository.swift:137-140; MemoAssetTests | `allAssets()` unscoped blob fetch, no production caller (→P38) | 2 | low |
| MSV-d05 | test-only | NotesRepository.swift:117-118,268-275; MemoModelTests:65 | `delete(_:)` has one test caller (→P38) | 8 | low |
| MSV-d06 | unreferenced | MemoDeduper.swift:43-46 | `isContentClone` pass-through (→P38) | 4 | low |
| MSV-d07 | unreferenced | Capture/CaptureInbox.swift:246-250 | `imageURL(for:entryDir:)` singular (→P38) | 5 | low |
| MSV-d08 | unreachable | CaptureInbox.swift:156-176 | `imageData:` param of `write` never passed; keep persisted `imageFileName` (→P38) | 6 | low |
| MSV-d09 | unreferenced | Export/ObsidianPublisher.swift:40; PortfolioVault.swift:48 | `clear()` x2 (→P38) | 3 | low |
| MSV-d10 | unreferenced | Transcription/TranscriptionService.swift:43; Diarization/SpeakerEmbedder.swift:40; DiarizationService.swift:27 | three phone `isModelReady` (→P38) | 3 | low |
| MSV-d11 | unreferenced | SpeakerEmbedder.swift:17-77; DiarizationService.swift:31 | `ensureLoaded` on the `SpeakerEmbedding` protocol (→P38) | 4 | low |
| MSV-d12 | dead-chain | TranscriptionService.swift:260-266; Shared/Recording/LiveCaptionEngine.swift:266-270 | `finishStream()` and `LiveCaptionEngine.finish()` (→P38) | 11 | low |
| MSV-d13 | unreferenced | TranscriptionService.swift:29-33 | `multilingualKey` alias (→P38) | 5 | low |
| MSV-d14 | test-only | Metadata/WeatherClient.swift:20-38; WeatherKeyTests | `setAPIKey`. Legacy-key fallback is Tuur's call. (→P38, setAPIKey only) | 10 | low |
| MSV-d15 | flag-unread | TranscriptionService.swift:66-67 | `useANE` defaults key read, never written (→P38) | 1 | low |
| MSV-d16 | unreferenced | Transcription/VocabularyBooster.swift:65-68,129-130 | `Boosted.replacementCount` (phone twin of DPE-d07) (→P24) | 0 | low |
| MSV-d17 | two-sources | App/LaunchArgs.swift:34-37; Export/PortfolioVault.swift:54 | `seedPortfolioFolder` has two definitions (→P35) | 0 | low |
| MSV-d18 | needless-abstraction | TranscriptionService.swift:290-294; LiveCaptionCadenceTests | `shouldRotate` forwarder (→P38) | 5 | low |
| MSV-d19 | copy-paste | Capture/CaptureInboxDrainer.swift (8 sites); CaptureInbox.swift:187-208 | remove-then-copy x11. Touches the file Q134 and Q145 edit; not queued (see section 6) | 15 | medium |
| MSV-d20 | history-comments | NotesRepository.swift:166-190; Polish/PolishCenter.swift:300-302 | `hasAsset` doc on the wrong function; keep the PolishCenter verdict note (→P38) | 0 | low |
| MSV-d-m1 | other (**missed**) | SkriftShare/ShareViewController.swift:15; Desktop Engines/TranscriptionService.swift:192-194 | stale doc mentions of removed signatures (→P38) | 0 | low |

### MAM m-app-models-ext (base `SkriftMobile/`)

| id | kind | where | what | lines | risk |
|---|---|---|---|---|---|
| MAM-d01 | unreferenced | App/LaunchArgs.swift:18,31-40 | `destinationsOn`, `seedPortfolioFolder`, `selectFirstMemo`, `intValue`; dup of MLJ-d07 | 1 | low |
| MAM-d02 | unreferenced | LaunchArgs.swift:59-61; AppTabView.swift:35-36 | dup of MLJ-d08 | 0 | low |
| MAM-d03 | unused-harness | LaunchArgs.swift:139-151; SkriftApp.swift:43-61 | DEBUG one-shot P0 restore hook (`-restoreEnhancementMemo`), restore aborted (→P43) | 33 | low |
| MAM-d04 | dead-chain | Models/MemoDisplay.swift:57-76; Shared/Pipeline/MemoLifecycle.swift:125-131; TrashTests:192-217; MemoLifecycleTests (both) | `trashCountdownLabel` → `trashDaysRemaining` → `MemoLifecycle.goneAt` reached only by tests; shipped countdown uses MemoSpine (→P43) | 55 | low |
| MAM-d05 | test-only | Models/Memo+Mobile.swift:114-162; NameResolutionTests | `nameSpans(people:)`, `clearNameResolution(alias:)` test-only; wait for Q116 (not queued) | 14 | low |
| MAM-d07 | case-never-built | Models/MemoDisplay.swift:329-340; MemosListView+Row.swift:96-101 | `MemoStatusKind.synced/.waiting` never produced (the chip is Q110) (→P43) | 8 | low |
| MAM-d08 | case-never-built | DesignSystem/Components.swift:55-78 | `PillStyle.synced/.waiting` never built (→P43) | 8 | low |
| MAM-d09 | unreferenced | DesignSystem/Components.swift:3-5,31-50,151-173; Theme.swift:87-101 | `TagChipStyle`, `Theme.Space.sm/md/lg`, `Radius.chip/sheet/group`, `SectionLabel.trailing` unused (→P43) | 18 | low |
| MAM-d10 | unused-harness | App/DemoDataSeeder.swift; LaunchArgs.swift:56-58,99-101 | `-seedJournal`, `-journalMemoDemo`; lane brief says keep (manual rig). Tuur's call | 65 | low |
| MAM-d11 | unused-harness | AudiobookSeeder.swift; AppTabView.swift | dup of MLJ-d09 | 0 | low |
| MAM-d12 | unused-harness | MemosListView.swift:108,280-282; PolishBootstrap.swift:17-67 | `-initialSearch`, `-showFilterSheet`, `-fakePolish*`; fake polish engine is a deliberate sim rig. Not queued. | 45 | low |
| MAM-d13 | test-only | Features/MemoDetail/ConversationMockView.swift | dup of MMD-d01 | 0 | low |
| MAM-d14 | dead-chain | SkriftShare/ShareSheetView.swift:20,776-841; ShareViewController.swift:92-185; CaptureInbox.swift:164-186 | share-side dictation retired 2026-07-10; nil data threaded through three layers (→P41); drain half → P42 | 30 | medium |
| MAM-d15 | flag-unread | SkriftShare/SharePayloadLoader.swift:27,404 | `SharedImageItem.mimeType` never read (→P43) | 2 | low |
| MAM-d16 | copy-paste | SkriftShare/SharePayloadLoader.swift:194-454 | temp-copy block x4; touches Q132/Q133/Q150 area (not queued) | 15 | low |
| MAM-d17 | copy-paste | SkriftWidget/RecordWidget.swift vs NewNoteWidget.swift | two widgets differ only in strings, symbol, URL, kind (→P44) | 60 | low |
| MAM-d18 | flag-unread | SkriftShared/RecordingActivityAttributes.swift:34-39 | `sessionId`, static `startedAt` never read; ActivityKit wire shape (not queued) | 6 | medium |
| MAM-d19 | other | project.yml:412-432 (SkriftShare sources) | extension compiles Components.swift and the tag trio nothing there uses (→P44, build check) | 0 | medium |
| MAM-d20 | other | App/SkriftApp.swift:17-23; DemoDataSeeder.swift:16-18; NamesSeeder.swift | seeders compile into Release; `seedIfRequested` runs `repo.allMemos()` on every production launch (→P43) | 0 | medium |
| MAM-d21 | copy-paste | MemosListView.swift:424-443 vs Components.swift:151-172 | inline `SearchField` copy; Q177 owns the search field (not queued) | 16 | low |
| MAM-d22 | history-comments | SkriftWidget/SkriftLiveActivity.swift:17-19; project.yml:308,335; ShareViewController.swift:3,15; SharePayloadLoader.swift:76-77 | stale 8a/8b comments, unused import (→P43) | 12 | low |
| MAM-d-m1 | test-only (**missed**) | Models/MemoDisplay.swift:201-215 | `Memo.rambleSnippet` only used by BookCaptureDisplayTests; delete or wire (→P43, ask) | 14 | low |

### SMU shared-model-ui-body (base `Shared/`)

| id | kind | where | what | lines | risk |
|---|---|---|---|---|---|
| SMU-d01 | dead-chain | SkriftMobile Components.swift:55-72; MemoDisplay.swift:329-338 (pills); Memo.swift:73,216,238; chip is Q110 | dead pill/status enums; dup of MAM-d07/d08. The `Unsynced` chip and `.synced` seed stay with Q110 | 0 | low |
| SMU-d03 | unreferenced | App/LaunchArgs.swift:32-34 | dup of MLJ-d07 | 0 | low |
| SMU-d04 | test-only | Model/ThreeBallScale.swift:53-57,72-76 | `toggling`, `syncCopy` called only by tests (both apps) (→P46 shared) | 24 | low |
| SMU-d05 | test-only | Model/Memo.swift:291-314; NoteDestinationTests:104-118 | `Memo.splitTagInput` (→P46 shared) | 40 | low |
| SMU-d06 | dead-chain | UI/TagRules.swift:47-80; TagRulesTests (Desktop) | `Fold`/`folds`/`keptSpelling` read only by tests (→P46 shared) | 14 | low |
| SMU-d07 | unreferenced | BodyV2/BodyNormaliseMigration.swift:147-150 | `remap(_:from:to:)` no caller (→P46 shared) | 4 | low |
| SMU-d08 | two-sources | SkriftDesktop Pipeline/DesktopTrash.swift:4-8; PipelineFile.swift:205-213 | `DesktopTrashPolicy` duplicates `TrashPolicy`; dup of DPE (→P25) | 0 | low |
| SMU-d09 | history-comments | BodyV2/BodyV2.swift:5-6; Model/Memo.swift:36-41,91-95; others | false statements: "nothing calls BodyV2" (15+ callers), SharedContent "mobile-typed", rating "gates sync" (→P46 shared) | 0 | low |
| SMU-d11 | needless-abstraction | BodyV2/BodyV2Legacy.swift:89-90; UI/EditConflictViews.swift:265; Model/NoteTitle.swift:24 | private marker literal duplicates `BodyV2Marker.literal`, no-op `.interactiveDismissDisabled(false)`, `clip(limit:)` never passed; NoteTitle overlaps the open NoteTitleLadder item (→P46 shared) | 4 | low |
| SMU-d-m1 | other (**missed**) | BodyV2Legacy.swift:18-20 | `isUnnormalised` one-line pass-through (→P46 shared) | 3 | low |

### SRS shared-rest (base `Shared/`)

| id | kind | where | what | lines | risk |
|---|---|---|---|---|---|
| SRS-d01 | unreferenced | Naming/NameUnlinking.swift:49-58 | `hasCanonicalLink` no caller; fix FEATURES.md:347 (→P47) | 10 | low |
| SRS-d02 | test-only | Naming/NameUnlinking.swift:61-67,82-90; UnlinkTests; DiarizationTests:363 | `unlinkOccurrence`, `relinkOccurrence` test-only, ~10 tests go (→P47) | 17 | medium |
| SRS-d03 | unreachable | Naming/Sanitiser.swift:37-39,209-282 | `wholeWord`, `avoidInside`, `preservePossessive` are `static let = true` (→P47) | 9 | low |
| SRS-d04 | flag-unread | Sanitiser.swift:51,65 | `Overrides.prunedKeys` never read (→P47) | 2 | low |
| SRS-d05 | test-only | Naming/SafeJSONStore.swift:28-124 | `CorruptFileRegistry` is the SPEC C265 surfacing mechanism with no UI yet; keep (trim `Entry.at` only) | 8 | medium |
| SRS-d06 | dead-chain | Recording/LiveCaptionEngine.swift:178-183; both TranscriptionService files | `caption()` / `liveCaption()` no caller (→P38 phone, P24 Mac; shared half → P47) | 12 | low |
| SRS-d07 | dead-chain | LiveCaptionEngine.swift:266-270; TranscriptionService.swift | `finish()`; dup of MSV-d12 | 0 | low |
| SRS-d08 | test-only | LiveCaptionEngine.swift:361-368 | `shouldRotate` + forwarder test-only; dup of MSV-d18 | 8 | low |
| SRS-d09 | copy-paste | SkriftMobile Services/Recording/LiveRecordingService.swift:1551-1560 vs LiveCaptionEngine.swift:422-431 | phone `copyBuffer` is identical to the shared one the Mac uses (→P32) | 10 | low |
| SRS-d10 | flag-unread | Corpus/CorpusSeed.swift:68-84 | `Note.expect`/`Expect` decoded, never read (DEBUG file) (→P47) | 17 | low |
| SRS-d11 | test-only | CorpusSeed.swift:89-106 | `NameOffsets` used only by tests (DEBUG only); skip | 0 | low |
| SRS-d12 | flag-unread | Naming/PersonEditCore.swift:44-64 | `materialise` returns `renamedFrom`, nothing uses it (→P47) | 7 | low |
| SRS-d13 | test-only | Retrieval/EmbeddingIndex.swift:170-173 | `rowCount(for:)` deliberate test seam; keep | 0 | low |
| SRS-d14 | other | Retrieval/MemoGist.swift:29-38 | `people` arg always `[]`; Q168 owns what gets embedded (not queued) | 3 | low |
| SRS-d15 | flag-unread | Export/VaultWrite.swift:38,361 | `ExportLedger.Entry.exportedAt` never read (→P47) | 2 | low |
| SRS-d16 | other | VaultWrite.swift:212-221 | `VaultWriter` `var` folders and `now` never overridden (→P47) | 6 | low |
| SRS-d17 | stale-workaround | ModelDownload/ResumableModelDownloader.swift:36-239 | `hubCacheCopy` migration shim; depends on device state, Tuur's call (not queued) | 6 | medium |
| SRS-d18 | reinvented | NameLinking.swift:69; Compiler.swift:308; BodyTextView.swift:1091 | pipe split already done by `Sanitiser.linkDisplay` (→P48) | 6 | low |
| SRS-d19 | copy-paste | Sanitiser.swift; NamesStore.swift; Compiler.swift; SpeakerTurnStyle.swift; RosterAudit.swift | `keyName + trim + lowercased` x11 (→P48) | 10 | low |
| SRS-d20 | other | plan/periphery.md | several old CHECK symbols are live (LockGate, wikiNames, gistPairScores...); update the doc (→P47) | 0 | low |

### PER periphery (repo-wide)

| id | kind | where | what | lines | risk |
|---|---|---|---|---|---|
| PER-d01 | unused-harness | GlassLab/ (GlassLabApp.swift 263, GlassLabUITests 50, project.yml) | throwaway glass harness; real glass is in MemoDetailView and GlassUITests. Archive, never delete (→P50) | 313 | low |
| PER-d02 | unused-harness | DiarizeSpike/ (198 + Package.swift) | finished spike; Package pins FluidAudio `branch: main`, apps pin a revision. Three code comments cite it (→P50) | 198 | low |
| PER-d03 | unused-harness | spikes/EmbeddingBakeoff/ | finished bake-off cited by five live paths (README, GemmaEmbedder.swift:9...). Verifier-2 refuted; leave | 0 | low |
| PER-d04 | unreferenced | SkriftMobile/scripts/mklongm4a.swift | one-off generator, only a FEATURES.md:158 cell mentions it (→P50) | 36 | low |
| PER-d05 | dead-chain | ShareSheetView.swift; ShareViewController.swift; CaptureInbox.swift; ShareFlowProbeUITests (`testDictationRecordingInSheet`) | MAM-d14 plus the UI test of controls that no longer exist; 47 lines beyond MAM-d14's 30 (→P41) | 47 | low |
| PER-d06 | dead-chain | Services/Capture/CaptureDictation.swift (120); CaptureDictationTests (174); CaptureInboxDrainer.swift:169,566-598,651-653; CaptureInbox.swift:39,252-256 | drain-side half of the retired share dictation; only matters for pre-build-63 pending entries (→P42, tuur) | 300 | medium |
| PER-d07 | flag-unread | LaunchArgs.swift:139-151; SkriftApp.swift:41-60 | dup of MAM-d03 | 0 | low |
| PER-d08 | unreferenced | ConversationMockView + test | dup of MMD-d01 | 0 | low |
| PER-d09/d10 | flag-unread | LaunchArgs.swift | dup of MLJ-d07, MLJ-d08 | 0 | low |
| PER-d12 | unused-harness | SkriftDesktop/Features/Shell/StubEngines.swift (35); ProcessingCoordinator.swift:33-66,186,285,376,496,637 | `-stubEnhancement`, StubTranscriber/StubEnhancer and five `stubbedEngines` guards; nothing launches it (→P18) | 62 | low |
| PER-d13 | unused-harness | RunFile.swift:181-213,293-384; SkriftDesktopApp.swift:45-50 | `-asrbench`, `-vaultpreview`, `-audiodate`, `-voiceloop`. `-voiceloop` clears and restores Dev names.json with no defer (data-loss row 31). FEATURES.md:74,183 and decisions.md:334 cite them (→P19, tuur) | 109 | low |
| PER-d14 | stale-workaround | MemoCloudReconciler+Wiring.swift; MemoCloudUpdate.swift:73-133 | dup of DAU-d14 and DPE-d19 (→P29) | 0 | low |
| PER-d15 | other | SkriftMobile/App/DemoDataSeeder.swift et al | dup of MAM-d20 (→P43) | 0 | medium |
| PER-d16 | stale-workaround | SkriftMobile/testflight.sh; ExportOptions*.plist | script header says its export fails; new automatic-signing plist is referenced by nothing. Needs Tuur to run it once (not queued) | 50 | medium |
| PER-d17 | history-comments | tools/rescue-lost-recordings.py:1-40 | docstring premise ("nothing looks at rec_tmp_* again") is out of date since Q16 (→P50) | 0 | low |
| PER-d18 | duplicate | mockups/Q51.html (494) | byte-identical stray copy of Skrift_Native/SkriftDesktop/mocks/Q51-apple-notes-import.html; RUN.md:73 calls it a stray copy (→P50) | 494 | low |
| PER-d19 | other | SkriftDesktop/project.yml:187-191 | dup of DPE-d20 | 0 | low |
| PER-d21 | unused-harness | DemoSeed.swift | dup of DSH-d05 | 0 | low |
| PER-d-m1 | other (**missed**) | LANES-2026-07-21, -21B, -21C, -22-ipad, -22D, -28 at repo root (40 files, about 3,460 lines) | finished lane briefs contradict CLAUDE.md's "root holds only the live set"; other docs may cite them (→P50, tuur) | 0 | low |
| PER-d-m2 | other (**missed**) | SkriftMobile/mockups/*.html (975 lines) | unreferenced, but Theme.swift:5 cites them as the signed source of the tokens; keep | 0 | low |

## 4. Complexity, per slice

Only complexity findings that are not already a dead-code row above. A complexity finding that repeats a section 3 row is folded into it and named in the "Folded" line. "Not queued" rows are real but are taste, collide with an open Q item, or need Tuur; section 6 says which.

### MAS m-audiobook-svc (base `SkriftMobile/Services/Audiobooks/`)
Folded: c01 = d12, c04 = d01+d02, c08 = d10, c13 = d04, c15 = d08, c16 = d14, c19 and c20 = d13, c22 = d11, c23 = d05, c28 = d07.

| id | kind | where | what | simpler shape | lines | risk |
|---|---|---|---|---|---|---|
| MAS-c02 | two-sources | Audiobook.swift:49-84; BookAlignment.swift:510,714,994,902; AudiobookCloudSync.swift:595; BookBundleManifest.swift:148 | `epubFilename` and `epubFilenames` hand-written as a pair at 5 sites | `mutating func setAttachedTexts(_:)`; both fields stay in Codable (→P3) | 8 | low |
| MAS-c03 | copy-paste | BookAlignment.swift; BookTranscriptionJob.swift:284; AudiobookCloudSync.swift:594,723 | fetch book, mutate, update, refresh session at 7 sites; `modifiedAt` bump differs on purpose (sync LWW) | `store.mutate(id, bumpModified:)` (not queued, medium) | 15 | medium |
| MAS-c05 | copy-paste | QuoteCaptureProcessor.swift:107-139,148-176 | `buildOutput` and `buildOutputFromSidecar` repeat bounds, slice, temp url, export, rebase | one private helper (→P1) | 15 | low |
| MAS-c06 | long-function | BookAlignment.swift:771-847 | `mergeSentences` carries a mixed-text second structure no caller uses | assert one `textFile` per batch, drop `appended*` and `inKeep` (→P5) | 20 | low |
| MAS-c07 | stringly-typed | BookAlignment.swift verdict fields; Shared/Pipeline/AlignmentCore.swift | `FileAlignment.verdict` is a String compared via `rawValue`; ~56 test literals | typed `AlignmentCore.Verdict` (not queued) | 8 | medium |
| MAS-c09 | copy-paste | BookAlignment.swift:416-437,463-473,485-622 | per-file align loop and signature loop in both `attach` and `alignIfNeeded` | one align-one-text helper with a progress closure; derive `AttachOutcome` counts from `perFile` (→P5) | 25 | medium |
| MAS-c10 | other | BookAlignment.swift:1355-1363 | `transcriptIndexRange` scans the whole transcript per sentence | binary search if word ends are monotone (perf, not queued) | 3 | medium |
| MAS-c17 | copy-paste | BookAlignment.swift:254-260; BookTranscriptStore.swift:34-39 | `sidecarSignature` copy of `signature(forFileAt:)` | one shared file-signature function (→P3) | 6 | low |
| MAS-c18 | magic-numbers | AudiobookSession.swift:331,413; BookAlignment.swift:666,1410; BookTranscriptionJob.swift:185,304,407 | guarded `indices.contains(i) ? a[i] : 0` at 8 sites | `Audiobook.fileStart(_:)`, `fileDuration(_:)` (→P3) | 6 | low |
| MAS-c24 | copy-paste | AudiobookCloudSync.swift:364,540; CloudKitAudiobookTransport.swift:198; BookBundle.swift:245; AudiobookImporter.swift:319 | `attributesOfItem` size read x5 | one size helper (→P3) | 6 | low |
| MAS-c25 | reinvented | Audiobook.swift:475-484; Shared/Recording/RecordingCore.swift:47-54 | `AudiobookTime.clock` vs `elapsedLabel` (rounding differs) | already Q121 DurationFormat | 0 | low |
| MAS-c26 | copy-paste | CloudKitAudiobookTransport.swift:145-185 | tolerant continuation wrapper written twice (download, delete) | one async helper; upload stays strict (→P4) | 8 | low |
| MAS-c27 | copy-paste | AudiobookCloudSync.swift:98-162,210,252; AudiobookSession.swift:157; NotesRepository.swift:28-32 | `removedDownloads` read-modify-write x3, `JSONDecoder().decode(Audiobook.self` x5, container id literal pair | `setDownloadRemoved`, `AudiobookSyncRecord.book`, one container constant (→P4) | 8 | low |
| MAS-c29 | history-comments | BookTranscriptionJob.swift:336-343 vs 66 | lead-in comment says "~2 s", `chunkLead = 3.0` (→P2) | fix the comment | 0 | low |

### MAU m-audiobook-ui (base `SkriftMobile/Features/Audiobooks/`)
Folded: c01 = d02, c02 = Q173, c03 = d06, c08 = d07, c09 = Q173, c10 = d14, c13 = d17, c15 = d10, c20 = d13, c24 = d15, c25 = d09, c26 = d16, c27 = Q147, c28 = d14.

| id | kind | where | what | simpler shape | lines | risk |
|---|---|---|---|---|---|---|
| MAU-c04 | two-sources | AudiobookLibraryView.swift:42-44,137,469-548; BookShelfTile.swift:13,69-76; SyncedAudiobooksView.swift:11-70 | two tick counters fake invalidation; per-row fetch per render; `BookSyncState` nested in the library view but used by the tile | top-level `BookSyncState` with `glyph`; Q148 edits the tile (not queued) | 12 | medium |
| MAU-c05 | long-function | AudiobookLibraryView.swift:338-381,499-611 | `row()` 112 lines, status line and empty message duplicated | status-line view; Q148 edits the tile (not queued) | 15 | low |
| MAU-c07 | copy-paste | AudiobookLibraryView.swift:147-168; BookTextSheet.swift:146; BookTextFlow.swift:112-143 + ~7 other files | `Binding(get: { x != nil }, set: ...)` hand-written ~14 times repo-wide | one `Binding<Value?>.isPresent` in Shared/UI (→P51) | 18 | low |
| MAU-c11 | copy-paste | BookImportSheet.swift:9-145; BookShareSheet.swift:9-161 | same sheet scaffold twice | shared `BookTransferSheet` (→P8) | 40 | low |
| MAU-c12 | flags-not-enum | BookShareSheet.swift:13-136; BookImportSheet.swift:105-137 | `.done`/`.landed` render like the phase before them; `totalBytes` re-stats files per callback | compute once, drop dead phases (→P8) | 14 | low |
| MAU-c14 | copy-paste | BookTextSheet.swift:172-174,339-349; BookTextPromptSheet.swift:20-22,102-108; BookTranscriptionJob.swift:113 | `activeBookID == book.id && isRunningOrPaused` at 4 sites | `BookTranscriptionJob.isWorking(on:)` (→P6) | 10 | low |
| MAU-c16 | needless-abstraction | BookTextSheet.swift:389-396,696-740 | `barSegments` emits uncovered gaps the only consumer skips; test-pinned | not queued (contract tested) | 10 | medium |
| MAU-c18 | flags-not-enum | MergedCaptureView.swift:71,90,95,425,435-486 | `touched` dead, `handedOff` equals `createdMemoID != nil`, failure toast twice | three small fixes (→P6) | 10 | low |
| MAU-c19 | stringly-typed | MergedCaptureView.swift:72-73,424-431; Models/TextCaptureSelection.swift:15-23 | toast colour derived by `hasPrefix("added")` | return a tone from `tap` (not queued) | 3 | low |
| MAU-c21 | magic-numbers | AudiobookPlayerView.swift:543-547; MergedCaptureView.swift:93-94 | 90 s capture look-back computed twice | one `captureWindow` helper (→P6) | 3 | low |
| MAU-c23 | reinvented | AudiobookPlayerView.swift:60-69,485-491 | **bug**: `Player.showToast` clears after 1.6 s without checking the text, so a second toast clears early | add the same text guard as `showSplitToast` (→P6) | 8 | low |
| MAU-c29 | other | ContinueListeningCard.swift:27-33,70-73,116-122 | `today()` builds a `DateFormatter` per render | `static let` (→P6) | 6 | low |

### MMD m-memodetail (base `SkriftMobile/Features/MemoDetail/`)
Folded: c04 = d03, c11 = d08, c12 = d15, c18 = d06, c19 = d07, c28 = d14.

| id | kind | where | what | simpler shape | lines | risk |
|---|---|---|---|---|---|---|
| MMD-c01 | stale-workaround | MemoDetailView.swift:532-592,646-659; MemoPageView.swift:13-15,467,640-702; NoteBodyView.swift:58-61,1415-1424 | pager has one live page since swipe was disabled 2026-07-16 (3521151f kept it on purpose for memo-link hops); neighbour-page plumbing remains | product call: render one page keyed by selection. Needs Tuur | 45 | medium |
| MMD-c02 | copy-paste | MemoDetailView.swift:88-133 vs 424-468 | iPad menu and compact dialog list the same verbs | one verb list over `NoteMenuItem`; Q180 owns Redo | 20 | low |
| MMD-c03 | async-tangle | MemoDetailView.swift:646-659,810-841; MemoPageView.swift:617-1161; SignificanceCircles.swift:36 | seven show/sleep/clear toast timers | `.autoDismiss` modifier (not queued) | 25 | low |
| MMD-c06 | reinvented | MemoDetailView.swift:679; MemoDetailSupportTypes.swift:212; CaptureVoiceAnnotate.swift:190; MemoDisplay.swift:45 | m:ss typed 10 times | already Q121 `DurationFormat`; add `CaptureVoiceAnnotate.clock`, `Memo.durationLabel` to that item | 10 | low |
| MMD-c07 | reinvented | NoteBodyView.swift:444-460; SpeakerTurnsView.swift:190-211; CaptureQuoteViews.swift:140 | played/current/upcoming paint rule written 5 times though Shared `KaraokeRole` exists | Q183 touches the active-word code; not queued | 12 | low |
| MMD-c08 | reinvented | SpeakerTurnsView.swift:141-169 | `segmentItems` compiles an `NSRegularExpression` per turn per render | use the static `BodyV2Marker.regex` (→P9) | 2 | low |
| MMD-c13 | copy-paste | MemoPageView.swift:1340-1468 | file and URL capture cards share tile, stack, pill, chrome | `CaptureSourceCard`; hot file, wait for Q119/Q120 (not queued) | 40 | low |
| MMD-c20 | stringly-typed | NoteBodyView.swift:84; MemoPageView.swift:45; SettingsView.swift:13 | `karaokeTapToSeek` declared 3x with default repeated | one key constant (→P51) | 3 | low |
| MMD-c26 | needless-abstraction | MemoDetailSupportTypes.swift:47-72 | `ConversationTurnsSection` per-tick isolation; keep, Q183 edits the same code | no change | 0 | medium |

### SPL shared-pipeline (base `Shared/Pipeline/`)
Folded: c04 = d07, c06 = d14, c08 = d17, c09 = d04, c16 = d11.

| id | kind | where | what | simpler shape | lines | risk |
|---|---|---|---|---|---|---|
| SPL-c01 | copy-paste | AlignmentCore.swift:286-340; SkriftMobile/Services/Audiobooks/ChapterDetector.swift:607-668 | EN/NL number-word tables, hundred rule, `dutchGlued` exist twice; AlignmentCore says "consolidate later" | `Shared/Pipeline/NumberWords.swift` (→P13) | 42 | low |
| SPL-c02 | copy-paste | LanguageSyncCore.swift:26-49; DestinationsSyncCore.swift:22-43 | Language and Destinations reconcilers are the same LWW; Language's `distantPast` guard is redundant | delete the guard now (→P11); merging is a sync change, not queued | 18 | medium |
| SPL-c03 | two-sources | MemoLifecycle.swift:34-60 vs MemoSpine.swift:98-138 | `neverFades` re-lists what `holdReason` lists; thresholds in two places | derive from `MemoSpine.station`; per-row hot path, not queued | 10 | medium |
| SPL-c07 | copy-paste | KaraokeTrack.swift:84-110 vs CommitOnceCache.swift:11-38 | single-slot memo twice | use `CommitOnceCache` (→P11) | 9 | low |
| SPL-c10 | copy-paste | SpeakerTranscript.swift:135-196; SpeakerFusion.swift:44 | `**name:** text` rebuilt 5 times | `Turn.markdown`, one `renamed` (→P53) | 14 | low |
| SPL-c11 | copy-paste | SpeakerTranscript.swift:34-97; SpeakerTurnStyle.swift:85-100 | header regex compiled twice, label cleanup twice | share the regex, `parsedLabel` (→P53) | 8 | low |
| SPL-c12 | copy-paste | SpeakerTurnStyle.swift:26-120; SpeakerNaming.swift:22-35 | slot assignment twice, redundant `ambiguous` | `SlotAssigner`, drop `ambiguous` (→P53) | 8 | low |
| SPL-c14 | deep-nesting | ImageMarkerReinsert.swift:49-94 | before/after anchor search duplicated | `locate(words:takeSuffix:...)`; pinned by reinsert tests (not queued) | 7 | low |
| SPL-c15 | stringly-typed | ImageMarkers.swift:52; ImageMarkerReinsert.swift:12,115; MixedBundle.swift:98; BodyV2Legacy.swift:90; NoteBodyView.swift:1236; BodyTextView.swift:1170; CaptureInboxDrainer.swift:622 | `[[img_%03d]]` hand-formatted at 7 sites though `BodyV2Marker.literal/block` is the one vocabulary; `convertPhotoMarkers` is Q154 | route through `BodyV2Marker` (→P46) | 4 | low |
| SPL-c17 | dead-code | BPEMerge.swift:43-70 | dead trim/empty check when flushing `pending` | flush directly (→P11) | 8 | low |
| SPL-c18 | two-sources | EPubParse.swift:88-207 | `ManifestItem.id` unread, two identical `collectBlocks` branches. Keep `lenientParse` (it repairs unclosed tags) | merge branches, drop `id` (→P11) | 6 | low |
| SPL-c20 | needless-abstraction | AlignmentCore.swift:59-71; MemoSpine.swift:66-80; SpeakerTranscript.swift:20-23 | three explicit inits duplicate the memberwise ones | delete, inline defaults on `Input` (→P11 for Config and Turn, P12 for Input) | 32 | low |
| SPL-c22 | reinvented | PolishPrompts.swift:82-115 | hand-rolled sentence splitter in `ensureParagraphs` | behaviour changes on closers and single newlines; not queued | 15 | medium |
| SPL-c24 | stringly-typed | PlaceCluster.swift:58-85 | merged cluster count and name recovered by splitting ids on `+`; a place called "C+ Cafe" breaks it | `memberIDs`, `mergedCount` (→P30) | 0 | low |
| SPL-c25 | stringly-typed | SourceTaxonomy.swift:54-73; Memo.swift:386; EditConflict.swift:352 | typed-note marker as raw JSON under `mediaSource`, `MemoMetadata.sourceType` is a second key | see P54 | 8 | medium |
| SPL-c30 | copy-paste | WayOut.swift:43-49; VocabularyTermParsing.swift:57-63; TagMatcher.swift:24 | trivial redundancies | (→P12 for WayOut, rest skip) | 4 | low |

### DRV d-review (base `SkriftDesktop/Features/Review/`)
Folded: c10 = d11, c11 = d04, c15 = d09, c25 = d06, c28 = Q147.

| id | kind | where | what | simpler shape | lines | risk |
|---|---|---|---|---|---|---|
| DRV-c01 | other | NoteDisplayView.swift:299-311; NoteBody.swift:20-131; BodyTextView.swift:49-1108 | five naming closures gated one by one | `NamingActions` struct; overlaps Q116 (not queued) | 6 | low |
| DRV-c04 | two-sources | BodyTextView.swift:604-609,984-996,1169-1179 | attachment to model-literal mapping in three switches; image marker hard-coded 10/11 | `ModelLiteralAttachment` protocol (not queued, medium) | 15 | medium |
| DRV-c08 | reinvented | BodyTextView.swift:569-585; Shared/Pipeline/KaraokeMap.swift:17-45 | Mac `wordRanges` copies the shared `KaraokeMap.wordRanges` and differs on surrogates | add a flag to the shared one, delete the copy, add an emoji test (→P17) | 14 | medium |
| DRV-c16 | stringly-typed | NoteProperties.swift:138-141; PipelineFile.swift:296-310 | day-period chip filtered by 4 literal SF Symbol names | `includeDayPeriod:` param (→P15) | 3 | low |
| DRV-c17 | two-sources | ReviewHelpers.swift:10; SplitSpeakers.swift:9-11; SidebarView.swift:1295; ConnectionsPanel.swift:123,134 | `sanitised ?? copyedit ?? transcript` re-typed; `bestBodyText` sits in the Features layer | move to `Models/PipelineFile.swift` (→P20) | 5 | low |
| DRV-c18 | copy-paste | CaptureViews.swift:12,69,115; NoteProperties.swift:271 | `SharedContent.decode` x4 | `PipelineFile.sharedContent` (→P15) | 4 | low |
| DRV-c19 | copy-paste | SplitSpeakersRow.swift:172; UnratedNotePane.swift:86; + 5 more | memo-by-id predicate fetch x7 | `MemoCloudStore.memo(id:context:)` (→P15) | 8 | low |
| DRV-c20 | copy-paste | ConnectionsPanel.swift:497-631 | five state views are one icon/title/bar/subtitle stack | `stateCard`; Q181 nearby, pixel decisions (not queued) | 25 | medium |
| DRV-c21 | other | ConnectionsPanel.swift:272-309 | "this note" entry has `id: UUID()` computed per render | stable id (→P15) | 0 | low |
| DRV-c23 | async-tangle | NoteDisplayView.swift:260-268 | connections refresh ignores `connectionsVisible` | one `.task(id:)`; not queued | 5 | medium |
| DRV-c27 | reinvented | UnratedNotePane.swift:55; UnpipelinedMemoSheet.swift:72 | `value > 0` instead of `NoteConsent.isRated` | use it (→P15) | 0 | low |

### DSH d-shell (base `SkriftDesktop/`)
Folded: c01 = d12, c03 = d11, c07 = d15, c11 = d10, c18 = d16.

| id | kind | where | what | simpler shape | lines | risk |
|---|---|---|---|---|---|---|
| DSH-c02 | async-tangle | Features/Shell/ProcessingCoordinator.swift:22,98-130,625-633 | `isRunning` and `runState` always set together; redo outside the queue strands waiting jobs | computed `isRunning`; drain after redo (→P21) | 8 | medium |
| DSH-c05 | copy-paste | Features/Shell/LiveRecordingSession.swift:123-201 | `stop()` builds the same `ArrivalPath.run` call in both branches | compute `(hooks, onCreated)` per branch (not queued, recording path) | 10 | low |
| DSH-c08 | copy-paste | Features/Shell/RootView.swift:9,35-50,105,133-137,224-230 | default plus init builds two coordinators, `activeID = id; selection = [id]` open-coded 3x (`AppModel.select` also sets the anchor), `onRated` default repeated, frame x4 | (→P18) | 10 | low |
| DSH-c09 | long-function | RootView.swift:160-214; SkriftDesktopApp.swift:14; MemoCloudContainer.swift:55 | `-isolatedRun` literal in 3 places | one constant (→P22) | 3 | low |
| DSH-c10 | copy-paste | Features/Shell/RunFile.swift (17 entry points) | each harness re-implements arg parse, log, exit; **bug**: `-ratetorow` uses `try` inside a non-catching `Task`, so a thrown error is swallowed and the process continues as a GUI | small `Harness` helper; fix the throw (→P22) | 80 | low |
| DSH-c12 | copy-paste | Features/Shell/Snapshot.swift:198-1066 | ten in-memory containers, eight seed `DemoSeed.snapshotFiles()` | `fixtureStore(full:)` (→P22) | 25 | low |
| DSH-c13 | copy-paste | Snapshot.swift:25-110 | 85-line flag chain | table; flag names are used by RUN.md (not queued) | 18 | low |
| DSH-c14 | needless-abstraction | Snapshot.swift:1013-1252; NoteDisplayView.swift; SidebarView.swift:700-714 | `scrollable` flag exists so three snapshots avoid ScrollView | move to hosted render, delete the flag (→P16, tuur) | 30 | medium |
| DSH-c15 | copy-paste | SidebarView.swift:271; SetupWizardView.swift:21; Theme.swift:61 | 'S' badge built twice | `SkriftBadge` (not queued) | 10 | low |
| DSH-c17 | copy-paste | ProcessingCoordinator.swift:460-516,560-565 | `setSplitNotice` clears by text compare, `flash` by token | token (→P21) | 3 | low |

### DPE d-pipeline-engines (base `SkriftDesktop/`)
Folded: c02 = DSH-d11, c04 = d13, c06 = d14, c09 = d16, c14 = d15, c17 = d03, c19 = d01, c20 = d05, c23 = DRV-c17.

| id | kind | where | what | simpler shape | lines | risk |
|---|---|---|---|---|---|---|
| DPE-c01 | long-function | Pipeline/BatchManager/BatchRunner.swift:56-288 | 232-line six-phase function; finder's "same condition twice" claim was wrong | phase helpers (not queued, medium, saves ~15) | 15 | medium |
| DPE-c03 | copy-paste | BatchRunner.swift:122-176; SplitSpeakers.swift:56-68; MemoCloudIngest.swift:224 | sidecar guard repeated 4x | folds into P26 | 15 | low |
| DPE-c07 | copy-paste | IngestService.swift:189-554; UploadService.swift:331; MemoPhotoMaterializer.swift:49-68 | `image_manifest.json` has four writers, two encoders | `ImageManifest.read/write` in Shared; check Q135 first (not queued) | 20 | low |
| DPE-c10 | copy-paste | IngestService.swift:557-575; AudioMetadata.swift:9-23; PipelineFile+BodyNormalise.swift:136 | four ISO parsers; two "read creation date" copies | `ISO8601.lenientDate`, move async `recordingDate` into Pipeline (→P25) | 25 | low |
| DPE-c11 | long-function | MemoCloudReconciler.swift:48-191; MemoCloudIngest.swift:34-120 | `alreadyIngested` re-decides what the sweep decided; direct test callers rely on it | only `existingFile` is certain (→P24) | 30 | medium |
| DPE-c12 | long-function | MemoCloudUpdate.swift:29-145 | `isFreshRow` doc between attribute and func (→P28) | move comment | 6 | low |
| DPE-c15 | two-sources | Pipeline/Ingest/EditConflictHold.swift:12-32; Shared/Model/EditConflict.swift:408 | two stores for the two-version set; Hold lock is a real threading need | not queued | 10 | medium |
| DPE-c21 | copy-paste | MirroredNoteFields.swift:55-119; MemoNoteProjection.swift | three plain fields mirrored by hand; file header says deliberate | not queued | 20 | low |
| DPE-c22 | reinvented | CompilerBridge.swift:16-70 | `PhoneMetadata` mirrors Shared `CompilerMetadata` | not queued (Q155 nearby) | 25 | medium |
| DPE-c24 | reinvented | UploadService, BatchRunner, PipelineFile (about 14 sites) | trim-to-nil open-coded | not queued | 15 | low |
| DPE-c25/26/27 | long-function | Engines/MacRecorder.swift:163-517 | `start()` 125 lines with 8 failure exits, duplicated abandon-take blocks, UID round trip through two DiscoverySessions. Hardware-flavoured, rebuilt after a 3-diagnosis saga | not queued (needs a Mac recording test) | 49 | medium |
| DPE-c28 | long-function | VaultExporter.swift:76-319 | `let vault = picked` alias, one-line `noteStem` wrapper | drop both (→P25) | 15 | low |
| DPE-c30 | other | SplitSpeakers.swift:31-43 | `settle` repeats `withdraw` in every non-split path | compute outcome once (→P25) | 6 | low |

### DAU d-app-ui (base `SkriftDesktop/`)
Folded: c01 = d01, c02 = d02..d06, c03 = d08..d10, c10 = d14, c11 = d11.

| id | kind | where | what | simpler shape | lines | risk |
|---|---|---|---|---|---|---|
| DAU-c04 | flags-not-enum | Features/Journal/JournalView.swift:42,149-308; AppModel.swift:44-45 | `mapMode` and `reviewShelf` are two variables for one shown column | `enum JournalColumn { lookback, map, wayOut }` in JournalView (→P18) | 12 | low |
| DAU-c05 | two-sources | SidebarView.swift:855-880; JournalView.swift:78; UnpipelinedMemoSheet.swift:225 | Sidebar says `mainContext` is stale after a CloudKit import, Journal and the peek sheet use it; toggleLock saves a different context from the one the memo came from | possible stale read or lost write, unverified (→P54) | 8 | medium |
| DAU-c06 | copy-paste | App/MacCloudDeleteSync.swift; MacCloudMetaSync.swift; MacCloudEditSync.swift; VocabularyCloudSync.swift; PolishPromptsCloudSync.swift; NamesCloudSync.swift; MemoCloudReconciler+Wiring.swift | `cloudKitMacSyncEnabled && container` guard at 8 App sites + 5 outside; `Logger(subsystem:category: "cloudkit")` inline 16 times | `MemoCloudStore.syncContainer`, `AppLog.cloudkit` (→P55) | 20 | low |
| DAU-c07 | copy-paste | MacCloudDeleteSync.swift:23-44; MacCloudMetaSync.swift:40-55 | batch `mirror` repeats what `write` already consolidated | batch variant of `write` (→P55) | 18 | low |
| DAU-c08 | long-function | VocabularyCloudSync.swift:14-94 | four `save` calls, prewarm twice | one dirty flag, keep ordering (→P55) | 6 | medium |
| DAU-c12 | copy-paste | SettingsView.swift; PersonEditor.swift; SetupWizardView.swift | boxed-field chrome x6, folder picker x2 | `MacFormField` (not queued) | 35 | low |
| DAU-c13 | copy-paste | SettingsView.swift:120-136,210-225,267-287 | destinations row hand-copies `toggleRow` | base `toggleRow(isOn:)` (not queued) | 12 | low |
| DAU-c14 | two-sources | SettingsView.swift:16-18,125-170; NoteDestination.swift:86-108 | `destinationsOn` mirrors a defaults flag by observer; `@AppStorage` would drop the `forcedOn` snapshot rig | not queued | 7 | medium |
| DAU-c15 | two-sources | SettingsView.swift:15,40,494-504 | open Settings holds a stale copy of settings.json while the CloudKit runners write vocab and prompts | risk, unverified; listed under Needs Tuur | 3 | medium |
| DAU-c16 | magic-numbers | Sidebar, Journal, Settings | 13 `Theme.hairline.opacity` literals; pixel changes need Tuur's eyes | not queued | 8 | medium |
| DAU-c18 | copy-paste | SidebarView.swift:616-733,1377-1399 | entry row switch typed twice | `entryRow`, `selectionID` (not queued) | 10 | low |
| DAU-c20 | stringly-typed | JournalView.swift:441,469; RailMiniMap.swift:95; Shared/Pipeline/PlaceCluster.swift:73; phone JournalMapView.swift:102,113 | split of `+` ids at 6 sites | `memberIDs` (→P30) | 5 | low |
| DAU-c21 | stringly-typed | SkriftDesktopApp.swift; RunFile.swift (19 `firstIndex(of:` parses) | `XCTestConfigurationFilePath` x4, `-isolatedRun` x3, flag parse x19 | `LaunchArgs.value(after:)` (→P22) | 20 | low |
| DAU-c22 | async-tangle | ConnectionsIndexService.swift:60-89 | redundant `MainActor.run` hops | skip, compile behaviour unverified | 6 | low |
| DAU-c23 | async-tangle | JournalView.swift:71,78-136 | `deriveThenVsNow` task never cancelled | keep a handle (not queued) | 0 | low |
| DAU-c26 | other | SidebarView.swift:413-453; RootView.swift:90; LiveRecordingSession.swift:37 | Phase predicates written in SidebarView and RootView | not queued | 8 | low |
| DAU-c27 | reinvented | JournalView.swift:584-587 | **bug**: `Duration.formatted(.time(pattern: .minuteSecond))` prints `125:00` for a 2h05 note; phone WayOutView.swift:384 same | `SkriftFormat.duration(seconds:)` on the Mac, matching helper on the phone (→P30) | 1 | low |

### MRC m-recording-capture-ui (base `SkriftMobile/`)
Folded: c15 = d04, c16 = d02, c17 = d14, c19 = d19.

| id | kind | where | what | simpler shape | lines | risk |
|---|---|---|---|---|---|---|
| MRC-c01 | reinvented | Features/Recording/MemoSaver.swift:652-694 | `appendAudio` still stitches with AVMutableComposition + export, the path `AudioClipMerge` replaced after a phantom silent tail | open base with `AVAudioFile` first and let it throw (else `AudioClipMerge` silently drops a bad base), then merge (→P33, tuur) | 28 | medium |
| MRC-c02 | copy-paste | MemoSaver.swift; RecordingRecovery.swift:147; LiveRecordingService.swift:571,688 + outside | `Double(f.length)/sampleRate` x7 here | `AVAudioFile.seconds` (→P32); MacMemoAuthor.audioDuration is a different helper, leave it | 10 | low |
| MRC-c03 | copy-paste | MemoSaver.swift:73-271 | three import entry points repeat the placeholder insert | `insertPlaceholder` (not queued; Q134 reshapes dates) | 14 | low |
| MRC-c04 | copy-paste | MemoSaver.swift:577-585; Services/Capture/CaptureDictation.swift:65-73 | retry-transcribe loop copied | `Transcribing.transcribeRetrying` (→P32) | 8 | low |
| MRC-c06 | unreachable | LiveRecordingService.swift:712-1243 | nine `!mock` guard terms dead; a mock service factory would not pay | not queued | 2 | low |
| MRC-c07/c08/c09 | copy-paste | LiveRecordingService.swift (teardown, captions, recovery observers) | repeated halt/teardown, caption begin/end, five named observers | hardware class: orchestrator only, device trace first. Not queued | 44 | medium |
| MRC-c11 | two-sources | LiveRecordingService.swift:266,848,1246 | `setCategory` x3, the third bypasses the HFP policy | `configureSession` (→P34, tuur) | 3 | medium |
| MRC-c18 | needless-abstraction | LiveRecordingService.swift:733-762; RecoverySweepTests:207 | `MemoryWarningStep` enum plus tautological test; D131 pin | straight-line + a handler-driving test; not queued | 8 | low |
| MRC-c20 | reinvented | LiveRecordingService.swift:1491-1504 | `name(_ reason:)` maps each case to its own name | `String(describing:)`, output unverified (→P31) | 11 | low |
| MRC-c21 | stringly-typed | RecordView.swift; LiveRecordingService.swift; SettingsView.swift | `liveTranscription` x4, auto-off key x2 | key constants (→P51) | 2 | low |
| MRC-c28 | other | Features/Recording/CameraSheet.swift:91-98,144-150 | **bug**: `setZoom` writes `zoomBase = zoom` on every callback while the pinch passes a cumulative scale, so zoom compounds | write `zoomBase` in `.onEnded` only (→P34, tuur, camera is hardware) | 0 | low |
| MRC-c29 | copy-paste | Services/Recording/PhotoCaptureService.swift | `videoDevice` equals `videoInput?.device`; zoom clamp x2 | not queued | 8 | low |
| MRC-c30 | copy-paste | MemoSaver.swift:850-940 | file-exists path expression x2 | not queued | 6 | low |

### MLJ m-list-journal-settings (base `SkriftMobile/`)
Folded: c03 = d17, c04 = d08/d03, c11 = d03, c13 = d11, c18 = d02, c19 = d11, c21 = Q160, c23 = d06.

| id | kind | where | what | simpler shape | lines | risk |
|---|---|---|---|---|---|---|
| MLJ-c01 | two-sources | Features/Settings/SettingsView.swift:19,87-99 | **bug**: picker writes the Bool through `@AppStorage` then `.onChange` re-stamps via `ASRLanguageStore.save`, so a sync-adopted value gets re-stamped as now | `Binding` whose setter saves, delete the `.onChange` (→P37) | 5 | low |
| MLJ-c05 | flags-not-enum | Features/Root/AppTabView.swift:41-124 | three seeded-sheet bools | not queued (rig kept) | 10 | low |
| MLJ-c06 | copy-paste | Features/Journal/JournalHomeView.swift:59-146 | river block in compact and regular | `riverCards` (not queued) | 10 | low |
| MLJ-c07 | copy-paste | JournalSidePane.swift:22-102; JournalCalendarView.swift:8-66 | month and selected-day state twice | `MonthSelection` (not queued; Q182 near) | 12 | low |
| MLJ-c09 | two-sources | Features/Journal/WallPrinter.swift:30-120 | **bug**: `tryDrain` snapshots the queue, awaits printing, then overwrites the key, dropping any card enqueued during the drain; queue/ledger re-read from defaults 5 times | stored properties with `didSet` persistence (→P37) | 15 | low |
| MLJ-c14 | needless-abstraction | MemosListView+Row.swift:10-45,70,90 | `MemoRow` forwards 6 properties to `MemoCard` twice | build once (→P35) | 12 | low |
| MLJ-c15 | other | MemosListView+Header.swift:151-289 | `processRow` reads `processPile` 5x per body | `let pile` (→P35) | 0 | low |
| MLJ-c16 | copy-paste | WayOutView.swift:222,336; MemosListView+Row.swift:107; MemoPageView.swift:265; NoteCardView.swift:185 | locked-note title fallback x5 | one helper (not queued) | 6 | low |
| MLJ-c17 | copy-paste | WayOutView.swift:452-483; Desktop UnpipelinedMemoSheet.swift:242-285 | phone and Mac `bodyRuns` are the same algorithm | shared `BodyRuns.split` (not queued) | 15 | low |
| MLJ-c20 | needless-abstraction | Features/Names/NamesListView.swift:159-163 | `NamesDisplay` is two forwarders | call `displayName` and `PersonEditCore.isEnrolled` (→P35) | 5 | low |
| MLJ-c23/c24 | unreferenced | Features/Feedback/* | store, composer, ISO strategies (see d05/d06); `sendNow` re-saves a draft folder on a second tap; no-mail alert says "Feedback list", which does not exist | (→P36) | 15 | low |
| MLJ-c25 | copy-paste | ObsidianSettingsSection.swift:46-168 | Folder and Portfolio rows and importers | not queued | 12 | low |
| MLJ-c26 | copy-paste | Features/Onboarding/OnboardingView.swift:13-51,130-134; ModelsView.swift:80-96; PolishSettingsView.swift:120 | **bug**: `modelRequested` is never reset after a failed download, so the spinner never clears (`try?` swallows the error); `ModelsView` resets its flag | reset after `ensureLoaded`; shared mini bar optional (→P37; Q173 also edits this view) | 8 | low |
| MLJ-c27 | stringly-typed | Services/Polish/PolishPromptsStore.swift; PolishSettingsView.swift:191-205 | three parallel switches over `PolishPromptKind` | one descriptor (→P56) | 14 | low |
| MLJ-c28 | copy-paste | four tabs | screen title row x4 | not queued | 8 | low |

### MSV m-services (base `SkriftMobile/Services/`)
Folded: c05 = d08, c06 = d03, c07 = d02, c11 = Q154, c13 = d10..d15, c18 = d04/d05, c20 = d06, c27 = Q182, c30 = d14.

| id | kind | where | what | simpler shape | lines | risk |
|---|---|---|---|---|---|---|
| MSV-c01 | long-function | Capture/CaptureInboxDrainer.swift:201-655 | `process` is 455 lines; the finder's "same delete ordering" claim is wrong (video/audio delete before import, capture after) | splitting saves little and collides with Q134, Q145 (not queued) | 30 | medium |
| MSV-c04 | two-sources | Capture/CaptureInbox.swift:52-85; CaptureInboxDrainer.swift:41-282 | 8 parallel optional arrays on `CaptureInboxEntry` | array of structs with a compat decoder; high risk, Q134 area (not queued) | 30 | high |
| MSV-c08 | copy-paste | Export/ObsidianPublisher.swift:6-41; PortfolioVault.swift:16-48 | two security-scoped-bookmark stores, same code | `ScopedFolderBookmark(key:)` (→P57) | 18 | low |
| MSV-c09 | copy-paste | ObsidianPublisher.swift:136-143; PublishCoordinator.swift:129-135 | destination root derivation twice | one helper (→P57) | 8 | low |
| MSV-c10 | long-function | ObsidianPublisher.swift:131-224 | `VaultWriteOutcome` mapped twice | `PublishOutcome.init(_:relativePath:)` (→P57) | 8 | low |
| MSV-c12 | copy-paste | Transcription/TranscriptionService.swift:146-207 | file and buffer `transcribe` repeat the scaffold | private `run` (not queued) | 15 | low |
| MSV-c14 | magic-numbers | Polish/Engine/MLXPolishEngine.swift:129-158 | title/summary turn budgets in two places | `titleTurn(plain:)`, `summaryTurn(plain:)` (→P56) | 4 | low |
| MSV-c15 | two-sources | Polish/PolishCenter.swift:140-377 | `canPolish` has a redundant `busyMemoID` clause | drop it (→P56) | 12 | low |
| MSV-c16 | stringly-typed | Polish/PolishPromptsStore.swift:7-115 | three parallel switches | descriptor (→P56) | 14 | low |
| MSV-c17 | copy-paste | Shared sync cores' `Outcome` enums | not identical shapes | not queued | 12 | medium |
| MSV-c21 | copy-paste | WordTimingsStore.swift; Diarization/DiarizationStore.swift | two per-memo JSON sidecar stores | not queued | 12 | low |
| MSV-c24 | flags-not-enum | Transcription/VocabularyBooster.swift:60-186 | five stored props set together | one `Ready?` (not queued) | 8 | low |
| MSV-c29 | history-comments | Export/MemoExporter.swift:7-9 | says the phone has no author setting; it has one (→P38) | fix | 3 | low |
| MSV-c34 | copy-paste | DocScanner.swift:69-82; CaptureInboxDrainer.swift:630-645 | `Memo.make` passes defaults explicitly | drop them (not queued) | 8 | low |
| MSV-c35 | magic-numbers | NotesRepository.swift:33; JournalIndexService.swift:49; Shared/Model/Memo.swift:283; Desktop x3 | `XCTestConfigurationFilePath` x6 | one constant (→P51) | 2 | low |
| MSV-m1 | other (**missed**) | Export/ObsidianPublisher.swift:35-38 | **bug**: `ObsidianVault.hasPublished` keys the ledger on the picked root while the writer and `PublishCoordinator.hasPublished` key it on the vault home (`<pick>/Skrift`), so the lock-flow notice can say "not in your vault" for an exported note (→P40) | call `PublishCoordinator.hasPublished(memo)` | 5 | low |

### MAM m-app-models-ext (base `SkriftMobile/`)
Folded: c13 = d19, c14..c17 = d01..d14, c19 = d07/d08.

| id | kind | where | what | simpler shape | lines | risk |
|---|---|---|---|---|---|---|
| MAM-c01 | two-sources | App/SkriftApp.swift:108-236; Services/CloudSyncMonitor.swift:143-157; MemosListView.swift:635 | "reconcile the corpus" sweep list kept by hand in four places; `PolishPromptsCloudSync` only runs at launch; **missed**: `runImportSweeps` omits `MemoDeduper` although dupes arrive during imports | one AppLifecycle; LaunchWorkGate split must stay. Not queued, medium. Dedupe gap in P54 | 30 | medium |
| MAM-c02 | copy-paste | SkriftShare/ShareSheetView.swift:216-626 | card chrome typed 6 times | `shareCardChrome(radius:)` (→P58) | 50 | low |
| MAM-c03 | flags-not-enum | ShareSheetView.swift:28-37,186-191,740,760 | audio destination derived twice | two computed values; overlaps Q132/Q150 (not queued) | 10 | low |
| MAM-c04 | long-function | ShareSheetView.swift:716-842 | `saveTapped` 127 lines, force-unwrap after a nil check | split by kind (→P58) | 30 | low |
| MAM-c06 | flags-not-enum | SharePayloadLoader.swift:39-72; ShareViewController.swift:47-87 | `SharePayload` kind as type plus two bools; a redundant viewDidLoad branch | local `Kind` enum; not queued | 20 | medium |
| MAM-c07 | copy-paste | SharePayloadLoader.swift:183-464 | temp-copy x4, duration read x2 | not queued (Q132/Q133/Q150 area) | 40 | medium |
| MAM-c08 | magic-numbers | ShareViewController.swift:29-119; ShareSheetView.swift:50-103; ShareFeedbackView.swift:24-59 | `#0e0f16` x3, sheet surface block x2 | `ShareTheme` (→P58) | 15 | low |
| MAM-c10 | two-sources | widget files; Shared/UI/Palette.swift | widget inlines Palette values | compile Palette into the widget (→P44) | 5 | low |
| MAM-c12 | needless-abstraction | SkriftShared/RecordingActivityAttributes.swift; project.yml:301-333,390,542 | a framework target exists for one 41-line file | multi-target membership like the intents; Live Activity needs a device (→P45, tuur) | 25 | medium |
| MAM-c18 | copy-paste | Models/Memo+Mobile.swift:119-162 | name-resolution mutators repeat guard/decode/encode | helper; wait for Q116 (not queued) | 8 | low |
| MAM-c20 | copy-paste | Models/MemoDisplay.swift:274-322; ShareSheetView.swift:711 | host-minus-www x4 | `SharedContent.domain`; Q179 near (not queued) | 10 | low |
| MAM-c24 | history-comments | ShareViewController.swift:216-219; MemoDisplay.swift:325-347; Components.swift:3-4 | tombstones, orphan docs | (→P43) | 15 | low |
| MAM-c25 | needless-abstraction | Components.swift:109-115 | `symbolEffectPulseFallback()` one-line wrapper | inline (→P43) | 6 | low |
| MAM-c27 | other | CaptureInbox.swift:50-85 | parallel arrays | high risk, Q134 | 10 | high |

### SMU shared-model-ui-body (base `Shared/`)
Folded: c06 = d06 (TagRules), c09 = d09, c10 = d10, c22 = d04, c26 = MSV-c35.

| id | kind | where | what | simpler shape | lines | risk |
|---|---|---|---|---|---|---|
| SMU-c01 | two-sources | BodyV2/BodyV2Legacy.swift:13-232; BodyNormaliseMigration.swift:93-156 | second "move markers to sentence end" implementation; not output-equivalent (git 35f98834 kept it on purpose so unopened notes export as before) | needs Tuur: export output could change; fixture-diff first | 120 | high |
| SMU-c03 | copy-paste | BodyV2.swift:139; BodyV2Text.swift:47-53; Paragrapher.swift:82-86 | closer set defined 3x; `Paragrapher.endsSentence` copies `BodyV2Text.endsSentence` | forward it (→P46) | 10 | low |
| SMU-c04 | stringly-typed | seven `[[img_%03d]]` sites | see SPL-c15 | (→P46) | 4 | low |
| SMU-c06 | reinvented | BodyNormaliseMigration.swift:55-70; Memo+BodyNormalise.swift:28; PipelineFile+BodyNormalise.swift:52 | `isC203Legacy` hand-parses the capture JSON | overload on `SharedContent?` (→P46) | 5 | low |
| SMU-c07 | deep-nesting | BodyV2Text.swift:17-103 | collapse regex computed twice per non-list line; two regexes compiled per call | compute once, hoist (→P46) | 3 | low |
| SMU-c11 | copy-paste | EditConflict.swift:108-129 | SHA256-prefix expression x3 | `digest(_:)` (→P46) | 3 | low |
| SMU-c13 | copy-paste | Memo.swift:385; EditConflict.swift:352 | typed-marker blob built twice | see P54 | 3 | low |
| SMU-c14 | copy-paste | UI/EditConflictViews.swift:62-282 | choice pills in phone and Mac bodies | `choiceButtons` (→P46) | 10 | low |
| SMU-c15 | two-sources | UI/TagRules.swift:47-94; TagEditorRow.swift:319-338 | `fold` and `alreadyOnNote` re-walk the batch | return `alreadyOn` from `fold`; tests are protected (not queued) | 10 | medium |
| SMU-c16..c21 | copy-paste | TagEditorRow, NoteRatingPill, DestinationRowView, DateRangeStrip, EditConflictViews | small view dedupes (toast lifetime 1.6 s in 4 hosts, three-ball readout x2, grid geometry, unset From/To pill) | not queued, each saves 4-8 lines | 30 | low |
| SMU-c23 | two-sources | UI/Palette.swift:16-59; both Theme files | six `DriftedPair` tokens kept apart on purpose until an eyeball round | needs Tuur's pick per token (see section 6, Needs Tuur) | 15 | medium |
| SMU-c24 | copy-paste | Model/MemoDate.swift:8-59 | days-between twice, six formatters | helpers; not queued | 10 | low |

### SRS shared-rest (base `Shared/`)
Folded: c08 = d03, c09 = d19, c13 = d01, c19 = d10.

| id | kind | where | what | simpler shape | lines | risk |
|---|---|---|---|---|---|---|
| SRS-c01 | copy-paste | Export/VaultWrite.swift:330-524 | `ownedName` URL/Data twins; `resolvedName` and `writeAsset` mirror each other. The second resolve inside `writeOwned`/`copyOwned` is the only clobber guard, keep it | one `ownedName`, one place-bytes step (→P59) | 25 | medium |
| SRS-c02 | flag-unread | VaultWrite.swift:225-297; VaultStamp.swift:57-99 | `Assessment.proceed(creates:)` read only by a test; `Standing.absent` unreachable | simplify, two tests (→P47) | 8 | low |
| SRS-c03 | other | VaultLayout.swift:41-84; VaultStamp.swift:124-157 | `if exists(nested) return nested` then `return nested`; two `home(forPicked:)` overloads; 2048-byte head read twice | (→P47) | 12 | low |
| SRS-c04 | long-function | Export/Compiler.swift:13-193 | 180 lines; force-unwrap at 147 | `input.significance.map` only (not queued) | 3 | low |
| SRS-c05 | stringly-typed | Export/CompilerInput.swift:53-84; Compiler.swift:52-257; MemoExporter.swift; CompilerBridge.swift:69 | `CompilerSharedContent` is a string-typed copy of `SharedContent` compiled into the same targets | use `SharedContent` and switch exhaustively (→P60) | 15 | low |
| SRS-c06 | reinvented | Compiler.swift:273-316; ConnectionWhy.swift:40-54 | three wiki-link scanners | `Sanitiser.bodyLinks`; keep `wikiNames` memo/60-char rules (→P60) | 20 | low |
| SRS-c07 | copy-paste | Naming/Sanitiser.swift:150-198; ConversationLinking.swift:118-163; NameLinking.swift:61-92 | alias derivation, earliest-match and demote loops pasted in three functions that must agree | `linkable`, `firstSafeMatch`, `demoteMentions`; pinned by SanitiserTests and corpus goldens (→P48) | 28 | medium |
| SRS-c10 | copy-paste | NamesData.swift; PersonEditCore.swift; NamesStore.swift | `displayName` equals `keyName`, short-name rule twice | not queued | 8 | low |
| SRS-c11 | needless-abstraction | Naming/NamesStore.swift:40-195 | four lock-then-forward wrappers | recursive lock; tombstone voiceprints differ (not queued) | 20 | medium |
| SRS-c14 | copy-paste | Recording/LiveCaptionEngine.swift:126-333 | reset blocks, chunk-commit twice | device-tuned settle rules, not queued | 18 | medium |
| SRS-c15 | async-tangle | RetrievalEngine/GemmaEmbedder.swift:82-127 | a new 605 s sleeping Task per `prepare()`; sweeps leave thousands | one idle task (→P49) | 6 | medium |
| SRS-c16 | reinvented | ModelDownload/ResumableModelDownloader.swift:245-262 | hand-written glob; doc says `*` stays within a segment, code lets it cross `/` | `fnmatch(pattern, name, 0)`; tests need the phone suite (→P49) | 14 | low |
| SRS-c17 | stale-workaround | ResumableModelDownloader.swift:98-239 | hub-cache adoption shim saved an 8.9 GB download once | needs Tuur | 25 | medium |
| SRS-c23 | async-tangle | Metadata/LocationOneShot.swift; Mac MacLocationStamp.swift | a shared instance overwrites its continuation if called twice before a fix returns | new `LocationOneShot()` per call as the phone does (→P49) | 0 | low |
| SRS-m1 | async-tangle (**missed**) | GemmaEmbedder.swift:84-94 | **bug**: two concurrent `prepare()` calls both pass the `loadTask == nil` check before the ANE wait loop, each creates a Task, the second overwrites the first, so the 295 MB model loads twice (the failure the comment at 75-79 describes) | move the wait loop inside the single-flight Task (→P49) | 0 | medium |
| SRS-m2 | other (**missed**) | VaultWrite.swift:384-394 vs 478-484 | `resolvedName` returns `disambiguated(preferred)` without checking that name is free; if it is taken by different bytes the embed points at the wrong file | test first when doing P59 | 0 | low |

### PER periphery (repo-wide)
Folded: most periphery complexity items duplicate section 3 or other slices.

| id | kind | where | what | simpler shape | lines | risk |
|---|---|---|---|---|---|---|
| PER-c02 | reinvented | RunFile.swift (19 sites), Snapshot.swift:26, CorpusSeed.swift:242, ProcessingCoordinator.swift:50, LifecycleSweepScheduler.swift:68; NoteDestination.swift:145; PortfolioVault.swift:54 | the phone has `[String].boolFlag/stringValue`, the Mac and Shared hand-roll `firstIndex(of:)` about 23 times | move the extension into Shared (→P51) | 30 | low |
| PER-c13 | copy-paste | 15 desktop test files; BookAlignmentTests; four `corpusRoot` climbs | `tempDir()` defined 17 times, corpus path climb 4 times | one helper per test bundle; protected tests, hand-merge (→P61) | 85 | low |
| PER-c14 | copy-paste | SkriftMobileUITests (19 snap/launch helpers) | no shared UI-test base | base class; sim lock; not queued | 55 | low |
| PER-c18 | copy-paste | plan/hand-merge.sh vs plan/accept.sh | hand-merge re-implements accept steps 2-5 with drift (always `done`, no worktree cleanup, `reset --hard` without the queue backup) | `accept.sh --approve-protected`, delete hand-merge.sh (→P62, tuur) | 15 | medium |
| PER-c21 | stale-workaround | tools/rescue-lost-recordings.py | docstring premise is out of date; `pull` and `pull_devlog` are the same call | rewrite, keep the tool (→P50) | 20 | low |

## 5. Refuted findings, and verifier "missed" findings

### Refuted (96 itemised here; the harness reports 97)

Why each was refuted, in a clause. None of these is proposed.

| slice | ids | why refuted |
|---|---|---|
| MAS | d17 | `hi = min(words.count, ...)` clamp in BookAlignment 1181-1191 is a live guard |
| MAS | c11, c12, c14, c21, c30 | taste-only latches, setSleep already centralised, multi-instance hazard hypothetical, chapter-number idea speculative, bookmark write is one line |
| MAU | d11, d12 | Aa-sheet theme swatches are a signed mock (SPEC C108); the screenshot launch flags are a kept rig (lane briefs) |
| MAU | c06, c17, c22, c30 | sheet follow-up slots exist for the iOS 26 sheet-swap race; alert enum saves nothing; reloadIfNeeded calls differ; reading themes are signed |
| MMD | d09, d12 | `ConnectionsPanel` person-chip branch becomes live under Q181; selection-handle probes belong to an unresolved device bug |
| MMD | c05, c14 | PlayerBar density is Q121; MemoPageView restructure is taste |
| SPL | d09 | `-aligncheck` is a documented harness (also DSH-d07 for the Mac side) |
| SPL | c13, c19, c21, c27, c28, c29 | SpeakerFusion scans are pinned by a determinism rule; `AlignmentCore.align` is deterministic and pinned; tag/heading rule disagreement needs a decision; PolishPrompts pin comment contains a constraint; small tested loops |
| DRV | d08, d08b, d18 | Q120/Q181 edit exactly those lines; Q172 owns the tag ranking; Q147 owns initials |
| DRV | c02, c03, c07, c12, c13, c24, c29, c30 | order-dependent attribute layering, per-branch capability gates, taste, Q116 rewrites naming overrides, trivial or net-zero, ~14 `fileprivate static` constants block a split |
| DSH | c06 | LiveRecordingSession stream rewrite touches the hardware capture path with no evidence of a defect |
| DPE | c13, c16, c18, c29, c31, c32 | MacCloudWriteBack resolve exists for a 2026-07-28 incident; ArrivalPath split is a deliberate seam; AppSettings optionals are the legacy-decode pattern; reorganisation only; style swap; pure mirror is commented |
| DAU | d20 | harness seams, not dead |
| DAU | c09, c19, c24, c25, c28, c29 | comments explain real device bugs; perf speculation; drag-and-drop crash guard; Q-items name the same ranges; deliberate test seam; no net reduction |
| MRC | d12, d22, d23 | persisted marker JSON (rescue tool reads it); ActivityKit Codable shared contract; inert glyphs are deliberate (mock) |
| MRC | c05, c10, c12, c13, c14, c27, c32 | zero lines saved and hardened by repro; start drivers differ on purpose (b117 trace); timing stamps are the device instrumentation; real-time tap documented; reset/clamp struct costs more; bridges have two different consumers; file split forces visibility changes |
| MLJ | d10 | the `deletedAt == nil` guards are reachable for one render after a trash |
| MLJ | c02, c13, c22, c29, c30 | `DestinationSettings.isEnabled` is `forcedOn || stored`, `@AppStorage` would break a UITest; two consumers of one counter; unverified MainActor claim; DevLog is an autoclosure no-op in Release; helper not usable in plain Strings |
| MSV | c19, c28, c31, c33, c36 | one-line accessors; one production site; taste; shared file would need target membership |
| MAM | d06, d23 | `nameResolutionsData` syncs through CloudKit and Q116 extends it; legacy `AudiobookAsset` registered in the container, keep |
| MAM | c11, c21, c22, c23, c26 | widget phase enum is net negative; Q133 covers the type lists; shared link enum saves 6 lines; bridges differ (cold-launch race fix); AppIntents are on the keep list |
| SMU | d10 | `MemoMetadata` field is persisted and synced |
| SMU | c02, c05, c08, c12, c25 | cohesive and commented; net zero; enum rewrite touches 10+ callers; literal compares; AppPaths claim not shown |
| SRS | c12, c18, c21, c22 | Sanitiser init tables are each a pinned rule; download perf unmeasured, rewrite larger; comment purge would drop rationale; taste |
| PER | d11, d20, d22 | demo/journal rig is "Keep" in BRIEF_JOURNAL; Odyssey diagnostics are listed as shipped tools in roadmap.yaml:1583; plan/sources*.md is a live provenance index |
| PER | c03, c06, c09, c10, c16, c19, c23 | Snapshot flag table would reorder prefix matches; seeds combine, a scenario enum loses combinations; mock rosters differ; seed helper takes 4 params to save 4 lines; the EmbeddingBakeoff spike is cited by 5 live paths; accept/queue regexes differ by design; comment records a decision rule |

### Verifier "missed" findings, folded into the tables above

Marked **missed** in sections 3 and 4. They are: MAS-d-m1..m4 and the stale `CaptureSheetView` comment (folded into P1); MAU-d-m1; DRV-d-m1 (the surrogate-pair word split, a real bug, P17) and DRV-d-m2; DAU-d-m1 and d-m2; MRC-c-missed (the `NotesBottomChrome` header doc, folded into Q173); MAM-d-m1; MSV-m1 (`ObsidianVault.hasPublished`, a likely bug, P40); SRS-m1 (the `GemmaEmbedder` double load, a real bug, P49) and SRS-m2; PER-d-m1 and d-m2. Other "missed" lines in the data repeated a finding already in the tables or an open Q item (Q120, Q121, Q173, Q116) and were not re-listed. Suspected bugs not tied to a slice row are collected in P54.

## 6. Queue items, ready to paste

Format follows QUEUE.md. `P#` are placeholders; renumber when pasting after Q187. Grouped by slice. `gate+: yes` is set only where an item changes Mac behaviour or build output. Every check runs the Mac gate and the Mac full build; phone-side items add `plan/mtest.sh <Class>` for the one class that covers the changed code.

**Before pasting.** Items that delete or edit existing tests touch protected paths (`SkriftMobileTests`, `SkriftDesktopTests`), so `accept.sh` will refuse them and they go through `plan/hand-merge.sh` like Q89 (D158) and Q80 (D154), after Tuur says yes in one line. Those are: P1, P2, P3, P9, P10, P11, P12, P14, P18, P23, P24, P25, P26, P27, P31, P38, P39, P41, P42, P43, P46, P47, P52, P61. New tests are additions and do not need that route. Items with no test change run through `accept.sh`.
Order constraints: P10 before P46 (same test fixtures); P41 before P42; P12 before P9 (P12 owns `displayRange` in `NoteBodyView.swift`); P38 deletes `finishStream`/`finish`, P47 then deletes `caption()` once P24 and P38 removed both forwarders; P20 before P27 (shared relink helper); P17 after P16 if both land. Items that overlap an open Q item say so in `needs:`.

### Audiobook services (MAS)

### P1 [auto] (todo) delete the dead audio-trim machinery in quote capture
spec: C240
needs: -
gate+: no
do: `applyTrim`, `TrimResult` and `isUnchangedTrim` in `SkriftMobile/Services/Audiobooks/QuoteCaptureProcessor.swift` (the "Apply trim" block, lines 208-296) have no production caller; Q89 removed `process()` and left these. Delete them, then the fields only they read: `QuoteCaptureOutput.bufferSentences`, `bufferOffset`, `spanEnd` (both initialisers) and `BufferSentence.isInInitialSpan`; drop the `snappedStart`/`snappedEnd` parameters (every production caller passes 0, 0) from `buildSentences`, `AlignedSentenceSource.sentences`, `asrFallback` and the call sites `ReadAlongView.swift:96-97`, `MergedCaptureView.swift:384,393`, `QuoteCaptureProcessor.swift:98`. Extract the shared bounds/slice/export/rebase block of `buildOutput` and `buildOutputFromSidecar` into one private helper. Keep `exportSpan`, `bufferAudioURL`, `audioURL`, `quote`, `duration`, `wordTimings`, `spanStart`. Tests: delete `testTimingRebaseFormula`, `testApplyTrimTranscriptAndSpan`, `testTrimRebaseDataContract`, `testTrimExpandToContextSentence` and the `isUnchangedTrim` cases (`AudiobookCaptureMathTests.swift:74-193`, `QuoteCaptureSaveTests.swift:123-212`); edit the `BufferSentence(isInInitialSpan:)` and snapped arguments in `AlignedSentenceSourceTests.swift` (86-100 asserts non-zero snapping, delete those), `TextCaptureTests.swift:43-57` and the buildSentences cases in `AudiobookCaptureMathTests.swift`. Fix the stale docs: `QuoteCaptureProcessor.swift:22-47,71`, `AlignedSentenceSource.swift:44`, the `applyTrimIfNeeded` pointer at `QuoteCaptureSaveTests.swift:125-126`, and `FEATURES.md:236`. Re-grep every symbol by NAME in both apps and tests before deleting; a hit outside its own definition and its own tests means keep and report. Protected-test deletions need Tuur's yes (hand-merge). Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuoteCaptureSaveTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAS-d01 MAS-d02 MAS-c05 MAU-d-m1

### P2 [auto] (todo) audiobook services: small dead code, one interruption rule, comment fixes
spec: C240
needs: -
gate+: no
do: Delete in `SkriftMobile/Services/Audiobooks/`: the single-URL `importBook(from:libraryDirectory:)` overload (`AudiobookImporter.swift:86-91`); `BookBundle.typeIdentifier` (`BookBundle.swift:43-45`) and the `SkriftBookUTI` line and its comment in `SkriftMobile/project.yml:227-229` (keep `SkriftBookExtension`; xcodegen drops the generated Info.plist key); the `starts` parameter of `publishValue`/`publishProgress` and `let starts` at `BookTranscriptionJob.swift:129,181,242,253,397-402`; `AttachSummary.rejectedFiles`, `AttachOutcome.rejected` and the `rejected` counter in `BookAlignment.swift:338,421,436-470`; the unused `derivedSidecars(bookID:)` parameter (`BookBundle.swift:258` and the two callers at 79 and 138); the write-only `levelObserver` (`BookTranscriptionJob.swift:79,478`); the computed `Audiobook.audioFilename` (`Audiobook.swift:76-77`; keep the init label); the redundant `segments.count >= 2` at `ChapterDetector.swift:188`, the unused 999 default on `Heading.init` (name the sentinel `fileStartGap`), and the no-op `total` in `spelledValue` (`ChapterDetector.swift:644-659`); the duplicate chapter-duration loop (`ChapterDetector.swift:539-543`, `BookAlignment.swift:1436-1448`) into one `[AudiobookChapter].fillingDurations(bookDuration:)`. `AudiobookLibraryStore.sortedByRecent` returns `BookSort.recentlyPlayed.sorted(books)` (`Audiobook.swift:535-546`). Move `InMemoryAudiobookTransport` (`AudiobookAudioTransport.swift:48-85`) into `SkriftMobileTests` beside `AudiobookCloudSyncTests`; keep the protocol in the app. Make `resumeAfterInterruptionIfOurs` call `shouldResumeAfterInterruption` and keep its per-branch DevLog lines, `isActive` becomes `var isActive: Bool { book != nil }` (`AudiobookSession.swift:30,136,187,592-648`); the 4 `AudiobookInterruptionTests` stay and now guard the shipped path. `ReadAlongView.swift:78` calls `FileTranscript.isCovered`. Fix comments: `BookTranscriptionJob.swift:336-343` ("~2 s", `chunkLead` is 3.0), `BookTranscriptStore.swift:161-175` (`removeTranscripts` backs the "remove transcript" action only). `sleepLabel` is Q173. Re-grep every symbol by NAME first; a hit outside its own definition and own tests means keep and report. Moving a test double is a protected-test change (hand-merge).
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh AudiobookLibraryStoreTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAS-d04 MAS-d05 MAS-d06 MAS-d07 MAS-d08 MAS-d09 MAS-d11 MAS-d13 MAS-d15 MAS-d-m1..m4 MAS-c29

### P3 [auto] (todo) audiobook plumbing: stop hashing the ePub, one attached-text setter, one folder-path owner
spec: C239
needs: P2
gate+: no
do: (1) `FileAlignment.epubSignature` is documented as compared nowhere and read nowhere (`BookAlignment.swift:136-140,970`), yet every attach and stale re-align reads the whole ePub into memory and SHA-256s it. Keep the field and its Codable shape (persisted in `alignment_f<n>.json`, give it `= ""` so old sidecars still decode); stop computing it: delete `sha256Hex`, the CryptoKit import, `epubSig`/`epubSignatures` plumbing and the two `Data(contentsOf:)` reads (`BookAlignment.swift:1,416,439,452,581,596,617,859-871,942,1452-1454`). Do NOT touch `AudiobookSyncRecord.epubSignature` (the live manifest signature, `AudiobookCloudSync.swift:558-599`). Update the tests that pass `epubSignature:` to `mergedFileAlignment` (`BookAlignmentTests.swift:502,520,541`, `OdysseyRealDataDiagnostics.swift:112`). (2) `Audiobook.setAttachedTexts(_:)` sets `epubFilenames` and the legacy `epubFilename` together; use it at the five write sites (`BookAlignment.swift:510,714,994`, `AudiobookCloudSync.swift:595`, `BookBundleManifest.swift:148`) and collapse `detachedTextFields` to the filtered list; both fields stay Codable. (3) One `AudiobookPaths` enum (root and `folder(for:)`) used by `AudiobookLibraryStore`, `BookTranscriptStore`, `BookAlignmentStore`, `BookmarkStore` and the four `BookTranscriptStore().folder(forBookID:)` calls in `BookAlignmentRunner`; folder layout and file names do not change. (4) One shared file-signature function for `BookAlignmentStore.sidecarSignature` and `BookTranscriptStore.signature(forFileAt:)`; one file-size helper for the five `attributesOfItem` reads; `Audiobook.fileStart(_:)`/`fileDuration(_:)` clamped accessors for the 8 `indices.contains(i) ? a[i] : 0` sites. Never remove a persisted or synced field.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh TextDetachTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAS-d10 MAS-d14 MAS-c02 MAS-c17 MAS-c18 MAS-c24

### P4 [auto] (todo) audiobook CloudKit sync: one sidecar helper, one tolerant continuation, shared decode
spec: C239
needs: P3
gate+: no
do: In `AudiobookCloudSync.swift` the transcript and alignment sidecar sets (`transcriptRecordName/Filename/RecordNames/Parts/Refs`, `sendTranscripts`; lines 410-467 vs 602-657) are the same code. Add a small `SidecarKind` (record-name infix, filename format, signature closure, key path to the carrier signature) and one generic `parts/refs/recordNames/send`. The record-name infixes `_t`, `_al`, `_txt` and the sidecar file names are CloudKit wire names and must stay byte-identical; keep both receive functions separate (transcripts restamp, alignments verdict-gate and derive chapters) and leave the ePub manifest block alone. In `CloudKitAudiobookTransport.swift:145-185` one async helper for the tolerant continuation (`unknownItem` counts as success) shared by download and delete; upload stays strict. `setDownloadRemoved(_:_:defaults:)` for the three `removedDownloads` read-modify-writes, an `AudiobookSyncRecord.book` accessor for the five `JSONDecoder().decode(Audiobook.self, ...)` calls, and one iCloud container-id constant used by `AudiobookCloudSync` and `NotesRepository` (the Mac copy `SkriftDesktop/App/MemoCloudContainer.swift:25-27` may import it if Shared; if not, leave it). Existing `AudiobookCloudSyncTests` and `CloudSignaturePartTests` must stay green unchanged.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh AudiobookCloudSyncTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAS-d12 MAS-c26 MAS-c27

### P5 [auto] (todo) BookAlignment: one align-one-text helper, single-text mergeSentences
spec: C239
needs: P3
gate+: no
do: In `SkriftMobile/Services/Audiobooks/BookAlignment.swift`: (1) `mergeSentences` (771-847) carries a second structure (`appended`, `appendedRemoved`, `appendedTextFiles`, `(inKeep, idx)` tuples) only for an incoming batch that mixes texts, which no caller does (the one caller `mergedFileAlignment:865`, every test in `MultiTextMergeTests`/`AudiobookCostTests` use one `textFile` per batch). Assert that precondition, drop the second structure and the `inKeep` flag; contests happen only between different texts, so incoming sentences never contest each other. Keep the Q57/C218 binary search and the same-text no-contest rule. (2) The per-file align loop (load transcript, skip empty, progress string, `alignFile`) and the transcript-signature loop appear in both `attach` and `alignIfNeeded`; extract one align-one-text helper that takes a progress closure (they differ in sink, `Task.yield` and the `deferring` flag), and one `transcriptSignatures(for:)`. Compute `AttachOutcome`'s aligned/rejected/total from `perFile` so it collapses into `TextAlignOutcome`. Do not change the order assess, pre-check, blobs, commit. Result of `MultiTextMergeTests`, `PerTextChapterMarksTests` and `BookAlignmentStoreTests` must be identical.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh MultiTextMergeTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAS-c06 MAS-c09

### Audiobook UI (MAU)

### P6 [auto] (todo) audiobook screens: dead state, orphan comments, small shared pieces, a toast bug
spec: C240
needs: Q173
gate+: no
do: In `SkriftMobile/Features/Audiobooks/` and the files named: delete the unused `ChaptersBookmarksSheet.initialTab` stored property, its custom init and `AudiobookPlayerView.tocInitialTab` with its two assignments (give `tab` a default `.chapters`; keep the `Tab` enum); delete `session` (`MergedCaptureView.swift:67`), `touched` (71, 425), `repository` (`SyncedAudiobooksView.swift:10`), `dismiss` (`AudiobookSyncSheet.swift:14`); delete the orphan "Attach book text (spike 6)" MARK and its two doc comments (`AudiobookLibraryView.swift:648-660`) and the stray `@ViewBuilder` at 425, rewrite the player class doc (speed and sleep moved to the utility row) and the mini-bar width comment (the chevron was cut), remove `ContinueListeningCard.swift:71` DevLog; inline `AudiobookPlayerView.content(_:)` into `body` (the `!isRegular` idle-recede guard is Q173); keep one UIActivityViewController wrapper (move to `DesignSystem/Components.swift`, update `BookShareSheet.swift:113` and `MemoDetailView.swift:488`); `BookTextSheet.swift:101-132` becomes one status toast fed by `busyMessage ?? (textActivity.isActive(book.id) ? textActivity.stage : nil)`; a store helper for the fresh-alignment half shared by `ReadAlongView.swift:84-91` and `MergedCaptureView.swift:376-379` (leave the two ASR fallbacks separate: MergedCaptureView windows the words before `buildSentences`); `Audiobook.isFinished` replaces the predicate in `BookStatusFilter.matches`, `BookShelfTile.isFinished` and `progressLabel`; `AudiobookSyncSheet` uses `BookTextDisplay.durationText` and the `BookShareCopy.subtitle` doc is corrected (check the format against the book-sharing mock first; `BookShareCopyTests` pins `BookTextDisplay.durationText`); `BookTranscriptionJob.isWorking(on:)` for the four `activeBookID == book.id && isRunningOrPaused` sites; `MergedCaptureView` uses `createdMemoID != nil` instead of `handedOff` and throws one `QuoteCaptureError` so one catch shows the failure toast; one `captureWindow` helper for the 90 s look-back in `AudiobookPlayerView.swift:543-547` and `MergedCaptureView.swift:93-94`; `ContinueListeningCard.today()` uses a `static let` formatter. Bug: `Player.showToast` (`AudiobookPlayerView.swift:485-491`) clears after 1.6 s without checking the text, so a second toast inside that window is cleared early; add the same text guard `showSplitToast` has (`MemoDetailView.swift:835-841`).
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh BookTextSummaryDisplayTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAU-d04 MAU-d05 MAU-d06 MAU-d07 MAU-d08 MAU-d10 MAU-d13 MAU-d16 MAU-d17 MAU-c14 MAU-c18 MAU-c21 MAU-c23 MAU-c29

### P7 [tuur] (todo) retire TranscribeBookView: the read-along nudge opens the Text sheet
spec: C240 C115
needs: P6
gate+: no
do: `TranscribeBookView.swift` is reachable only from the read-along nudge (`ReadAlongView.swift:427` to `AudiobookPlayerView.swift:165`, `showTranscribe`); `BookTextSheet` Level 1 shows the same status, progress, ETA and start/pause/resume. Tuur decides: the nudge would open the two-level Text sheet (`bookTextBook = book`) instead of a one-purpose sheet (the audiobook-player-redesign mock routes the nudge to the old sheet, so a signed mock changes). If yes: first port the one thing only `TranscribeBookView` shows, the `.failed(why)` "Stopped: ..." line (`TranscribeBookView.swift:127-132`; the job sets `.failed` at `BookTranscriptionJob.swift:179,250` and BookTextSheet never reads it, so a plain delete would make a failed transcribe silent); then delete the file, `showTranscribe` and its `.sheet`, `reflectSavedProgress` and `estimatedRemainingSeconds` (`BookTranscriptionJob.swift:98,135`); move `shortDuration` (`BookTextSheet.swift:331,346`, `BookTextPromptSheet.swift:105`) into `BookTextDisplay`; fix the comments at `AudiobookPlayerView.swift:284` and `BookTextSheet.swift:9,341`; trim Q187's transcribe-book copy clause. Test: `BookTextSummaryDisplayTests` gains a failed-phase case.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh BookTextSummaryDisplayTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAU-d02 MAU-c01

### P8 [auto] (todo) shared book sheet pieces: progress bar, grabber, scaffold, glass chrome, labelled field
spec: C239 C240
needs: P6
gate+: no
do: In `DesignSystem/Components.swift` add `ThinProgressBar(fraction:height:fill:)` (BookShareSheet, BookImportSheet, BookTextSheet, BookShelfTile; the shelf tile turns green when finished, so the fill is a parameter), `SheetGrabber` (the 34 and 36 pt capsules in `AudiobookSyncSheet`, `BookTextPromptSheet`, `TextSettingsSheet`, `BookShareSheet`, `BookTextSheet`, `BookImportSheet`, `ChaptersBookmarksSheet`; keep the drawn handle, the signed mocks draw it, do not switch to the system indicator), `LabeledTextField` and a cancel/confirm row for `AudiobookImportConfirmSheet` (move it to its own file) and `EditBookDetailsView`, a `miniGlass(height:)` modifier plus one `.bookSessionCovers(showPlayer:showCapture:)` for `AudiobookMiniPlayerBar.swift` bar and pill (keep the two layouts), and a `BookTransferSheet` scaffold for `BookImportSheet` and `BookShareSheet` (cover view and detents stay parameters). In the same sheets: compute `totalBytes` once, drop the phases that render like the one before them (`.done`, `.landed`), `packagedBytes`, `attachedTexts`; keep `guard case .packaging = phase` in the progress callback (it blocks late callbacks after cancel); a `.textCard()` modifier for the three card chrome sites in `BookTextSheet`. Sheets must look the same: render the sheets headlessly (`-showTextSheet` etc.) before and after and compare.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh BookShareCopyTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAU-d09 MAU-d14 MAU-d15 MAU-c11 MAU-c12

### Memo detail (MMD)

### P9 [auto] (todo) memo detail: dead conversation mock, unused state, imports, stale comments
spec: C240
needs: P12
gate+: no
do: In `SkriftMobile/Features/MemoDetail/` and the files named: delete `ConversationMockView.swift`, the `LaunchFlags.conversationMock` flag and RootView branch (`App/LaunchArgs.swift:47-48`, `App/SkriftApp.swift:290-291`) and `testConversationMock` (`SkriftMobileUITests/ConversationMockUITests.swift:13-23`; the other tests in the file stay, including `testRealConversationMemoRendersTurns`); then make `SpeakerTurnsView.speakerSlots` required and delete the first-appearance fallback (`SpeakerTurnsView.swift:8-12,31-43`; only the mock ever passed no slots). Delete `exportedBump` and its comment fragments (`MemoDetailView.swift:57-60,255-257,815`; the re-render already comes from `exportFlash = nil`). Delete `QuickLookTarget` (`MemoPageView.swift:23-29`) and change `photoWasEdited` to take `marker: Int?` at the three sites. Delete the `Coordinator.init(memo:onCommit: () -> Void)` convenience (`NoteBodyView.swift:264-269`) and change the 12 test sites to `onCommit: { _ in }` (`NoteBodyTests` x11, `QuotePresentationTests.swift:177`; `{}` would not satisfy the `(Bool) -> Void` form). Drop `enroll:` from `assign(_:to:enroll:slot:turnSlots:)` (`MemoPageView.swift:194,196,909,919-921`). Remove the 8 unused import lines (`MemoDetailView.swift:4-6`, `MemoDetailSupportTypes.swift:2-6`, `MemoPageView.swift:4`; keep MemoPageView's PhotosUI and FluidAudio). `SpeakerTurnsView.segmentItems` uses the static `BodyV2Marker.regex` instead of compiling one per turn per render (do NOT switch to `BodyTransform.pieces`, it also tokenises tasks and links). The compact dialog uses `NoteMenuItem` labels for lock, share, copy and delete (`MemoDetailView.swift:462-467`). Fix stale comments: `MemoDetailView.swift:8-13,36-38,427-431,663-667,743-745`, `MemoPageView.swift:45,141,148-155,389-393,1547`, `NoteBodyView.swift:338,521` ("Q14 removes it": `BodyV2Legacy.swift:3` says Q14 kept it), `ConnectionsPanel.swift:4-16,47-53` (the importance doc sits on the wrong declaration), `MemoDetailSupportTypes.swift:78-82`. Do not touch `PlayerBar.density` (Q121), `ConnectionsPanelLogic.ordered` (after Q181) or the draft/selection probes in `NoteBodyView` (an open device bug). Re-grep every symbol by NAME first.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh NoteBodyTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MMD-d01 MMD-d02 MMD-d03 MMD-d05 MMD-d07 MMD-d13 MMD-d14 MMD-d15 MMD-d16 MMD-c08

### Shared pipeline (SPL)

### P10 [auto] (todo) move the v1 body fixtures into the tests: Paragrapher.paragraphed and ImageMarkers.insert
spec: C240
needs: -
gate+: no
do: `Paragrapher.paragraphed` and `defaultGap` have no production caller (`Shared/Pipeline/Paragrapher.swift:20-21,32-79`); `plan/RUN.md:109` records that Q80 kept `paragraphed` only as the fixture for `BodyNormaliseMigrationTests.swift:49`. `ImageMarkers.insert` (`Shared/Pipeline/ImageMarkers.swift`, 63 lines) is used in production only by the phone's `SeededTranscriber` (`SkriftMobile/Services/Transcription/TranscriptionService.swift:300-318`); real transcription uses `BodyV2.committed` (`ASRPostProcess.swift:60-68`). Make `SeededTranscriber` call `BodyV2.committed` the same way. Move the v1 paragraph splitter and the v1 marker inserter into `BodyNormaliseMigrationTests` as one private fixture helper (both test targets compile it; the Mac and phone test files each get their own copy only if they share no file), delete `ImageMarkers.swift`, `Paragrapher.paragraphed`/`defaultGap`, `ParagrapherTests` cases for them, the two `ImageMarkers` cases in the transcription-logic tests (`SkriftMobileTests/TranscriptionLogicTests.swift:54-84`, find the class name with grep), and fix the doc at `SkriftMobile/Models/FillerFilter.swift:33`. Keep `Paragrapher.endsSentence` and `longFormGap` (live in `LiveCaptionEngine`). Run the photo-bearing `MemoSaverTests` that use `SeededTranscriber` (e.g. `MemoSaverTests.swift:47`): they will now see v2 placement; if any expectation changes, list it in the commit message. Protected-test edits: hand-merge after Tuur's yes.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh MemoSaverTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SPL-d01 SPL-d02

### P11 [auto] (todo) shared pipeline: unused overloads, always-default parameters, stale headers
spec: C240
needs: -
gate+: no
do: In `Shared/Pipeline/` (all compiled into both apps; re-grep each symbol by NAME in both apps and all tests first): delete `Karaoke.activeWordIndex(_:at:hint:)` (`Karaoke.swift:26-38`); `TranscriptionResult.durationMs` and the `durationMs` parameter of `ASRPostProcess.finish` with the three engine fills and the 22 test/stub constructions (`TranscribingContract.swift:14`, `ASRPostProcess.swift:31-69`, both `TranscriptionService.swift`, `StubEngines.swift:18`; the assertion at `ASRPostProcessTests.swift:26` goes); `SplitSpeakersCopy.rateFirstShort` only if Tuur confirms (it is signed Q86 copy: keep by default), `ASRLanguageStore.mode(defaults:)`, `VocabularyTermParsing.canonical(_:)` (+2 tests), `KaraokeTrackCache.invalidate()`, `CommitOnceCache.invalidate()` (`ProcessPile.isDone` is Q102's); the explicit `AlignmentCore.Config.init` and `SpeakerTranscript.Turn.init` (keep memberwise; `Karaoke.swift:75` calls `Config()`, tests call `.init(anchorN: 2)`); the unreachable `?? timings[0].start` and final `out.map { $0 ?? firstKnown }` in `Karaoke.wordTimes`; `EPubTOCEntry.fragment` and the second tuple value of `splitFragment` (11 test constructor lines); reduce `Karaoke.seekTarget` to the in-range check plus clamp and port `QuoteSeekTests.swift:28` to `KaraokeTrack.seekTime`; inline the rms/wordCount overload of `shouldDropAsPhantom` (`BPEMerge.swift:72-93`, 5 test lines) and flush `pending` directly in `mergeBPETokens`; `KaraokeTrackCache` becomes a `CommitOnceCache<KaraokeTrack.CacheKey, KaraokeTrack>` at `SkriftDesktop/Features/Review/NoteBody.swift:38` and both `KaraokeTrackTests:63`; delete the redundant `distantPast` guard at `LanguageSyncCore.swift:34-39` (keep the "never broadcast a default" sentence); merge the two `collectBlocks` branches and drop `ManifestItem.id` in `EPubParse.swift` (keep `lenientParse`). Fix the stale headers (`Karaoke.swift:40-71`, `AlignmentCore.swift:8-14`, `Paragrapher.swift:11-15,23-29`, `MemoSpine.swift:5-9`). Do not touch `ASRLanguageStore.isMultilingual`, `Karaoke.seekTime(forWord:in:)` or `Paragrapher.endsSentence`.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh KaraokeTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SPL-d04 SPL-d05 SPL-d06 SPL-d08 SPL-d10 SPL-d15 SPL-d16 SPL-d17 SPL-d18 SPL-c02 SPL-c07 SPL-c17 SPL-c18 SPL-c20

### P12 [auto] (todo) lifecycle and spine: delete the unbuilt queue states, one ceil-days, one displayRange
spec: C240
needs: Q102
gate+: yes
do: (1) `MemoSpine` (`Shared/Pipeline/MemoSpine.swift`): `QueuePhase`, `Input.queue`, `Input.macLocalFile` and the Station cases `.processing`, `.stuck`, `.ready`, `.exported` are never built by production (all 11 callers use `.from(memo, backlinked:)`); delete them with their `oneLiner` arms and `testActiveTrackFollowsTheQueuePhase` in both `MemoSpineTests`; collapse the rated branch to `if input.rated { return .toProcess }`; delete the explicit `Input.init` (inline defaults) and fix the header (it claims the Mac builds this from `Memo + PipelineFile`). Keep `.toProcess` and its one-liner. (2) `MemoLifecycle.daysUntilSweep` has no production caller: delete it and its 3 asserts per test file (6 lines in all). `MemoSpine.daysUntil` calls `WayOut.daysLeft(until:now:)`; one shared `days(_:)`; rename `MemoLifecycle.fadesAt` (it returns the trash date) to `trashesAt` (`WayOut.swift:23`, `WayOutViewTests`, `MemoLifecycleTests:52`); `WayOut.isUrgent` uses one pattern `case .fading(let d), .deleted(let d)`. (3) `BodyTransform.displayRange(forRaw:in:)` becomes `displayRanges(forRaw: [raw], in: text)[0]`; delete the private unused `NoteBodyView.Coordinator.displayRange(forRaw:transcript:)` (`NoteBodyView.swift:548-555`); delete `displayLength` (use `r.length - 1`); fix the stale comments `BodyTransform.swift:74-77,92-93`. Coordinate: Q102 edits `ProcessPile.isDone`; do not touch it here. Do not touch `MemoLifecycle.goneAt` (P43 owns it). Protected-test edits: hand-merge after Tuur's yes.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh MemoSpineTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SPL-d03 SPL-d07 SPL-d11 SPL-c20 SPL-c30 MMD-d06

### P13 [auto] (todo) one number-word table for AlignmentCore and ChapterDetector
spec: C239
needs: -
gate+: no
do: `AlignmentCore.swift:286-340` and `SkriftMobile/Services/Audiobooks/ChapterDetector.swift:607-668` hold the same EN and NL units/teens/tens tables, the linking-word filter, the hundred rule and `dutchGlued`; AlignmentCore's own comment (279-285) says "consolidate later". Add `Shared/Pipeline/NumberWords.swift` with the tables, `dutchGlued` and `value(of parts:)`. `AlignmentCore.canonicalizeNumberWord` keeps its lowercase, diaeresis fold, trim and hyphen split and calls it; `ChapterDetector.spelledValue` calls it after joining tokens. Delete both table blocks. Behaviour must not change: `AlignmentCoreTests` and `ChapterDetectorTests` (including 379-383, which exercise `spelledValue`) stay green unedited.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh ChapterDetectorTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SPL-c01

### P14 [tuur] (todo) delete the one-clock migration once every device has run it
spec: C240
needs: -
gate+: no
do: `migrateParkedToOneClock` and `runOneClockMigrationOnce` (`Shared/Pipeline/MemoLifecycle.swift:147-184`, defaults key `oneClockMigrated.v1`, from 2026-07-22) run at launch on both apps: `RootView.swift:164`, `SkriftApp.swift:132` and `:201`. `Memo.keptAt` syncs through CloudKit, so one device's run already propagated, but a build that predates the change would not have run it. Tuur confirms the prod iPhone, iPad and Mac each launched a build with it; then delete both functions, the three call sites and their tests (`MemoLifecycleTests ~177-190` in both apps; `MemoSpineTests:166-167` uses it as a setup helper: replace with `memo.keptAt = now`). Do nothing if he cannot confirm.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh MemoLifecycleTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SPL-d14

### P53 [auto] (todo) speaker transcript: one rebuild, one header regex, one slot assigner
spec: C239
needs: Q183
gate+: no
do: `SpeakerTranscript.swift` rebuilds `**name:** text` joined by blank lines in `setText`, `reassign`, `mergeAdjacentTurns`, `relabel`, `relabelSlot` (lines 138,148,169,180,193) and `SpeakerFusion.swift:44` does the same. Add `Turn.markdown` and one `renamed(_:_ pick: (Int, Turn) -> String?)`; `reassign`, `relabel`, `relabelSlot` become one-liners (`relabelSlot` keeps its count guard). `SpeakerTurnStyle.headerRegex` (line 85) recompiles the pattern `SpeakerTranscript` already compiles at 39: make that one internal and delete `headerPattern`; add `SpeakerTranscript.parsedLabel(_:)` for the bracket strip used at `SpeakerTranscript.swift:66-67` and `SpeakerTurnStyle.swift:96-97` and one `preamble(of:)` for `parseWithPreamble:83-84` and `withPreamble:93-97`. First-appearance slot assignment in `turns(in:)` and `slots(forParsedNames:)` becomes one `SlotAssigner`; drop `HeaderResolver.ambiguous` (`person(for:)` already requires `cands.count == 1`) and add `HeaderResolver.identity(forDisplayed:)` for the four `identity(for: SpeakerTurnStyle.label(for: x))` calls in `SpeakerNaming.swift`. Do NOT touch `SpeakerFusion`'s three scans (re-fusing the same segments must give the same turns). Q183 edits `SpeakerTurnsView` and the active-word code, not these files; keep the public names. `SpeakerTranscriptTests`, `SpeakerFusionTests`, `SpeakerNamingTests` stay green unedited.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh SpeakerTranscriptTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SPL-c10 SPL-c11 SPL-c12

### Mac review column (DRV)

### P15 [auto] (todo) Mac review column: unused parameters, one title builder, comments in the right place
spec: C240
needs: Q116
gate+: no
do: In `SkriftDesktop/Features/Review/` (and `Features/Shell/RootView.swift:101-107` for the caller): delete `ConnectionsModel.count` (`ConnectionsPanel.swift:50`; the header recomputes at 199) and the "toolbar badge" comments (`ConnectionsPanel.swift:40-42`, `NoteDisplayView.swift:55-58`); remove `UnratedNotePane.onRated` (`UnratedNotePane.swift:15,19-21,56`, caller passes `{ _ in }`); drop `enabled` and `fadingLine` from `MacRatingRow` (`SignificanceCircles.swift:15-21`; the one caller is `UnpipelinedMemoSheet.swift:172`); use `inspectorOpen` at `NoteDisplayView.swift:233`, make `capabilities` a function of the non-optional file so the nil guard goes (keep the `NoteCapabilities` struct: two channels, spend vs claim; drop its unused `Equatable`); `NoteActions.swift:91` `if isConversation {` and one `copyItems` view for the two copy buttons (the two branches order `undoTidyUpItem` differently, hold only the buttons); `NoteProperties.swift:170-207` `titleSection` = chooser VStack or `titleLine` (re-render the `-snapshot` title once), one `.onChange(of: file.significance)`; `contextChips(includeDayPeriod:)` default true instead of the literal 4 SF Symbol set (`NoteProperties.swift:138-141`, `PipelineFile.swift:296-310`; `MemoNoteProjectionTests:138-140` keeps passing); `PipelineFile.sharedContent` for the four `SharedContent.decode(from:)` sites (`CaptureViews.swift:12,69,115`, `NoteProperties.swift:271`) and delete the no-op `u.path.isEmpty ? "" : u.path`; `MemoCloudStore.memo(id:context:)` (predicate fetch, limit 1) for `SplitSpeakersRow.swift:175` and `UnratedNotePane.swift:88`; use `NoteConsent.isRated(new)` instead of `value > 0` at `UnratedNotePane.swift:55` and `UnpipelinedMemoSheet.swift:72`; inline `sourceLabel(_:)` (`NoteDisplayView.swift:586-590`); move `KaraokePlayback.init(fractionOf:fraction:)` into a `#if DEBUG` extension in `Snapshot.swift` (`BodyTextView.swift:93-103`); the "this note" `ThreadEntry` in `ConnectionsPanel.swift:272-283` gets a stable id instead of `UUID()` per render. Comments: delete the two ReviewHelpers tombstones (`ReviewHelpers.swift:35-43`), fix "Actions are stubbed" (`NoteActions.swift:7`), "10-circle control" (`NoteProperties.swift:9`), "chunk 4" (`BodyTextView.swift:14-17`), "Q14 removes it" (`BodyTextView.swift:193,505`), and move the doc blocks onto the right declaration (`BodyTextView.swift:5-18,1215-1218`, `NoteDisplayView.swift:330-331,454-458`, `NoteActions.swift:54-64`). Q116 rewrites the naming overrides in `NoteDisplayView.swift:356-403`; do not touch that block. Never run SkriftDesktopUITests; Mac proof = unit tests + full build + headless `-snapshot-shell`.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DRV-d01 DRV-d02 DRV-d03 DRV-d04 DRV-d05 DRV-d06 DRV-d09 DRV-d10 DRV-d11 DRV-d12 DRV-d16 DRV-d19 DRV-c16 DRV-c18 DRV-c19 DRV-c21 DRV-c27

### P16 [tuur] (todo) retire the second SwiftUI-Text note renderer: move three snapshots to the hosted render
spec: C240 C117
needs: P15
gate+: yes
do: `NoteBody.swift` (`BodyText`, `readBody`, `quoteCard`, `karaoke`, `summaryAside`, the Text fallbacks, lines 15-288) and the `scrollable`/`interactive` flags in `NoteDisplayView`, `NoteProperties`, `SidebarView` (`SidebarView.swift:20,700-714`) and `SplitSpeakersRow.swift:73-76` exist only so three ImageRenderer snapshots (`Snapshot.swift:1013-1016,1163-1166,1249-1252`, `-snapshot`, `-snapshot-light`, `-snapshot-capture`) can avoid ScrollView and NSTextView; live `interactive` always takes the NSTextView editor. About 150 lines and the flags can go if those three move to the hosted `renderShell`/`hostPNG` path. Tuur decides, because CLAUDE.md names the headless `-snapshot` as the Mac proof and `plan/RUN.md:57,86-87` records that `hostPNG` misdraws `.bordered` system buttons, truncates unwrapped text and still shows a ~12 px left-edge cut: so each moved snapshot needs an eyeball pass (render before and after, view both PNGs) and nothing is deleted until all three look right. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DRV-d15 DSH-c14

### P17 [auto] (todo) one word-split rule for Mac karaoke: emoji no longer splits a word
spec: C113 C240
needs: -
gate+: yes
do: Bug found by reading, not run: `BodyTextView.Coordinator.wordRanges` (`SkriftDesktop/Features/Review/BodyTextView.swift:569-585`) calls `UnicodeScalar(c) ?? UnicodeScalar(32)` on a UTF-16 unit; that initialiser returns nil for a surrogate half, so every emoji or non-BMP character is classed as whitespace. A word like `great😀day` is split in two there, while `NoteBody.karaokePlayback` (`NoteBody.swift:167`) and `KaraokePlayback.init(fractionOf:)` count one word, so karaoke highlight and click-to-seek drift one word per emoji after it. First write a failing test on the shared `KaraokeMap.wordRanges` with an emoji. Then make the Mac coordinator use `Shared/Pipeline/KaraokeMap.swift:17-45` (add `countAttachmentOnlyTokens: Bool = false`; the Mac passes true, since its gutter attachment must count as a word, comment near `BodyTextView.swift:695`), delete `Coordinator.wordRanges`, and update its other callers (`BodyTextView.swift:535,1009`, `Snapshot.swift:819`). If the emoji case does not reproduce, log what you found and still do the dedupe. Never run SkriftDesktopUITests; Mac proof = the shared unit test + full build.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DRV-d14 DRV-d-m1 DRV-c08

### Mac shell (DSH)

### P18 [auto] (todo) Mac shell: delete the unused stub engines, naming demo and dead members
spec: C240
needs: -
gate+: no
do: In `SkriftDesktop/`: delete `Features/Shell/StubEngines.swift` and the DEBUG `-stubEnhancement` branch (`ProcessingCoordinator.swift:33-66`); make `transcriber`/`enhancer`/`diarizer` plain `= Service.shared`, delete `stubbedEngines` and un-guard the five sites (186, 285, 376, 496, 637); fix the comment at `SkriftDesktopUITests/ReviewWalkthroughUITests.swift:11`. Nothing launches the flag (`BatchRunnerTests` has its own private stub). Delete `-naming-demo` and `DemoSeed.seedNamingDemo` (`DemoSeed.swift:19-61`, `RootView.swift:166-177`; `-snapshot-naming` covers it) and fix the stale `DemoSeed.swift:3-6` header; wrap the `-demo` branch and `DemoSeed.seedIfEmpty`'s call in `#if DEBUG` (`RootView.swift:178-179`; today a Release `Skrift -demo` on an empty store seeds fake notes; the UI tests run Debug). Delete `Theme.violet` (`Theme.swift:42`), `LifecycleSweepScheduler.activationObserver` (49,57: call `addObserver` without storing it), the unused `in pf:` parameter of `ProcessingCoordinator.diarizationSlot` (520, call at 489), `SidebarSort` raw values, the unreachable `guard !isRunning` at the top of `runProcess` and `runTranscribe` (134, 271). `RootView`: `@State private var coordinator: ProcessingCoordinator` with no default (init assigns it), `model.select(id)` instead of `activeID = id; selection = [id]` at 48-50, 135-137, 226-230 (it also sets the selection anchor; keep the `surface = .queue` lines), drop `onRated`, one `.frame(minWidth: 480...)` on the pane switch. Replace `AppModel.ReviewShelf` and `JournalView.mapMode` with one `enum JournalColumn { lookback, map, wayOut }` kept as `@State` in `JournalView` (`JournalView.swift:42,149-308`; not on AppModel, so map mode does not start surviving a surface switch); inline `shelfRow`. `SkriftDesktop/project.yml:187-190`: remove the redundant `Pipeline/Recording` test-source entry and its comment. Do not touch `LiveRecordingSession.cancel` (Q at QUEUE.md:1225 may wire it). Never run SkriftDesktopUITests; Mac proof = unit tests + full build + headless `-snapshot-shell`.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DSH-d01 DSH-d02 DSH-d05 DSH-d06 DSH-d13 DSH-d14 DSH-d16 DSH-d17 DSH-d20 DSH-c08 DAU-c04 DPE-d20 PER-d12

### P19 [tuur] (todo) delete finished Mac headless probes
spec: C240
needs: -
gate+: no
do: These DEBUG flags have no invoker in `plan/*.sh`, `gate.sh`, UITests, SPEC or QUEUE. Tuur picks which to delete: `-aligncheck` (`RunFile.swift:7,574-632`; also drops the Mac's only ZIPFoundation use: remove the package and the target dependency from `SkriftDesktop/project.yml:19-21,161-162`, regenerate; it is the only headless way to run `AlignmentCore.align` on a real ePub); `-asrsweep` plus `wer`, `wordCount`, `import CoreML` (`RunFile.swift:3-4,383-471`; `Shared/Pipeline/ASRLanguageMode.swift:7` and `SkriftMobile/Services/Transcription/TranscriptionService.swift:84` cite it as the language-mode evidence: reword both, and fix the stale `7f963cd` pin in the comment at `RunFile.swift:388`, the pin is `19600a48`); `-audiodate` (`RunFile.swift:320-332`); `-vaultpreview` (`RunFile.swift:293-318`); `-voiceloop` (`RunFile.swift:334-384`; it backs up, clears and restores the Dev names.json in memory with no `defer`, `plan/data-loss.md:51` row 31); `-asrbench` (`RunFile.swift:181-213`, cited for a measured speed in `FEATURES.md:183`); `-snapshot-wizard`, `-snapshot-run`, `-snapshot-settings` and `ProcessingCoordinator.preview` (`Snapshot.swift:41-43,1135-1170,1329-1334`, `ProcessingCoordinator.swift:68-73`; `-snapshot-settings-hosted` supersedes the last). Keep `-chunksim`, `-readalongcheck`, `-runfile`, `-snapshot`, `-corpus`. Update `FEATURES.md:74,183` and `plan/extraction/decisions.md:334` for whatever goes. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DSH-d07 DSH-d08 DSH-d09 DSH-d19 PER-d13

### P20 [auto] (todo) one relink helper for the four conversation-or-monologue sites, bestBodyText in the model layer
spec: C239
needs: Q116
gate+: yes
do: The block "conversation ? `Sanitiser.processConversation` : `Sanitiser.process`, then write `sanitised` and `ambiguousNames` (empty means nil)" is typed four times: `ProcessingCoordinator.swift:664-672,694-704`, `BatchRunner.swift:278-282`, `MemoCloudUpdate.swift:151-160` (its comment at 146-148 admits it is inlined from the coordinator to stay pure). Add one helper in `Models/PipelineFile.swift` or `Pipeline/` (host-less, not on the coordinator) `relinkNames(_ pf:, working:, isConversation:, people:)`; each site keeps its own `isConversation` decision (BatchRunner derives it once from the transcript at 216 and reuses it for tags and copy-edit; the others derive it from `working`), `sanitiseStatus` and compile step. Move `bestBodyText` (`sanitised ?? enhancedCopyedit ?? transcript`, `Features/Review/ReviewHelpers.swift:10`) into `Models/PipelineFile.swift`, use it in `SplitSpeakers.swift:9-11` (delete `shownBody`), `SidebarView.swift:1295`, `ConnectionsPanel.swift:123,134` (Q120 also edits `backlinkScan`: keep your edit to the call). `BatchRunner:199,201,237` compare optionals and `CompilerBridge:98` reads a `CompilerInput`; they do not use it. The phone's `MemoLinking.swift:18-29` routes on a looser predicate (`parse != nil`, 2 headers, vs `isAttributed`, 2 distinct names): do not unify the routing here; record the difference in the commit message and ask Tuur. Existing `BatchRunnerTests`, `MemoCloudUpdateTests`, naming goldens stay green unedited. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DSH-d11 DPE-c02 DRV-c17

### P21 [auto] (todo) Mac process queue: a Process asked during a Redo no longer gets stranded
spec: C49 C239
needs: P18
gate+: yes
do: Bug found by reading, not run: `ProcessingCoordinator.redo` sets `isRunning` itself (`ProcessingCoordinator.swift:625`) and never goes through `submit()`; `submit` (111-114) enqueues when `isRunning` and returns, and the only drain loop lives in the `submit` call that holds `draining`. A Process, Transcribe or Split request that arrives during a Redo (recording-stop transcribe, import auto-transcribe with `announce: false`) therefore sits in `waiting` until some later `submit` happens to drain it. The sidebar button is disabled while `isRunning` (`SidebarView.swift:484`) but the automatic paths are not. Write a failing test through the coordinator seam (queue a job during a redo, expect it to run when the redo ends), then fix: either drain `waiting` in `redo`'s `defer`, or add `.redo` to `RunQueue.Job` (note a queued redo changes its `await`: callers at `SidebarView.swift:1086-1092` and `NoteActions.swift:101` do not expect it to return early). Same file: `isRunning` becomes `runState != nil` (they are always set and cleared together; `runState` is read at `SidebarView.swift:916`); one `beginRun/endRun` pair for the lifecycle pasted in `runProcess`, `runTranscribe` and `redo` (lines 144-155, 276-283, 625-632), keeping the real differences: `runTranscribe` loads only the ASR model and never sets `modelsLoaded`, only `runProcess` and `redo` call `ConnectionsIndexService.shared.sweepSoon`; one constant for the "A run is already going" message (134, 580, 609, 621); `setSplitNotice` clears by a per-id token like `flash()` instead of by text compare (`ProcessingCoordinator.swift:460-516`). Do NOT share a `hasAudio` helper: `runProcess` requires `sourceType == .audio`, `runTranscribe` (304) does not; note that divergence in the commit message. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DSH-d12 DSH-d21 DSH-c02 DSH-c17

### P22 [auto] (todo) Mac headless harnesses: one arg parser, one runner, and a swallowed error fixed
spec: C240
needs: P19
gate+: no
do: `RunFile.swift` has 17 `...IfRequested` entry points; 16 define their own `log()` (two to stdout, `runVaultExportIfRequested` at 226 and `runVaultPreviewIfRequested` at 309, the rest to stderr: keep both) and each parses its argument with `firstIndex(of: "-flag"), i + 1 < count` (19 sites). Add `LaunchArgs.value(after:)` (move the phone's `[String].boolFlag/stringValue` from `SkriftMobile/App/LaunchArgs.swift` into `Shared/Model` so both apps and `Snapshot.swift:26`, `CorpusSeed.swift:242`, `ProcessingCoordinator.swift:50`, `LifecycleSweepScheduler.swift:68`, `NoteDestination.swift:145,153`, `PortfolioVault.swift:54` use it; the phone helper also accepts `-key=value`, harmless) and a small `Harness` helper (arg lookup, log, `main(body)` that catches, prints and exits 0 or 1). Bug first: `runRateToRowIfRequested` (`RunFile.swift:863-923`) uses `try` inside `Task { @MainActor in }` with no catch, so a throw from `typedNote` (878) or `cloudCtx.save()` (887) is swallowed, `exit()` is never reached and the process carries on as a GUI app; fix it before the refactor. `-readalongcheck` (`RunFile.swift:141-172`) calls `anchorDrift` after extending it to return its rows and percentiles (it prints p10/p90/min/max and a per-anchor listing; the harness stays, `SPEC.md:1218`, `CLAUDE.md:190`). `fixtureStore(full:)` in `Snapshot.swift` for the ten in-memory containers (eight seed `DemoSeed.snapshotFiles()`; schemas differ, so the schema is a parameter). One constant for `-isolatedRun` (`SkriftDesktopApp.swift:14`, `MemoCloudContainer.swift:55`, `RootView.swift:192`) and one `isXCTest` for the six `XCTestConfigurationFilePath` sites. Flag names and output formats must not change (plan/*.sh and RUN.md use them). Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DSH-c10 DSH-c09 DSH-c12 DSH-d10 DAU-c21 PER-c02

### Mac pipeline and engines (DPE)

### P23 [auto] (todo) Mac settings: delete the dead toggles and the old wire DTOs
spec: C240
needs: -
gate+: no
do: In `SkriftDesktop/`: delete `Models/FileDTO.swift` (`StepsDTO`, `FileDTO`, `UploadResponseDTO` reference only each other; xcodegen globs `Models/`); `AppSettings.audioFolder` and `attachmentsFolder` (`AppSettings.swift:8-9`) and their two harness lines `RunFile.swift:561-562` (leave the legacy keys in the `CustomVocabularyTests.swift:22` JSON fixture: unknown keys are ignored on decode, it proves old settings.json files still load; update the comment at `AppSettings.swift:6-7`); `processAllSyncedMemos` and the `processEverything` parameter of `MemoCloudReconciler.sweep` and `MemoCloudIngest.ingest` with the `|| NoteConsent.isRated` arm (`MemoCloudReconciler.swift:49,139`, `MemoCloudIngest.swift:27-40`, `MemoCloudReconciler+Wiring.swift:105-107`; SPEC D57 already says delete it; update `FEATURES.md:301`), delete the two true-case tests (`MemoCloudReconcilerTests.swift:80`, `MemoCloudIngestTests.swift:138`) and drop `processEverything: false` from the other 29 + 1 + 1 test lines; `AppSettings.conversationMode`, `conversationModeEnabled` and the nil-ing in `SettingsStore.load()` (`AppSettings.swift:39-50,159-162`), reduce `BatchRunner.swift:146` to `pf.diarizeRequested`, point `DiarizationTests:119,132,175,473` at `pf.diarizeRequested`, and rewrite `DiarizationOptInTests.legacySettingsFile()` (:30-34) to write raw JSON containing the legacy `conversationMode: true` key so the regression guard survives (the typed field will not exist). Re-grep every symbol by NAME first. Protected-test edits: hand-merge after Tuur's yes. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DPE-d01 DPE-d02 DPE-d03 DPE-d04 DAU-d11 DAU-d12 DAU-d13

### P24 [auto] (todo) Mac and phone engines: unread fields, a one-field wrapper, one unused sweep helper
spec: C240
needs: -
gate+: no
do: Desktop `Engines/TranscriptionService.swift`: delete `models` (the strong ref is redundant: `AsrManager.loadModels` holds them), `ready` and its writes, `isModelReady`, `liveCaption()` (`:22,36-42,52-53,65,68,82-84,179-183`) and, since only `finalTail` is read, make `finishStreamParts` return just that (keep the Shared `LiveCaptionEngine.finishParts` API); `EnhancementService.isModelReady` (29); `MacRecorder.isRecording` (114) and the write-only `deviceInput` (130, 272, 354; keep `cancel()`); `RunQueue.isWaitingSplit` (`RunQueue.swift:69`, one assertion at `SplitSpeakersTests.swift:107` becomes `q.jobs.contains(.split(id: "a"))`; check the Q62 verdicts first); `MemoCloudReconciler.existingFile` (`:93,182-191`; keep `SweepOutcome.stranded`, `MemoCloudReconcilerTests.swift:340` asserts it); the `PipelineFile.steps` setter (`PipelineFile.swift:238-243`; `PipelineFileTests.swift:17-18` assigns `transcribeStatus`/`enhanceStatus` instead). `Boosted.replacementCount` and the `Boosted` wrapper: `boost()` returns `String?` in both `SkriftDesktop/Engines/VocabularyBooster.swift:29-32,95-96` and `SkriftMobile/Services/Transcription/VocabularyBooster.swift:65-68,129-130` and their one consumer (`TranscriptionService.swift:121-123`, phone `:175-177`). The phone-side `isModelReady` (x3) and `finishStream` are P38's. Do NOT touch `StepStatus.skipped` or the `RunReconciler` lines that heal old stores (persisted SwiftData column). Re-grep by NAME first. Protected-test edits: hand-merge after Tuur's yes. Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh VocabularyBoosterTrustTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DPE-d05 DPE-d06 DPE-d07 DPE-d10 DPE-d11 DPE-d23 MSV-d16 DPE-c11

### P25 [auto] (todo) Mac pipeline: drop the WayOut forwarders, one ISO parser, a few tidy-ups
spec: C239 C240
needs: Q114 Q178
gate+: no
do: In `SkriftDesktop/`: delete the four pure forwarders in `Pipeline/WayOutRules.swift` (`oneLiner`, `bringBack`, `fadingOrdered`, `deletedOrdered`, lines 124-134, 168-189) and call `WayOut.*` at `WayOutColumn.swift:58,65`, `JournalView.swift:282`, `UnpipelinedMemoSheet.swift:307`, `SidebarView.swift:811`, `NoteProperties.swift:67`; move the matching `WayOutRulesTests` assertions (124-135, 208-235, 280) to `WayOut.*` (`WayOutSharedTests.swift:20-30` already covers three of them: delete the duplicates). Delete `DesktopTrashPolicy` (`Pipeline/DesktopTrash.swift:4-8`) and use `Shared/Model/Memo.swift` `TrashPolicy` at `DesktopTrash.swift:46`, `PipelineFile.swift:205-213`, `DesktopTrashTests.swift:63`. Add `ISO8601.lenientDate(from:)` (fractional seconds, else plain) with static formatters to `Shared/Model/ISO8601.swift`; delete `AudioMetadata.parse`, `IngestService.parseISODate` and `MetadataDate` (`PipelineFile+BodyNormalise.swift:136-143`); point `VideoIngestTests:34-39` at it; do not change `ISO8601.date(from:)` (names sync compares strings lexicographically). Move the async `AudioMetadata.recordingDate(of:)` into `Pipeline/` so `IngestService.ingestVideo` (already async, 400) can call it and delete the sync `embeddedRecordingDate` (this also removes the test comment re-implementation at `MergedNoteDateAndParagraphsTests.swift:78`). `IngestService.makeFolder` returns only the `URL` (all 5 callers discard the id), delete `let vault = picked` (`VaultExporter.swift:87-90`), inline `VaultName.stem` in `noteStem(_ pf:)` and delete the two-argument wrapper (`VaultExporterTests:266-269`), inline the three `Prompts.default*` aliases (`AppSettings.swift:121-131`), and compute the outcome once in `SplitSpeakers.settle` (`:31-43`). Q114 and Q178 edit `displayTitle`/`matchesSearch` in `WayOutRules`: keep your edit to the forwarders. Protected-test edits: hand-merge after Tuur's yes. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DPE-d15 DPE-d17 DPE-d18 SMU-d08 DPE-c10 DPE-c30 DPE-c28

### P26 [tuur] (todo) drop the write-only Mac diarization sidecar
spec: C182 C240
needs: -
gate+: yes
do: The Mac's `diar_<id>.json` sidecar (`Pipeline/BatchManager/DiarizationSidecar.swift`) is written at `BatchRunner.swift:175`, `UploadService.swift:195`, `MemoCloudIngest.swift:225` and deleted at `BatchRunner.swift:125` and `SplitSpeakers.swift:59`, but `load(in:id:)` is read only by tests; voice enrollment reads `pf.diarizationSegments`. Tuur decides, because `SPEC.md:1034` (C182, "re-transcribe also clears diarization + its sidecar") names it: amend that clause in the same change. If yes: delete the struct, its 3 writes and 2 deletes, the `sidecar:` parameter of `adoptLateDiarization`, and the wrong comment at `MemoCloudIngest.swift:207-208`; retarget the sidecar tests (`UploadTests.swift:58`, `DiarizationTests.swift:435-460`) to `pf.diarizationSegments`; `DiarizationData.slotNames` and `turnSlots` then go unread on the Mac, so shrink it to a segments-only decode of the phone blob (the phone's blob arrives as a `MemoAsset`, not this file). Also fold the repeated empty-path guard (`PipelineFile.workingFolder` is the existing helper; `BatchRunner.swift:124,174`) and keep the field lists of retranscribe and flatten separate (retranscribe also clears `titleSuggested`, flatten resets statuses and keeps the title). Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DPE-d09 DPE-c03

### P27 [auto] (todo) Mac ingest: one typed path instead of fake multipart parts
spec: C238 C240
needs: P20
gate+: yes
do: The only production ingest path is `MemoCloudIngest.swift:48` calling `upload.ingest(parts:)`; `buildParts` (122-171) re-encodes a Memo into fake multipart parts and `UploadService.prepare` (66-345) parses them back, reading keys the same file just wrote in `metadataJSON`. The Bonjour/HTTP server this mirrored is retired (`MultipartPart.swift:3-5`; header comments `UploadService.swift:9-14`). First port the tests that feed parts: `UploadTests.swift` (12 `ingest` calls with no `memoID`, lines 26-289) and `MemoCloudIngestTests.swift:59,170` to build a `Memo` and `MemoAsset`. Then replace `buildParts` and `prepare` with one typed `UploadService.prepare(memo:assets:)` that reads memo fields directly and decides audio, text or capture once (retiring `isTextOnly` and `isTranscriptTrusted`, which must stay exact complements today), make `memoID` non-optional (drop the random-id branches at `UploadService.swift:53-55,88,117`), keep `metadataJSON(for:)` only to fill `pf.audioMetadataJSON`, and delete `MultipartPart` and `contentType`. Also delete the video branch in `prepareAudio` (138-149) and `IngestService.extractAudioSync` (498-525): its only caller; the phone converts video before sync (`MemoSaver.swift:373`) and the async `extractAudio` stays for `ingestVideo`. Keep exactly: the textOnly rule (no audio ASSET and empty `audioFilename`), the capture-payload-does-not-parse fallback, the trust gate. This touches the trust path: the corpus tests (`MemoCloudIngestTests`, `RoundTripParityTests`, `MemoCloudReconcilerTests`) must stay green. Protected-test edits: hand-merge after Tuur's yes. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DPE-d12 DPE-d13 DPE-d14

### Mac app UI (DAU)

### P28 [auto] (todo) Mac sidebar and app: unused pill and helpers, wrong comments
spec: C240
needs: P18
gate+: no
do: In `SkriftDesktop/`: delete `StatusPill`, `PulseDot`, `QueueStatus.color` and `QueueStatus.tint` (`Features/Sidebar/SidebarView.swift:1345-1373`, `QueueDerivations.swift:20-34`; keep `label` and `pulses`, `QueueRowView.cardModel` uses them); `View.sidebarRowSelection` (`SidebarView.swift:1326-1343`); `queuedCount` (48); `SkriftFormat.shortDate` and `shortDF` (`QueueDerivations.swift:136-147`); the `asRecording` parameter of `ingest`/`runIngest` and the unreachable tail at `SidebarView.swift:203-232` (pass `asRecording: false` to `ArrivalPath.run`; `ArrivalPath.run` keeps the parameter, `LiveRecordingSession` and `RunFile:729` pass true); `actionButton(filled:)` (486, call at 302); `showDateStrip`'s launch-argument seed (76); `JournalView.coordinator` (16) and the argument at `RootView.swift:46`, `Snapshot.swift:969,979`; `UnpipelinedMemoSheet.backlinked`/`effectiveBacklinked` (keep `derivedBacklinked`, fill it in `load()`); `RecordingDraftBody.everEdited` (19, 56) with `Snapshot.swift:531,535`, the orphan doc at `RecordingDraftView.swift:189` and the `LiveRecordingSession.everEdited` proxy (63; keep `LiveRecordingDraft.everEdited`); `PersonEditor.request` stored property (19, 39); the unused `import FluidAudio` (`SkriftDesktopApp.swift:4`); `NamesCloudSync.run`'s unread `Bool`, `MacCloudEditSync.debounce` as `let` and `flush` private (leave the phone twin's shape). Fix false comments and strings: `WayOutColumn.swift:239-241`, `SidebarView.swift:14,611-616,972-976` and the empty-state "click + Upload above" at 906 (the button reads Import; use `SharedCopy.importVerb`), `MemoCloudContainer.swift:14-20,33-36` (Bonjour/HTTP fallback is retired; "opt-in" is wrong, `cloudKitMacSyncEnabled` defaults ON), `SkriftDesktopApp.swift:6-7,83-84`, `RootView.swift:26-29,211-213` ("day-change + 24h", the scheduler runs on launch and activation), `LiveRecordingSession.swift:12-14`, `Snapshot.swift:495-511`, `RecordingDraftView.swift:42-44` (LIVE-ENGINE is built), `Theme.swift:9-14`, `RunFile.swift:926-927`, and in `IngestService.swift:351-355,587-591,615`, `MemoNoteProjection.swift:22-27`, `MacRecorder.swift:27-30`, `MemoCloudReconciler.swift:7-14`, `MemoCloudIngest.swift:4-20,97,103`, `UploadService.swift:9-14,46-59` (shorten the Q5 essay), `AppSettings.swift:39-47,94-106`, `MemoCloudUpdate.swift:27-37` (`isFreshRow` doc sits between the attribute and the function). Keep rationale comments that record why a behaviour exists (`SidebarView.swift:226,430,442`, `LifecycleSweepScheduler` removed-trigger note, the `RootView` minWidth note). Never run SkriftDesktopUITests; Mac proof = unit tests + full build + headless `-snapshot-shell`.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DAU-d01 DAU-d02 DAU-d03 DAU-d04 DAU-d05 DAU-d06 DAU-d07 DAU-d08 DAU-d09 DAU-d10 DAU-d16 DAU-d17 DAU-d18 DAU-d-m1 DAU-d-m2 DSH-d15 DPE-d16 DPE-c12

### P29 [tuur] (todo) delete the 2026-07-27 sync trace
spec: C240
needs: -
gate+: no
do: `syncTrace` and `eventTypeName` in `SkriftDesktop/App/MemoCloudReconciler+Wiring.swift:45,53,57,87,113-115,189-216` are a DEBUG diagnostic that says "delete once the cause is known"; commit `cd086137` says the trace cleared the transport and the real fix was the `.cloudMemosDidChangeFromSync` post at line 122. Tuur confirms the "memo only appears after relaunch" bug is gone on his Mac. Then delete `syncTrace`, `eventTypeName`, the five call sites, the `visible` `fetchCount` (a fetch on every Release reconcile that only feeds the trace), the DEBUG `synctrace` log block in `MemoCloudUpdate.swift:130-134` and the `why: [String]` array with its appends (`MemoCloudUpdate.swift:73,77-79,96,102,111,123,128`). No script, SPEC or BUGS entry uses the `synctrace` category. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DAU-d14 DPE-d19 PER-d14

### P30 [auto] (todo) two display bugs: the 125:00 duration and a place name containing a plus
spec: C115 C240
needs: Q182
gate+: yes
do: (1) `SkriftDesktop/Features/Journal/JournalView.swift:584-587` formats a note's duration with `Duration.seconds(...).formatted(.time(pattern: .minuteSecond))`, which prints `125:00` for a 2 h 05 note; every other Mac site uses `SkriftFormat.duration(seconds:)`, whose doc (`ReviewHelpers.swift:41-45`) says it was unified for exactly this. Use it. The phone's `WayOutView.swift:384` has the same bug: use the phone's equivalent (Q121 is introducing `DurationFormat`; if it has landed use that). Write a test that a 7500 s duration does not render `125:00`. (2) A merged `PlaceCluster` keeps its member count and base name inside its `id` and `name` and recovers them with `split("+")` at six sites (`Shared/Pipeline/PlaceCluster.swift:58-85`, `JournalView.swift:441,469`, `RailMiniMap.swift:95`, phone `JournalMapView.swift:102,113`), so a place called "C+ Cafe" gives a wrong count and title. Add `memberIDs: [String]` and `mergedCount` (default 1; `PlaceClusterTests:9` and `WallPrinterTests:12` construct it with named args and keep compiling) and replace the splits with membership tests. The merged label stays `base +<count before the merge>`, i.e. new total minus 1. Q182 rewrites the calendar grid and Then-vs-Now, not this. Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh WallPrinterTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DAU-c27 DAU-c20 SPL-c24 MLJ-c08

### P55 [auto] (todo) Mac cloud adapters: one sync gate, one logger, one batch write helper
spec: C239
needs: P29
gate+: yes
do: Eight App adapters hand-write `cloudKitMacSyncEnabled && MemoCloudStore.container` (`MacCloudDeleteSync.swift:24-26`, `MacCloudMetaSync.swift:26-28,41-43`, `MacCloudEditSync.swift:37`, `VocabularyCloudSync.swift:16`, `PolishPromptsCloudSync.swift:15`, `NamesCloudSync.swift:32-37`, `MemoCloudReconciler+Wiring.swift:86`) and five more sit outside App/ (`ProcessingCoordinator.swift:344,471`, `LifecycleSweepScheduler.swift:86`, `NoteActions.swift:66`, `NoteDisplayView.swift:110`), each loading settings.json afresh. Add `MemoCloudStore.syncContainer` (nil when sync is off or there is no container) and `enum AppLog { static let cloudkit }` for the 16 inline `Logger(subsystem: "com.skrift.desktop", category: "cloudkit")` constructions (also the second Logger in `ConnectionsIndexService.swift:51-53`, use its existing `logger`). `MacCloudMetaSync` already has a single-file `write` helper; add a batch variant that saves once per batch (not per file) and use it from `MacCloudMetaSync.mirror` and `MacCloudDeleteSync.mirror` (the `trashSeenAt` stamp stays in the closure). In `VocabularyCloudSync.run` keep the ordering (destinations re-fetch after the vocab insert) and collapse the four `SettingsStore.shared.save` calls into one dirty flag and one save, with one prewarm call. Do not merge the adapters into one runner. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DAU-c06 DAU-c07 DAU-c08

### Recording and capture (MRC)

### P31 [auto] (todo) phone recording and quick note: unread state, forwarders, doc fixes
spec: C240
needs: Q173
gate+: no
do: In `SkriftMobile/`: delete `RecordingActivityManager.isRunning` (`Services/Recording/RecordingActivityManager.swift:69`); `PhotoCaptureService.isReady` and both writes (`PhotoCaptureService.swift:16,46,68`); `LiveRecordingService.level` and its five writes, pass the local to `pushWaveform` (`LiveRecordingService.swift:28-29,448,634,1019-1022,1671-1673`); `QuickNoteView.draftID` (`QuickNoteView.swift:20-23`, call sites `MemosListView.swift:217,372`; line 372 keeps `id` for `.id(id)`); `MemoSaver.importVideoAsync` (make `processVideo` internal and point `VideoImportTests` x4 at it; keep `saveAndTranscribe`, Tuur kept it in Q62; `persist` and `applyMetadata` are private); `RecordingSweepReport.kept` and its append (`RecordingRecovery.swift:10-21,84`; keep the struct Equatable, two tests compare it to empty); `NoteRoute.isDraft` (`NoteRoute.swift:24-27`; `QuickNoteRouteTests:40` pattern-matches instead) and the `Memo?` return of `QuickNoteDraft.edited` (7 test sites incl. `QuickNoteHeaderQ88Tests:14,25`); make `extractAudio` return `Void` and move the failure handling into the catch (`MemoSaver.swift:301-311,404-423`); drop the `duration:` parameter of `appendRecording*` (`MemoSaver.swift:526-546`, `RecordView.swift:568-569`, 9 test call sites: `QuoteCaptureSaveTests:94`, `MemoSaverTests` x7, `AutoCopyAndCameraFlipTests:115`); `RecordClock` forwarder (`RecordView.swift:597-600`; use `RecordingCore.elapsedLabel`); `LiveRecordingService.captionPollDelay` (call `LiveCaptionEngine.pollDelay` at 1589, retarget the 9 `LiveCaptionCadenceTests` assertions, do not delete them, the Mac suite only has 3 nominal cases); `MemoryWarningStep.allCases` instead of `memoryWarningOrder` (keep an order assertion for D131); `LiveRecordingService.name(_ reason:)` becomes `String(describing:)` (output unverified, log-only); one `waveformBars` constant for `Meter(width: 40)`, `waveformBars` and `RecordView.barCount`; the closed-investigation DevLog at `MemosListView.swift:317-319`; fix the doubled "rec rec quarantined" prefix (`RecordingRecovery.swift:79,103,209`: pass `quarantined`, `quarantine-failed`; no test matches the string). Comments: move the orphan `settleSession` doc (`LiveRecordingService.swift:210-218`) onto the function (261), fix `RecordingIntentBridge.swift:4-9,30` (RecordView only observes `stopRequestID`; start goes through `MemosListView.handleStartRequest` + `consumePendingStart`; the FAB is gone) and `MemosListView.swift:338-340` (`[NoteRoute]`). The hardware paths (route changes, tap install, session settle) are not touched. Re-grep every symbol by NAME first. Protected-test edits: hand-merge after Tuur's yes.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh RecoverySweepTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MRC-d02 MRC-d03 MRC-d04 MRC-d05 MRC-d06 MRC-d08 MRC-d09 MRC-d10 MRC-d11 MRC-d14 MRC-d15 MRC-d16 MRC-d19 MRC-d24 MRC-d25 MRC-d26 MRC-c20

### P32 [auto] (todo) one AVAudioFile duration, one buffer copy, one retrying transcribe
spec: C239
needs: P31
gate+: yes
do: (1) `Double(f.length) / f.fileFormat.sampleRate` is written 11 times (`MemoSaver.swift:91,174,195,328`, `RecordingRecovery.swift:147`, `LiveRecordingService.swift:571,688`, `CaptureInboxDrainer.swift:312`, `SharePayloadLoader.swift:214,276`, `IngestService.swift:156`, `AudiobookImporter.swift:351`) with the `sampleRate > 0` guard at only some. Add `extension AVAudioFile { var seconds: Double }` with the guard in `Shared/Recording/` (an extension on the open file fits every site; `LiveRecordingService.swift:571` is still open for writing, so a URL helper would not); check `SkriftShare`'s source list in `project.yml` before touching `SharePayloadLoader`. Do NOT merge `MacMemoAuthor.audioDuration` (uses `AVURLAsset.duration`, returns nil on failure). (2) The phone's private `copyBuffer` (`LiveRecordingService.swift:1551-1560`, call at 984) is identical to `LiveCaptionEngine.copyBuffer` (`Shared/Recording/LiveCaptionEngine.swift:422-431`) which `MacRecorder.swift:607` already uses: delete it and call the shared one. (3) The retry-transcribe loop is copied in `MemoSaver.swift:577-585` and `Services/Capture/CaptureDictation.swift:65-73` (delays `[0,2,5,15]` vs `[0,2,5]`): add `extension Transcribing { func transcribeRetrying(audioURL:imageManifest:delays:) async -> TranscriptionResult? }` next to the protocol in `Shared/Pipeline/TranscribingContract.swift` and keep both delay arrays at the callers (tests set them). No behaviour change; the recording tap and settle paths are not touched.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh MemoSaverTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MRC-d20 MRC-c02 MRC-c04 SRS-d09

### P33 [tuur] (todo) appending a recording: use AudioClipMerge, not the export session
spec: C240
needs: P32
gate+: no
do: `MemoSaver.appendAudio` (`SkriftMobile/Features/Recording/MemoSaver.swift:652-694`) still stitches with `AVMutableComposition` + `AVAssetExportSession`, the path `Shared/Pipeline/AudioClipMerge.swift` replaced after a phantom silent tail (header comment, and `MemoSaver.swift:211-217`). Replace it with: open the base with `AVAudioFile(forReading:)` first and let that throw (frames/rate is the splice offset), run `AudioClipMerge.merge([base, clip])` to a temp file in a detached task, then `replaceItemAt(base)`; delete the composition code and `AppendError`. The explicit base-open must stay a hard failure: `AudioClipMerge` `continue`s past an unreadable source and only throws `noAudio` if nothing was written, so an unreadable base would otherwise be silently replaced by the new clip alone and the original audio lost; the current code throws `noBaseTrack` and keeps the base. The base can be an imported `.mp3`. Tuur checks the append on the iPhone 17 Pro: record, append a clip, play both ends, check karaoke timing at the seam. `appendRecordingAsync` already tolerates a failed merge. Tests (`MemoSaverTests`, `QuoteCaptureSaveTests`) use placeholder audio and rely on falling back to the base; they stay green.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh MemoSaverTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MRC-c01 MRC-d17

### P34 [tuur] (todo) camera pinch zoom compounds, and a media-services reset brings the Bluetooth mic back
spec: C115
needs: -
gate+: no
do: Two hardware-flavoured defects found by reading; neither run on a device. (1) `CameraSheet.swift:91-98,144-150`: `setZoom` writes `zoomBase = zoom` on every call, while the pinch's `onChanged` passes `zoomBase * scale` with a cumulative scale, so each callback rebases the baseline and zoom compounds (base 1, scale 1.1 gives 1.1, then 1.1 x 1.2 = 1.32). The comment above the gesture says the baseline must be snapshotted at gesture start. Make `setZoom` write only `zoom`; set `zoomBase = zoom` in `.onEnded`, in the zoom-selector taps and in `flip()`. (2) `LiveRecordingService.handleMediaServicesReset` (`:1246`) sets a hard-coded `[.allowBluetooth, .defaultToSpeaker]` while the other two `setCategory` sites use `recordingCategoryOptions(avoidBluetoothMic:)`, bringing back the HFP mic path the b117 policy (2026-07-26) removed. Add `static func configureSession(_ s: AVAudioSession) throws` using `recordingCategoryOptions(avoidBluetoothMic: avoidBluetoothMicNow(s))` and call it from `settleSession`, `startEngine` (inside the `!warm` branch) and the reset handler. CLAUDE.md: hardware bugs are diagnosed from the devlog and belong to the orchestrator, not a lane; Tuur or the orchestrator tries both on the iPhone 17 Pro (pinch from 1x; trigger a media services reset with a Bluetooth headset connected) and marks them unverified until then.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh LiveRecordingRouteChangeTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MRC-c28 MRC-c11 MRC-d18

### List, journal, settings (MLJ)

### P35 [auto] (todo) phone list, journal and settings: unused chrome, filters, launch flags, comments
spec: C240
needs: Q173 Q110
gate+: no
do: In `SkriftMobile/`: delete `SelectableCard` (`Features/MemosList/NotesBottomChrome.swift:58-77`, plus its "iPad shell helpers" MARK; Q173 does not name it; if Q173 landed first, only this struct remains); `quietLine` from `MemoRow` and `MemoCard` and the `quietLine: nil` call with its comment (`MemosListView+Row.swift:18-90`, `MemosListView.swift:505-510`; keep the Shared `NoteCardModel.quietLine`, the Mac sets it at `SidebarView.swift:810`); build the `MemoCard` once in `MemoRow.body` (selected: `editing ? false : selected`) with an if/else between the bare card and the Button wrapper; `LaunchFlags.destinationsOn`, `seedPortfolioFolder`, `selectFirstMemo` and `Array.intValue` accessors (`App/LaunchArgs.swift:18,31-40`; the raw-argument reads at `Shared/Model/NoteDestination.swift:145` and `Services/Export/PortfolioVault.swift:54` stay, which should `guard LaunchFlags.seedPortfolioFolder`); `-openJournal` and `-openSettings` and their two lines in `AppTabView.initialTab()` (`-openTab` replaces them; update `FEATURES.md:396`); the closed-investigation diagnostics `MemosListView.swift:317-337` and `MemosListView+Derived.swift:135-140` (DEBUG only; keep them if Tuur wants more device rounds); `Identifiable` and `id` from `MemoSort` and `MemoDateField` (keep `MemoDateField`'s raw type, `MemosListView+Header.swift:248` uses it); `NamesDisplay` (call `person.displayName` and `PersonEditCore.isEnrolled(person)` directly, `NamesListView.swift:159-163`); `let pile = processPile` once in `processRow` (`+Header.swift:151-169`). Do NOT touch `MemoFilter.hasPhotosOnly/.place/.isActive` (Q110, gated on Tuur) or the `AddPersonView` and Names headers (Q113). Comments: `MemosListView.swift:49-52,99-103`, `+Header.swift:6-20,304-306` (the Filter moved out, Q66), `+Actions.swift:78-79,107-112`, `WayOutView.swift:7-8,243-244` (reached from Review, `JournalHomeView.swift:49`; `FadingShelfView` no longer exists), `JournalHomeView.swift:159-160`, `PersonDetailView.swift:4-8`. Leave the `-showTOCSheet`, `-showTextSheet`, `-showTextPrompt`, `-seedAudiobook`, `-seedDetectedChapters`, `-showFilterSheet`, `-seedJournal`, `-journalMemoDemo` rig alone (lane briefs keep them; Tuur's call). Re-grep every symbol by NAME first.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh MemoModelTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MLJ-d02 MLJ-d04 MLJ-d07 MLJ-d08 MLJ-d11 MLJ-d13 MLJ-d16 MLJ-c14 MLJ-c15 MLJ-c20 MSV-d17

### P36 [auto] (todo) feedback: a single-item mail composer, a store that only saves, no duplicate draft
spec: C240
needs: -
gate+: no
do: `FeedbackCaptureView` is the only consumer (`FeedbackCaptureView.swift:82-83,183`) of `FeedbackStore`, `FeedbackItem` and `FeedbackMailComposer`; nothing observes `items`, no Feedback list screen exists, and `FeedbackMailComposer.init(items:)` has no caller. Make the composer single-item (one item, `onSent: (FeedbackItem) -> Void`, fixed subject and zip name; update `sent.forEach` at `FeedbackCaptureView.swift:82-83`). Make `FeedbackStore` a plain struct or enum: delete `count`, `delete(_:)`, `items`/`@Published`/`ObservableObject`, `reload()`, both `load(from:)`, `makeDecoder`, and `FeedbackItem.screenshotURL`, `hasScreenshot`, `durationSeconds`; `save()` returns `FeedbackItem(folder:metadata:)`, `markSent` keeps working; use the built-in `.iso8601` date strategies (same internet-date-time format, existing files still decode). KEEP the on-disk `Documents/Feedback/<uuid>/metadata.json` layout and field names: `.claude/skills/pull-phone-feedback` reads those files over USB. `sendNow` (182-191) saves a second draft folder when the user taps again after the no-mail alert: keep a `@State savedItem` so a retry reuses the folder; reword the alert that says "send it from the Feedback list" (92), a screen that does not exist. `FeedbackRecorder` is also used by `VoiceEnrollView` (`PersonDetailView.swift:138`): leave it where it is, set `elapsed` from `audioRecorder?.currentTime` only if the change is trivial. Run the feedback flow once in the simulator with the pull-phone-feedback parse step on the result.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh MemoModelTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MLJ-d05 MLJ-d06 MLJ-c23 MLJ-c24

### P37 [auto] (todo) three phone state bugs: lost print card, stuck model spinner, re-stamped language
spec: C115
needs: Q173
gate+: no
do: Found by reading; each gets a failing test first where one can be written, otherwise log what you found. (1) `WallPrinter.tryDrain` (`SkriftMobile/Features/Journal/WallPrinter.swift:30-120`) snapshots the queue, awaits printing, then writes `remaining` back over the key, dropping any card `ratingCommitted` enqueued during the drain; queue and ledger are re-read from UserDefaults in five places and `queuedCount` is a hand-synced mirror. Hold queue and ledger as stored properties with `didSet` persistence, loaded once in `init`, derive `queuedCount`, fetch memos once into a dictionary in `tryDrain`. `WallPrinterTests`: enqueue during a drain survives. (2) `OnboardingView.modelRequested` is never reset (`Features/Onboarding/OnboardingView.swift:13-51,130-134`): after a failed download the row shows a spinner forever (`try?` swallows the error and `ModelLoadStatus.ready`/`downloadProgress` are false/nil after `.failed`); reset it after `ensureLoaded` as `ModelsView.downloadASR` does and show the failure. Q173 also edits this view (the permission step): rebase on it. (3) The language picker (`Features/Settings/SettingsView.swift:19,87-99`) writes the Bool through `@AppStorage` and then `.onChange` calls `ASRLanguageStore.save`, so when sync adopts a value while Settings is open the `.onChange` re-stamps it as now and overwrites the remote stamp. Keep `@AppStorage(ASRLanguageMode.settingKey)` (so sync still re-renders the picker) and put the save and `VocabularyCloudSync.run` in a `Binding` setter; delete the `.onChange`. Do NOT replace it with `Binding(get: ASRLanguageStore.mode())`.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh WallPrinterTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MLJ-c09 MLJ-c26 MLJ-c01

### P52 [auto] (todo) phone WayOut: call the Shared WayOut directly, one partition
spec: C239
needs: Q178
gate+: no
do: Delete the static forwarders `orderedByImminence`, `oneLiner` and `total` in `SkriftMobile/Features/MemosList/WayOutView.swift:279-312` (production callers 30, 32, 33, 201: use `WayOut.fadingOrdered`, `deletedOrdered`, `oneLiner`; keep `bringBack`, it adds `repository.save()`). `WayOutViewTests.swift:27-100` and `LockedNoteVisibilityTests.swift:75` use them: drop the cases that `WayOutSharedTests` already covers and retarget the rest. Add `MemoLifecycle.partition(_:backlinked:now:)` taking a precomputed backlink set, make the existing `partition` call it and replace `MemosListView.lifecycle(backlinked:)` (`MemosListView+Derived.swift:44-50`) with it, keeping the single backlink scan the comment at 42-43 protects (R92/C278). Q178 edits the one-liner and meta line in `WayOutView`: land after it. Protected-test edits: hand-merge after Tuur's yes.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh WayOutViewTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MLJ-d14 MLJ-d15

### Phone services (MSV)

### P38 [auto] (todo) phone services: unread members, unused overloads and test-only helpers
spec: C240
needs: P24
gate+: no
do: In `SkriftMobile/Services/` (re-grep each symbol by NAME in both apps and tests first): `PublishCoordinator.memosProvider` and the `live()` argument and test-helper parameter (`PublishCoordinator.swift:23,40`, `PublishCoordinatorTests.swift:24,33`; Q80 left it, nothing reads it); `NotesRepository.allAssets()` (unscoped blob fetch, 6 test calls in `MemoAssetTests`: use `repo.context.fetch(FetchDescriptor<MemoAsset>())` in a private test helper) and `NotesRepository.delete(_:)` (one caller, `MemoModelTests.swift:65`; use `repo.context.delete` + `repo.save()`), fix the stale docs (`permanentlyDelete` says MemoDetailView mirrors the cleanup, it calls `softDelete`; move the `hasAsset` doc down to line 190); `MemoDeduper.isContentClone` pass-through (`MemoDeduper.swift:43-46`); `CaptureInbox.imageURL(for:entryDir:)` (`CaptureInbox.swift:246-250`) and the never-passed `imageData:` parameter of `CaptureInbox.write` with its branch (156-176; keep the persisted `imageFileName` field and `imageURLs(for:)`; `SkriftShare` compiles this file too); `ObsidianVault.clear()` and `PortfolioVault.clear()`; the three phone `isModelReady` (`TranscriptionService.swift:43`, `SpeakerEmbedder.swift:40`, `DiarizationService.swift:27`); `ensureLoaded()` on the `SpeakerEmbedding` protocol and the `SeededEmbedder` stub (make the two real ones private); `TranscriptionService.finishStream()` and `LiveCaptionEngine.finish()` (keep `finishParts()`); `TranscriptionService.liveCaption()` (phone) with `LiveCaptionEngine.caption()` (the Mac `liveCaption()` is P24's; do the shared function after both are gone); `TranscriptionService.multilingualKey` (update the comment at `SettingsView.swift:16`); the `useANE` defaults read (`TranscriptionService.swift:66-67`: set `.cpuAndNeuralEngine`); `TranscriptionService.shouldRotate` and `LiveCaptionEngine.shouldRotate` (point `LiveCaptionCadenceTests:47-63` and `LiveCaptionSettleTests:54-56` at `rotationTrigger(...) != nil`); `WeatherClient.setAPIKey` and `testSetAPIKeyRoundTrip` (keep the legacy-key fallback, Tuur's call). Fix stale mentions: `ShareViewController.swift:15` (`complete(entry:imageData:)`), `SkriftDesktop/Engines/TranscriptionService.swift:191-194` (the Mac has no `finishStream`), `MemoExporter.swift:7-9` (the phone has an author setting). `PolishCenter.swift:300-302` keeps its dated verdict note. Protected-test edits: hand-merge after Tuur's yes.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh PublishCoordinatorTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MSV-d01 MSV-d04 MSV-d05 MSV-d06 MSV-d07 MSV-d08 MSV-d09 MSV-d10 MSV-d11 MSV-d12 MSV-d13 MSV-d14 MSV-d15 MSV-d18 MSV-d20 MSV-d-m1 MSV-c29 SRS-d06 SRS-d08

### P39 [tuur] (todo) the phone export gate has one rule and no paired mode
spec: C240 C65
needs: Q156
gate+: no
do: `PublishCoordinator.live()` hard-codes `isMacPaired: { false }` and `policy: { .importantOnly }`; `skrift.publish.whenPaired` is read (`PublishCoordinator.swift:48`) and written nowhere; `Policy.all` is built only in tests. `plan/extraction/code-core.md:260` holds it as "needs-verdict, delete in v2?" and `plan/reads/parity-audit.md` setexp-74 calls the paired refusal unreachable: Tuur gives the verdict. If delete: remove `Policy`, `isMacPaired`, `publishWhenPaired`, `policy`, the four guard lines and the pairing doc paragraph; make the rated check unconditional via `NoteConsent.isRated`; define `shouldPublish(_:) = exportRefusal(_:) == nil` and delete the duplicated guard list (60-86 vs 94-113: they carry the same 8 guards in the same order; keep the 74-85 comment about `isProcessed`, next to the matching refusal) so `MemoDetailView.swift:769-790`'s `case nil` arm is the only path; delete the paired and `.all` cases in `PublishCoordinatorTests` and rewrite `UnratedConsentTests.testLivePublishPolicyIsRatedOnlyRegardlessOfStoredSetting` (it asserts `coordinator.policy()`) to store the old "all" key and assert an unrated memo still fails `shouldPublish`. Q156 unifies the phone gate with the Mac gate: land after it. Protected-test edits: hand-merge.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh PublishCoordinatorTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MSV-d02 MSV-d03

### P40 [auto] (todo) the lock flow asks the right ledger whether a note was exported
spec: C115
needs: P38
gate+: no
do: `ObsidianVault.hasPublished(_ memoID:)` (`SkriftMobile/Services/Export/ObsidianPublisher.swift:35-38`) keys the ledger on the picked root (`ExportLedger.default(for: vault)`) while the writer and `PublishCoordinator.hasPublished` (`PublishCoordinator.swift:126-138`) key it on the vault home (`VaultLayout.home(forPicked:profile:)`, `<pick>/Skrift` unless the pick is already named Skrift or already holds Skrift notes, `VaultLayout.swift:50-66`) and on the note's destination. So the lock-flow notice at `MemoDetailView.swift:731` and `MemosListView+Actions.swift:126` can say "not in your vault" for a note that was exported. Write a failing test that exports a memo into a picked folder named something other than Skrift and then asks the lock flow's check, then delete `ObsidianVault.hasPublished` and have both callers use `PublishCoordinator.hasPublished(memo)`. Found by reading, not run on a device; if the test passes today, log why and still remove the duplicate predicate.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh PublishCoordinatorTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MSV-m1

### P41 [auto] (todo) share extension: drop the share-side dictation that was retired on 2026-07-10
spec: C240
needs: Q132
gate+: no
do: Share-sheet dictation is gone (`SkriftMobile/project.yml:448-450`; iOS blocks recording in an extension), yet `SkriftShare/ShareSheetView.swift:779` hard-codes `let dictationData: Data? = nil` and that nil still flows through `onSave`'s third parameter (line 20), `ShareViewController.complete(...dictationData:)` and its retry closure (`ShareViewController.swift:92-94,158,170,184-185`), and into `CaptureInbox.write(dictationData:)` (`CaptureInbox.swift:164,183-186`); `ShareSheetView.swift:828` (`dictationFileName` ternary) is always nil. Remove the parameter end to end, the `dictationFileName` expression, and the unused `imageData:` branch if P38 has not (check first). Delete `testDictationRecordingInSheet` in `SkriftMobileUITests/ShareFlowProbeUITests.swift` (it taps `capture-dictation-record` and `capture-dictation-chip`, which no source file defines; the probe is opt-in behind `RUN_SHARE_PROBE`). KEEP everything the drain side reads for pending legacy inbox entries: `CaptureInboxEntry.dictationFileName`, `dictationURL`, the drainer's `hasDictation` branch, `CaptureDictation` and `CaptureInbox.write(dictationData:)` (the last is used by `CaptureDictationTests.swift:114`), P42 is the separate decision on those. Q132 and Q150 reshape the audio choice in this sheet: rebase on them. Both extension and app targets compile these files, so edit both together. Protected-test edit: hand-merge after Tuur's yes.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh AudioShareDrainTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAM-d14 PER-d05

### P42 [tuur] (todo) delete the drain-side half of the retired share dictation
spec: C240
needs: P41
gate+: no
do: `Services/Capture/CaptureDictation.swift` (120 lines), `CaptureDictationTests.swift` (174), `CaptureInboxDrainer.swift:169,566-598,651-653` (the `hasDictation` block and the `resumePending` call that runs on every drain), `CaptureInboxEntry.dictationFileName`/`dictationURL` (`CaptureInbox.swift:39,252-256`) exist only for inbox entries written by a build before 63; the only producer is gone after P41. `CaptureInboxEntry` is a transient inbox JSON, not SwiftData or CloudKit, but an old pending entry that no longer decodes is skipped and never deleted. Tuur confirms no device holds a pre-build-63 pending entry (or accepts losing one). Then delete those, reword `MemoSaver.swift:828` and `MemoSaverTests.swift:268,301` (`testRecoverSkipsCaptureDictationsAndBookCaptures` case (a) names `CaptureDictation.resumePending`; keep the empty-`audioFilename` carve-out for audiobook captures). KEEP `CaptureVoiceAnnotate`: it is the live in-app dictation path and does not use `CaptureDictation`.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh MemoSaverTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md PER-d06

### P56 [auto] (todo) polish: one prompt descriptor, one title/summary turn, no redundant canPolish clause
spec: C239
needs: Q187
gate+: no
do: `PolishPromptsStore.swift` has three parallel switches over `PolishPromptKind` (`isEdited`, `key(for:)`, `fallbackText(for:)`, lines 38-44, 88-103) plus 3 key constants, 3 accessors and 3 `store(...)` lines in `adoptSynced`; `PolishSettingsView.PromptEditorView.defaultText` and `currentText` (191-205) add two more. Expose `PolishPromptKind.defaultText` (the store's `fallbackText`) and `PolishPromptsStore.text(for:)`; `isEdited` is `text(for:) != kind.defaultText`; `setText`, `adoptSynced`, `blob` loop over `allCases` with one private descriptor (key, fallback). Do not touch the `promptsTick` mechanism. `MLXPolishEngine.swift:129-158` spells the title turn (budget 64) and summary turn (256) in both `redo` and `polish`: add `titleTurn(plain:)` and `summaryTurn(plain:)` with named budgets (take `plain` as a parameter, `polish` computes it once). `PolishCenter.canPolish` has `|| busyMemoID == memo.id`, redundant because `!isWorking(memo.id)` follows (both are set together in `run` and `runRedo`): drop it. Q187 reorders the polish prompt rows on iPad and Mac: land after it or rebase. `PolishPromptsSyncTests` and `IPadPolishTests` stay green unedited.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh PolishPromptsSyncTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MLJ-c27 MSV-c14 MSV-c15 MSV-c16

### P57 [auto] (todo) export services: one scoped-folder bookmark, one destination root, one outcome mapping
spec: C239
needs: P38 Q154
gate+: no
do: `ObsidianVault` and `PortfolioVault` (`SkriftMobile/Services/Export/ObsidianPublisher.swift:6-41`, `PortfolioVault.swift:16-48`) are the same security-scoped-bookmark store with a different defaults key (set, resolve, `isConfigured`, `displayName`, clear): add one `ScopedFolderBookmark(key:)` value type; the two enums keep their own extras (`PortfolioVault.folder(for:)`, `seedIfRequested`) and forward to it. The "portfolio destination uses the portfolio folder, otherwise the vault root" derivation with its scope start/stop is written in `ObsidianPublisher.publish` (136-143) and `PublishCoordinator.hasPublished` (129-135): one helper returning picked root, scope root and profile. Do NOT fold the gate sites (63, 95-100): they call the injected `portfolioConfigured()`/`obsidianEnabled()` closures. `ObsidianPublisher.publish` maps `VaultWriteOutcome` to `PublishOutcome` twice (160-165, 217-223): one `PublishOutcome.init(_:relativePath:)` and a `stem(ofRelativePath:)` helper. Q154 replaces the photo-marker converter in the same file; keep your edit away from `convertPhotoMarkers`. `ObsidianPublisherTests`, `PortfolioExportTests`, `PublishCoordinatorTests` stay green unedited.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh ObsidianPublisherTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MSV-c08 MSV-c09 MSV-c10

### App, models and extensions (MAM)

### P43 [auto] (todo) phone app: dead launch hook, status enums, unused tokens, seeders out of Release
spec: C240
needs: P35 P46
gate+: no
do: In `SkriftMobile/` (re-grep each symbol by NAME in both apps and tests first): delete the DEBUG one-shot P0 restore hook `LaunchFlags.restoreEnhancement` and the `#if DEBUG` block in `SkriftApp.init` (`App/LaunchArgs.swift:139-151`, `App/SkriftApp.swift:43-61`; the restore was aborted, nothing launches it, it rewrites a CloudKit-synced `MemoEnhancement` from base64 arguments); the chain `Memo.trashCountdownLabel` to `Memo.trashDaysRemaining` to `MemoLifecycle.goneAt` (`Models/MemoDisplay.swift:57-76`, `Shared/Pipeline/MemoLifecycle.swift:125-131`), reached only by tests (the shipped countdown uses MemoSpine's `.deleted(goneAt:)`), with `TrashTests.swift:192-217` and the `goneAt` assertions in both `MemoLifecycleTests`; keep the Mac `PipelineFile.trashDaysRemaining` (`WayOutColumn.swift:188`) and the enum case label `goneAt`; `MemoStatusKind.synced/.waiting` (`MemoDisplay.swift:329-340`, `MemosListView+Row.swift:96-101`; `MemoModelTests:96-111` assert nil for those states and stay valid; leave `SyncStatus` alone) and `PillStyle.synced/.waiting` (`DesignSystem/Components.swift:55-78`; only `.working` and `.error` are built, `MemoPageView.swift:574,626`); `TagChipStyle`, `Theme.Space.sm/md/lg`, `Theme.Radius.chip/sheet/group`, `SectionLabel.trailing` (`Components.swift:3-5,31-50,151-173`, `Theme.swift:87-101`; `Theme.swift` also compiles into `SkriftShare`, checked); `SharedImageItem.mimeType` (`SkriftShare/SharePayloadLoader.swift:27,404`); `Memo.rambleSnippet` (`Models/MemoDisplay.swift:201-215`, used only by `BookCaptureDisplayTests:76,83,88`) unless Tuur wants it wired into the capture row; the private `symbolEffectPulseFallback()` wrapper (`Components.swift:109-115`); tombstone comments (`ShareViewController.swift:216-219`, `MemoDisplay.swift:325-347`, `SkriftLiveActivity.swift:17-19`, `project.yml:308,335-336` "8a/8b", unused `import UniformTypeIdentifiers` at `ShareViewController.swift:3`, `SharePayloadLoader.swift:76-77`). Seeders: `DemoDataSeeder.seedIfRequested` starts with `guard repo.allMemos().isEmpty`, a sorted fetch of every live memo before any flag is checked, so every production launch fetches and discards the list (`plan/perf-sweep.md:24`). Wrap `DemoDataSeeder`, `NamesSeeder`, `AudiobookSeeder`, `DestinationSettings.resetIfRequested` and `PortfolioVault.seedIfRequested` and their call sites (`SkriftApp.swift:17-23`, `AppTabView.swift:90-93`) in `#if DEBUG` like `CorpusSeed`. Keep `LaunchFlags.inMemoryStore`, `skipOnboarding`, `seedTranscript`, `fakePolish*` readable in Release (production code reads them: `SkriftApp.swift:164-185,314-316`, `NotesRepository.swift:8`, `TranscriptionService.swift:323`, `PolishBootstrap.swift:21`). The test scheme builds Debug, so the UI tests keep working; confirm with a full phone test run of one UI-adjacent class. Protected-test deletions: hand-merge after Tuur's yes.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh TrashTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAM-d03 MAM-d04 MAM-d07 MAM-d08 MAM-d09 MAM-d15 MAM-d20 MAM-d22 MAM-d-m1 MAM-c24 MAM-c25

### P44 [auto] (todo) one quick-action widget, and the share extension stops compiling files it does not use
spec: C239
needs: -
gate+: no
do: `SkriftWidget/RecordWidget.swift` and `NewNoteWidget.swift` differ only in names, display text, SF Symbol, URL and kind (`diff` shows nothing else); add one parameterised quick-action view and provider (kind, url, symbol, title, caption) and keep the two `Widget` structs as thin wrappers so the bundle kinds `com.skrift.mobile.recordwidget` and `.newnotewidget` are unchanged (installed widgets reference them; `SkriftWidgetBundle.swift:12,14`; D135 requires separate widgets). Compile `Shared/UI/Palette.swift` (Foundation-only) into `SkriftWidget` and read the dark values (accent `7c6bf5`, red, amber, bg `0f1117`) from it with one `Color(hex:)` helper instead of the inlined copies in the two widgets and `SkriftLiveActivity.swift:7-15`. In `SkriftMobile/project.yml:412-432` drop `DesignSystem/Components.swift` from the `SkriftShare` sources (nothing there uses its symbols) and, after moving the `extension TagRowStyle { static let phone }` at the end of `DesignSystem/Theme.swift:119-128` into an app-only file, drop `FlowLayout.swift`, `TagRules.swift` and `TagEditorRow.swift` too. Regenerate. This is a compile-list change: build the extension with the phone scheme (`xcodebuild -scheme SkriftMobile`, which builds the extensions) and report the result; widgets and the share sheet are unverified on a device until Tuur looks (add a widget to the Home Screen and open the share sheet from Safari).
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh SharedContentParityTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAM-d17 MAM-d19 MAM-c10

### P45 [tuur] (todo) remove the SkriftShared framework target
spec: C240
needs: P44
gate+: no
do: A framework target exists only to share one 41-line `ActivityAttributes` file (`SkriftShared/RecordingActivityAttributes.swift`; `SkriftMobile/project.yml:301-333,390,542`, and the 64-70 comment records the version drift it already caused). Compile the file into the app and the widget by multi-target membership, the way the intents already are; drop `public` modifiers and `import SkriftShared`; drop the never-read `sessionId` and the static attributes-level `startedAt` (the widget reads `context.state.*`; `RecordingActivityManager.reapOrphans` limits any in-flight activity). Tuur decides because ActivityKit encodes these attributes and the Live Activity cannot be proven by a unit test: after the build he starts a recording on the iPhone 17 Pro and checks the Lock Screen and Dynamic Island, and ends it.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh RecordingActivityCaptionTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAM-c12 MAM-d18

### P58 [auto] (todo) share sheet: one card chrome, a split saveTapped, one theme
spec: C239
needs: P41 Q132
gate+: no
do: `SkriftShare/ShareSheetView.swift` draws its card chrome (skSurface fill plus a 0.5 pt white 0.09 hairline, radius 13) in six places (216-310, 315-357, 479-522, 531-574, 576-626): add a private `shareCardChrome(radius:)` and call `honestyLine` from `audioCard` (510-518 inlines it). The cards are not identical (video tile 46x34, url card has no honesty line), so only the chrome is shared. `saveTapped()` (716-842, 127 lines) splits into `audioEntries()`, `videoEntry()`, `fileEntry()`, `mediaEntry()`; add a `trimmedThought` property (trim and empty-to-nil three times), `if let fileURL` instead of the `payload.fileURL!` at 800, one helper for the four index-aligned image arrays, reuse the local `iso` helper at 744 and 835. `ShareTheme` for the `#0e0f16` backdrop (`ShareViewController.swift:29,34,119`, `ShareSheetView.swift:50`, `ShareFeedbackView.swift:24`), the `#1b1d28` surface and the `10_000` constant, with one `shareSheetSurface()` modifier for the sheet block repeated at `ShareSheetView.swift:90-103` and `ShareFeedbackView.swift:48-59`. Q132 and Q150 change the audio chooser and P41 removes `dictationData`: rebase on them. Verify the sheet with the existing probe or by rendering it before and after; extension UI is unverified on a device until Tuur opens the share sheet.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh AudioShareDrainTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAM-c02 MAM-c04 MAM-c08

### Shared model, UI and body (SMU)

### P46 [auto] (todo) shared model: unused helpers, one marker vocabulary, false comments
spec: C240 C239
needs: P10 Q154
gate+: no
do: In `Shared/` (compiled into both apps; re-grep each symbol by NAME in both apps and tests first): delete `ThreeBallScale.toggling` and `syncCopy` (`Model/ThreeBallScale.swift:50-57,72-76`) with their cases in `SkriftDesktopTests/ThreeBallScaleTests.swift:76-116` and `SkriftMobileTests/SignificanceCirclesTests.swift:43-80` (keep `names`/`stops`, they are asserted); `Memo.splitTagInput` (`Model/Memo.swift:291-314`, 24 lines with the long essay) and the three tests at `NoteDestinationTests.swift:104-118` (keep `NoteDestination.reserved`, `Compiler.swift:128` uses it), fix the `TagRules.swift:6-7` header and `BUGS.md:377`; `TagRules.Fold`, `folds` and `keptSpelling` (`UI/TagRules.swift:47-80`; `fold` returns the tags to add; the four fold tests in `SkriftDesktopTests/TagRulesTests.swift:51-88` assert the returned array only); `BodyNormaliseMigration.remap(_:from:to:)` (`BodyV2/BodyNormaliseMigration.swift:147-150`); `BodyV2Legacy.isUnnormalised` pass-through (`BodyV2Legacy.swift:18-20`); the private `reflowMarkerLiteral` (use `BodyV2Marker.literal`); the no-op `.interactiveDismissDisabled(false)` at `UI/EditConflictViews.swift:265` and one `choiceButtons` for the three pills in `phoneBody` and `macBody` (the Mac passes `.keyboardShortcut(.defaultAction)` on the first); the `limit:` parameter of `NoteTitle.clip` (never passed, 9 callers; the open NoteTitleLadder item touches this file, coordinate). Marker vocabulary: route the hand-formatted `[[img_%03d]]` sites through `BodyV2Marker.literal/block`: `Pipeline/ImageMarkers.swift:52` (gone after P10), `ImageMarkerReinsert.swift:12,115`, `MixedBundle.swift:98`, `BodyV2Legacy.swift:90`, `SkriftMobile/Features/MemoDetail/NoteBodyView.swift:1236`, `SkriftDesktop/Features/Review/BodyTextView.swift:1170`, `SkriftMobile/Services/Capture/CaptureInboxDrainer.swift:622`; C14/C15 say readers accept `\d+` and no `\d{3}`-only matcher remains: `ImageMarkerReinsert.swift:12` is `\d{3}`-only, fix it in the same change. Leave `convertPhotoMarkers` in the exporters to Q154. `Paragrapher.endsSentence` forwards to `BodyV2Text.endsSentence(Substring(word))` and the closer set is defined once. `isC203Legacy` takes a `SharedContent?` (`BodyNormaliseMigration.swift:55-70`; callers `Memo+BodyNormalise.swift:28`, `PipelineFile+BodyNormalise.swift:52`; rewrite the dict-based asserts at `BodyNormaliseMigrationTests.swift:185-193`). `BodyV2Text.normalised` computes the collapse once per line and hoists the two regexes (`BodyV2Text.swift:17-103`). `EditConflict.swift:108-129`: one private `digest(_:)` for the SHA256-prefix expression. Fix false comments: `BodyV2.swift:5-6` ("nothing calls it": 15+ callers), `Memo.swift:36-41` (`SharedContent` lives in `Shared/Model/SharedContent.swift`), `Memo.swift:91-95` (rating gates processing, CloudKit mirrors everything, `ThreeBallScale.swift:6-8`). Protected-test edits: hand-merge after Tuur's yes.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh NoteDestinationTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SMU-d04 SMU-d05 SMU-d06 SMU-d07 SMU-d09 SMU-d11 SMU-d-m1 SMU-c03 SMU-c04 SMU-c06 SMU-c07 SMU-c11 SMU-c14 SPL-c15

### Shared rest (SRS)

### P47 [auto] (todo) shared naming, export and corpus: unread members and unused overloads
spec: C240
needs: P38
gate+: no
do: In `Shared/` (re-grep each symbol by NAME first, both apps and all tests): delete `Sanitiser.hasCanonicalLink` (`Naming/NameUnlinking.swift:49-58`; fix `FEATURES.md:347` and `plan/extraction/decisions.md:366`); `Sanitiser.unlinkOccurrence` and `relinkOccurrence` (`NameUnlinking.swift:61-67,82-90`) with their tests (`SkriftDesktopTests/UnlinkTests.swift:38-70,173-186`, `DiarizationTests.swift:363`: re-point `testLinkOccurrencesAndUnlinkArePipeAware` at `unlinkAll` to keep the pipe-aware coverage), fix the doc at `NameUnlinking.swift:30` and `FEATURES.md:348`; keep `unlinkAll`, `linkDisplay`, `linkOccurrences`, `linkTarget` (the Mac popover at `BodyTextView.swift:1085-1100` builds from `namePicks`/`neverLink`); the three `static let ... = true` flags `wholeWord`, `avoidInside`, `preservePossessive` and their false branches (`Naming/Sanitiser.swift:37-39,209-282`; inline the true branches, drop the flags from the regex cache key); `Overrides.prunedKeys` (51, 65); `LiveCaptionEngine.caption()` (`Recording/LiveCaptionEngine.swift:178-183`, after P24 and P38 removed both `liveCaption()` forwarders); `CorpusSeed.Note.expect`/`Expect` (`Corpus/CorpusSeed.swift:68-84`; keep `Manifest.count`, `CorpusSeedTests:42,43,48` reads it; `generate.py` keeps writing the key, `Decodable` ignores it); the `renamedFrom` half of `PersonEditCore.materialise` (`Naming/PersonEditCore.swift:44-64`, assertions in both `PersonEditCoreTests`); `ExportLedger.Entry.exportedAt` (`Export/VaultWrite.swift:38,361`; the ledger is a local JSON file, old files with the extra key still decode); the `VaultWriter` `var` folders and `now` that no construction overrides (`VaultWrite.swift:212-221`); `Assessment.proceed(creates:)` becomes `proceed(relativePath:)` and `Standing.absent` with `standing(of: String?)` (non-optional) goes (`VaultWrite.swift:225-297`, `VaultStamp.swift:57-99`; update `VaultWriteTests:157`, `VaultStampTests:58`); `VaultLayout.swift:59-65` `if fileExists(nested) { return nested }` followed by `return nested`, merge the two `home(forPicked:)` overloads (profile defaults to `.obsidian`), add `VaultStamp.head(of:)` for the 2048-byte read written twice, move the stray doc comments (`VaultLayout.swift:37-43`, `VaultStamp.swift:124-128`, `VaultName.stem`). Do NOT delete `CorruptFileRegistry` (SPEC C265 surfaces corruption through it; no UI yet), `EmbeddingIndex.rowCount`, or `NamesStore.upsert(canonical:aliases:short:)` (the Mac calls it, `ProcessingCoordinator.swift:486`). Update `plan/periphery.md`: LockGate, `wikiNames`, `gistPairScores`, `writeWithSmartBumps`, `seedRoster`, `pruneOldTombstones` are live. Protected-test edits: hand-merge after Tuur's yes.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh PersonEditCoreTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SRS-d01 SRS-d02 SRS-d03 SRS-d04 SRS-d06 SRS-d10 SRS-d12 SRS-d15 SRS-d16 SRS-d20 SRS-c02 SRS-c03

### P48 [auto] (todo) naming: one match key, one pipe split, one link finder
spec: C239
needs: Q116
gate+: no
do: `NamesMerge.keyName(x).trimmingCharacters(in: .whitespaces)` (sometimes `.lowercased()`) is typed 11 times (`Sanitiser.swift:58,64,72`, `NamesStore.swift:205,241,268,270` with two identical local `key()` helpers, `Compiler.swift:276,298`, `SpeakerTurnStyle.swift:49`, `RosterAudit.swift:41`) with inconsistent combinations. Add `NamesMerge.bareName(_:)` (keyName + trim) and `matchKey(_:)` (+ lowercase) and an alias-side key for `trim.lowercased()` at `Sanitiser.swift:70,81,95,119,122` and `NameLinking.swift:33,36`; trim is almost always a no-op because `normaliseCanonical` already trims. Three sites re-implement `Sanitiser.linkDisplay` (`NameLinking.swift:69`, `Compiler.swift:308`, `BodyTextView.swift:1091-1092`): use `linkDisplay(core) ?? fallback`; check `A|`, `|x`, `a|b|c` give the same display, run the NameLinking and Compiler tests. `Sanitiser.process`, `ConversationLinking.process` and `NameLinking` repeat the alias derivation, the earliest-eligible-match loop (`Sanitiser.swift:170-182`, `ConversationLinking.swift:134-147`, `NameLinking.swift:77-83`) and the demote-later-mentions loop (`Sanitiser.swift:191-197`, `ConversationLinking.swift:157-163`): extract `linkable`, `firstSafeMatch(of:in:)` and `demoteMentions(of:to:in:)`; the demotion string differs (`process` uses the short name behind `guard !short.isEmpty`, `linkInline` short-or-canonical), so pass it in; `linkInline` guards `!unambiguous.isEmpty`; `nameSpans` records a span instead of rewriting. Pinned by `SanitiserSmokeTests`, naming goldens and the conversation tests: they must pass unedited. Q116 changes the Mac naming overrides: land after it.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh SanitiserSmokeTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SRS-d18 SRS-d19 SRS-c07

### P49 [auto] (todo) two real bugs in model loading and location, plus a glob that lies about itself
spec: C115
needs: -
gate+: no
do: Found by reading, not run. (1) `GemmaEmbedder.prepare()` (`Shared/RetrievalEngine/GemmaEmbedder.swift:84-94`): two concurrent calls both pass the `loadTask == nil` check before the `TranscriptionActivity` wait loop suspends, each creates a Task, the second overwrites the first, so the 295 MB model loads twice (the exact failure the single-flight comment at 75-79 describes). Move the wait loop inside the single-flight Task; write a test that two concurrent `prepare()` calls start one load (inject the loader). Also keep ONE idle-unload Task: `scheduleIdleUnload()` spawns a new 605 s sleeping Task on every `prepare()` and `embed()` calls `prepare()` per chunk (`EmbeddingIndex.swift:124,127,133`), so a sweep leaves thousands of sleepers; use one task that loops until `lastUse + 600 s`. (2) `MacLocationStamp` shares one `LocationOneShot` instance (`SkriftDesktop/Pipeline/Ingest/MacLocationStamp.swift:31,40-45`); a second `current()` before the first fix returns overwrites the continuation and leaves the first caller suspended. Create `LocationOneShot()` per call as the phone does (`MetadataService.swift:20`). Reachability is low (one stamp per Mac recording). (3) `ResumableModelDownloader.glob` (`ModelDownload/ResumableModelDownloader.swift:245-262`) is a 17-line hand-written matcher whose doc says `*` stays within a path segment while the code lets it cross `/`: replace the body with `fnmatch(pattern, name, 0) == 0` (flag 0, `*` crosses `/` as today) and fix the doc; the patterns mlx-swift-lm passes (`*.safetensors`, `*.json`) are unaffected. The file imports MLXLMCommon, so it is not in the Mac test bundle: put the test in the phone suite. Leave the `hubCacheCopy` migration shim (it saved an 8.9 GB download once; Tuur's call). Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh EmbeddingIndexTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SRS-m1 SRS-c15 SRS-c16 SRS-c23

### P59 [auto] (todo) VaultWriter: one ownedName and one place-bytes step for URL and Data attachments
spec: C239
needs: P47
gate+: no
do: `Shared/Export/VaultWrite.swift:330-524`: `ownedName` exists for URL (478-484) and Data (489-495) differing only in the equality test; `resolvedName` (384-394) and `writeAsset` (425-442) are two switch-on-`Source` wrappers; `writeAtomic` and `copyOwned` repeat the `NSFileCoordinator` dance. Collapse to one `ownedName(preferred:in:id:isIdentical:)` and one place-bytes step on `VaultAsset.Source`; keep `copyOwned` and `writeOwned` as thin public wrappers (Mac `VaultExporter.swift:238,274,308`, `AttachmentOwnershipTests`, `DataAttachmentOwnershipTests` call them). Keep the second resolve inside `writeOwned`/`copyOwned`: it is the only guard against a clobber when the id-suffixed name is itself taken. Test first (found by reading): `resolvedName` returns `disambiguated(preferred)` without checking that name is free, so if `X id8.png` is occupied by different bytes the embed is patched to `X id8.png` but `writeOwned` writes `X id8 id8.png` and the embed points at the wrong file. Write that test; fix by resolving the id8 name in the same pass that patches the embed. `AttachmentOwnershipTests` and `DataAttachmentOwnershipTests` stay green unedited. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SRS-c01 SRS-m2

### P60 [auto] (todo) compiler: typed shared content and one wiki-link scanner
spec: C239
needs: Q155
gate+: no
do: `CompilerSharedContent` (`Shared/Export/CompilerInput.swift:53-64,84`) is a string-typed five-field copy of `Shared/Model/SharedContent.swift` compiled into the same targets (both `project.yml`s list `../Shared/Model` and `../Shared/Export`); `Compiler.swift:52,59-65,234-257` switches on `"url"/"text"/"image"/"file"` strings and a default hides a new capture type. Use `SharedContent?` and switch exhaustively on `ShareContentType` (add an explicit `.file: break`, today the default swallows it); delete `CompilerSharedContent`, `MemoExporter.compilerShared` (`SkriftMobile/Services/Export/MemoExporter.swift:58,125-128`) and the lambda in `CompilerBridge.swift:69`; update the five `CompilerTests.swift:325-354` constructors (memberwise init, optionals default nil). Leave `CompilerMetadata` and `PhoneMetadata` to Q155. Add `Sanitiser.bodyLinks(in:)` (`linkOccurrences` minus `![[` embeds) and one replacing-ranges helper (`Sanitiser.nsReplace` exists at `Sanitiser.swift:300`; the right-to-left loop is repeated at `Compiler.swift:312`, `VaultExporter.swift:247,317`, `ObsidianPublisher.swift:257`): `peopleLinks` and `plainifyNonPeopleLinks` use it. `ConnectionWhy.wikiNames` may use `linkOccurrences` + `linkTarget` but keeps its `memo:` exclusion and the length-60 guard; it does not skip embeds or `img_NNN` markers today, so accept that one small change and say so. `CompilerTests` and the corpus goldens stay green unedited; the frontmatter key order is a pinned contract. Q155 moves input building: land after it. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SRS-c05 SRS-c06

### Cross-cutting

### P51 [auto] (todo) one place for preference keys, the isXCTest check and the optional-binding shim
spec: C239
needs: P35
gate+: no
do: (1) A `PrefKey` enum with each key and its default beside it in `Shared/Model`, used by every writer and reader: `liveTranscription` (x4: `RecordView.swift:52`, `LiveRecordingService.swift:167,445,469`), `liveCaptionAutoOffSeconds` (x2, default 60 in two files), `autoCopyTranscript` (reuse `MemoSaver.autoCopySettingKey`), `karaokeTapToSeek` (x3: `NoteBodyView.swift:84`, `MemoPageView.swift:45`, `SettingsView.swift:13`; fix the "must match TranscriptBodyView" comment, that view is gone), `fadingLastSeenAt` (`WayOutView.swift:54`, `JournalHomeView.swift:20`), `continueCardDismissedDay` (x3, `NotesBottomChrome.swift:19`, `ContinueListeningCard.swift:27`, `AudiobookSeeder.swift:23`), `skrift.publish.author` (`ObsidianSettingsSection.swift:27`, `MemoDetailView.swift:768`; Q158 owns the author-name rule, coordinate), `weatherAPIKey` (reuse `WeatherClient.apiKeyDefaultsKey`), `appTheme` (Q172 owns the ColorScheme mapping), `macSidebarVisible` and the appearance default `"dark"` on the Mac (`RootView.swift:23,25`, `SettingsView.swift:14`, `Theme.swift:108`, `NoteDisplayView.swift:65`). (2) One `isXCTest` for the six `XCTestConfigurationFilePath` lookups (`Shared/Model/Memo.swift:283`, `NotesRepository.swift:33`, `JournalIndexService.swift:49`, `ConnectionsIndexService.swift:105`, `SkriftDesktopApp.swift:66`, `MemoCloudContainer.swift:47`; `LaunchFlags` is phone-only so it cannot host it). (3) One `Binding<Value?>.isPresent` in `Shared/UI` replacing the hand-written `Binding(get: { x != nil }, set: { if !$0 { x = nil } })` at about 14 sites (`AudiobookLibraryView.swift:147-168`, `BookTextSheet.swift:146`, `BookTextFlow.swift:112-143`, `MemoDetailView.swift:475`, `MemoPageView.swift:1035`, `WayOutView.swift:87`, `SkriftApp.swift:100`, Mac `RootView.swift:127`, `WayOutColumn.swift:91`, `SidebarView.swift:127`); `BookShareSheet.swift:111-112` is a different pattern, leave it. Behaviour must not change; `-selectFirstMemo`-style launch flags are untouched. Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh MemoModelTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MRC-d21 MLJ-d17 MMD-c20 MSV-c35 MAU-c07

### P54 [auto] (todo) six suspected bugs the audit tripped over: prove each with a test or log why not
spec: C115
needs: -
gate+: yes
do: Each is a reading, not a run. One commit per bug; write the failing test first; if it does not reproduce, log what you found in `BUGS.md` and do nothing else. (1) `SourceKind.of` (`Shared/Pipeline/SourceTaxonomy.swift:54-63`) reads only the raw `mediaSource` key, but the phone writes video notes as `sourceType: "video"` (`MemoSaver.swift:318,354`, `MemoMetadata.swift:51`), so a phone-made video note may classify as a voice memo on the Mac and in the phone's row chips (`MemosListView+Row.swift:131`; `MemoDisplay.swift:55` checks `sourceType` separately). (2) The typed-note marker is raw JSON `{"mediaSource":"typed"}` built by `Memo.newTyped` (`Shared/Model/Memo.swift:386`) and `EditConflicts.makeCopy` (`EditConflict.swift:352`), and `MemoMetadata` does not model that key: any later `memo.metadata = ...` write on a typed note would drop it and turn it into an "Apple Note"; check whether adding a photo to a typed note does. (3) `CloudSyncMonitor.runImportSweeps` (`SkriftMobile/Services/CloudSyncMonitor.swift:143-157`) omits `MemoDeduper`, but `SkriftApp.swift:223-229` says CloudKit dupes land mid-session and the 2026-07-12 crash loop was duplicate memo UUIDs; the foreground gate is the only mid-session dedupe path. (4) `IngestService.ingestNote` (`SkriftDesktop/Pipeline/Ingest/IngestService.swift:417-451`) is the only Mac import that does not stamp `isLocalImport`, while SPEC C49 (as reversed by D159) says a Mac import arrives unrated, and `NoteConsent.isRated(pf)` reads an unstamped inserted row as rated (legacy). (5) `SidebarView.refreshCloudMemos` says `mainContext` returns stale memos after a CloudKit import and fetches through a fresh `ModelContext(cloud)`, but `JournalView.refresh` and `UnpipelinedMemoSheet.load` read `cloud.mainContext`, and `SidebarView.toggleLock`/`deleteQuiet` mutate memos fetched through the throwaway context and then save `mainContext` (`SidebarView.swift:855-880`, `JournalView.swift:78`); check that the change persists and that the Journal river is not stale. (6) Open Settings keeps a stale copy of settings.json (`SettingsView.swift:15,40,494-504`) while the CloudKit runners write vocab, language and prompts to disk; an autosave from the open sheet can write older values back (LWW stamps may self-heal; check). Never run SkriftDesktopUITests; Mac proof = unit tests + full build.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh SourceTaxonomyTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SPL-c25 SMU-c13 MAM-c01 DPE-m1 (ingestNote, missed) DAU-c05 DAU-c15

### Repo hygiene (PER)

### P50 [auto] (todo) archive the finished spikes and the stray duplicate mock
spec: C240
needs: -
gate+: no
do: Move, never delete (repo rule): `Skrift_Native/GlassLab/` to `archive/spikes/GlassLab` (its own `project.yml` says to port the result to `MemoDetailView`, which now has `.glassEffect(.clear, ...)` at line 619 with `SkriftMobileUITests/GlassUITests.swift`; only two `archive/handoffs/*.md` prose mentions refer to it); `Skrift_Native/DiarizeSpike/` to `archive/spikes/DiarizeSpike` (its `Package.swift` pins FluidAudio `branch: main` while the apps pin revision `19600a48`; three code comments cite it for measured thresholds, `SpeakerFusion.swift:8`, `VoiceMatcher.swift:16`, `DiarizationService.swift:12`: change the path in the comment); `git rm mockups/Q51.html` (byte-identical to `Skrift_Native/SkriftDesktop/mocks/Q51-apple-notes-import.html`, `plan/RUN.md:73` calls it a stray copy); `Skrift_Native/SkriftMobile/scripts/mklongm4a.swift` (one-off, no target compiles it; remove the `FEATURES.md:158` cell mention); rewrite the docstring of `tools/rescue-lost-recordings.py:1-40` (since Q16 the app sweeps and quarantines orphaned takes: `RecordingRecovery.swift:10-45`, so say it diagnoses quarantined and orphaned takes, drop the stale line cites `LiveRecordingService.swift:433`, `RecordView.swift:548`, pull `Documents/QuarantinedRecordings` too, and merge `pull`/`pull_devlog` into one `copy_from`; keep the tool, `BUGS.md:25`, `RecordingRecovery.swift:24` and `RecoveryQuarantineTests.swift:9` name it). Leave alone: `spikes/EmbeddingBakeoff/` (cited by five live paths: `GemmaEmbedder.swift:9`, `EmbeddingEngine.swift:8`, `SkriftMobile/project.yml:25`, `FEATURES.md:391`, `roadmap.yaml:1520`), `SkriftMobile/mockups/*.html` (`Theme.swift:5` cites them as the signed token source), `plan/sources*.md`, `tools/twin-scan.py`. Confirm with `git grep` that nothing in `gate.sh`, `plan/*.sh` or either `project.yml` references the moved paths before moving.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md PER-d01 PER-d02 PER-d04 PER-d17 PER-d18 PER-c21

### P61 [auto] (todo) one temp-dir helper and one corpus-root helper per test bundle
spec: C239
needs: -
gate+: no
do: Test-only. `tempDir()` is defined 17 times in 15 desktop test files (some with `addTeardownBlock` cleanup, others without, e.g. `RoundTripParityTests:14-19` vs `UploadTests:13`) and `BookAlignmentTests.swift:11,116` on the phone; the four-level `#filePath` climb to `test-fixtures/corpus` is copied in `BodyGoldenTests.swift:11-18`, `ChipCountParityTests.swift:19-25` and both `CorpusSeedTests.swift:8-14`. Add one `makeTempDir()` (with teardown) per test bundle and one `CorpusSeed.fixtureRoot(file: #filePath)` (`CorpusSeed` is compiled into both test bundles). The 11 phone UI tests that repeat the climb cannot use it (separate bundle): leave them. Behaviour and assertions do not change; this is a protected-path edit that goes through hand-merge after Tuur's yes. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md PER-c13

### P62 [tuur] (todo) accept.sh learns --approve-protected and hand-merge.sh goes
spec: C239
needs: -
gate+: no
do: `plan/hand-merge.sh` re-implements `plan/accept.sh` steps 2-5 with drift: it always sets `done` (accept.sh:129-135 parks `[tuur]` items), leaves the worktree and branch, and runs `git reset --hard $PRE` without the queue backup that `accept.sh`'s `undo_merge` makes (96-100), which can discard uncommitted QUEUE.md state because `queue.sh set` writes into the working tree. Add `--approve-protected "<why>"` to `accept.sh` that skips only the protected-paths block and logs the reason; put the xcodebuild-idle `busy()` wait in one place (`accept.sh --wait`, so `accept-chain.sh` is only a loop); delete `hand-merge.sh`; update the mentions in SPEC.md, QUEUE.md and `plan/RUN.md`. This is the gate machinery and the protected list: Tuur reviews the diff before it merges and nothing else touches `plan/*.sh` in the same session.
check: `./gate.sh`
source: plan/reads/cleanup-audit.md PER-c18

### Needs Tuur (no queue item; each is a decision)

| Decision | Where | What it buys |
|---|---|---|
| Is swipe between notes permanently off? | MMD-c01, `MemoDetailView.swift:532-592` | about 45 lines of pager plumbing, loses the slide animation on a link hop |
| Keep the legacy `epubFilename` mirror (downgrade to a pre-multi-text build)? | MAS-d16 | 8 lines |
| Is the `-showTOCSheet` / `-seedAudiobook` / `-seedJournal` / `-fakePolishEngine` screenshot rig still used by hand? | MLJ-d09, MAM-d10, MAM-d12 | about 160 lines; lane briefs say keep |
| Pick the winner for each `DriftedPair` palette token | SMU-c23 | 15 lines, 6 tokens, two visible (`textTertiary` light, `nameSuggestLine` dark) |
| Collapse `BodyV2Legacy.reflowMidSentencePictures` into `BodyNormaliseMigration`? | SMU-c01 | 120 lines, but vault export output may change; git 35f98834 kept it on purpose |
| Drop the `hubCacheCopy` model-download shim? | SRS-d17 | 25 lines; costs an 8.9 GB re-download if a device still needs it |
| Wire or delete `LiveRecordingSession.cancel` / `MacRecorder.cancel` | DSH-d03, QUEUE.md:1225 | 19 lines |
| Does `PublishCoordinator`'s paired mode have a use? | P39 | 30 lines |
| Run `testflight.sh` once with the new `ExportOptions-TestFlight.plist`, then drop the old plist | PER-d16 | 50 lines, unverified |
| Move the six finished `LANES-*` brief folders (40 files) to `archive/` | PER-d-m1 | repo-root tidiness; check `roadmap.yaml` cross-references first |
| Which phone/Mac routing predicate wins for conversation linking (`parse != nil` vs `isAttributed`)? | P20 note, `MemoLinking.swift:18-29` | removes a behaviour difference between phone and Mac |

### Found but not queued (reason)

- Test-only deletes that wait on an open item: `ConnectionsPanelLogic.ordered` (after Q181), `Memo.nameSpans(people:)` and `clearNameResolution` (after Q116), `MemoFilter.hasPhotosOnly/.place/.isActive` (Q110, Tuur-gated), `PlayerBar.density` (Q121), `NotesBottomChrome.recordButton`, `sleepLabel`, `ChaptersBookmarksRail` (Q173).
- Hardware-flavoured recording code (observer array, caption begin/end, halt/teardown, `MacRecorder.start()` refusals, UID round trip): the rule is "diagnose from the device trace first, fixes belong to the orchestrator". About 130 lines, medium risk.
- Collide with open items: `CaptureInboxDrainer` copy helper and the 8 parallel arrays (Q134, Q145, Q93/Q96), share-sheet temp-copy and `SharePayload` kind enum (Q132, Q133, Q150), connections state cards (Q181), `SearchField` focus (Q177), sync tick counters and `row()` split (Q148).
- Taste or no net saving: typed `Verdict` enum (56 test sites), `store.mutate` helper (sync LWW bump differs on purpose), `MemoPageView` capture cards and footer rows, `NoteBodyView` coordinator parent pointer, `ModelLiteralAttachment` protocol, toast-lifetime modifier, `MacFormField`, hairline tokens, `ImageManifest.read/write` (check Q135 first), `BatchRunner.run` phases, `JournalHomeView.riverCards`, `MonthSelection`, `StableTail`, the Snapshot flag table.
