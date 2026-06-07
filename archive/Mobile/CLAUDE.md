# Skrift Mobile — CLAUDE.md

## What This Is

iPhone companion app for the Skrift desktop pipeline. Captures voice memos with contextual metadata (location, weather, pressure, daylight, steps, photos) and either:
- syncs raw audio to the Mac for processing, or
- transcribes on-device first (Parakeet TDT v3 via FluidAudio on the Apple Neural Engine), then syncs the finished text. The Mac picks up at whichever pipeline stage is left. **Name-linking is NOT done on-device** — the Mac links names from the trusted transcript and resolves ambiguities at its review step.

The phone and Mac share a names database via bidirectional last-write-wins sync.

Full feature spec: `docs/skrift-mobile-spec.md`.

## Tech Stack

- **Framework:** Expo SDK 54, React Native 0.81, TypeScript
- **Navigation:** expo-router (file-based, tab layout)
- **Audio:** expo-audio (hook-based: `useAudioRecorder`, `useAudioPlayer`)
- **Storage:** expo-file-system (new `File`/`Directory`/`Paths` API, not legacy `FileSystem.*`)
- **IDs:** expo-crypto (`randomUUID()`)
- **Native ASR:** `Mobile/modules/parakeet/` — local Expo module exposing FluidAudio (Parakeet TDT v3) to JS. SPM dependency declared via `spm_dependency` in the podspec; requires `use_frameworks! :linkage => :static` in the Podfile (set via `Podfile.properties.json` → `"ios.useFrameworks": "static"`).

