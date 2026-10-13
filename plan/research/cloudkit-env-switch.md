# CloudKit environment switch: one local store, Development → Production

Researched 2026-10-13 for Q393 (D203). Web research plus code reading only. No real store, no
CloudKit, no prod app was opened. Feeds `plan/release/ICLOUD_MERGE.md`.

The question: the prod Mac's `memo_cloud.store` has mirrored the **Development** environment of
`iCloud.com.skrift.mobile` since August. The next Mac Release build is pinned to **Production**
(Q388, `SkriftDesktop.entitlements`). What does SwiftData / `NSPersistentCloudKitContainer` do
when that same store file is opened by a build pointed at the other environment?

**Short answer: nobody documents it, and the reports that exist disagree. Do not let it happen to
the real store.** The plan moves the old store aside and copies its extra rows in at app level.

## What is documented

1. **SwiftData sync is `NSPersistentCloudKitContainer`.** Apple DTS (Ziqiao Chen), Jun 2025:
   "today's SwiftData + CloudKit uses NSPersistentCloudKitContainer under the hood."
   https://developer.apple.com/forums/thread/787019
   Everything below about Core Data mirroring applies to our `ModelConfiguration(cloudKitDatabase:
   .private(...))` stores (phone `NotesRepository.swift:34`, Mac `MemoCloudContainer.swift:94`).

2. **Export is driven by persistent history since the last exported token.** TN3163 shows the
   exporter logging `Exporting changes since (0): <NSPersistentHistoryToken …>` and then
   `Found 0 objects needing export.`
   https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer
   DTS, Sep 2024: "`NSPersistentCloudKitContainer` relies on the history to figure out the changes
   on the store since last export." https://developer.apple.com/forums/thread/764080
   Consequence (my inference, medium confidence): if the mirroring metadata survives the switch,
   rows already exported to Development are **not** exported again to Production. Only changes made
   after the switch go up.

3. **The user identity is the same in both environments.** Apple staff, Jan 2016: "the identifiers
   for a given user are identical between Production and Development containers, so it will remain
   unchanged after updating the entitlement." https://developer.apple.com/forums/thread/28387
   Consequence (inference, medium): the switch should not trigger the `AccountChange` reset, which
   keys on the user identity (see 6).

4. **What Apple says the switch looks like to an app.** Same 2016 post, for the private database:
   "fixing the entitlement will behave as if the user database was empty. Depending on how the app
   handles such behavior, this might result in users losing data (if there's no local cache or the
   "truth" is aways stored in CloudKit rather than locally) or it might be transparent (if the
   "truth" is the local data and the app pushes its local state to CloudKit)."
   This is about apps that push their own state. It says nothing about whether
   `NSPersistentCloudKitContainer` pushes local state; see 2 for why it may not.

5. **On iCloud sign-out the container wipes the local store.** DTS, Sep 2024: "it wipes off the
   Core Data store on the device when it gets notified that the user logs out iCloud. (This doesn't
   lead to data loss, because NSPersistentCloudKitContainer downloads the data from CloudKit when
   the user logs back in with the same iCloud account.)" https://developer.apple.com/forums/thread/764080
   Also https://crunchybagel.com/nspersistentcloudkitcontainer/ section 10: "NSPersistentCloudKitContainer
   will remove the data", "intentional behaviour, intended as a privacy feature."
   For us that "no data loss" premise fails: Mac-only rows live in Development, which a Production
   build can never download.

6. **Resets exist and carry a reason.** Logs from forum reports:
   - `Error Domain=NSCocoaErrorDomain Code=134405 … PFCloudKitOldUserIdentityKey=_XXX,
     PFCloudKitNewUserIdentityKey=_YYY, NSCloudKitMirroringDelegateResetSyncReasonKey=3` then
     `Sending 'NSCloudKitMirroringDelegateWillResetSyncNotificationName' with reason: 'AccountChange'`
     (a seeded store opened under another account, Mar 2021). https://developer.apple.com/forums/thread/675490
   - `NSCloudKitMirroringDelegateWillResetSyncNotificationName reason: 'ZoneDeleted'` after
     `"Zone Not Found" (26/2036)`, "followed by a full mirroring reset." https://developer.apple.com/forums/thread/822382
   No Apple page lists the reasons or says what a reset does to local rows.

7. **A zone deleted behind SwiftData's back comes back.** A developer deleted the zone with
   `modifyRecordZones`; it "reappears after SwiftData/CloudKit sync or app restart." Apple Frameworks
   Engineer, Dec 2025: "You would need to mark the zone as user-purged for the DefaultStore to obey
   an out of band delete." https://developer.apple.com/forums/thread/809726
   Read with 6: after a `ZoneDeleted` reset the store recreates the zone and, by the poster's
   account, its records. Low-medium confidence that records go back up, and under which record names.

