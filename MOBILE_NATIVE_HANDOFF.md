# Skrift Mobile Native Rewrite — HANDOFF

> ⚠️ **POST-CONVERGENCE (2026-06-07):** the iOS app moved to
> **`Skrift_Native/SkriftMobile/`** and now lives on the unified **`native`**
> branch (merged `mobile-native` + `desktop-native`; the macOS app is at
> `Skrift_Native/SkriftDesktop/`). There is no longer a separate `Skrift-desktop`
> worktree. **Absolute/relative paths in the session notes below are
> pre-move** — see the repo-root **`CLAUDE.md`** for the current build/run commands.
>
> For the next chat. Resume the **native SwiftUI rewrite** of the Skrift iOS app.
> Read this, then **`MOBILE_NATIVE_REWRITE_PLAN.md`** (the full plan — phases,
> Shhhcribble reuse, the mobile↔Mac contract, the XCUITest harness). Repo:
> `/Users/tiurihartog/Hackerman/Skrift`, branch **`native`**, app in
> `Skrift_Native/SkriftMobile/`.

## TL;DR — where we are
- Decided to rewrite the iOS companion from Expo/RN (`Mobile/`) to **native
  SwiftUI** (`SkriftMobile/`). Why: iOS-only + native-heavy (FluidAudio/ANE,
  widgets, Live Activity, App Intents, the diarization/boosting roadmap), a much
  better sim-test story (XCUITest like the Pike Companion app), and convergence
  with the user's existing native FluidAudio app **Shhhcribble**.
- **Plan:** `MOBILE_NATIVE_REWRITE_PLAN.md` (committed). Phase checklist in its §7.
- **Phase 0 (toolchain spike): ✅ GREEN** — `SkriftMobile/` xcodegen project +
  minimal SwiftUI app + first XCUITest; `xcodebuild test` passes on the iPhone 17
  sim (commit `09541e0`). Toolchain proven.
- **Phase 1 (data model): ✅ GREEN** — SwiftData `Memo` + Codable `MemoMetadata`/
  `SharedContent`, `Person`/`NamesData`, `NotesRepository`, wordTimings sidecar,
  launch-arg seed hooks. **The user pulled Phase 5's names sync forward into
  Phase 1**, so `NamesStore` + `NamesSync` (LWW + voiceEmbeddings union, injectable
  transport for `-mockMac`) shipped here too. A **unit-test target** was added
  alongside the XCUITest target: 21 tests green (merge/union/tombstone/encoding +
  full mock-transport sync flow + SwiftData repo + a seeded-memos UI test).
  **Next: Phase 2 (recording + transcription).**
- **Phase 2 (recording + transcription): ✅ GREEN** — FluidAudio `main` SPM dep
  builds for the sim. `TranscriptionService` (actor): one-shot file transcribe
  ported from the RN `ParakeetModule`, adapted to FluidAudio `main`
  (`AsrModels.downloadAndLoad(configuration:version:progressHandler:)` →
  `AsrManager.loadModels` → `transcribe(url, decoderState: &TdtDecoderState.make())`
  → `ASRResult{text,confidence,tokenTimings}`; `cleanup()` teardown). Carries both
  native fixes (memory-warning `unload()` + RMS/word-count silence guard) and
  `insertImageMarkers`. `RecordingService` uses `AVAudioRecorder` (metering,
  pause/resume) + a mock mode; plain `RecordView`; `MemoSaver` does
  record→save→transcribe→sidecar. `-seedTranscript` seeds a transcript AND mocks
  recording (no mic). **23 tests green. Next: Phase 3 (photos + markers).**
  **Design note:** chose one-shot-transcribe-on-stop (RN/Mac behavior), NOT
  Shhhcribble's live VAD streaming — simpler + faithful to Skrift's product.
- **Phase 3 (photos + markers): ✅ GREEN** — shared `ImageMarkers` helper (real +
  seeded transcribers both inject); `PhotoCaptureService` (real `AVCapture` + a mock
  for the camera-less sim) + `CameraPreviewView`; shutter on the record screen
  (offset = recording elapsed, paused time excluded); `MemoSaver` moves photos →
  `photo_{memoId}_NNN.jpg`, builds `imageManifest`, injects `[[img_NNN]]`. **25
  tests green. Next: Phase 4 (metadata).**
