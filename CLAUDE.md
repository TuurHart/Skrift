# CLAUDE.md

Guidance for Claude Code working in this repo.

## What Skrift is

Skrift transcribes iPhone voice recordings (+ Apple Notes) to text, sanitises
(name-linking), enhances (local MLX Gemma), and exports to Obsidian-compatible
Markdown — fully offline. **Two native SwiftUI apps** that sync over the local
network (Bonjour + HTTP) and share a names database (bidirectional last-write-wins):

- **`Skrift_Native/SkriftMobile/`** — native **iOS** app. Records voice memos with
  contextual metadata + photos, transcribes on-device (FluidAudio / Parakeet on the
  Apple Neural Engine), syncs to the Mac. Live caption, Live Activity, Control
  Center + Lock/Home widgets, App Intents, share-to-import audio/video, an
  **audiobook player with quote-capture** (Bound-style library; captures become
  memos with the quote audio + the user's voice ramble).
- **`Skrift_Native/SkriftDesktop/`** — native **macOS** app. ONE process: FluidAudio
  (ASR) + mlx-swift (Gemma enhancement) in-process + a thin Bonjour/HTTP server as
  the phone's sync target. Transcribe → enhance → name-link → compile → export to
  Obsidian. **No Python, no Electron.**

The previous apps are preserved **intact** under `archive/` for reference
(`archive/Mobile/` = old React Native iOS, `archive/frontend-new/` = old Electron,
`archive/backend/` = old Python; the full pre-convergence project doc is
`archive/CLAUDE-electron-python.md`). They can still be run with path adjustments.

## Hard rules

- **PRIVACY:** never point AI/agents at the user's Obsidian vault contents. Only the
  app's own code scans the vault; test with a small sample the user provides.
- **Mobile↔Mac contract is the spine** (handoffs §4): multipart `POST
  /api/files/upload`; the phone sends the **RAW transcript** (+ confidence /
  userEdited / markers / metadata / optional `title`), **never `sanitised`** — the
  Mac links names. Trust = `transcriptUserEdited || transcriptConfidence ≥ 0.7`.
  Names sync: `GET /api/names/meta` → `GET` → LWW merge (**union** voiceEmbeddings)
  → `PUT`. Keep it byte-compatible across both apps.
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
  capture-items, audiobook-capture. A mock the user approved IS the spec — build to it.
- **`.claude/skills/pull-phone-feedback/`** — the feedback loop: user records test findings as
  memos in Skrift Dev on the phone → pull over USB (devicectl app-container copy) → parse →
  MANDATORY second-agent verify → triage into backlog.md. Crash logs via `idevicecrashreport`.
- **`CONVERSATION_MODE_HANDOFF.md`** — conversation/diarization + voice identity (current focus): full state, the locked Sortformer-diarize + wespeaker-embedding-cosine design, bidirectional voice sync, mandatory codebase-read step, next-chat prompt. Start here for conversation work.
- `MOBILE_NATIVE_HANDOFF.md` → `MOBILE_NATIVE_REWRITE_PLAN.md` — the iOS app (phases, contract, XCUITest harness).
- `DESKTOP_NATIVE_HANDOFF.md` → `DESKTOP_NATIVE_REWRITE_PLAN.md` — the macOS app. `WALKTHROUGH_BUGS.md` — desktop walkthrough tracker.
- Memory: `project_native_convergence`, `feedback_vault_privacy`, `feedback_autonomous_execution`, `feedback_native_ui_process`, `feedback_native_ui_verification`.

## Branch

Converged onto **`native`** (merged `mobile-native` + `desktop-native`, 2026-06-07):
both apps + full history on one branch so cross-app features land atomically.

## Open cross-app work

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
