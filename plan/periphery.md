# Periphery dead-code scan (Q60) — report only, no deletions

Periphery 2.21.2, installed from the release zip to `~/bin` — the brew cask
errored on a homebrew-core policy check (`depends_on macos: :catalina` disabled),
unrelated to sudo/GUI, so the binary was fetched directly instead of via brew.

Scanned: SkriftMobile (targets SkriftMobile+SkriftShare+SkriftWidget+SkriftShared,
iPhone 17 sim) and SkriftDesktop (full MLX scheme). Flags: --retain-public
--retain-objc-accessible --retain-codable-properties --retain-swift-ui-previews.
Raw logs (not committed, machine-local): `/private/tmp/claude-501/-Users-tiurihartog-Hackerman-Skrift--claude-worktrees-session-3-f90c83/b8d66d42-eaeb-4240-a283-1b7a64a1f889/scratchpad/periphery/{mobile,desktop}-scan.log`.

## Totals: 374 unique findings (263 raw mobile + 163 raw desktop, 52 overlap in Shared/)
SAFE 245 (~1976 lines,
brace-matched span estimate — an upper bound, since an unused enum/struct and its
own unused members each get spanned separately) · CHECK 127 (116 test-only + 11 structural) · KEEP 2

**Biggest finding of this scan: Periphery alone was not enough.** 116 of the
374 unique findings looked identical to genuine dead code (zero references in the app
targets) but have a dedicated XCTest file exercising them (e.g. `CaptureMath.swift`'s
whole 20-member enum ↔ `AudiobookCaptureMathTests.swift`/`AudiobookScrubberTests.swift`;
`TagMatcher.swift` ↔ `TagMatcherTests.swift`) — built, tested, correct, just never
wired into a call site. Deleting on Periphery's word alone would have deleted tested
logic, exactly the NamesStore.pruneOldTombstones shape Tuur already flagged. Moved to
CHECK. Detection: cross-grepped every SAFE symbol name against the matching
`<File>Tests.swift`; this needed reading source, not just running the tool.

Three items named in the brief, confirmed:
- MemosListView.swift MemoCard helpers (statusPill/captureGlyph/voiceGlyph/videoGlyph/
  bookGlyph/quoteText/photoThumb, :1415-1490) — no test file either — dead, SAFE.
- SidebarView.swift `quietMeta` (:778), `process(_ memo:)` (:800) — dead, SAFE.
- NamesStore.pruneOldTombstones (:277) — KEEP per Tuur (test-only, wired in Q58) —
  this is the exact shape of the 116 test-only CHECK items below.

A second KEEP found by reading source past the grep, not by Periphery: the
`AudiobookAsset` init (AudiobookSyncModels.swift:77) has zero references, same shape
as a SAFE case — but the file's own comment says the `@Model` is intentionally
retained until prod promotion (dropping it risks a CloudKit-schema fatalError on
already-deployed dev data).

## Per-folder (SAFE / CHECK / KEEP, SAFE-line-count)

| folder | SAFE | CHECK | KEEP | SAFE lines |
|---|---|---|---|---|
| Skrift_Native/SkriftMobile/Services | 48 | 25 | 0 | 458 |
| Skrift_Native/SkriftMobile/Features | 38 | 1 | 0 | 286 |
| Skrift_Native/Shared/Pipeline | 34 | 59 | 0 | 380 |
| Skrift_Native/SkriftDesktop/Features | 19 | 0 | 0 | 127 |
| Skrift_Native/Shared/Naming | 17 | 5 | 1 | 128 |
| Skrift_Native/Shared/Model | 14 | 4 | 0 | 87 |
| Skrift_Native/SkriftMobile/DesignSystem | 13 | 0 | 0 | 140 |
| Skrift_Native/Shared/Retrieval | 11 | 4 | 0 | 116 |
| Skrift_Native/SkriftDesktop/Engines | 8 | 0 | 0 | 15 |
| Skrift_Native/Shared/UI | 7 | 5 | 0 | 32 |
| Skrift_Native/SkriftMobile/Models | 6 | 1 | 1 | 52 |
| Skrift_Native/Shared/Recording | 5 | 4 | 0 | 34 |
| Skrift_Native/SkriftDesktop/Pipeline | 5 | 1 | 0 | 21 |
| Skrift_Native/Shared/BodyV2 | 4 | 7 | 0 | 38 |
| Skrift_Native/Shared/Export | 4 | 3 | 0 | 11 |
| Skrift_Native/SkriftMobile/App | 4 | 5 | 0 | 4 |
| Skrift_Native/Shared/Session | 3 | 1 | 0 | 7 |
| Skrift_Native/SkriftDesktop/Models | 2 | 1 | 0 | 29 |
| Skrift_Native/Shared/Corpus | 1 | 1 | 0 | 4 |
| Skrift_Native/Shared/RetrievalEngine | 1 | 0 | 0 | 6 |
| Skrift_Native/SkriftMobile/SkriftShare | 1 | 0 | 0 | 1 |

