# Skrift — Feature Source of Truth

One table of every feature across **both** native apps: what it does, which app has
it, where it lives, and its status. This is the canonical map — when you add or change
a feature, **update this file in the same commit**. Linked from `CLAUDE.md`.

Paths are relative to `Skrift_Native/`. Mobile = `SkriftMobile/`, Desktop = `SkriftDesktop/`.

**Status legend:** ✅ shipped · 🟡 partial · 🧩 stub/placeholder · ➖ not present (by design or not yet)

> Generated 2026-06-09 from a full read of both codebases. The contract spine
> (multipart upload, RAW transcript, names LWW) is in `CLAUDE.md` "Hard rules".

---

## Recording & live transcription  *(mobile-owned)*

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Record / pause / resume / stop | ✅ | ➖ | `Features/Recording/RecordView.swift` | Pause hides paused interval from elapsed time. **Instant record (2026-06-11): every entry auto-starts** (FAB, + append, Siri/widget — unified path). ✅ 2026-06-12: legacy ready screen no longer flashes — quiet "Starting…" placeholder while auto-start is in flight; mic-button screen survives only as the empty-stop retry surface (+ ~7 s give-up fallback) |
| Live caption (auto-scroll + color-by-confidence) | ✅ | ➖ | `RecordView.swift` (LiveCaption), `TranscriptionService.liveCaptionParts` | ✅ 2026-06-12: colouring now uses the REAL finalized boundary — words in rotated (committed) chunks render solid (they never re-transcribe), the live chunk lighter; replaces the trailing-6 positional approximation that visibly lied. `[photo N]` tokens are ANCHORED to the words they followed at capture (re-located on rewrite, ±12-word window, clamped fallback) — no more drift |
| Live waveform (40-bar) | ✅ | ➖ | `RecordView.swift:453-480` | |
| Model preload status | ✅ | n/a | `RecordView.swift:271-292` | ✅ 2026-06-09: in-place "model loading" placeholder in the caption during record-while-loading, cleared once words arrive |
| Caption polling | ✅ | ➖ | `Services/Recording/LiveRecordingService.swift:231-243` | 0.6s timer |
| Audio-route-change handling (AirPods pull-out) | ✅ | n/a | `LiveRecordingService.swift` | ✅ 2026-06-12 (rev 2, per the DevLog device-trace verdict): on every route transition the tap is torn down and REINSTALLED in the CURRENT hardware format — the install precondition compares the vended tap format against the SESSION's live hw format (cross-rate rebuilds like AirPods 24k ↔ built-in 48k are ACCEPTED; the per-install `AVAudioConverter` bridges tap→file; only transient 0Hz/0ch or vended≠session-hw states are refused — the earlier hw==old-format check refused all cross-rate rebuilds and recordings went DEAF). Rebuild retries back off ~3 s total and NEVER permanently give up: route-change + `AVAudioEngineConfigurationChange` + media-services-reset observers re-arm the rebuild; resume() also rebuilds if the tap died while paused. Engine restarted + amber notice names the new input. Every decision DevLogged. Also exposes `LiveRecordingService.isRecordingActive` (MainActor static, true incl. paused) so the audiobook player ignores remote-play mid-recording. Unit-tested: format-change decision, tap-install precondition (cross-rate accept + transient refusals), backoff/re-arm contract, converter selection, conversion continuity, active-flag lifecycle (`LiveRecordingRouteChangeTests.swift`) |
| Conversation-mode toggle (diarize this take) | ✅ | ✅ | `RecordView.swift:100-111` · desktop `Models/AppSettings.swift:28-30` | |
| Append to an existing recording | ✅ | ➖ | `MemoDetailView.swift` (`add-recording-button` + ⋯ menu); merge `MemoSaver.swift` | ✅ 2026-06-09: visible top-right **+** button added (also in ⋯ menu); append flow verified |

