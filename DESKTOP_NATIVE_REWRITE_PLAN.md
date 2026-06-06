# Skrift Desktop — Native (SwiftUI/AppKit) Rewrite Plan

> Decision (2026-06-05): rewrite the Skrift **desktop** app from Electron + React
> (`frontend-new/`) + a FastAPI/Python backend (`backend/`) to a **single native
> macOS app** in Swift. The headline win is collapsing the two-process
> (Electron UI ↔ Python backend over HTTP) architecture into **one process**:
> FluidAudio (Swift) for transcription + **mlx-swift** for the Gemma enhancement
> LLM, both in-process — **no Python, no `localhost:8000` client/server split, no
> "backend won't start" failure mode** (the historical "feels buggy" root cause).
> Plus: far lower RAM (no Chromium → more headroom for the MLX models), native
> file-watching for watched-folder ingest, and unification with the iOS native
> rewrite + Shhhcribble on one stack + one test harness (XCUITest).

This runs as a **parallel track** to the iOS rewrite (branch `mobile-native`).
They share the repo + history + the mobile↔Mac **contract**, but touch different
folders, so they don't collide.

- **Branch:** `desktop-native` (this worktree, off `mobile-overhaul`).
- **Worktree:** `/Users/tiurihartog/Hackerman/Skrift-desktop` (separate folder, same
  repo as `/Users/tiurihartog/Hackerman/Skrift`). The Electron app (`frontend-new/`)
  + Python `backend/` keep running until the native app reaches parity, then retire.
- **New code lives in:** `SkriftDesktop/` (xcodegen project, like `SkriftMobile/`).

---

## 0. Hard rules
- **PRIVACY:** never point AI/agents at the user's Obsidian vault contents. The
  app's OWN local Swift code scanning the vault (for the tag whitelist, export) is
  fine — that's the design — but Claude/agents must not read the vault. Test with a
  small sample the user provides. (See memory `feedback_vault_privacy`.)
- **Keep it simple;** don't over-engineer. **Bring the user along** — for the review
  UI especially, mock/screenshot before building (memory `feedback_visual_ui_iteration`;
  the desktop is an EDITOR, WYSIWYG to the Obsidian markdown).
- **Verify every chunk + commit per phase.** Native verification = `xcodebuild build`
  + `xcodebuild test` (XCUITest) on macOS, read logs/screenshots.
- **Preserve the mobile↔Mac contract byte-for-byte** (§4) — the iOS app (being
  rewritten in parallel) is a live client. Don't change the wire format.
- **Read the existing app as the source of truth:** `backend/` (the pipeline +
  contract) and `frontend-new/src/` (the review UX) are in this worktree. Port
  behavior from them; don't reinvent product decisions. Root `CLAUDE.md` documents
  the whole pipeline.

---

## 1. Target architecture — one native process

```
SkriftDesktop/
├── App/                  # @main SwiftUI App, window/menu, SwiftData container, deep links
├── Features/
│   ├── Sidebar/          # the ingest queue (honest status chips) — mirrors frontend Sidebar
│   ├── Review/           # the note editor: toolbar + properties block + body + karaoke
│   │                     #   (NoteProperties: two-title chooser, significance slider,
│   │                     #    tag chips + vault autocomplete; ResolverStrip for ambiguous names)
│   ├── Settings/         # deps/model selection, Obsidian paths, names, prompts
│   └── SetupWizard/      # first-launch (deps detect/extract, author + vault paths)
├── Pipeline/             # the former backend, in-process Swift:
│   ├── Transcription/    # FluidAudio (ASR) + audio preprocessing
│   ├── Enhancement/      # mlx-swift: copy-edit / title / summary (the RISK — §6)
│   ├── Tags/             # deterministic lemma matching (NLTagger) + spoken #hashtags
│   ├── Sanitisation/     # name-linking (non-blocking; ambiguous → review resolver)
│   ├── Export/           # Obsidian markdown compile + write to the vault
│   └── BatchManager/     # the auto-run orchestrator (transcribe→enhance→tag→link→compile)
├── Server/               # thin local HTTP server + Bonjour — the phone's sync target (§4)
├── Models/               # PipelineFile/Memo, Person/NamesData, settings (SwiftData/Codable)
└── SkriftDesktopUITests/ # XCUITest harness (§5)
```

