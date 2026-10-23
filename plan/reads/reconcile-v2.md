# Reconcile v2 beside v1 — every row that changed

1 of 109 corpus rows changes. v1 = the recorded row golden (`goldens/v1-rows/<slug>.json`, every stored `PipelineFile` field plus the working folder's files). v2 = `ReconcileV2.sweep` in `Skrift_Native/Shared/ReconcileV2/` (873 lines, 16% of v1's 5,297; budget 2,119, C3). The app still calls v1 (C2).

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

## Not in v2 yet

v2 is the sweep and its writers. These stay v1 until the swap and are not diffed here: the triggers + coalescer + fresh context (C52, the wiring), the Mac's own memos (`MacMemoAuthor.backfill` / `reflectTranscripts`), the orphan-row trash after the first import (C157), the background ingest of a large first enable (v2 ingests inline, on the main actor), the unrated-note projection (C187, `MemoNoteProjection`), the edit-conflict bookkeeping (v2 calls the shared `EditConflictHold`), the phone's asset materializer (C190) and `cloudKitMacSync` defaulting on (C191, a setting). C191's default is unchanged code.