8. **Record identity is not our UUID.** `NSPersistentCloudKitContainer` "doesn't support unique
   constraints today. To make sure that a record is unique across devices, you need to implement
   your own mechanism." (DTS, Feb 2022) https://developer.apple.com/forums/thread/699634
   A store copied so its objects lose their CloudKit metadata gets every server record downloaded
   again next to them: "the existing objects are re-downloaded to the device. This effectively
   duplicates all of the records." Apple's fix there: use `replacePersistentStore`, not
   `migratePersistentStore`. (Jul 2020) https://developer.apple.com/forums/thread/653975
   So two rows with the same `Memo.id` but different CloudKit records are what a botched
   re-upload produces. Our readers tolerate them (`MemoDuplicates.swift`), but the phone heals only
   exact clones (`MemoDeduper.swift`); divergent pairs stay forever by design.

9. **Bulk writes get throttled.** TN3164: "populating a large dataset in a short time frame to your
   Core Data store may trigger rate limit throttles … The expiration time can be hours."
   https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer

## What developers saw when they did exactly this (install a Production build over Development data)

| Report | Outcome |
|---|---|
| https://developer.apple.com/forums/thread/728475 (Apr 2023) | TestFlight installed over months of Development data: "It is now missing a lot of data that used to be on that device." Sync then broke for the Xcode build too. Community advice: "When ever I detect a change of deployment type … I nuke my local core data database and let it rebuild from CloudKit. While you can replicate the data in both development and production containers, it probably won't be 'auto-magic'." |
| https://developer.apple.com/forums/thread/763062 (Aug 2024, SwiftData) | TestFlight installed over the Xcode build: "all the meetings show up" locally. A clean TestFlight install shows none of them: "it's as if there are 2 Containers, one for Development and one for Production … not sync'd with each other." |

No Apple staff answer in either thread.

## The four questions

| Question | Answer | Confidence |
|---|---|---|
| Does it re-export all local records to the new environment? | Not documented. If metadata survives: no, export is history-token driven (2), so old rows stay local-only. If a reset fires (6, 7): it may re-upload, possibly under new record names. | low |
| Does it keep or reset its mirroring metadata and history tokens? | Not documented. The user identity is unchanged (3), so no `AccountChange` reset is expected. The stored server change token belongs to Development; what Production does with it is unknown (a token-expired or zone reset is plausible). | low |
| Does it create the zone fresh? | In Production the zone `com.apple.coredata.cloudkit.zone` already exists if any Production build (the TestFlight phone) has synced. A store that finds its zone missing recreates it (7). | medium |
| What happens to records already in Production with the same ids? | CloudKit dedupes by record name only, never by `Memo.id` (8). If the Mac re-uploads under the record names it learned in Development and the phone re-uploaded the same records under the same names, the server sees one record (a change-tag conflict). If either side minted new names, every shared note becomes two rows with one `Memo.id`. | low |

Two outcomes have actually been reported: local rows silently kept but never uploaded (763062), and
local rows lost (728475). Both are bad for us. The first leaves Mac-only notes stranded on the
Mac. The second deletes them.

## What this means for Skrift (code facts, read 2026-10-13)

- **Never open the old Mac store with a Production-pinned build.** The Release app opens
  `AppPaths.memoCloudStoreFile` unconditionally (`MemoCloudContainer.swift:94-99`). Installing build
  188+ over the August app does the uncontrolled switch on first launch. The old store family must
  be moved out of `~/Library/Application Support/Skrift/` before that launch.
- **A fresh Mac store plus the current reconcile makes duplicates.** `MacMemoAuthor.backfill`
  (`MacMemoAuthor.swift:225`, called from `MemoCloudReconciler.swift:362` on every reconcile) authors
  a NEW `Memo` for every local `PipelineFile` with a UUID id and no `Memo` in the cloud store yet.
  It does not check `isLocalCapture`. Phone-made rows have `id` = the phone's `Memo.id`. While a fresh
  store is still downloading, every one of them looks Memo-less, so the Mac uploads a Mac-shaped twin
  that then collides with the phone's record. This guard must land before any fresh-store launch
  (ICLOUD_MERGE.md, step A1).
- **Our dedupe is by app-level id, and that is enough for an app-level merge.** `Memo.id` UUIDs are
  stable across devices and environments (they are a SwiftData property, not the record name).
  `MemoEnhancement` is one row per `memoID`, LWW by `enhancedAt` (`MemoEnhancement.swift`). Names
  merge per canonical with LWW plus union of voice embeddings, with tombstones kept 90 days
  (`NamesData.swift:170`, `NamesStore.swift:307`). Vocab merges as a word union
  (`VocabularyCloudSync.swift`).

## Not found

- An Apple statement of what the mirroring delegate stores about the environment, or what it does
  when the environment under a store changes.
- The full list of `NSCloudKitMirroringDelegateResetSyncReasonKey` values.
- Whether record names survive a reset.

The only way to learn these is a write test in a container that does not hold his data (for
example the Dev container `iCloud.com.skrift.mobile.dev` with a synthetic store, Development then
Production). The plan does not need it, so it is listed as optional in ICLOUD_MERGE.md.
