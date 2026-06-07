# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

**Skrift** is a macOS desktop app for transcribing iPhone voice recordings (.m4a, .opus, .wav, .mp3, .mp4, .mov) and Apple Notes exports to text using MLX-accelerated Parakeet, then sanitising (name linking), enhancing (local MLX model), and exporting to Obsidian-compatible Markdown — all offline. The companion mobile app can run the same Parakeet model on-device via FluidAudio + Apple Neural Engine, send pre-transcribed memos that the Mac accepts directly, and stays in sync with the Mac's names database for shared name-linking.

Architecture: Electron + React frontend (`frontend-new/`) communicates with a FastAPI Python backend over HTTP on `localhost:8000`.

---

## Commands

### Run (development)

```bash
# Double-click to open in Terminal (sources full shell env, starts backend + Electron dev mode)
open '/Users/tiurihartog/Hackerman/Skrift/Open Skrift New.command'

# Or manually:
cd frontend-new && npm run dev:electron   # Vite dev server + Electron concurrently

# Stop backend
cd backend && ./start_backend.sh stop
```

### Frontend only (from `frontend-new/`)

```bash
npm run dev            # Vite dev server only (no Electron)
npm run dev:electron   # Vite dev server + Electron (full dev mode)
npm run build          # TypeScript check + Vite production build → renderer-dist/
npm run build:electron # Full build + electron-builder → dist-electron/Skrift-*.dmg
npm run type-check     # TypeScript check (no emit)
npm run lint           # ESLint with auto-fix
```

### Backend only (from `backend/`)

```bash
./start_backend.sh start     # Start (resolves deps from user_settings.json or defaults)
./start_backend.sh stop
./start_backend.sh restart
./start_backend.sh status
```

Backend runs on `http://localhost:8000`. API docs at `http://localhost:8000/docs`.

### Building a distributable

```bash
cd frontend-new && npm run build:electron
# Output: dist-electron/Skrift-0.1.0-arm64.dmg
# App icon: /Users/tiurihartog/Hackerman/Skrift/Icons/Skrift_icon_light.icns
```

The packaged app spawns the backend via `bash -l backend/start_backend.sh start` (login shell so Homebrew PATH is available). Falls back to `~/Hackerman/Skrift/backend/start_backend.sh` if relative path not found.

**Important:** `start_backend.sh` resolves its own location via `BASH_SOURCE`, reads the dependencies path from `config/user_settings.json`, and exports `/opt/homebrew/bin` so `ffmpeg` is always available. On first launch it auto-creates the Python venv if not present.

---

## Architecture

### Backend (`backend/`)

FastAPI app with routers split by domain:

| Router | Prefix | Purpose |
|--------|--------|---------|
| `api/files.py` | `/api/files` | Upload, list, delete audio/note files |
| `api/transcribe.py` | `/api/process/transcribe` | Trigger Parakeet transcription; supports `force` flag to re-transcribe |
| `api/sanitise.py` | `/api/process/sanitise` | Name linking — **non-blocking**: unambiguous aliases auto-link; ambiguous ones are carried on the note as `ambiguous_names` and resolved at review (no 409). (Now mostly invoked inside the auto-run, not directly.) |
| `api/enhance.py` | `/api/process/enhance` | MLX text enhancement (copy-edit/title/summary), **deterministic** tag suggestions, manual significance setter, **`POST /resolve-names`** (apply review-time ambiguous-name choices), model management |
| `api/export.py` | `/api/process/export` | Compile + export to Markdown/Obsidian |
| `api/batch.py` | `/api/batch` | The **auto-run orchestrator** (`/batch/run/start`) — transcribe→enhance→name-link→compile to Ready; SSE progress stream |
| `api/system.py` | `/api/system` | Resource monitoring, health check |
| `api/config.py` | `/api/config` | Read/write user settings, dependency detection/setup |
| `api/names.py` | `/api/names` | Phone↔Mac names sync: meta GET, full GET, full PUT |

