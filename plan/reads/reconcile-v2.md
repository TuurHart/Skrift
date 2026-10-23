# Reconcile v2 beside v1 — every row that changed

1 of 109 corpus rows changes. v1 = the recorded row golden (`goldens/v1-rows/<slug>.json`, every stored `PipelineFile` field plus the working folder's files). v2 = `ReconcileV2.sweep` in `Skrift_Native/Shared/ReconcileV2/` (873 lines at Q429, 1,262 after Q510; v1 is 5,297, budget 2,119, C3). The app still calls v1 (C2).

Harness (`ReconcileDiffHarnessTests`, Q428): v1 identical 109; v2 identical 108, expected-different 1, unexplained 0. The second and third sweeps change nothing in v2 (C41); v1 still has its one known second-sweep heal (`pic-missing-file`).

## The one changed row

| slug | field | v1 | v2 | clause |
|---|---|---|---|---|
| pic-missing-file | `folder` | `original.m4a` only | `original.m4a` + `image_manifest.json` | C41 |

The memo's manifest names a photo whose blob never synced. v1 writes no `image_manifest.json` at first contact (it only writes one when a photo blob is present), so its second sweep writes it as a "heal" and bumps `lastActivityAt`: a second sweep that changes something, against C41. v2 writes the manifest at first contact from the memo's own list, so the row is settled after one sweep. The marker still shows a placeholder and export still skips the picture, as the fixture expects.

## What changed that one sweep's golden cannot show

Each is pinned by `ReconcileV2Tests`.

| what | v1 | v2 | clause |
|---|---|---|---|
| Blobs read by a sweep of an unchanged corpus | 2 per sweep, forever (pic-missing-file's photo, video-no-speech's empty timings `[]`) | 0. The asset index (one blob-free fetch: kind, filename, byte count) says whether a missing file's asset exists and whether a timings asset holds anything | R29, C45 |
| The Mac's polish when the phone's clock runs fast | refused for good: the phone's stamp is compared to THIS Mac's clock | written: stamp compared to stamp. A polish is refused only when it came from another device the row has not seen (beyond the row's watermark + 5 s). The Mac's stamp is never earlier than the one it replaces | R44, C46 |
| A conversation re-split on the phone | the Mac keeps the first split forever (adopted once) | re-adopted when the decoded segments differ, checked only in a sweep that changed the row's words to the phone's trusted words. A Mac-made split is never replaced; a steady sweep reads no diarization blob | R57, C45 |
| Query during a sweep | the reconcile has one await (background ingest), committed in one main-actor block | no await anywhere: a pure synchronous main-actor sweep, one save | C294 |

## Same as v1, by rule

Checked by the harness (row-for-row) or a v2 test: one row per rated live memo, none for a never-rated or trashed one (C41, C187); trust gate and sidecars only with a trusted transcript (C42); kinds from the memo, a voice memo whose audio is still on its way waits and never becomes text (C43); direct memo → row, no multipart (C44); late photos, movie, link thumbnail, attachments, timings (C45); fresh row adopts this Mac's polish, an existing row ignores its own echo (C46); per-field content reflect, a nil or blank title never clears, lock / reminder / OCR never recompile (C47, C188); same-id clones → one row (C48); row match by id, else filename unless another memo owns that row (C188); content date = the phone's `recordedAt` (C188); a failed store read is reported, never an empty store (R40). Q486: a copy-edit older than the raw words is never adopted. Q489: a Mac body edit is settled into the copy-edit before any recompile.

Writers (Mac → phone, `ReconcileV2.Writers`): resolve the memo through the store, a Mac recording included (C186); rating / title / destination are events on the memo; clearing a rating writes 0; no meta write bumps the edit time; a Mac trash stamps `trashSeenAt` (C188). Pass order as data: names, vocabulary, prompts, sweep, notify, save + re-export, author backfill, transcript reflect, index (C185). Re-export only rows already exported, unlocked and live (C189).

## Q510: the whole pass

v2 now covers the pass around the sweep, not only the sweep: 1,262 lines (24% of 5,297; budget 2,119). Still one synchronous main-actor sweep with no `await` in `Shared/ReconcileV2/` (C294). Harness unchanged: v2 identical 108, expected-different 1, unexplained 0. Tests `ReconcileV2PassTests`.

| piece | now | why / clause |
|---|---|---|
| Orphan-row trash | in v2 (`ReconcileV2.Orphans`) | C157 with Q487's refusals: no memos in the store, or more than a quarter of the linked rows (and more than two) at once, is refused and logged; never before the first import; an in-flight ingest is never an orphan |
| Mac's own memos: author backfill + transcript reflect | in v2 (`ReconcileV2.Author`) | Q397: only rows this Mac captured, only after the first import, never a phone row; the take's words reach its memo once, never a capture's, never another device's, no edit-time bump (C188); timings and diarization ride as the phone's assets (C245) |
| Background first-enable ingest | in v2 as two synchronous halves | `run(deferNew: true)` returns the never-seen ids; `Ingest.prepare` writes folders (nonisolated, safe on a background context); `Ingest.commit` makes the rows on the main actor. The one `await` (the detached task between them) belongs to the app wiring, so the v2 folder stays await-free. The test runs prepare on a detached task and gets the same rows as the inline sweep |
| Names / vocabulary / prompts before memos | in v2's pass as its `carriers` step | C185: the pass runs them first (a test checks no memo was fetched yet); the carriers themselves are app singletons |
| Triggers, coalescer, fresh context | stays in the wiring | C52 is WHEN and THROUGH WHAT the pass runs (NSApplication / CloudKit notifications, `ReconcileCoalescer`, `freshCloudContext`). A host-less sweep must not depend on app lifecycle; at the swap the wiring calls `ReconcileV2.pass` instead of v1 |
| Unrated-note projection | stays outside | C187 renders a never-rated memo as a transient row at VIEW time; the sweep's whole rule for it is "no row", which the harness and the C41 test check |
| Phone asset materializer | stays outside | C190 is the phone's sweep (blobs to files on the phone); the Mac's heals follow the same never-overwrite rule and are in v2 (`Heal`) |
| `cloudKitMacSync` default on | stays a setting | C191 is the gate the wiring checks before any pass, not sweep logic. Now pinned by a test (never set = on, explicit off honoured) |

**R44 closed.** v2's reflect now records every phone polish it SEES: when a later-stamped phone polish carries words the row already has (nothing to adopt), the row's watermark still moves to its stamp. The Mac's next polish is then written, not refused as "newer, unseen". The row is saved but not re-exported (`watermarked`, not `updatedIDs`).

Still outside v2 after Q510: the edit-conflict bookkeeping (v2 calls the shared `EditConflictHold`), the notice + re-export + connections index (the pass returns `reexportIDs`; the app does the export).

## Q512: app code stops calling v1

App code (App, Features, Pipeline, Models) now calls only reconcile v2, so Q432 can delete v1 without touching it. v2 is 1,298 lines (budget 2,119).

| v1 call | now | sites |
|---|---|---|
| `MacCloudWriteBack.resolve` | `ReconcileV2.Writers.resolve` | MacCloudMetaSync, MacCloudEditSync, LiveRecordingSession, NoteBody (4), NoteActions, VaultExporter, PipelineFile+BodyNormalise |
| `MacCloudWriteBack.upsert` | `Writers.upsertEnhancement` (R44 stamp-to-stamp guard) | MacCloudEditSync, ProcessingCoordinator, MacAppendRecording |
| `MacCloudWriteBack.memoID` / `uuid(fromFilename:)` | `Writers.memoID` / `Writers.candidates` (same order) | WayOutRules, MacEmbeddingSnapshot |
| `MirroredNoteFields.pushable` | `Writers.pushMeta` (tags; a rating only when set) | MacCloudMetaSync.mirror |
| `MemoCloudUpdate.resanitiseAndCompile` | `Reflect.recompile(_:people:author:)` | MacAppendRecording, RosterRelink, BatchRunner |
| `MemoCloudIngest.metadataJSON` / `ocrText` | `ReconcileV2.Ingest` | MemoNoteProjection, MacLocationStamp |
| `AssetKindIndex` | `ReconcileV2.AssetIndex.has` | wiring's orphan-transcription adopt |
| `UploadService` | a plain output URL | Snapshot capture renderer |
| `MacMemoAuthor.typedNote` | `Memo.newTyped` | RunFile `-typednote` |
| `MemoCloudReconciler` declaration (`didStart`, `coalescer`) | `ReconcileTriggers.swift`; the v1 file is now an extension | — |

Behaviour change: the Mac's edit and pass write-backs now use v2's R44 guard. A polish from another device that the row has not seen yet (beyond its watermark + 5 s) refuses the Mac's write, where v1 compared the other stamp with this Mac's clock.

Stays outside v2: `MemoPhotoMaterializer` (+ `MacNoteAttachments.materializeMissing`). The unrated-note projection (C187) uses it at view time from a lazy asset closure, with no store to index; it is not reconcile code and Q432 must keep it.
