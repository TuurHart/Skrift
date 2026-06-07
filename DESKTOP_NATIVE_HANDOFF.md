# Skrift Desktop — Native Rewrite HANDOFF

> Session ledger for the **desktop** native (SwiftUI/Swift) rewrite. Read this
> first, then `DESKTOP_NATIVE_REWRITE_PLAN.md` (the phased plan) and the root
> `CLAUDE.md` (documents the Electron/Python app being replaced). Memory
> auto-loads: `project_desktop_native_arch`, `feedback_autonomous_execution`,
> `feedback_vault_privacy`, `feedback_visual_ui_iteration`, `project_overhaul`.

- **Branch:** `desktop-native` · **Worktree:** `/Users/tiurihartog/Hackerman/Skrift-desktop`
- **New code:** `SkriftDesktop/` (xcodegen project). The Electron app (`frontend-new/`) + Python `backend/` are still in this worktree as the **source of truth** — port behavior from them; verify against them.
- **The goal:** collapse Electron(UI) + Python(backend) into ONE native macOS process — FluidAudio (ASR) + mlx-swift (Gemma enhancement) in-process, a thin Swift HTTP+Bonjour server as the phone's sync target. Kills Python, drops Chromium, far lower RAM, unifies with the iOS rewrite (`mobile-native`) on one stack + test harness.

---

## STATUS — Phases 0–8 GREEN; HF download bar + follow-ups F1–F6 DONE. Remaining: inline image thumbnails, marker→embed export, live phone↔Mac round-trip; Phase 9 (parity + retire Electron/Python).

Follow-ups this session: F1 phone-`title` extraction (unblocks mobile title), F2 two-Jacks per-occurrence resolver apply, F3 vault audio/image copy on export (VERIFIED on the test vault), F4 Apple-Notes `#` heading title, F5 names CRUD in Settings, F6 NSTextView body editor (live `[[link]]` styling + self-size).

Commits on `desktop-native` (newest first):
```
1a009e0 F6 — NSTextView body editor (live [[link]] styling + self-size)
632c0b7 F5 — names editing (CRUD) in Settings
ee59fe1 F3+F4 — vault audio/image copy on export (verified) + Apple-Notes title
3a1a73c F1+F2 — phone title extraction + per-occurrence resolver apply
ea43a5d HF model download progress bar
ce3a705 docs: Phase 8 done (ingest + Settings + SetupWizard)
95db821 Phase 8 — first-launch SetupWizard
2b14a06 Phase 8 — Settings panel
c217f69 Phase 8 — file/folder ingest + drag-drop
df6014a docs: Phase 7 wired + real end-to-end run verified
bb7cc95 -runfile harness + REAL end-to-end run verified (two-Jacks)
062ce55 wire review UI to the pipeline (process/export/resolve)
e105490 docs: mark Phase 7 review UI built (7a–7d)
7c81fbb Phase 7d — body styled [[links]] + karaoke (SwiftUI)
a5d014b Phase 7c — properties block + smart name resolver (SwiftUI)
35f7370 Phase 7b — note toolbar + contextual actions (SwiftUI)
c8edcd7 Phase 7a — review UI shell + sidebar (SwiftUI)
6d7689c fix NamesStore reading 0 people from legacy names.json (the "two Jacks" find)
c67d7ae docs: plan status
41b40c7 Phase 6 — BatchManager auto-run
7549c35 Phase 5c — compile to Obsidian markdown
188da49 Phase 5b — deterministic tags (NLTagger)
d6a336b Phase 5a — name-linking (non-blocking sanitise)
6624a89 Phase 4b — mlx-swift enhancement service (compile-verified)
6e3b8e1 Phase 4a — enhancement prompts + image-marker reinsert (pure)
8291041 Phase 3b — FluidAudio transcription adapter (real-ASR verified)
2123c01 Phase 3a — pure transcription post-processing (BPE merge + markers)
5cd837c Phase 2b — multipart upload -> SwiftData PipelineFile
98dad86 Phase 2a — thin sync server (HTTP + Bonjour) + names/health
e4d7d9c Phase 1 — SwiftData data model + names source-of-truth store
aa71b85 Phase 0 — toolchain + mlx-swift Gemma 4 go/no-go (GO native)
```
**53 host-less unit tests pass.** Both heavy engines proven on device (M4/ANE): FluidAudio transcribed a real `say` sample (conf 0.998); mlx-swift ran the real `copy_edit` prompt on the local 8bit Gemma in the Phase 0 spike.