**Why one process works:** the heavy lifting was always in the backend, not the UI.
Moving it in-process (FluidAudio + mlx-swift) removes the HTTP hop + the Python venv
lifecycle. The UI talks to the pipeline via direct Swift calls; the **only** HTTP
left is the small server that the *phone* talks to (§4).

---

## 2. Electron/React → native feature map (port these behaviors)

From `frontend-new/src/` + `backend/`:
- **Ingest queue (Sidebar):** drag/drop + file picker + folder (Apple Notes) +
  phone sync. Honest status chips (Queued/Transcribing/Transcribed/Enhancing/Ready/
  Exported/Error). Multi-select batch Process/Delete.
- **Auto-run pipeline (BatchManager):** transcribe → copy-edit → title → summary →
  deterministic tag candidates → name-link → compile draft → **Ready for Review**.
  No mid-flight gates. All LLM steps run on the RAW transcript.
- **Review surface (the hard UI):** 2-pane (Sidebar | NoteDisplay). NoteDisplay =
  pinned toolbar (audio transport + actions) → ResolverStrip (ambiguous names) →
  NoteProperties (two-title chooser, significance **slider**, tag chips + vault
  autocomplete, metadata grid) → summary → body editor + **karaoke** (highlight body
  words off transcript `word_timings`). Body precedence: sanitised → copyedit →
  transcript. WYSIWYG to the exported markdown (brackets visible).
- **Export to Obsidian:** compile markdown + YAML frontmatter, copy audio/images to
  the vault's configured folders.
- **Settings / SetupWizard:** dependency detect/extract, model selection, Obsidian
  vault paths, author, names management, prompts, audio-preprocessing sliders.

---

## 3. Pipeline port mapping (Python → Swift)

