# Skrift — Backlog

Deferred ideas and features, captured during the 2026-06 overhaul planning so they're not lost. Not scheduled — pull from here when ready.

## North star — "see how my thinking evolved over time"
The eventual reason the app exists. When I add a note about a realization, surface related notes from across the years and lay them on a timeline ("you had a similar thought in 2019, it shifted in 2021, here's where you are now").
- **Backbone (reachable now, offline):** semantic search across the whole vault using local embedding models; retrieve + rank related notes; timeline UI. Mostly engineering, not model-limited.
- **Harder part (deferred):** having a local LLM *narrate* the evolution well — same quality ceiling as the stale-summary problem. Defer until local models are good enough.

## Other deferred items
- **Watched-folder ingest** — point Skrift at a folder (e.g. the Mac Voice Memos export) for zero-friction auto-ingest. (The overhaul keeps ingest simple: drag/picker + phone sync.)
- **Summary prompt quality** — summaries read stale / not in my voice. Dedicated prompt-tuning pass once the rest is stable.
- **Tagging matchable-subset + lemma expansion** — which vault tags are auto-matchable (flag-per-tag vs separate list) and conjugation/lemma handling. Being decided in the mobile-app chat; align the desktop to it.
- **Git housekeeping** — remove the empty `claude/competent-haslett-718d5a` worktree; finish mining `robustness-cleanup` for any remaining good fixes before deleting it.
- ✅ **DONE (2026-06-09, parallel-lanes batch)** — **Import VIDEO → transcribe (with the real recording date)** —
  both apps. Phone: PHPicker + share/open-in video UTIs → extract audio (`AVAssetExportSession`) + ONE frame
  thumbnail as `[[img_001]]`, `recordedAt` from the embedded creation date. Mac: `IngestService` detects video →
  extracts audio. Open-Q resolved: **audio-only + 1 frame thumbnail** (original video discarded). Original plan kept below.
  accept video files on the
  phone (e.g. self-recorded "life advice to myself" clips) and transcribe their audio.
  Plan: extend the import path to video UTIs (`CFBundleDocumentTypes` += `public.movie` /
  `public.mpeg-4` / `com.apple.quicktime-movie`; `AppURLHandler` → `MemoSaver`) and/or a
  Photos picker (`PHPickerViewController`, filter `.videos`). Extract the audio track via
  `AVAssetExportSession` / `AVAssetReader` → feed FluidAudio on-device.
  **The memo's `recordedAt` MUST come from the video's embedded creation date**
  (`AVAsset` `.creationDate` metadata, or `PHAsset.creationDate` from the library) — NOT the
  import time. Mirrors how the Mac reads the embedded m4a recording date. Open Qs: keep/attach
  the original video or audio-only? a frame thumbnail as a `[[img]]`? Desktop side:
  `UploadService` / ingest needs the same audio-extraction if videos sync to the Mac.

## Mobile ↔ desktop unification + mobile UX (2026-06-08 brain-dump)
Captured from a session brain-dump; parity audit done (file refs are on branch `native`).
Locked process for the UI items: spec → mock → build → XCUITest (feedback_native_ui_process).

### Decisions taken (this session)
- **Significance gates sync — flag-to-send / opt-in.** Add a per-memo significance value on
  MOBILE, mirroring desktop's slider (0–1.0, snap 0.1, labels Passing/Useful/Significant —
  `SkriftDesktop/.../NoteProperties.swift:118`, stored `PipelineFile.swift:90`). **Default 0 =
  stays on the phone; > 0 = eligible to sync to the Mac.** Persist it on `Memo` + send it in the
  upload metadata (NEW, additive/optional contract field) so the Mac pre-fills its slider.
  (User: "only if they have more than 0 significance are they suitable for transfer — I don't
  need to send stupid messages to the Mac.") NOTE: this flips today's behavior (mobile currently
  uploads ALL `waiting` memos unconditionally — `SyncCoordinator.swift:31`).