### What each phase delivered
- **0** — xcodegen macOS app + FluidAudio + a 3-target test harness; the mlx-swift **go/no-go = GO native** (8bit Gemma copy-edit ran correctly, preserved EN/NL, removed fillers).
- **1** — SwiftData `PipelineFile` `@Model`; `NamesData`/`Person`/`NamesMerge` (LWW + voiceEmbeddings union, duplicated verbatim from the iOS app); desktop `NamesStore` (source-of-truth, mirrors `backend/utils/names_store.py`: smart bumps, tombstones, 90-day prune); `AppSettings`/`SettingsStore`; `ISO8601`, `AppPaths`.
- **2** — `Server/`: `LocalHTTPServer` (Network framework `NWListener`) advertised over **Bonjour** `_skrift._tcp` behind a `SyncServer` protocol; pure `HTTPParser`/`SyncHandlers` (host-tested). Serves: `GET /api/system/health`, `GET /api/names/meta`, `GET /api/names`, `PUT /api/names`, `GET /api/files/`, multipart `POST /api/files/upload` → `PipelineFile` (`UploadService`, api/files.py trust logic). `MultipartParser` is host-tested.
- **3** — `Pipeline/Transcription/`: pure `BPEMerge` (sub-word→word + phantom guard), `ImageMarkers` (insert), `WordTiming`/`ImageManifestEntry`. `Engines/TranscriptionService` (FluidAudio Parakeet-v3, app-only). Real ASR verified.
- **4** — `Pipeline/Enhancement/ImageMarkerReinsert` (strip→edit→reinsert, pure, tested); `Engines/EnhancementService` (mlx-swift-lm `MLXLLM` + `ChatSession`; copy-edit/title/summary on the RAW transcript). Exact prompts in `AppSettings.Prompts`. App compile-verified with MLX linked.
- **5** — `Sanitiser` (name-linking, port of sanitisation.py), `TagMatcher` (NLTagger lemmas nl+en + spoken #hashtags), `Compiler` (Obsidian markdown + YAML frontmatter, port of compile_file). All pure + host-tested.
- **6** — `BatchRunner` orchestrates transcribe→copy-edit/title/summary→tags→name-link→compile; engines behind `Transcribing`/`Enhancing` protocols so it host-tests with stubs.

---

## ARCHITECTURE / FILE LAYOUT (`SkriftDesktop/`)
```
App/SkriftDesktopApp.swift   @main; SharedStore (one ModelContainer); starts LocalHTTPServer
Models/   PipelineFile(@Model) NamesData ISO8601 AppPaths AppSettings FileDTO WordTiming
Pipeline/ (PURE, host-tested — NO FluidAudio/MLX here)
  Transcription/ BPEMerge ImageMarkers Transcribing(protocol+TranscriptionResult)
  Enhancement/   ImageMarkerReinsert Enhancing(protocol)
  Sanitisation/  NamesStore Sanitiser
  Tags/          TagMatcher
  Export/        Compiler
  Ingest/        UploadService
  BatchManager/  BatchRunner
Server/   HTTP SyncHandlers SyncServer Multipart
Engines/  (APP-ONLY — the heavy adapters; NOT in the test target)
  TranscriptionService (FluidAudio)   EnhancementService (mlx-swift)
SkriftDesktopTests/  (host-less logic tests)
SkriftDesktopUITests/ (XCUITest — see gotcha)
```
**The split is load-bearing:** pure deterministic logic lives in `Pipeline/`+`Models/`+`Server/` (compiled into the host-less test bundle → fast, MLX-free). FluidAudio/MLX live in `Engines/` (app target only), behind `Transcribing`/`Enhancing` protocols so `BatchRunner` etc. are tested with stubs.

---

## BUILD & TEST
```
cd SkriftDesktop && xcodegen generate                      # regenerate after adding files
# Fast logic tests (no app/MLX build) — USE THIS for the routine loop:
xcodebuild test -project SkriftDesktop/SkriftDesktop.xcodeproj -scheme UnitTests \
  -destination 'platform=macOS' -derivedDataPath SkriftDesktop/build
# Full build (compiles MLX into the app — slow first time):
xcodebuild build -project SkriftDesktop/SkriftDesktop.xcodeproj -scheme SkriftDesktop \
  -destination 'platform=macOS' -derivedDataPath SkriftDesktop/build -skipMacroValidation
```
Run long builds via Bash `run_in_background:true` + `dangerouslyDisableSandbox:true` (network for SwiftPM). Do NOT pipe `xcodebuild ... | tail` for pass/fail (the pipe masks the exit code).

### Gotchas (hard-won — don't relearn these)
1. **`testmanagerd` wedges.** macOS hosted/UI tests hang on "enabling automation mode / control session with daemon", and a hung run wedges the daemon so EVERY later `xcodebuild test` times out. Fix: `killall -9 testmanagerd` before test runs. → We run unit tests **HOST-LESS**: the test target compiles the pure sources directly (`sources: SkriftDesktopTests + Models + Pipeline + Server`); we do NOT `@testable import` the app or use a hosted test target.
2. **XCUITest is TCC-blocked** in this automated context (needs a one-time macOS Automation grant). Build + unit tests are green; the smoke UI test is written but needs the user to grant it once (or run from Xcode).
3. **SwiftData traps on Codable-struct `@Model` attributes** on read-back. `PipelineFile` stores steps as enum columns + `ambiguousNames`/`audioMetadata` as JSON `Data?` blobs behind computed accessors. Enum-with-String-rawValue attributes are fine.
4. **Only `xcodebuild` compiles MLX's Metal shaders** (`.metallib`); plain `swift build` cannot (→ "Failed to load the default metallib" at runtime). The MLXHuggingFace macros need `xcodebuild ... -skipMacroValidation`.
5. **Swift language mode = 5.9** (`SWIFT_VERSION: "5.9"`). The app's `static let` singletons (`ISO8601.formatter`, `NamesStore.shared`, …) are NOT Swift-6-concurrency-clean — a bump to Swift 6 needs `@unchecked Sendable`/actor isolation.

---

## LOCKED DECISIONS (see `project_desktop_native_arch` memory for detail)
- **mlx-swift Gemma = GO native** (no Python sidecar). `ml-explore/mlx-swift-lm` branch `main` (gemma4 registered), `MLXLLM` + `ChatSession`. Ship the **8bit** quant (`mlx-community/gemma-4-e4b-it-8bit`); 4bit was faster/lighter but under-removed fillers.
- **Models download from HuggingFace on first run** (FluidAudio Parakeet ~600MB; Gemma 8bit ~9GB) — NO shipped deps zip. SetupWizard gets a progress bar (Phase 8). Overrides CLAUDE.md's "local-only" for the native app. (A local 8bit copy exists at `~/Skrift_dependencies/models/mlx/gemma-4-e4b-it-8bit` — use it for fast LLM testing without the 9GB download.)
- **FluidAudio pin = branch `main`** (matches Shhhcribble at `~/Hackerman/Shhhcribble`, the proven macOS FluidAudio reference).
- **Phone↔Mac contract is byte-compatible** — the iOS app (`mobile-native`, now at its Phase ~6) round-trips upload/names against THIS server. Don't change the wire format (§4 of the plan).
- **Phase 7 UI = FULL SwiftUI rebuild (Option A).** We seriously evaluated Option B (reuse the React UI in a WKWebView + expand the server; the "Tauri" pattern — its real cost is a native bridge re-implementing `window.electronAPI`: file pickers, Cmd+F find, system IP). User chose A for true native feel; B stays a fallback (the pipeline is Swift either way).

---

## PHASE 7 — REVIEW UI (current task)
**MOCK FIRST, then SwiftUI** (the user has sharp visual taste + a standing mock-first rule). Build it as a **faithful port of the current overhauled Electron app** (dark, purple accent) **plus** the agreed improvements — NOT a fresh design.

- **Design spec = the current app + the v2 mock + the Opus critique.**
  - Real components: `frontend-new/src/features/NoteDisplay.tsx`, `Sidebar.tsx`, `src/components/NoteProperties.tsx`, `NoteToolbar.tsx`, `NoteActions.tsx`, `NoteBody.tsx`, `KaraokeText.tsx`, `ResolverStrip.tsx`. Tokens: `frontend-new/src/index.css` (DARK default — bg `rgb(15 17 23)`, surface `rgb(24 26 35)`, text `rgb(228 228 231)`, **accent `rgb(124 107 245)`**; `.light` theme too; step colors transcribe-blue/sanitise-violet/enhance-amber/export-green).
  - **Throwaway HTML mock at `mocks/index.html`** (served by a preview: `.claude/launch.json` has a `mock` config → `python3 -m http.server 7799 --directory mocks`; `preview_start` name `mock`, then `preview_screenshot`; after editing the file run `preview_eval` `location.reload()` then screenshot — it caches). v2 already applied the critique (centered ~680px body measure + primacy, grouped properties card, summary as left-rule aside, refined two-card title chooser, unified significance, quieter sidebar dot+text chips, etched 44px toolbar, calm resolver, solid image chip, softer karaoke).
  - **Opus design critique (apply when building):** body needs primacy + real text measure; group properties into one quiet card; bigger active title (20–22px); unify significance to one color; native materiality (NSVisualEffectView sidebar vibrancy, SF Symbols `gobackward.10`, varied radii by elevation, hover-only scrubber thumb); quieter sidebar; softer karaoke (brighten active word + dim rest, no box).
- **Build order (safe → risky):** theme tokens + 2-pane shell + Sidebar → toolbar + properties block → **body editor (visible `[[links]]`, WYSIWYG) + karaoke LAST** (Mac rich-text is the hard part). Verify each chunk with an XCUITest snapshot against the mock (needs the TCC grant — gotcha #2).
- **User UI feedback so far:** v2 sidebar felt "too massive/empty" → v3 should narrow it + reduce the gradient + fill space. Restore `+ Upload` as a real button (it was demoted). Note selection = clicking a sidebar row.

### OPEN DESIGN QUESTION raised by the "two Jacks" test (decide in Phase 7)
The user's test memo has **two different friends both called "Jack"** in one note. The old app's `ResolverStrip` groups ambiguous names **by alias** → one choice for "Jack" → it CANNOT map different occurrences to different people. But the `Sanitiser` records **each occurrence** as a separate `AmbiguousOccurrence` (offset + context) — verified: 4 separate "jack" occurrences. So the rebuild's resolver COULD offer **per-occurrence** disambiguation. Worth designing in (this is a real gap the old app had).

---

## FINDING REAL REBUILD GAPS AUTOMATICALLY (user's ask — propose/build next)
We just found a silent bug by hand (NamesStore read 0 people from the real legacy `names.json`). To catch the rest systematically:

**Differential ("golden") parity testing against the Python backend as the oracle.** The deterministic stages are perfect for this — feed IDENTICAL inputs into both Python and Swift and diff:
1. **Pure-logic parity** (highest value, CI-able): a corpus of `{transcript, names.json, tag-whitelist}` cases → run through Python `sanitisation.process_sanitisation` / `enhancement.match_tags_in_text`+`extract_spoken_hashtags` / `compile_file` AND the Swift `Sanitiser` / `TagMatcher` / `Compiler`, assert byte-identical `sanitised` / tags / markdown. Include edge cases: two-Jacks, possessives ('s), inside-link skip, #hashtags, EN/NL, image markers, the legacy/`short:"None"` name shapes.
2. **Real-config round-trips** (would have caught today's bug): load the REAL (legacy-shaped) `names.json` through BOTH `names_store.read_names()` and Swift `NamesStore`, assert same live-people count + same linking output. Generalize: round-trip every real on-disk artifact (names.json, user_settings.json, status.json) through both.
3. **Harness already seeded:** `pipecheck/` (repo root, throwaway, uncommitted) builds a tool that runs a real audio file through the native `TranscriptionService` + `Sanitiser` + `NamesStore` and prints transcript/sanitised/ambiguous. Extend it (or write a Python sibling) to emit machine-diffable JSON for both pipelines.
ASR + the LLM are non-deterministic → can't golden-diff exactly; pin the transcript as INPUT and golden-test the deterministic stages downstream; spot-check ASR/LLM manually.

---

## OWED / REMAINING
- **Phase 7 review UI — DONE** (commits 7a–7d): `SkriftDesktop/Features/` (Theme, Shell{RootView,AppModel,DemoSeed,Snapshot}, Sidebar{SidebarView,QueueDerivations}, Review{NoteDisplayView,NoteToolbar,NoteActions,AudioController,NoteProperties,ResolverStrip,FlowLayout,NoteBody,ReviewHelpers}). Faithful v5-mock port; snapshot-verified. **Verification method = the app's `-snapshot <path>` ImageRenderer PNG** (no screencapture/sim/TCC — `Snapshot.swift`; scrollable/interactive flags swap ScrollView→VStack and TextField/TextEditor→Text because ImageRenderer can't draw scroll contents or AppKit controls). **WIRED (commit 062ce55) + real run VERIFIED (bb7cc95):** `Features/Shell/ProcessingCoordinator.swift` runs `BatchRunner` over SwiftData files (Process all-pending / selection / single), publishes a live run bar, exports via `Compiler.compile` → `<title>.md` to the vault root, and applies per-alias resolver choices via `Sanitiser.applyResolvedNames`. Headless validation: `<App>.app/Contents/MacOS/SkriftDesktop -runfile <audio>` (`RunFile.swift`) — proven on `Hotel Du Vin.m4a` (two-Jacks): Parakeet transcript → Gemma copy-edit+title+summary → Sanitiser flagged 4 "Jack" ambiguous → 792-char markdown, 105s on M4, models from HF cache, no Python. **GOTCHA:** never block the main thread waiting on the engines — FluidAudio ASR posts completion callbacks to main; a semaphore-on-main DEADLOCKS at inference (loading is fine). **Remaining inside Phase 7:** per-occurrence resolver APPLY (distinct people per mention — UI ready, needs an offset-aware Sanitiser apply); Upload + Settings(gear) still stubs (Phase 8); body editor is a plain TextEditor MVP (NSTextView self-sizing + inline image markers + live [[link]] styling owed); karaoke proportional (real `word_timings` owed); export copies only the .md (vault audio/image copy owed); `DemoSeed` seeds the UI until ingest lands. Resolver design DECIDED: smart alias-default + per-occurrence expander (built in 7c).
- **Phase 8 ingest + Settings + SetupWizard — DONE** (commits c217f69 / 2b14a06 / 95db821): `Pipeline/Ingest/IngestService.swift` (host-tested, mirrors UploadService per-file folders; +Upload → NSOpenPanel + sidebar `.dropDestination`; audio→.audio, .md→.note, folder→.md enumerate); `Features/Settings/SettingsView.swift` (gear → sheet: vault/author/model/prompts/preprocessing sliders/names list, autosaves to SettingsStore); `Features/Settings/SetupWizardView.swift` (first-launch overlay, author + vault). `DemoSeed` gated behind `-demo` so the real app starts empty. Snapshot modes added: `-snapshot-settings`, `-snapshot-wizard`. **Owed:** live HF model **download progress bar** (wire swift-huggingface `Progress` through the engines' `ensureLoaded`, currently ignored); Apple-Notes frontmatter parsing (ingestNote stores raw markdown); names editing in Settings is read-only (CRUD owed); phone `title` upload-metadata extraction in UploadService (flagged by the mobile track — BatchRunner sets `titleSuggested` from the LLM unconditionally).
- **Real end-to-end app run** — wire `BatchRunner` → SwiftData saves + write `compiled.md` + `word_timings.json` sidecars + the Obsidian vault export (copy audio/images to the configured folders). Then drop an audio file in the app and get a real note.
- **Phase 8** — ingest (drag/folder/phone) + Settings + SetupWizard, incl. the HF model **download progress bar** (`swift-huggingface` `Progress` callback; current `loadContainer` ignores it — wire it through). Vault tag-whitelist scan (deferred from Phase 5).
- **Phase 9** — parity sweep + retire Electron/Python.
- **Live phone↔Mac round-trip** once the `mobile-native` app's upload/names sync lands.
- **Data-quality** (user's real names.json): `[[Sebastiaan Paap]]` short=`"None"` (literal), Jack shorts `jank`/`timmons`, `Jank` alias — surface/clean in the names UI; consider treating `"None"`/empty short defensively.

---

## THROWAWAY / SCRATCH (safe to delete; NOT committed)
- `mocks/index.html` + `.claude/launch.json` — the design mock + its preview server.
- `pipecheck/` — the real-audio parity harness (reuses `../SkriftDesktop` sources via relative paths; Swift 5.9; FluidAudio). Useful for the parity work above.
- (Already deleted: `mlx-spike/`, `asr-check/`.)

## SOURCE OF TRUTH / PRIVACY
- Port from `backend/` (Python pipeline + contract) and `frontend-new/src/` (React UI + tokens). Root `CLAUDE.md` documents the whole pipeline. `API_REFERENCE.md` / `BACKEND_MAP.md` exist too.
- **PRIVACY (firm):** never point AI/agents at the user's Obsidian vault contents. The app's own Swift code scanning the vault is fine; an agent reading it is not. Test with small samples the user provides (e.g. they gave `~/Hackerman/Skrift/test images - delete this folder/Hotel Du Vin.m4a`). `names.json` is app config (ok to read for debugging). Don't screenshot the live Electron app at a real note.
