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
  Center + Lock/Home widgets, App Intents, share-to-import audio.
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

## Ledgers (read to resume)

- **`FEATURES.md`** — cross-app feature source of truth (every feature × {mobile, desktop} ×
  file × status). **Update it in the same commit whenever you add or change a feature.**
- **`CONVERSATION_MODE_HANDOFF.md`** — conversation/diarization + voice identity (current focus): full state, the locked Sortformer-diarize + wespeaker-embedding-cosine design, bidirectional voice sync, mandatory codebase-read step, next-chat prompt. Start here for conversation work.
- `MOBILE_NATIVE_HANDOFF.md` → `MOBILE_NATIVE_REWRITE_PLAN.md` — the iOS app (phases, contract, XCUITest harness).
- `DESKTOP_NATIVE_HANDOFF.md` → `DESKTOP_NATIVE_REWRITE_PLAN.md` — the macOS app. `WALKTHROUGH_BUGS.md` — desktop walkthrough tracker.
- Memory: `project_native_convergence`, `feedback_vault_privacy`, `feedback_autonomous_execution`, `feedback_native_ui_process`, `feedback_native_ui_verification`.

## Branch

Converged onto **`native`** (merged `mobile-native` + `desktop-native`, 2026-06-07):
both apps + full history on one branch so cross-app features land atomically.

## Open cross-app work

- **Capture items** (share a URL/text/image into Skrift + annotate it): needs BOTH
  apps. Mobile = a share-extension target + App Group + the `attachments` multipart
  part (mobile `UploadMetadata` already carries `sharedContent`/`annotationText`).
  Desktop = `UploadService` currently only ingests audio `files` (always
  `sourceType:.audio`) — it must accept a non-audio "capture" content type and carry
  it through pipeline/compile/export. Build as one coordinated commit on `native`.