## Structural CHECK (11) + KEEP (2) — every one, with why

- **CHECK** `Skrift_Native/Shared/Corpus/CorpusSeed.swift:91` Struct 'NameOffsets' is unused — marker: Decodable nearby (system-called, not Swift-referenced)
- **CHECK** `Skrift_Native/Shared/Model/EditConflict.swift:378` Function 'debugForceConflict(in:now:)' is unused — marker: DEBUG nearby (system-called, not Swift-referenced)
- **CHECK** `Skrift_Native/Shared/Pipeline/ASRLanguageMode.swift:56` Enum 'ASRLanguageStore' is unused — marker: @Model nearby (system-called, not Swift-referenced)
- **CHECK** `Skrift_Native/Shared/Pipeline/VocabularyTermParsing.swift:112` Enum 'VocabularyTuning' is unused — marker: DEBUG nearby (system-called, not Swift-referenced)
- **CHECK** `Skrift_Native/SkriftDesktop/Models/FileDTO.swift:24` Struct 'UploadResponseDTO' is unused — marker: Codable nearby (system-called, not Swift-referenced)
- **CHECK** `Skrift_Native/SkriftMobile/App/Intents/NewNoteIntent.swift:14` Property 'description' is unused — marker: AppIntent nearby (system-called, not Swift-referenced)
- **CHECK** `Skrift_Native/SkriftMobile/App/Intents/ResumeAudiobookIntent.swift:17` Property 'description' is unused — marker: AppIntent nearby (system-called, not Swift-referenced)
- **CHECK** `Skrift_Native/SkriftMobile/App/Intents/SkriftShortcuts.swift:8` Struct 'SkriftShortcuts' is unused — marker: AppIntent nearby (system-called, not Swift-referenced)
- **CHECK** `Skrift_Native/SkriftMobile/App/Intents/StartRecordingIntent.swift:18` Property 'description' is unused — marker: AppIntent nearby (system-called, not Swift-referenced)
- **CHECK** `Skrift_Native/SkriftMobile/App/Intents/StopRecordingIntent.swift:16` Property 'description' is unused — marker: AppIntent nearby (system-called, not Swift-referenced)
- **CHECK** `Skrift_Native/SkriftMobile/Services/Embeddings/JournalIndexService.swift:79` Parameter 'repository' is unused — marker: DEBUG nearby (system-called, not Swift-referenced)
- **KEEP** `Skrift_Native/Shared/Naming/NamesStore.swift:277` Function 'pruneOldTombstones(maxAgeDays:)' is unused — test-only, being wired in Q58 (Tuur)
- **KEEP** `Skrift_Native/SkriftMobile/Models/AudiobookSyncModels.swift:77` Initializer 'init(bookID:filename:blob:createdAt:)' is unused — file comment: @Model intentionally RETAINED (no longer written) — dropping risks a load fatalError against the deployed dev CloudKit schema; remove at prod promotion

## Test-only CHECK (116) — has a dedicated unit test, no production caller
packed as file:line(s)(lines) → test file

