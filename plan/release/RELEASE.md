# Release 188 — promotion sheet (Q366, for Q298 / Q368 / Q369 / Q370)

Nothing here is installed. This sheet lists what the promotion needs from Tuur.

## Version

- Phone: `SKRIFT_BUILD` 187 → **188** (`Skrift_Native/SkriftMobile/project.yml`; app, widget and
  share extension read it). Marketing version stays 0.2.0.
- Mac: `CURRENT_PROJECT_VERSION` 187 → **188** (`Skrift_Native/SkriftDesktop/project.yml`).
  Marketing version stays 0.1.0.

## Release builds (local only, never copied anywhere)

| App | Command (run in the app folder after `xcodegen generate`) | Product | Literal grep |
|---|---|---|---|
| Mac | `xcodebuild build -scheme SkriftDesktop -configuration Release -destination 'platform=macOS' -skipMacroValidation ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -derivedDataPath build-release` | `Skrift_Native/SkriftDesktop/build-release/Build/Products/Release/Skrift.app` (com.skrift.desktop, CFBundleVersion 188) | `Include audio in export` (Q360 MacExportConfirm) 1 hit; `Previous 30 Days` (Q358 MemoDate.bucket) 1 hit |
| Phone | `xcodebuild build -scheme SkriftMobile -configuration Release -destination 'generic/platform=iOS' -skipMacroValidation -skipPackagePluginValidation -derivedDataPath build-release -allowProvisioningUpdates DEVELOPMENT_TEAM=9W82X49JZS CODE_SIGN_STYLE=Automatic` | `Skrift_Native/SkriftMobile/build-release/Build/Products/Release-iphoneos/SkriftMobile.app` (com.skrift.mobile, CFBundleVersion 188, team 9W82X49JZS) | `IPadTabControl` 2 hits; `Previous 30 Days` (Q358) 1 hit |

Both built 2026-10-13 from `wt/Q366`, `** BUILD SUCCEEDED **`, exit 0. Greps use `/usr/bin/grep -a -c`
on the main binary. `ContinueListeningCard` (deleted in Q357) has 0 hits in both binaries.
Swift strings of 15 bytes or fewer are stored inline in code and never grep (`card-unrated` gives 0),
and a case-less enum such as `MacExportConfirm` leaves no type name; grep literals of 16+ bytes.
The phone product is development-signed (`aps-environment` = development); Organizer re-signs for
distribution at archive time.

For the TestFlight upload, archive from Xcode Organizer (Product > Archive on the SkriftMobile
scheme, Release) as usual; this build only proves Release compiles and links at 188.

## Prod baseline

There is no prod tag. The last prod builds found in the history:

| App | Commit | What |
|---|---|---|
| Mac | `e6245caa` 2026-08-14 "Mac prod promoted at last" | the last confirmed swap of `/Applications/Skrift.app`. `c4896c8c` (2026-08-19) staged a later Release "for the prod-idle swap"; no commit confirms that swap happened. |
| Phone | `e915d29b` 2026-08-30, build 170 | Ad Hoc Release for Roksana's iPhone; build 168 (`b46cd5ac`, 2026-08-29) was the last TestFlight archive. Builds 171–187 were Dev builds (D161: build 173 = Skrift Dev). |

`main` (`9aea7014`) is NOT the prod baseline: it already carries the v2 work (Q29 and on).
The field list below is diffed from the older baseline, `e6245caa`, so it is a superset. The CloudKit
console's own Development-vs-Production comparison is the final word.

## Synced fields added since prod (CloudKit container `iCloud.com.skrift.mobile`)

SwiftData mirrors each synced `@Model` as record type `CD_<Model>` and each property as field
`CD_<property>`. A new property is a new CloudKit field and needs a Production schema deploy. A new
value inside an existing field or JSON blob does not.

Synced models (phone `NotesRepository.swift:18`, Mac `MemoCloudContainer.swift:33`): Memo, MemoAsset,
MemoEnhancement, MemoEditHead, NamesRecord, VocabularyRecord, PolishPromptsRecord, and phone-only
AudiobookSyncRecord, AudiobookBookmarksRecord, AudiobookAsset. Local only (no deploy ever):
PipelineFile, MemoEmbedding (`cloudKitDatabase: .none`).

