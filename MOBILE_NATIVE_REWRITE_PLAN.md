# Skrift Mobile — Native SwiftUI Rewrite Plan

> Decision (2026-06-05): rewrite the Skrift iOS companion from Expo/React Native
> (`Mobile/`) to **native SwiftUI**. Reason: the app is iOS-only and native-heavy
> (FluidAudio/ANE transcription, widgets, Live Activity, App Intents, audio
> session, the upcoming diarization + word-boosting tracks). RN pays a "native
> tax" on exactly the hard parts (gitignored `ios/`, `expo prebuild` wiping
> config, the FluidAudio bridge, weak sim-test story). The user also already runs
> a **native Swift + FluidAudio** app — **Shhhcribble** (`/Users/tiurihartog/Hackerman/ShhcribbleiOS`,
> app dir `ShhhcribbleiOS/`) — so going native lets Skrift mobile *share* that
> foundation and unify on one stack + one testing approach (XCUITest, like the
> Pike Companion harness at `/Users/tiurihartog/Hackerman/Matthew smith stretching app`).

Working branch: `mobile-native` (off `mobile-overhaul`). The old RN app stays in
`Mobile/` until the native app reaches parity, then it's retired.

New native app location: **`SkriftMobile/`** at the repo root (xcodegen-generated
project, mirroring Shhhcribble's structure).

---

## 0. Hard rules (unchanged from the overhaul)
- **PRIVACY:** never point AI/agents at the user's Obsidian vault. App code only;
  test with a small sample the user provides.
- **Keep it simple.** Don't over-engineer (the user pushed back on this before).
- **Bring the user along:** for UI, render/screenshot before building big; confirm
  decisions. The native testing harness makes "show, don't tell" cheap — use it.
- **Verify every chunk + commit each chunk.** Native verification = `xcodebuild`
  build for the sim + `xcodebuild test` (XCUITest) + read logs/screenshots.
- **The mobile↔Mac contract is the spine** (§4). It must match the backend byte
  for byte — the backend is NOT changing for this rewrite.

---

## 1. What ports (almost) free from Shhhcribble vs. what's Skrift-specific

**Shhhcribble already solved (port + adapt — read its `CLAUDE.md` for the
load-bearing decisions, especially the AirPods audio-session rules):**
- FluidAudio integration: `Services/TextEngine.swift` (actor), `AudioInput.swift`
  (mic tap, RMS, route-change self-heal), `RecordingCoordinator.swift`,
  `TranscriptionStatus.swift`. **The hard ASR + audio-session work is done.**
- Recording overlay UI (waveform + live text), the recording phase state machine.
- Live Activity + Control Center widget + App Intents (Start/Stop/Cancel/Toggle as
  auto-registered App Shortcuts). Skrift's RN app already has widget/LiveActivity/
  share-extension targets, so this is well-trodden.
- SwiftData store pattern (`Models/Note.swift`, `NotesRepository`).
- The deterministic text pipeline (filler/substitutions/casing) — **optional**,
  parked for Skrift (the Mac copy-edit already strips fillers). Substitutions could
  later be a synced list (see overhaul notes).
- Audio cues, onboarding patterns, settings patterns.
- NOTE: Shhhcribble pins FluidAudio `branch: main`; the RN app pinned `0.12.4`.
  For the rewrite, follow Shhhcribble (`main`) so diarization/boosting APIs match
  what we verified there (`OfflineDiarizerManager`, `configureVocabularyBoosting`
  on `SlidingWindowAsrManager`).

**Skrift-specific (re-implement in Swift — these are NOT in Shhhcribble):**
- **Mac sync** — multipart upload + names bidirectional sync (the whole reason the
  app exists). §4.
- **Contextual metadata capture** — location, weather (OpenWeatherMap key),
  barometric pressure, daylight (sunrise/sunset/hours), step count, day period.
  (RN got these from Expo modules; native uses CoreLocation, WeatherKit *or* the
  existing OpenWeatherMap REST call, CoreMotion (`CMAltimeter` pressure +
  `CMPedometer` steps), and a solar-position calc for daylight.)
- **Photos during recording** with timestamp offsets + `[[img_NNN]]` marker
  injection (mirror `ParakeetModule.swift` `insertImageMarkers` / backend
  `_insert_image_markers`). The marker logic already exists in
  `Mobile/modules/parakeet/ios/ParakeetModule.swift` — port it directly (it's
  already Swift!).
- **Names DB** with `voiceEmbeddings` + tombstones + LWW (port `Mobile/lib/names.ts`
  semantics to Swift; the merge must union voiceEmbeddings — see overhaul step 1).
- **Capture items** (shared URL/image/text + annotation) via the Share Extension.
- **Tags** at review (free-text now; on-device matching is a later track).

---

## 2. Target architecture (SwiftUI)

```
SkriftMobile/                      # xcodegen project (project.yml at repo root or here)
├── App/
│   ├── SkriftApp.swift            # @main, SwiftData ModelContainer, deep links (skrift://record)
│   └── Intents/                   # StartRecording / StopRecording / etc. (App Shortcuts)
├── Features/
│   ├── MemosList/                 # list, sync status, delete
│   ├── Recording/                 # overlay, waveform, camera+shutter, pause/resume
│   ├── Review/                    # transcript edit, tags, photos
│   ├── MemoDetail/                # playback, transcript
│   └── Settings/                  # Mac connection, Names, weather key, theme
├── Models/                        # Memo (SwiftData), Person/NamesData, MemoMetadata
├── Services/
│   ├── TextEngine / AudioInput / RecordingCoordinator   # from Shhhcribble (FluidAudio)
│   ├── TranscriptionStatus
│   ├── MetadataService            # location/weather/pressure/daylight/steps
│   ├── NamesStore + NamesSync     # names.json local + bidirectional sync
│   ├── SyncService                # multipart upload to Mac
│   └── MacConnection              # host/port, health check, QR parse
├── Shared/                        # framework: App Intents + ActivityAttributes (widget shares it)
├── Widget/                        # Live Activity + Control Center record widget
├── ShareExtension/                # import audio / shared content
└── SkriftMobileUITests/           # XCUITest harness (§5)
```

Mirror Shhhcribble's target layout: a `SkriftShared` framework holds the App
Intents + `ActivityAttributes` so the widget and main app share them (Apple's
pattern; intents must also be source-membered into the widget target — see
Shhhcribble `project.yml`).

---

## 3. Phase plan (each phase builds, tests, commits)

**Phase 0 — Toolchain spike (do FIRST; de-risks everything).**
- `project.yml` (xcodegen) with the app target + FluidAudio SPM dep, deployment
  target iOS 18 (Shhhcribble uses 18; the RN app used 17 — 18 is fine and matches
  Shhhcribble/diarization APIs).
- Minimal `SkriftApp` + one screen. `xcodegen generate` → `xcodebuild build` for
  the **iOS Simulator** succeeds (no signing needed for sim).
- A first XCUITest that launches the app and asserts the first screen shows; run
  `xcodebuild test`. **Green build + green test = toolchain proven.** Commit.

**Phase 1 — Data model + persistence.**
- SwiftData `Memo` (mirror the RN `Memo` shape + the preserved contract fields),
  `MemoMetadata`, `Person`/`NamesData`. `NotesRepository`.
- wordTimings stored in a per-memo sidecar (the overhaul moved them out of the
  index for memory — keep that).
- Unit/UI seed hooks (`-inMemoryStore`, `-seedDemoMemos`). Commit.

**Phase 2 — Recording + transcription (port from Shhhcribble).**
- Port `AudioInput` / `RecordingCoordinator` / `TextEngine` / `TranscriptionStatus`.
- Recording screen: timer, waveform, pause/resume.
- FluidAudio transcribe → transcript + confidence + word timings. **Carry over the
  two native fixes already written for the RN module** (they're in
  `Mobile/modules/parakeet/ios/ParakeetModule.swift` on `mobile-overhaul`): the
  **model teardown + memory-warning observer** and the **RMS/word-count silence
  guard**. Also port `insertImageMarkers`.
- XCUITest: record (seeded/mock audio) → transcript appears. Commit.

**Phase 3 — Photos during recording + markers.**
- Camera preview + shutter (CameraView with ZERO subviews — the RN Fabric-crash
  note becomes a non-issue in native, but keep the capture→offset→marker logic).
- Timestamp offsets accounting for paused time; `[[img_NNN]]` injection. Commit.

**Phase 4 — Metadata capture.**
- CoreLocation (place name via reverse geocode), pressure (`CMAltimeter`), steps
  (`CMPedometer`), daylight (solar calc from lat/long/date), day period, weather
  (port the OpenWeatherMap REST call + the user's API key from Settings). Commit.

**Phase 5 — Names DB + sync.**
- `NamesStore` (local names.json equivalent; SwiftData or a JSON file — match the
  on-disk schema the Mac expects). `NamesSync`: GET /meta → GET → LWW merge
  (union voiceEmbeddings) → PUT. Settings → Names UI. Commit.

**Phase 6 — Mac sync (upload).**
- `MacConnection` (host/port, health, QR `skrift://{ip}:{port}/{name}`).
- `SyncService`: the multipart upload (§4) + reconcile + per-memo status. Timeout +
  retry (the overhaul added this). Commit.
- **Round-trip test against the running Mac backend** — the real integration test.

**Phase 7 — Review + memo detail + settings polish.**
- Review screen (transcript edit → `transcriptUserEdited`, tags, photo filmstrip).
- Memo detail (playback, transcript). Settings (all sections). Commit.

**Phase 8 — Widget / Live Activity / Control Center / App Intents / Share Extension.**
- Port from Shhhcribble + the RN targets. `skrift://record` deep link. Commit.

**Phase 9 — Parity sweep + retire `Mobile/`.**
- Side-by-side check vs the RN app's feature list (this doc §1). Then delete
  `Mobile/` (or move to an `archive/` ref). Update root `CLAUDE.md`.

Later tracks (post-parity, from the overhaul/Scribble work): on-device tags,
word-boosting (SlidingWindow), diarization + voice profiles (multi-embedding,
never average; `voiceEmbeddings` already round-trips), the substitutions list.

---

## 4. The mobile↔Mac contract (PRESERVE EXACTLY — backend is unchanged)

**Upload:** `POST http://{host}:{port}/api/files/upload` (multipart/form-data):
- `files`: the audio (m4a). Name = `memo_{uuid}.m4a` (UUID in the filename — the
  reconcile-by-filename is safe because of this; don't "fix" it).
- `images`: timestamped photos (one part each), filenames from the manifest.
- `attachments`: shared-content files (capture items).
- `metadata`: JSON string. Keys the backend reads (`backend/api/files.py`
  `upload_files`): `location, weather, pressure, daylight, dayPeriod, steps,
  capturedAt, recordedAt, duration, tags (list), source:"mobile", sharedContent,
  annotationText, transcriptConfidence (0..1|null), transcriptUserEdited (bool),
  transcriptMarkersInjected (bool), imageManifest [{filename, offsetSeconds}]`.
- `transcript`: string, ONLY if on-device transcription succeeded. **Do NOT send a
  `sanitised` field** — name-linking is Mac-side now (the overhaul dropped it; the
  backend's `sanitised` Form param was removed on `mobile-overhaul`).
- **Trust rule:** the Mac trusts `transcript` iff `transcriptUserEdited == true`
  OR `transcriptConfidence >= 0.7`. Then it sets `steps.transcribe=done` and runs
  its own name-linking during its auto-run.

**Names sync** (`backend/api/names.py`): `GET /api/names/meta` → `{lastModifiedAt}`
(cheap pre-check); `GET /api/names` → full `{lastModifiedAt, people:[{canonical:
"[[Name]]", aliases:[], short, voiceEmbeddings?:[], lastModifiedAt, deleted?}]}`
incl. tombstones; `PUT /api/names` → the merged payload (server writes verbatim,
prunes old tombstones). Merge = per-canonical LWW; **voiceEmbeddings union across
both sides** (additive, never overwritten — overhaul step 1).

**Health:** `GET /api/system/health`. **Reconcile:** `GET /api/files/` → list of
`{filename}` to mark already-uploaded memos synced.

**Image markers:** `[[img_NNN]]` inserted at the word whose start time is closest
to each photo's `offsetSeconds` (ascending by offset). Algorithm is already in
Swift: `Mobile/modules/parakeet/ios/ParakeetModule.swift insertImageMarkers`.
Set `transcriptMarkersInjected=true` so the Mac doesn't re-inject.

---

## 5. Testing harness (XCUITest — modeled on Pike Companion)

Reference: `…/Matthew smith stretching app/.claude/worktrees/laughing-bhabha-917fe3/app/PikeCompanionUITests/SessionWalkthroughUITests.swift`.

The reusable craft to copy:
- **Launch-arg test hooks** the app reads from `ProcessInfo`/`launchArguments`:
  `-skipOnboarding`, `-inMemoryStore`, `-seedDemoMemos`, `-initialTab <name>`,
  `-mockMac` (stub the sync layer so tests don't need a live backend),
  `-seedTranscript` (inject a deterministic transcript so tests don't need the ANE
  — the Simulator has no Neural Engine and FluidAudio pulls ~600MB; seed instead).
- **Helpers:** `visibleTexts(app)` + `dump(app, tag)` (print `SCREEN[tag]: …` to the
  test log), `snap(app, name)` (attach `XCUIScreen.main.screenshot()`),
  `tapAny(app, [labels])` (tap button/staticText by exact label).
- **Accessibility identifiers on every key control** (`record-button`, `tab-memos`,
  `save-memo`, `transcript-field`, `memo-row-0`, …). Skrift's RN app has ZERO
  testIDs — native is a fresh start, so add `.accessibilityIdentifier(...)` as you
  build each screen.
- Run: `xcodebuild test -scheme SkriftMobile -destination 'platform=iOS
  Simulator,name=iPhone 17' -resultBundlePath /tmp/skrift_ui.xcresult`. Read the
  printed `SCREEN[...]` dumps from the log; extract screenshots from the
  `.xcresult` (`xcrun xcresulttool`). I (Claude) drive + read this myself — no
  manual tapping.
- **The Simulator can't do ANE transcription or real mic/camera.** So: seed
  transcripts via launch args for UI tests; verify the *behavioral* native bits
  (memory teardown, silence guard, real ASR, diarization) on a **physical device**
  separately.

Commands cheat-sheet:
```
brew install xcodegen                 # if missing
cd SkriftMobile && xcodegen generate  # after editing project.yml / adding files
xcodebuild -scheme SkriftMobile -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build build
xcrun simctl boot "iPhone 17"; xcrun simctl install booted <App.app>; xcrun simctl launch booted com.skrift.mobile
xcodebuild test -scheme SkriftMobile -destination 'platform=iOS Simulator,name=iPhone 17' -resultBundlePath /tmp/sk_ui.xcresult
xcrun xcresulttool get --path /tmp/sk_ui.xcresult ...   # pull screenshots/logs
```

---

## 6. Risks / watch-items
- **FluidAudio on `main` vs `0.12.4`** — Shhhcribble uses `main`. Confirm the
  Swift-6 concurrency issue that forced the RN `0.12.4` pin doesn't bite (it was a
  package-internal error; building Shhhcribble proves `main` works). Match
  Shhhcribble's pin.
- **WeatherKit vs OpenWeatherMap** — RN used OpenWeatherMap + a user API key.
  Simplest port keeps that REST call. WeatherKit is nicer (no key) but needs an
  entitlement + capability. Decide in Phase 4 (lean: keep OpenWeatherMap first).
- **Signing** — sim builds need none. Device builds need the team (free personal
  team = 7-day expiry, like Shhhcribble). For the harness, sim-only is fine.
- **Metadata parity** — daylight/pressure/steps are the fiddly re-implements;
  budget time. They're non-blocking for sync (all optional in the payload).
- **Don't break the backend contract** — every field name in §4 is load-bearing.
- **Context/handoff** — this is multi-session. Keep `HANDOFF.md` current; commit
  per phase so a fresh chat can resume from green.

---

## 7. Status (update as you go)
- [x] Phase 0 — toolchain spike (build + first XCUITest green)
- [x] Phase 1 — data model **+ full names store/sync** (user pulled Phase 5's
      names sync forward into Phase 1). SwiftData `Memo` + Codable `MemoMetadata`/
      `SharedContent`, `Person`/`NamesData`, `NotesRepository`, wordTimings
      sidecar, launch-arg seed hooks (`-inMemoryStore`/`-seedDemoMemos`/`-mockMac`),
      `NamesStore` + `NamesSync` (LWW + voiceEmbeddings union) with an injectable
      transport. 21 tests green (unit + XCUITest). **Live names round-trip vs a
      running Mac is still pending — verified only via mock transport + unit tests.**
- [ ] Phase 2 — recording + transcription (+ port the memory/silence fixes)
- [ ] Phase 3 — photos + markers
- [ ] Phase 4 — metadata
- [ ] Phase 5 — names + sync
- [ ] Phase 6 — Mac upload (round-trip vs live backend)
- [ ] Phase 7 — review/detail/settings
- [ ] Phase 8 — widget/live activity/intents/share ext
- [ ] Phase 9 — parity + retire Mobile/
