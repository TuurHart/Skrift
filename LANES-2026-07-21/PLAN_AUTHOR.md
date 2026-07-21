# PLAN_AUTHOR — the Mac authors Memos ⑤

Base SHA `11372a450faa733c28e79e5a3034debbdd0d71bb`. Read BASE.md + LANE_AUTHOR.md + all six
contract files (Memo.swift, MemoAsset.swift, MemoCloudIngest.swift, MemoCloudReconciler.swift,
MemoCloudUpdate.swift, MacCloudWriteBack.swift, MacCloudMetaSync.swift, UploadService.swift,
MemoCloudReconciler+Wiring.swift, PipelineFile.swift, MemoCloudContainer.swift, AppSettings.swift,
DeviceID.swift) before writing this.

## Findings that shape the plan (recorded so a reviewer doesn't have to re-derive them)

1. **"Local uploads make only PipelineFiles (UploadService.ingest)" is imprecise.** The real
   +Upload-button/drag-drop path is `IngestService.ingest(localURLs:into:)` — a SEPARATE struct,
   not owned by any lane in this batch (BASE.md's "everything else in Pipeline/Ingest" makes it
   READ-ONLY for me). `UploadService.ingest(parts:memoID:)`'s `memoID == nil` branch has exactly
   ONE real caller in the live app today: none — `MemoCloudIngest` (the only non-test caller)
   always passes a memoID. That branch is only exercised by tests standing in for the retired
   Bonjour HTTP path. This does NOT block the brief: `backfill(files:into:)`, hooked into the
   reconciler sweep (step 3), is the general-purpose mechanism — it scans ALL local PipelineFiles
   with a UUID id and no Memo, which catches IngestService-created rows (they mint
   `UUID().uuidString` ids) on the next sweep regardless of which local path created them. See
   finding 8 below for why step 2 ended up NOT calling `MacMemoAuthor` after all — `backfill` is
   the one that actually delivers Q5 for the real +Upload/drag-drop path either way. No
   escalation needed; this is implementation-mapping, not a contract gap.
2. **`PipelineFile` has no `duration` field.** The brief's "duration/recordedAt from the pf" reads
   `recordedAt` as `pf.uploadedAt` (the closest analogue — IngestService's own comments call it
   "the CONTENT date"), but there's no `pf.duration` to copy. Leaving `Memo.duration` at its
   default (0) would show "0:00" on the phone's memo-row duration chip forever (confirmed:
   `MemoDisplay.durationLabel` formats unconditionally, no zero-hiding) — a visible regression for
   a memo that has real audio. Decision: compute it synchronously from the materialized audio file
   via `AVURLAsset(url:).duration`, mirroring the EXACT synchronous-AVFoundation pattern
   `IngestService.hasVideoTrack`/`embeddedRecordingDate` already use in this codebase (not a new
   pattern). Best-effort — nil/unreadable file → duration stays 0, never blocks authoring.
3. **The phone's audio `MemoAsset.kind` string is unambiguous.** `MemoAsset.Kind.audio == "audio"`
   is a shared constant; grepped the phone's own `AssetMaterializer.swift:97` — it uses the SAME
   `MemoAsset.Kind.audio` constant, not a raw literal. No escalation needed.
4. **The working-folder audio path is directly resolvable.** `PipelineFile.path` is already the
   absolute path to `original.<ext>` for `sourceType == .audio` (set by both `UploadService` and
   `IngestService` at construction) — no extra helper needed. For `.note`/`.capture` sourceType,
   `path` isn't an audio file, so `resolvedAudioURL` only resolves for `.audio` rows. No escalation
   needed.
5. **One demo row breaks the brief's "non-UUID = demo row" shortcut.**
   `DemoSeed.swift`'s `f7` deliberately uses a UUID-shaped id
   (`"9E8B7C6D-1111-4222-8333-444455556666"`, comment: "UUID-string id like a real synced memo",
   used only to make a memo-link chip resolve in `-snapshot`/`-demo` renders). It has NO `path` set
   (omitted from its initializer call, defaults to `""`), unlike every real local ingest (which
   always sets a real `path`). `backfill` additionally requires `sourceType == .audio && !path
   .isEmpty` before treating a row as an authoring candidate, which excludes this demo row (and
   every other non-audio/pathless synthetic row) without weakening the real-file case. `-demo` mode
   is an explicit CLI dev flag (`RootView.swift`, `args.contains("-demo")`), never hit in normal
   use, so this is a belt-and-suspenders correctness fix, not a response to a live bug.