## Memo detail & playback  *(mobile)* / Review surface *(desktop)*

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Editable transcript | ✅ | ✅ | mobile `MemoDetail/TranscriptEditor.swift`; desktop `Features/Review/BodyTextView.swift` | Both self-sizing native text views w/ inline image attachments + live `[[link]]` styling |
| Keyboard dismiss on scroll | ✅ | n/a | `TranscriptEditor.swift:31`; `MemoDetailView.swift` | ✅ 2026-06-09: outer page ScrollView now `.scrollDismissesKeyboard(.interactively)` too |
| Karaoke (word highlight + tap-to-seek) | ✅ | ✅ | mobile `MemoDetail/TranscriptBodyView.swift`; desktop `Features/Review/NoteBody.swift:74-80` | ✅ 2026-06-12: mobile render path unified into `TranscriptBodyView` (editing / playing / reading modes); captures karaoke the WHOLE memo — quote + ramble, one continuous highlight. Tap-to-seek ON by default (toggle kept). Round 2: quote keeps its styled frame DURING playback (karaoke runs inside `CaptureQuoteFrame`, ramble continues below at `spokenWordCount`); tap-to-seek grid preserves paragraph breaks (`KaraokeWordLayout.lines`, per-line FlowLayout blocks) |
| Playback bar (Liquid Glass) | ✅ | ✅ | mobile `MemoDetailView.swift:603-674`; desktop `Features/Review/NoteDisplayView.swift` | ✅ 2026-06-09: desktop review transport bar is now a floating glass capsule (`.glassEffect(.regular)` macOS 26 + `.ultraThinMaterial` fallback). ✅ 2026-06-12: memo↔book playback exclusion is now MUTUAL — `AudioPlayerModel.nowPlaying` (static weak) lets `AudiobookSession.play()` pause a playing memo; the memo→book direction shipped earlier |
| Title editor | ✅ | ✅ | mobile `MemoDetailView.swift:189-195`; desktop `Features/Review/NoteProperties.swift:25-103` | Desktop = two-title chooser (Suggested vs From-recording) |
| Significance **circles** (gates sync) | ✅ | ✅ | mobile `MemoDetail/SignificanceCircles.swift`; desktop `Features/Review/SignificanceCircles.swift` + `Models/SignificanceScale.swift` | ✅ 2026-06-11: slider → 10 tappable circles (signed-off mock); re-tap clears; tier labels; all three ≥0.8 refine-wall cues. Gating LIVE: 0 = phone-only, >0 syncs |
| Tags add/remove | ✅ | ✅ | mobile `MemoDetailView.swift:201-217`; desktop `NoteProperties.swift:120` | |
| Copy transcript / delete | ✅ | ✅ | `MemoDetailView.swift`; list row swipe/long-press `MemosListView.swift` | 2026-06-11: copy also via row swipe-action + context menu (list-delete now cleans the diar sidecar) |
| Editable summary (review) | n/a | ✅ | desktop `Features/Review/NoteProperties.swift` | 2026-06-11: summary editable like title/tags; export recompiles |
| Speaker turns + name-a-speaker | ✅ | ✅ | mobile `MemoDetail/SpeakerTurnsView.swift`; desktop `Features/Review/InlineResolver.swift` | Mobile inline relabel; desktop ambiguous-name resolver (per-alias + per-occurrence) |
| Context chips (place/weather/time) | ✅ | ✅ | `MemoDetailView.swift:343-357`; desktop frontmatter | |
| Horizontal paging between memos | ✅ | n/a | `MemoDetailView.swift:31-56` | |

## Memos list  *(mobile)* / Sidebar queue *(desktop)*

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| List / queue | ✅ | ✅ | mobile `Features/MemosList/MemosListView.swift`; desktop `Features/Sidebar/SidebarView.swift` | Desktop groups by status (Queued/Transcribed/Ready/Exported) |
| Row label source | ✅ | ✅ | `MemosListView.swift`; `Models/MemoDisplay.swift` | ✅ 2026-06-09: titled memos lead with the user `title` (transcript snippet as secondary); untitled keep transcript-first |
| Status pill (synced/waiting/transcribing) | ✅ | ✅ | `MemosListView.swift`; `Models/MemoDisplay.swift` | ✅ 2026-06-09: significance-0 (phone-only) memos show **no** sync pill; transcribing/error always show; >0 keeps Waiting/Synced |
| Search / sort / filter | ✅ | ✅ | `MemosListView.swift:290-332` | place / has-photos / unsynced filters |
| Multi-select + delete + swipe-to-delete | ✅ | ✅ | `MemosListView.swift:100-105, 146-154` | |
| Trash / Recently Deleted (14-day retention) | ✅ | ✅ | mobile `Models/Memo.swift` (`deletedAt`) + `NotesRepository` + `Features/MemosList/RecentlyDeletedView.swift`; desktop `Models/PipelineFile.swift` (`deletedAt`) + `Pipeline/DesktopTrash.swift` + `Features/Sidebar/RecentlyDeletedView.swift` | ✅ 2026-06-11 mobile; ✅ 2026-06-13 DESKTOP MIRROR: soft-delete keeps the working folder (lossless Restore), 14-day launch purge (`DesktopTrash.purgeExpired`), trashed excluded from sidebar/queue/process AND the phone's `GET /api/files/`; sidebar footer 'Recently Deleted (N)' → restore sheet (Restore / Delete-Now); `-snapshot-trash` verified |
| Sync button + status banner | ✅ | n/a | `MemosListView.swift:161-216` | |

