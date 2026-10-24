# What a CloudKit-backed SwiftData store does to local rows on an iCloud account change

Researched 2026-10-24. Nothing here was tested on a device. No source is specific to iOS 26/27 or macOS 26; the newest Apple statements are from Dec 2025 (iOS 18 era) and June 2026. Most sources describe Core Data's `NSPersistentCloudKitContainer`. Two Apple replies (805940, and the OP's test in 811294) cover SwiftData + CloudKit and report the same behaviour.

Key: **[Apple]** = Apple engineer or DTS reply, or Apple docs. **[dev]** = a developer's report or blog.

## 1. Does the mirroring delegate purge local objects? Including never-exported ones?

What we saw: the question is whether a sign-out or account switch deletes Memo rows on the device.

What others found:
- **[Apple]** DTS (Ziqiao Chen): the container "wipes off the Core Data store on the device" when the user logs out of iCloud. Nothing is lost if the data reached CloudKit, because it downloads again when the same account signs back in. Access control is the reason: only the account that was signed in when the store was created may read it. https://developer.apple.com/forums/thread/764080
- **[Apple]** DTS, SwiftData specifically: the framework deleting local data when iCloud is turned off for the app is intentional. https://developer.apple.com/forums/thread/805940
- **[Apple]** DTS: "as-designed", done for privacy, and no API exists to configure it. https://developer.apple.com/forums/thread/766668
- **[Apple + dev]** Never-exported rows are deleted too. The OP tested Core Data and SwiftData on iOS 18: saved but unsynced changes (export throttled, app force-quit) were wiped and lost. An Apple Frameworks Engineer replied "This is by design" and offered no fix inside the container. Their only suggestion was to move to `CKSyncEngine`. https://developer.apple.com/forums/thread/811294
- **[dev]** The wipe is the whole store. Fatbobman (2022) says the container clears "all data associated with the account on the device upon restart", using its sync metadata tables to decide. https://fatbobman.com/en/posts/real-time-switching-of-cloud-syncs-status/
- **[dev]** Quentin Zervaas (2022) saw users' data vanish and come back up to a day later, when iOS falsely reported no iCloud access. https://crunchybagel.com/nspersistentcloudkitcontainer/
- **[dev]** A SwiftData app with full iCloud storage saw false "iCloud unavailable" reports erase local data. DTS answered with a sysdiagnose request, not a fix. https://developer.apple.com/forums/thread/771870

The fix or workaround: none inside SwiftData or the container. Apple points to `CKSyncEngine` (811294).

Our next step: treat every row that has not been exported as at risk the moment the account changes.

## 2. Signed out vs switched account vs app toggle off vs iCloud Drive off

What we saw: there are four user actions, and they may behave differently.

What others found:
- **[Apple]** Turning off iCloud for the app "is equivalent to signing out of the account." https://developer.apple.com/forums/thread/811294
- **[Apple]** DTS: switching users and turning off iCloud are treated the same way "as far as I know". https://developer.apple.com/forums/thread/766668
- **[dev]** A switch to a different Apple ID logs `NSCocoaErrorDomain Code=134405` with `PFCloudKitOldUserIdentityKey` / `PFCloudKitNewUserIdentityKey` and `Sending 'NSCloudKitMirroringDelegateWillResetSyncNotificationName' with reason: 'AccountChange'`. No reply on the thread, and it doesn't say what happened to the rows. https://developer.apple.com/forums/thread/675490
- **[dev]** iCloud Drive must be on, as well as being signed in, or setup fails with 134400. https://developer.apple.com/forums/thread/119457
- **[Apple doc]** `NSUbiquityIdentityDidChange` fires on sign-in, sign-out, and when "syncing of documents and data" is turned on or off. https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/nsubiquityidentitydidchange
- Not found: whether turning off iCloud Drive alone triggers the purge, or only blocks setup.
- Not found: any Mac-specific difference.

The fix or workaround: assume all four lead to a purge.

Our next step: test the iCloud Drive toggle alone on the Dev build with a throwaway Apple ID.

## 3. Signals before or after, and can rows be copied out first?

What we saw: we want to know what the app can observe and whether it can save rows before the purge.