- **⚠ GOTCHA fixed in Phase 3 (don't reintroduce):** SwiftData traps
  (`EXC_BREAKPOINT`) when it decodes a Codable-**struct** stored as a `@Model`
  attribute, the first time the attribute is *read back* — it stayed hidden until
  a read of `Memo.metadata` happened. Fix: store complex value types as JSON
  `Data?` blobs + computed accessors (see `Memo.metadata`/`sharedContent`). Do NOT
  add a raw Codable-struct attribute to a SwiftData model.
- **Phase 4 (metadata capture): ✅ GREEN** — `SolarCalc` (NOAA sunrise/sunset,
  pure), `DayPeriod.from`, `WeatherClient` (OpenWeatherMap REST; pressure from the
  same response, matching RN; testable `parse`), `MetadataService` (CoreLocation +
  reverse-geocode, `CMPedometer` steps) + `MockMetadataService` + factory.
  `MemoSaver` captures metadata on save and merges onto the memo, preserving the
  photo `imageManifest`. **30 tests green. Next: Phase 5 (names UI).**
- **Phase 5 (names UI): ✅ GREEN** — `NamesListView` + `AddPersonView` over the
  Phase-1 `NamesStore` (list/add/delete=tombstone); `NamesSeeder` (`-seedDemoNames`
  overwrites names.json for deterministic tests); reached via a `person.2` toolbar
  button on the memos screen. **31 tests green. Next: Phase 6 (Mac upload).**
- **Phase 6 (Mac upload): ✅ GREEN** — targets the **NATIVE** Mac server
  (`/Users/tiurihartog/Hackerman/Skrift-desktop/SkriftDesktop`), NOT the Python
  backend (user's call). Contract verified byte-for-byte by reading its
  `Server/SyncHandlers.swift` + `Pipeline/Ingest/UploadService.swift` + tests.
  `UploadPayload` builds the multipart (`files` audio/mp4, `metadata` flat JSON with
  `source:"mobile"`, `transcript` only when `.done`, `images` per manifest — **never
  `sanitised`**, name-linking is Mac-side); `MacTransport` (+mock+factory),
  `MacConnection` (QR `skrift://host:port/name` + health + URLs), `SyncCoordinator`
  (names sync → reconcile by filename → upload waiting). Sync button on the memos
  toolbar. **37 tests green. Next: Phase 7 (review/detail/settings — MOCK FIRST).**
- **⚠ NO on-device name-linking (locked, re-confirmed by the user).** The phone
  sends the RAW transcript (+ confidence/userEdited/markers/metadata/tags); the MAC
  links names + resolves ambiguity at review. The names DB + sync + Names screen
  stay (sync, people mgmt, future voice profiles) but DON'T link names into the
  transcript and DON'T send a `sanitised` field. (Verified: no sanitise logic in the
  native app.) Tagging later = on-device topic-tag *matching* (suggestions only,
  mirrors the desktop deterministic tagger) — separate from name-linking.
- **⚠ Owed: live upload round-trip** against the running native desktop app
  (`SkriftDesktop` — launch it, pair via host/port or QR, POST a real memo). Contract
  is byte-verified but no real POST has run. Also clears the Phase-1 live names
  round-trip (same server).
- **⚠ Sim flake note:** UI tests occasionally fail the whole session with *"Busy
  / Application failed preflight checks"* (SpringBoard stuck) — not a code bug.
  Fix: `xcrun simctl shutdown all; xcrun simctl erase "iPhone 17"` then re-run.
- **⚠ Open verification debt (verified-in-sim vs owed-on-device):**
  - **Phase 1 names sync** — mock-transport + unit tests only; the **live Mac
    round-trip** (`GET /meta`→`GET`→merge→`PUT`) is NOT done (backend was down).
    `URLSessionNamesTransport` is ready; do it early in Phase 6.
  - **Phase 2 transcription/recording** — the real FluidAudio ASR, mic capture,
    `AVAudioRecorder` output, the silence-guard threshold (`0.0075`), and the
    memory-pressure `unload()` are **all device-owed** (sim has no ANE/mic; UI tests
    use `-seedTranscript` + mock recording). Verify on a physical iPhone.
  - **Phase 3 real camera** — the `AVCaptureSession` preview + real photo capture
    are **device-owed** (sim has no camera; UI tests use the mock capture path).
    Verify shutter → photo → correct `[[img_NNN]]` placement on a physical iPhone.
  - **Phase 4 location/steps/weather** — CoreLocation fix + reverse-geocode,
    `CMPedometer` steps, and the OpenWeatherMap network call are **device-owed**
    (sim has no motion sensors; weather needs the user's API key). The pure bits
    (SolarCalc, day period, weather parse) are unit-tested. Verify a real capture
    populates location/daylight/weather/steps on a physical iPhone with the key set.

## Branch map (important)
- `mobile-native` (current) — the rewrite. Branched off `mobile-overhaul`, so it
  ALSO contains: the backend `voiceEmbeddings`-preservation fix, the dead-code
  cleanup (incl. backend `sanitised` Form param removed), and the RN app's audit
  fixes. The native app must preserve the same backend contract (plan §4).
- `mobile-overhaul` — the RN app overhaul + audit fixes (steps 1–2, sync/storage/
  memory/silence). The RN app stays in `Mobile/` until native reaches parity.
- `overhaul` — the (done) desktop overhaul.
- The **native ParakeetModule fixes** (model teardown + memory-warning observer +
  RMS/word-count silence guard) live in `Mobile/modules/parakeet/ios/ParakeetModule.swift`
  on this branch — **port them into the native transcription service in Phase 2**.

## ▶ NEXT-CHAT PROMPT (paste this to start the next session)

> Resume the Skrift native rewrite. Repo `/Users/tiurihartog/Hackerman/Skrift`, branch
> `native` (= main = origin, clean); apps under `Skrift_Native/{SkriftMobile,SkriftDesktop}`.
> **Read `MOBILE_NATIVE_HANDOFF.md` "## NEXT SESSION" first** (memory auto-loads:
> `project_unification_backlog`, `project_native_convergence`, `feedback_native_ui_process`).
>
> State: dev/prod split DONE both apps; prod "Skrift" is on the iPhone 13 (UDID
> `00008110-001208C902EA201E`, unlocked) + prod desktop runs on the Mac. Big batch shipped
> (significance + flag-to-send sync gating, native-List swipe/multiselect, append-transcription,
> feedback/email, karaoke grey-out, sips→ImageIO).
>
> ⚠️ **Three MemoDetailView features are committed but DON'T WORK ON DEVICE** — Liquid Glass,
> the significance slider, and karaoke "tap words to seek" — all rooted in the UIKit-hosted
> `TabView(.page)`. **START with handoff item 0: replace `TabView(.page)` with a SwiftUI paging
> ScrollView** (`.scrollTargetBehavior(.paging)` + `.scrollPosition(id:)`); it's expected to fix
> all three (glass refracts page content; slider drag + per-word tap-seek work). Then revert the
> significance control to a drag slider. Verify on the iPhone 17 sim, then deploy Release to the
> device and have me confirm on the phone.
>
> Then the rest of "## NEXT SESSION": capture items (share-extension + App Group + desktop
> non-audio ingest), light+dark mode (both apps), conversation mode (I'll record a sample →
> diarization + Parakeet speaker-embedding vs my names/aliases), and re-ingest the ~30 old notes
> (drag from `~/Desktop/Skrift old notes/` → Process; dates come from the embedded m4a metadata).
>
> Rules: dev builds = Debug ("Skrift Dev", isolated data); prod = Release ("Skrift"). Commit per
> chunk; verify each (xcodebuild build+test on the iPhone 17 sim; desktop UnitTests +
> `-skipMacroValidation`). Keep the mobile↔Mac contract byte-exact (no `sanitised`). Device deploy
> = Release + `DEVELOPMENT_TEAM=9W82X49JZS` + `devicectl`.

## NEXT SESSION (2026-06-09) — capture items + deferred UI

### ✅ DONE this session (2026-06-09 cont.)
- **Item 0 — TabView(.page)→SwiftUI paging ScrollView** (`d96dafb`). MemoDetail
  pager is now `ScrollView(.horizontal)`+`LazyHStack`(`containerRelativeFrame`)
  `.scrollTargetBehavior(.paging)`+`.scrollPosition(id:)`, with a `ScrollViewReader`
  doing the initial jump (the binding's initial value isn't honoured on first
  layout). Significance reverted to a **drag** slider (0-distance highPriority gesture;
  tap still works). Gotcha: the LazyHStack realises neighbour pages → duplicate
  controls/text in the a11y tree (broke add-tag/edit taps) → `.accessibilityHidden`
  on off-screen pages. New `testOpenNonFirstMemoLandsOnIt` asserts **hittability**
  to prove the initial scroll lands. 39 unit + 23 UI green; **Release deployed to
  the iPhone 13** (install OK; launch needs the phone unlocked). **Owed: user
  confirms glass-refraction / slider-drag / word-tap-seek ON DEVICE** (can't be
  self-verified — visual/gesture).
- **Light + dark mode, BOTH apps** (mobile `a7ebb2a`, desktop `4b6afc4`). Tokens
  are now adaptive (mobile `UIColor` / desktop `NSColor` dynamic providers, light+dark
  pair each). Mobile: the existing Settings→Theme picker now actually re-skins (root
  already had `.preferredColorScheme`); stray accent-purple literals routed through a
  new `skAccentText` token. Desktop: new `AppTheme` helper + a Light/Dark/Auto
  segmented picker in Settings; `NSApp.appearance` kept in lock-step (system-drawn
  controls); Snapshot pins the drawing appearance via `performAsCurrentDrawingAppearance`
  (+`-snapshot-light`). Verified via sim screenshots (mobile) and `-snapshot`/
  `-snapshot-light` PNGs (desktop); decorative capture/placeholder gradients left dark.
- **GLASS — SOLVED + device-confirmed.** Root cause was NOT the code: (1) the bar was
  a detached ZStack overlay (sampled nothing) → moved to `.safeAreaInset(edge:.bottom)`
  + `GlassEffectContainer` so scroll content is in the backdrop (`9990d32`); (2) the
  device had **Reduce Motion ON**, which throttles Liquid Glass on the A15 → frosted
  (also Reduce Transparency / Display&Brightness→Liquid Glass=Tinted frost it). With
  full glass on, `.regular` reads frosted, **`.clear` is the lensed look the user wants**
  → switched (`5d60646`). **The iOS-26 Simulator can't render specular/chromatic glass —
  device-only.** Built `Skrift_Native/GlassLab/` (standalone harness, static/scroll/
  skrift scenes + dark toggle) to iterate glass on-device (`6ef3553`,`b19c688`).
- **Slimmer player bar** (`08d6eee`): play 60→46, tighter spacings/padding.
- **Inline rich-text editor — always editable, no Edit button** (`c07d100`).
  `TranscriptEditor` (self-sizing UITextView): inline image attachments at `[[img_NNN]]`,
  edits in place, writes back (reconstructs markers from attachments) + flags
  `transcriptUserEdited`. Paused→editor; playing→read-only karaoke view; transcribing→pill.
  Detail UI tests now read the transcript via `app.textViews["transcript-editor"].value`.
  **User confirmed karaoke + edit work.**
- **Significance label = desktop tiers** (`9990d32`): `0.7 · Significant` / `Not rated`.
- **Perf** (`bc98e86`): `MemoImageLoader` (ImageIO thumbnail → display size + NSCache)
  fixed the "600× with a picture" slow page-render; significance slider commits to
  SwiftData only on release (per-tick writes re-ran the @Query → lag). User-reported,
  now fixed.
- **Video import → backlog** (`3c9978f`, repo `backlog.md`): import `.mov`/`.mp4`,
  transcribe audio, `recordedAt` from the video's embedded creation date.

**CONVERSATION MODE — scoped + sample in hand (next build):** pulled the app's recordings
off the device via `devicectl device copy from --domain-type appDataContainer
--domain-identifier com.skrift.mobile --source Documents/recordings`. The sample is
`memo_6C0C4C75…m4a` (28s; transcript "If conversation mode works, if I talk, then what
if you talk?…"). FluidAudio HAS the full API: `DiarizerModels.download/loadFromHuggingFace`
→ `AudioConverter.resampleAudioFile(url)` → `DiarizerManager.initialize(models:)` +
`process()` → `DiarizationResult`/`TimedSpeakerSegment` (embedding per speaker) +
`initializeKnownSpeakers([Speaker])`. The names store already carries `voiceEmbeddings`.
**Decision LOCKED: tag-as-you-go** (diarize → Speaker 1/2/3 → user assigns a name → save
that voiceprint → auto-match next time). **Plan:** (1) headless diarization SPIKE on the
28s sample (prove split) — desktop `-diarize` or a standalone CLI; (2) mock the speaker-
split UI; (3) `DiarizationService` (own model download) + ASR/word-timing fusion + the
tag affordance. Needs device (ANE) for real runs.

**Still TODO: conversation mode (build, per the plan above — next), capture items (user
drives the share-ext), re-ingest the 30 notes (with the user — prod desktop quit), desktop
glass (user said later).**


**Dev/prod split is LIVE (both apps); the user runs prod "Skrift" on the iPhone 13 +
the prod desktop on the Mac.** Build prod = `-configuration Release`; dev iteration =
Debug (`com.skrift.{mobile,desktop}.dev`, "Skrift Dev"). Deploy prod to the phone:
`xcodebuild build -scheme SkriftMobile -configuration Release -destination 'platform=iOS,id=00008110-001208C902EA201E' -derivedDataPath build-device -allowProvisioningUpdates DEVELOPMENT_TEAM=9W82X49JZS CODE_SIGN_STYLE=Automatic` → `devicectl device install … Release-iphoneos/SkriftMobile.app`.

### ✅ FIXED (2026-06-09, `d96dafb`) — was: THREE MemoDetailView features broken on device
All three lived inside `MemoDetailView`'s `TabView(.page)` page content, and the
**UIKit-hosted `TabView(.page)` was the common root cause** (verified 2026-06-09 on the
iPhone 13). Replaced with a SwiftUI paging ScrollView (item 0 below). Sim-green +
deployed; **device confirmation of the three behaviours still owed.** Original diagnosis:
- **Glass** — `.glassEffect` on the playback bar refracts the ZStack background but NOT the
  page's scroll content, so a photo inside a page doesn't show through (user confirmed over a
  picture; a bright ZStack bg DID refract → it's the page-hosting layer, not the API).
- **Significance slider** — the page-pan steals the gesture; neither drag
  (`.highPriorityGesture`) nor the current tap-to-set (`SpatialTapGesture`) reliably register.
- **Karaoke "tap words to seek"** — committed (`6bf74db`…`7678f85`: Settings toggle +
  per-word `FlowLayout`), but tapping a word doesn't seek on device (same page-content gesture
  hosting; ALSO verify the `@AppStorage("karaokeTapToSeek")` toggle actually flips the
  per-word renderer, and that `player.seek` fires).

**0. ✅ DONE (`d96dafb`) — replaced `TabView(.page)` with a SwiftUI-native paging ScrollView**
(see "DONE this session"; device confirmation owed): `ScrollView(.horizontal){ LazyHStack(spacing:0){ ForEach(memos){
MemoPageView.containerRelativeFrame(.horizontal) } } }.scrollTargetBehavior(.paging)
.scrollPosition(id: $selection)` (+ keep the bottom glass bar as the ZStack overlay). SwiftUI
ScrollView is sampled by `.glassEffect` (glass refracts page content) AND yields child gestures
(restore the significance **drag** slider; per-word tap-to-seek works). Then re-verify:
swipe-between-memos, player re-targets on `selection`, page dots, karaoke colour, the glass over
a photo, the slider drag, and a word tap seeking. Update `MemoDetailUITests`/`SyncUITests`
(the sync test taps the significance control). (Dating of re-ingested audio is already FINE —
desktop reads the embedded m4a recording date.)
1. **Capture items** — the user will drive this tomorrow (they've built iOS share
   extensions before). Plan: new **ShareExtension** target + **App Group**
   (`group.com.skrift.mobile[.dev]`, per-config like the bundle IDs; entitlements via a
   `$(SKRIFT_APP_GROUP)` build-setting var) → extension writes shared URL/text/image to
   the App-Group container → app ingests on launch → no-audio "capture" `Memo`
   (`sharedContent`/`annotationText` already on the model + in `UploadMetadata`) →
   desktop `UploadService` accepts a non-audio capture content type through
   pipeline/compile/export. (Mobile-only would break — coordinated both-apps change.)
2. **Karaoke tap-to-seek (toggleable in Settings)** — while playing, tap a word →
   `player.seek(to: timing.start)`; when paused, tapping leaves Edit available. Needs
   per-word hit-testing: the transcript currently renders via `Text(AttributedString)`
   (not per-word tappable) — switch the text segments to a word-flow of tappable views
   (the app has `FlowLayout`) OR map tap-location→word. Add a Settings toggle (default
   off). Karaoke grey-out + active-word logic already shipped (`Karaoke.activeWordIndex`).
3. **Restore the ~35 old notes** — data is SAFE: 31 working folders in
   `~/Documents/Voice Transcription Pipeline Audio Output/`, but each holds ONLY
   `original.m4a` (no processed output), so recovery = re-ingest the 31 originals into
   the prod desktop (+Upload/drag-drop) and Process (re-run transcribe/enhance/export).
   This is the deferred "port old notes" task. (The split did NOT lose SwiftData notes —
   the native store had none persisted.)
5. ✅ **Light + dark mode (both apps) — DONE 2026-06-09** (mobile `a7ebb2a`, desktop
   `4b6afc4`). Tokens made adaptive via dynamic color providers (UIColor mobile /
   NSColor desktop), light+dark pair each. Mobile Theme picker now re-skins;
   desktop got an Appearance picker + `AppTheme` helper + `NSApp.appearance` sync.
   Verified by sim screenshots / `-snapshot[-light]` PNGs. (See "DONE this session".)
4. **Liquid Glass polish (optional)** — `.glassEffect` is CORRECT + verified (it refracts
   content behind it; proven over a bright bg). Over the dark UI it's subtle by design
   (Apple DTS/WWDC25). A hairline+specular edge was added so it reads as glass. If the
   user wants it obviously glassy on the dark UI, options: a subtle `.tint(...)` on the
   glass, or lighter content behind the bar. Don't "fix" it as a bug — it works.

## Resume here (do this first)
**Phases 0–7 DONE + on-device hardening DONE + the live round-trip is VERIFIED on
real hardware.** The native iOS app is no longer "owed" — it works end-to-end.

- **Phase 7 (full UI)** built to the locked mockups: 7.0=`0d4ca98` … 7.11=`200523a`.
  15 UI + 31 unit tests green; every screen screenshot-verified; UI-coverage +
  correctness agent audits run and closed. Locked fork: **save-now → Memo detail**.
- **On-device hardening** (committed as "Phase 8.x" — from real iPhone testing;
  NOT the plan's Phase 8 = widget/intents): 8.0=`f4ab571`, 8.1=`9a36c46`,
  8.2=`5a5cb96`. Fixed from the device run: recording gain (`.measurement`→
  `.default` — was soft + tiny waveform), live model-load status + onboarding
  download % bar, place-name shorten + chip truncation, photo double-capture
  debounce, the dead detail ⋯ (`Menu`→`Button`+`.confirmationDialog` — a Menu
  won't present over a paged TabView on device), ⋯ = Copy transcript + Delete
  (dropped Re-transcribe), **ATS `NSAllowsLocalNetworking`** (cleartext LAN HTTP
  was blocked → upload never left the phone), **Bonjour resolve forced to IPv4**
  (was resolving a dead `fe80::` link-local), honest sync banner.
- **LIVE ROUND-TRIP VERIFIED (2026-06-07):** real iPhone 13 → native `SkriftDesktop`
  server over Wi-Fi. Two real memos uploaded (`memo_<uuid>.m4a`, 495 KB), the Mac
  **trusted the on-device transcript** (`steps.transcribe = done`), names synced
  (`/api/names/meta` timestamp updated). Confirmed on real hardware: ASR + live
  caption, mic→.m4a, camera+photos, CoreLocation place, model load, Bonjour
  discover+IPv4 resolve, ATS cleartext upload, multipart accept, names LWW sync.

**Device build/run (signed; the user's team):**
```
cd SkriftMobile && xcodebuild build -project SkriftMobile.xcodeproj -scheme SkriftMobile \
  -destination 'platform=iOS,id=<DEVICE_UDID>' -derivedDataPath build-device \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=9W82X49JZS CODE_SIGN_STYLE=Automatic
xcrun devicectl device install app --device <UDID> build-device/Build/Products/Debug-iphoneos/SkriftMobile.app
xcrun devicectl device process launch --device <UDID> com.skrift.mobile   # device must be UNLOCKED
```
iPhone 13 UDID this session: `00008110-001208C902EA201E`. Mac LAN IP: `192.168.1.139:8000`.
Crash reports: `~/Library/Logs/DiagnosticReports/SkriftMobile-*.ips`.

**What's left — all follow-ups, none blocking:**
1. ✅ **Multi-Mac disambiguation DONE** (2026-06-07). Phone (`a7c24ca`,
   mobile-native): `MacDiscovery` eager-resolves each discovered service's
   host/port as it appears (preserved across result churn) → every Pair-a-Mac
   row shows its **IP**; the "Looking for more Macs…" spinner **caps** via a
   settle timer (6s quiet window; 2s seeded) → becomes a "Search again" button
   (also the empty state). Also fixed a latent port-format bug (`Text(verbatim:)`
   → "8000", not LocalizedStringKey-grouped "8.000"). Desktop (`3fd4848`,
   desktop-native): `LocalHTTPServer` advertises a **unique Bonjour name** from
   the Mac's computer name (`Host.current().localizedName`, fallback "Skrift
   Desktop"). Contract unchanged (connect by host/port; name is display-only).
   18 UI + unit tests green (sim); 81 desktop UnitTests green; screenshot-verified.
   **Still open (deferred hardening):** no pairing code (QR dropped) → a Mac-side
   "allow this iPhone?" confirm is the right hardening for shared networks. The
   device-owed bit: confirm real Bonjour eager-resolve shows IPs on hardware
   (sim seeds entries).
2. **Desktop `title`-read** (spawned task in the desktop repo): `UploadService`
   decodes the metadata but never extracts `title`; `BatchRunner.swift:44` sets
   `titleSuggested` from the LLM unconditionally.
3. ✅ **Process-a-synced-phone-memo on the Mac DONE** (2026-06-07, desktop-native
   `10548fe`). A real synced memo (`memo_203…`, `source=mobile`, conf 0.96, with
   `[[img_001]]`) ran through the Mac's half via `-runfile -transcript`: **ASR
   skipped** (Mac trusted the phone transcript byte-for-byte — no re-transcribe),
   Gemma title+summary+filler-removal copy-edit, **`[[img_001]]` preserved →
   Obsidian `![[…]]` embed**, audio+photo exported to the test vault. A
   names-bearing transcript confirmed name-link on the trust path
   (`Tuur`→`[[Tiuri Hartog]]`, `Rox`→`[[Roksana Gurova]]`, ambiguous `Jack`
   flagged). The Mac's half is validated on real mobile input end-to-end.
4. **Still device/later-owed:** voice-enrollment ML (diarization track — the
   on-phone flow is a placeholder), word-timings→karaoke (computed but unused),
   weather (needs the user's OpenWeatherMap key), Light/Auto theme palette.
5. ✅ **Plan's Phase 8 DONE** (2026-06-07; user signed off App Intents "from the
   start"). Commits `55c2032`→`ece27b9`, mock-first, per-chunk:
   - **8a** (`55c2032`): `SkriftShared` framework (`RecordingActivityAttributes`,
     ActivityKit, +`paused`/`pausedAt`) + `SkriftWidget` widgetkit extension —
     recording **Live Activity** (Lock Screen + Dynamic Island, Skrift-tokened,
     self-animating waveform, head-truncated caption, frozen timer while paused).
     `RecordingActivityManager` drives it (throttle + orphan reaping, ported from
     Shhhcribble). Info.plist `NSSupportsLiveActivities` + `UIBackgroundModes
     audio`. Mock: `mockups/liveactivity.html`.
   - **8b** (`3ce27a6`): **App Intents** (Start/Stop) + **Control Center** record
     button + **Siri** shortcut + interactive Live Activity **Stop** button.
     **SIGTRAP-avoided by design:** plain `AppIntent` + `openAppWhenRun:true`,
     NOT `AudioRecordingIntent` (that's what SIGTRAP'd at AppShortcutsProvider
     registration without PTT). Static-performer indirection compiles intents in
     both app+widget; `RecordingIntentBridge` routes to the existing record
     handlers. No App Group.
   - **8c** (`7d919a7`): **share-to-import audio** via document types
     (`CFBundleDocumentTypes public.audio` + `.onOpenURL` → `MemoSaver.importAudio`)
     — Shhhcribble's path, no share-extension target. m4a/wav/mp3 transcribe
     on-device; .opus etc. fall back to Mac transcription.
   - **8d** (`ece27b9`): `skrift://record` deep link → start recording (shared
     `AppURLHandler` + bridge).
   - **Verified:** 18 UI + 35 unit tests green on the iPhone 17 sim; app launches
     with the shortcut registered + no crash (so registration is SIGTRAP-free —
     it would surface on the sim too). **Device-owed:** real Live Activity
     display, Control Center / Siri invocation, Live Activity Stop, the Share
     Sheet hand-off, and stop-without-unlock (needs a shared session controller).
   - **Deferred to Phase 9 parity:** richer capture-items (shared URL/text/image +
     annotation) via a full share extension; the RN `record-widget` Home/Lock
     widget (only Control Center + Live Activity shipped).
6. **Plan's Phase 9** = parity sweep + retire the RN `Mobile/`.

## Phase 9 — parity sweep DONE (2026-06-07); retirement of `Mobile/` NOT yet done

Ran a full feature-by-feature RN (`Mobile/`) → native (`SkriftMobile/`) audit.
**Verdict: at parity-or-better on the whole core loop, but NOT 1:1 — real gaps
remain, so `Mobile/` was NOT deleted** (the plan's gate is "parity → then
retire"; user decision pending — see end).

**Native meets/exceeds RN for:** recording (+ pause/resume, live caption — a
native *addition*), on-device Parakeet (BPE merge, `[[img_NNN]]` markers, silence
guard, memory teardown, download progress), photos-during-recording, the full
contextual-metadata set (location/weather/pressure/daylight/dayPeriod/steps),
names DB + bidirectional LWW/tombstone/**voiceEmbeddings-union** sync, the
multipart Mac upload contract (flat metadata, `source:"mobile"`, phone `title`,
**no `sanitised`**), reconcile/health, memo list/detail/playback. Native-only
extras: Bonjour auto-discovery + multi-Mac, full-text search + sort/filter,
swipe-paging detail, editable title + in-detail tags, Siri App Shortcuts +
Control Center, onboarding, richer interactive Live Activity, on-device hardening.

**GAP PUNCH-LIST (what blocks retiring `Mobile/`), ranked:**
1. **Share Extension + capture items** — ❌ entirely missing. RN has
   `ios/ShareExtension/ShareViewController.swift` + `capture.tsx` +
   `saveCaptureItem` + URL-metadata fetch (share URL/text/image/file + annotate).
   Native has no share-extension target; the `SharedContent` model + upload field
   exist but nothing produces them. **+ `UploadPayload` sends no `attachments`/
   legacy `photo` multipart parts**, so capture-item files wouldn't upload anyway.
   *Biggest gap.*
2. **Lock Screen / Home Screen widgets + QuickActions** — ❌ RN `record-widget`
   (accessoryCircular/rectangular/inline + systemSmall) + app-icon long-press
   "Quick Record" not ported. Native covers quick-start via Control Center + Siri
   + `skrift://record`, but the dedicated Lock/Home widget + app-icon action are
   absent.
3. **Memory-aid prompts** — ❌ record-screen prompt list + Settings editor dropped.
4. **Full capture-context in Memo detail** — ⚠️ daylight/steps/pressure/full
   weather/sync-status row captured + uploaded but not surfaced (detail shows only
   place/temp/day-period chips).
5. **Photo filmstrip w/ offset labels + full-screen viewer** — ⚠️ native shows
   inline embeds only (no horizontal filmstrip + tap-to-fullscreen).
6. **On-device transcript text editing → `transcriptUserEdited`** — ⚠️ flag +
   upload plumbing exist but detail transcript is read-only (no editor; only
   Re-transcribe). RN's Review let you fix the transcript (flips the Mac trust).
7. **Settings extras** — ❌ storage stats + "Clear synced memos", persisted
   last-sync time (native has a transient banner), metadata-capture status rows.
8. **Pull-to-refresh / on-focus auto-sync / row-swipe-delete** — ⚠️ native sync is
   an explicit toolbar tap; delete via multi-select or detail ⋯.
9. **Names alias editing** — ⚠️ deliberate (Mac owns aliases): native edits
   name+short+delete only.
10. **Voice enrollment** — ⚠️ store API ready + round-trips; UI is a placeholder
    (diarization track).

**Deliberate design swaps (not regressions):** QR pairing → Bonjour + manual;
post-record Review screen → save-now → Memo detail.

**Gap-closure status (user picked which to build, 2026-06-07):**
- ✅ **9a — hand-editable transcript** (`97a3bf1`): Edit/Done toggle in Memo
  detail; sets `transcriptUserEdited`. **Re-transcribe removed** (dead
  `MemoSaver.retranscribe` + the list Error→Retry button; failed = informational
  "Error" pill, recovers via sync or hand-edit).
- ✅ **9b — Lock/Home record widget** (`3773b5f`): `RecordWidget` (accessory +
  systemSmall) → `skrift://record`.
- ⏸ **9c — capture items: DEFERRED, and it's CROSS-TRACK.** Re-verified: the
  native Mac `UploadService.ingest` ONLY loops `files` (audio) parts + always
  `sourceType:.audio` — a pure capture item (no audio, just `attachments`+meta)
  yields **zero PipelineFiles → silently dropped**. So capture items needs
  **desktop work too** (UploadService accept captures + a capture content-type
  through pipeline/compile/export). Mobile-only would be broken. Mobile
  `UploadMetadata` already carries `sharedContent`/`annotationText`; only the
  `attachments` multipart part + the whole Mac side are missing. **Build it as a
  coordinated mobile+desktop change AFTER convergence** (below). Small stuff
  (metadata grid, filmstrip, settings extras, alias editing, prompts) — user
  doesn't care, won't port.
- ⏸ **Retiring `Mobile/` — DEFERRED.** User wants the old apps kept **fully
  operational** (to look back at, incl. an even-older wildly-different Skrift) —
  so "archive" = relocate intact under `archive/`, never gut. Do this during
  convergence, NOT before.

## CONVERGENCE PLAN (mobile-native + desktop-native → one `native` branch) — DONE + CLEANED UP

**EXECUTED 2026-06-07** (merge `9e338b6` + reorg `8b3a409`) **and re-audited + cleaned
up 2026-06-08:** convergence re-verified by git tree-hash equality (not eyeballing) —
both apps' code byte-identical to their source branches across merge+reorg (reorg was
a pure R100 rename; only intended doc/`.gitignore` edits + the archived Electron-Python
doc were non-renames), `desktop-native` fully merged (`is-ancestor`=0, zero unmerged
commits), all 3 archived apps byte-identical to source. The redundant
`Skrift-desktop` worktree was cleaned up: salvaged the 6 desktop UI mocks →
`Skrift_Native/SkriftDesktop/mocks/` (incl. locked `v5.html`; committed `eba5576`,
mirrors `SkriftMobile/mockups/`, NOT in build target), dropped `pilot/`+`pipecheck/`
spike scratch (user's call), `git worktree remove --force …/Skrift-desktop` (763 MB
DerivedData reclaimed). `desktop-native` branch kept as a harmless merged pointer.
**Both apps re-build-verified from the new homes this session:** mobile TEST
SUCCEEDED (`SkriftMobileTests` 35 unit + `SkriftMobileUITests` 19 UI = 54, 0 fail,
iPhone 17 sim); desktop BUILD SUCCEEDED (full MLX `-skipMacroValidation`). The
separate `.claude/worktrees/competent-haslett-718d5a` worktree is on a different
branch (origin/main) — left alone, not convergence scratch. The historical plan
follows for reference.

User decision (2026-06-07): the desktop app is **actively being worked on**
(`desktop-native` is mid-flight), so **do NOT merge/move folders yet** — wait
until desktop reaches a stable point, then converge. The merge itself is
**verified conflict-free** (the two branches changed disjoint files since
merge-base `9b7cec5`; `comm -12` of changed-on-both = empty). When desktop is
ready, execute (clean trees first):
1. `git checkout -b native` (off mobile-native) → `git merge desktop-native`
   (conflict-free → both `SkriftMobile/` + `SkriftDesktop/` on one branch).
2. Group: `git mv SkriftMobile Skrift_Native/SkriftMobile` +
   `git mv SkriftDesktop Skrift_Native/SkriftDesktop` (wholesale dir moves keep
   each `project.yml`'s relative paths; then update all absolute paths in the
   docs/build/deploy commands).
3. Archive (KEEP OPERATIONAL — relocate intact, don't delete/gut):
   `git mv Mobile archive/`, `git mv frontend-new archive/`, `git mv backend archive/`.
4. Rewrite root `CLAUDE.md` for the native-only layout.
5. `git worktree remove …/Skrift-desktop` (+ prune the stray `.claude/worktrees/*`);
   single checkout on `native` after that.
6. THEN build capture items (9c) as one coordinated commit across both apps.

Verify each app still builds after the moves (sim for mobile; `-skipMacroValidation`
full scheme for desktop).

## Device verification — Phase 8 on a real iPhone 13 (2026-06-08) — DONE

Deployed signed (team `9W82X49JZS`) from `Skrift_Native/SkriftMobile`; UDID
`00008110-001208C902EA201E`. **Confirmed working on hardware:** app launches (App
Intents register with **NO SIGTRAP** — the plain-`AppIntent` design holds on
device); **Live Activity** (Lock Screen + Dynamic Island, Stop button); **Control
Center** record control; **Siri "Record with Skrift"** + **Lock-Screen widget**
now **auto-record** (after the fix below); **share audio** import works from
WhatsApp + (after broadening UTIs) **Signal**.

**⚠ The cold-launch auto-record saga (commit `150fd4f`) — read before touching the
intent→record path.** Siri/widget opened the record screen but didn't start
recording on a COLD launch (warm/Control-Center + manual always worked). Took 6
research agents + on-device `os_log` tracing (via `idevicesyslog -u <UDID>` — `log
collect`/`log stream --device` both need root/aren't supported; `idevicesyslog`
needs neither). FOUR stacked causes:
1. The `autoStart` Bool passed into `RecordView` through `.fullScreenCover`
   arrived **stale (false)** on cold launch (@State→cover propagation race). →
   `RecordView` now reads a **consumable pending-start from `RecordingIntentBridge`**
   (set at intent time); FAB calls `clearPendingStart()`.
2. Fired **too early** — iOS blocks mic capture until the app is foreground-
   `.active`. → gate on `UIApplication.applicationState == .active` via
   `didBecomeActiveNotification` (reliable on cold launch + inside a cover, unlike
   `scenePhase`).
3. **THE blocker:** `Haptics.tap()` ran on the main actor right before the start
   Task — **haptics share the audio session, which Siri still owns just after a
   voice launch, so the haptic BLOCKED** and the Task never ran (trace: "consumed
   → starting" with no `start()` after). → **no haptic in the auto-start path.**
4. Siri mic handoff → 700ms delay + retry so `start()` doesn't contend.
Recording is independent of the model (the live caption catches up on load).

**Also fixed (committed `0c76494`):** the model-load status state machine —
`ModelLoadStatus` is now a single `phase` (written only via `set(_:)`) with a
persisted `everDownloaded` latch; `.compiling` surfaces as "Preparing N%" (was a
frozen "Preparing…"); a memory-warning `unload()` no longer falsely shows "not
downloaded" for a cached model.

**Owed (next session):**
- **"Transcription a bit weird" after a cold-launch auto-record** (user, 2026-06-08)
  — likely the streaming caption catching up while the model finishes loading
  mid-recording. Investigate the live-caption behavior on a cold auto-start.
- ✅ Clean build re-installed to the device (2026-06-08) — device now runs the
  committed `150fd4f` (debug `os_log` stripped); installed without launching.
- Optional polish: `openAppWhenRun` is deprecated on iOS 18 → `supportedModes:
  .foreground` (not a bug; works as-is).

Sanity-check the sim toolchain (runs BOTH test targets; sim flake → re-run after
`xcrun simctl shutdown all; xcrun simctl erase "iPhone 17"`):
```
cd SkriftMobile && xcodegen generate && rm -rf /tmp/sk_ui.xcresult && \
  xcodebuild test -project SkriftMobile.xcodeproj -scheme SkriftMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build \
  -resultBundlePath /tmp/sk_ui.xcresult > /tmp/sk_ui_test.log 2>&1; echo "EXIT $?"
grep -E "TEST SUCCEEDED|TEST FAILED" /tmp/sk_ui_test.log
```

The per-screen spec + mockups are in **`## Phase 7 — LOCKED UI DESIGN`** below and
`SkriftMobile/mockups/mockup{1..5}.html`. The Shhhcribble streaming port lives in
`TranscriptionService` (feed/liveCaption/finish + time-based rotation) and
`insertImageMarkers`. SEED transcripts via a `-seedTranscript` launch arg for UI
tests (the sim has no ANE); verify real ASR/memory/silence on a physical device.
The iPhone 17 sim is the test target (run `xcrun simctl shutdown all` first if a
stale dialog lingers). **Run long builds via Bash `run_in_background: true` +
`dangerouslyDisableSandbox: true`.**

Data-model facts for Phase 2+: audio is stored by `Memo.audioFilename` (resolve
`Memo.audioURL` at runtime — no absolute paths); transcript trust + word timings go
on the `Memo` (sidecar via `WordTimingsStore`); `VoiceEmbedding.vector` is `[Double]`
(map FluidAudio's `[Float]` when enrolling); enums (`SyncStatus`/`TranscriptStatus`/
`DayPeriod`/`PressureTrend`) are String-backed; `ISO8601.now()` matches JS
`toISOString()` for names timestamps.

## Phase 7 — LOCKED UI DESIGN (build to this)

The whole UI was mock-first designed + approved this session (5 rounds). Build to it.

**Process the user wants (carry forward, durable):** (1) spec ALL functionality →
(2) agents audit the UI step-by-step for coverage gaps → (3) build → (4) XCUITest
sims. Catch affordance gaps proactively (they caught a buried camera button). See
memory `feedback_native_ui_process.md`.

**Mockups = the visual spec.** `SkriftMobile/mockups/mockup{1..5}.html` (committed,
NOT in the build target). Authoritative per screen: **Record = mockup5**
(caption-first + on-demand camera) & **mockup4** (ready state); **Memo detail =
mockup2**; **Memos = mockup3**; **Names = mockup3**; **Settings = mockup2** +
**Pair-a-Mac = mockup3**; **Review/Onboarding = mockup4** (+ Review title/add-tag in
mockup5). Render any:
```
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new \
  --force-device-scale-factor=2 --window-size=1200,910 \
  --screenshot=/tmp/m.png "file:///Users/tiurihartog/Hackerman/Skrift/SkriftMobile/mockups/mockup5.html"
```
(then Read /tmp/m.png). The user can't see the preview panel until you render+Read.

**Design direction (Opus research agent, web-verified 2026):**
- Adopt only **2 libs**: **DSWaveformImage** (MIT, v14.5 — live mic waveform; wire to
  the existing `AVAudioRecorder` meters, don't open a 2nd session) + **Pow** (MIT —
  tasteful transitions, use sparingly). Everything else native (`NavigationStack` +
  `TabView(.page)` cover paging; skip confetti/design-system/haptics libs).
- **Haptics = native `.sensoryFeedback`** (iOS 17+). CAVEAT: it shares the audio
  session and gets suppressed mid-recording → for the shutter/stop buttons use an
  `AudioServicesPlaySystemSound` fallback so taps still buzz while recording.
- Tokens (already in code via the mocks): bg `#0f1117`, surface `#181a23`, elev
  `#1e2130`, border white@.06, text `#e4e4e7`/`#8b8b97`/`#55556a`, accent `#7c6bf5`,
  green `#34d399`, amber `#f59e0b`, red `#ef4444`.
- Type: Dynamic Type styles; only the timer is custom
  (`.system(size:~52,weight:.semibold,design:.rounded).monospacedDigit()`). Spacing
  4/8/16/24/32 (card pad 16, inter-card 12, margins 20). **Continuous corners**
  (`.rect(cornerRadius:style:.continuous)`): cards 16, chips/pills 8/capsule,
  sheets 24. **Accent restraint:** full strength only on small elements (record btn,
  active dot, CTA, waveform fill, selection); chips/bg at .12–.18 opacity; never tint
  body text; avoid pure black. **Motion:** one spring
  `.spring(response:0.35,dampingFraction:0.85)`, `.snappy` for taps, ≤300ms;
  `.matchedGeometryEffect` card→detail. Wins: live mic waveform; status pills that
  pulse while transcribing (`.symbolEffect(.pulse)`); coherent `.symbolEffect` icons.

**LOCKED decisions (this session):**
1. **Live transcription DURING recording = YES** (signature; "starts the moment you
   speak"). → Port Shhhcribble's **streaming** path (`Services/TextEngine.swift`:
   VAD chunk-rotation + `feed`/`liveSnapshot`/`finalize`) into the native engine for
   the record screen. The current `TranscriptionService.transcribe(url)` is one-shot
   — KEEP it for import/file, ADD streaming for live record.
2. **Record = caption-first, camera on-demand** (mockup5). Recording screen = big
   live caption + compact waveform + timer + Pause/Stop/**Photo** (count badge).
   Photo → viewfinder **slides up as a sheet** (pinch-zoom .5×/1×/2× via
   `AVCaptureDevice.videoZoomFactor`), shutter, recording keeps going ("still
   listening" strip), Done dismisses. Camera NOT persistent. **Ready state** (mockup4):
   context chips + conversation toggle + on-device/model-download status + big "Tap
   to start".
3. **Conversation mode (diarization) = a manual TOGGLE** on the record screen, NOT
   automatic. Diarization itself is still a later track (voiceEmbeddings round-trip;
   nothing runs on them yet).
4. **Names = voice-first (Option B)** (mockup3): people + voice-fingerprint enroll
   ("Voice enrolled" / "Add voice") + simple add. NO alias editing on the phone (Mac
   does it; phone syncs aliases silently). NO "synced on Mac" footer. Phone NEVER
   links names into transcripts.
5. **Pair-a-Mac = Bonjour auto-discovery, NO QR** (mockup3). `NWBrowser` for
   `_skrift._tcp` (the native Mac server advertises it: `SkriftDesktop/Server/
   SyncServer.swift`, name "Skrift Desktop"). UI: "On your network" list (tap to
   connect) + manual host/port fallback. Add Info.plist `NSLocalNetworkUsageDescription`
   + `NSBonjourServices` (`_skrift._tcp`). **Drop the QR parser** (built in Phase 6,
   now unused — user: "noone cares, remove it").
6. **Memos list** (mockup3): search = **full-text over transcript + tags + place
   name** (no separate titles). A SINGLE **funnel icon = Sort & Filter** sheet (sort
   recent/oldest/longest; filter unsynced/has-photos/by place) — NOT a separate
   "Recent" pill, NOT two controls (user picked the funnel: less vertical space).
   Day-group headers (Today/Yesterday), multi-select ("Select"), honest status pills
   incl **Error→Retry**, context chips, photo thumbnail, record FAB.
7. **Memo detail = the "note" screen** (mockup2): **optional editable title** +
   transcript (RAW — never fake `[[links]]`; the Mac adds those) with inline image
   markers rendered, playback (scrub/±10/speed), tags edit, photo filmstrip,
   metadata, **swipe left/right between notes** (`TabView(.page)`, peek next card),
   delete, re-transcribe.
8. **Optional TITLE per memo (NEW):** phone-set title (Review + Memo detail). →
   add `Memo.title: String?` + UI + `title` in `UploadMetadata`. **CONTRACT
   ADDITION:** the native Mac server (`UploadService`) must read `title` from the
   upload metadata and offer it in its title chooser (instead of the LLM title).
   Coordinate with the desktop-native track. (Phone shows the transcript's first line
   when no title is set.)
9. **Tags model (clarified, NOT a synced DB):** the Mac owns the vocabulary — it
   scans the Obsidian vault locally/privately (NEVER AI — see
   `feedback_vault_privacy`) for tag NAMES → a whitelist endpoint. Phone PULLS the
   whitelist (read-only) to suggest matching tags; applied tags ride with the memo
   upload (`tags`). Phone only ever sees tag names. On-device suggestions = later
   track (needs the Mac whitelist endpoint); until then free-text tags + Mac-side
   tagging. Review needs a **"+ Add tag"** free-text affordance beside the dashed
   suggestions.
10. **Onboarding/first-run** (mockup4): permissions (mic/camera/location/motion/
    local-network) + pair Mac (Bonjour) + one-time model download (494 MB, progress).
11. **OPEN FORK (ASK before building):** post-record flow — save-now→edit-in-Memo-
    detail (lean: fewer taps, detail already edits) vs a separate **Review** screen
    (mockup4/5: title + transcript edit + tags + Save/Discard). User dismissed the
    question; don't decide alone.

**Build order (per the user):** Record (live caption + on-demand camera — biggest,
needs the streaming port) → Memo detail (swipe + playback) → Memos list → Names
(voice-first + enroll) → Settings + Bonjour pairing → Onboarding. Each: build →
XCUITest sim (seed via launch args) → commit. Re-run the agent UI-coverage audit
against the BUILT app. Still-undrawn minors: voice-enrollment flow, single-person
detail, empty states, conversation/diarization result.

## Build / test commands (native)
```
cd SkriftMobile
xcodegen generate                      # after editing project.yml or adding files/dirs
xcodebuild build  -project SkriftMobile.xcodeproj -scheme SkriftMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build
rm -rf /tmp/sk_ui.xcresult
xcodebuild test   -project SkriftMobile.xcodeproj -scheme SkriftMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build \
  -resultBundlePath /tmp/sk_ui.xcresult > /tmp/sk_ui_test.log 2>&1; echo "EXIT $?"
# read screenshots/logs from the result bundle:
xcrun xcresulttool get --legacy --path /tmp/sk_ui.xcresult > /tmp/sk_ui.json   # then dig for attachments
```
Run long builds via the Bash `run_in_background` flag + `dangerouslyDisableSandbox: true`
(builds write broadly + spawn many procs). You get notified on completion; don't poll.

## How to "test bugs yourself in the sim" (the capability the user wants)
Model: Pike Companion's XCUITest harness
(`/Users/tiurihartog/Hackerman/Matthew smith stretching app/.claude/worktrees/laughing-bhabha-917fe3/app/PikeCompanionUITests/SessionWalkthroughUITests.swift`).
Copy its craft (plan §5): launch-arg test hooks (`-skipOnboarding -inMemoryStore
-seedDemoMemos -seedTranscript -mockMac -initialTab X`), `visibleTexts`/`dump`/
`snap`/`tapAny` helpers, **accessibility identifiers on every key control**, run
via `xcodebuild test`, read the printed `SCREEN[...]` dumps + attached screenshots.
**The Simulator has no Neural Engine** and FluidAudio pulls ~600MB — so SEED
transcripts via launch args for UI tests; verify real ASR / memory / diarization on
a **physical device** separately.

## Key facts / gotchas
- FluidAudio: follow **Shhhcribble's pin (`branch: main`)**, not the RN `0.12.4`.
  Shhhcribble's `project.yml` is the reference for the SPM stanza + target layout
  (`/Users/tiurihartog/Hackerman/ShhcribbleiOS/project.yml`). Diarization
  (`OfflineDiarizerManager`) + CTC boosting (`configureVocabularyBoosting` on
  `SlidingWindowAsrManager`) were verified present in 0.12.4; main has them too.
- Bundle id: `com.skrift.mobile`. Deep link scheme: `skrift` (e.g. `skrift://record`).
- Sim builds need NO signing. Device builds need a team (free personal team = 7-day
  expiry, like Shhhcribble/Pike).
- **The mobile↔Mac contract is the spine — do not drift from plan §4.** Backend is
  NOT changing. Phone sends `transcript` (no `sanitised`); Mac links names. Trust =
  `transcriptUserEdited || transcriptConfidence >= 0.7`. Names sync = LWW +
  voiceEmbeddings union. Filenames embed the memo UUID (`memo_{uuid}.m4a`).
- **PRIVACY:** never point AI at the user's Obsidian vault. App code only.
- **.gitignore:** the repo root `.gitignore` is tuned for the RN app + Python. Make
  sure `SkriftMobile/build/` and `SkriftMobile/*.xcodeproj/xcuserdata` are ignored;
  DO commit `SkriftMobile/project.yml` + sources. (xcodegen regenerates the
  `.xcodeproj` — some teams gitignore it and commit only project.yml. Decide;
  committing the .xcodeproj is fine and simpler for CI-less work.)

## Shhhcribble reuse map (plan §1 has detail)
Port from `…/ShhcribbleiOS/ShhhcribbleiOS/`: `Services/TextEngine.swift`,
`AudioInput.swift`, `RecordingCoordinator.swift`, `TranscriptionStatus.swift`
(FluidAudio + audio session — read Shhhcribble's `CLAUDE.md` for the AirPods
rules), the recording overlay UI, Live Activity + Control Center widget + App
Intents, the SwiftData store pattern. Skrift-specific (build fresh): Mac sync,
metadata capture (location/weather/pressure/daylight/steps), names DB, photos +
`[[img_NNN]]` markers (algorithm already in the RN `ParakeetModule.swift`).

## Open decisions (carry forward)
- **Auto-enqueue mobile uploads on the Mac** (hands-free processing) — optional,
  not a regression. Decide later.
- **WeatherKit vs OpenWeatherMap** for weather in Phase 4 (lean: keep
  OpenWeatherMap REST + the user's key first).
- Whether to commit the generated `.xcodeproj` or gitignore it (see above).

## Task list (TaskList tool)
Phase 0 is done; **Phase 1 (data model)** is the active task. The RN-specific tracks
(tags/boosting/diariz) were removed — they're post-parity items in plan §7.

---

## Session ledger — every bug / finding / change / open item (full context)

The entire 2026-06-05 session, so nothing is lost. Most fixes landed on
`mobile-overhaul` (inherited by `mobile-native`). The RN app (`Mobile/`) retires at
parity, but its fixes + the BACKEND fixes are real and the CONTRACT they encode is
what the native app must match (plan §4).

### A. Changes already committed (newest first)
`mobile-native`: Phase 6 — Mac upload to the NATIVE server (see `git log`).
`UploadPayload` (multipart, no `sanitised`), `MacTransport` (+mock), `MacConnection`
QR/health, `SyncCoordinator` (names→reconcile→upload), sync button. 37 tests green.
Live POST owed (needs the desktop app running).
`mobile-native`: Phase 5 — names UI (see `git log`). `NamesListView` +
`AddPersonView` over `NamesStore`; `NamesSeeder` (`-seedDemoNames`); memos-toolbar
entry. 31 tests green.
`mobile-native`: Phase 4 — metadata capture (see `git log`). `SolarCalc`,
`DayPeriod.from`, `WeatherClient`, `MetadataService` (+mock+factory); `MemoSaver`
merges captured metadata, preserving the photo manifest. 30 tests green.
Location/steps/weather = device-owed.
`mobile-native`: Phase 3 — photos + markers (see `git log`). `ImageMarkers`,
`PhotoCaptureService` (+mock), `CameraPreviewView`, shutter, `MemoSaver` manifest.
**Includes the SwiftData Codable-attribute crash fix** (`Memo.metadata`/
`sharedContent` → JSON blobs). 25 tests green. Real camera = device-owed.
`mobile-native`: Phase 2 — recording + transcription (see `git log`). FluidAudio
`main` SPM dep; `TranscriptionService` + `RecordingService` + `RecordView` +
`MemoSaver`; `-seedTranscript` seam. 23 tests green. Real ASR/mic = device-owed.
`mobile-native`: Phase 1 — SwiftData data model + full names store/sync (see
`git log` for the hash). Adds `SkriftMobile/{Models,Services,Features,SkriftMobileTests}`,
the unit-test target, launch-arg seed hooks. 21 tests green. Names sync verified
via mock transport only (live Mac round-trip still owed — see TL;DR ⚠).
`mobile-native`: `09541e0` Phase 0 (green build + XCUITest) · plan doc commit.
`mobile-overhaul` (inherited by `mobile-native`):
- `9b7cec5` RN `ParakeetModule.swift`: model teardown + memory-warning observer +
  RMS/word-count silence guard. **Compiles; behavior UNVERIFIED on a real device
  (sim has no ANE).** Port these two fixes into the native transcription service (Phase 2).
- `423b4a2` storage perf — wordTimings → per-memo sidecar; batched `deleteMemos`.
- `d78e75b` sync robustness — upload AbortController timeout + 1 retry; save photos
  even when metadata capture returns null.
- `d0f7a23` dead-code — removed RN `liveNames`, unused step color tokens, backend
  `sanitised` upload Form param + honor block.
- `4d3c289` storage cache — `loadMemos` returns a copy; `updateMemoSyncStatus` immutable.
- `542e9f0` backend — `write_with_smart_bumps` now preserves `voiceEmbeddings`
  (a desktop names save previously WIPED phone-enrolled voice profiles).
- `26154a4` dropped RN on-device sanitise — phone sends transcript only; Mac links names.
- `c5398dd` RN names — typed `voiceEmbeddings`, union merge, `addVoiceEmbedding` writer.

### B. Bugs found by the 3-agent audit — FIXED
voiceEmbeddings wiped on desktop save (`542e9f0`); memos cache by-reference
(`4d3c289`); sync upload no timeout (`d78e75b`); photos dropped on null metadata
(`d78e75b`); memos.json bloat + O(n²) clear-synced (`423b4a2`); ASR model never
released = OS-kill (`9b7cec5`, verify on device); TDT silence phantom (`9b7cec5`,
tune threshold on device).

### C. Findings that are NOT bugs (do not "fix")
- **reconcile-by-filename is safe** — filenames embed the memo UUID; an agent over-flagged it.
- **Mac does not auto-enqueue mobile uploads** — a synced memo waits for a desktop
  "Process" click; intended (same as desktop drops), not a regression. See E.1.
- **FluidAudio:** offline diarization present; CTC boosting is on
  `SlidingWindowAsrManager`, not `AsrManager` (TDT). Use Shhhcribble's `main` pin.

### D. Deferred — STILL NEEDS FIXING / VERIFYING (with context)
- **Native memory + silence batch needs a PHYSICAL DEVICE** to verify (no OS-kill
  under load; silent recording → empty, no phantom). Silence RMS threshold `0.0075`
  (gated on wordCount ≤ 3) likely needs tuning.
- **Memory follow-ups not done (Agent A):** RN review screen ran transcription in the
  foreground alongside full-res photo bitmaps + rendered photos undownsampled. In the
  NATIVE app, design Phase 2/3 to avoid (defer transcription off the review path /
  downsample). Carry the lesson.
- **Marker insertion UTF-16 vs Python `str`** — spot-check `[[img_NNN]]` parity on
  multibyte/emoji transcripts when porting `insertImageMarkers`.
- RN-only minors (won't port; for completeness): `_layout.tsx` start double-tap
  unguarded; `awaitTranscript` can block the full timeout if the foreground path
  transcribes; `index.tsx` getItemLayout fixed-height drift; two photo-manifest builds.

### E. Open decisions — DISCUSS with the user (don't decide alone)
1. **Auto-enqueue trusted mobile uploads on the Mac** (hands-free) — optional backend change.
2. **WeatherKit vs OpenWeatherMap** (Phase 4) — lean: keep OpenWeatherMap + user key first.
3. **Substitutions feature** — the Scribble text-cleanup item the user liked:
   deterministic whole-word find/replace for systematically-misheard jargon (the Mac
   LLM won't fix word choice). Design as a synced list like names (`substitutions.json`,
   phone↔Mac, applied both sides). Parked; needs the user's go-ahead. (Filler-removal:
   skip — Mac copy-edit does it. Casing: minor.)
4. **App Intents (Start/Stop)** — user HESITANT: in Scribble the keyboard cold-start +
   bundled-Shortcut never worked reliably and a plain `AudioRecordingIntent` hit a
   SIGTRAP. A plain foreground Start/Stop intent is simpler — prototype carefully +
   discuss before committing (Phase 8).
5. **Dictate-anywhere keyboard** — deferred big bet; not chosen.
6. **Retire `Mobile/` (RN)** — only at native parity (Phase 9).

### F. Scribble (Shhhcribble) — context
Native Swift + FluidAudio dictation app (`/Users/tiurihartog/Hackerman/ShhcribbleiOS`,
app dir `ShhhcribbleiOS/`); the foundation the rewrite draws from (plan §1). Its
README is stale ("two transcription engines" — streaming was removed; Parakeet TDT
only). User-chosen port candidates: deterministic text cleanup (→ E.3), capture UX +
automation (App Intents [E.4], live waveform+word-fade overlay, toast, error states,
model-download ring), engine fixes (silence [done], SlidingWindow boosting).

### G. Memory files
`~/.claude/projects/-Users-tiurihartog-Hackerman-Skrift/memory/`:
`project_mobile_overhaul.md` (RN overhaul + FluidAudio findings — **add the native
pivot here**), `feedback_vault_privacy.md`, `feedback_visual_ui_iteration.md`,
`project_overhaul.md` (desktop).