Business logic lives in `services/`:
- `transcription.py` — Parakeet-MLX transcription (in-process, model cached as singleton between calls). Audio preprocessing via ffmpeg: high-pass filter + `afftdn` adaptive denoiser + EBU R128 loudness normalization. Produces `word_timings.json` by merging BPE sub-word tokens into whole words. **Parakeet loads from local files only — never downloads from HuggingFace.**
- `sanitisation.py` — Name linking. `process_sanitisation` auto-links unambiguous aliases and returns ambiguous occurrences as data (no blocking). `apply_resolved_names(text, decisions)` applies the user's review-time choices to the current body (first mention → `[[Canonical]]`, rest → short name; preserves existing links + edits). (`resolve_name_disambiguation` is the old session-based path — now frontend-orphaned.)
- `enhancement.py` — MLX model invocation (streaming SSE); auto-unloads after 10s idle in manual mode. **All LLM steps (copy-edit/title/summary) run on the RAW transcript** — no `[[ ]]` ever reaches the LLM (the bracket-preservation hack was deleted).
- `export.py` — Markdown/Obsidian compilation; reads `export.attachments_folder` for image destination
- `batch_manager.py` — **The single auto-run orchestrator** (`start_run`/`_process_run`, `POST /api/batch/run/start`). Two model-grouped passes: transcribe-all (Parakeet hot) → enhance-all (copy-edit/title/summary on the raw transcript → **deterministic** tag *candidates* → name-link → compile draft) → lands at **Ready for Review**. A single file is a run of one. No mid-flight human gates. SSE broadcast of tokens; MLX model stays loaded across the run.
- `mlx_runner.py` + `mlx_cache.py` — MLX model singleton cache; survives between calls within a session
- `apple_notes_importer.py` — Apple Notes `.md` export parser; sets `source: Apple-Note` in frontmatter

**One Process action drives everything** (`POST /api/batch/run/start`) — the Sidebar's batch "Process" and the toolbar's single-file "Process" both call `startRun`. The old separate transcribe/enhance batch endpoints were removed in the overhaul. Live progress streams via SSE at `GET /api/batch/enhance/stream`.

`utils/status_tracker.py` — heartbeat-style status files stored as `status.json` per file in the output folder.

`config/settings.py` — `Settings` class with dot-notation access (`settings.get('transcription.parakeet_model')`). User overrides persisted to `~/Library/Application Support/Skrift/user_settings.json`. On first launch, seeds from `config/user_settings.template.json` (clean, no personal paths).

**Key settings paths:**
- `export.note_folder` — Obsidian vault root
- `export.audio_folder` — vault subfolder for voice memos
- `export.attachments_folder` — vault subfolder for images/attachments (falls back to vault root if empty)
- `enhancement.tags` — `{ max_old, max_new, selection_criteria }`
- `transcription.noise_reduction` — afftdn noise floor in dB (-10 = aggressive, -30 = gentle, 0 = off)
- `transcription.highpass_freq` — High-pass filter cutoff in Hz (0 = off, 80 = default)

**Dependency detection API** (`/api/config/deps/*`):
- `GET /deps/detect` — scans ~/Skrift_dependencies, ~/Downloads, ~/Desktop for valid deps folder or `.zip` files
- `GET /deps/validate?path=...` — checks a folder for venv, MLX models, Parakeet model
- `POST /deps/extract` — extracts a `.zip` to ~/Skrift_dependencies, validates
- `POST /deps/apply` — saves deps path, auto-selects first MLX model

**File storage layout:**
```
~/Documents/Voice Transcription Pipeline Audio Output/
└── [file_id]_[filename]/
    ├── original.m4a          # or original.md for Apple Notes
    ├── processed.wav         # denoised + normalized audio fed to Parakeet
    ├── compiled.md
    ├── status.json           ← single source of truth for all state
    ├── word_timings.json     # word-level timestamps for karaoke
    ├── image_manifest.json   # (optional) timestamped photo offsets from mobile
    └── images/               # (optional) photos captured during recording
        ├── photo_xxx_001.jpg
        └── photo_xxx_002.jpg
```

