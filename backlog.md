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
   detail), "Recently Deleted" sheet, lossless Restore, startup purge ≥14 days. Desktop mirror = later.
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

#### Device-test results — 2026-06-11 23:00 (first real capture, Steal Like an Artist)
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
