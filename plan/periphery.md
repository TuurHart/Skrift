# Periphery dead-code scan (Q60) + Q61 removal pass

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
own unused members each get spanned separately) · CHECK 127 (116 test-only + 11 structural) · KEEP 2.
**Q61 update:** of the 245 SAFE, 18 removed (150 real lines, see below) + 227 moved to
CHECK after whole-repo grep re-verification (span estimates were never trustworthy
enough to delete on their own — see the Q61 section below).

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

## Q61 — SAFE list processed: 18 removed (150 lines), 227 moved to CHECK

Every one of the 245 SAFE findings was re-verified before touching anything, per the
item's instruction: a whole-repo `grep` (Swift, tests, plists, entitlements,
`.intentdefinition`, mocks, docs — everything, not just app targets) for the symbol's
base identifier, excluding only the symbol's own declaration span (not its whole file —
an early pass that excluded the whole file missed a same-file caller: `remap(_:from:to:)`
calls the SAFE-listed `offsetMap(from:to:)` from three lines away in
`BodyNormaliseMigration.swift`, which would have broken the build). A second, more
"precise" label-anchored regex pass was tried and abandoned: it missed
`RetrievalGate.derive(...)` being called from `ConnectionsPanel.swift:58` because the real
call site wraps its 7 labeled parameters across multiple lines and `grep -E` patterns
don't span newlines — a false "clean" that would have broken the Mac build. Base-name
whole-repo matching, own-span excluded, was the only pass trusted for deletion.

**Span caveat found along the way:** `plan/periphery.md`'s brace-matched span estimates
are wrong for brace-less one-line declarations (`static let xs: CGFloat = 4` has no `{`,
so the span algorithm over-counts to the next enclosing `}` it finds — e.g. it claimed 13
lines for `Theme.Space.xs`, a single line). Every deletion below was done by reading the
real source around the reported line, never by trusting the `span` number.

