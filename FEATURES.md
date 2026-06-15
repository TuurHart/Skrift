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
| Conversation-mode toggle (diarize this take) | ✅ | ✅ | `RecordView.swift:100-111` · desktop `Models/AppSettings.swift` (`conversationModeEnabled`), `ProcessingCoordinator.flattenToMonologue`, `SpeakerTranscript.flattened` | ✅ 2026-06-15: desktop conversation mode now DEFAULTS OFF (`conversationMode ?? false`) — it was a blunt global auto-diarize that over-split MONOLOGUES into Speaker 1/2. Added **"Flatten to monologue"** (review row menu): drops the `**Speaker N:**` headers → prose, clears diarization, re-enhances as a monologue (no re-ASR). Per-note "Split speakers" (on-demand opt-in diarize) is the remaining fast-follow (`backlog.md`) |
| Append to an existing recording | ✅ | ➖ | `MemoDetailView.swift` (`add-recording-button` + ⋯ menu); merge `MemoSaver.swift` | ✅ 2026-06-09: visible top-right **+** button added (also in ⋯ menu); append flow verified |

## Memo detail & playback  *(mobile)* / Review surface *(desktop)*

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Editable transcript | ✅ | ✅ | mobile `MemoDetail/TranscriptEditor.swift`; desktop `Features/Review/BodyTextView.swift` | Both self-sizing native text views w/ inline image attachments + live `[[link]]` styling |
| Keyboard dismiss on scroll | ✅ | n/a | `TranscriptEditor.swift:31`; `MemoDetailView.swift` | ✅ 2026-06-09: outer page ScrollView now `.scrollDismissesKeyboard(.interactively)` too |
| Karaoke (word highlight + tap-to-seek) | ✅ | ✅ | mobile `MemoDetail/TranscriptBodyView.swift`; desktop `Features/Review/NoteBody.swift:74-80` | ✅ 2026-06-12: mobile render path unified into `TranscriptBodyView` (editing / playing / reading modes); captures karaoke the WHOLE memo — quote + ramble, one continuous highlight. Tap-to-seek ON by default (toggle kept). Round 2: quote keeps its styled frame DURING playback (karaoke runs inside `CaptureQuoteFrame`, ramble continues below at `spokenWordCount`); tap-to-seek grid preserves paragraph breaks (`KaraokeWordLayout.lines`, per-line FlowLayout blocks) ✅ 2026-06-15: desktop **click-a-word seeks to that word's REAL start time** (was an index-proportional seek → landed on the wrong word when speech is uneven, e.g. a silent intro; `KaraokePlayback.seekWord`). |
| Playback bar (Liquid Glass) | ✅ | ✅ | mobile `MemoDetailView.swift:603-674`; desktop `Features/Review/NoteDisplayView.swift` | ✅ 2026-06-09: desktop review transport bar is now a floating glass capsule (`.glassEffect(.regular)` macOS 26 + `.ultraThinMaterial` fallback). ✅ 2026-06-12: memo↔book playback exclusion is now MUTUAL — `AudioPlayerModel.nowPlaying` (static weak) lets `AudiobookSession.play()` pause a playing memo; the memo→book direction shipped earlier |
| Title editor | ✅ | ✅ | mobile `MemoDetailView.swift:189-195`; desktop `Features/Review/NoteProperties.swift:25-103` | Desktop = two-title chooser (Suggested vs From-recording) |
| Significance **circles** (gates sync) | ✅ | ✅ | mobile `MemoDetail/SignificanceCircles.swift`; desktop `Features/Review/SignificanceCircles.swift` + `Models/SignificanceScale.swift` | ✅ 2026-06-11: slider → 10 tappable circles (signed-off mock); re-tap clears; tier labels; all three ≥0.8 refine-wall cues. Gating LIVE: 0 = phone-only, >0 syncs |
| Tags add/remove | ✅ | ✅ | mobile `MemoDetailView.swift:201-217`; desktop `NoteProperties.swift:120` | |
| Copy transcript / delete | ✅ | ✅ | `MemoDetailView.swift`; list row swipe/long-press `MemosListView.swift` | 2026-06-11: copy also via row swipe-action + context menu (list-delete now cleans the diar sidecar) |
| Editable summary (review) | n/a | ✅ | desktop `Features/Review/NoteProperties.swift` | 2026-06-11: summary editable like title/tags; export recompiles |
| Speaker turns + name-a-speaker | ✅ | ✅ | mobile `MemoDetail/SpeakerTurnsView.swift` (`relabelSlot`) + `DiarizationStore` (`turnSlots`); desktop `Features/Review/InlineResolver.swift` | Mobile inline relabel; desktop ambiguous-name resolver (per-alias + per-occurrence). ✅ 2026-06-15: rename/enroll are **slot-aware** — a per-turn slot map (`turnSlots` in the diar sidecar) means naming one of two same-named speakers (one voice split into two slots) renames + enrolls ONLY that slot, not its twin (was: relabeled both + enrolled an arbitrary slot's audio). Falls back to name-based after a structural edit |
| Context chips (place/weather/time) | ✅ | ✅ | `MemoDetailView.swift:343-357`; desktop frontmatter | |
| Horizontal paging between memos | ✅ | n/a | `MemoDetailView.swift:31-56` | |

## Memos list  *(mobile)* / Sidebar queue *(desktop)*

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| List / queue | ✅ | ✅ | mobile `Features/MemosList/MemosListView.swift`; desktop `Features/Sidebar/SidebarView.swift` | Desktop groups by status (Queued/Transcribed/Ready/Exported) |
| Row label source | ✅ | ✅ | `MemosListView.swift`; `Models/MemoDisplay.swift` | ✅ 2026-06-09: titled memos lead with the user `title` (transcript snippet as secondary); untitled keep transcript-first ✅ 2026-06-15: EVERY row carries a leading source glyph (voice memos wear a mic, like the Mac sidebar) — video/link/text/image/book already had theirs. |
| Status pill (synced/waiting/transcribing) | ✅ | ✅ | `MemosListView.swift`; `Models/MemoDisplay.swift` | ✅ 2026-06-09: significance-0 (phone-only) memos show **no** sync pill; transcribing/error always show; >0 keeps Waiting/Synced |
| Search / sort / filter | ✅ | ✅ | mobile `MemosListView.swift` (`MemoSort`, `MemoFilter`, `matchesFilter`, `groupDate`); desktop `AppModel.swift` (`QueueFilter`, `matchesFilter`, `matchesSearch`, `SidebarSort`, `visible`), `SidebarView.swift` (`searchField`, `sortControl`, `noMatches`) | ✅ 2026-06-15 desktop BRIDGED: sidebar text search (title/transcript/summary) + a Newest/Oldest/Title sort cycle + a "No matches" empty state, on top of the 3-way `QueueFilter`. Live-verified (`SidebarSearchSortUITests`; the sidebar can't be `-snapshot`'d — ImageRenderer chokes on its drop-catcher). Mobile keeps its 5 sort modes + multi-axis filters. **2026-06-14:** sorts = **Recently added** (default) / Recently edited / Recently recorded / Oldest / Longest — backed by `Memo.createdAt` (when it entered Skrift) + `Memo.editedAt` (bumped on title/transcript/tags/append edits); both nil-default → legacy memos fall back to `recordedAt` (no migration). Day-headers follow the active sort (`groupDate`). Filters: place / has-photos / unsynced + a **date range** (pick Recorded or Added, from/to). `recordedAt` stays the content's true date (so a shared video keeps its filming date but sorts to the top under "added") |
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
| **Trust guard (false-positive cut)** | ✅ | ✅ | `VocabularyTrust` + `VocabularySimilarity` (both); booster post-filter | FluidAudio's small-vocab **spotter-anchored rescue** mangles ordinary speech once warm (Mac probe: `room→Rox`, `its alias.→Tiuri` on a clip saying none of them). Can't disable it from outside FluidAudio, so the booster gates the boost in `VocabularyBooster.allReplacementsTrusted`. ✅ 2026-06-15 TIGHTENED (both apps) after a device repro garbled "hello testing testing…my book is skrift" → "Tuur Skrift Tiuri Tuur…Skrift Skrift": was "keep if ANY replacement trusted" (one real custom word let the whole over-corrected mix through); now **keep ONLY when EVERY applied replacement is trusted** (string-similar to canonical OR alias hit) — one distant rescue drops the WHOLE boost → clean unboosted transcript. Genuine corrections stay (trusted); add a mishear as an alias to make its rescue trusted. Mac-verified earlier: `script→Skrift` + aliases kept |
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
| ~~Capture-style toggle (A/B)~~ | — | n/a | _(removed 2026-06-13)_ | A/B concluded — text capture won; `AudiobookCaptureStyle` + the Settings toggle deleted. The merged screen is the only capture flow |
| Build-your-quote selection | ✅ | n/a | `MergedCaptureView`; pure `TextCaptureSelection` + `TextCaptureMath` in `Models/TextCaptureSelection.swift` | Scroll the ~90 s window; tap a grey line's **+** to add / an end line's **✕** to drop; last line pre-picked. Now lives INSIDE the merged note-style screen (standalone `TextCaptureView` retired 2026-06-13). **Bidirectional + bounded (2026-06-14): the tapped line is the pre-picked anchor in the MIDDLE — the ~90 s you heard BEFORE it + up to 8 lines AFTER (transcribed) / 4 (un-chunked). Scroll up to quote earlier, down to quote a little later (past the tap; the post-pause audio exists). NO infinite scroll. `sel` indexes the full sidecar array; only the bounded slice is displayed.** |
| Window transcribe-for-display | ✅ | n/a | `QuoteCaptureProcessor.transcribeWindowForDisplay` | Exports + transcribes the playhead window → sentences (reuses exportSpan + buildSentences); buffer kept for the preview. Real ASR device-owed |
| Capture flow host | ✅ | n/a | `QuoteCaptureFlowView` (thin host → `MergedCaptureView`) | Pauses the bg transcribe + warms ASR on open; resumes the book + dismisses on finish/cancel. ALL capture → the merged screen; the audio mark-in/out branch + sheet are retired |
| **Wave 2 — book transcript sidecar** | ✅ | n/a | `Services/Audiobooks/BookTranscript.swift` (`FileTranscript` pure math) + `BookTranscriptStore.swift` | Per-book, per-file sidecar `Documents/audiobooks/<id>/transcript_f<n>.json`. Time basis (fileIndex, file-local); stores word-timings, sentences derived on read via the SAME `buildSentences`. `coveredUpTo` frontier = resume state. Staleness keyed by `size:mtime` (re-import invalidates). Atomic per-file write so a capture never reads a torn chunk |
| **Wave 2 — chunk-seam fusion** | ✅ | n/a | `Services/Audiobooks/ChunkFusion.swift` | Cut at the last complete sentence (`SentenceSnap.sentenceStartIndices`); re-transcribe the trailing partial from a clean start next chunk → no split/duplicated words at the seam, no fragile overlap-agreement. Run-on/silence fallbacks. Unit-tested |
| **Wave 2 — resumable transcribe job** | ✅ | n/a | `Services/Audiobooks/BookTranscriptionJob.swift` | Sequential per-file chunk loop; saves each fused chunk atomically before the next (= resume; in-flight chunk discarded on interruption). Charger job: pauses on unplug, auto-resumes on charge; foreground Pause/Resume. Yields to live capture between chunks (`suspendForCapture`). ✅ 2026-06-15: **runs on battery** (not charger-gated) — auto-pauses only to conserve (Low Power Mode or charge < 20%, `shouldConserve`/`powerStateChanged`), auto-resumes on charge/recovery; observes battery state + level + `NSProcessInfoPowerStateDidChange`. **Chunks extracted with sample-accurate `extractPCM` (AVAudioFile frame read → WAV), NOT `AVAssetExportSession`** — the latter drifts word-times late on compressed audio, growing with seek depth (read-along trailed ~+2 s deep in a chapter; Mac `-chunksim` proof). `FileTranscript` schema 1→2 invalidates v1 drifted sidecars. Engine path device-owed. ✅ 2026-06-15: **background continuation** via `BookBackgroundScheduler` (BGProcessingTask `com.skrift.booktranscribe`, `requiresExternalPower`) — registered at launch, scheduled when the app backgrounds with a job in flight, resumes the job in the handler until done or the OS window expires (then re-schedules). Best-effort/overnight-charging; jetsam just resumes from the saved chunk (benign). **Device-test owed** (can't verify background/overnight on the sim) |
| **Wave 2 — "Transcribe book" button + sheet** | ✅ | n/a | `Features/Audiobooks/TranscribeBookView.swift`; player ⋯ menu (Text mode only) | Progress bar + % + Start/Pause/Resume; copy per design §12/§13 ("keep listening — capture works for done parts" lede, "best overnight, plugged in", "resumes if interrupted", "leave any time"). Hidden in Audio mode (sidecar only feeds Text) |
| **Wave 2 — instant capture from sidecar** | ✅ | n/a | `TextCaptureView` (Source `.sidecar`/`.window`) + `QuoteCaptureProcessor.buildOutputFromSidecar` + `BookTranscriptStore.coveredWindowWords` | A chunked spot reads sentences from the sidecar (no engine, no warm-up, no contention) and exports the quote span straight from the book file on confirm; an un-chunked spot falls back to the wave-1 live window transcribe. `QuoteCaptureOutput` seam unchanged |
| **Wave 2 — pre-warm on book-open** | ✅ | n/a | `AudiobookPlayerView.prewarmIfUseful` | Text mode + un-chunked playhead spot → warm the engine on player-open (background) so the 35 s warming screen rarely shows; skipped when the spot is already chunked (capture is instant, warming would just pin memory). Live capture also pauses the bg job (`QuoteCaptureFlowView`) |
| **Merged capture screen** *(2026-06-13 redesign)* | ✅ | n/a | `Features/Audiobooks/MergedCaptureView.swift`; `QuoteCaptureFlowView` hosts it | ONE note-style screen (signed-off mock `audiobook-capture-merged.html`): header (❝ + book·ch) → the real `SignificanceCircles` card → build-your-quote sentence rows (reuses `TextCaptureSelection`) → Record-your-thoughts pinned. Tap record → build quote from selection → `saveQuoteCapture` → apply significance → `RecordView(appendTo:)` → recorder dismiss auto-resumes the book + lands as the normal note (NO preview; the append is fire-and-forget). Always records voice; a bail before recording discards the quote-only memo. ALL capture routes here — the audio mark-in/out arm is retired (chunk 3) |
| **Wave 2 — real per-device speed** | ✅ | n/a | `BookTranscriptionJob` measured RTF (persisted) → `TranscribeBookView` estimate | Job times each chunk → live real-time factor, persisted; the sheet shows "≈ N min left"/"≈ N min per hour" from the MEASUREMENT (placeholder removed; nothing shown until a device rate exists). Per-chunk timing also DevLog'd. Mac `-asrbench`: ~100–134× realtime (inference is tiny vs audio); phone absolute number device-measured |

## Audiobook player — text-forward redesign *(A+D hybrid)* — built 2026-06-13

Signed-off mock: `Skrift_Native/SkriftDesktop/mocks/audiobook-player-redesign.html`.

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Read-along text panel *(Spotify-lyrics)* | ✅ | n/a | `Features/Audiobooks/ReadAlongView.swift` (+ `BookTranscriptStore.fileTranscript`); sentence split = `SentenceSnap.sentenceStartIndices` | The hero: discrete lyric LINES from the wave-2 sidecar, current line large+bright, neighbours dim by distance, **smooth auto-scroll**, edge fade, tap-a-line-to-seek. ✅ 2026-06-15: lines split with **`NLTokenizer(.sentence)`** (was naive trailing-`.` matching) so they no longer break mid-sentence on abbreviations ("Mr."), decimals ("3.14") or ellipses; on clean sentence ends it matches the old rule (seam-cut + capture-snap unchanged). Un-chunked spot → "Transcribe to read along" nudge → `TranscribeBookView`; re-checks coverage every ~1.5 s even paused so a finishing transcribe flips nudge→read-along live. **Sync (2026-06-13, all device-proven):** playhead INTERPOLATED between the 0.5 s AVPlayer ticks + advance at line-END (`lead` 0.1 s) so the lit line rides the voice, not trailing/early. Lines are uniform 18 pt (current emphasised by `scaleEffect`, not font-size) so advancing doesn't reflow/"hustle". Real text device-owed (sim has no ASR) |
| Player relayout | ✅ | n/a | `Features/Audiobooks/AudiobookPlayerView.swift` | Cover-tint header (`UIImage.averageColor`, darkened to the cover's hue) + 56 px cover chip + `Ch N/M` pill; speed◁ ⟲15 ▶ 15⟳ ▷sleep; slim Chapters + Bookmark row; hero "Capture this". Swipe-down dismiss + capture seam preserved. **Full-screen (2026-06-13): the read-along fills all space below the header (`ReadAlongView` flexible-height, geo-relative head/tail spacers) with scrubber→transport→Chapters·Bookmark→Capture pinned at the bottom — no dead `Spacer` gap** |
| Bookmarks (lightweight) | ✅ | n/a | `Services/Audiobooks/Bookmark.swift` (`AudiobookBookmark` + `BookmarkStore`) | Tap Bookmark → drops a marker (global position + chapter label + timestamp), haptic + toast, near-dupe guard (±2 s). Per-book `bookmarks.json`, atomic. NOT a rich save — Capture is that. 6 unit tests |
| Chapters / Bookmarks sheet | ✅ | n/a | `Features/Audiobooks/ChaptersBookmarksSheet.swift` | TOC sheet, Chapters | Bookmarks tabs. Chapters promoted out of the ⋯ menu (couldn't find them there) → tap to seek, current marked. Bookmarks: tap to jump, swipe to delete |

## Audiobook quote-capture *(mobile player + capture; desktop pipeline)* — built 2026-06-11

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Audiobook library + player (Bound-style) | ✅ | n/a | `Features/Audiobooks/*`, `Services/Audiobooks/*` | Files/iCloud import (copy into app), tags/cover/m4b chapters, per-book resume, speed, sleep timer, background + lock-screen transport (`AudiobookSession`); readable multi-file chapter titles (`ChapterDisplay` — LCP-strip + "Chapter N" prettify, 2026-06-12); Edit book details after import (player ⋯ → `EditBookDetailsView`: title/author/cover via PhotosPicker, falls back to current art; persists via store + live `refreshFromStore`, 2026-06-12) |
| Retroactive quote capture | ✅ | n/a | `MergedCaptureView` + `CaptureMath` (OUTWARD sentence-snap) + `QuoteCaptureProcessor` | Quote built from the selected sentences (span±20 s transcribed on demand / read from the wave-2 sidecar); quote audio = the memo's audio. **The waveform mark-in/out (`CaptureMomentView`) + grains were retired 2026-06-13 — text capture is the only flow** |
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
| Voiceprint enrollment | ✅ | ✅ | mobile `Features/Names/PersonDetailView.swift` (`VoiceEnrollView`) + `Services/Diarization/VoiceEnroller.swift` | ✅ 2026-06-15 mobile BRIDGED: the DIRECT "Add voice" button now records a short on-device sample (`FeedbackRecorder` → `AudioConverter` 16 kHz → `VoiceEnroller.enroll` → embed + store + sync) — the SAME pipeline as conversation speaker-naming (was a "Got it" placeholder). ≥3 s guard (`minSamples` 32 000 = 2 s); audio discarded after embedding. UI-probe-verified (`VoiceEnrollUITests`, screenshot `/tmp/skrift-enroll-shots`) |
| Voice match (cosine, thr 0.5) | ✅ | ✅ | mobile `Services/Diarization/VoiceMatcher.swift`; desktop `Pipeline/Diarization/VoiceMatcher.swift` | Full on-device identify loop on both |

## Diarization / conversation mode

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Diarize (Sortformer) + fuse to turns | ✅ | ✅ | mobile `Services/Diarization/DiarizationService.swift` + `Services/SpeakerFusion.swift`; desktop `Engines/DiarizationService.swift`, `Pipeline/Diarization/SpeakerFusion.swift` (byte-identical) | Mobile runs the FULL on-device pipeline (diarize + fuse, byte-identical to desktop) — the Split-speakers button triggers it. ✅ 2026-06-14 fusion hardening (#3/#4): `minTurnWords` 2→3 (absorbs short mid-run mis-attribution flanked by the same speaker) + gap words assigned by NEAREST BOUNDARY not nearest midpoint (boundary-word mis-snap). Mid-sentence mis-splits still bounded by Sortformer quality |
| Split-speakers on an existing memo | ✅ (button) | ✅ | mobile `MemoDetailView.swift` (`split-speakers-button` → How-many-speakers); desktop pipeline | Mobile = dedicated toolbar button + Auto/N dialog |
| Persist diarization segments (for later enrollment) | ✅ | ✅ | mobile `Services/Diarization/DiarizationStore.swift` (`diar_<id>.json` + `turnSlots`); desktop `Models/PipelineFile.swift` (`diarizationSegments`) + `Pipeline/BatchManager/DiarizationSidecar.swift` | ✅ 2026-06-09: written by BatchRunner; byte-mirrors the phone sidecar — unblocks Mac "name a speaker" |
| **Bold speaker turn headers** | ✅ | ✅ | mobile `Features/MemoDetail/SpeakerTurnsView.swift`; desktop `Features/Review/BodyTextView.swift` (`turnHeaderRegex` + restyle) | ✅ 2026-06-15: `**Name:**` headers render as a BOLD speaker label (name bold; `**` dimmed but kept in the model so export/edit round-trip the markdown) instead of showing raw asterisks. (Snapshot/read-only `BodyText.styled` path still literal — follow-up.) |
| **Conversation name-linking (turn-aware)** | ➖ | ✅ | desktop `Pipeline/Sanitisation/Sanitiser.swift` (`processConversation`), `Pipeline/Diarization/Diarizing.swift` (`SpeakerTranscript.parse/mergeAdjacentTurns`), `BatchRunner.swift` | ✅ 2026-06-14: attributed transcripts get turn-aware linking — **merge** consecutive same-speaker turns (#3); **first** header → full `[[Canonical]]`, later → plain short name (#2); **inline** mentions → `[[Canonical\|short]]` alias-display, NORMALISING misheard forms ("tyr"/"cherry") to the SHORT name instead of the transcribed surface (#1). ✅ 2026-06-15: inline is now FIRST-ONLY per person (one note, one link) — a speaker's single link is their turn header; later inline mentions demote to the short; opt-in gated by `aboutPeople`. Mac-diarize path emits PLAIN headers so both routes render identically |
| **`isAttributed` line-anchored + ≥2 distinct speakers** | n/a | ✅ | desktop `Pipeline/Diarization/Diarizing.swift:29-...` | ✅ 2026-06-14: turn-header regex anchored to line start + requires 2 distinct labels, so a hand-formatted `**Pros:**`/`**Cons:**` body isn't mis-read as a conversation (no longer skips copy-edit) |
| **Re-transcribe disabled for diarized memos** | n/a (removed) | ✅ | desktop `Features/Review/NoteActions.swift`, `Features/Sidebar/SidebarView.swift`, `Features/Shell/ProcessingCoordinator.swift` | ✅ 2026-06-14 (#5): a speaker-attributed transcript hides Re-transcribe + Redo-copy-edit (both destroy the turns — the phone never uploads segments/word-timings, so the `**Name:**` text is the only copy); `redo(.copyEdit)` keeps a conversation verbatim defensively |

## Sync & contract  *(the spine)*

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Significance-gated upload (flag-to-send) | ✅ | ✅ (reads) | mobile `Services/Sync/SyncCoordinator.swift:34`; desktop `Pipeline/Ingest/UploadService.swift:44-46` | **LIVE**: only `significance > 0` uploads. Desktop pre-fills its slider from the sent value |
| Multipart `POST /api/files/upload` (RAW transcript, never sanitised) | ✅ | ✅ | desktop `Server/SyncHandlers.swift:37-38`, `UploadService.swift` | reads `title`, `significance`, `transcriptUserEdited`, `transcriptConfidence`, `imageManifest` |
| Upload word-timings + diarization sidecars (additive parts) | ✅ | ✅ | mobile `Services/Sync/UploadPayload.swift` (`wordTimings` + `diar` parts) + `SyncCoordinator.swift`; desktop `Pipeline/Ingest/UploadService.swift` | ✅ 2026-06-15: phone sends `wt_<id>.json` + `diar_<id>.json` as OPTIONAL parts (absent on older builds → byte-compatible). Mac ingests → `pf.wordTimings` (drives **Mac karaoke/read-along** on a trusted phone memo) + `pf.diarizationSegments` + the `diar_<id>.json` sidecar (enables **voice-enroll from a phone conversation**). Mac re-diarize now gates on `didTranscribe` (Mac-transcribed-this-run), so phone word-timings never trigger a re-diarize |
| Diarized transcript marked trusted (never re-ASR'd) | ✅ | ✅ (honors) | mobile `Features/Recording/MemoSaver.swift` (`diarizeIntoTurns` sets `transcriptUserEdited`) | ✅ 2026-06-14 (#5): a phone-diarized conversation sets `transcriptUserEdited=true` so the Mac trusts its `**Name:**` turns regardless of ASR confidence (was: a noisy <0.7 take got silently re-transcribed → turns destroyed at ingest) |
| Names meta/get/put + LWW | ✅ | ✅ | `SyncHandlers.swift:55-71` | |
| Bonjour discovery / advertise | ✅ | ✅ | mobile `Features/Settings/PairMacView.swift`; desktop `Server/SyncServer.swift:51-64` | Desktop advertises unique host name; phone resolves IPv4 |
| Health endpoint | ✅ | ✅ | `SyncHandlers.swift:50-53` | reports FluidAudio "parakeet" availability |

## Ingest / import

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Audio file import (share / open-in) | ✅ | ✅ | mobile `App/AppURLHandler.swift`, `MemoSaver.swift:39-69`; desktop `Pipeline/Ingest/IngestService.swift:41-61` | |
| Folder / drag-drop ingest | n/a | ✅ | desktop `SidebarView.swift:39-62`, `IngestService.swift:201-211` | |
| Apple-Notes import (+HEIC→JPG relink) | n/a | ✅ | desktop `IngestService.swift:63-94, 128-170` | |
| **Video import → audio + 1 frame thumbnail** | ✅ | ✅ | mobile `App/AppURLHandler.swift`, `Features/Recording/MemoSaver.swift` (`importVideo`), `Features/Import/VideoImportPicker.swift`, `SkriftShare` (Photos share → `"video"` inbox entry → `CaptureInboxDrainer` → `importVideo`); desktop `IngestService.swift` (`ingestVideo`/`hasVideoTrack`/`extractAudioSync`/`embeddedRecordingDate`), `UploadService.swift` | Open-in, pick, OR **share a video from Photos** (2026-06-14: `NSExtensionActivationSupportsMovieWithMaxCount` + a `"video"` inbox entry — bypasses the capture sheet) → strip audio to `.m4a` + grab one frame as `[[img_001]]` → normal voice memo. `recordedAt` = the video's EMBEDDED creation date (not import time). A SHARED-video import **opens the new memo** (`MemoOpenBridge` → `MemosListView` pushes it) so it isn't lost when it sorts down to the video's date (2026-06-14, DevLog-diagnosed). **2026-06-15 fixes:** (1) **playback** — the memo opens BEFORE async extraction finishes, so the detail player's first `load()` hit a missing file and stayed silent; `MemoDetailView` now reloads on `duration`/`transcriptStatus` change (guarded `!hasAudio`). (2) **source glyph** — a video import is neither a share nor book capture, so it had no source marker; added `MemoMetadata.sourceType = "video"` (first entry of the unified source taxonomy; mobile-only — NOT in the upload contract), a `video.fill` row glyph + a "Video" chip in the row + detail (`Memo.isVideoImport`). (3) **row snippet** — stripped `[[img_NNN]]` markers from the untitled-row snippet (a video transcript always opens with `[[img_001]]`, which used to fill the whole snippet line). (4) **portrait frame stretched (device-reported)** — the Memo-detail inline image (`TranscriptEditor.imageAttachment`) pinned FULL width but capped height at 320; `NSTextAttachment` fills bounds without preserving aspect, so a tall PORTRAIT video frame (1080×1920) came out stretched wide. Fixed: shrink the width to keep aspect when the height cap kicks in. (`-seedVideoMemo` now seeds a PORTRAIT diagnostic frame; its circle stays round.) The 48×48 row thumb + the playing-mode `ImageEmbed` already aspect-fill/clip correctly. (5) **desktop now mirrors it** — the phone uploads `sourceType:"video"` (additive contract field); the Mac reads it (`UploadService` → `PipelineFile.mediaSource`) → a unified `sourceDescriptor` (`QueueDerivations`) drives BOTH the sidebar glyph AND the detail "source" label (`video.fill` + "Video", not mic + "Voice memo"); a desktop-imported video sets the same marker. (6) **desktop date fix** — `UploadService` now uses the phone's `recordedAt` for `pf.uploadedAt` (a Photos video kept showing the upload day instead of its filming date). `backlog.md:15` |
| Capture items (share URL/text/image) | ✅ | ✅ | see the **Capture items** section above + `Skrift_Native/CAPTURE_CONTRACT.md` | ✅ BUILT 2026-06-12 (C3 lanes) — **NOT deferred** (this row was stale). Phone: share-extension → App-Group inbox → Memo; Mac: enhance-lite + compile/export |

## Transcription engine *(desktop in-process)* / on-device *(mobile)*

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| FluidAudio / Parakeet ASR | ✅ | ✅ | desktop `Engines/TranscriptionService.swift` | word timings, phantom-transcript guard |
| Audio preprocessing (high-pass + normalize) | — | ✅ | desktop `Engines/AudioPreprocessor.swift` | `highpassFreqHz`, default 80 Hz |
| BPE merge / image-marker injection | — | ✅ | desktop `Pipeline/Transcription/BPEMerge.swift`, `ImageMarkers.swift` | |

## Enhancement (Gemma 4 E4B, mlx-swift) *(desktop)*

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Copy-edit / title / summary | ➖ | ✅ | `Engines/EnhancementService.swift:49-65`; gate `BatchRunner` + `AppSettings.summaryMinWords` | runs on RAW transcript; `[[img]]` stripped + reinserted via anchors. ✅ 2026-06-15: **summary SKIPPED for short notes** (body < `summaryMinWords`, default 75) — a 2-line memo doesn't need one; a manual "Redo summary" still forces it |
| Prompt templates (configurable) | ➖ | ✅ | `Models/AppSettings.swift:37-76` | |

## Name-linking, tagging, export *(desktop)*

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Sanitiser (alias→`[[Canonical]]`, ambiguity) | ➖ | ✅ | `Pipeline/Sanitisation/Sanitiser.swift` (`process` = monologue, `processConversation` = turns) | Monologue: first mention→`[[Canonical]]`, rest→short. Conversation: turn-aware (see Diarization table). per-alias + per-occurrence ("two Jacks") resolver |
| **Opt-in naming gate** (`aboutPeople`) | ➖ | 🟡 | `Pipeline/Sanitisation/Sanitiser.swift` (`process`/`processConversation(aboutPeople:)`, `gated`), `Models/PipelineFile.swift` (`aboutPeople`), `BatchRunner.swift`, `ProcessingCoordinator.swift` | ✅ 2026-06-15 (chunk 1, `mocks/opt-in-naming.html`): names are NOT auto-linked. `process`/`processConversation` take an `aboutPeople` set (canonical keys) and link ONLY those people — everyone else stays plain; EMPTY (a fresh note) → links nobody; `nil` = ungated (engine-level tests). Production callers pass `pf.aboutPeople`. Conversations still AUTO-link matched speakers (their turn header is the one link). 🟡 review chip bar + Names editor + `people:` frontmatter = chunks 2–4 |
| Conversation inline mentions FIRST-ONLY | ➖ | ✅ | `Sanitiser.swift` (`linkInline`, shared `seen`) | ✅ 2026-06-15: one note, one link — a person's FIRST mention (header OR inline) links, every later mention demotes to the plain short (was: every inline mention linked → clutter + multiple links per speaker) |
| Alias-display links pipe-aware (`[[Canonical\|spoken]]`) | ➖ | ✅ | `Sanitiser.swift` (`linkTarget`/`hasCanonicalLink`/`linkDisplay`), `Features/Review/BodyTextView.swift` (`person(matchingCore:)`) | ✅ 2026-06-14: link-identity (highlight, unlink/relink, resolver first-mention detection) parses the canonical part before the `\|`; unlink/relink preserve the spoken display word |
| Unlink a `[[Name]]` (click a linked mention) | ➖ | ✅ | `Features/Review/BodyTextView.swift` (popover), `NoteDisplayView.swift` (apply + undo toast), `Sanitiser.swift` (`unlinkOccurrence`/`unlinkAll`/`process(neverLink:)`) | Per signed-off `mocks/name-unlink.html`: exactly TWO scopes — this mention → plain alias as spoken (possessive kept; alias-display restores the SPOKEN word), or all mentions in this note (persists on `PipelineFile.unlinkedNames` so reprocess won't re-link). Inline undo toast stays until dismissed |
| Deterministic tags (NLTagger lemma + spoken #) | ➖ | ✅ | `Pipeline/Tags/TagMatcher.swift` | |
| Vault tag scan (privacy: app-only) | ➖ | ✅ | `Pipeline/Tags/VaultTagScanner.swift:13-72` | |
| Compile Obsidian markdown (YAML frontmatter) | ➖ | ✅ | `Pipeline/Export/Compiler.swift:24-87` | title/date/author/source/location/weather/tags/significance/summary ✅ 2026-06-15: `source:` reflects the true origin — Video / Voice-memo / Apple-Note / Audiobook-quote / capture-url|text|image|file (was: a video exported as Voice-memo). |
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
| Start-recording intent (Siri / Control Center) | ✅ | n/a | `App/Intents/StartRecordingIntent.swift`, `SkriftWidget/RecordControlWidget.swift` | plain `AppIntent` + `openAppWhenRun` (SIGTRAP-safe). CC tile glyph = `quote.opening` ❝ (2026-06-13 — Skrift-forward, replaced the generic `mic.fill`) |
| Lock/Home record widget · `skrift://record` | ✅ | n/a | `SkriftWidget/RecordWidget.swift`, `AppURLHandler.swift:20-22` | Glyph = `quote.opening` ❝ across all families (2026-06-13, matches the CC tile) |

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