6. **`reflectTranscripts` is scoped to Mac-authored memos only**, via
   `memo.recordingDeviceID == DeviceID.current()` (the field exists precisely to answer "did this
   device create this memo"). Without this guard, the literal brief wording ("pf.transcript exists
   and memo.transcript is empty") would ALSO fire for a phone-originated memo whose transcript the
   Mac distrusted and re-transcribed itself — silently pushing the Mac's re-ASR back onto a
   phone-authored memo. That's a plausible feature but a BROADER one than "a Mac upload's
   transcription reaches the phone" (the brief's own framing) and isn't this lane's call to make
   unscoped. Flip: delete the one guard line if the wider behavior turns out to be wanted.
7. **`author()` stamps `transcriptConfidence = 1.0`, never `transcriptUserEdited`**, when it sets a
   transcript. `.done` + a real trust-worthy confidence value keeps `Memo.isTrustedTranscript`
   coherent without lying about who wrote it (`transcriptUserEdited` stays false — nobody edited
   it).
8. **Step 2 (the UploadService hook) was built, then REVERTED — a real compile-boundary bug caught
   while writing tests, not a style choice.** `project.yml`'s `SkriftDesktopTests` target compiles
   `Pipeline/`, `Models/`, and `../Shared/*` sources HOST-LESS, straight into the test bundle —
   explicitly excluding `App/`/`Features/`/`Engines/` (its own comment: "compile the pure-logic
   sources straight into the test bundle instead of @testable-importing the app"). `MemoCloudStore`
   (the CloudKit container) lives in `App/MemoCloudContainer.swift`; grepped the WHOLE codebase —
   it is referenced ONLY from `App/`/`Features/` files (`MacCloudMetaSync`, `MemoCloudReconciler
   +Wiring`, `JournalView`, `ProcessingCoordinator`), NEVER from `Pipeline/`/`Models/`/`Shared/`.
   My first draft of `authorLocalUpload` (gated like `MacCloudMetaSync`, called from
   `UploadService.ingest`) referenced `MemoCloudStore.container` from `MacMemoAuthor.swift`, which
   lives under `Pipeline/` — that would have failed "cannot find 'MemoCloudStore' in scope" the
   moment `xcodebuild test -scheme UnitTests` tried to compile the test bundle, REGARDLESS of
   whether any test exercised that function (the whole file has to compile). Fixed by reverting
   `UploadService.ingest` to its original one-line body and deleting `authorLocalUpload` entirely
   — `MacMemoAuthor.swift` is now 100% pure (Foundation/SwiftData/AVFoundation +
   Memo/MemoAsset/PipelineFile/DeviceID only, all host-less-compiled types). Given finding 1
   (step 2's hook had zero live callers anyway), this costs nothing functionally — `backfill`
   (step 3, wired from the ALREADY `App/`-domain `MemoCloudReconciler+Wiring.swift`, which is
   correctly excluded from the test target and free to depend on `MemoCloudStore`) is the complete,
   correctly-layered, and only mechanism that ships. Not an escalation: no contract file changed,
   a fully-tested working alternative already existed, and the alternative (adding `App/` to the
   test target's sources, or building a DI seam into `UploadService`) is a bigger, riskier,
   out-of-scope change to shared build config this lane has no business making unilaterally.

## Build steps (small commits, explicit paths)

1. `Skrift_Native/SkriftDesktop/Pipeline/Ingest/MacMemoAuthor.swift` (NEW) — `author`,
   `reflectTranscripts`, `backfill`, `resolvedAudioURL`/`markTranscribed`/`audioDuration` privates.
   Pure — no `MemoCloudStore`/`SettingsStore` dependency (see finding 8).
2. `Skrift_Native/SkriftDesktop/Pipeline/Ingest/UploadService.swift` — doc-comment-only change:
   `ingest(parts:into:memoID:)` explains why it does NOT hook `MacMemoAuthor` (finding 8). Body is
   byte-identical to before this lane touched it.
3. `Skrift_Native/SkriftDesktop/App/MemoCloudReconciler+Wiring.swift` — Q6 flip
   (`processEverything: false` + retirement comment) + hook `backfill`/`reflectTranscripts` into
   `reconcile()` after the existing sweep, same gated block, best-effort logged.
4. `Skrift_Native/SkriftDesktop/SkriftDesktopTests/MacMemoAuthorTests.swift` (NEW) — field mapping +
   0.1 floor, idempotency, non-UUID skip, backfill orphans-only, reflectTranscripts empty-only +
   device-scoped, author→sweep round-trip creates no second PipelineFile.

## Don'ts (reconfirmed)

No edits to MemoCloudIngest/MemoCloudUpdate/MacCloudWriteBack/MemoCloudReconciler.swift, Shared/,
Features/, IngestService.swift, AppSettings.swift/SettingsView.swift (Q6 UI is LANE_SURF's).
