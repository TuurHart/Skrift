# NEXT CHAT — Skrift resume (handoff)

Paste-as-prompt. Work **autonomously**: build without asking, **gate + commit per chunk**,
device-install, report. Don't push to `main` (prod untouched). Mock-first only for genuinely-new UI.

## READ FIRST
1. `CLAUDE.md` — build/run, hard rules, **dev/prod data safety** (build+install the DEBUG "Skrift Dev"
   only; never rebuild prod). The signing lesson: `-allowProvisioningUpdates` registers bundle IDs but
   **can't add a capability (App Groups)** — that's a one-time Xcode Signing&Capabilities visit per target.
2. `backlog.md` — **the bottom is the live ledger.** The newest items (2026-06-14) are appended after the
   ⭐ block: share-video diagnosis+fix, the date sort/filter, and (in the ⭐ block) the capture redesign.
3. `FEATURES.md` — every feature × {mobile,desktop} × file × status (kept current per-commit).

## STATE (2026-06-14)
Branch `native`, **all committed, `main` untouched/un-pushed, prod untouched**. The mobile **dev** build
("Skrift Dev", `com.skrift.mobile.dev`) is installed on the **iPhone 13** (devicectl UUID
`A9195A77-601A-54C1-B3BD-659FBFE1DC54`). Gate = `xcodebuild test` on the iPhone 17 sim — but an earlier
`simctl erase` wiped the sim's onboarding/permissions, so the **UI** suite cross-fails on a fresh sim;
gate on **unit-only** (`-only-testing:SkriftMobileTests`) + compile + device eyeball until the sim is
re-stated. Real ASR / read-along / share behaviour are device-owed (sim has no ANE).

### Shipped this session (all on `native`, dev build on the phone)
- **Control Center / record-widget glyph → `quote.opening` ❝** (`806645b`).
- **Audiobook capture redesign** (signed-off mock `mocks/audiobook-capture-merged.html`): full-screen
  player — read-along fills, controls pinned (`605efec`); **merged note-style capture screen**
  `MergedCaptureView` — significance card → build-your-quote → Record-your-thoughts; builds quote → memo →
  significance → recorder → auto-resume into note (`24d6e85`); **retired the audio mark-in/out arm**
  (deleted `CaptureMomentView`/old `CaptureSheetView`/`TextCaptureView`/`AudiobookCaptureStyle`/`GrainPlayer`/
  `SpanWaveform`; text is the only flow) (`6a08df7`).
- **Build-your-quote bidirectional + bounded** (`5a6991f`→`daa80f5`): the tapped line is the centred
  anchor; ~90 s before + up to **8** lines after (transcribed) / **4** (un-chunked). [First attempt went
  backward-only (`df1303c`) — wrong; corrected.]
- **Share a video from Photos → voice memo** (`551f032`): `NSExtensionActivationSupportsMovieWithMaxCount`
  + a `"video"` inbox entry → `CaptureInboxDrainer` → `MemoSaver.importVideo`. The "memo vanishes" report
  was **DevLog-diagnosed = relocation** (recordedAt rewritten to the video's filming date), not a delete/
  crash → fixed by (a) open-on-import `MemoOpenBridge` (`4f3f501`) and (b) the date sort below.
- **Memo sort/filter by date** (`fc5e818`): `Memo.createdAt` (added) + `editedAt` (bumped on edits) —
  nil-default, legacy falls back to `recordedAt` (no migration). Sorts: **Recently added (DEFAULT)** /
  Recently edited / Recently recorded / Oldest / Longest; day-headers follow the sort; date-range filter
  (Recorded or Added). `recordedAt` is never rewritten → a shared video keeps its true date but sorts to
  the top under "added". Local-only (not in the Mac upload contract).
- **DevLog instrumentation kept** (DEBUG-only): drain → importVideo → processVideo + the three memo-removal
  vectors (softDelete/permanentlyDelete/delete). Pull: `xcrun devicectl device copy from --device <UUID>
  --domain-type appDataContainer --domain-identifier com.skrift.mobile.dev --source Documents/devlog.txt ...`

### ⏳ OWED — device eyeball (sim can't): the ❝ glyph (CC + widget), full-screen player + read-along sync
(`ReadAlongView.lead` 0.1 s dial), merged capture E2E, the bidirectional/bounded selection, share-video
open-on-import, and the new date sorts + date filter (esp. the pickers + the edited-sort over real edits).

## TestFlight (NEW ask 2026-06-14 — internal testers, NO review)
Method = how glot-study/echo does it (same team **9W82X49JZS**): `xcodebuild archive` (Release) →
`xcodebuild -exportArchive` with **`Skrift_Native/SkriftMobile/ExportOptions.plist`** (already created:
`method=app-store-connect`, `destination=upload` → auto-uploads to TestFlight) + an **ASC API key**
(`-authenticationKeyPath ~/.asc-api/key.p8 -authenticationKeyID <KEY_ID> -authenticationKeyIssuerID <ISSUER>`).
Internal testing = immediate, no Apple review. Exact commands are in `ExportOptions.plist`'s comment.

**BLOCKED on 3 prereqs (credential/portal/Xcode — not code; user must provide/do):**
1. **ASC API key not on disk** — `~/.asc-api/` is absent. Reuse the glot-echo key (same team) or download
   one (ASC → Users & Access → Integrations → Keys); place the `.p8` + note its key ID + issuer ID.
2. **App-Group capability on the Release bundle IDs** (`com.skrift.mobile`, `.share`, `.widget`) — one-time
   Xcode Signing & Capabilities visit (the dev IDs got it 2026-06-12; `-allowProvisioningUpdates` can't).
3. **ASC app record** for `com.skrift.mobile` (create it — immediate, not review).
Release archive attempt logged in the session (run id `bjksgvzfi`) to confirm the precise signing blocker.
Once 1–3 are in place it's the two commands above (I can run them). NOTE: TestFlight ships the **Release**
(`com.skrift.mobile`) build — that's the first time prod signing is exercised (prod data still untouched).

## Pre-existing backlog (untouched) — see `backlog.md`
Prod promotion (push `native`→`main`); Mac "name a speaker" UI (backend ready); record-a-voice enroll
(placeholder both apps); drag-multi-select (Photos-style lasso, wants a mock); desktop Models/Storage view;
in-app feedback→inbox; source-taxonomy unification; re-ingest old notes; "transcription a bit weird".

## GATES
Mobile: `cd Skrift_Native/SkriftMobile && xcodegen generate` after adding files; unit gate
`xcodebuild test -scheme SkriftMobile -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build -only-testing:SkriftMobileTests`;
device `xcodebuild build -scheme SkriftMobile -destination 'generic/platform=iOS' -derivedDataPath build-device -allowProvisioningUpdates DEVELOPMENT_TEAM=9W82X49JZS CODE_SIGN_STYLE=Automatic` then
`xcrun devicectl device install app --device A9195A77-601A-54C1-B3BD-659FBFE1DC54 build-device/Build/Products/Debug-iphoneos/SkriftMobile.app`.
Commit per chunk; update `FEATURES.md` + `backlog.md` in the same commit.
