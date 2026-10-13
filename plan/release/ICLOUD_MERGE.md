# iCloud merge: the prod Mac's Development data into Production (Q393, D203)

Plan only, written 2026-10-13. Nothing here has been run. No agent has read his data, opened a
real store or touched CloudKit. Research behind it: `plan/research/cloudkit-env-switch.md` (what
an environment switch does) and `plan/research/cloudkit-env-mac-release.md` (why the Mac is on
Development).

## End state

- One copy of everything in the **Production** environment of `iCloud.com.skrift.mobile`.
- The phone (already on Production) and the Mac (Release build pinned to Production by Q388) both
  sync it.
- Every note, polish, person and custom word made on either side since the split is present
  once. No `Memo.id` appears twice that did not already appear twice before.
- The Development environment is left as it is, untouched. It is the second backup.

## What lives where today

The split date is **S = 2026-09-25 00:00 Europe/Lisbon**. The Mac shows phone notes up to 25/26
Sep, and the phone's newest note is from 11 Oct.

| Place | Holds | Environment |
|---|---|---|
| Phone local store (iPhone 17 Pro, prod app, TestFlight/App Store signed) | Everything the phone has: its pre-S history (how it got there is unconfirmed, see F2) plus every note since S. Polish the Mac wrote before S. | syncs **Production** |
| Production (CloudKit) | Whatever the phone exported under Production. Unconfirmed whether that includes the pre-S history (see research Q1: export only covers history after the last token). | — |
| Mac `~/Library/Application Support/Skrift/memo_cloud.store` (+`-wal`, `-shm`, `.memo_cloud_SUPPORT`), August build `e6245caa` | Every phone note up to S. **Mac-only since S:** notes made on the Mac (recordings, imports, typed notes), `MemoEnhancement` polish of any note, and Mac edits to shared notes (rating, title, body, trash, lifecycle auto-trash, all written by the Aug build: `MacCloudMetaSync.swift`, `MemoNoteProjection.swift`, `MacCloudDeleteSync.swift`, `LifecycleSweepScheduler.swift` at `e6245caa`). | syncs **Development** |
| Development (CloudKit) | The Mac's side, plus the phone's side up to S. | — |
| Mac `skrift.store` (local `PipelineFile` rows, never synced) | The Mac's queue: one row per note it ingested or made, with its local polish. Row `id` = the note's `Memo.id`. | none |
| Mac `names.json`, `user_settings.json` | The Mac's people (with tombstones), custom words, polish prompts. Merged with the cloud carriers by the normal reconcile (`NamesSyncCore`, `VocabularyCloudSync`, `PolishPromptsCloudSync`). | none (local) |

## Why not just install the Production build over the old store

That is what happens by default: the Release app opens `memo_cloud.store` at the fixed path
(`MemoCloudContainer.swift:94`). What the container then does is undocumented and the reports
disagree. One developer's local data vanished (forum 728475); another's stayed local and never
uploaded (forum 763062). If it re-uploads under fresh record names, every shared note becomes two
rows with one `Memo.id`, and the phone never heals divergent pairs (`MemoDeduper.swift`). Research
doc, "The four questions": all low confidence. So the plan never lets the real store see a
Production-pinned build.

## The approach

1. Move the old Mac store out of the app's folder, untouched, and keep it as the source.
2. The Production-pinned Mac starts with a fresh `memo_cloud.store` and downloads Production.
3. A one-time merge reads a COPY of the old store (CloudKit off) and writes only what Production
   lacks into the live Production store, matched by `Memo.id` / `memoID`. These are ordinary
   SwiftData inserts and updates, so they sync like any new note.
4. Names, words and prompts need no copying: they live in the Mac's local files and the normal
   reconcile merges them with Production.

## Code that must land first (agent work, four new queue items)