- BodyNormaliseMigration.swift:67,148,152,160,217,309(42l)→BodyNormaliseMigrationTests.swift; BodyV2.swift:25(1l)→BodyV2HarnessTests.swift; VaultStamp.swift:53(1l)→VaultStampTests.swift
- VaultWrite.swift:314,315(2l)→VaultWriteTests.swift; EditConflict.swift:43,60(2l)→EditConflictTests.swift; Memo.swift:300(3l)→MemoModelTests.swift
- Sanitiser.swift:34,53,221,544,664(122l)→SanitiserParityTests.swift; AlignmentCore.swift:88,89,95,99,100,101,112,113,114,119,120,121,122,129,131,133,137,138(18l)→AlignmentCoreTests.swift; EPubParse.swift:89,500,501,502,513,516(6l)→EPubParseTests.swift
- Karaoke.swift:17,30,110,118(27l)→KaraokeTests.swift; LanguageSyncCore.swift:29(22l)→LanguageSyncCoreTests.swift; LookbackProvider.swift:29(1l)→LookbackProviderTests.swift
- MemoDuplicates.swift:46(9l)→MemoDuplicatesTests.swift; MemoLifecycle.swift:40,76,81,127,135(16l)→MemoLifecycleTests.swift; MemoSpine.swift:169,186,195(45l)→MemoSpineTests.swift
- Paragrapher.swift:44,76,120(79l)→ParagrapherTests.swift; ProcessPile.swift:20,38,54(14l)→ProcessPileTests.swift; SpeakerTranscript.swift:87,116,126,139,159(41l)→SpeakerTranscriptTests.swift
- SpeakerTurnStyle.swift:69,85,113,127(42l)→SpeakerTurnStyleTests.swift; TagComplete.swift:8(49l)→TagCompleteTests.swift; TagMatcher.swift:9(74l)→TagMatcherTests.swift
- VaultTagScanner.swift:10(63l)→VaultTagScannerTests.swift; RecordingCore.swift:18,29,48,58(39l)→RecordingCoreTests.swift; EmbeddingIndex.swift:16,28,156,172(20l)→EmbeddingIndexTests.swift
- NoteVisibility.swift:10(5l)→LockedNoteVisibilityTests.swift; NotesListModel.swift:20,35(14l)→NotesListModelTests.swift; SignificanceWarmFill.swift:16(19l)→SignificanceWarmFillTests.swift
- TagRules.swift:48,48(2l)→TagRulesTests.swift; ArrivalPath.swift:39(1l)→ArrivalPathTests.swift; MemoSaver.swift:552(7l)→MemoSaverTests.swift
- FillerFilter.swift:29(1l)→FillerFilterTests.swift; Audiobook.swift:519(3l)→AudiobookCloudSyncTests.swift; BookAlignment.swift:581(4l)→BookAlignmentTests.swift
- CaptureMath.swift:16,20,25,36,43,63,73,227,266,306,351,372(265l)→AudiobookCaptureMathTests.swift; ChapterDetector.swift:340(3l)→ChapterDetectorTests.swift; DevLog.swift:62(1l)→DevLogTests.swift
- MemoExporter.swift:38,46,53,182,228(65l)→MemoExporterTests.swift; MemoLinking.swift:33(3l)→MemoLinkingTests.swift; PublishCoordinator.swift:37,155(31l)→PublishCoordinatorTests.swift

## SAFE list (245 findings across 109 files, no test found either) — file:line(s)(lines)

**Skrift_Native/SkriftMobile/Services**
- AudiobookAudioTransport.swift:53(33l); AudiobookImporter.swift:89(3l); AudiobookSession.swift:368,466,602(23l); BookAlignment.swift:288(1l)
- BookBundle.swift:43,258(16l); BookTranscriptionJob.swift:79,402(17l); CaptureMath.swift:13,23,55,212,222,223,279,385(139l); QuoteCaptureProcessor.swift:30,47,76,279,308,357(126l)
- CaptureInbox.swift:234(4l); DiarizationService.swift:27(1l); SpeakerEmbedder.swift:18,40,77(6l); ArchiveVault.swift:48(1l)
- MemoExporter.swift:244(42l); ObsidianPublisher.swift:40(1l); MemoDeduper.swift:43(3l); WeatherClient.swift:30(9l)
- ModelInventory.swift:14,18(2l); NotesRepository.swift:102,253(10l); RecordingActivityManager.swift:69(1l); RecordingCheckpoint.swift:29,85(5l)
- TranscriptionService.swift:22,33,43,249,263,291(14l); VocabularyBooster.swift:67(1l)

**Skrift_Native/SkriftMobile/Features**
- AudiobookPlayerView.swift:122,122,122(3l); AudiobookSyncSheet.swift:14(6l); BookTextSheet.swift:22(10l); ChaptersBookmarksSheet.swift:10,202(72l)
- MergedCaptureView.swift:67(23l); SyncedAudiobooksView.swift:10(9l); FeedbackMailComposer.swift:20(3l); FeedbackStore.swift:27,69,120,121,123,124,125(10l)
- CaptureQuoteViews.swift:109(32l); ConnectionsPanel.swift:75(3l); MemoDetailView.swift:16,2416(2l); NoteBodyView.swift:267,590,598(16l)
- MemosListView.swift:16,27,1415,1423,1439,1453,1467,1480,1485,1531,1534,1727(93l); QuickNoteView.swift:23(1l); MemoSaver.swift:316(3l)