> **⚠️ ios/ is gitignored.** Settings in `ios/Podfile`, `ios/Podfile.properties.json`, and `ios/Skrift.xcodeproj/project.pbxproj` (e.g. `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, `"ios.useFrameworks": "static"`) live only on whichever machine ran `pod install`. Running `expo prebuild --clean` will wipe them. If you need to re-prebuild, re-apply: bump deployment target to 17, set `"ios.useFrameworks": "static"`, run `pod install`. A future cleanup is to express these via a config plugin so they survive prebuild.
- **Build:** expo-dev-client for development, plain Release config for standalone (no Metro) field-test builds.

## Commands

```bash
cd Mobile
npm install --legacy-peer-deps      # peer dep conflicts require this flag
npx tsc --noEmit                    # TypeScript check
npx expo start --dev-client         # Dev — Metro must be running on the Mac

# Standalone (no laptop in the field) build for the iPhone:
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
  xcodebuild -workspace ios/Skrift.xcworkspace -scheme Skrift \
    -configuration Release \
    -destination "id=<device UDID from xcrun xctrace list devices>" \
    -derivedDataPath ios/build CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates

xcrun devicectl device install app --device <UDID> \
  ios/build/Build/Products/Release-iphoneos/Skrift.app
```

The Release path bakes the JS bundle into the `.app` so the app works without Metro. Free Apple personal team certs expire after 7 days — re-run the two commands above to refresh.

> Note: at time of writing, `expo run:ios --device` mis-parses the new `devicectl` JSON format and can't find the iPhone. The `xcodebuild` + `devicectl install app` pair above is the workaround.

## Architecture

### Navigation (`app/`)

```
app/
├── _layout.tsx              # Root Stack (dark theme, no headers)
├── (tabs)/
│   ├── _layout.tsx          # Tab bar: Memos | Record (red circle) | Settings
│   ├── index.tsx            # Memos list (FlatList, pull-to-refresh, long-press delete)
│   ├── record.tsx           # Recording screen (live timer, metering, camera, photos)
│   └── settings.tsx         # Settings (Mac connection, Names, weather, prompts, theme...)
├── review.tsx               # Post-recording review (transcript + photos + tags)
└── memo/
    └── [id].tsx             # Memo detail (playback, transcript, sync status)
```

### Core modules

| Module | Path | Purpose |
|--------|------|---------|
| Storage | `lib/storage.ts` | Memo CRUD: JSON index + .m4a files in `Paths.document` |
| Recording | `hooks/useRecording.ts` | Wraps `useAudioRecorder`, exposes start/stop/duration/metering/pause |
| Playback | `hooks/usePlayback.ts` | Wraps `useAudioPlayer` |
| Transcribe | `lib/transcribe.ts` | Background queue around the native module; per-memo serial |
| Names store | `lib/names.ts` | Local copy of names.json + bidirectional sync (last-write-wins, tombstones). Carries `voiceEmbeddings` for diarization. |
| Sync | `lib/sync.ts` | Multipart upload to Mac. Runs `syncNames` first, then memos. |
| Parakeet | `modules/parakeet/` | Native Expo module wrapping FluidAudio. JS bridge in `index.ts`, Swift in `ios/ParakeetModule.swift` |
| Colors | `constants/colors.ts` | Dark + light tokens matching the desktop app |

### Data model (`lib/storage.ts`)

```typescript
type Memo = {
  id: string;
  filename: string;
  duration: number;
  recordedAt: string;
  tags: string[];
  syncStatus: 'waiting' | 'synced';
  audioUri: string;
  metadata: MemoMetadata | null;       // location/weather/photos/etc
  sharedContent?: SharedContent | null;
  annotationText?: string | null;

  // On-device transcription
  transcript?: string;                 // contains [[img_NNN]] markers when photos taken
  transcriptStatus?: 'pending' | 'transcribing' | 'done' | 'failed';
  transcriptConfidence?: number;       // 0..1, FluidAudio token-min
  transcriptUserEdited?: boolean;
  transcriptMarkersInjected?: boolean; // tells the Mac not to re-inject
  wordTimings?: WordTiming[];          // [{word, start, end}]
};
```

Memos stored as `Paths.document/memos.json` (index) + `Paths.document/recordings/*.m4a` + photos.

Names stored separately as `Paths.document/names.json` (canonical schema mirrors `backend/utils/names_store.py`).

### Sync flow (`lib/sync.ts`)

1. **Names sync first** — bidirectional last-write-wins merge by canonical name. Cheap pre-check via `GET /api/names/meta` skips the heavy round-trip when nothing changed.
2. **Reconcile** — query `GET /api/files/` for memos already on the backend, mark them locally as synced (handles stale state after IP changes).
3. **Per-memo upload** — wait for any pending on-device transcription, then `POST /api/files/upload` with audio + photos + metadata + (if available) `transcript`. Mac upload handler trusts the transcript when `transcriptUserEdited === true` OR `transcriptConfidence >= 0.7`, then runs its own name-linking.

### On-device transcription pipeline

`Mobile/modules/parakeet/ios/ParakeetModule.swift`:
- Loads model lazily via `AsrModels.downloadAndLoad(version: .v3)` — first run pulls ~600 MB CoreML weights from HuggingFace, ANE-optimized. Cached after.
- Emits `downloadProgress` events (`{fractionCompleted, phase: 'listing'|'downloading'|'compiling'|'ready', completedFiles, totalFiles}`) so the Review screen can show "Downloading model… 45%" instead of a silent spinner.
- `transcribe(audioUri, imageManifestJson?)` — uses `AsrManager.transcribe(url, source: .system)`, gets `tokenTimings`, merges BPE sub-words → words, optionally injects `[[img_NNN]]` markers at the word whose `startTime` is closest to each photo's `offsetSeconds`. Bit-for-bit equivalent to the Mac's `_insert_image_markers`.
- Returns `{text, confidence, durationMs, wordTimings, markersInjected}`.

JS surface: `import Parakeet from '../modules/parakeet'` exposes `isAvailable`, `isModelReady`, `downloadModel`, `transcribe(uri, manifest?)`, and `onDownloadProgress(cb)`.

### Name-linking is Mac-side (no on-device sanitise)

The phone does **not** link names. It sends the trusted transcript and the Mac runs its (now non-blocking) name-linking: unambiguous aliases auto-link to `[[Canonical]]`, ambiguous ones are left plain and resolved at the Mac's review step. `lib/sanitise.ts` and `components/DisambiguationModal.tsx` were removed in the 2026-06 mobile overhaul (matching the desktop overhaul). The names DB still syncs — it feeds the Mac's linker and the diarization voice profiles (`voiceEmbeddings`).

### Names UI (`components/NamesList.tsx`)

Mirrors desktop's `NamesTab.tsx`. Expandable per-person rows (canonical, short, alias chips). Search box appears once you have more than 5 people. Tapping Delete writes a tombstone (the entry stays in `names.json` with `deleted: true` until the backend prunes it after 90 days).

### Sync target

The Mac's FastAPI backend at `http://<local-ip>:8000`. Audio + names traffic over the same connection. Memo upload: `POST /api/files/upload` (multipart). Health: `GET /api/system/health`.

## Design system

Color tokens in `constants/colors.ts` match the desktop app exactly:
- Accent purple: `#7c6bf5` (dark) / `#6c5ce7` (light)
- Dark theme is default
- Background: `#0f1117`, Surface: `#181a23`
- Destructive red: `#ef4444` (used for record button)

## API notes

### expo-audio (SDK 54)
- Hook-based: `useAudioRecorder(preset)`, `useAudioPlayer(source)`, `useAudioRecorderState(recorder)`, `useAudioPlayerStatus(player)`
- No class-based `Audio.Recording` / `Audio.Sound` — that's the old expo-av API
- Metering is on `RecorderState.metering`, NOT on `RecordingStatus`
- `RecordingPresets.HIGH_QUALITY` records .m4a (AAC) by default
- Native `.pause()` / `.record()` (resume) supported. The hook tracks `totalPausedMs` so `duration` and photo `offsetSeconds` reflect recording time, not wall time.

### expo-file-system (SDK 54)
- New API: `File`, `Directory`, `Paths` classes — NOT the legacy `FileSystem.documentDirectory`
- `new File(Paths.document, 'name.json')` — create file reference
- `file.text()` (async), `file.write(string)` (sync), `file.exists` (property), `file.delete()`, `file.move(dest)`
- `directory.create()`, `directory.exists`

### FluidAudio
- Pinned to `0.12.4` via `spm_dependency` in `modules/parakeet/ios/ParakeetModule.podspec`. Version pinned because `0.13.x` shipped a Swift 6 concurrency error.
- API: `AsrModels.downloadAndLoad(version: .v3, progressHandler:)` → `AsrManager(config: .default).initialize(models:)` → `asr.transcribe(url, source: .system)`. (Note: the `main` branch renamed `initialize` → `loadModels`; we still use the older name.)
- Requires iOS 17.0+ (we set `IPHONEOS_DEPLOYMENT_TARGET = 17.0` in `Skrift.xcodeproj` and `app.json` `ios.deploymentTarget`).

## Status

- iPhone 13 builds + runs as a standalone Release app (free Apple personal team — re-sign every 7 days).
- TypeScript compiles clean (`npx tsc --noEmit`).
- `npm install --legacy-peer-deps` required due to peer dep conflicts in Expo 54.

## Memory optimizations

- FlatList uses `getItemLayout` + `removeClippedSubviews` for memo list.
- Waveform uses ref + in-place shift instead of `setState([...spread])` every 50ms.
- Storage caches parsed memos in-memory; invalidated on every write.