**Health endpoint:** `GET /api/system/health` returns `transcription_modules.parakeet.available`.

**Upload handler trust logic** (`api/files.py:upload_files`):
The mobile app may send `transcript`, `sanitised`, and metadata flags alongside the audio file. The handler decides whether to skip the Mac's own transcription/sanitisation steps:
- `transcript` is trusted iff `transcriptUserEdited === true` OR `transcriptConfidence >= 0.7`. Trusted transcripts → `transcript.txt` written, `steps.transcribe = done`, `audioMetadata.transcript_source = "mobile"` (plus `transcript_markers_injected` if mobile did the photo markers).
- `sanitised` is honored only if `transcript` was trusted. Sets `steps.sanitise = done`, `audioMetadata.sanitise_source = "mobile"`.
- Low-confidence transcripts are silently dropped — the Mac re-runs transcribe + sanitise from scratch.
- `.opus` is supported alongside `.m4a`/`.wav`/`.mp3`/etc. (WhatsApp voice notes work directly via Share Sheet).

### Frontend (`frontend-new/`)

Entry: `src/main.tsx` → `App.tsx`

`App.tsx` is the shell — manages the selected file, audio/karaoke state (`isPlaying`/`currentTime`/`seekTo`/`tokens`), first-launch detection, and the review-time mutation handlers (body, title, tags, significance, resolve-names, transcribe). It renders a **2-pane resizable layout** (`react-resizable-panels` v4 `Group`/`Panel`/`Separator`): **`Sidebar` | `NoteDisplay`**. Plus overlays: `SetupWizard`, `Settings`, `FindBar`, `<Toaster/>`. **There is no third "Inspector" column** — the redesign moved its controls into the note's toolbar + properties block (Phase 5).

**State = ONE source of truth.** `useFiles` (TanStack Query, key `['files']`) holds the full file objects and polls 1s only while something is processing; `useCurrentBatch` tracks the active run. The selected file + the enhance-lock are derived from it. Edits go through optimistic cache patches (`useFilesCache.patchFile`) + invalidation. **Do not reintroduce polling loops.** `NoteBody` has a dirty-guard so an in-flight refetch can't revert unsaved keystrokes.