- ✅ **DONE (2026-06-09)** — **Liquid-glass playback bar.** Replaced the ghosting `LinearGradient`
  with a real iOS-26 Liquid Glass floating bar (`.glassEffect(.clear)` + `.safeAreaInset(edge:.bottom)`
  so transcript scrolls cleanly *under* it), and slimmed its vertical height. The iOS-18-target note
  below is OUTDATED — we run iOS 26 and use `glassEffect`. **Device gotcha (logged for the next chat):**
  the lensed look needs `.clear` (`.regular` reads frosted), and **Reduce Motion ON throttles Liquid
  Glass on A15** (user's phone — turn Reduce Motion OFF); the Simulator never renders specular/chromatic
  glass, so judge glass on-device only.

### Items
1. ✅ **DONE** — **Significance slider on mobile + sync gating** — slider + flag-to-send live; the
   2026-06-09 batch also fixed the list to show **no sync pill** for significance-0 (phone-only) memos.
2. ✅ **DONE (2026-06-09 batch)** — **Append-more-transcription to an existing note** — a visible top-right
   "+" button on memo detail (and the ⋯ menu) records more audio → transcribes → appends + merges audio. Mobile-led.
3. ✅ **DONE (2026-06-09)** — **Karaoke on mobile** (unification): word-level highlight + tap-to-seek
   during playback. Was: mobile stored word timings (`WordTiming.swift`/`WordTimingsStore`) but never
   rendered them. Device-verified ("karaoke and edit work well").
3.5 **Mobile delete/select UX** — replace the meh "Select + bubbles" with **left-swipe-to-delete**
   + a nicer drag-to-multi-select (Photos/Mail-style). Current: `MemosListView.swift:134` Select btn.
4. **Feedback/email in Settings** — NEITHER app has any feedback/contact mechanism today. Port from
   the user's **Shhhcribble** app at `/Users/tiurihartog/Hackerman/ShhcribbleiOS` →
   `ShhhcribbleiOS/Features/Feedback/` (explored 2026-06-08). Its module:
   - `FeedbackStore` — file-based `Documents/Feedback/<uuid>/{metadata.json, screenshot.png}`,
     items = {createdAt, transcript, note, hasScreenshot, durationSeconds, sentAt?}; CRUD + markSent.
   - `FeedbackRecorder` — dictate feedback (record→transcribe→keep TEXT, discard audio).
   - `FeedbackCaptureView` / `FeedbackListView` — capture (note + optional pasted screenshot + dictation)
     + list with "Sent ✓" badges.
   - `FeedbackMailComposer` — `MFMailComposeViewController` (MessageUI, `UIViewControllerRepresentable`);
     To: `tiurihartog@icloud.com`; subject/body = transcript+note+timestamp+device; attaches a `.zip`
     of the raw folders (via `NSFileCoordinator .forUploading`). `canSendMail()` guard.
   **Skrift port plan:** add a "Send Feedback" row in `SettingsView.swift` → a capture sheet (typed note
   + optional dictation REUSING Skrift's `TranscriptionService`/`LiveRecordingService` + optional
   screenshot) → `FeedbackStore` (mirror, file-based) → email via an MFMailComposer wrapper. Needs
   `UIFileSharingEnabled`-style access if we want Files visibility. Consider desktop later (unification).
   Recipient `tiurihartog@icloud.com` (configurable).
5. **Capture items** — the big deferred cross-app feature (share URL/text/image + annotate): mobile
   share-extension target + App Group + `attachments` multipart; desktop `UploadService` accepts a
   non-audio "capture" content type through pipeline/compile/export. (Also in root CLAUDE.md.)
6. **"Transcription a bit weird" on cold auto-start** — user UNSURE it's a real bug now; park / quick-
   check only (live caption catching up while the model loads mid-recording).

### Dev/prod separation — ✅ DONE (verified implemented 2026-06-09)
Both apps split by config: Debug = `com.skrift.{mobile,desktop}.dev`, **"Skrift Dev"**, own data container +
test vault; Release = the real **"Skrift"**. The 2026-06-09 session also fixed the desktop menu-bar NAME
(`PRODUCT_NAME` per config, since `INFOPLIST_KEY_CFBundleName` was being dropped) and installed prod "Skrift"
to `/Applications`. **Open follow-up:** inverted-color dev app ICON (both apps) so dev is unmistakable by icon too.
Original decision recorded below.

#### (original decision, 2026-06-08)
Goal: use Skrift for real (real recordings/notes/vault) while still iterating, with the
real data OS-guaranteed safe from dev churn. **Approach = bundle-ID split** (chosen):
- **Production** keeps the current bundle IDs (`com.skrift.mobile` / `com.skrift.desktop`)
  — the install already on the phone, real data preserved.
- **Dev** builds get `.dev` bundle IDs → a brand-new, SEPARATE OS data container; dev
  builds physically can't touch prod memos/recordings/names. macOS Dev defaults its
  export to the **test vault** (`~/Hackerman/Obsidian_LLM_Test_Vault`), never the real one.
- iOS `.dev` plumbing: own App Group (`group.com.skrift.mobile.dev`) + widget/shared
  bundle IDs + automatic signing (team 9W82X49JZS handles new IDs); dev Mac advertises a
  distinct Bonjour name so the dev phone pairs with the dev Mac.
- **Look = name only** ("Skrift Dev"), same icon (user's call).
- Implement via an xcodegen build configuration that overrides bundle ID + display name
  (+ App Group/Bonjour for dev); keep Release = production.
- **"Switch them out" = promote** dev code under the prod bundle ID; SwiftData migrates in
  place. SAFE BY CONSTRUCTION if model changes stay **additive** (defaults, like
  `significance: Double = 0`) → lightweight migration. Test the migration on a copy first.

### Unification audit (mobile vs desktop) — exists on ONE side only
- significance slider → desktop only (→ add to mobile, item 1)
- karaoke word-highlight → ✅ DONE on mobile (2026-06-09); was desktop-only
- per-memo sync gating → NEITHER (→ new, item 1)
- feedback/email → NEITHER (→ new, item 4)
- swipe-to-delete → NEITHER (→ mobile, item 3.5)
- deep settings (vault/author/model/prompts) → desktop only (intentionally NOT unified — Mac-side concerns)

## Features to implement (added 2026-06-09)
- **Direct "record a voice" enroll in Settings → Names & voices** — today the "Add voice" row is a
  status label only; voices enroll ONLY via conversation-mode naming. Add a tap-to-record-a-sample
  enroll flow so a Person can be given a voiceprint directly. (Tied to the embedding-cosine pivot —
  see `CONVERSATION_MODE_HANDOFF.md` §5.) Both apps (the Names & voices tab is on phone + Mac).
- ✅ **DONE (2026-06-09 batch)** — **Desktop Liquid Glass pass** — the Mac review transport bar is now a
  floating glass capsule (`.glassEffect(.regular)` on macOS 26 + `.ultraThinMaterial` fallback). Judge live;
  flip `.regular`→`.clear` for a more lensed look. Sidebar left opaque (could extend).
- **Re-ingest the ~30 old notes** from `~/Desktop/Skrift old notes/` — run the existing ingest over
  them (DO WITH the user: needs the prod desktop app quit for the shared-store race, and it writes
  into the REAL Obsidian vault).
- **In-app feedback → `backlog.md` (not just email)** — today dictated/typed feedback is emailed
  (mobile `Features/Feedback/FeedbackCaptureView.swift` → `FeedbackMailComposer`, recipient
  `tiurihartog@icloud.com`; desktop has none yet). Idea: route feedback straight into this
  `backlog.md` so ideas become triage-ready items without copy-paste. **Constraint:** `backlog.md`
  lives in the repo (Mac/dev side) — the phone can't write it directly. Options: (a) sync feedback
  phone→Mac like memos, then the Mac appends to a dedicated `## Inbox (from in-app feedback)` section
  here; (b) a small scheduled agent reads the feedback inbox/email and appends + lightly tidies into
  the right section; (c) the desktop feedback module writes locally. Open Q: append raw vs. have an
  agent dedupe/route into existing sections. Pairs with the feedback port (item 4 above).
- **Show downloaded models in phone Settings** — a Settings → "Models / Storage" section listing
  the on-device models (Parakeet ASR; the diarization + voiceprint models once enrolled): downloaded?
  size, version, and optional actions (re-download, delete to free space). The state already exists
  (onboarding download + the record-ready preload status, `RecordView.swift:271-292`) — surface it in
  `Features/Settings/SettingsView.swift`. **Unification:** desktop also downloads models (~600 MB ASR
  + ~9 GB Gemma) — mirror a Models/Storage view on Mac Settings (ties to the desktop model-unload
  idle-timer backlog item). Open Q: read-only display vs. management (delete/re-download).

## Follow-ups from the 2026-06-09 parallel-lanes batch
Most of the brain-dump shipped this batch (record-screen polish, list fixes, video import, desktop glass,
diarization-segment persistence) — see `FEATURES.md`. Remaining threads it opened:
- **Task A — auto-sync names after voice enrollment (REAL BUG, confirmed).** Naming a speaker enrolls the
  voiceprint into the phone's local `names.json` but **never auto-pushes** — it only reaches the Mac on a manual
  sync-button tap (`SyncCoordinator.syncAll` is the ONLY caller of `NamesSync`). So cross-device auto-match
  silently lacks the new voiceprint until a manual sync. Fix: fire a names-sync right after a successful enroll
  (tail of `VoiceEnroller.enroll` / `learnVoice`, or on memo-save / app-foreground), debounced + guarded on a
  paired Mac. The merge/UNION itself is correct (now covered by `SkriftDesktopTests/NamesSyncRoundTripTests`).
- **Task A — live device round-trip** (human-gated): enroll on phone → confirm it lands in the Mac `names.json`
  with the server running → process that person's clip on the Mac → confirm `VoiceMatcher` auto-labels them.
- **Task B — Mac "name a speaker" review UI** (build phase): mock done (`SkriftDesktop/mocks/name-a-speaker.html`,
  awaiting sign-off); backend done (segments persisted: `DiarizationSidecar` + `PipelineFile.diarizationSegments`).
  Owed: a conversation-turn renderer in `Features/Review/` + click-to-name → people picker → relabel `**[[Person]]:**`
  → `DiarizationService.embedSpeaker` + `NamesStore.addVoiceEmbedding`.
- **F3 live confidence-color** is a positional approximation (trailing 6 words = "settling") — FluidAudio's live
  path exposes no finalized/volatile flag. Revisit if/when it does, for true locked-vs-volatile coloring.
- **Inverted-color dev app ICON** (both apps) so dev is unmistakable by icon (not just name).
  ✅ DONE same day (Debug → `AppIcon-Dev`, RGB-inverted; both apps).

## Device-testing feedback — 2026-06-10 (12 memos + feedback note pulled off the dev phone)
User ran the full TESTING_2026-06-09.md pass. Transcripts pulled via `devicectl` from the dev container;
crash logs via `idevicecrashreport`. **PASSED:** title-on-rows ✓, sig-0-no-pill ✓, + append button exists ✓,
keyboard-dismiss ✓, inline photos ✓, caption scrollback ✓, video date ✓, desktop video ingest (via Finder) ✓,
glass bar acceptable ✓.

### P0 — fix before promoting to prod
1. **CRASH mid-recording (3× today, one recording LOST).** All three .ips identical: SIGSEGV "stack size
   exceeded due to excessive recursion" in SwiftUI `ConcatenatedTextStorage.resolve` — the live caption is
   built as per-word concatenated `Text` runs (solid+volatile+photo tokens), so a long recording → thousands-
   deep `Text + Text` chain → stack overflow. Fix: build ONE `AttributedString` and render a single
   `Text(attributedString)` (constant depth). Crash files: `/tmp/skrift-crashes/SkriftMobile-2026-06-10-*.ips`.
2. **Append silently adds NO text** (3× repro, BROADER than the model-cold theory — verifier-corrected).
   Repros: (a) stopped the append recording before the ASR model loaded; (b) tried AGAIN with the model
   presumably warm — still no text; (c) appended after manually editing the note body — nothing added.
   `MemoSaver.appendRecordingAsync` merges audio but can silently add no text with no error. Fix: REPRODUCE
   first (all three sequences), then harden the whole append-text path — never silent-no-op, queue
   transcription when the engine isn't ready (status `.transcribing`), surface failures; regression tests
   for cold-model append and append-after-manual-edit.
3. **Tail of recording cut off after Stop** (BOTH dev + prod, intermittent): live caption had the full text,
   then the final one-shot file transcription replaced it WITHOUT the last bit. Likely a race: final
   transcribe reads the file before the writer flushes the last buffers, or stop truncates. Investigate
   `LiveRecordingService.stop` → final transcribe ordering. "This shit needs to be very robust."
4. **Live Activity doesn't end**: lock screen still showed "recording, 45min" long after stop+save. End/
   dismiss the activity reliably on stop (and on app foreground if stale).

### P1 — bugs (post-promotion ok)
- **Confidence colors wrong in practice**: "white text is supposed to be non-changing but it also changes" —
  the positional approximation visibly fails (re-transcription rewrites the 'solid' body too). Either find a
  real finalized signal or drop/soften the distinction.
- **Opening a memo stops Spotify**: audio session activates on note open (player setup) instead of on Play.
  Use `.ambient`/don't activate until playback; respect `.mixWithOthers` when idle.
- **Paste into note body teleports scroll to top** (mobile editor) — keep scroll position after paste.
- **Share-a-video from Photos doesn't list Skrift** (mobile): document types alone don't surface the app for
  videos in the share sheet — likely needs a share extension or different UTI handling. (Photos→file works.)
- **Desktop: drag direct from Photos app doesn't ingest** (works via Finder) — Photos drags provide promised
  file/`NSItemProvider`, not a file URL; accept promised files in the drop handler.
- **No video thumbnail seen — check BOTH apps** (verifier: source ambiguous). Desktop `ingestVideo` has no
  frame-grab by design → add one (mirror mobile). Mobile claims `[[img_001]]` — verify it actually renders
  on a real import.
- *(doc fix, not a bug: TESTING guide said the desktop glass play bar is at the BOTTOM — it's pinned at the TOP.)*
- **Desktop: summary not editable** in review.
- **Desktop: name-linking brackets EVERY mention** (user expects `[[Name]]` first mention only, alias after —
  the Sanitiser's design intent; verify what produced all-bracket output, possibly the conversation-turn
  headers or a regression).
- **`SkriftMobile.diskwrites_resource-2026-06-10-221621.ips`** — disk-writes resource warning; check what's
  writing heavily (likely model download or audio writes).

### P2 — feature requests from testing
- **Instant record**: tapping record (or + append) should START RECORDING IMMEDIATELY — no record-ready
  screen stop; model loads in background (it already catches up).
- **Feedback rework**: not email — user wants Claude to read feedback directly off the phone (PROVEN possible
  today via devicectl pull) or append to backlog.md. Plus: floating/shake-to-feedback affordance w/ screenshot
  (Henry's idea), not while recording.
- **Copy-transcript button on each memo row** (today: open → ⋯ → copy). Multiple paths to the same action.
- **Auto-copy transcript to clipboard after transcription** (cheap backup against data loss).
- **Custom vocabulary / word boosting** ("Skrift" mis-recognized; FluidAudio CTC boosting exists per memory).
- **Trash with ~2-week retention** instead of permanent delete (like Apple Voice Memos).
- **Front camera option** for in-recording photo capture (selfie).
- **Click a `[[name]]` to revert to alias** (desktop review): popup like the disambiguator with "unlink".
- **Audiobook quote capture** (BIG idea, design doc needed): mark in/out while listening (in-app audiobook
  player or lock-screen scrubber), transcribe the marked span snapped to sentence boundaries, insert as a
  quote block (chapter/book/author metadata) + space for own rambling below. Inspiration: Bound audiobooks
  app (loads files from iCloud/Files). Possibly later: link to existing notes.
- **Significance-gated "wall" pipeline**: notes above a significance threshold require a manual refine pass
  (desktop gate: can't export to Obsidian until refined) → then export + send to printer for the physical wall.

## Audit findings (2026-06-09 post-batch error sweep — triaged, verified against code)
Two read-only agents swept both apps after the batch; orchestrator verified each claim before listing.
None are release blockers; fix in a follow-up pass.

**Mobile:**
- **`[photo N]` markers anchor by WORD COUNT at capture** (`RecordView.swift:83`) but the live caption
  re-transcribes wholesale, so the token can drift later than the real capture point (clamped, no crash).
  Fix: anchor by TIME offset (stable across re-transcription) — `LiveCaptionLayout` maps time→word at render.
- **Recorder teardown hygiene** (`LiveRecordingService.swift`): route observer + timers rely on `stop()`
  running before `deinit`; an abnormal teardown can leak them (`[weak self]` prevents a crash). Fix: explicit
  `stopTimers()` + `teardownRouteObserver()` in `deinit`.
- UX nits: silent video (no audio track) imports as a silently-`failed` memo (no user feedback); a failed
  video import shows import-time instead of the video's date; rapid photo taps are silently debounced (0.6s).
- *Dismissed as false positives (so future sweeps don't re-flag): "SwiftData off-main in append" (`MemoSaver`
  is `@MainActor`); "append audio format corruption" (export re-encodes via `AppleM4A`; merge-failure falls
  back to base-audio+text by design; temp-export→swap order is safe).*

**Desktop:**
- **Re-transcribe leaves STALE diarization segments** (`ProcessingCoordinator.retranscribe` resets transcript
  but not `diarizationSegmentsJSON`/sidecar) → re-transcribed conversation memos can carry old speaker
  segments → wrong enrollment slices. Fix FIRST: clear segments + delete the sidecar in `retranscribe()`.
- **Sidecar write is `try?`** (`DiarizationSidecar.swift:47`) — a failed write is silent. SwiftData copy
  still survives (so no data loss), but log + surface it; the sidecar is the portability/enroll copy.
- Pre-existing, already-tracked (now slightly more pressing with video uploads): full multipart body
  buffered in RAM (256 MB cap; `SyncServer.swift:90`); `DispatchQueue.main.sync` SwiftData bridge in the
  Bonjour handlers (`SkriftDesktopApp.swift:46,59` — deadlock-free only while handlers never run on main);
  health endpoint vs the model idle-unload interplay (phone may see `available=false` after 60s idle).
- Minor: HEIC→JPG conversion failure falls back silently w/ a possibly-broken md ref (`IngestService.swift:282`);
  snapshot PNG write is `try?`; `SpeakerFusion.foldShortIslands` indexing deserves explicit bounds asserts.