**Skrift_Native/Shared/Pipeline**
- ASRLanguageMode.swift:29,49,63(13l); AlignmentCore.swift:457(81l); AudioRMS.swift:34(11l); BodyMarkdown.swift:12(31l)
- BodyTransform.swift:78,78,87,110,134(50l); DiarizingContract.swift:29(3l); ImageMarkers.swift:9(55l); LookbackProvider.swift:115(8l)
- MemoDuplicates.swift:20(7l); MemoSpine.swift:227(7l); NoteWorkState.swift:51(1l); PDFTextExtract.swift:13(17l)
- Paragrapher.swift:23,142(31l); ProcessPile.swift:24,42(9l); SpeakerTranscript.swift:72,82,105(19l); SpeakerTurnStyle.swift:64(14l)
- TranscribingContract.swift:13,14,16,27,31,37,47(22l); VocabularyTermParsing.swift:49(1l)

**Skrift_Native/SkriftDesktop/Features**
- JournalView.swift:16(1l); RecordingDraftView.swift:56(1l); ConnectionsPanel.swift:50(1l); PersonEditor.swift:19(1l)
- SettingsView.swift:574(17l); AppModel.swift:15,23(11l); LifecycleSweepScheduler.swift:49(1l); LiveRecordingSession.swift:204(8l)
- QueueDerivations.swift:115,154,161(26l); SidebarView.swift:37,421,778,800,1252,1261(49l); Theme.swift:42(11l)

**Skrift_Native/Shared/Naming**
- NameMatch.swift:35(27l); NamesStore.swift:97,177,238(48l); SafeJSONStore.swift:31,99,100,101,107,119(13l); Sanitiser.swift:51,600,614,623,634,648,675(40l)

**Skrift_Native/Shared/Model**
- CaptureQuote.swift:35,43,62,102(34l); Memo.swift:258,317,381,384(21l); MemoEnhancement.swift:76(7l); MemoLinkSyntax.swift:19,43(11l)
- MemoMetadata.swift:91(3l); NoteDestination.swift:93,110(11l)

**Skrift_Native/SkriftMobile/DesignSystem**
- Components.swift:18,183(46l); Theme.swift:87,88,89,90,91,94,102,103,104,105,116(94l)

**Skrift_Native/Shared/Retrieval**
- ConnectionWhy.swift:40(15l); EmbeddingEngine.swift:45(30l); EmbeddingIndex.swift:30,178(24l); RetrievalGate.swift:8,9,13,14,17,18,23(47l)

**Skrift_Native/SkriftDesktop/Engines**
- EnhancementService.swift:29(1l); MacRecorder.swift:114,325(7l); TranscriptionService.swift:22,39,43,182(6l); VocabularyBooster.swift:31(1l)

**Skrift_Native/Shared/UI**
- DestinationRowView.swift:37(1l); NoteMenu.swift:63,84(20l); Palette.swift:22(1l); SharedCopy.swift:28,44,55(10l)

**Skrift_Native/SkriftMobile/Models**
- Memo+BodyNormalise.swift:70(12l); Memo+Mobile.swift:119,155(13l); MemoDisplay.swift:74,206,336(27l)

**Skrift_Native/Shared/Recording**
- LiveCaptionEngine.swift:181,268,277,362,423(34l)

**Skrift_Native/SkriftDesktop/Pipeline**
- DiarizationSidecar.swift:26,69(9l); MemoCloudReconciler.swift:184(8l); MultipartPart.swift:11(1l); WayOutRules.swift:158(3l)

**Skrift_Native/Shared/BodyV2**
- BodyNormaliseMigration.swift:124,132,300(25l); BodyV2Thumbnail.swift:4(13l)

**Skrift_Native/Shared/Export**
- ExportProfile.swift:41,111(4l); VaultWrite.swift:193,313(7l)

**Skrift_Native/SkriftMobile/App**
- LaunchArgs.swift:18,34,37,40(4l)

**Skrift_Native/Shared/Session**
- LockGate.swift:36,62,68(7l)

**Skrift_Native/SkriftDesktop/Models**
- FileDTO.swift:32(15l); PipelineFile+BodyNormalise.swift:105(14l)

**Skrift_Native/Shared/Corpus**
- CorpusSeed.swift:102(4l)

**Skrift_Native/Shared/RetrievalEngine**
- GemmaEmbedder.swift:138(6l)

**Skrift_Native/SkriftMobile/SkriftShare**
- SharePayloadLoader.swift:22(1l)