Only 18 of 245 came out fully clean (zero hits anywhere outside their own declaration,
whole repo, any file type) — the rest had a base-name collision (same short name reused
elsewhere, e.g. a different type's property, a local variable, a doc-comment mention,
or a genuine same-file caller) that a plain grep can't safely disambiguate from a real
reference without full type-checking. Per the item's rule ("any hit outside its own
definition moves to CHECK, do not delete"), all 227 of those move to CHECK now — most are
probably still genuinely dead (periphery's own SourceKit-based analysis said so), but
proving it needs semantic (not textual) verification that's out of scope here. A follow-up
pass with Xcode's own "Unused" index (or a periphery re-run that already excludes these 18)
could recover more.

### Removed (Q61, 18 items, 150 lines, one commit per folder — see git log `Q61:`)

- Shared/UI/SharedCopy.swift:28 `processSettingsTitle`
- SkriftDesktop/Engines/TranscriptionService.swift:39 `isModelReadySync`
- SkriftDesktop/Features/Settings/SettingsView.swift:574 `chooseSubfolder(_:)`
- SkriftDesktop/Features/Sidebar/QueueDerivations.swift:115 `queueMeta`
- SkriftDesktop/Models/FileDTO.swift:32 `PipelineFile.dto` (+ its now-empty extension)
- SkriftDesktop/Pipeline/WayOutRules.swift:158 `sourceGlyph(for:)`
- SkriftMobile/DesignSystem/Components.swift:18 `SkScreenBackground`
- SkriftMobile/DesignSystem/Components.swift:183 `TagChip` (its only user, `TagChipStyle`, left in place — now itself dead, not on this list)
- SkriftMobile/DesignSystem/Theme.swift:87,91,94,102,116 `Space.xs`, `Space.xl`, `Space.cardGap`, `Radius.editBox`, `timerFont(_:)`
- SkriftMobile/Features/Feedback/FeedbackStore.swift:123,125 `isSent`, `screenshotImage` (`screenshotURL`, its only other user, left in place — now itself dead, not on this list)
- SkriftMobile/Features/MemoDetail/NoteBodyView.swift:598 `spanAt(_:)`
- SkriftMobile/Models/MemoDisplay.swift:336 `pillStyle`
- SkriftMobile/Services/ModelInventory.swift:18 `isDownloaded`

Verified per commit: `./gate.sh` GREEN (894 tests, 0 failures), full Mac build
(`xcodebuild -scheme SkriftDesktop -skipMacroValidation`) exit 0, phone
`plan/mtest.sh QuickNoteRouteTests` exit 0. Nothing reverted — zero red folders.

**Deliberately left alone despite zero code callers:** `Memo.trustConfidenceThreshold` /
`Memo.isTrustedTranscript(userEdited:confidence:)` (Shared/Model/Memo.swift:381,384) — this
is THE trust gate CLAUDE.md names as the sync-contract spine
(`transcriptUserEdited || transcriptConfidence ≥ 0.7`); the rule is duplicated inline at
`MemoSpine.swift:228`, `RoundTripParityTests.swift:48` and `CorpusSeedTests.swift:72`
rather than calling this named implementation, so it reads as dead by the letter of the
scan — too structurally significant to blind-delete on that alone. Left in CHECK below.

### CHECK — Q61 grep re-verification (227), `symbol` list per file, reason: grep found a hit outside its own declaration span

Skrift_Native/Shared/BodyV2 (4)
  BodyNormaliseMigration.swift: offsetMap(from:to:); contentUnits(_:); undoPolished(id:bodies:ledger:now:didRestore:) | BodyV2Thumbnail.swift: BodyV2Thumbnail

Skrift_Native/Shared/Corpus (1)
  CorpusSeed.swift: nameOffsets(folder:)

Skrift_Native/Shared/Export (4)
  ExportProfile.swift: usesWikiEmbeds; imageMarkdown(_:) | VaultWrite.swift: isWrittenOrCurrent; markdownURL

Skrift_Native/Shared/Model (14)
  CaptureQuote.swift: spokenWordCount; lineRanges(in:); markerLength(ofLine:); body(withRamble:) | Memo.swift: addedAt; splitTagInput(_:); trustConfidenceThreshold; isTrustedTranscript(userEdited:confidence:) | MemoEnhancement.swift: isProcessed | MemoLinkSyntax.swift: link(id:title:); targets(in:) | MemoMetadata.swift: Source | NoteDestination.swift: archiveRootKey; resetIfRequested()

Skrift_Native/Shared/Naming (17)
  NameMatch.swift: NameSpan | NamesStore.swift: writeWithSmartBumps(_:); upsert(canonical:aliases:short:); seedRoster(titles:) | SafeJSONStore.swift: quarantinedTo; url; quarantinedTo; at; found; reset() | Sanitiser.swift: prunedKeys; hasCanonicalLink(_:in:); unlinkOccurrence(text:canonical:index:alias:); linkDisplay(_:); relinkOccurrence(text:canonical:index:newCanonical:); unlinkAll(text:canonical:alias:); spokenAlias(for:)

Skrift_Native/Shared/Pipeline (34)
  ASRLanguageMode.swift: settingKey; footer; mode(defaults:) | AlignmentCore.swift: bookWords | AudioRMS.swift: rms(of:) | BodyMarkdown.swift: BodyMarkdown | BodyTransform.swift: displayLength(of:in:); raw; displayRange(forRaw:in:); displayRanges(forRaw:in:); containsTaskSyntax(_:) | DiarizingContract.swift: diarize(audioURL:) | ImageMarkers.swift: ImageMarkers | LookbackProvider.swift: importantLately(for:now:calendar:limit:) | MemoDuplicates.swift: isContentClone(_:of:) | MemoSpine.swift: touchVerb(for:) | NoteWorkState.swift: wantsProcessing | PDFTextExtract.swift: PDFTextExtract | Paragrapher.swift: defaultGap; splitSentences(_:) | ProcessPile.swift: isWaiting(_:enhancedIDs:); isDone(_:enhancedIDs:) | SpeakerTranscript.swift: withPreamble(of:_:); isUnnamed(_:); flattened(_:) | SpeakerTurnStyle.swift: Turn | TranscribingContract.swift: confidence; durationMs; markersInjected; transcribe(buffer:); transcribe(audioURL:); transcribe(buffer:); writeWAV(_:to:) | VocabularyTermParsing.swift: canonical(_:)

Skrift_Native/Shared/Recording (5)
  LiveCaptionEngine.swift: caption(); finish(); finishParts(); shouldRotate(sinceRotation:lastSnapshotCost:interval:); copyBuffer(_:)

Skrift_Native/Shared/Retrieval (11)
  ConnectionWhy.swift: wikiNames(inSanitised:) | EmbeddingEngine.swift: MockEmbedder | EmbeddingIndex.swift: relatedK; gistPairScores(limit:) | RetrievalGate.swift: gate; downloading(fraction:); preparing; indexing(done:total:); finding; ready; derive(enabled:modelDownloaded:downloadFraction:sweeping:sweepProgress:hasRows:querying:) — the last one is a CONFIRMED real catch: it IS called from ConnectionsPanel.swift:58 (multi-line call site), an earlier precise-regex pass missed it

Skrift_Native/Shared/RetrievalEngine (1)
  GemmaEmbedder.swift: unloadNow()

Skrift_Native/Shared/Session (3)
  LockGate.swift: resignObserver; authorizeRemoveLock(); canAuthenticate()

Skrift_Native/Shared/UI (6)
  DestinationRowView.swift: text | NoteMenu.swift: systemImage; lockItem(isLocked:) | Palette.swift: mac | SharedCopy.swift: processingStep(_:_:of:); processingDownload(_:)

Skrift_Native/SkriftDesktop/Engines (7)
  EnhancementService.swift: isModelReady | MacRecorder.swift: isRecording; cancel() | TranscriptionService.swift: models; isModelReady; liveCaption() | VocabularyBooster.swift: replacementCount

Skrift_Native/SkriftDesktop/Features (17)
  JournalView.swift: coordinator | RecordingDraftView.swift: everEdited | ConnectionsPanel.swift: count | PersonEditor.swift: request | AppModel.swift: short; next | LifecycleSweepScheduler.swift: activationObserver | LiveRecordingSession.swift: cancel() | QueueDerivations.swift: shortDF; shortDate(_:) | SidebarView.swift: queuedCount; filled; quietMeta(_:); process(_:); sidebarRowSelection(_:hovering:); StatusPill | Theme.swift: violet

Skrift_Native/SkriftDesktop/Models (1)
  PipelineFile+BodyNormalise.swift: undoBodyNormalise(ledger:cloud:)

Skrift_Native/SkriftDesktop/Pipeline (4)
  DiarizationSidecar.swift: init(segments:slotNames:turnSlots:); load(in:id:) | MemoCloudReconciler.swift: existingFile(id:filename:in:) | MultipartPart.swift: contentType

Skrift_Native/SkriftMobile/App (4)
  LaunchArgs.swift: intValue(_:); destinationsOn; seedArchiveFolder; selectFirstMemo

Skrift_Native/SkriftMobile/DesignSystem (6)
  Theme.swift: sm; md; lg; chip; sheet; group

Skrift_Native/SkriftMobile/Features (35)
  AudiobookPlayerView.swift: token; up; playing | AudiobookSyncSheet.swift: dismiss | BookTextSheet.swift: detent | ChaptersBookmarksSheet.swift: initialTab; ChaptersBookmarksRail | MergedCaptureView.swift: session | SyncedAudiobooksView.swift: repository | FeedbackMailComposer.swift: init(items:onSent:) | FeedbackStore.swift: count; delete(_:); hasScreenshot; durationSeconds; screenshotURL | CaptureQuoteViews.swift: sync | ConnectionsPanel.swift: ordered(_:byDate:) | MemoDetailView.swift: initialID; tight | NoteBodyView.swift: init(memo:onCommit:); displayRange(forRaw:transcript:) | MemosListView.swift: short; next; statusPill; captureGlyph; voiceGlyph; videoGlyph; bookGlyph; quoteText(_:); photoThumb; hasTranscript; hasPhoto; SelectableCard | QuickNoteView.swift: draftID | MemoSaver.swift: importVideoAsync(id:source:fallbackDate:)

Skrift_Native/SkriftMobile/Models (5)
  Memo+BodyNormalise.swift: undoBodyNormalise(enhancement:ledger:) | Memo+Mobile.swift: nameSpans(people:); clearNameResolution(alias:) | MemoDisplay.swift: trashCountdownLabel(now:); rambleSnippet

Skrift_Native/SkriftMobile/Services (47)
  AudiobookAudioTransport.swift: InMemoryAudiobookTransport | AudiobookImporter.swift: importBook(from:libraryDirectory:) | AudiobookSession.swift: sleepLabel; time; shouldResumeAfterInterruption(pausedByInterruption:shouldResumeHint:recordingActive:) | BookAlignment.swift: rejectedFiles | BookBundle.swift: typeIdentifier; bookID | BookTranscriptionJob.swift: levelObserver; starts | CaptureMath.swift: lookback; transcriptionPadding; replayWindow(now:in:); Snapped; closers; terminators; inIndex(starts:words:proposedIn:); CaptureScrub | QuoteCaptureProcessor.swift: spanEnd; bufferOffset; process(bookAudio:span:bookDuration:); TrimResult; applyTrim(output:included:initialIncluded:); isUnchangedTrim(included:sentences:) | CaptureInbox.swift: imageURL(for:entryDir:) | DiarizationService.swift: isModelReady | SpeakerEmbedder.swift: ensureLoaded(); isModelReady; ensureLoaded() | ArchiveVault.swift: clear() | MemoExporter.swift: QuoteCard | ObsidianPublisher.swift: clear() | MemoDeduper.swift: isContentClone(_:of:) | WeatherClient.swift: setAPIKey(_:) | ModelInventory.swift: directory | NotesRepository.swift: restore(_:); delete(_:) | RecordingActivityManager.swift: isRunning | RecordingCheckpoint.swift: recent; mainURL | TranscriptionService.swift: models; multilingualKey; isModelReady; liveCaption(); finishStream(); shouldRotate(sinceRotation:lastSnapshotCost:) | VocabularyBooster.swift: replacementCount

Skrift_Native/SkriftMobile/SkriftShare (1)
  SharePayloadLoader.swift: mimeType
