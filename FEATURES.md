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
| Record / pause / resume / stop | ✅ | ➖ | `Features/Recording/RecordView.swift` | Pause hides paused interval from elapsed time. **Instant record (2026-06-11): every entry auto-starts** (FAB, + append, Siri/widget — unified path) |
| Live caption (auto-scroll + color-by-confidence) | ✅ | ➖ | `RecordView.swift` (LiveCaption) | ✅ 2026-06-09: native auto-scroll+scrollback; finalized text solid / trailing words lighter (positional **approximation** — FluidAudio exposes no volatile flag); inline tinted `[photo N]` tokens |
| Live waveform (40-bar) | ✅ | ➖ | `RecordView.swift:453-480` | |
| Model preload status | ✅ | n/a | `RecordView.swift:271-292` | ✅ 2026-06-09: in-place "model loading" placeholder in the caption during record-while-loading, cleared once words arrive |
| Caption polling | ✅ | ➖ | `Services/Recording/LiveRecordingService.swift:231-243` | 0.6s timer |
| Audio-route-change handling (AirPods pull-out) | ✅ | n/a | `LiveRecordingService.swift` | ✅ 2026-06-09: observes `routeChangeNotification`, restarts engine on the new route + amber notice; recording survives. (On-device: tap re-install on format change is a flagged follow-up) |
| Conversation-mode toggle (diarize this take) | ✅ | ✅ | `RecordView.swift:100-111` · desktop `Models/AppSettings.swift:28-30` | |
| Append to an existing recording | ✅ | ➖ | `MemoDetailView.swift` (`add-recording-button` + ⋯ menu); merge `MemoSaver.swift` | ✅ 2026-06-09: visible top-right **+** button added (also in ⋯ menu); append flow verified |

## Memo detail & playback  *(mobile)* / Review surface *(desktop)*

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Editable transcript | ✅ | ✅ | mobile `MemoDetail/TranscriptEditor.swift`; desktop `Features/Review/BodyTextView.swift` | Both self-sizing native text views w/ inline image attachments + live `[[link]]` styling |
| Keyboard dismiss on scroll | ✅ | n/a | `TranscriptEditor.swift:31`; `MemoDetailView.swift` | ✅ 2026-06-09: outer page ScrollView now `.scrollDismissesKeyboard(.interactively)` too |
| Karaoke (word highlight + tap-to-seek) | ✅ | ✅ | mobile `MemoDetailView.swift:499-545`; desktop `Features/Review/NoteBody.swift:74-80` | |
| Playback bar (Liquid Glass) | ✅ | ✅ | mobile `MemoDetailView.swift:603-674`; desktop `Features/Review/NoteDisplayView.swift` | ✅ 2026-06-09: desktop review transport bar is now a floating glass capsule (`.glassEffect(.regular)` macOS 26 + `.ultraThinMaterial` fallback) |
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
| Trash / Recently Deleted (14-day retention) | ✅ | ➖ | `Models/Memo.swift` (`deletedAt`), `Services/NotesRepository.swift` (`softDelete`/purge), `Features/MemosList/RecentlyDeletedView.swift`, purge hook `App/SkriftApp.swift` | ✅ 2026-06-11: ALL delete paths (list + detail) soft-delete; Restore is lossless (files kept); trashed memos excluded from list/search/sync; startup purge ≥14 days. Desktop mirror = backlog |
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

## Audiobook quote-capture *(mobile player + capture; desktop pipeline)* — built 2026-06-11

| Capability | Mobile | Desktop | Key files | Notes |
|---|---|---|---|---|
| Audiobook library + player (Bound-style) | ✅ | n/a | `Features/Audiobooks/*`, `Services/Audiobooks/*` | Files/iCloud import (copy into app), tags/cover/m4b chapters, per-book resume, speed, sleep timer, background + lock-screen transport (`AudiobookSession`) |
| Retroactive quote capture | ✅ | n/a | `CaptureMomentView` (micro-scrubber + grains), `CaptureMath` (span + OUTWARD sentence-snap), `QuoteCaptureProcessor` | Capture proposes [now−30s→now]; span±20s transcribed on demand; quote audio = the memo's audio |
| Capture sheet (ramble-first) | ✅ | n/a | `CaptureSheetView`; ramble = `RecordView(appendTo:)` | Big record-your-thoughts, Save & keep listening, circles; book auto-pauses/resumes |
| Conditional mini-player + list integration | ✅ | n/a | `AudiobookMiniPlayerBar` (C3), mounted in `MemosListView` | Exists only while a session is active; FAB nudges up; capture rows = book glyph + italic ❝-quote lead |
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