| Record type / field | Type | Added | Deploy? |
|---|---|---|---|
| `CD_Memo.CD_destinationRaw` | String | `37ae2c17` 2026-08-27 (before phone b170) | **yes**, unless Production already has it |
| `CD_MemoEnhancement.CD_processedAt` | Date/Time | `00e67299` 2026-08-26 (before phone b170) | **yes**, unless Production already has it |
| `CD_Memo.CD_includeAudioInExport` | Int(64) (Bool) | Q186 | **yes** |
| `CD_Memo.CD_editVectorData` | Bytes | Q29 | **yes** |
| `CD_Memo.CD_editStampHash` | String | Q29 | **yes** |
| `CD_Memo.CD_polishStampHash` | String | Q38 | **yes** |
| `CD_Memo.CD_replacedAt` | Date/Time | D139 | **yes** |
| `CD_MemoEditHead` (new record type): `CD_memoID` (same type as `CD_Memo.CD_id`), `CD_deviceID` String, `CD_deviceKind` String, `CD_vectorData` Bytes, `CD_baseHash` String, `CD_title` String, `CD_body` String, `CD_tags` (same type as `CD_Memo.CD_tags`), `CD_editedAt` Date/Time, `CD_polishedBody` String | — | Q29, Q38 | **yes** (whole record type) |
| `CD_VocabularyRecord.CD_destinationsEnabled` Int(64), `CD_destinationsModifiedAt` Date/Time | — | Q98 | **yes** |
| `CD_VocabularyRecord.CD_authorName` String, `CD_authorModifiedAt` Date/Time | — | Q158 | **yes** |
| `CD_VocabularyRecord.CD_weatherKey` String, `CD_weatherKeyModifiedAt` Date/Time | — | Q326 | **yes** |
| `MemoAsset.kind` value `thumbnail` | value in existing String field | Q260 | no |
| `MemoAsset.kind` value `video` (movie ≤ ~200 MB in the existing `blob` field) | value in existing field | Q287 | no |
| `Memo.metadataData` JSON keys `bookKind`, `bookURL`, `clipManifest`, `importFileName`, `videoFilename`, `testLibrary`, `mediaSource` | inside existing Bytes blob | various | no |
| `Memo.nameResolutionsData` now synced both ways | existing field, new use | Q116 | no |
| `Memo.remindAt` | existing field, now unused (D185), kept | — | no |
| `AudiobookSyncRecord.blob` keys `kind`, `publishedAt`, `sourceURL`, `site` | inside existing blob | Q352–Q355 | no |
| NamesRecord, PolishPromptsRecord, AudiobookBookmarksRecord, AudiobookAsset | unchanged | — | no |
| Raw audiobook records `ab_<bookID>_*` (`CloudKitAudiobookTransport`) | no new record type or field (Q191 changed only error handling) | — | no |

No synced field or model was removed or renamed (C219 holds).

Not deployable yet: the Q364 "X1 #Index" idea would be a schema change; it is not built.

## CloudKit console steps (Q298, about ten minutes, before the first 188 install)

1. Open https://icloud.developer.apple.com/dashboard, team 9W82X49JZS, container
   **`iCloud.com.skrift.mobile`** (the prod one; Dev builds use `iCloud.com.skrift.mobile.dev`,
   whose schema does not carry over).
2. Schema > Record Types, environment **Development**: check every "yes" row above exists. A field
   appears in the prod container's Development schema only after a development-signed build of the
   prod app saved a record carrying it, so most will be missing. Add each missing one by hand
   (Record Types > `CD_Memo` > Add Field, name and type as in the table; for `CD_MemoEditHead`
   create the record type first). Open question for the first one added: confirm the type SwiftData
   uses by comparing with an existing sibling field (e.g. `CD_Memo.CD_significance` for numbers,
   `CD_Memo.CD_title` for strings, `CD_Memo.CD_createdAt` for dates).
3. Click **Deploy Schema Changes…**. The dialog lists every Development-only change: it must show
   exactly the "yes" rows (plus anything Production lacks from before). Nothing may be deleted.
   Confirm.
4. Switch the environment to **Production** and check `CD_Memo` shows `CD_includeAudioInExport`
   and `CD_MemoEditHead` exists.
5. Only then install 188 on the phone (TestFlight) and swap the Mac (Q370), on the same day.

Doubt to settle in step 1: the Mac prod app is a locally built, development-signed Release.
Neither `SkriftDesktop.entitlements` nor `SkriftMobile.entitlements` sets
`com.apple.developer.icloud-container-environment`; check in the console (Data > Records, query
`CD_Memo`) that his real notes sit in the Production environment where the TestFlight phone writes.