## Photos during recording

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| In-record camera + zoom + shutter | ✅ | n/a | `Features/Recording/CameraSheet.swift` | Camera stays open while recording continues |
| Front/back camera flip | ✅ | n/a | `CameraSheet.swift` (flip button); `Services/Recording/PhotoCaptureService.swift` (`flipCamera`) | 2026-06-11: flip swaps the session input mid-recording; front hides the .5×/1×/2× presets (pinch floored at 1×); photo pipeline unchanged |
| Photo-count badge | ✅ | n/a | `RecordView.swift:227-237` | |
| `[[img_NNN]]` markers in transcript | ✅ | ✅ | mobile `TranscriptEditor.swift:102-122`; desktop `Pipeline/Transcription/ImageMarkers.swift` | Injected at capture offset |
| Inline `[photo N]` token in **live** caption | ✅ | n/a | `RecordView.swift` (LiveCaption) | ✅ 2026-06-09: tinted `[photo N]` token inserted inline at the capture point |
| `[[img]]` → Obsidian embed on export | n/a | ✅ | desktop `Pipeline/Export/VaultExporter.swift:84-114` | |

## Models tab *(on-device model inventory)* — built 2026-06-12

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Settings → Models | ✅ | ➖ | `Services/ModelInventory.swift`, `Features/Settings/ModelsView.swift` | Read-only v1: Transcription (Parakeet v3) / Speaker recognition (diarizer+embedder) / Custom-word spotting (CTC 110M) with downloaded state + size-on-disk + total (FluidAudio cache dirs). Mac mirror = later (board) |

## Custom vocabulary *(CTC keyword-spot + rescore — fixes mis-heard names)* — built 2026-06-12, efficacy-fixed 2026-06-13

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Vocabulary boost pass | ✅ | ✅ | mobile `Services/Transcription/VocabularyBooster.swift`; desktop `Engines/VocabularyBooster.swift` + `BPEMerge.alignWords` | FluidAudio custom-vocab (NeMo arXiv:2406.07096): after `AsrManager.transcribe`, CTC-spot the custom terms in the same samples → token-rescore → take rescored text when modified; word-timings re-aligned positionally so karaoke shows corrected words. One extra ~97.5 MB HF model (ctc110m), lazy-loaded only while the list is non-empty; failures NEVER fail the transcription. LIVE-verified on the two-Jacks file (planted word replaced; real Jacks untouched) |
| **Booster pre-warm (readiness fix)** | ✅ | ✅ | mobile app launch + `VocabularyBooster.prewarm`; desktop `SkriftDesktopApp.init` + `prewarm` | **The 2026-06-13 "Script never → Skrift" fix.** The booster is per-process + non-blocking (it skips the first, model-loading transcribe); the device devlog showed it was NEVER warm when transcription ran (`loaded=[], rescorer=false`) → every recording went unboosted. Now warmed proactively at launch when the custom-word list is non-empty, so the first transcribe is already boosted. Mac-verified: warm → spotter detects + rescorer replaces |
| **Aliases** `"Canonical: alias1, alias2"` | ✅ | ✅ | `VocabularyTermParsing` (both); booster builds `CustomVocabularyTerm(aliases:)` | Mis-heard forms widen the string-similarity gate so a distant mis-hearing still surfaces the canonical — the escape hatch for pairs edit-distance alone misses. Mac-verified: alias `jack` surfaced `Jacques` (sim 0.43, below the 0.50 floor) and replaced |
| **Trust guard (false-positive cut)** | ✅ | ✅ | `VocabularyTrust` + `VocabularySimilarity` (both); booster post-filter | FluidAudio's small-vocab **spotter-anchored rescue** mangles ordinary speech once warm (Mac probe: `room→Rox`, `its alias.→Tiuri` on a clip saying none of them). Can't disable it from outside FluidAudio, so the booster drops a boost when EVERY replacement is a distant acoustic-only guess (sim < 0.55 to canonical AND no alias hit). Mac-verified: negative-control clip left clean; `script→Skrift` (0.667) + aliases kept |
| Custom words list (Settings) | ✅ | ✅ | mobile `Features/Settings/CustomWordsView.swift` + `CustomVocabularyStore` (UserDefaults); desktop Settings → Transcription (`AppSettings.customVocabulary`, optional for legacy decode) | Per-device v1 — no phone↔Mac sync (possible later, names-style). Desktop `-runfile -vocab "A; Canonical: alias"` (entries split on `;`) exercises the pass headlessly with a synchronous prewarm; DEBUG `SKRIFT_VOCAB_CBW`/`SKRIFT_VOCAB_MINSIM` env knobs sweep the gate |

