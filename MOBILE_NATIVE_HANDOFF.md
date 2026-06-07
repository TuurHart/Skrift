# Skrift Mobile Native Rewrite — HANDOFF

> For the next chat. Resume the **native SwiftUI rewrite** of the Skrift iOS app.
> Read this, then **`MOBILE_NATIVE_REWRITE_PLAN.md`** (the full plan — phases,
> Shhhcribble reuse, the mobile↔Mac contract, the XCUITest harness). Repo:
> `/Users/tiurihartog/Hackerman/Skrift`. Branch: **`mobile-native`**.

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

## Resume here (do this first)
**Phases 0–7 are GREEN and committed. The FULL Phase 7 UI is built** to the locked
mockups (7.0→7.9 on `mobile-native`; 7.0=`0d4ca98` … 7.9=`d97e783`). 15 UI + 31
unit tests green; every screen screenshot-verified vs its mockup; an agent
UI-coverage audit ran against the built app and its gaps were closed (7.9).
Locked fork resolved: **save-now → Memo detail** (no separate Review screen).

**What's left:**
1. **Live Mac round-trip (owed, was blocked):** with **SkriftDesktop running**
   (it advertises `_skrift._tcp` on :8000), pair the sim app (Bonjour or manual
   host/port), POST a real memo (multipart), and run the names round-trip
   (`GET /meta`→`GET`→merge→`PUT`). This also clears the Phase-1 + Phase-6 live
   debt. (As of last session SkriftDesktop was still building — wait for it.)
2. **Desktop title contract:** the phone now sends an optional `title` in upload
   metadata (7.8). The native Mac server must read it — `UploadService.swift`
   decodes the metadata but never extracts `title`, and `BatchRunner.swift:44`
   sets `titleSuggested` from the LLM unconditionally. (Flagged as a spawned task
   in the desktop repo.)
3. **On-device verification** of everything marked device-owed: real ASR + the
   live streaming caption, mic/AVAudioEngine file write, camera + pinch-zoom,
   CoreLocation/weather/steps, real Bonjour discovery+resolve, the 494 MB model
   download, voice-enrollment ML. (The sim seam covers UI; behavior needs a phone.)
4. **Phase 8** (widget/Live Activity/App Intents/share ext) — **App Intents:
   still confirm with the user first** (they're hesitant; Scribble SIGTRAP/
   keyboard cold-start history). **Phase 9** parity + retire `Mobile/`.

Build order + per-screen spec are in **`## Phase 7 — LOCKED UI DESIGN`** below
(kept for reference). The mockups live in `SkriftMobile/mockups/mockup{1..5}.html`.
Sanity-check the toolchain still builds + tests (runs BOTH `SkriftMobileTests` and
`SkriftMobileUITests`):
```
cd SkriftMobile && xcodegen generate && rm -rf /tmp/sk_ui.xcresult && \
  xcodebuild test -project SkriftMobile.xcodeproj -scheme SkriftMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build \
  -resultBundlePath /tmp/sk_ui.xcresult > /tmp/sk_ui_test.log 2>&1; echo "EXIT $?"
grep -E "TEST SUCCEEDED|TEST FAILED" /tmp/sk_ui_test.log
```
Phase 2: port `AudioInput`/`RecordingCoordinator`/`TextEngine`/`TranscriptionStatus`
from Shhhcribble (FluidAudio `branch: main`), build the recording screen, wire
FluidAudio transcribe → transcript + confidence + word timings into the `Memo`
model. **Carry over the two native fixes** from the RN `ParakeetModule.swift`
(model teardown + memory-warning observer; RMS/word-count silence guard) and port
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