| Id | What | Why |
|---|---|---|
| A1 | **Backfill guard.** `MacMemoAuthor.backfill` (`MacMemoAuthor.swift:225`, run on every reconcile from `MemoCloudReconciler.swift:362`) may author a `Memo` only for a row with `isLocalCapture` true, and only once the cloud store has finished its first full import since it was created (an `NSPersistentCloudKitContainer.eventChangedNotification` import that ended with success, stamped in settings). Test: a fresh, empty cloud context plus phone-origin `PipelineFile`s authors nothing. | Today a fresh store makes the Mac author a Mac-shaped twin of **every** phone note it has a row for, because none of their `Memo`s have downloaded yet. Those twins upload and collide with the phone's records as divergent same-id pairs. This is the biggest code risk in the whole switch, merge or no merge. |
| A2 | **Merge engine** `SkriftDesktop/Pipeline/Ingest/DevEraMerge.swift` (built Q398, Mac-only, tests `DevEraMergeTests`): `plan(old:prod:splitDate:macDeviceIDs:)` returns counts plus a list of actions; `apply(_:from:into:firstImportDone:)` performs them in batches of 25 notes per save. Rules below. Unit tests on synthetic stores. | Deterministic, id-based, testable without CloudKit. |
| A3 | **Dry-run tool.** `StoreCopyTest --merge-dry-run --old <copy> --prod <copy>`: runs plan and apply on two copies with `cloudKitDatabase: .none`, prints counts before and after (never a title or text), exits 1 on any check failure. `plan/release/mac-store-copytest.sh --merge <old store dir>` copies both (old store from its backup folder, Production store from the live app folder, app quit) into a fresh temp dir and runs it. Self-test on the synthetic corpus. | The dry run below. Reuses the Q367 guard (marker file, protected roots, exit 3). |
| A4 | **One-shot trigger in the Release app.** If `~/Library/Application Support/Skrift/merge-from-dev/memo_cloud.store` exists and the first-import stamp from A1 is set, show one alert with the dry-run counts ("Bring in N notes and M polishes from the old Mac store?"). Yes runs `apply`, writes `merge-report.txt` (counts and inserted ids only) and renames the folder to `merged-<date>`. No leaves it. | Release builds cannot take DEBUG launch arguments. One alert, no new screen. |

A1 ships in the same Release build as Q388 (the Production pin) or earlier. Without A1, step 6
below is unsafe.

## Merge rules (A2)

Per note id, after collapsing same-id rows on each side with `MemoDuplicates.keeper`:

| Case | Action |
|---|---|
| In both, Production unchanged since S, old store edited on the Mac after S (`lastEditedAt` > S) | Copy the fields the Aug Mac writes (rating, title, transcript/annotation body, `deletedAt`, `trashSeenAt`) onto the Production row. A2 must confirm from `e6245caa` that each of those writes bumps `lastEditedAt`; any that does not gets a field-by-field compare instead. |
| In both, edited on both sides after S | Keep Production. Count it as a conflict and list its id in the report. Tuur decides; expected to be a handful. |
| In both, otherwise | Keep Production. |
| Only in old store, made on the Mac (`recordingDeviceID` is the Mac's `DeviceID`, or a Mac typed note) | Insert it with all its `MemoAsset` rows. |
| Only in old store, phone-made, `recordedAt` ≥ S | Insert (a phone note that reached the Mac but not Production). |
| Only in old store, trashed (`deletedAt` set) | Skip, count. |
| Only in old store, phone-made, `recordedAt` < S | **Do not insert.** Most likely deleted on the phone after S and purged (14-day trash, `Memo.swift:23`). Count it by month. If this count is large (more than 20), Production probably lacks the phone's history: **stop and re-plan**. |
| Only in Production | Nothing. |

### What the Aug Mac's writes stamp (Q398, read from `git show e6245caa:…`, 2026-10-13)

**Most Aug Mac writes do NOT bump `lastEditedAt`.** Only one path calls `markEdited`:

| Aug Mac write (`e6245caa`) | Fields | Bumps `editedAt`? |
|---|---|---|
| `MemoNoteProjection.writeBack` (edits in an unrated note's pane) | title, transcript + `transcriptUserEdited`, tags | **yes** (`markEdited`, content changes only) |
| same, rating change | significance | no |
| `MacCloudMetaSync.mirror` / `setRating` / `setTitle` | tags, significance, title | no (doc comment says so on purpose) |
| `MacCloudDeleteSync.mirror`, `SidebarView`/`JournalView`/`UnpipelinedMemoSheet` delete | `deletedAt`, `trashSeenAt` | no (but `deletedAt` is itself a time) |
| `LifecycleSweepScheduler` auto-trash | `deletedAt`, `trashSeenAt` | no (same) |
| `WayOutRules.bringBack` (restore / keep) | `keptAt` = now, `deletedAt` = nil, `trashSeenAt` = nil | no (but `keptAt` is a time) |
| `MacMemoAuthor.reflectTranscripts` (Mac's own notes, empty transcript only) | transcript, status, confidence | no |
| `SidebarView` / `UnpipelinedMemoSheet` rate | significance | no |

The phone's rating (`MemoPageView` significance binding) and restore (`NotesRepository.restore`)
do not stamp either. So for a field neither side timestamps, a difference does not say which side
changed it. The engine (`SkriftDesktop/Pipeline/Ingest/DevEraMerge.swift`) therefore copies only
on evidence:

- **Content (title, body, tags):** copied when the old row's `editedAt` > S and Production's
  `editedAt` ≤ S. Both > S with a difference = conflict, Production kept, id listed. Old `editedAt`
  ≤ S with a difference = "diverged", Production kept, id + field listed for Tuur (this is where a
  Mac `setTitle` after S shows up).
- **Rating:** copied with the content case above only when Production's rating is 0 (never
  overwrite a rating Production has, since the phone's rating leaves no stamp). Otherwise diverged.
  A rating difference alone is never a conflict.
- **Refusals:** `apply` throws before writing anything when the Q397 first-import stamp is not set
  for the live store, or when more than 20 old-only phone notes predate S.
- **Files:** `merge-report.txt` (counts and ids only) and `merge-undo.json` (the before/after
  values of every changed field and enhancement, plus inserted ids). `DevEraMerge.unmerge` replays
  the journal: inserted notes go to the trash, inserted enhancement rows are deleted, changed rows
  get their before values back; a row edited again since the merge is left alone and listed. The
  undo file holds note text, so it stays on the Mac next to the report and is never pasted.
- The old store is opened only as a copy (`openOldStoreCopy`, CloudKit off); the files in
  `merge-from-dev/` are never opened.
- **Trash:** old `deletedAt` > S, Production alive and not touched since (`lastEditedAt`, `keptAt`
  both earlier) = copy `deletedAt` + `trashSeenAt`. Old alive with `keptAt` > S and after
  Production's pre-S `deletedAt` = a Mac restore, copied. Anything else that differs = diverged.
- **`keptAt`:** the later one wins (it only delays fading).
- `editedAt` (not `lastEditedAt`) is the signal: `lastEditedAt` falls back to `createdAt`, which
  would make every note created after S look edited.
- "Phone note after S" uses `addedAt` (`createdAt ?? recordedAt`), not `recordedAt`: an imported
  old video keeps its filming date in `recordedAt` and would otherwise count as "before S".

`MemoEnhancement`, per `memoID` of a note in the merged result: take the newest row on each side
by `enhancedAt`. If Production has none, insert the old one. If both exist, the newer `enhancedAt`
wins and is written into the Production row in place, so no second row appears. A tie keeps
Production. `processedAt` takes the later non-nil value. This matches the write-back's own rule
(`MacCloudWriteBack.swift`: LWW, never clobber a strictly newer other-device write).

`MemoEditHead`: none in the old store (the Aug schema has no such model). `NamesRecord`,
`VocabularyRecord`, `PolishPromptsRecord`: not copied, as explained in "The approach", step 4.

## Step order

Gate rule: a step that fails its check stops the sequence. Nothing later runs.

| # | Who | Step | Check |
|---|---|---|---|
| 0 | agent | Land A1–A4 and Q298's prerequisites. Build the Release Mac with the Production pin, A1 and A4. Don't install it. | Unit tests green. `mac-store-copytest.sh --self-test` and the A3 self-test print PASS. |
| 1 | Tuur | Confirm the facts F1 and F2 below. | F1 shows `aps-environment development` and no `icloud-container-environment`. |
| 2 | Tuur | Deploy the Production schema (RELEASE.md, "CloudKit console steps", Q298). | Production shows `CD_MemoEditHead` and `CD_Memo.CD_includeAudioInExport`. |
| 3 | Tuur | **Freeze the Mac:** quit Skrift on the Mac and don't open it again until step 9. Keep using the phone. | `pgrep -x Skrift` prints nothing. |
| 4 | Tuur | **Back up:** copy the whole `~/Library/Application Support/Skrift/` folder and `/Applications/Skrift.app` to `~/SkriftBackup-<date>/` (Finder copy is fine). Also run a Time Machine backup if he has one. | The backup folder's size matches the original. |
| 5 | Tuur | Run `plan/release/mac-store-copytest.sh` (Q367, existing) on the old store. | Exit 0. Note the printed counts as the baseline. |
| 6 | Tuur | Move `memo_cloud.store`, `memo_cloud.store-wal`, `memo_cloud.store-shm` and `.memo_cloud_SUPPORT` from the app folder into `~/Library/Application Support/Skrift/merge-from-dev/` (A4 reads them from there; the step-4 backup is the untouched original). Leave `skrift.store`, `names.json` and `user_settings.json` where they are. Swap in the new Release app (Q370 procedure). Launch it. | The app opens with his notes list (from `skrift.store`). Do not press Yes on the merge alert yet: it must not appear until the first import is done (A1/A4). |
| 7 | Tuur | Let it download. Keep the Mac awake and on power until the sync monitor is idle and the note count stops changing for 10 minutes. Expect a long first import: audio and photos come down as blobs. | Phone notes from after S (up to 11 Oct) appear on the Mac. |
| 8 | Tuur | Quit Skrift. Run `plan/release/mac-store-copytest.sh --merge ~/Library/Application\ Support/Skrift/merge-from-dev` (the dry run). Paste the printed counts to the agent. | All dry-run checks below pass. |
| 9 | agent + Tuur | Agent reads the counts (counts only) and says go or stop. On go, Tuur opens Skrift, checks the alert's numbers match the dry run, and presses Yes. | `merge-report.txt` counts equal the dry run's. |
| 10 | Tuur | Wait for the export (sync monitor idle), then check on the phone: a Mac-made note from after S, a Mac polish of an after-S phone note, a person added on the Mac after S. Then let the Mac run its normal reconcile for a day. | All three present on the phone. No note shows twice on either device. |
| 11 | Tuur | After a week with no surprises, delete `merged-<date>` (the step-4 backup stays). | — |

## Dry run on a copy (A3): what it must check

The run uses two copies in a fresh temp dir: OLD (the moved Dev-era store) and PROD (the
downloaded Production store). It merges into the PROD copy and prints the following, counts only.

| Check | Pass when |
|---|---|
| Notes before: OLD total, PROD total, ids in both, OLD-only (split into Mac-made, phone after S, trashed, phone before S), PROD-only | Printed. "Phone before S, OLD-only" ≤ 20, otherwise stop (Production lacks history). |
| Notes after: PROD-copy total | = PROD before + inserted. |
| Duplicate `Memo.id` groups | After = before in PROD. No new group. Also reported for OLD. |
| Every OLD Mac-made live note | Present once in PROD after. |
| `MemoAsset` rows | Each inserted note has the same asset count and kinds as in OLD; total blob bytes printed. |
| Enhancements: OLD-only, OLD newer, PROD newer, tie | After the merge, every memo in PROD has ≤ 1 enhancement row it did not already have duplicated, and every OLD-only or OLD-newer one is present with OLD's `enhancedAt`. |
| Conflicts (edited on both sides after S) | Printed with ids. Tuur reviews if non-zero. |
| Fields copied onto shared notes | Count per field (rating, title, body, trash). |
| Nothing dropped | No PROD count goes down, including trashed notes (exit 1 otherwise, like Q367). |
| Names and words | Printed for information: people in `names.json` vs the PROD `NamesRecord`, and the merged count `NamesMerge` would produce. Same for custom words. |

## Rollback

- **Before step 9 (no Production write by the merge):** quit the new app, put the Aug app and the
  whole Skrift folder back from `~/SkriftBackup-<date>/`. The Mac is back on Development exactly
  as before. Production only received what a normal client writes (zone subscription and the
  Mac's reconcile of names, words and prompts).
- **After step 9:** `merge-report.txt` lists every inserted note id and every enhancement row it
  changed. An "unmerge" (agent writes it only if needed) trashes the inserted notes by id. It
  restores the changed enhancements from the step-8 PROD copy, which A3 keeps next to the report
  when run with `--keep-copy`. The old store stays untouched in the backup either way, so the merge
  can be rerun after a fix.
- Development is never written by any step, so it remains a complete record of the Mac's side.

## Open risks

| # | Risk | Confidence it is real | Mitigation |
|---|---|---|---|
| 1 | **The fresh Mac store authors twins of every phone note** (`MacMemoAuthor.backfill`, no `isLocalCapture` check, runs while the download is incomplete). | **High.** Read in code. | A1, before step 6. |
| 2 | **Production lacks the phone's pre-S history.** If the new phone's store arrived by device transfer with its Development metadata, the history-token export may never have uploaded old notes to Production (research Q1). Then the Mac's fresh download is missing them, and the phone holds the only live copy. | Medium. Unknown until the dry run. | The "phone before S, OLD-only" count stops the plan. Re-plan if it trips: likely the phone needs its own controlled re-export, a separate plan. |
| 3 | **Deleted notes come back.** A phone note trashed and purged after S is still alive in the old store. | Medium. | The rule never inserts phone-made notes from before S. Phone notes from after S that were purged within days are a small residue: listed, not auto-inserted, if trashed. |
| 4 | Edit conflicts on shared notes (edited on both sides after S). | Low count expected. | Keep Production, list ids for Tuur. |
| 5 | Upload throttling: a few hundred inserts plus their audio blobs at once can trip the CloudKit rate limit for hours (TN3164). | Medium. | Batches of 25 notes per save in A2; the step-10 check waits for idle. |
| 6 | Large blobs: a kept video up to ~200 MB as one `MemoAsset.blob` is unverified through CloudKit (Q287). | Low-medium. | The dry run prints total blob bytes; an outlier gets checked by hand before Yes. |
| 7 | Mac push delivery on Production: a development-signed build still carries `aps-environment development`, so pushes may not arrive. Sync then happens on launch or activation only. | Medium. | Step 7 and 10 wait for idle with the app frontmost; not a data risk. |
| 8 | Names: a person deleted on one side more than 90 days ago lost their tombstone and could come back; custom words merge as a union, so a word deleted on one side since S comes back. | Low. | Tuur glances at the people and words lists after step 10. |
| 9 | A step done out of order (the new app launched with the old store still in place). | Low with this sheet, high impact. | Step 6 moves the store before the swap; Q370's checklist links here. |

## Facts to confirm first (Tuur, read-only)

- **F1** `codesign -d --entitlements :- /Applications/Skrift.app`: confirm `aps-environment`
  `development` and no `icloud-container-environment` (the Q388 next step). If it says Production,
  the split has another cause: stop.
- **F2** How the iPhone 17 Pro got its notes: Quick Start or backup transfer (local store copied)
  versus a clean install that downloaded from Production. A transfer makes risk 2 likely. A clean
  install means Production already holds his phone history.
- **F3** (optional) CloudKit Console, Production, `iCloud.com.skrift.mobile`, Data > Records,
  query `CD_Memo` sorted by `CD_recordedAt`: is there a note from before S at all? If not, risk 2 is
  confirmed before any build.

## Optional experiment (not required)

To learn what the container really does on an environment switch, run a synthetic store through
Development then Production in the **Dev** container `iCloud.com.skrift.mobile.dev`. That needs
the Dev container's schema deployed to Production, which is a one-way CloudKit write. The plan
above does not depend on the answer.