| Backend (Python) | Native (Swift) | Risk |
|---|---|---|
| Parakeet-MLX transcription (`transcription.py`) | **FluidAudio** (proven on macOS — Shhhcribble has a Mac sibling) | LOW |
| ffmpeg preprocessing (highpass/denoise/normalize) | AVFoundation/`AVAudioEngine` filters, or bundle a static `ffmpeg` | MED |
| Gemma enhancement via mlx-lm (`enhancement.py`) | **mlx-swift / mlx-swift-examples (MLXLLM)** | **HIGH — spike first (§6)** |
| Deterministic tags via simplemma (`enhancement.py`) | **NLTagger** lemmas (nl+en) + spoken `#hashtag` regex; ≥2× freq gate | MED (lemma parity) |
| Name-linking (`sanitisation.py`) | Swift port (non-blocking; ambiguous → `ambiguous_names` for the resolver) | LOW |
| Export (`export.py`) | Swift string/markdown + FileManager writes to vault | LOW |
| Tag whitelist refresh (vault scan, frontmatter only) | Swift FileManager scan (app's own code — privacy OK) | LOW |
| `names_store.py` (LWW, tombstones, voiceEmbeddings union) | Swift (the iOS app already has this logic to mirror) | LOW |
| status.json / per-file state | SwiftData (or Codable JSON) | LOW |

Keep the on-disk layout + Obsidian output identical so the user's vault + existing
notes are unaffected.

---

## 4. The phone's sync target — thin Swift server + Bonjour (PRESERVE THE CONTRACT)

The iOS app (parallel rewrite) syncs to the Mac over HTTP. The native desktop must
keep a **small local HTTP server** exposing the SAME endpoints the phone uses, so
the phone keeps working unchanged. Source of truth: `backend/api/files.py` (upload),
`backend/api/names.py`, `backend/api/system.py` (health).

Endpoints to serve (match exactly):
- `POST /api/files/upload` (multipart): `files` (audio), `images`, `attachments`,
  `metadata` (JSON: location/weather/pressure/daylight/dayPeriod/steps/tags/
  recordedAt/duration/transcriptConfidence/transcriptUserEdited/
  transcriptMarkersInjected/imageManifest/sharedContent/annotationText/source),
  `transcript` (string). Trust = `transcriptUserEdited || transcriptConfidence ≥ 0.7`.
  Phone sends NO `sanitised` (Mac links names). On receipt → enqueue into the
  in-process BatchManager.
- `GET /api/names/meta` → `{lastModifiedAt}`; `GET /api/names` (full incl.
  tombstones + voiceEmbeddings); `PUT /api/names` (merged; write verbatim + prune).
- `GET /api/system/health`. `GET /api/files/` (reconcile by filename — filenames
  embed the memo UUID).

**Transport decision (locked):** keep local-network HTTP (tiny Swift server —
`Network` framework or Vapor) **+ advertise via Bonjour/mDNS** so the phone
**auto-discovers** the Mac (no manual IP / QR). This stays fully **local (no cloud)**
and removes today's biggest sync friction. Keep the server behind a `SyncServer`
protocol so CloudKit could be swapped in later if the user ever wants
sync-anywhere (a separate values call — Apple's cloud vs the local/offline ethos).

---

## 5. Testing harness — XCUITest on macOS (model: Pike Companion + the iOS rewrite)
Reference: `/Users/tiurihartog/Hackerman/Matthew smith stretching app/.claude/worktrees/laughing-bhabha-917fe3/app/PikeCompanionUITests/SessionWalkthroughUITests.swift`,
and the iOS rewrite's `SkriftMobileUITests/` (in the `mobile-native` worktree).
- **Launch-arg test hooks** the app reads from `ProcessInfo`: `-skipSetup`,
  `-inMemoryStore`, `-seedDemoFiles`, `-seedTranscript` (skip real ASR — see below),
  `-stubEnhancement` (skip the LLM so UI tests are fast/deterministic).
- Helpers: `visibleTexts`/`dump`/`snap`/`tapAny`, accessibility identifiers on every
  key control. Run via `xcodebuild test`; read `SCREEN[...]` dumps + screenshots.
- **Real ASR + the MLX LLM are slow/heavy** — for UI tests, seed transcripts +
  stub enhancement; verify the real pipeline in dedicated (non-UI) integration tests
  + manually. The pipeline (FluidAudio + mlx-swift) DOES run on a Mac (unlike the
  iOS sim's missing ANE), so a real end-to-end test is possible but slow.
- **Round-trip the phone↔Mac contract** against the iOS app once both exist.

Commands:
```
cd SkriftDesktop && xcodegen generate
xcodebuild build -project SkriftDesktop.xcodeproj -scheme SkriftDesktop \
  -destination 'platform=macOS' -derivedDataPath build
xcodebuild test  -project SkriftDesktop.xcodeproj -scheme SkriftDesktop \
  -destination 'platform=macOS' -derivedDataPath build -resultBundlePath /tmp/skd_ui.xcresult
```
(Run long builds via Bash `run_in_background: true` + `dangerouslyDisableSandbox: true`.)

---

## 6. Risks / spike-first items
- **🔴 mlx-swift running Gemma (the enhancement LLM) — THE risk. Spike in Phase 0/1.**
  The desktop uses `gemma-4-e4b-it-8bit` via Python `mlx-lm`. Verify mlx-swift /
  mlx-swift-examples (MLXLLM) can load + run that model (or an equivalent quant) with
  acceptable quality/speed. If it can't yet, the fallback is a **hybrid** (keep a
  minimal Python MLX sidecar JUST for enhancement) — which weakens the "delete
  Python" win, so confirm early. FluidAudio (ASR) is low-risk (Mac-proven).
- **Rich editor + karaoke in SwiftUI** — Mac SwiftUI text editing is weaker than web
  contenteditable for WYSIWYG markdown + the karaoke highlight. Budget time; mock the
  review surface for the user before building (it's the product's heart).
- **ffmpeg** — either bundle a static binary or replace with AVFoundation filters.
- **Lemma parity** — NLTagger vs simplemma will differ slightly; tags are
  suggestions-only, so acceptable, but note it.
- **Deps/model distribution** — the Python venv goes away; the MLX model files still
  need to ship/download. Rework the SetupWizard for native (no venv bootstrap).

---

## 7. Phase plan (each builds, tests, commits)
- **Phase 0 — toolchain spike + the mlx-swift risk.** xcodegen macOS app + FluidAudio
  + mlx-swift deps; minimal window; `xcodebuild build` + a first XCUITest green. In
  the SAME phase, a throwaway spike: load the Gemma model via mlx-swift and run one
  copy-edit prompt — **decide go / hybrid before building the pipeline.**
- **Phase 1 — data model + SwiftData** (PipelineFile/Memo, Person/NamesData, settings).
- **Phase 2 — thin sync server + Bonjour** (so the iOS app can talk to it early;
  round-trip names + a stub upload). Preserve the contract (§4).
- **Phase 3 — transcription** (FluidAudio + preprocessing; ingest an audio file → transcript).
- **Phase 4 — enhancement** (mlx-swift: copy-edit/title/summary on the raw transcript).
- **Phase 5 — tags + name-linking + compile/export** (deterministic tags, non-blocking
  sanitise, Obsidian markdown out).
- **Phase 6 — BatchManager auto-run** (wire the steps into the unattended pipeline → Ready).
- **Phase 7 — the review UI** (Sidebar + NoteDisplay + properties + body + karaoke +
  ResolverStrip). Mock first.
- **Phase 8 — ingest + Settings + SetupWizard** (drag/folder/phone; deps/model/vault config).
- **Phase 9 — parity sweep + retire Electron/Python** (or keep Python only if the
  mlx-swift spike forced a hybrid).

---

## 8. Coordination with the iOS track (don't collide)
- Shared: the repo + the **contract** (§4) + memory + docs. The phone (mobile-native)
  is a client of this app's §4 server.
- **Do NOT prematurely extract a shared Swift package** between phone + desktop while
  both are half-built in separate chats — duplicate the small bits (names model,
  contract types), converge later. Keeps the parallel tracks conflict-free.
- Both follow FluidAudio `branch: main` + the same XCUITest harness style.
- Merge both `*-native` branches to a `native` integration branch only once each
  reaches parity; `main` stays the old baseline until then.

## 9. Status
- [x] Phase 0 — toolchain GREEN (xcodegen macOS app + FluidAudio linked + unit test passing; XCUITest written, needs a one-time macOS automation-permission grant) **+ mlx-swift Gemma 4 go/no-go = GO NATIVE.** Spike loaded the local `gemma-4-e4b-it-8bit` via `mlx-swift-lm` (main) and ran the exact `copy_edit` prompt correctly (removed fillers, collapsed false starts, preserved EN/NL — matches the Python pipeline). Debug build: load 3.2s, ~10.8 tok/s, peak ~8.75 GB (8bit). **No Python sidecar.** Distribution decision: ship models via **HF download** (no deps zip; progress bar in SetupWizard). Toolchain note: only `xcodebuild` compiles MLX's `.metallib` (plain `swift build` can't). Quant compare: 4bit (5.2 GB, ~21.5 tok/s, ~5 GB RAM) is faster/lighter but left fillers in; 8bit (9.0 GB, ~10.8 tok/s, ~8.75 GB) follows the copy-edit prompt cleanly → **ship 8bit default**, 4bit as a low-RAM option later. HF download `Progress` callback works but coarse — refine to byte-level for the SetupWizard bar (Phase 8).
- [x] Phase 1 — SwiftData data model (NamesData/NamesStore mirroring names_store.py: LWW, tombstones, 90-day prune, voiceEmbeddings union; PipelineFile @Model with the struct-attribute-trap workaround; AppSettings). 14 host-less unit tests. Tests run HOST-LESS (see arch memory: testmanagerd wedges hosted/UI runs).
- [x] Phase 2 — thin sync server: NWListener + Bonjour (`_skrift._tcp`) behind a SyncServer protocol; pure HTTP parser/router/handlers serving the contract — names meta/get/put, health, GET /api/files/, multipart POST /api/files/upload → PipelineFile (api/files.py trust logic). 25 unit tests.
- [ ] Phase 3 — transcription (FluidAudio)
- [ ] Phase 4 — enhancement (mlx-swift)
- [ ] Phase 5 — tags + name-linking + export
- [ ] Phase 6 — BatchManager auto-run
- [ ] Phase 7 — review UI
- [ ] Phase 8 — ingest + settings + setup
- [ ] Phase 9 — parity + retire Electron/Python
