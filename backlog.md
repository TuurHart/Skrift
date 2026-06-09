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
- **Import VIDEO → transcribe (with the real recording date)** — accept video files on the
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
1. **Significance slider on mobile + sync gating** (above) — unifies a desktop feature, contract change.
2. **Append-more-transcription to an existing note** — open a memo → a button records more audio,
   transcribes it, and appends to the existing transcript (then re-syncs). Mobile-led.
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

### Dev/prod separation (DECIDED 2026-06-08 — do AFTER this feature batch)
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
- **Desktop Liquid Glass pass** — the Mac UI has no glass treatment; bring the iOS-26 glass look to
  the desktop player/surfaces for visual parity.
- **Re-ingest the ~30 old notes** from `~/Desktop/Skrift old notes/` — run the existing ingest over
  them (DO WITH the user: needs the prod desktop app quit for the shared-store race, and it writes
  into the REAL Obsidian vault).
