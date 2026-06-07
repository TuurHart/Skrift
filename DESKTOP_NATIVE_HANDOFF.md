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

## STATUS — Phases 0–8 GREEN; HF download bar + follow-ups F1–F6 + image-embed export DONE. The native app is feature-complete for the core loop (ingest → process → review → export). Remaining: the prioritized backlog below + Phase 9 (parity + retire Electron/Python).

Follow-ups this session: F1 phone-`title` extraction (unblocks mobile title), F2 two-Jacks per-occurrence resolver apply, F3 vault audio/image copy on export (VERIFIED on the test vault `~/Hackerman/Obsidian_LLM_Test_Vault`), F4 Apple-Notes `#` heading title, F5 names CRUD in Settings, F6 NSTextView body editor (live `[[link]]` styling + self-size), image-embed export (`[[img_NNN]]` → `![[Title_NNN.ext]]` + image copy).

➡ **Start the next session from the "## NEXT SESSION" block below.**

### SESSION 2026-06-07 — live pilot + ALL of backlog A + a pilot-found bug (commits `b19d279`…`2ac2939`)
**Live-driving harness built & WORKING** (`pilot/axdrive.swift`, uncommitted scratch): a self-compiled Swift helper that reads the running app's **Accessibility tree** (element role/label/id/value + exact center coords in logical points) and posts **CGEvent** mouse/clipboard input. TCC grant goes on **`/Applications/Claude.app`** (the shell's responsible process); a self-built helper inherits it (no signing). **Gotchas:** synthetic *mouse* works; synthetic *keyboard/text* does NOT reach NSTextView (so I can't drive body/title/tag/Settings text-entry live — use XCUITest or real keys); the first click only *activates* a background window, so `activate <pid>` first + dwell between mouse-down/up. `-stubEnhancement`/`-seedTranscript` launch hook (committed) swaps in canned engines so Process→Ready is instant (no 9 GB model).
**Pilot findings:** ✅ resolver/two-Jacks works end-to-end (per-occurrence Apply links names, strip clears); ✅ Process→Ready works; ⚠️ **fixed** a stranded-`.processing` note (no re-process path) → `RunReconciler` on launch; ℹ️ `BodyTextView.applyStyling` rebuilds the whole textStorage every keystroke (fragile vs IME/undo — not yet hardened); ℹ️ `-demo` only seeds an *empty* store (`seedIfEmpty`) so stale demo data persists across launches (wipe `~/Library/Application Support/default.store*` for a fresh seed).
**Backlog A — ALL DONE & committed, 74 host-less tests green:** A1 model-unload idle timer (60 s after last run; was dead code); A2 persist `word_timings` → real karaoke (cadence-driven, was discarded); A3 marshal upload/list SwiftData onto the main actor (was on the Bonjour queue → corruption risk; verified live via curl upload, no crash); A4 native AVFoundation high-pass+normalize → 16 kHz mono `processed.wav` before ASR, **noise-reduction slider dropped** (no native afftdn — user decision; DSP verified standalone on a real memo); A5 upload size cap + 413 (was unbounded RAM); A6 `/health` reports real `isModelReadySync` (was hardcoded true; lazy-load caveat noted for the phone); A7 golden parity vs the Python sanitiser (6 edge cases byte-identical). Plus the stuck-`Enhancing` fix (#9, verified live).
**B (landed this session too):** B1 in-app image thumbnails — `[[img_NNN]]` renders as an inline `NSTextAttachment` thumbnail in the body editor (`ImageMarkerAttachment` carries the number so the literal marker is reconstructed for export; verified live: body grew 60→143 pt, marker → attachment); **also fixed a latent stale-`parent` bug** — the BodyTextView Coordinator's write-back binding + image resolver pointed at the *previously-selected* note after switching (now refreshed in `updateNSView`); styling switched to in-place (no per-keystroke storage rebuild). B3 vault tag-whitelist scan (`VaultTagScanner`, app FileManager frontmatter+#tag scan, off-main). Both committed + tested (`5884405`, `bc02a38`). **Still owed:** B2 Apple-Notes attachments/HEIC→JPG; C (product — ask the user; Backlink Weaver is the cheap high-value one); Phase 9. The styled-Text read path still shows `[[img_NNN]]` as text (the editor is the primary body view). A7 parity could extend to TagMatcher/Compiler.

### SESSION 2026-06-07 (cont.) — trusted-mobile process+export VALIDATED (mobile-track relay) + unique Bonjour name
- **Process-a-synced-phone-memo VALIDATED** (`10548fe`): the Mac's half now proven on REAL mobile input, not just raw audio. Added `-runfile -transcript <file>` (pre-loads a transcript + marks transcribe done → BatchRunner skips ASR = the trusted-phone path). Ran a real synced memo (`memo_203…`, `source=mobile`, conf 0.96, with `[[img_001]]`): **ASR skipped** (transcript preserved byte-for-byte, 20s, no ~30s ASR), Gemma title+summary+filler-removal copy-edit, **`[[img_001]]` preserved → exported as Obsidian `![[…]]` embed**, audio+photo copied to the test vault. A names-bearing transcript confirmed name-linking on the trust path: `Tuur`→`[[Tiuri Hartog]]`, `Rox`→`[[Roksana Gurova]]`, ambiguous **`Jack` left plain + flagged** (two Jacks). So name-link → enhance → Obsidian export all work on a trusted phone transcript. (Positive name-link was already proven on raw audio via two-Jacks; the BatchRunner Sanitiser call is source-agnostic.)
- **⚠ CLI BUILD GOTCHA:** the MLX-linked `SkriftDesktop` scheme needs **`-skipMacroValidation`** (`mlx-swift-lm`'s `MLXHuggingFaceMacros` macro-trust gate fails CLI builds — invisible in Xcode). The `UnitTests` scheme is MLX-free and unaffected.
- **⚠ Two-instance store hazard:** `-runfile` still creates `SharedStore.container` + starts the server + runs `RunReconciler` (which WRITES SwiftData) at launch. **Quit the running app before a headless run** or two `ModelContainer`s race on `~/Library/Application Support/default.store`.
- **Unique Bonjour name** (`3fd4848`): `LocalHTTPServer` defaults the service name to this Mac's computer name (`Host.current().localizedName`) so a room of Macs is distinguishable on the phone — pairs with mobile `a7c24ca` (per-row IP + spinner cap). Display-only; contract unchanged.

Commits on `desktop-native` (newest first):
```
10548fe -runfile -transcript trusted-mobile validation mode
3fd4848 advertise unique Bonjour name for multi-Mac disambiguation
0c8e508 image embeds — [[img_NNN]] → Obsidian ![[…]] on export
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

## NEXT SESSION — prioritized backlog + how to start

Phase 7 UI + pipeline wiring + Phase 8 + image-embed export are DONE & committed (newest = `0c8e508`). Verify: `git -C /Users/tiurihartog/Hackerman/Skrift-desktop log --oneline -20`. Verify UI headlessly via `-snapshot` / `-snapshot-settings` / `-snapshot-wizard` / `-snapshot-run`; verify the real pipeline+export via `-runfile <audio> [-vault <path>]` (method = memory `native-ui-verification`; screencapture/sim are blocked). Test vault `~/Hackerman/Obsidian_LLM_Test_Vault` — OK to export to; never read OTHER vault contents.

### A. Correctness / reliability — ✅ ALL DONE 2026-06-07 (see SESSION log above; A1–A7 + the stuck-processing fix all committed + tested)
1. **Models never unload (~9 GB pinned all session).** `TranscriptionService.unload()` + `EnhancementService.unload()` have NO call sites. Add an idle timer in `ProcessingCoordinator` that unloads both ~30–60 s after the last run (the Python app did this). HIGH — jetsam risk on 16 GB Macs.
2. **Karaoke is fake.** `TranscriptionService` builds `wordTimings` but `BatchRunner.run` keeps only `result.text` and never persists them → `NoteBody.karaoke` is always proportional. Persist timings (a `word_timings.json` sidecar next to `original.*`, or a PipelineFile field) and feed `KaraokeText`. HIGH value, cheap.
3. **SwiftData written off the Bonjour socket queue** (`SkriftDesktopApp` upload handler makes a `ModelContext` on the Network-framework queue while the UI uses `mainContext`) → concurrent-write corruption risk. Marshal `UploadService.ingest` onto `@MainActor`/a serial actor. (On the phone's exact path.)
4. **Audio-preprocessing sliders are inert.** `AppSettings.noiseReductionDB/highpassFreqHz` + the Settings sliders do nothing; FluidAudio gets the raw m4a. Apply an AVAudioEngine high-pass + normalize (write `processed.wav`, feed that), or remove the sliders.
5. **Upload buffered fully in RAM, no size cap** (`HTTPParser.parse` needs the whole Content-Length body). Stream multipart to disk past a threshold + reject oversized.
6. **Health endpoint hardcodes `available = true`** (`SyncHandlers`) → should report `TranscriptionService.shared.isModelReady` (the phone trusts it). (Phone path.)
7. **Parity golden tests.** Stages are stub-tested but nothing pins Swift vs the Python backend on fixtures. Check in a few golden `{transcript,names,whitelist} → {sanitised,tags,markdown}` cases (use `pipecheck/` + Python siblings) and assert byte-equality — guards the "same results, no Python" promise. (Note: F2's resolver apply is ORDER-based on the current body, so the audit's "offset alignment" worry is moot.)

### B. Remaining owed UI/feature bits
- ✅ **In-app inline image thumbnails — DONE 2026-06-07** (`bc02a38`): NSTextAttachment in `BodyTextView`. (Still owed: the snapshot/karaoke `BodyText.styled` read path shows `[[img_NNN]]` as text — the editor is the primary view.)
- **Apple-Notes attachment rename + HEIC→JPG** (`IngestService.ingestNote` stores raw md; `apple_notes_importer.py` renames `Attachments/` + sips-converts HEIC). ← only remaining B item.
- ✅ **Vault tag-whitelist scan — DONE 2026-06-07** (`5884405`): `VaultTagScanner` (app FileManager frontmatter + `#tag` scan, off-main), wired into the coordinator.

### ★ PRODUCT NORTH STAR — canonical source: `/Users/tiurihartog/Hackerman/Skrift/backlog.md`
**READ that backlog first** (main worktree; it predates this session — the "North star" + deferred items live there). In short: Skrift is **not** an Obsidian replacement — it's the **capture + processing front-end that feeds Obsidian** (memo → clean, linked, tagged markdown; Obsidian keeps graph/backlinks/plugins/search). The north star: **"see how my thinking evolved over time"** — when you add a note, surface related notes across the years on a timeline ("a similar thought in 2019, it shifted in 2021, here's now"). Backbone is reachable now + offline: **local-embedding semantic search across the vault + retrieve/rank related notes + a timeline UI** (mostly engineering, not model-limited); the LLM *narrating* the evolution is deferred (same quality ceiling as the stale-summary problem). The agent's Ask-Your-Memos/People-Timeline are adjacent but the backlog is the real spec. Other backlog items there: watched-folder ingest, summary-prompt quality (reads stale/not in my voice), tag matchable-subset + lemma expansion, git housekeeping. Design cautions the user raised: (a) Backlink Weaver must avoid over-linking common words (gate by length/distinctiveness/toggle); (b) do NOT feed sensor context into the LLM copy-edit (small local model hallucinates) — keep context deterministic (frontmatter / a "Context:" line), at most a tightly-constrained title hint.

### Live-app PILOT + trace pass — STARTED (commit d041a50)
The audit was one static pass; piloting the running app catches interaction bugs snapshots/`-runfile` can't. **Done:** `SkriftDesktopUITests/ReviewWalkthroughUITests.swift` + accessibility ids (`sidebar.process`, `sidebar.settings`, `settings.root`, `settings.done`); `-demo` launch arg seeds notes + skips the wizard; `build-for-testing` GREEN. **Can't run headless here** — XCUITest is TCC-blocked (gotcha #2); run it from Xcode (or a machine with the one-time Automation grant): `xcodebuild test -scheme SkriftDesktop -destination 'platform=macOS'` after `killall -9 testmanagerd`. **Owed:** extend the walkthrough to tap **Process→Ready** + the **resolver** + body editing — needs the engines stubbed for UI tests (inject `Transcribing`/`Enhancing` stubs behind a `-stubEnhancement`/`-seedTranscript` launch hook so taps don't run real ASR/LLM; `ProcessingCoordinator` currently hard-codes `TranscriptionService.shared`/`EnhancementService.shared`). Alt path if you'd rather: have the user grant Accessibility + Screen Recording → drive via `osascript`/`cliclick` + `screencapture`.

### C. Product ideas (fresh-eyes brainstorm — ask the user which to pursue)
- **Backlink Weaver** (high impact / low effort): on export, auto-`[[link]]` any vault note title (places/projects), not just people — generalize `Sanitiser.process` to take a vault-title whitelist like `TagMatcher`. Makes memos a connected graph.
- **Context-aware enhancement**: the phone's place/weather/people/time is only stamped into frontmatter — feed a one-line context string into the Gemma title/summary prompts in `BatchRunner`. Free signal already captured.
- **People Timeline**: per-person view (every note mentioning `[[Jack]]` + date/place/summary) from the graph you already write.
- **Smart Suggest New People**: NLTagger PersonalName pass minus existing aliases → "Add [[Sam]]?" chips at review (the names graph only grows by hand today).
- **Ask-Your-Memos**: local RAG over exported notes (offline, reuses the loaded Gemma). **Weekly Digest**: scheduled person/place/significance summary. (Photo-caption VLM was deliberately dropped.)

### D. The mobile track waits on this app
`mobile-native`'s live upload/names round-trip is blocked on a RUNNING desktop server (`_skrift._tcp`, the in-app `LocalHTTPServer` starts on launch; contract intact incl. F1's `title`). To unblock: run the desktop app, confirm the server is up, then the phone pairs over Bonjour and round-trips `POST /api/files/upload` + `GET/PUT /api/names`. Do A.3 + A.6 first (phone's exact path).

### NEXT-CHAT PROMPT (copy-paste)
> Continue the Skrift DESKTOP native rewrite. Worktree `/Users/tiurihartog/Hackerman/Skrift-desktop`, branch `desktop-native` — do NOT switch branches (other worktrees share the repo; `git worktree list` to confirm). READ FIRST: `DESKTOP_NATIVE_HANDOFF.md` "## NEXT SESSION" → the rest of the handoff → root `CLAUDE.md`. Memory auto-loads — `native-ui-verification` is essential: verify UI via the app's headless `-snapshot*` ImageRenderer PNGs (screencapture/System-Events/iOS-sim are blocked); verify the real pipeline via `-runfile <audio> [-vault <path>]`. STATE: Phases 0–8 + follow-ups F1–F6 + image-embed export DONE & committed (newest `0c8e508`); 64 host-less tests green; tree clean (`mocks/` + `pipecheck/` are intentional scratch — don't commit). Work the "## NEXT SESSION" backlog in order: **A (correctness: model-unload idle timer, real word_timings→karaoke, SwiftData cross-queue marshal, inert audio sliders, upload streaming/cap, health `isModelReady`, parity golden tests), then B (in-app image thumbnails, Apple-Notes attachments, vault tag-whitelist), then C (product ideas — ask the user which).** Verify every change (host-less `UnitTests` scheme — `killall -9 testmanagerd` first; full app build via background Bash + `dangerouslyDisableSandbox`, don't pipe xcodebuild to tail; `xcodegen generate` after adding files; Swift 5.9) and commit per item. PRIVACY: the app may read/write the test vault `~/Hackerman/Obsidian_LLM_Test_Vault`; never point an agent at vault contents.

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
