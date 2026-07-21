# LANE_AUTHOR — the Mac authors Memos ⑤ (both devices are collectors)

Read `LANES-2026-07-21/BASE.md` first (base check, ownership, rules). Locked direction (Q5,
Tuur 2026-07-21): a file uploaded ON the Mac becomes a synced `Memo` like any phone capture —
"Mac-only files" stop existing. Verified starting fact: today ZERO code in the desktop app
constructs a `Memo`; local uploads make only `PipelineFile`s (UploadService.ingest).

Contracts you build against (all READ-ONLY):
- `Shared/Model/Memo.swift` — the init (id, audioFilename, duration, recordedAt, transcript,
  transcriptStatus, significance, recordingDeviceID, …). `Shared/Model/MemoAsset.swift` —
  `init(memoID:kind:filename:blob:createdAt:)`; grep the PHONE'S usages for the exact audio
  `kind` string and mirror it byte-for-byte.
- `MemoCloudIngest.swift` — the reverse bridge. The reconciler matches memo↔pf by id OR
  filename (MemoCloudReconciler.swift:75-77), so an authored Memo with `id == pf.id` and
  `audioFilename == pf.filename` can NEVER double-ingest — it hits the update path.
- `MemoCloudStore.container` — the cloud context. Gated: author ONLY when
  `SettingsStore.shared.load().cloudKitMacSyncEnabled` and the container exists (copy
  MacCloudMetaSync's guard exactly).

## Build (small commits, explicit paths)

1. NEW `Pipeline/Ingest/MacMemoAuthor.swift`:
   - `author(for pf: PipelineFile, audioURL: URL?, into ctx: ModelContext)` — idempotent
     (fetch by id first; bail if a Memo exists). Fields: `id = UUID(pf.id)` (bail on
     non-UUID), `audioFilename = pf.filename`, duration/recordedAt from the pf,
     `transcript = pf.transcript` + `transcriptStatus = .done` when the pf already has one
     else `.pending`, `significance = (pf.significance ?? 0) > 0 ? pf.significance! : 0.1`
     (LOCKED: a Mac capture is user-initiated processing — an unrated Memo the Mac processes
     would lie on the phone), `recordingDeviceID = DeviceID.current()`. Attach a MemoAsset
     with the audio blob when `audioURL` is readable; author WITHOUT audio otherwise (honest
     text-only note beats no note).
   - `reflectTranscripts(files:into:)` — sweep-companion: for authored/matched pairs where
     `pf.transcript` exists and `memo.transcript` is empty, copy transcript +
     `transcriptStatus = .done` + confidence flags. This is how a Mac upload's transcription
     reaches the phone WITHOUT touching the processing coordinator (not yours). No
     `lastEditedAt` bump (echo-quiet, same reasoning as MacCloudMetaSync).
   - `backfill(files:into:)` — one-shot over live local pfs with UUID ids and no memo: author
     each (audio from its working-folder file when present — resolve via the same path
     helpers UploadService uses). Skip non-UUID (demo rows). Idempotent by construction, so
     no stored "ran once" flag.
2. `UploadService.swift`: in the LOCAL ingest path only — `memoID == nil` distinguishes it;
   the CloudKit re-ingest path passes memoID and must NOT author — call
   `MacMemoAuthor.author` for each created PipelineFile (audio URL = the file it just
   materialized). Keep the HTTP-parity structure intact.
3. `App/MemoCloudReconciler+Wiring.swift` (yours):
   - Hook `MacMemoAuthor.backfill` + `reflectTranscripts` into the existing sweep trigger
     path (same gates as the sweep — enabled + container).
   - Q6 flip (pinned seam): `processEverything: settings.processAllSyncedMemosEnabled` →
     `processEverything: false`, with a one-line comment "toggle retired 2026-07-21 — the
     Queue band's Process all N is the visible override". LANE_SURF removes the Settings UI;
     do NOT touch AppSettings/SettingsView yourself.
4. Tests — NEW `SkriftDesktopTests/MacMemoAuthorTests.swift` (MLX-free, in-memory
   ModelContext like MemoCloudIngestTests): authoring maps every field + the 0.1 floor;
   idempotency (author twice = one memo); non-UUID skipped; backfill authors only orphans;
   reflectTranscripts fills empty-only (never clobbers a phone transcript); a full
   author→reconciler-sweep round-trip creates NO second PipelineFile.

## Don'ts
No edits to MemoCloudIngest/MemoCloudUpdate/MacCloudWriteBack/MemoCloudReconciler.swift —
read them, call them, never change them. No Shared/ edits. No Features/ edits. If the phone's
audio-asset `kind` string is ambiguous or the working-folder audio path isn't resolvable from
your files — ESCALATE with the evidence; a wrong asset kind poisons sync.
