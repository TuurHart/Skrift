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
3.5 **Mobile delete/select UX** — ✅ swipe-to-delete DONE (native List `.swipeActions`, full-swipe
   commits, in `MemosListView`; verified 2026-06-12 status audit). Still open: a nicer
   drag-to-multi-select (Photos/Mail-style) to replace the Select button.
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

### P0 — ✅ ALL FOUR FIXED (2026-06-11 fix batch, merged + all tests green; awaiting device re-test)
Fixes in brief: (1) crash → caption is ONE AttributedString in a single Text (run-count pinned by test);
(2) append → .transcribing shown throughout, clip kept until text lands, retry-with-backoff, terminal
failure surfaces as Error pill, editor-clobber window closed; (3) tail cutoff → explicit AVAudioFile
close() finalizes the m4a before transcription reads it (same race also hit append clips); (4) Live
Activity → staleDate+keep-alive, "Recording interrupted" stale fallback, foreground orphan reaping.
PLUS: instant record (locked decision — every record entry auto-starts), Spotify ducks only on Play,
paste keeps scroll position, row swipe/long-press Copy, desktop editable summary, first-mention-only
name links (incl. conversation turn headers), desktop video thumbnail, drag-from-Photos promised files,
retranscribe clears stale segments, list-delete cleans the diar sidecar. Original P0 list below.
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

### Feature decisions — LOCKED 2026-06-10 (user sign-off)
1. **Feedback loop = plug-in-phone → Claude pulls + parses + triages into this file** (devicectl app-container
   pull, proven 2026-06-10). Email path dead. **Valid only while the user is the sole user** — revisit if the
   app ever gets other users. Skill: `.claude/skills/pull-phone-feedback/`.
2. **Share extension = build as FULL capture items** (not a video-only hack): share URL/text/image/video +
   annotate, share-extension target + App Group + `attachments` multipart + desktop capture content-type.
   **OWED TOMORROW: walk the user through what (if anything) must be set up in the Apple Developer portal /
   App Store Connect for the new extension target + App Group** (likely nothing manual — automatic signing
   team 9W82X49JZS auto-registers bundle IDs + App Groups for dev builds; explain + verify).