## Capture items *(share URL/text/image into Skrift + annotate)* — built 2026-06-12 (C3 contract)

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| C3 wire contract | ✅ | ✅ | `Skrift_Native/CAPTURE_CONTRACT.md` | Discriminator: zero audio `files` parts + `metadata.sharedContent` → capture. Both apps test against the doc's literal fixture. Memo uploads byte-identical |
| Share extension + sheet | ✅ | n/a | `SkriftShare/` (target), `ShareSheetView`, `SharePayloadLoader` | Mock state 1: preview per type (url card / text quote / image thumb), annotation, significance circles + sync line, Save. 2026-06-12 UX pass: forced-dark (`overrideUserInterfaceStyle`), keyboard avoidance (.container-scoped safe area) + Done bar, capped editor height, full-sheet dark canvas (`preferredContentSize`) |
| Voice dictation in the sheet | ✅ | n/a | `SkriftShare/ShareDictationRecorder` (record), `Services/Capture/CaptureDictation` (transcribe on drain) | The mock's mic, deferred-transcription design: the extension only RECORDS (Parakeet can't fit its memory ceiling); audio rides the inbox; the app transcribes on drain → appends to annotationText, audio discarded on success / kept as retry source on `.failed` (Error pill, re-kicked each drain). Sync holds captures until `.done`; capture detail swaps the annotation editor out while transcribing (clobber window) |
| App Group inbox → Memo | ✅ | n/a | `Services/Capture/CaptureInbox.swift` + `CaptureInboxDrainer` | `group.com.skrift.mobile(.dev)` via `SKRIFT_APP_GROUP` build setting → entitlements + `SkriftAppGroup` Info.plist key BOTH targets (the key must be in the APP's plist too — its absence crashed launch). Drain on launch + foreground; idempotent, delete-after-save |
| Capture upload (no audio) | ✅ | ✅ | mobile `UploadPayload.buildCapture` + `SyncCoordinator`; desktop `UploadService.ingestCapture` | Same endpoint/gate (significance>0); image rides the existing `images` part + manifest |
| Pipeline: skip + enhance-lite | n/a | ✅ | `BatchRunner.runCapture`, `captureFallbackTitle` | No ASR/diarize/copy-edit; title+tags+summary+name-link on the annotation; empty annotation → fallback title (urlTitle → text head → filename) |
| Compile/export | n/a | ✅ | `Compiler.captureSharedBlock`, `VaultExporter.copyCaptureFolderImages` | frontmatter `source: capture-url/text/image` + `url:` key; pinned block (bold title+URL / blockquote / `![[embed]]`) above the annotation body |
| Review surface (Mac) | n/a | ✅ | `Features/Review/CaptureViews.swift` (source strip, banner, shared-content card), `NoteProperties` url row, `QueueDerivations` glyphs | Mock state 3; verify via `-snapshot-capture <path>` |
| List/detail (phone) | ✅ | n/a | `MemoDisplay` shareCapture helpers, `MemosListView`, `MemoDetailView` | Mock state 2: glyph rows + domain chip; detail = pinned card (Open ↗) + editable annotation body; player bar/append/split hidden (no audio) |

## Text-first quote capture *(A/B alternative to audio-marking)* — wave 1 built 2026-06-13

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Capture-style toggle (A/B) | ✅ | n/a | `Models/AudiobookCaptureStyle.swift`, Settings → Audiobooks | `@AppStorage` default **.audio** (proven); Text opt-in. The capture flow routes on it |
| Text sentence-select screen | ✅ | n/a | `Features/Audiobooks/TextCaptureView.swift` (pure `TextCaptureSelection` + `TextCaptureMath.globalSpan`) | Scroll the ~90 s window; tap a grey line's **+** to add / an end line's **✕** to drop; last line pre-picked; CTA tonal-until-touched; 1.5× preview; warming + empty states. Per signed-off mock `text-capture.html` |
| Window transcribe-for-display | ✅ | n/a | `QuoteCaptureProcessor.transcribeWindowForDisplay` | Exports + transcribes the playhead window → sentences (reuses exportSpan + buildSentences); buffer kept for the preview. Real ASR device-owed |
| Shared-seam routing | ✅ | n/a | `QuoteCaptureFlowView` (`.adjust` branch; `confirmCapture(_:span:)`) | Both modes emit a GLOBAL span → SAME processor/sheet/save/sync/export. Removing Text later = delete the view + branch + toggle |
| **Wave 2 — book transcript sidecar** | ✅ | n/a | `Services/Audiobooks/BookTranscript.swift` (`FileTranscript` pure math) + `BookTranscriptStore.swift` | Per-book, per-file sidecar `Documents/audiobooks/<id>/transcript_f<n>.json`. Time basis (fileIndex, file-local); stores word-timings, sentences derived on read via the SAME `buildSentences`. `coveredUpTo` frontier = resume state. Staleness keyed by `size:mtime` (re-import invalidates). Atomic per-file write so a capture never reads a torn chunk |
| **Wave 2 — chunk-seam fusion** | ✅ | n/a | `Services/Audiobooks/ChunkFusion.swift` | Cut at the last complete sentence (`SentenceSnap.sentenceStartIndices`); re-transcribe the trailing partial from a clean start next chunk → no split/duplicated words at the seam, no fragile overlap-agreement. Run-on/silence fallbacks. Unit-tested |
| **Wave 2 — resumable transcribe job** | ✅ | n/a | `Services/Audiobooks/BookTranscriptionJob.swift` | Sequential per-file chunk loop; saves each fused chunk atomically before the next (= resume; in-flight chunk discarded on interruption). Charger job: pauses on unplug, auto-resumes on charge; foreground Pause/Resume. Yields to live capture between chunks (`suspendForCapture`). Engine path device-owed |
| **Wave 2 — "Transcribe book" button + sheet** | ✅ | n/a | `Features/Audiobooks/TranscribeBookView.swift`; player ⋯ menu (Text mode only) | Progress bar + % + Start/Pause/Resume; copy per design §12/§13 ("keep listening — capture works for done parts" lede, "best overnight, plugged in", "resumes if interrupted", "leave any time"). Hidden in Audio mode (sidecar only feeds Text) |
| **Wave 2 — instant capture from sidecar** | ✅ | n/a | `TextCaptureView` (Source `.sidecar`/`.window`) + `QuoteCaptureProcessor.buildOutputFromSidecar` + `BookTranscriptStore.coveredWindowWords` | A chunked spot reads sentences from the sidecar (no engine, no warm-up, no contention) and exports the quote span straight from the book file on confirm; an un-chunked spot falls back to the wave-1 live window transcribe. `QuoteCaptureOutput` seam unchanged |
| **Wave 2 — pre-warm on book-open** | ✅ | n/a | `AudiobookPlayerView.prewarmIfUseful` | Text mode + un-chunked playhead spot → warm the engine on player-open (background) so the 35 s warming screen rarely shows; skipped when the spot is already chunked (capture is instant, warming would just pin memory). Live capture also pauses the bg job (`QuoteCaptureFlowView`) |
| **Wave 2 — real per-device speed** | ✅ | n/a | `BookTranscriptionJob` measured RTF (persisted) → `TranscribeBookView` estimate | Job times each chunk → live real-time factor, persisted; the sheet shows "≈ N min left"/"≈ N min per hour" from the MEASUREMENT (placeholder removed; nothing shown until a device rate exists). Per-chunk timing also DevLog'd. Mac `-asrbench`: ~100–134× realtime (inference is tiny vs audio); phone absolute number device-measured |

## Audiobook player — text-forward redesign *(A+D hybrid)* — built 2026-06-13

Signed-off mock: `Skrift_Native/SkriftDesktop/mocks/audiobook-player-redesign.html`.

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Read-along text panel | ✅ | n/a | `Features/Audiobooks/ReadAlongView.swift` (+ `BookTranscriptStore.fileTranscript`) | The hero: narration around the playhead from the wave-2 sidecar, CURRENT sentence lit (past fades, a little upcoming trails). Window cached; lit line recomputed per 0.5 s tick (disk I/O only on window change). Un-chunked spot → "Transcribe to read along" nudge → `TranscribeBookView` (growth loop). Real text device-owed (sim has no ASR) |
| Player relayout | ✅ | n/a | `Features/Audiobooks/AudiobookPlayerView.swift` | Cover-tint header (`UIImage.averageColor`, darkened to the cover's hue) + 56 px cover chip + `Ch N/M` pill; speed◁ ⟲15 ▶ 15⟳ ▷sleep; slim Chapters + Bookmark row; hero "Capture this". Swipe-down dismiss + capture seam preserved |
| Bookmarks (lightweight) | ✅ | n/a | `Services/Audiobooks/Bookmark.swift` (`AudiobookBookmark` + `BookmarkStore`) | Tap Bookmark → drops a marker (global position + chapter label + timestamp), haptic + toast, near-dupe guard (±2 s). Per-book `bookmarks.json`, atomic. NOT a rich save — Capture is that. 6 unit tests |
| Chapters / Bookmarks sheet | ✅ | n/a | `Features/Audiobooks/ChaptersBookmarksSheet.swift` | TOC sheet, Chapters | Bookmarks tabs. Chapters promoted out of the ⋯ menu (couldn't find them there) → tap to seek, current marked. Bookmarks: tap to jump, swipe to delete |

## Audiobook quote-capture *(mobile player + capture; desktop pipeline)* — built 2026-06-11

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Audiobook library + player (Bound-style) | ✅ | n/a | `Features/Audiobooks/*`, `Services/Audiobooks/*` | Files/iCloud import (copy into app), tags/cover/m4b chapters, per-book resume, speed, sleep timer, background + lock-screen transport (`AudiobookSession`); readable multi-file chapter titles (`ChapterDisplay` — LCP-strip + "Chapter N" prettify, 2026-06-12); Edit book details after import (player ⋯ → `EditBookDetailsView`: title/author/cover via PhotosPicker, falls back to current art; persists via store + live `refreshFromStore`, 2026-06-12) |
| Retroactive quote capture | ✅ | n/a | `CaptureMomentView` (micro-scrubber + grains), `CaptureMath` (span + OUTWARD sentence-snap), `QuoteCaptureProcessor` | Capture proposes [pause−30s→pause]; span±20s transcribed on demand; quote audio = the memo's audio. Round 2 (2026-06-12): all labels BOOK time, pan = window only (handle drags window-confined, no edge-bump), "⟲ pause point" jump-back, grains only mid-drag + mute toggle, audio session untouched until first drag |
| Capture sheet (ramble-first) | ✅ | n/a | `CaptureSheetView`; ramble = `RecordView(appendTo:)` | Big record-your-thoughts, Save & keep listening, circles; book auto-pauses/resumes; long quotes scroll in a bounded block (2026-06-12) |
| Conditional mini-player + list integration | ✅ | n/a | `AudiobookMiniPlayerBar` (C3), mounted in `MemosListView` | Exists only while a session is active; FAB nudges up; capture rows = book glyph + italic ❝-quote lead. 72pt bar (2026-06-12, replaces the oversized 104pt): cover 48, transport 40/17pt, Capture pill 12pt bold wrap-proof (fixedSize+lineLimit), chevron 30×40 — width-budget arithmetic in the source. Remote/AirPods play is IGNORED while a recording is live (`LiveRecordingService.isRecordingActive` guard, session priority) |
| Capture memo rendering (detail) | ✅ | n/a | `MemoDetail/TranscriptBodyView.swift` + `CaptureQuote` (`Models/MemoDisplay.swift`) | ✅ 2026-06-12: ONE 3-mode component — editing = styled quote (accent bar + attribution) above the quote-protected ramble editor; playing = continuous karaoke through the quote (LIVE inside its styled `CaptureQuoteFrame`, words 0..N) then the ramble (from `spokenWordCount`) — no restyle jump on play; reading (transcribing) = styled quote + pill, no editor |
| Book metadata contract (C2) | ✅ | ✅ | mobile `MemoMetadata`/`UploadPayload` (+bookTitle/bookAuthor/bookChapter, additive); desktop `Compiler.swift` PhoneMetadata | Byte-compatible; absent = old behavior |
| Quote protection in enhancement | n/a | ✅ | `Pipeline/Enhancement/QuoteProtection.swift`, `EnhancementService`, `BatchRunner` (byte-assert gate) | Copy-edit touches ONLY the ramble; quote byte-identical or full fallback to unedited |
| Quote export (italics + attribution) | n/a | ✅ | `Compiler.swift` | `> — [[Author]], *Book*, ch. N` inside the blockquote; `[[Author]]` written at export only (never in names DB); frontmatter book/bookAuthor/chapter |
| Resolver per-occurrence INSTANT apply | n/a | ✅ | `Sanitiser.applyPartialOccurrences`, `InlineResolver`, `NoteDisplayView` | Each pick renders immediately (document-order demotion correct); "N of M assigned" progress |

## Names & voices  *(both — synced)*

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Names list + add/edit/delete | ✅ | ✅ | mobile `Features/Names/NamesListView.swift`; desktop `Features/Settings/SettingsView.swift:93-129` | |
| Names LWW sync (union voiceEmbeddings) | ✅ | ✅ | `Models/NamesData.swift:147-177` (desktop) | byte-compatible both apps |
| Voiceprint enrollment | 🧩 | ✅ | mobile `Features/Names/PersonDetailView.swift:99-136` | **Mobile = placeholder** (enroll only via conversation naming). Direct "record a sample" enroll is a backlog item |
| Voice match (cosine, thr 0.5) | ✅ (match) | ✅ | desktop `Pipeline/Diarization/VoiceMatcher.swift:19-42` | |

## Diarization / conversation mode

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Diarize (Sortformer) + fuse to turns | 🟡 | ✅ | desktop `Engines/DiarizationService.swift`, `Pipeline/Diarization/SpeakerFusion.swift` | Mobile records w/ conversation toggle; heavy fusion is desktop-side |
| Split-speakers on an existing memo | ✅ (button) | ✅ | mobile `MemoDetailView.swift` (`split-speakers-button` → How-many-speakers); desktop pipeline | Mobile = dedicated toolbar button + Auto/N dialog |
| Persist diarization segments (for later enrollment) | n/a (phone keeps `diar_<id>.json`) | ✅ | desktop `Models/PipelineFile.swift` (`diarizationSegments`) + `Pipeline/BatchManager/DiarizationSidecar.swift` | ✅ 2026-06-09: written by BatchRunner; byte-mirrors the phone sidecar — unblocks Mac "name a speaker" |

## Sync & contract  *(the spine)*

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Significance-gated upload (flag-to-send) | ✅ | ✅ (reads) | mobile `Services/Sync/SyncCoordinator.swift:34`; desktop `Pipeline/Ingest/UploadService.swift:44-46` | **LIVE**: only `significance > 0` uploads. Desktop pre-fills its slider from the sent value |
| Multipart `POST /api/files/upload` (RAW transcript, never sanitised) | ✅ | ✅ | desktop `Server/SyncHandlers.swift:37-38`, `UploadService.swift` | reads `title`, `significance`, `transcriptUserEdited`, `transcriptConfidence`, `imageManifest` |
| Names meta/get/put + LWW | ✅ | ✅ | `SyncHandlers.swift:55-71` | |
| Bonjour discovery / advertise | ✅ | ✅ | mobile `Features/Settings/PairMacView.swift`; desktop `Server/SyncServer.swift:51-64` | Desktop advertises unique host name; phone resolves IPv4 |
| Health endpoint | ✅ | ✅ | `SyncHandlers.swift:50-53` | reports FluidAudio "parakeet" availability |

## Ingest / import

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Audio file import (share / open-in) | ✅ | ✅ | mobile `App/AppURLHandler.swift`, `MemoSaver.swift:39-69`; desktop `Pipeline/Ingest/IngestService.swift:41-61` | |
| Folder / drag-drop ingest | n/a | ✅ | desktop `SidebarView.swift:39-62`, `IngestService.swift:201-211` | |
| Apple-Notes import (+HEIC→JPG relink) | n/a | ✅ | desktop `IngestService.swift:63-94, 128-170` | |
| **Video import → audio + 1 frame thumbnail** | ✅ | ✅ | mobile `App/AppURLHandler.swift`, `Features/Recording/MemoSaver.swift` (`importVideo`), `Features/Import/VideoImportPicker.swift`; desktop `IngestService.swift` (`ingestVideo`/`hasVideoTrack`/`extractAudioSync`/`embeddedRecordingDate`), `UploadService.swift` | Share/open-in or pick a video → strip audio to `.m4a` + grab one frame as `[[img_001]]`. `recordedAt` = the video's EMBEDDED creation date (not import time). `backlog.md:15` |
| Capture items (share URL/text/image) | ➖ | ➖ | — | Big deferred cross-app feature (`backlog.md:73`) |

## Transcription engine *(desktop in-process)* / on-device *(mobile)*

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| FluidAudio / Parakeet ASR | ✅ | ✅ | desktop `Engines/TranscriptionService.swift` | word timings, phantom-transcript guard |
| Audio preprocessing (high-pass + normalize) | — | ✅ | desktop `Engines/AudioPreprocessor.swift` | `highpassFreqHz`, default 80 Hz |
| BPE merge / image-marker injection | — | ✅ | desktop `Pipeline/Transcription/BPEMerge.swift`, `ImageMarkers.swift` | |

## Enhancement (Gemma 4 E4B, mlx-swift) *(desktop)*

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Copy-edit / title / summary | ➖ | ✅ | `Engines/EnhancementService.swift:49-65` | runs on RAW transcript; `[[img]]` stripped + reinserted via anchors |
| Prompt templates (configurable) | ➖ | ✅ | `Models/AppSettings.swift:37-76` | |

## Name-linking, tagging, export *(desktop)*

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Sanitiser (alias→`[[Canonical]]`, ambiguity) | ➖ | ✅ | `Pipeline/Sanitisation/Sanitiser.swift:21-90` | per-alias + per-occurrence ("two Jacks") resolver |
| Unlink a `[[Name]]` (click a linked mention) | ➖ | ✅ | `Features/Review/BodyTextView.swift` (popover), `NoteDisplayView.swift` (apply + undo toast), `Sanitiser.swift` (`unlinkOccurrence`/`unlinkAll`/`process(neverLink:)`) | Per signed-off `mocks/name-unlink.html`: exactly TWO scopes — this mention → plain alias as spoken (possessive kept), or all mentions in this note (persists on `PipelineFile.unlinkedNames` so reprocess won't re-link). Inline undo toast stays until dismissed |
| Deterministic tags (NLTagger lemma + spoken #) | ➖ | ✅ | `Pipeline/Tags/TagMatcher.swift` | |
| Vault tag scan (privacy: app-only) | ➖ | ✅ | `Pipeline/Tags/VaultTagScanner.swift:13-72` | |
| Compile Obsidian markdown (YAML frontmatter) | ➖ | ✅ | `Pipeline/Export/Compiler.swift:24-87` | title/date/author/source/location/weather/tags/significance/summary |
| Export to vault + **copy audio** (per-note toggle) | ➖ | ✅ | `Pipeline/Export/VaultExporter.swift:20-79`; toggle `NoteProperties.swift:127-140` | `includeAudioInExport` (default on) → copies `.m4a` to audio subfolder |

## Settings / onboarding

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Settings | ✅ | ✅ | mobile `Features/Settings/SettingsView.swift`; desktop same path | Desktop adds vault/author/model/prompts/preprocessing |
| First-run setup | ✅ (onboarding) | ✅ (wizard) | mobile `Features/Onboarding/OnboardingView.swift`; desktop `Features/Settings/SetupWizardView.swift` | |
| Theme (Light/Dark/Auto) | ✅ | ✅ | `SettingsView.swift` | |
| Auto-copy transcript to clipboard | ✅ | ➖ | mobile `SettingsView.swift` (toggle); `MemoSaver.swift` (`autoCopyIfEnabled`) | 2026-06-11: opt-in, **default OFF** (user-locked). On transcription success (record/import/append) the final transcript lands on the pasteboard; appends copy the combined text |
| Send feedback (record+type+screenshot→Mail) | ✅ | ➖ | mobile `Features/Feedback/FeedbackCaptureView.swift` | Desktop port deferred |

## Widgets / intents / share *(mobile)*

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Live Activity + Dynamic Island (record) | ✅ | n/a | `SkriftWidget/SkriftLiveActivity.swift` | Stop button intent |
| Start-recording intent (Siri / Control Center) | ✅ | n/a | `App/Intents/StartRecordingIntent.swift` | plain `AppIntent` + `openAppWhenRun` (SIGTRAP-safe) |
| Lock/Home record widget · `skrift://record` | ✅ | n/a | `SkriftWidget/RecordWidget.swift`, `AppURLHandler.swift:20-22` | |

## Metadata / sensors *(mobile)*

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Location / weather / day-period / steps / pressure | ✅ | (consumes) | mobile `Services/Metadata/*`; desktop `Compiler.swift:3-17` (PhoneMetadata) | Phone captures, Mac renders into frontmatter |

---

## Known targets (open work as of 2026-06-09)
See `backlog.md` for the full list. Active batch:
- **B (mobile record screen):** model-loading placeholder, live auto-scroll, color-by-confidence, inline `[photo N]`, AirPods route-change robustness, append-flow verify, keyboard-dismiss-on-scroll.
- **A (mobile list):** surface user `title` on rows; suppress "Waiting" on significance-0 memos.
- **C (cross-app):** video import → audio extraction (mobile import path + desktop ingest).
- **D (desktop):** Liquid Glass pass (player bar / sidebar).