What others found:
- **[Apple]** By the time the app learns of the transition, sync "will just fail with `CKErrorNotAuthenticated`". So a last export is not possible. https://developer.apple.com/forums/thread/811294
- **[Apple]** DTS: checking `CKContainer.accountStatus` at launch and opening the store with `cloudKitDatabase: .none` when the account isn't `.available` is "fine". During a session the only signal is `CKAccountChanged`, and the container "may still erase the data before you release the current model container". https://developer.apple.com/forums/thread/771870
- **[Apple]** DTS also warns that opening an existing CloudKit store without CloudKit drops access control, so a new user can see the old user's data. https://developer.apple.com/forums/thread/764080
- **[Apple doc]** `CKAccountChanged` is posted on an arbitrary queue and has no detail; call `accountStatus` afterwards. https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/ckaccountchanged
- **[Apple doc]** `.temporarilyUnavailable`: "Don't delete any cached data". Wait for `CKAccountChanged` to report `.available`. https://developer.apple.com/documentation/cloudkit/ckaccountstatus/temporarilyunavailable
- **[Apple doc]** `NSUbiquityIdentityDidChange` is "Sent after" the change. Compare `FileManager.ubiquityIdentityToken`, which is nil when signed out or disabled. https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/nsubiquityidentitydidchange
- **[dev]** Fatbobman says the clear happens "upon restart", and that an app running during the change is restarted. https://fatbobman.com/en/posts/real-time-switching-of-cloud-syncs-status/
- `eventChangedNotification`: no source shows an account-change event type. The documented types are setup, import and export. The signs found are a setup error with 134400 when there is no account (119457) and the 134405 reset log above (675490).
- **[Apple doc]** `CKSyncEngine` sends an explicit account-change event with `previousUser` / `currentUser` and leaves local deletion to the app. https://developer.apple.com/documentation/cloudkit/cksyncengineaccountchangeevent
- `fetchUserRecordID`: no source found covering it for this case. Storing the user record ID and comparing it at launch is our idea, not a documented recipe.

The fix or workaround: the one window found is app launch, before the `ModelContainer` is built. Check `accountStatus` and the identity token against the last known value, and copy the store files aside if they differ. No source confirms the purge always waits for that load. DTS calls the mid-session case a race.

Our next step: put the identity check and a store-file copy before `ModelContainer` creation, then test it with a sign-out on the Dev phone.

## 4. After a purge and sign-in to a new account, is what's left re-exported?

What we saw: we want to know whether the new account receives the local rows.

What others found:
- **[Apple]** Data comes back only for the same account (764080).
- **[Apple]** Export is driven by persistent history. Rows with no history entry are invisible to the container, "by design". https://developer.apple.com/forums/thread/120328
- **[Apple]** In the `cloudKitContainerOptions = nil` toggle case, DTS believes sync resumes "assuming that the data belongs to the orignal user", and isn't sure that's current behaviour (764080).
- **[dev]** Sync resumes on its own once the account is signed in. https://fatbobman.com/en/posts/coredatawithcloudkit-4/
- Not found: any source on whether rows that survive (or rows created while signed out) are exported into a different Apple ID after an `AccountChange` reset.

The fix or workaround: not found.

Our next step: test it on Dev: account A → sign out → create a note → sign in as B → check B's zone in CloudKit Console.

## 5. Error codes: quota full and not signed in

What we saw: we want to know whether the export event's `error` carries `quotaExceeded` and `notAuthenticated`.

What others found:
- **[Apple]** Quota full: DTS calls it a known issue. The quota error is nested in a partial failure, and the container doesn't fill `partialErrorsByItemID` on the `Event.error` from `eventChangedNotification`. DTS suggests writing a test record with CloudKit directly to detect it. https://developer.apple.com/forums/thread/840348
- **[dev]** Logs from that thread: the save shows `"Quota Exceeded" (25/2035)` with "Retry after 316.0 seconds". The mirroring error wraps `CKErrorDomain Code=2` (partialFailure). (840348)
- **[Apple]** A Frameworks Engineer (June 2026) expects the notification to carry the full payload including `CKPartialErrorsByItemIDKey`, and treats its absence as a bug (FB13773922, open). Events fetched with `NSPersistentCloudKitContainerEventRequest` "will only include the domain / code". https://developer.apple.com/forums/thread/830420
- **[dev]** Zervaas saw `.partialFailure` instead of `.quotaExceeded` and used a test `CKRecord` write as a probe (crunchybagel, above).
- **[dev]** Not signed in, at setup: `NSCocoaErrorDomain Code=134400 "Unable to initialize without an iCloud account (CKAccountStatusNoAccount)."` (119457). A variant says `CKAccountStatusTemporarilyUnavailable`. https://developer.apple.com/forums/thread/729924
- **[Apple]** Not signed in, mid-transition: sync fails with `CKErrorNotAuthenticated` (811294). Not found: whether that arrives as the top-level export `Event.error` or wrapped in a partial failure.

The fix or workaround: for quota, use `CKError.partialFailure` (code 2) on an export event as a hint and confirm it with a direct CloudKit probe. For no account, use `accountStatus`, not the event.

Our next step: log `(error as NSError).domain/code/userInfo` for every failed export event in DevLog so the real shape is on record.

## What this means for an app that wants to say "nothing here was deleted"
1. Apple says the purge is by design and can't be configured. It includes saved rows that never exported, so the app can't promise that unexported rows survive an account change.
2. The only window found is before the `ModelContainer` loads at launch: detect an identity change, then copy the store aside. Mid-session, DTS calls it a race.
3. Show "safe" only for rows that have been exported. Quota-full exports hide their reason (partialFailure with no per-item errors), so treat any failed export as "not safe yet".

## Things to try first
1. Before `ModelContainer` creation, compare `accountStatus` and `ubiquityIdentityToken` with the stored value, and copy the store files aside on any change.
2. Run the Dev-phone account-switch test from section 4 to settle re-export and what is left after the purge.
3. Record the full export-event error (domain, code, userInfo) in DevLog to see the real quota and not-authenticated shapes.