3. **Custom vocabulary** — GO. ✅ SPIKE DONE (2026-06-11): FluidAudio `main` (7f963cd, identical checkout in
   both apps) ships a full custom-vocab system — CTC word-spotting + rescoring (NeMo arXiv:2406.07096,
   "separate CTC encoder"; works with the Parakeet TDT 0.6B v3 both apps use). Neither app uses
   `SlidingWindowAsrManager` (its built-in `configureVocabularyBoosting` doesn't apply); both call
   `AsrManager.transcribe` directly → integrate like the CLI batch pattern: after `transcribe`, run
   `CtcKeywordSpotter.spotKeywordsWithLogProbs` over the same samples, then
   `VocabularyRescorer.ctcTokenRescore(...)`, take rescored text when `wasModified`. Cost: one extra
   ~97.5 MB HF model. Build next: Settings "Custom words" list (both apps) + the rescore pass in each
   transcriber.
4. ✅ **DONE (2026-06-11 batch)** — **Trash / 2-week retention** — all delete paths soft-delete (list +
   detail), "Recently Deleted" sheet, lossless Restore, startup purge ≥14 days. ✅ **DESKTOP MIRROR DONE
   2026-06-13** (`Pipeline/DesktopTrash.swift` + `PipelineFile.deletedAt` + `Features/Sidebar/RecentlyDeletedView.swift`):
   soft-delete keeps the working folder (lossless Restore), 14-day launch purge, trashed excluded from
   sidebar/queue/process + the phone's `GET /api/files/`; sidebar footer "Recently Deleted (N)" → restore
   sheet; `-snapshot-trash` verified; 236 unit + build green.
5. ✅ **DONE (2026-06-11 batch)** — **Auto-copy transcript** — opt-in Setting, default OFF; copies on
   transcription success incl. appends.
6. ✅ **DONE (2026-06-11 batch)** — **Front camera toggle** — flip button in CameraSheet; front hides
   zoom presets, pinch floored at 1×.
7. ✅ **DONE (2026-06-11 batch)** — **Click-`[[name]]`-to-unlink (desktop)** — built per signed-off mock:
   two scopes (this mention → alias as spoken; all mentions in note + persisted no-relink-on-reprocess via
   `PipelineFile.unlinkedNames`), undo toast, 15 tests. Note: single-mention unlink is a body edit (not
   persisted across re-transcribe) — by design, consistent with hand edits.
8. **Audiobook quote-capture** — direction written below; design after the current wave.
9. **Significance wall** — GO, threshold **≥ 0.8**; AirPrint; refine-gate before export; design with the
   audiobook session. ✅ The locked **circles UI is DONE (2026-06-11 batch, BOTH apps)** — 10 tappable
   circles per the signed-off mock (all three ≥0.8 wall cues, re-tap clears, tier labels); the wall
   PIPELINE (refine gate + print) remains the design-session item.

### Audiobook quote-capture — DESIGN LOCKED 2026-06-11 (grill session; supersedes the direction below)
Build-ready spec, every branch user-approved. **MOCK SIGNED OFF same day** ("wouww looks great, let's go").
✅ **BUILT 2026-06-11 (4-lane batch, all tests green, merged to native)** — see FEATURES.md "Audiobook
quote-capture" for the full capability×file map. Also in that batch: ✅ the resolver per-occurrence
INSTANT-apply fix (each pick renders immediately, document-order demotion, progress counter).
Owed from lane flags: device-test the capture flow end-to-end (grains/scrubber feel, ramble append,
Mac round-trip of a quote memo incl. quote protection + [[Author]] export).

#### Device-test results — 2026-06-11 23:00 — ✅ ALL FIXED same night (3-lane batch + polish, tests green)
Fixes: scrubber gesture rewrite (root cause: .contentShape applied AFTER .offset stacked both hit-zones in
the strip corner → 56pt latched per-handle targets, min-span clamp, pannable window w/ edge-bump); preload
on capture-open; post-ramble = review-first (green SAVED card w/ live appended text, resume ONLY on Save &
keep listening, button flips to "Add more"); single import affordance; MULTI-FILE BOOKS (multi-select →
one book, filename-ordered chapters, continuous cross-file playback, capture confined to one file —
cross-file spans flagged as a possible later enhancement); styled quote + attribution caption BOTH apps
(presentation-only, raw "> " preserved); desktop book glyph + "Audiobook quote · <Title>" source; list chip
truncation (all chips capped 220pt). POLISH: mini-player 104pt (~2×), 2h-idle session auto-end, Siri
"Resume my book in Skrift" (plain-AppIntent pattern). Owed: morning phone install + re-test (esp. scrubber
feel, folder import, AirPods re-insert recheck). Original findings below.

#### Morning re-test — 2026-06-12 (round 2)
**PASSED:** folder import → one book ✓ · scrubber handles respond ✓ · post-ramble review flow "way better" ✓
· styled quote + ch. attribution ✓ · in-note BOOK AUDIO playback loved ✓.
**New fixes:**
- **Chapter titles unreadable** (full filename per row): strip the files' longest-common-prefix + extension
  → "chapter_01"/"Chapter 1". Compare Bound's chapter list.
- **Mini-player bar grotesquely oversized** (Capture text wraps vertically; ORCHESTRATOR'S OWN MISS — scaled
  by arithmetic, never rendered): proper resize ~72-76pt, fixedSize/lineLimit(1) so wrap is impossible.
- **Capture screen round 2:** (a) grains/preview "always talking" — add explicit pause/mute + only sound
  while actively dragging; (b) span/pan semantics confusing — pan moved the SPAN with the window, span
  ended up "now+99s→now+256s" (future of the pause point!), labels relative-to-now unreadable → labels in
  BOOK TIME (or chapter time), pan moves WINDOW only, add "back to pause point" jump; (c) long quote text
  not scrollable on the sheet; (d) pressing Capture yanked AirPods from the Mac (session activation —
  don't activate audio for grains until first drag).
- **Edit book AFTER import:** title + author + cover (⋯ menu in the player — user expected it there; keep
  Chapters in the menu too, add "Edit book details" sheet; cover pick from Photos/Files).
- **P0 RECORDING ROUTE STILL BROKEN (worse):** memo recording with AirPods → pull out → recording DIES (no
  fallback to phone mic — the earlier restart-without-tap-reinstall fix is insufficient on device, the
  flagged format-mismatch follow-up is the likely cause); re-insert → still dead AND THE AUDIOBOOK STARTED
  PLAYING (AirPods auto-play remote command hit AudiobookSession while a recording was supposedly active).
  Fix: reinstall the tap with the new route's input format on EVERY route change; AudiobookSession must
  IGNORE remote-play while a recording is active (session priority).
- Bookmarks: user considered, DECIDED AGAINST (linking back into books = complexity/fragility). Skip.

#### Round-2 re-test — 2026-06-12 — ✅ P0 FIXED (validate-before-install + own-activation echo filter + stale-format check), DevLog shipped (Documents/devlog.txt, devicectl-pullable), swipe-down player + tap-cover-to-edit. CAPTURE DESIGN STILL PAUSED. Owed: device re-test w/ devlog pull.
- **P0 CRASH: first tap of Record crashed the app** (fresh install, round-2 build). Crash log pull attempted
  to /tmp/skrift-crashes2 (check SkriftMobile-2026-06-12-*.ips; if absent, pull next plug-in via
  idevicecrashreport). Suspects: instant-record path or the new route-change tap-reinstall init.
- **P0 DIAGNOSED (crash log SkriftMobile-2026-06-12-081100.ips, kept in /tmp/skrift-crashes3): BOTH
  morning failures are ONE bug — the round-2 route fix itself.** NSException → SIGABRT in
  `LiveRecordingService.installRecordingTap` ← `rebuildTapForCurrentRoute` ← `handleRouteChange`
  (AVFAudio InstallTapOnNode raise). First record tap: session-activation fires .categoryChange →
  rebuild installs a tap with an invalid mid-transition input format (0 Hz/0 ch) or double-installs →
  abort. AirPods pull: same path = app CRASHED (user read it as "stopped recording"). FIX DIRECTION:
  (a) ALWAYS removeTap before install; (b) VALIDATE input format (sampleRate>0 && channelCount>0)
  before installTap — NSExceptions are uncatchable from Swift, preconditions are the only defense;
  retry on a short delay while the route settles; (c) ignore route events caused by our OWN session
  activation (.categoryChange at start); (d) build WITH the dev file-logging item so the fix is
  verified from traces, not vibes.
- **P0 STILL BROKEN: AirPods pull-out stops the recording** (started with AirPods → pulled → recording
  stopped). The tap-reinstall fix did NOT hold on device. NEXT: stop guessing — add DEV-BUILD FILE LOGGING
  (user explicitly asked): a ring-buffer log file in the app container (os.Logger mirror or simple appender;
  recording/route/session events), pullable via devicectl like the feedback skill → diagnose from REAL traces.
- **Capture tool still confusing — STOP REBUILDING (user decision): design pause.** Next session = sit down
  with the user / produce interaction mocks for the capture-adjust flow BEFORE more code. No more iteration
  batches on CaptureMomentView until the design is agreed.
- **Bar at bottom: looks good now** ✓.
- **Full player (big-thumbnail screen): add swipe-down to close.** Also: user still couldn't change the
  cover ("still needs to be able to be changed") — Edit-book-details shipped in round 2 under the ⋯ menu;
  either they tested before finding it or discoverability is poor → check + consider a tap-on-cover edit
  affordance.

#### (original findings)
**WORKED:** import (single file + manual title/author confirm) ✓ · play + mini-player + nudged FAB ✓ ·
capture E2E ✓ · ramble append ✓ · circles + Will-sync line ✓ · sync to dev Mac ✓ · **QUOTE PROTECTION
held — the book quote came through enhancement untouched** ✓.
**P0 fixes (capture UX):**
- **IN/OUT scrubber handles barely respond / freeze**; dragging toward IN makes OUT jump (gesture grabs
  the wrong/nearest handle; persisted across audio-route changes, so it's the gesture system, not routes).
- **Post-ramble flow wrong ×2**: the book auto-resumed IMMEDIATELY on recorder dismiss (user couldn't
  review what they spoke) AND the record-thoughts button stayed big/purple (rambleAdded state never
  showed). Fix: no auto-resume after a ramble — resume only on "Save & keep listening"; show the
  ramble-added state + the appended text for review.
- **Span can't extend past the proposed 30s window** — the micro-scrubber window must PAN (scroll
  left/right beyond the initial span) so IN/OUT can be placed further back/forward.
- **First-capture transcription slow** — preload the transcriber the moment the capture screen opens
  (second capture was instant; warm-model). 
- **Multi-file books unsupported**: many audiobooks are file-per-chapter (the user's is ~30 mp3s); Bound's
  importer multi-selects a whole folder as ONE book ("the selector in Bound is way better"). Import must
  accept multi-select/folder → one book, files = chapters in order. *Verifier nuance: Bound's PICKER UX
  itself is the model (Select All over a chapter folder, one obvious flow) — not just the capability;
  the scrubber bug presented as PROGRESSIVE freezing (handles fully unresponsive on later attempts), so
  the gesture fix must address freeze, not only wrong-handle grabs.*
- **Two import affordances in the Library** (big dashed row + toolbar +): keep ONLY the toolbar +.
**P1 presentation:**
- **Memos-list capture row: the book chip overflows off-screen** (long book title; needs truncation).
- **Quote styling missing in the note body (BOTH apps)**: shows as plain "> " lines — no italics, no
  quote bar, no chapter/author attribution → "looks like I recorded twice". Render the C1 blockquote
  styled (italic + bar) with an attribution caption derived from C2 metadata (presentation-layer; the
  real `[[Author]]` line stays export-time).
- **Desktop source wrong for captures**: shows "Voice memo" + mic glyph; should be an audiobook-quote
  source (book glyph) when C2 bookTitle is present — sidebar + properties. (NOT a sync bug: the C2 book
  metadata arrives fine — the phone derives its book glyph from it; the desktop just never does.)
- **Backlog (capture-items umbrella): unify the SOURCE taxonomy across both apps** — voice memo / URL /
  document-PDF / video / audiobook quote / Apple Note — consistent glyphs + labels everywhere (user:
  "all the sources should be done well"). 
- **Mini-player bar ~2× vertical height** (user, 2026-06-11 late): buttons too small to hit comfortably;
  it only shows during an active session so it can afford the space. Apply post-merge (fix-lane owns the file).
- **Mini-player AUTO-HIDE after idle** (user, 2026-06-11: "I'm always listening to one book or another —
  the player will be there always"): the bar must end its session automatically after X paused time
  (start ~2h idle, + on app launch when last-played is >~6h old; constants flippable). Zero loss: progress
  persists per-book; reopening from the Library resumes exactly. Post-merge pass, with the 2x-height tweak.
- **Siri: "play/resume my book in Skrift"** — an App Shortcut that resumes the last-played audiobook.
  SAFE SHAPE per this repo's SIGTRAP history: plain `AppIntent` + `openAppWhenRun` (like
  StartRecordingIntent), NOT an audio-playback intent; opens the app + resumes playback. Phrases:
  "Resume my book in Skrift", "Play Skrift book". (True background-start via AudioPlaybackIntent = later
  experiment, device-tested carefully.)
- Watch: scrubbing while another device held the AirPods felt entangled with the route (audio yanked
  from Mac to phone) — recheck after the gesture fix lands.
1. **Skrift IS the player** for actively-mined books — model it on **Bound** ("there isn't a feature
   there I don't like"): Files/iCloud import, library w/ covers + sort, per-book resume, speed, sleep
   timer, embedded m4b chapters, background playback + lock-screen transport. One book at a time moves in.
2. **One memo per capture** (NOT a per-book note): each capture = quote block + ramble + book metadata in
   frontmatter; full existing pipeline applies (significance, sync, enhance, export). A generated
   per-book index note is a possible later export-side addition.
3. **Capture gesture = RETROACTIVE**: one Capture button (in the full player AND the mini-player) pauses
   the book and proposes span [now−30s → now]; the ~15s **micro-scrubber** adjusts IN (and OUT), with
   **snippet audio scrubbing** in v1 (hear grains as you scrub; DaVinci-style varispeed = v2 polish).
   **Sentence-snap OUTWARD** on both edges (sloppy markers always yield whole sentences). Optional
   long-press marker-in for the foresight case if it falls out cheap.
4. **Transcription = span-on-demand ONLY** (marked range ±~20s buffer through Parakeet, seconds-fast).
   Whole-book indexing explicitly REJECTED ("I don't see the point").
5. **Quote audio = the memo's audio** (span extracted to the memo .m4a) → playback/karaoke/sync/export
   toggle all work for free; you can hear the author from Obsidian. **Ramble = the append flow**
   (A-dominant: record-your-thoughts is the big button on the capture sheet; "Save & keep listening"
   secondary; book auto-pauses during ramble, resumes in place after).
6. **Metadata from file tags at import** (title/author/chapters; one editable confirm screen only if
   missing). Chapter per capture derived from marker position. Capture itself asks NOTHING.
7. **Export**: italic quote block + attribution "— [[Author]], *Book*, ch. N". `[[Author]]` is written
   as a literal wikilink AT EXPORT ONLY — authors NEVER enter the names DB (would pollute alias matching).
8. **Enhancement protects the quote — option (b) from day one**: strip quote block behind an anchor
   (image-marker pattern), copy-edit ONLY the ramble, reinsert, then **assert the quote is byte-identical**;
   any mismatch → fall back to skip-all-copy-edit + flag. Title/summary generate normally.
9. **Placement**: Library behind a book toolbar icon on the memos list. **Conditional mini-player** —
   exists ONLY while a book session is active (Bound-style glass capsule: cover, ⟲15, play, 15⟳,
   **Capture ❝**, expand ˄); the record FAB nudges up above it; mini-player YIELDS on memo detail (book
   keeps playing in background); record-FAB-while-playing auto-pauses the book and resumes after save.
   Captures appear in the memos list with a book glyph. App identity stays notes-first.
10. Mobile-first; capture memos sync to the Mac as normal memos (book files never sync). Open/minor (mock
   decides): significance circles on the capture sheet vs detail-only; mini-player on the Library screen.

### (original direction, 2026-06-10 — superseded above)
Capture a passage from an audiobook as a quoted, attributed note + your own thoughts under it.
- **Flow (preferred shape, in-app):** audiobook section in Skrift → loads the transcription model in the
  background → fine scrubber for precise positioning (a ~15s micro-scrubber alongside the normal one — a
  15h book makes one scrubber useless) → set marker-in, listen, marker-out → that span is transcribed,
  **snapped to natural sentence boundaries** (don't cut mid-sentence; markers are imprecise by nature) →
  inserted as a QUOTE block (italics) with book/chapter/author metadata asked-or-inferred → free rambling
  space below the quote (the user's own thinking — the actual point).
- **Alt shape (lock-screen markers):** marker-in/out from the lock-screen player controls — iOS gives 3rd-
  party apps limited lock-screen control, so realistically this degrades to the in-app flow; park it.
- **Player inspiration:** "Bound" audiobooks app (one-time payment; loads audio straight from Files/iCloud —
  that ingestion model is the one to copy). User has it; could inspect on the jailbroken iPhone for UX.
- **Maybe-later:** linking the quote-note to existing notes at capture time (or leave linking to Obsidian).

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

## Device-testing feedback — 2026-06-11 (4 memos pulled; verifier-passed; screenshot of two-Jacks on dev Mac)
**PASSED:** front-camera flip ✓ (photo mid-record, `[[img_001]]` inline) · circles on phone ✓ (0.4 set via
circles) · circles render on dev Mac ✓ (screenshot) · "the black screen is fixed" ✓ (ambiguous which —
ask) · feedback-via-memos + pull workflow accepted (no dedicated feedback feature wanted).

**Not a bug:** two-Jacks file on the dev Mac showed NO name linking — the dev container has NO `names.json`
(starts empty by design; prod has the Jacks). To test names on dev: add the people in dev Settings or sync
from the dev phone first.

### New items
- **P1 — instant-record flashes the old ready screen** before recording starts (model-loaded screen with
  the legacy record button). Remove the transient screen (or skip straight to the live caption) — it no
  longer serves a purpose on the auto-start path.
- **P1 — AirPods RE-insertion doesn't resume**: pull-out mid-record survives (route-change fix works), but
  putting them back in didn't move input back to AirPods ("I think it was a fail"). Confound: they may have
  re-paired to the Mac. Repro with Mac BT off; likely the `newDeviceAvailable` branch needs the same
  restart treatment as removal.
- **WATCH — Live Activity "still going on the last thing"** on the lock screen right after the new install.
  Possibly a stale activity from the PRE-fix build (new build reaps on foreground). Observe once more on
  the new build; if it recurs, the reaper has a gap.
- **Confirms backlog priority:** Settings → Models/Storage list ("we have three models — transcription,
  diarization and something else") — already specced under "Show downloaded models in phone Settings".
- Next focus per user: the BIGGER design items (capture-items build, audiobook, significance-wall pipeline,
  vocab build).
- **Reassign in the unlink popover** (from the two-Jacks discussion): clicking a linked `[[Name]]` should
  offer not just Unlink but **"Change to → <other person>"** (one-tap fix when the deterministic alias
  match picked the wrong person — e.g. a spoken "Jack" auto-linked to Timmons but meant Hutton). Reuses
  the people-picker; per-mention scope.

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

#### DevLog verdict 2026-06-12 09:14 (log in /tmp/devlog.txt — DevLog works perfectly)
NO crash ✓, echo-filter ✓, re-insert recovery ✓. REMAINING BUG: `canInstallTap` requires hw format ==
old tap/file format → REFUSES legitimate cross-rate rebuilds (AirPods 24k ↔ built-in 48k), gives up after
4×250ms permanently → recording goes DEAF on the new route (both the first-record race and the pull-out).
FIX: tap must install in the CURRENT hw format whenever valid (rate>0,ch>0) — the AVAudioConverter in the
write path bridges tap→file; only refuse transient invalid/disagreeing formats; retry with backoff ~3s;
NEVER permanent give-up — re-arm on every later route/config notification + observe
AVAudioEngineConfigurationChange (the canonical format-changed signal).

#### DevLog round 3 (2026-06-12 09:40, /tmp/devlog2.txt): DEADLOCK ON STALE VENDED FORMAT
ACCEPT path + echo-filter + start-retry all work. BUG: after a route flip the inputNode keeps VENDING the
old format (vended=48k vs sessionHw=24k, frozen across every retry) — AVAudioEngine caches node formats
until `engine.reset()`. The rebuild never calls reset → vended never converges → refuse-loop until user
cancels. FIX: on vended≠sessionHw in rebuild: removeTap → engine.stop() → **engine.reset()** → re-query
vended → install (+ reconnect/restart as the start path does). DevLog the reset.

#### DevLog round 4 (09:56, /tmp/devlog3.txt): DIAGNOSIS COMPLETE — WRONG PROPERTY
Even after engine.reset(), vended (inputNode.outputFormat) stays 48k forever — it's the ENGINE RENDER
format, not hardware. nodeIn (inputNode.inputFormat) = 24k AGREES with sessionHw on every line. The
validator demands the un-convergeable property. FIX (orchestrator doing it DIRECTLY, no agent): validate
nodeIn vs sessionHw; install the tap with format = inputFormat(forBus:0) (or nil); converter bridges to
file. Drop the vended check entirely.

#### ✅ AirPods P0 CLOSED — 2026-06-12, round 4 DEVICE-VERIFIED ("it works!")
Four layers, each peeled by a device trace: crash (NSException on install) → policy (refused legit
cross-rate) → cache (no engine.reset) → WRONG PROPERTY (validated outputFormat — engine-render-pinned,
can never converge — instead of inputFormat, which tracked hardware on every logged line). Final fix
applied by the orchestrator directly. Recording now survives pull-out AND re-insert.

#### Capture redesign — HYBRID SIGNED OFF 2026-06-12 ("everything works quite nicely")
Spec = `mocks/capture-redesign.html` mode 4 ⭐. One screen, one playhead, play/paused is the only state:
- ENTRY: auto-replays from −45s at 1.5× immediately (model preload stays). Full transport beneath
  (⟲5 · ▶/⏸ · 5⟳); rate pill (1×/1.5×/2×) pinned RIGHT of the row, transport stays centered.
- MARK: two buttons (「 Mark In / Mark Out 」) drop flags AT the playhead — −0.7s reaction bias while
  playing, exact while paused. Re-tap moves the flag. NO draggable handles, NO window/pan mode, NO gain
  graph, NO grains (playback IS the audio feedback).
- FINE-TUNE: ±1s chips per edge; in-chip nudges AND INSTANTLY REPLAYS from the new in-mark (the
  spam-to-find-start mechanism — MUST work while the span is playing, no pause needed; mock couldn't,
  code must); out-chips replay only the last ~5s up to the new out.
- ⟲ past the strip's left edge extends the window arbitrarily far back (clamped to the chapter file).
- Sentence-snap OUTWARD stays on confirm. ▶ Play span before Continue.
Replaces CaptureMomentView's interaction wholesale; capture SHEET (quote+ramble) unchanged.

#### Hybrid capture — first device test 2026-06-12 13:11
Screen matches the mock ✓ (sweep, transport, rate pill, marks, hints). Findings:
- **Make the capture screen FULLSCREEN + swipe-down to close** (currently floats with dead space below).
- **UX: start landed wrong — "I think it just added an extra sentence"** (user deleted the capture).
  Diagnosis: the −0.7s reaction bias can push the in-mark back ACROSS a sentence boundary into the
  previous sentence's tail; snap-OUTWARD then swallows that ENTIRE previous sentence. Bias + always-
  outward compose badly at the IN edge. Proposed (awaiting sign-off):
  (1) NEAREST-boundary snap at IN: if the mark sits in the last ~1s of the previous sentence (bias
      overshoot) snap FORWARD to the next sentence start; only snap back when the mark is genuinely
      inside the sentence. Outward stays for OUT.
  (2) Sentence-level trim on the capture SHEET: render the quote with first/last sentence droppable
      (one tap removes the leading/trailing sentence) — fix-by-reading after the fact, no re-scrub.

#### Capture round 2 — SIGNED OFF 2026-06-12 ("this works great, let's go"); one Sonnet lane
1. NEAREST-boundary snap at IN: mark in last ~1.0s of the PREVIOUS sentence (bias overshoot) → snap
   FORWARD to next sentence start; genuinely mid-sentence → snap back as today. OUT stays outward.
2. SENTENCE-TRIM on the capture sheet (spec = mocks/capture-sheet-trim.html): one grey context sentence
   each side; tap grey → include (context window slides); tap bright EDGE → drop (middles refuse w/ hint);
   audio span FOLLOWS included sentences via word timings; transcript = the existing span±buffer (already
   transcribed — zero wait). Sentence granularity only, no sub-sentence scrubber.
3. Capture adjust screen FULLSCREEN. 4. Swipe-down closes it.

#### Capture round 2 — DEVICE-VERIFIED working ("it works, very well done"). Two bugs:
1. KARAOKE broken on captured notes (word highlight/tap-to-seek no longer works during playback).
   Suspect: round-2 trim re-derives quote text+audio but the word-timings sidecar isn't re-derived/rebased
   to the final trimmed audio — or the styled-quote rendering path skips karaoke.
2. MEMO PLAYBACK and the AUDIOBOOK can play SIMULTANEOUSLY (play in a note while the book plays).
   Fix: AudioPlayerModel.play() pauses AudiobookSession (and book play should pause the memo player).
DIAGNOSIS (orchestrator): the sheet's trim is DISPLAY-ONLY — `included` changes never write back
(onFinish just closes; no re-derive of memo transcript/audio/timings). Karaoke on captures likely
collateral (sidecar/rebase or the styled-quote render path skipping karaoke). Fix design: apply trim
at the two moments that matter — when "Record your thoughts" is tapped (await apply, THEN open the
recorder so the ramble lands on trimmed audio) and on finish/close; re-derive from included sentences:
audio = exportSpan(bufferAudioURL, firstWord.start→lastWord.end), transcript = C1 blockquote of joined
sentences, timings = rebased included words → memo + WordTimings sidecar + duration. Plus: memo player
and AudiobookSession must be mutually exclusive (each pauses the other on play).

#### Session log 2026-06-12 morning (superseded — the ⭐ CONTINUE HERE entry is at the BOTTOM of this file)
STATE: `native` is green + fully landed (audiobook player + Hybrid capture + sentence-trim persistence +
playback exclusion all device-installed on Skrift Dev). NOT pushed to main; prod untouched.

1. ✅ **BUILT 2026-06-12 (refactor, inline/sole-editor) — KARAOKE on capture memos. AWAITING DEVICE VERIFY.**
   Done per the 1b mandate: the whole capture render path unified into ONE component —
   `Features/MemoDetail/TranscriptBodyView.swift`, three explicit modes derived in one place
   (playing wins → reading while transcribing → editing default). PLAYING = classic full-text karaoke
   over the WHOLE memo via new `Memo.karaokeText` (quote with "> " markers STRIPPED + ramble, one
   continuous text, word indices 1:1 with the sidecar from 0); EDITING = styled quote + attribution
   above the quote-protected ramble editor (raw "> " write-back untouched, tests still green);
   READING (transcribing) = styled quote + pill, no editor (append-clobber protection kept).
   DELETED: TranscriptContentView + overrideText/baseWordOffset plumbing + CaptureQuote.spokenWordCount
   (~215 lines out of MemoDetailView). BONUS FIX: the old "working" karaoke counted the ">" markers as
   words → captures were silently off-by-N vs the timings; karaokeText fixes the alignment by design.
   3 dup imageURL(markerIndex:) helpers consolidated onto Memo. Gate: full sim suite green (33 UI +
   unit bundles, 0 failures); new tests pin karaokeText + mode precedence. Dev build installed on the
   iPhone. **USER: verify karaoke on a capture WITH a ramble present (and quote-only).**
1c. ✅ **KARAOKE DEVICE-VERIFIED 2026-06-12 ("it pretty much works")** — full-text quote+ramble highlight
   confirmed on device. Follow-up finding: "tap a word → jump" did nothing — NOT a bug: tap-to-seek was an
   opt-in Settings toggle (`karaokeTapToSeek`, default OFF) and the device prefs (pulled over USB) had it
   unset. USER CALL: **default flipped to ON** (commit 0808543; toggle kept for opting back to the crisp
   single-Text rendering).
1d. ✅ **Round 2 (same day) — tap-to-seek verified working; two presentation findings, BOTH FIXED:**
   (a) quote+ramble "all mixed together, no division" — root cause: the tap-to-seek FlowLayout flattens
   ALL whitespace, so the \n\n division the AttributedString path kept (their first, toggle-off test)
   collapsed once tap-to-seek became default. (b) layout jumped on play (styled quote swapped out).
   FIX (design-level, playing mode evolved): the capture KEEPS its styled quote frame during playback —
   `CaptureQuoteFrame` (accent bar + attribution, shared by all 3 modes) now wraps the LIVE karaoke quote
   text (italic, offset 0) with the ramble karaoke below (offset `spokenWordCount`, re-added) → no jump,
   unmistakable book-vs-own-words division, highlight still continuous. Plus `KaraokeWordLayout.lines`
   (pure + tested): the word grid stacks per-line FlowLayout blocks so paragraph breaks survive in ALL
   memos (multi-append rambles included). `Memo.karaokeText` deleted again (regions replaced it).
   ✅ DEVICE-VERIFIED same day ("very close, looks way better"). One P2 polish nit logged, NOT blocking
   (user: "pretty good", moved on): on play the text spreads slightly vertically — the tap-to-seek word
   grid's FlowLayout lineSpacing 6 + per-line VStack spacing 8 vs the static text's lineSpacing 4; tune
   the grid constants to match. USER MOVED ON TO THE BOARD → capture items build started 2026-06-12.
5. **CAPTURE ITEMS BUILT 2026-06-12 (board item 1) — two Sonnet lanes + orchestrator integration; AWAITING
   DEVICE VERIFY.** Contract-first: `Skrift_Native/CAPTURE_CONTRACT.md` (C3) pinned the wire seam (no audio
   part + sharedContent = capture; literal fixture both lanes test against). Lane M = SkriftShare extension
   target + App Group inbox + share sheet (mock state 1) + capture upload + list/detail (state 2). Lane D =
   UploadService capture branch + skip/enhance-lite pipeline + compile/export pinned block + review surface
   (state 3). Integration fixes (orchestrator): 3 one-line compile slips; QueueDerivations read snake_case
   only (phone sends camelCase); ADDED the mock's shared-content card to the review column (lane built it
   export-only); **launch crash fixed** — `SkriftAppGroup` Info.plist key was extension-only + CaptureInbox
   assertionFailure trapped Debug at launch (every UI test "app not running") → key added to the APP plist,
   fallback derives dev/prod group from the bundle ID instead of trapping. Gates: desktop UnitTests 223/0 +
   full build + `-snapshot-capture` mock-faithful; mobile full suite green (see commit). V1 flags: no mic in
   the sheet (memory ceiling), no location/weather on captures, tags/title Mac-suggested only. **USER:
   share a URL → annotate → rate → Save; check the row/detail; then sync to the dev Mac and check the
   review surface + export.** Known-untested: real share-sheet payloads from third-party apps (sim tests
   cover the inbox/upload logic, not the OS share UI).
2. Then user re-tests: trim persistence end-to-end (tap sentence → ramble → saved audio/text/karaoke match).
3. Owed smalls — **BUILT 2026-06-12 (this session, pending device verify):**
   - ✅ Reverse playback exclusion BUILT — `AudioPlayerModel.nowPlaying` (static weak) +
     one guarded `pause()` at the top of `AudiobookSession.play()`; cleared on pause/stop/finish.
   - ✅ Ready-screen flash BUILT — instant record now shows a quiet "Starting…" placeholder instead of
     the legacy ready screen (RecordView `showManualReady`); the mic-button screen survives ONLY as the
     empty-stop retry surface + a ~7 s fallback when the auto-start retry loop gives up.
   - Mini-player idle auto-hide (2 h `idleEndDelay`) + Siri "Resume my book" (`ResumeAudiobookIntent`):
     CONFIRMED SHIPPED in code — user test still owed.
   - ✅ Watch item (stale Live Activity on lock screen): user considers it fixed — CLOSED.
4. THE BOARD — **ORDER LOCKED BY USER 2026-06-12:**
   1) **Capture-items build** (mock signed off — share URL/text/image + annotate; mobile share-extension
      target + App Group + `attachments` multipart; desktop non-audio capture content type; folds in the
      unified source taxonomy + "share video from Photos doesn't list Skrift").
   2) **Custom vocabulary build** (spike done — CTC keyword-spot + rescore in both transcribers +
      Settings "Custom words" list; ~97.5 MB extra model).
   3) **Models tab in phone Settings** (user re-confirmed: "a tab that says models" — list the on-device
      models w/ downloaded state/size; spec already under "Show downloaded models in phone Settings";
      Mac mirror later).
   4) **Prod promotion LAST** — push native→main + Release builds both apps when prod idle.
   **Significance-wall design session: DEFERRED** (user call).
   Status audit done same session: swipe-to-delete ALREADY DONE (native `.swipeActions` in MemosListView
   — item 3.5 partially closed; nicer drag-multi-select still open); confirmed-bugs list all still open
   (names auto-sync after enroll, Mac name-a-speaker UI, photo marker drift, confidence colours). QoL
   user picks: record-a-sample voice enroll = yes (later); desktop unlink-popover "Change to →" = yes.
PROCESS (now in skill rules): single bugs = orchestrator edits directly; lanes ONLY for batches; Sonnet for
specced lanes / Opus for taste; verify lane CLAIMS against write-paths. Feedback loop: "pull my feedback"
(skill) + devlog.txt for anything hardware-ish.
1b. ✅ **DONE 2026-06-12 — the refactor mandate was executed as specified** (whole path read first, then
   unified into the 3-mode `TranscriptBodyView`; quote-protection intact; inline as sole editor; sim
   gate green; installed to device). See item 1 for the full shape. Device verification owed by user.

#### (superseded by the ⭐ block at the bottom) — session wrap 2026-06-12 evening
STATE: `native` green through `df4850b`. Everything below is committed, sim-gated green (mobile 336 unit +
33 UI; desktop 223 unit + full build), and the DEV builds are installed: phone = Skrift Dev with capture
items; Mac dev build in DerivedData (launch on request for the round-trip test). NOT pushed to main; prod
untouched. The C3 contract doc is `Skrift_Native/CAPTURE_CONTRACT.md`; capability map in FEATURES.md.

SHIPPED THIS SESSION:
- ✅ DEVICE-VERIFIED: karaoke refactor (3-mode `TranscriptBodyView`, full-text capture karaoke), tap-to-seek
  default ON, round-2 presentation (styled quote frame stays live during playback; paragraph-true word grid).
- 📲 INSTALLED, AWAITING USER TEST: reverse playback exclusion; instant-record "Starting…" placeholder
  (ready-flash gone); CAPTURE ITEMS both apps (share extension + App Group inbox + share sheet + capture
  upload + list/detail; desktop ingest/pipeline/compile/export + review surface, snapshot-verified).
- Process: lanes rules.md gained "prove your base" (user-approved); CLAUDE.md records the App-Group CLI
  signing limitation (Xcode one-time visit done for dev IDs; Release IDs owe one at prod promotion).

USER FEEDBACK 2026-06-12 evening: "coming in from Safari was a bit shit" → ✅ REPRODUCED IN SIM + FIXED
(commits 7f76a77 + 6b95070; full gate green). A Safari-driving XCUITest probe
(`ShareFlowProbeUITests`, opt-in via TEST_RUNNER_RUN_SHARE_PROBE=1, screenshots to
/tmp/skrift-share-shots) reproduced the whole flow and caught FOUR stacked share-sheet bugs:
(1) keyboard buried significance+Save with no dismiss (ignoresSafeArea(.bottom) ate the keyboard
safe area → .container + keyboard-Done + scrim-tap unfocuses first — Save was literally
unreachable while typing, captures got lost); (2) light-mode innards on the dark shell
(preferredColorScheme is a no-op in extension UIHostingControllers → overrideUserInterfaceStyle);
(3) annotation TextEditor greedily filled the sheet (cap maxHeight 110); (4) the host content-hugs
the remote view leaving an unpaintable gray sheet backdrop (preferredContentSize 10k + opaque
#0e0f16 canvas). Sim E2E now verified: share → annotate → rate (works with keyboard up) → Save →
app inbox drain → capture row → detail (Open ↗ / annotation / Will-sync). SIM GOTCHA learned:
the share-sheet host caches extension processes per boot — reboot the sim after reinstalling
or you'll screenshot the stale extension. The fixed dev build is INSTALLED on the iPhone
(build 2026-06-12 evening, incl. share-sheet fixes); prod untouched.

USER FEEDBACK round 2 ("no way to record a voice message from sharing in safari — only type")
→ ✅ BUILT same evening + INSTALLED on the phone. The mock's mic, deferred-transcription design
(the v1 "no mic" flag is CLOSED): extension only RECORDS (Parakeet can't fit its ~120 MB memory
ceiling) → audio rides the App Group inbox → the APP transcribes on drain with the same Parakeet
engine → appends to the annotation, audio discarded (kept + Error pill on failure, re-kicked every
drain). Sync holds captures until transcription lands; detail editor swapped out meanwhile (clobber
window). Sim-verified (recording state + voice-note chip screenshots; 7 new unit tests incl. sync
gate + crash recovery; full gate green). DEVICE TEST OWED: share → tap mic (first time: mic
permission prompt INSIDE the share sheet) → talk → Save → open Skrift Dev → watch the annotation
fill in; then rate + sync → Mac gets the full text. C3 contract untouched (uploads stay text-only).

NEXT-SESSION DEVICE TEST LIST (in rough order):
1. CAPTURE phone half: Safari → Share → "Skrift Dev" (first time: enable via the share sheet's More/Edit
   row) → annotate + rate → Save → OPEN Skrift Dev (inbox drains on launch/foreground) → capture row +
   detail (Open ↗, editable annotation, no player bar). Also try a TEXT selection share + a PHOTO share.
   ↳ 2026-06-12 evening: sim-verified incl. the UX fixes above; device re-test still owed (esp. the
   share-from-Photos / text-selection variants + the first-time enable row).
2. CAPTURE Mac half: launch the dev desktop app → phone syncs the rated capture → review surface (source
   strip + banner + SHARED CONTENT card + url prop row) → Export to the test vault → check the .md
   (frontmatter url:/source:, pinned block above the annotation).
   ↳ 2026-06-12 evening: the WHOLE Mac half verified headlessly (commit 7799848) — real POST of the C3
   fixture → dev server → store row contract-perfect → REAL Gemma enhance-lite (title+summary on the
   annotation, no copy-edit) → compile → export to the test vault. New DEBUG flag `-processfile <id>
   [-exportafter]` (RunFile) runs Process+Export headlessly on any stored file — reuse it for future
   round-trips. CAUGHT + FIXED two export bugs affecting ALL notes: (1) filenames kept Obsidian-forbidden
   chars (Gemma's "Title: Subtitle" colons); (2) frontmatter title:/summary: unquoted → ': ' in a Gemma
   title makes Obsidian reject the whole frontmatter — both now sanitised/quoted + tests. What's left for
   the user here = just the visual review-surface check on a phone-synced capture. NOTE: a probe capture
   (Stoicism - Wikipedia, from the sim run) lives in the DEV store + an exported probe .md in the test
   vault — delete on sight if they get in the way. The dev desktop GUI app is currently QUIT.
3. Trim persistence end-to-end (OWED since the morning): capture sheet → tap a sentence in/out → ramble →
   saved audio/text/karaoke all match the trimmed span.
4. Reverse exclusion: play a memo in detail → start the audiobook → the memo must pause.
5. Instant record: no legacy ready-screen flash — brief "Starting…" then the live caption.
6. Mini-player 2 h idle auto-hide + Siri "Resume my book in Skrift" (shipped 2026-06-11, never tested).
7. Karaoke playback spacing nit (P2): confirm the slight vertical spread during playback is acceptable,
   or ask for the word-grid constant tune (FlowLayout lineSpacing 6 / VStack 8 vs static lineSpacing 4).

THE BOARD (user-locked order):
1. ✅ Capture items — BUILT, verify above.
2. CUSTOM VOCABULARY build (spike done 2026-06-11): CTC keyword-spot + rescore in BOTH transcribers +
   Settings "Custom words" list; one extra ~97.5 MB HF model. Integration pattern documented in the
   "Feature decisions — LOCKED 2026-06-10" §3 entry above.
3. MODELS TAB in phone Settings (list on-device models w/ state/size; spec under "Show downloaded models
   in phone Settings"; Mac mirror later).
4. PROD PROMOTION LAST: push native→main + Release builds both apps while prod idle. NOTE: Release bundle
   IDs need the one-time Xcode App-Group signing visit (same two clicks as dev, recorded in CLAUDE.md).
Significance-wall design session: DEFERRED (user call 2026-06-12).

OUTSTANDING (later, off the board):
- Confirmed bugs: names DON'T auto-sync after voice enroll (manual sync only); Mac "name a speaker" review
  UI (backend done, mock `name-a-speaker.html` awaits sign-off) + live enroll→auto-label round-trip;
  photo `[[img_NNN]]` marker drift (anchor by TIME not word count); confidence colours wrong in practice.
- Capture-items v1 flags (deliberate, flip on demand): no mic dictation in the sheet (extension memory
  ceiling); no location/weather on captures; "file" share type has no pinned block; UI-test capture
  seeding skipped (unit tests cover the logic); real third-party share payloads untested.
- QoL: drag-multi-select on the memos list (swipe-delete done); record-a-sample voice enroll in Names &
  voices; desktop unlink popover "Change to → <person>"; karaoke playback-grid spacing tune (P2).
- ✅ Audit nits — RECONCILED 2026-06-13 (verified each against CURRENT code + live on the fixture; the
  "open" citations were stale, written mid-desktop-track and never reconciled after the fixes landed):
  desktop sidecar try? writes (logged), 256 MB cap + early 413 (done), main.sync bridge (marshaled to
  main + NOW guarded by `dispatchPrecondition(.notOnQueue(.main))`), model idle-unload (real `unload()`
  fires 60 s idle — proven: idle `/health` returns available:false), real word_timings→karaoke (done,
  `BatchRunner:40`; runfile logs `word_timings: 90` on the two-Jacks fixture), `/health` truthful
  (`isModelReadySync`, not hardcoded), parity golden tests (`UnlinkTests`/`CompilerTests` cover it),
  HEIC→JPG (ImageIO now, fallback recomputes the md ref — old `sips` nit gone), snapshot try? (now
  logs write FAILED). Mobile — recorder deinit (belt-and-braces inline), silent-video import (titles
  "Video had no audio track"), photo-marker drift + confidence colours (fixed this wave). Commit dd…
  (`harden(desktop)`). NOTHING in this list is still open.
- With-user sessions: re-ingest ~30 old notes (`~/Desktop/Skrift old notes/`, prod quit, real vault);
  "transcription a bit weird" cold-start (parked unless seen again).

#### Session 2026-06-13 — desktop architecture A-list verified-done + Trash mirror built
- Verified the desktop "A-list" against CURRENT code + live (the backlog/CLAUDE citations were stale):
  model-unload, real word_timings→karaoke, 256MB cap+413, main-actor SwiftData marshal, truthful /health
  — ALL already done. Hardened the two genuine remainders: SwiftData-bridge invariant now enforced
  (`dispatchPrecondition(.notOnQueue(.main))`), snapshot write no longer claims success on failure
  (commit `2ac3d32`). Audit-nits section reconciled (`4a6a982`).
- ✅ **Desktop Trash / Recently Deleted** built (commit after `4a6a982`) — see board item 4 above.
- STILL genuinely open (features needing a pick/mock/user, NOT bugs): Mac "name a speaker" UI (mock
  awaits sign-off), drag-multi-select (mock first), watched-folder ingest, Backlink Weaver, unified
  source taxonomy, record-a-sample voice enroll (device voice), re-ingest 30 notes (with user), prod
  promotion (device tests + Release App-Group Xcode visit). Significance-wall = user-deferred.
- Deferred ideas: watched-folder ingest; summary prompt quality pass; tag lemma expansion; north-star
  semantic timeline ("how my thinking evolved").

#### CONTINUE HERE (SUPERSEDED — see the ⭐ block at the BOTTOM of this file, 2026-06-13 night) — session wrap 2026-06-12 night (the "do all outstanding" batch)
STATE: `native` green; every gate passed per commit (mobile 352 unit + 38 UI; desktop 231 unit + full
build). NOT pushed to main; prod untouched. PHONE: has capture items + share-sheet UX fixes + DICTATION
(installed earlier tonight); the LAST build (vocab + models tab + bug fixes + QoL) is STAGED in
`build-device/` — phone went unavailable before install. Install when plugged in + unlocked:
`xcrun devicectl device install app --device 00008110-001208C902EA201E Skrift_Native/SkriftMobile/build-device/Build/Products/Debug-iphoneos/SkriftMobile.app`

SHIPPED THIS SESSION (all sim/headless-verified, commits in order):
- Share-sheet UX pass (7f76a77+6b95070): keyboard buried Save (captures losable!) / light-on-dark mix /
  giant TextEditor / gray host backdrop — all fixed; Safari+Photos probes (opt-in) screenshot the flow E2E.
- Mac capture half verified LIVE (7799848): C3 fixture POST → store → real Gemma enhance-lite → export.
  New DEBUG flag `-processfile <id> [-exportafter]`. CAUGHT: Obsidian-forbidden filename chars + unquoted
  YAML title/summary (Gemma colons break Obsidian frontmatter) — both fixed, all exports affected.
- VOICE DICTATION in the share sheet (user ask): extension records (no model in-process), app transcribes
  on drain → annotation; sync holds till done; crash/failure recovery; ON THE PHONE already.
- CUSTOM VOCABULARY (board 2): CTC spot+rescore in BOTH transcribers + Settings editors both apps +
  word-timings re-alignment; `-runfile -vocab "A,B"`; LIVE-verified (planted "Jacques" replaced, real
  Jacks untouched). Dev Mac settings carry ["Skrift"]. Lists are per-device v1 (no sync — possible later).
- MODELS TAB (board 3): Settings → Library → Models (3 models, downloaded state + sizes). Mac mirror later.
- CONFIRMED BUGS fixed: names AUTO-SYNC after voice enroll (debounced push, no-op unpaired); photo-marker
  drift (marks anchored to the words they followed); caption colours now TRUTHFUL (solid = rotated
  committed chunks — a real finalized signal; volatile = live chunk; expect a LARGER lighter tail
  on device, up to ~25s — that's honest, not a regression).
- QoL: desktop unlink popover "CHANGE THIS MENTION TO →" (two-Jacks one-tap fix, Sanitiser.relinkOccurrence);
  karaoke grid spacing matches static text; silent-video failures self-titled. Git housekeeping done
  (haslett worktree + robustness-cleanup local branch removed — both targeted archived apps only).

DEVICE-TEST LIST (新, on top of the morning list):
1. Share from Safari with the NEW sheet: type + tap circles + Save WITH the keyboard up; dictate a
   voice note (first time = mic permission inside the sheet) → open Skrift Dev → annotation fills in.
2. Custom words: Settings → Capture → Custom words → add "Skrift" → record a memo saying it.
3. Models tab shows real sizes once models are on the phone.
4. Voice-enroll someone → names should reach the Mac WITHOUT a manual sync tap (~3s).
5. Live caption: solid text never changes now; lighter tail is longer than before (honest).
6. Desktop: click a [[Name]] → "Change this mention to →" the other Jack.

NOT DONE, with reasons:
- Significance wall / printer pipeline — user said skip.
- PROD PROMOTION — blocked on the device tests above + the one-time Xcode App-Group signing visit for
  the Release bundle IDs (CLAUDE.md records the steps).
- Mac "name a speaker" review UI — mock `name-a-speaker.html` still awaits sign-off (locked process).
- Drag-to-multi-select on the memos list — interaction design wants a mock first (locked UI process).
- Record-a-sample voice enroll in Names & voices — conversation-track; needs real-voice device
  validation; do with the next conversation-mode session.
- Desktop trash mirror, source-taxonomy unification pass, desktop A-list perf nits (multipart RAM cap,
  main.sync bridge, desktop real-timings karaoke, parity golden tests) — pre-existing backlog, untouched.
- Re-ingest ~30 old notes + "transcription a bit weird" — with-user sessions.

#### Text-first audiobook capture — DESIGNED + WAVE 1 BUILT 2026-06-13 (installed on the phone)
Trigger: real (non-builder) testers couldn't use the shipped Hybrid audio-marking capture
(didn't get in/out marks, too many buttons, didn't know sentences were tappable). Designed a
**text-first** alternative WITH the user + 2 verification agents (code-reality + locked-decisions)
+ 2 UX critics (caught the warming-screen purple-button misfire — "brightest element must be the
one intended action"). Full design + all decisions/nuances: `SkriftDesktop/mocks/text-capture-DESIGN.md`;
signed-off interactive mock: `mocks/text-capture.html`.

**LOCKED design points:** ships ALONGSIDE audio mode (A/B, Settings → Audiobooks Audio·Text toggle,
default Audio), surgically removable; the isolation seam is the `QuoteCaptureOutput` (Text mode emits
a GLOBAL span → SAME processor/sheet/save/sync/export). Tap-+-to-add / ✕-to-drop sentence select;
last line pre-picked; scroll (no button); "Hear selection" plays the span at 1.5×; warming screen is
just a wait (whole-book offer is a bottom link, NOT a button); no-speech = tiny "back to book"; no
false "place saved" reassurance. 35 s = one-time engine WARM-UP (not inference; ~1 s warm/screen).
Chunking = the path; **resumability locked** (chunk sidecar IS the resume state; discard the in-flight
half-chunk; pause-on-unplug/auto-resume). Whole-book transcribe = best overnight/plugged; ≈X-min/hr
estimate is a PLACEHOLDER pending real phone measurement.

**WAVE 1 BUILT (commit + installed):** the toggle, `TextCaptureView` (sentence-select),
`QuoteCaptureProcessor.transcribeWindowForDisplay`, the router in `QuoteCaptureFlowView` (both modes →
`confirmCapture(_:span:)`). 343 unit (+7 TextCaptureTests) + 38 UI green. Real transcription is
device-owed (no audiobook UI harness in the sim).
**OWED — DEVICE TEST (put it in front of the same testers):** flip Settings → Audiobooks → Text;
in a book, hit Capture → sentence-select; the two things to watch — (1) does +/✕ read as tappable
WITHOUT being told? (2) does the pre-pick + sandwich make EXTENDING feel natural, or do they just
confirm one line? If +/✕ still isn't instant, next lever = a one-time coachmark.
**WAVE 2 — BUILDING 2026-06-13 (user greenlit):** `BookTranscript` sidecar + chunker + resumable
overnight transcribe job + the transcribe-book button + instant-capture-from-sidecar + pre-warm-on-
book-open. Measure the real per-hour transcribe speed on the phone to replace the placeholder.
Multi-file/chapter-boundary confinement is already code-enforced (`QuoteCaptureProcessor:69-76`) — kept.
- ✅ Sidecar (`BookTranscript`/`FileTranscript` + `BookTranscriptStore`, per-file JSON, atomic write,
  `size:mtime` staleness, file-local word-timings; sentences derived on read via `buildSentences`).
- ✅ Chunk-seam fusion (`ChunkFusion`): cut at the last complete sentence, re-transcribe the tail next
  chunk — no split/dup words, uses `SentenceSnap`; run-on/silence fallbacks. Unit-tested.
- ✅ Resumable job (`BookTranscriptionJob`): sequential per-file chunk loop, save-after-complete =
  resume state (in-flight chunk discarded on interruption), pause-on-unplug + auto-resume on charge,
  foreground Pause/Resume, yields to live capture between chunks. Engine path device-owed.
- ✅ ⋯ "Transcribe book" button + sheet (`TranscribeBookView`, Text mode only): progress + %, Start/
  Pause/Resume, design §12/§13 copy. Instant-capture-from-sidecar (`TextCaptureView` Source +
  `buildOutputFromSidecar`; un-chunked → wave-1 fallback). Pre-warm on book-open in Text mode when the
  spot is un-chunked; live capture pauses the bg job.
- ✅ Real per-device speed: the job measures its own RTF (persisted) → the sheet shows a measured
  "≈ N min" estimate (placeholder removed). Mac `-asrbench` = ~100–134× realtime (inference tiny vs
  audio); the phone's absolute number is device-measured (job DevLogs per-chunk timing).
- **DEVICE-OWED:** real ASR on the phone (sim has no ANE) — run "Transcribe book" on a real book,
  watch the progress + the measured min/hr in the devlog, then capture at a done spot (instant, no
  warming screen) and at an un-done spot (wave-1 fallback); verify pause-on-unplug/auto-resume + that
  an interrupted job resumes from the last saved chunk.

#### Player redesign DEVICE TEST 2026-06-13 (night) — 2 fixes
- ✅ **Transcribe sheet showed "Resume transcribing" at 100% done** (device screenshot). Cause: the
  job clears `activeBookID` on finish → `isThisBook` flips false → the `.finished` control case was
  skipped → fell to the "Resume" default. Fixed: TranscribeBookView gates the done-state on
  **progress ≥ 0.999** (lede "Done…", a "Fully transcribed" indicator instead of a button, estimate
  hidden) — robust for both just-finished and a re-opened already-done book.
- ✅ **Read-along "text smaller & jumps fast" → Spotify lyrics** (device feedback). Reworked
  `ReadAlongView` from one re-coloring/reloading paragraph to discrete **lyric LINES**: current line
  large + bright (21 pt), neighbours dim by distance, **smooth auto-scroll** (centered, animated),
  soft edge fade, tap-a-line-to-seek. Loads the WHOLE covered prefix once (reloads only on coverage-
  frontier cross / file change) so scrolling is smooth, not jumpy. Device-owed re-look.
- ✅✅ **ROOT CAUSE of read-along trailing — chunker time-DRIFT (2026-06-13, proven on Mac).** Built a
  headless harness (`-readalongcheck`, `-chunksim` + `anchorDrift`, desktop `RunFile`): pulled the
  real book audio + sidecars off the phone, transcribed each chapter WHOLE on the Mac as ground truth,
  aligned on words unique-in-both. f0 (2 chunks) was clean (±0.08 s); **f2 "Beginning" (14 chunks)
  drifted monotonically late: thirds +0.40/+0.81/+1.99 s** — so no fixed lead could fix it. `-chunksim`
  reproduced + isolated the cause: **per-chunk `AVAssetExportSession` extraction from the compressed
  MP3 isn't time-accurate (error grows with seek position): thirds −0.24/+0.38/+0.96; sample-accurate
  `AVAudioFile` PCM frame reads = −0.02/−0.02/−0.01 (flat).** FIX (mobile): `BookTranscriptionJob`
  now extracts chunks via `extractPCM` (AVAudioFile → temp WAV), NOT exportSpan. `FileTranscript`
  schema 1→2 so the already-drifted sidecars re-transcribe. Quote-audio carving keeps exportSpan (a
  few-ms shift there is inaudible). Device re-test: re-transcribe "Do the Work", read-along should now
  ride the voice the whole chapter.
- ✅ **Read-along "text lags behind voice"** (device feedback) — also addressed the latency layer. The
  AVPlayer playhead (`session.currentTime`) only ticks every 0.5 s, so the lit line was quantized to
  half-second steps and always trailed. Fixed: `ReadAlongView` now INTERPOLATES the playhead between
  ticks (anchor + wall-elapsed × `session.rate`) on a 0.1 s timer, plus a small `lead` (0.2 s) for
  Parakeet-TDT's slightly-late word timings, and a snappier highlight (0.18 s). Lit line now tracks
  the narrator. `lead` is tunable if it reads early/late on device.

#### Wave-2 DEVICE TEST 2026-06-13 (evening) — vocab + transcribe-book
- ✅ **Custom vocab WORKS on device now** (user: "customs words are working"). Pre-warm-at-launch was
  the fix, confirmed.
- ✅ Transcribe-book runs: progress moves, measured estimate shows ("~11-12 min left"), pause-on-
  unplug → "plug in to continue" → auto-resume on charge all confirmed ("very cool"). Resume after
  force-quit PRESERVES progress (11% survived) — the sidecar resume state works.
- ✅ FIXED two device-found bugs (commit): (1) the transcribe sheet showed **0% on reopen** until
  Start (saved % wasn't displayed — data was fine); now `reflectSavedProgress` seeds the bar/label/
  estimate from the sidecar on open. (2) **Start while already charging showed "paused, plug in"** —
  `isPluggedIn` was read before battery monitoring was enabled (→ `.unknown` → false unplugged);
  monitoring now enabled in `init` + before the read in `start`.
- ✅ **UX — library long-press to transcribe (BUILT 2026-06-13):** `AudiobookLibraryView` rows got a
  `.contextMenu` — "Transcribe book" (Text mode) presents `TranscribeBookView` for that book without
  opening it; + Delete. No need to open book → ⋯.
- ✅ **UX — Control Center / record-widget icon (BUILT 2026-06-13):** the literal app icon CAN'T be a
  Control Center glyph (it's a detailed 3-D render; Control Center renders simple MONOCHROME templates
  → its silhouette is an indistinct blob). Control Center control kept as `mic.fill` (clear record
  glyph, already labelled "Skrift"). Real fix applied: the Home/Lock **record widget** was a generic
  RED mic-dot while the in-app record button is `skAccent` purple — rebranded the widget to the Skrift
  accent (`RecordWidget.accent` = 0x7c6bf5) so it reads as Skrift. A custom monochrome Skrift logomark
  for Control Center is a later option (needs simple mark artwork, not the 3-D icon).
- ✅ **Audiobook player UI redesign — DESIGN SIGNED OFF 2026-06-13** (grill-me). Spec mock:
  `Skrift_Native/SkriftDesktop/mocks/audiobook-player-redesign.html`. Direction = **text-forward
  A+D hybrid**: warm cover-derived tint header; cover demoted to a 56px chip; **live read-along text
  is the hero**, current line lit (reuse `Karaoke.activeWordIndex` on the sidecar word-timings); `Ch
  N/M` pill; speed◁ transport ▷sleep; slim **Chapters + Bookmark** icon row above a hero **Capture
  this** pill. Un-transcribed spot → **"Transcribe this book to read along →" nudge** (routes to
  `TranscribeBookView` — the player sells the transcribe feature). No read-along on/off toggle (v1).
  Resolved via grill: feature set = bookmarks + surfaced chapters (NOT AirPlay — Control Center
  covers it; NOT skip-silence/EQ). **Bookmark = NET-NEW, lightweight:** tap drops a marker (global
  position + chapter + timestamp), haptic + toast; list in the Chapters sheet under a Bookmarks tab
  (jump / swipe-delete); Capture stays the rich save. Mock-first step done.
  - ✅ **BUILT 2026-06-13** (autonomous): `Bookmark.swift` (model + `BookmarkStore`, per-book JSON,
    near-dupe guard, 6 unit tests); `ChaptersBookmarksSheet.swift` (Chapters | Bookmarks tabs);
    `ReadAlongView.swift` (sidecar-fed read-along, current line lit via cached window + per-tick
    recompute; nudge when un-chunked → TranscribeBookView); `AudiobookPlayerView` rewritten to the
    text-forward layout (cover-tint header from `UIImage.averageColor`, 56px cover chip, Ch N/M pill,
    speed◁/sleep▷ flanking transport, slim Chapters+Bookmark row, hero "Capture this"). Chapters
    removed from the ⋯ menu (now the sheet + slim row). App builds, bookmark unit tests green.
  - **DEVICE-OWED:** visual check (no headless iOS screenshot) + the read-along is only real on a
    transcribed book (sim has no ANE → shows the nudge). Verify: cover-tint band, read-along lit line
    tracking playback on a transcribed book, nudge on an un-transcribed one, bookmark drop+toast,
    Chapters/Bookmarks sheet jump + swipe-delete.
  - **GATES:** app builds (sim + device) ✓; **396 unit tests green** (incl. 6 bookmark); device build
    ✓ + INSTALLED. UI suite (re-run at low load): 36/38 ran-and-passed; the 2 failures
    (`testEnrolledPersonAutoLabeledOnSplit`, `testSplitSpeakersButtonSplitsIntoTurns` — both
    speaker-diarization, UNRELATED to the player/library/widget changes) fail on the fresh-erased-sim
    permission-dialog + onboarding wall (`allow-media`/`allow-location`/`get-started-button`), not an
    assertion — they passed earlier this session on a stateful sim (412-green). No UI tests exercise
    the changed audiobook player/library/widget surfaces. (Earlier mass UI failures were the host at
    load ~80 SIGTERM-ing the runner; resolved once load dropped.)
- Note: charging-state can lag a second after plugging in mid-run (iOS `batteryStateDidChange`
  latency); self-corrects. Acceptable.

#### Text-capture round 2 device feedback 2026-06-13 (evening)
PASSED: text-capture double-select GONE ("I can record my thoughts. Nice."); +/✕ & extend confirmed.
SHIPPED + installed: share-sheet PROMINENT record button (was a missed tiny mic — "why doesn't it
just have a button to record like the rest of the app"); ShareSheetView reworked (record primary,
type secondary). Vocab booster INSTRUMENTED with DevLog (spot/rescore outcome + replacements).
CONFIRMED BUG — custom vocab does NOT correct "Script"→"Skrift" with the model loaded. Next:
user records one more Skrift memo → pull devlog.txt → the `vocab:` line says whether the SPOTTER
missed it (phonetic limit) or the RESCORER declined (loosen minSimilarity/cbw). Don't blind-tune.
OPEN: (a) old stuck-"Transcribing" memos from the pre-fix build — delete, or add a launch
reconciler that re-transcribes stuck .transcribing memos (offered). (b) "sentence breaks up
strangely" in text capture — awaiting the capture-screen screenshot; likely Parakeet punctuation
(abbreviations like "Dr.") splitting sentences in SentenceSnap.isSentenceEnd.

#### ✅ CUSTOM VOCAB — VERDICT + FIX (2026-06-13, both apps)
**Devlog verdict = NEITHER spotter nor rescorer; the booster was never READY.** The fresh
`vocab:` lines (14:26:58) read `not ready (loaded=[], rescorer=false) → bg prepare, unboosted` —
no `wasModified` line ever appeared, so the boost never reached spot/rescore. Root cause: the
booster's spotter/rescorer are per-PROCESS in-memory state that resets every launch, and the
non-blocking design (the queue-jam fix) makes the FIRST transcribe skip while the ~97 MB ctc110m
loads in the background. The user records ~one memo per launch → it always raced the load → always
unboosted. "Model downloaded" (Models tab = on-disk) ≠ "booster warm" (in-memory, per-session).
**Mac ground truth** (`-runfile -vocab` with a synchronous prewarm + booster stderr diagnostic;
no phone audio needed): once warm, the spotter detects + the rescorer replaces — proven
(`Jacques: jack` alias surfaced `Jacques` at sim 0.43, below the 0.50 floor, and replaced).
script→Skrift is an EASIER case (sim 0.667, candidate already surfaces; the audio genuinely says
"skrift" so the acoustic gate favours it).
**FIX (committed, both apps):** (1) **pre-warm** the booster at launch when custom words exist →
the confirmed bug; (2) **aliases** via `"Canonical: alias1, alias2"` → user-controllable widening
for stubborn mis-hearings; (3) **trust guard** → FluidAudio's spotter-anchored rescue mangles
ordinary speech once warm (negative-control clip turned `room→Rox`, `its alias.→Tiuri`); the
booster now drops a boost when EVERY replacement is a distant acoustic-only guess (sim < 0.55 AND
no alias) → negative control verified CLEAN. cbw tuning was a DEAD END (even cbw=2.0 kept the FPs —
the original words' constrained-CTC scores are too low). cbw stays at FluidAudio's 4.5.
**DEVICE RE-TEST (owed — phone was unavailable this session):** with the new build, in Skrift Dev
say "Skrift" once → it should now correct (booster warm at launch). If a SHORT/uncommon word
(≤3-4 char, e.g. "Rox") still mis-fires on unrelated speech, drop it or add it with an explicit
alias; report and we tighten further. Note: very short words are inherently spotter-FP-prone.

#### ⭐ CONTINUE HERE — session wrap 2026-06-13 night
STATE: branch `native`, all committed, **`main` untouched / not pushed, prod untouched**. Mobile dev
build ("Skrift Dev", `com.skrift.mobile.dev`) **installed on the iPhone 13** (devicectl UUID
`A9195A77-601A-54C1-B3BD-659FBFE1DC54`). Desktop dev build in `build/` (vocab fix + read-along sync
harness). Gates per chunk: mobile 396 unit green (the 2 UI fails are the documented permission/
testmanagerd sim flake on unrelated speaker tests — pass on a stateful sim); desktop 248 unit + full
`-skipMacroValidation` build.

✅ SHIPPED + DEVICE-CONFIRMED:
- **Custom vocab fix** (both apps) — pre-warm booster at launch + aliases (`"Canonical: alias"`) +
  trust guard (drop distant spotter-rescue FPs, sim<0.55). **User confirmed working** ("customs words
  are working"). Root cause was readiness (per-process booster never warm), not spotter/rescorer.
  See the `✅ CUSTOM VOCAB` block above + [[project_vocab_booster]].

✅ SHIPPED (mobile, on the phone; real-ASR / read-along behaviour is device-owed to eyeball):
- **Text-capture WAVE 2** — `BookTranscript` sidecar (per-file JSON, file-local times) + `ChunkFusion`
  (cut-at-sentence, redo-tail) + `BookTranscriptionJob` (resumable charger job: save-after-complete,
  pause-on-unplug/auto-resume, yields to capture) + ⋯/long-press "Transcribe book" sheet + instant
  capture from the sidecar (else wave-1 fallback) + measured per-device speed (no placeholder).
- **Audiobook player redesign — text-forward A+D hybrid** (signed-off mock
  `Skrift_Native/SkriftDesktop/mocks/audiobook-player-redesign.html`): warm cover-tint header, 56px
  cover chip, `Ch N/M` pill, **Spotify-style read-along** (current line lit, smooth auto-scroll, edge
  fade, tap-line-to-seek), speed/sleep flanking transport, slim **Chapters + Bookmark** row, hero
  "Capture this". **Bookmarks** (light position markers) + **Chapters/Bookmarks TOC sheet**.
- **Library long-press → Transcribe book**; **record widget** rebranded red→Skrift purple.
- **Read-along sync — fully chased down + fixed (Mac harness, real data):**
  1. timings drift — per-chunk `AVAssetExportSession` on compressed MP3 drifts late, growing to
     ~+2s deep in a chapter (proven via `-chunksim`); fixed with sample-accurate `AVAudioFile`
     extraction (`extractPCM`), sidecar schema 1→2 to force re-transcribe of drifted transcripts.
  2. latency — interpolate the playhead between the 0.5s AVPlayer ticks + advance at line-END.
  3. stuck-nudge — the player now re-checks coverage every ~1.5s even paused, so a finishing
     transcribe flips nudge→read-along live (devlog proved the data was fine; it was stale UI state).
  4. smoothness + lead (device feedback "too early" + "words hustle"): lead 0.3→0.1; lines are now a
     UNIFORM 18 pt (font-size change can't animate → reflowed/shoved neighbours = the hustle), the
     current line emphasised by a smooth `scaleEffect(1.08, anchor:.leading)` (transform, no reflow) +
     brightness. Device re-eyeball owed.
  Desktop harness (`-readalongcheck`, `-chunksim`, `anchorDrift`) committed for reuse.

⏳ STILL OPEN / DEVICE-OWED (next session):
1. **Read-along final eyeball** — drift/latency/stuck-nudge/smoothness/lead all fixed + installed;
   confirm on a re-transcribed book it tracks the whole chapter, smoothly (no hustle), in-sync (not
   early). `ReadAlongView.lead` is the dial (now 0.1s) if still slightly off.
2. **Vocab — RESOLVED on device:** user confirms **both "Rox" and "Skrift" work** as custom words.
   The short-word-FP worry didn't materialise; keep as a watch-only note, no action.
3. **Control Center glyph — DECISION PENDING (candidates shown to user):** A `quote.opening` / B
   `pencil.line` (both SF Symbols, 1-line swap, ship now) vs C custom carved-strokes mark (echoes the
   app icon, needs a monochrome template asset). HOW (recorded for whoever builds it): SF option =
   change `Label("Record", systemImage:)` in `SkriftWidget/RecordControlWidget.swift` (+ RecordWidget).
   Custom = add an asset catalog to the SkriftWidget target, drop a single-colour SVG/PDF as a Symbol
   Image (or Render-As-Template), reference via `Label{} icon:{ Image("skrift.mark") }`. The 3D app
   icon itself can't be a CC glyph (CC renders monochrome templates).
4. **Wave-2 deferred** (design doc §9): cross-chapter quotes; auto-transcribe-ahead while playing;
   **A/B test integrity** for text vs audio capture (assign the arm, pre-transcribe the test book,
   define the success metric); desktop mirror of wave-2 (mobile-only today).
5. **Bookmarks**: viewing the list is via Chapters sheet → Bookmarks tab (the Bookmark button only
   drops). Consider a more direct path if it feels hidden.
6. Pre-existing untouched: **prod promotion** (one-time Xcode App-Group signing for the Release bundle
   IDs, then Release build + `native`→`main`); Mac "name a speaker" mock sign-off; drag-multi-select
   mock; record-a-sample voice enroll (conversation track); desktop A-list perf nits (multipart RAM
   cap, off-main SwiftData on the Bonjour queue, real word_timings→karaoke, parity golden tests);
   re-ingest ~30 old notes; "transcription a bit weird" investigation.