## Open device checks (QUEUE items in state `tuur`) — clear or wave before Q370

| Item | Check |
|---|---|
| Q17 | iPhone: phone call (FaceTime/WhatsApp over Wi-Fi) and force-quit mid-take; take 2 passed, take 1 (call) owed |
| Q63 | Mac typing feel after Q56: headings and links while typing |
| Q64 | iPhone: quick note full screen, ✎ opens a new note, toolbar stays (device: force-quit relaunch, real keyboard/dictation, first location prompt) |
| Q221 | camera pinch zoom compounds; a media-services reset brings the Bluetooth mic back |
| Q272 | (done 2026-10) Q187/Q185 look picks glanced on Dev — listed in the brief, already closed |
| Q280 | phone list header Import/Record/New-note row + filter date picker (compile-checked only) |
| Q281 | share a voice memo, video, URL and photo into the phone: share cards unchanged (compile-checked only) |
| Q302 | Dev Mac: custom word, person and polish prompt from the phone arrive; a deleted note disappears |
| Q304 | Dev Mac: ⋯ > Add recording appends audio and words; phone shows the same after sync |
| Q309 | Mac + iPad: ⌘N, ⇧⌘N, ⌘F in and outside a note, ⌘1/⌘2; File > New Window gone — OK? |
| Q311 | phone (Dev 177+): add a recording to a voice note, play across the join, karaoke stays in time |
| Q375 | Library tab on Dev: shelf, podcast link, PDF share + reader, send to a note, jump back |
| Q335 | (stuck, after release) real Mac: Full Disk Access, Import > Apple Notes…, report the start screen |

Promotion gates still open: Q367 (store copy-test script), Q368 (Mac upgrade on a copy of the real
store), Q369 (D186 perf re-run on phone and Mac; a miss blocks promotion), Q298 (the console steps above).

## Known unverified behaviours (from `plan/RUN.md` findings)

Data and sync, highest risk first:
- Q287: a ~200 MB `MemoAsset.blob` (plain Data, not external storage) for a kept video is untested
  through SwiftData/CloudKit on a device (memory).
- Q29/Q38: edit-conflict prompt/banner never rendered; a Mac title-only edit may count as a polished edit.
- Q338: old idea/inspiration/project destinations rewrite to Portfolio + tag on first open — device-owed.
- Q98, Q326, Q302: real CloudKit round trip of the destinations switch, the weather key and the
  refactored cloud adapters unverified.
- Q364: Mac background ingest + lifecycle hand-off unverified on a real Dev Mac (→ Q369).
- Q336: Fill/Remove of the 2,000-note test library and its sync unverified live.
- Q163: hardware kill / disk-full during a recording unverified.
- Q191: tolerant unknown-item handling untested against real CloudKit.

Phone, on device:
- Q164: mic path device check owed. Q299: FeedbackKit audio interplay. Q220/Q311: append audio.
- Q231: widgets + share sheet. Q232: Live Activity on Lock Screen + Dynamic Island.
- Q94/Q134/Q135/Q132/Q150: real Signal/WhatsApp shares, GIF/PNG shares, AirDrop bursts.
- Q353: live podcast MP3 download (redirecting enclosures). Q354: PDF selection handles + share route.
- Q355: Safari share-sheet frame (XCUITest cannot reach Safari's Share button on iOS 27).
- Q359: press-drag of an inline photo. Q382: edge-swipe back. Q329: typing in a quote, caret scroll.
- Q273: real AVPlayer jump-back path. Q173: onboarding flow. Q317: Books tab never rendered.
- Q380: phone now styles fences + block quotes, unseen on screen.

Mac, in the live app (no Mac UI tests from agents):
- Q360: new editor (format commands, MacExportConfirm) never driven live. Q386: header with the
  fading line below never rendered. Q361/Q363: list invalidation and typing feel unverified in-app.
- Q290/Q304: Add recording end to end. Q328: recorder popover anchoring. Q327: sync monitor
  states. Q325: Quick Look Markup. Q342: feedback bubble. Q166: map gesture clear. Q125/Q126: ⌘F
  and typing eyeballs. Q112: NSTextView quote-guard delegate path.
- Q333/Q337: Apple Notes import against a real NoteStore (needs Full Disk Access → Q335).