**First-launch detection:** On mount, retries `GET /api/system/health` a few times before concluding setup is needed (so a booting/restarting backend doesn't flash the wizard). Shows `SetupWizard` only if the backend never comes up, parakeet is unavailable, or no deps folder is configured.

**Setup wizard** (`src/features/SetupWizard.tsx`): Step 1 auto-detects `Skrift_dependencies.zip`/folder (one-click extract to `~/Skrift_dependencies`); Step 2 author name + Obsidian vault paths (optional). Saves config to backend on complete.

Key files:
- `src/api.ts` — `api` singleton + `API_BASE`; all HTTP calls. Exports `DEFAULT_PROMPTS` (match `settings.py`) + types. Review-time setters: `setTitle(id,title,suggested?)`, `setCopyedit`, `setSummary`, `setTags`, `setSignificance`, `resolveNames(id,decisions)`, `startRun(ids)`.
- `src/types/pipeline.ts` — `PipelineFile` (incl. `title_suggested`, `ambiguous_names`, `significance`), `AmbiguousOccurrence`/`NameCandidate`, `SystemHealth`.
- `src/hooks/useSettings.ts` — `AppSettings`; **backend config is nested** — use `(config as any)?.export?.note_folder`, never dot-keys.
- `src/hooks/useFiles.ts` — the single `useFiles`/`useCurrentBatch` queries + `useFilesCache`.
- `src/features/Sidebar.tsx` — **virtualized** queue (`@tanstack/react-virtual`, windowed rows) with honest status chips (Queued/Transcribing/Transcribed/Enhancing/Ready/Exported/Error); multi-select batch **Process** (`startRun`) / Delete; drag/picker/folder upload; header has a top band for the inset macOS traffic lights. Fills its resizable panel (no hard width).
- `src/features/NoteDisplay.tsx` — the middle pane: breadcrumb → a pinned **toolbar bar** (`NoteToolbar` audio transport on the left + `NoteActions` on the right) → scroll area (`ResolverStrip` when ambiguous names exist → `NoteProperties` → summary → `NoteBody`/`KaraokeText`). `NoteBody` stays mounted, hidden during karaoke.
- `src/components/NoteProperties.tsx` — the editable **properties block**: two-title chooser (Suggested = `title_suggested` vs From-recording = cleaned filename; active card editable), significance **slider** (`ui/slider`), tag chips + **vault autocomplete** (`ui/command`/cmdk over the cached `/tags/whitelist` — never scans the vault) + one-tap dashed suggestion chips from `tag_suggestions`, metadata grid.
- `src/components/NoteToolbar.tsx` — owns the `<audio>`; skip ±10s (circular-arrow-with-10), play, draggable click-to-seek scrubber, speed cycle. Renders inline so the toolbar bar can also hold `NoteActions`.
- `src/components/NoteActions.tsx` — contextual primary button (**Process → Export to Obsidian → Re-export**) + a ⋯ overflow (re-transcribe, per-step redo title/copy-edit/summary) + the RAM-warning dialog + a toast when another note is enhancing (only one MLX run at a time).
- `src/components/NoteBody.tsx` — contenteditable. `getBestText` prefers **`sanitised`** (so the body shows the name-linked text that exports — `[[links]]` visible), then `enhanced_copyedit`, then `transcript`; edits save to that same field. Dirty-guard; selection toolbar → `AddNameModal`; renders image markers as inline `<img>`.
- `src/components/KaraokeText.tsx` — highlights the **body** text itself (same words + typography, so play never reflows — the old jump bug); uses transcript `word_timings` only to drive the moving highlight + click-to-seek (proportional alignment, approximate within seconds).
- `src/components/ResolverStrip.tsx` — review-time ambiguous-name resolver; groups `ambiguous_names` by alias, shows context + candidate people + "leave as plain", submits to `resolveNames`.
- `src/components/ui/*` — shadcn primitives adapted to the app tokens (button, dialog, input, tabs, tooltip, slider, sonner, command).
- `src/features/Settings.tsx` + `settings/*` — preferences UI. `EnhancementTab` shows the single text-only model + `TagSettings`; `TranscriptionTab` has audio-preprocessing sliders. **Config reads use nested access.**

**Removed in the overhaul (do not reference):** `Inspector.tsx`, `ExportPreview.tsx`, `DisambiguationModal.tsx`, `StepDots.tsx`, `AudioPlayer.tsx`, the chat feature (`ChatPanel`/`ChatInput`/`api/chat.py`), and the dead VLM/vision path.

### Electron (`frontend-new/electron/`)

- `main.cjs` — main process; spawns backend via `bash -l`; uses `fs.existsSync` to fall back to absolute repo path; registers `file://` protocol for audio playback; `dialog:openUpload` IPC opens native picker accepting files and folders; `dialog:openFiles` supports `accept` filter (e.g. `['zip']`). **Native macOS chrome:** `titleBarStyle: 'hiddenInset'` + `trafficLightPosition` — the inset traffic lights float over the Sidebar header's top band (which is `WebkitAppRegion: drag`). (Vibrancy not enabled — would need translucent surfaces.)
- `preload.cjs` — contextBridge exposing `electronAPI` to renderer

### Design system

Colors use space-separated RGB values in CSS variables (e.g. `--color-primary: 37 99 235`) so Tailwind's alpha modifier works (`bg-primary/10`). Never use comma-separated values. Dark mode tokens are defined under `:root.dark`.

### Config architecture — single source of truth

**The backend is the single source of truth for all configuration.** The frontend uses localStorage only as a fast startup cache, and always overwrites it with backend values on mount.

Key rules:
- Backend `GET /api/config/` returns a **nested** dict (e.g. `{ "export": { "note_folder": "..." } }`)
- Frontend must use nested access: `(config as any)?.export?.note_folder` — **never** dot-notation keys like `config['export.note_folder']`
- `DEFAULT_PROMPTS` in `api.ts` must stay in sync with `settings.py` defaults. When no user overrides exist in `user_settings.json`, the frontend fetches backend defaults via `/api/config/defaults` and uses those.
- `user_settings.template.json` is the clean seed for new installs (no personal paths). The developer's `user_settings.json` is excluded from the DMG build.
- `names.json` is also excluded from the DMG build. If missing, sanitisation defaults to empty people list.

### Sanitise / name-linking flow (non-blocking)

Name-linking is the **last** deterministic step of the auto-run and never blocks. Unambiguous aliases auto-link to `[[Canonical]]`; an alias that maps to 2+ people is left as plain text and recorded on the note as `ambiguous_names` (each: `alias`, `offset`, context, `candidates[]`). At review, `ResolverStrip` surfaces these; the user picks a person (or "leave plain") and `POST /api/process/enhance/resolve-names` applies the choices to the body via `apply_resolved_names`, clears `ambiguous_names`, and recompiles. **No 409, no mid-pipeline modal.** The body the user sees/edits prefers `sanitised`, so the applied links are visible (what you see = what exports).

### Transcription pipeline

Parakeet-MLX is the sole transcription engine. Audio preprocessing: ffmpeg high-pass → afftdn adaptive denoiser → EBU R128 loudness normalization → 16kHz mono WAV. The Parakeet model is cached as a singleton (loads once, stays in memory). **Parakeet uses local model files only — never downloads from HuggingFace.** Model files must exist in `{dependencies_folder}/models/parakeet/` (HF cache structure). Progress is reported via `chunk_callback` for long files. Force-retranscribe deletes `processed.wav` so preprocessing runs fresh with current denoiser settings.

Sub-word BPE tokens from Parakeet are merged into whole words using leading-space detection before writing `word_timings.json`.

### Enhancement pipeline

**Single text-only model:** `gemma-4-e4b-it-8bit` (~8.4 GB). No vision model. Photos are placed in the text by position only — the LLM never describes them.

The cache (`mlx_cache.py`) calls `mx.clear_cache()` on unload to prevent Metal memory leaks.

**RAM check:** Compares model size against **total system RAM** (not `psutil.virtual_memory().available`, which reads artificially low on macOS due to aggressive file caching). Only blocks when the model physically can't fit with 25% headroom.

**Prompts** (defined in `backend/config/settings.py` `DEFAULT_SETTINGS.enhancement.prompts`):
- `copy_edit` — minimal cleanup, preserves English/Dutch mixing, collapses speech stumbles/self-corrections, removes filler words. Does NOT rephrase or restructure.
- `summary` — 1–3 sentences, matches primary language of text.
- `title` — 5–15 words, matches primary language. (Stored as `title_suggested`; the review chooser offers it vs the recording's own name.)
- **No LLM significance, no LLM tagging.** Significance is a **manual slider** at review (`POST /enhance/significance`, plain YAML number). Tags are **deterministic**: at capture, lemmatized transcript words that match a vault tag NAME ≥2× (frequency-gated) + spoken `#hashtags` → `tag_suggestions`; the user one-taps to apply. (Any leftover `importance` prompt in settings is unused.)

**Copy-edit with image markers** (`copy_edit_with_image_markers_stream` in `enhancement.py`):
For transcripts containing `[[img_NNN]]` markers:
1. Save anchor words around each marker (last ~6 words before, first ~6 after)
2. Strip the markers (the LLM can't be trusted to preserve them)
3. Run a normal copy-edit
4. Reinsert markers via `_reinsert_image_markers()` — search the edited text for the anchor words, place the marker after the matching sentence. Falls back to proportional placement if no anchor matches.

No vision step — photos appear in the text but are not described by AI.

Both single-file and batch go through the **one auto-run** (`batch_manager`): copy-edit/title/summary on the raw transcript → deterministic tag *candidates* → name-link → compile draft → **Ready for Review**. Streaming uses SSE with `status` events ("Loading model...", "Generating title...", "Editing text...") so the toolbar action shows live progress.

**`steps.enhance == done` means the auto-steps are complete (title + copy-edit + summary present) — NOT that tags/significance are set.** Tags and significance are **review-time** (set in the properties block), not gates. The sidebar batch progress bar tracks `enhanced_title && enhanced_summary` (so it fills when the LLM work is done, before the user reviews). `compile_file` body precedence is `sanitised → enhanced_copyedit → transcript`.

### Apple Notes import

Dropping or selecting a folder via `+ Upload`:
- Electron's `dialog:openUpload` IPC returns both file paths and folder paths
- Folder paths sent as `note_folder_paths` JSON field in FormData
- Backend `apple_notes_importer.py` parses the `.md`, extracts title/date/content, sets `source: Apple-Note`
- Images referenced in the note are resolved to `export.attachments_folder` on export

Dragging a single `.md` file also works (treated as a note file).

### People / names config

`backend/config/names.json` — timestamped schema for bidirectional phone↔Mac sync:
```json
{
  "lastModifiedAt": "2026-04-27T13:48:21Z",
  "people": [
    {
      "canonical": "[[Full Name]]",
      "aliases": ["Nick"],
      "short": "Nick",
      "lastModifiedAt": "2026-04-27T13:48:21Z",
      "deleted": false
    }
  ]
}
```
- Top-level `lastModifiedAt` = max of all per-entry timestamps. Recomputed on every write. Phone uses it for cheap pre-sync meta-checks.
- Per-entry `lastModifiedAt` drives last-write-wins merge during sync.
- `deleted: true` is a tombstone — propagates the deletion across devices, then pruned after 90 days.
- **No duplicate aliases** — duplicates cause false ambiguity in sanitise.
- One-time migration: any pre-timestamp file gets backfilled with `lastModifiedAt` on first read via `backend/utils/names_store.py`.

Centralised store: [backend/utils/names_store.py](backend/utils/names_store.py) (`read_names`, `write_names`, `write_with_smart_bumps`, `prune_old_tombstones`).

**API endpoints:**
- `GET /api/config/names` — desktop UI; returns live people only (no tombstones).
- `POST /api/config/names` — desktop save; uses `write_with_smart_bumps` (only changed entries get a fresh timestamp; removed entries auto-tombstone).
- `GET /api/names/meta` — tiny payload `{lastModifiedAt}` for the phone's cheap pre-check.
- `GET /api/names` — full file including tombstones (phone consumes during sync).
- `PUT /api/names` — phone pushes its merged result; server writes verbatim then prunes old tombstones.

Edited via Settings → Names in both the desktop and mobile UIs. File is excluded from DMG build; if missing, defaults to empty list.

---

## External dependencies

All heavy dependencies live **outside the repo** in a configurable dependencies folder (default `~/Skrift_dependencies/`):
- `mlx-env/` — Python venv with FastAPI, parakeet-mlx, mlx-lm (auto-created by `start_backend.sh` on first launch)
- `models/parakeet/` — Parakeet TDT v3 model weights (HF cache structure, **local only — no auto-download**)
- `models/mlx/gemma-4-e4b-it-8bit/` — text-only enhancement model (the only LLM Skrift uses)

The path is configurable via `settings.get('dependencies_folder')`. `start_backend.sh` reads it from `config/user_settings.json` at startup.

`ffmpeg` must be on PATH — installed via Homebrew at `/opt/homebrew/bin/ffmpeg`. `start_backend.sh` prepends `/opt/homebrew/bin` to PATH at startup to ensure this works in all launch contexts.

### Distribution

The distribution folder (`~/Desktop/Skrift-Distribution/`) contains:
- `Skrift-0.1.0-arm64.dmg` — the Electron app (no personal config baked in)
- `Skrift_dependencies.zip` — models (~10 GB): `models/mlx/gemma-4-e4b-it-8bit/` + `models/parakeet/`
- `setup.sh` — backup/alternative setup script (installs Python, ffmpeg, creates venv)
- `README.txt` — setup instructions

**New user flow (zero manual steps):**
1. Download DMG + `Skrift_dependencies.zip` to Downloads
2. Install app (drag to Applications)
3. Open app → backend auto-creates Python venv (first time, ~2-5 min)
4. Setup wizard auto-detects zip in Downloads → click "Set up" → extracts to `~/Skrift_dependencies`
5. Wizard step 2: set author name, Obsidian vault paths (optional)
6. Done — no terminal, no `setup.sh` needed

**DMG build excludes:** `user_settings.json`, `names.json` (via `package.json` `extraResources` filter). Seeds from `user_settings.template.json` on first launch.

The `mlx-env/` venv is NOT distributed (path-specific); `start_backend.sh` bootstraps it automatically. The Parakeet model is pre-bundled in the zip (no HuggingFace download).

### Photo capture (mobile → desktop pipeline)

Users can take timestamped photos during voice recording on the mobile app. The flow:
1. **Mobile**: Camera preview during recording, shutter button captures photos with timestamp offsets
2. **Mobile transcription** (when on-device Parakeet is available): `[[img_NNN]]` markers are injected directly in Swift inside `Mobile/modules/parakeet/ios/ParakeetModule.swift` using FluidAudio's `tokenTimings`. BPE sub-word tokens are merged into whole words; for each photo the closest word's character end is the insertion point. Bit-for-bit equivalent to the Mac's algorithm.
3. **Sync**: Audio + images + `image_manifest.json` + (optionally) marker-injected transcript sent as multipart upload. Mobile sets `transcriptMarkersInjected: true` in metadata so the Mac knows.
4. **Mac transcription** (only runs when mobile didn't send a trusted transcript): `_insert_image_markers()` in `backend/services/transcription.py` does the same job server-side.
5. **Enhancement**: Copy-edit with marker-preservation (E4B copy-edits text, markers reinserted programmatically by transcript-word anchoring — no AI vision)
6. **Export**: `[[img_XXX]]` → `![[title-slug_XXX.jpg]]` Obsidian embeds, images copied to `export.attachments_folder`

Mobile app key files:
- `Mobile/contexts/RecordingContext.tsx` — shared recording state between tab layout and record screen. Exposes `isPaused`, `pauseRecording`, `resumeRecording`.
- `Mobile/app/(tabs)/record.tsx` — camera preview + shutter (CameraView must have ZERO React children to avoid Fabric crashes). Pause/resume button below timer during recording.
- `Mobile/app/(tabs)/_layout.tsx` — tab bar record/stop button
- `Mobile/app/review.tsx` — photo filmstrip with timestamps
- `Mobile/lib/storage.ts` — `copyPhotosToRecordings()`, `imageManifest` in metadata. In-memory cache for `loadMemos()` to avoid repeated JSON parsing. Shared `updateMemoSyncStatus()`.
- `Mobile/lib/sync.ts` — sends images as multipart `images` field. `reconcileSyncStatus()` queries backend `GET /api/files/` to mark already-uploaded memos as synced (handles stale status after IP changes).

**Pause/resume recording:** expo-audio's `AudioRecorder` supports native `.pause()` / `.record()` (resume). The hook tracks `totalPausedMs` so `duration` and photo `offsetSeconds` reflect recording time, not wall time. A photo taken at wall-clock 30s but with 10s paused gets `offsetSeconds=20`.

**Memory optimizations:** FlatList uses `getItemLayout` + `removeClippedSubviews` for memo list. Waveform uses ref + in-place shift instead of `setState([...spread])` every 50ms. Storage caches parsed memos in-memory.
