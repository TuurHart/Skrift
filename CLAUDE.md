# CLAUDE.md

Guidance for Claude Code working in this repo.

## What Skrift is

Skrift transcribes iPhone voice recordings (+ Apple Notes) to text, sanitises
(name-linking), enhances (local MLX Gemma), and exports to Obsidian-compatible
Markdown — fully offline transcription. **Two native SwiftUI apps** that sync over
**CloudKit** (the user's private iCloud database) and share a names database
(bidirectional last-write-wins). Bonjour/HTTP LAN sync is fully retired.

- **`Skrift_Native/SkriftMobile/`** — native **iOS** app. Records voice memos with
  contextual metadata + photos, transcribes on-device (FluidAudio / Parakeet on the
  Apple Neural Engine), syncs across the user's devices (and the Mac) over CloudKit.
  Live caption, Live Activity, Control Center + Lock/Home widgets, App Intents,
  share-to-import audio/video, an **audiobook player with quote-capture** (Bound-style
  library; captures become memos with the quote audio + the user's voice ramble).
- **`Skrift_Native/SkriftDesktop/`** — native **macOS** app. ONE process: FluidAudio
  (ASR) + mlx-swift (Gemma enhancement) in-process, a **CloudKit client** of the
  shared `Memo` store (reads synced raw memos, writes its polish back as
  `MemoEnhancement`). Transcribe → enhance → name-link → compile → export to
  Obsidian. **No Python, no Electron, no Bonjour server.**

The previous apps are preserved **intact** under `archive/` for reference
(`archive/Mobile/` = old React Native iOS, `archive/frontend-new/` = old Electron,
`archive/backend/` = old Python; the full pre-convergence project doc is
`archive/CLAUDE-electron-python.md`). They can still be run with path adjustments.

## Hard rules

- **PRIVACY:** never point AI/agents at the user's Obsidian vault contents. Only the
  app's own code scans the vault; test with a small sample the user provides.
- **CloudKit sync contract is the spine:** memos mirror to the user's private CloudKit
  DB (SwiftData `Memo` + `MemoAsset` blobs); the Mac ingests a synced memo
  (`MemoCloudIngest`) and writes its polish back as `MemoEnhancement` (LWW by
  `enhancedAt`). The phone always carries the **RAW transcript** (+ confidence /
  userEdited / markers / metadata / optional `title`), **never `sanitised`** — the Mac
  links names. Trust = `transcriptUserEdited || transcriptConfidence ≥ 0.7`. Names sync
  over CloudKit (`NamesRecord` carrier ↔ local `names.json`) via `NamesMerge` LWW
  (**union** voiceEmbeddings); custom vocab likewise. Keep `names.json` byte-compatible
  across both apps.
- **Keep it simple. Commit per chunk. Verify each chunk** (xcodebuild build+test on
  the iPhone 17 sim for mobile; `-skipMacroValidation` full scheme for desktop). For
  new UI, mock first.

## Build / run

Both are **xcodegen** projects; the `.xcodeproj` + `build/` are gitignored —
regenerate after pulling or moving.

**iOS — `Skrift_Native/SkriftMobile/`:**
```
cd Skrift_Native/SkriftMobile && xcodegen generate
xcodebuild test -scheme SkriftMobile -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build
# device (UDID 00008110-001208C902EA201E, unlocked):
xcodebuild build -scheme SkriftMobile -destination 'platform=iOS,id=<UDID>' -derivedDataPath build-device \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=9W82X49JZS CODE_SIGN_STYLE=Automatic
xcrun devicectl device install app --device <UDID> build-device/Build/Products/Debug-iphoneos/SkriftMobile.app
```
Sim flake ("Lost connection to testmanagerd" / preflight) → `xcrun simctl shutdown all; xcrun simctl erase "iPhone 17"`, re-run.

**macOS — `Skrift_Native/SkriftDesktop/`:**
```
cd Skrift_Native/SkriftDesktop && xcodegen generate
xcodebuild test  -scheme UnitTests   -destination 'platform=macOS'                          # fast, MLX-free
xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation   # full app (MLX); flag is REQUIRED on CLI
# headless pipeline run (DEBUG): <app binary> -runfile <audio> [-transcript <txt>] [-vault <path>]
# quit the running app first — a 2nd instance races the shared SwiftData store.
```

## Dev vs prod — DATA SAFETY (read before building/installing)

Two build configs, fully isolated, so iterating never risks real data:
- **Debug = "Skrift Dev"** — `com.skrift.{mobile,desktop}.dev`, **inverted app icon**, its OWN OS data
  container; macOS dev defaults to the TEST vault (`~/Hackerman/Obsidian_LLM_Test_Vault`).
- **Release = "Skrift"** (prod) — the real data + real Obsidian vault. Prod desktop lives at
  `/Applications/Skrift.app`.

Rules:
- **Merging code to a branch changes NOTHING on any installed app.** An app only changes when someone
  **builds + installs** it.
- **To TEST, build + install the DEV (Debug) build** — it physically can't touch prod memos/names/vault
  and runs alongside prod. (Tell them apart by name "Skrift Dev" + the inverted icon.)
- **Never rebuild/reinstall PROD while it's in use** (e.g. mid-processing). **Promote to prod
  deliberately, when prod is idle**: Release build + install, and push `native`→`main`.
- **Device debugging:** DEV builds write a pullable trace to the app container —
  `Documents/devlog.txt` (`DevLog.log(...)`, ring-buffered, DEBUG-only): recording lifecycle,
  every audio-route event + formats, tap installs/refusals. Pull it with
  `xcrun devicectl device copy from --domain-type appDataContainer --domain-identifier
  com.skrift.mobile.dev --source "Documents/devlog.txt" ...`. **Hardware-flavored bugs (audio
  routes/BT/sensors): instrument + diagnose from this trace FIRST — the sim gate cannot falsify
  hardware behavior, and fixes belong to the orchestrator directly, not lanes** (learned the
  hard way: the AirPods P0 took 4 rounds — crash → policy → cache → wrong API property).

## Ledgers (read to resume)

- **`FEATURES.md`** — cross-app feature source of truth (every feature × {mobile, desktop} ×
  file × status). **Update it in the same commit whenever you add or change a feature.**
- **`backlog.md`** — THE working ledger: feature decisions, device-test findings/verdicts, fix
  status, "CONTINUE HERE" resume points. Triage every brain-dump/feedback batch into it and tick
  items off **in the same session they land** (user hard requirement).
- **`Skrift_Native/SkriftDesktop/mocks/*.html`** — signed-off design specs (mock-first is locked
  process for new UI): v5 (desktop shell), significance-circles, name-unlink, name-a-speaker,
  capture-items, audiobook-capture, text-capture, **audiobook-player-redesign** (text-forward A+D
  hybrid player, signed off + built 2026-06-13), **audiobook-player-reading-mode** (e-reader "reading
  mode" + tab-bar IA redesign, signed off 2026-06-19 — not yet built), **journal-desktop** (Journal on
  the Mac + iPad v2 — map mode behind Places, slim in-flight row, body-parity panels; signed off
  2026-07-11 — not yet built; build board = backlog "CONTINUE HERE — desktop-parity"),
  **related-panel** (Mac Connections side-panel — ONE list + Date⇄Closest pill, P1 importance
  decimals, closeness = hover-% tooltip, in-panel consent gate, collapsible w/ count badge; signed
  off 2026-07-16 — build board = backlog "🕸️ CONTINUE HERE"). A mock the
  user approved IS the spec — build to it.
- **`.claude/skills/pull-phone-feedback/`** — the feedback loop: user records test findings as
  memos in Skrift Dev on the phone → pull over USB (devicectl app-container copy) → parse →
  MANDATORY second-agent verify → triage into backlog.md. Crash logs via `idevicecrashreport`.
- **`STANDALONE_PLAN.md`** — ⭐ **CURRENT DIRECTION (2026-06-15):** ship SkriftMobile to the App Store
  as a standalone audiobook+notetaking app (no Mac required). Locked: **$0.69, no IAP**; full-vision v1;
  **CloudKit** internal sync (not iCloud-Drive); one-way Obsidian publish; on-device Polish as a **gated
  spike**; Mac+Obsidian = optional sinks over one source of truth. Phases 0–11 + portability map +
  device/LLM matrix. Branch **`standalone`**. Track in `backlog.md` "⭐ Standalone App Store push".
- **`roadmap/`** — ⭐ the roadmap **data** (new chats: start at **`roadmap/README.md`**).
  **`roadmap/roadmap.yaml`** is the single source of truth for the plan: the node graph (spine
  `nodes`, `detours`, the 5 `history` eras with dated `shipped` logs, `ideas`). Layout auto-computes
  from each node's `lane` (vertical) + `order` (horizontal) — to move a node, change those two numbers.
  It's rendered by the **Tiuri Command Center hub**, a *separate* project in its own repo
  (`OsamaBinBallZak/Tiuri-Command-Center`); this repo only holds the data. **UPDATE CONTRACT (so it
  can't drift):** when a phase/detour/idea changes, edit `roadmap.yaml` AND the markdown ledger it
  mirrors (`SKRIFT_SOURCE_OF_TRUTH.md` §4, `STANDALONE_PLAN.md`, `backlog.md`) in the **same pass**, and
  bump `updated:`. **History note (2026-06-29):** the old in-repo viz `roadmap/ROADMAP.html` (a
  self-contained metro-tree with its *own hardcoded* plan copy) was **deleted** — it was a second source
  that drifted from `roadmap.yaml`. Recover it from git history if ever needed; the A/B/C/D
  design-exploration mocks remain in `roadmap/mocks/`.
- **`SKRIFT_SOURCE_OF_TRUTH.md`** — ⭐ the canonical record: timeline, current state, decisions, wire contracts, resolved contradictions. **Start here** — it indexes the deep docs by `file:line`.
- **`archive/handoffs/`** — the native-rewrite deep tier (the SSOT's cited sources, moved out of root 2026-07-01): `MOBILE_NATIVE_HANDOFF.md` + `…_REWRITE_PLAN.md` (iOS), `DESKTOP_NATIVE_HANDOFF.md` + `…_REWRITE_PLAN.md` (macOS), `CONVERSATION_MODE_HANDOFF.md` (diarization + voice identity — Sortformer + wespeaker-cosine), `MAC_CLOUDKIT_PLAN.md`, `OBSIDIAN_EXPORT_ALTERNATIVES.md`, `WALKTHROUGH_BUGS.md`. Read on demand via the SSOT's citations.
- Memory: `project_native_convergence`, `project_vocab_booster`, `feedback_vault_privacy`, `feedback_autonomous_execution`, `feedback_native_ui_process`, `feedback_native_ui_verification`.

## Docs: keep them lean

- Root holds only the live set (see README's doc map). Write rules, not essays — cut any
  sentence that doesn't change what the reader does; state each rule once.
- Superseded docs → `archive/` (session handoffs/plans → `archive/handoffs/`), never delete.
  Fold a new handoff's durable facts into `SKRIFT_SOURCE_OF_TRUTH.md`, then archive it.
- The SSOT is a citation index — keep its `Filename.md:line` anchors resolvable when moving cited docs.

## Branch

**Work on `main`.** As of **2026-06-14**, `main` IS the trunk: the `native` branch — itself
the 2026-06-07 convergence of `mobile-native` + `desktop-native` — was fast-forwarded into
`main` (clean, 215 commits) and pushed, so we now live on `main`. Both apps + full history on
one branch so cross-app features land atomically. The old `native` branch still exists as a
safety net but is no longer the working branch (delete it once comfortable). Older pre-converge
branches (`mobile-native`, `desktop-native`, `feature/photo-capture`, …) are stale leftovers.

## Open cross-app work

- **Audiobooks — ✅ BIG 2026-06-13 batch (see `backlog.md` ⭐ CONTINUE HERE + FEATURES.md):**
  (1) **Custom vocab fixed** both apps — pre-warm booster + aliases + trust guard; device-confirmed
  working ([[project_vocab_booster]]). (2) **Text-capture WAVE 2** (mobile) — whole-book pre-transcribe:
  `BookTranscript` sidecar + `ChunkFusion` + resumable `BookTranscriptionJob` + Transcribe-book button +
  instant sidecar capture. (3) **Player redesign — text-forward A+D hybrid** (mock
  `mocks/audiobook-player-redesign.html`): Spotify-style read-along, bookmarks, Chapters/Bookmarks
  sheet, library long-press → transcribe. **Chunk-extraction gotcha (durable):** per-chunk
  `AVAssetExportSession` on compressed audio drifts time late (grows with seek depth) — use
  sample-accurate `AVAudioFile` frame reads for any extraction whose word-times must align to the
  source (proven via the desktop `-chunksim`/`-readalongcheck` harness). Read-along device-eyeball +
  `lead` tune still owed.
- **Capture items — ✅ BUILT 2026-06-12** (two-lane batch + orchestrator integration;
  awaiting device verify). Contract = `Skrift_Native/CAPTURE_CONTRACT.md` (C3); design
  = `mocks/capture-items.html`; capability map = FEATURES.md "Capture items".
  **Signing lesson:** `xcodebuild -allowProvisioningUpdates` registers bundle IDs but
  CANNOT add a capability (App Groups) to them — that takes a one-time visit to
  Xcode's Signing & Capabilities per target (done for the dev IDs 2026-06-12; the
  Release IDs need the same once, at prod promotion). Also: a `$(VAR)` inside an
  `.entitlements` file breaks CLI profile matching — keep entitlement values LITERAL,
  per-config files selected via `CODE_SIGN_ENTITLEMENTS`.
- **Capture-screen redesign (audiobooks)** — DESIGN PAUSED by the user: no more code
  iterations on `CaptureMomentView` until an interaction design/mock session happens.
- **Unified source taxonomy** — voice memo / URL / PDF / video / audiobook quote /
  Apple Note: consistent glyphs + labels across both apps (folds into capture items).

## How this project is run (Tiuri Command Center)

This repo is a project in my Tiuri Command Center — a hub where I manage all my side projects.

- Each project has one `roadmap/roadmap.yaml`: the single source of truth for the plan —
  what's done, what I'm on now, what's next. The Command Center reads it from the repo and
  renders it as a visual map I can see and talk to.
- I plan by talking to Huginn (the hub agent), who edits roadmap.yaml. You (Claude Code) are
  the builder — you do the work in this repo. The roadmap is the brief between us.
- The habit every session: when you finish a chunk of work, update roadmap.yaml in the SAME
  change — flip that node to `done`, move the one `now` node to what's next. Live state, not a notepad.
- No `roadmap.yaml` yet? Don't create one — Huginn seeds it. Just build; this habit starts once a plan exists.

Editing rules:
- A node is a chunk of work with a done-state. `status: done|now|inprogress|planned|deferred`, exactly one `now`.
- `id` is permanent — edit the title, not the id.
- Layout = `lane` (kind of work) + `order` (left→right) — set those, never position by pixel; a fractional lane is fine to draw a convergence.
- The past is just nodes to the left: `done` at negative `order`.
- Keep it lean — few nodes, short notes.
