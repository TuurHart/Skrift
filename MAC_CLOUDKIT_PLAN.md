# MAC_CLOUDKIT_PLAN.md — Mac as a CloudKit client of the phone's note store

> **Status:** BUILT (8a–8d) — code-complete on `main`, awaiting the user's Xcode prod-registration
> step + on-device verification (see RESUME). Drafted 2026-06-21; built 2026-06-22. This is "option A"
> from `STANDALONE_PLAN.md` ("Mac → CloudKit client … user-greenlit, AFTER Phases 1–3"), pulled
> forward at the user's request. This doc locks the architecture.

---

## ⭐ RESUME HERE (2026-06-22) — BUILT (8a–8d), awaiting the user's Xcode + device steps

**ALL BUILT + committed + pushed to `main`/origin (commit-per-chunk, each gated green):**
- `845e6bc` **8a-ii — true-share `Memo`/`MemoAsset`/`DeviceID` → `Shared/Model`.** The @Model CORE (+ `SyncStatus`/
  `TranscriptStatus`/`TrashPolicy` enums, `addedAt`/`lastEditedAt`/`markEdited`/`parseTagInput`, internal
  `encode/decodeJSON`) moved to `Shared/Model/Memo.swift` with a **blob-based** designated init (no iOS types).
  iOS coupling lives in `SkriftMobile/Models/Memo+Mobile.swift` (typed `metadata`/`sharedContent` accessors,
  `audioURL`/`sharedFileURL`, `Memo.make(…)`). **Chose `Memo.make` over a convenience init** — a convenience init
  with all-defaulted typed params is *ambiguous* with the blob designated init (Swift overload resolution, not just
  macro friction); the 12 typed call sites use `Memo.make(…)`, metadata-free ones keep `Memo(…)`. `../Shared/Model`
  wired into the desktop `project.yml` (app + UnitTests).
- `add6a23` **8a-iii — `MemoCloudStore`** (`SkriftDesktop/App/MemoCloudContainer.swift`): the 2nd
  `NSPersistentCloudKitContainer` over `[Memo, MemoAsset, MemoEnhancement]`, `.private(iCloud.com.skrift.mobile{.dev})`
  per `#if DEBUG`, separate from the local PipelineFile `SharedStore`. `container: ModelContainer?` — nil under XCTest /
  if it fails to build (→ Bonjour fallback). Lazy + inert until touched. `AppPaths.memoCloudStoreFile` = its own
  dev/prod-suffixed mirror store. Mac device-id = the shared `DeviceID.current()`.
- `a2e831a` **8b — `MemoCloudIngest`** read bridge: synthesizes the phone's multipart parts from the `Memo` + its
  `MemoAsset` blobs and reuses `UploadService.ingest` (parity by construction; trust gate + materialization + field
  reads are the identical code). `UploadService.ingest` gained an optional `memoID` (HTTP default unchanged) so
  `PipelineFile.id == memo.id.uuidString`. Significance>0 gate + dedup (by UUID OR `memo_<uuid>` filename — collapses a
  Bonjour+CloudKit memo to one row). `metadataJSON` rebuilds the upload-metadata shape on the desktop (`.sortedKeys`).
  **10 golden tests** (`MemoCloudIngestTests`).
- `74cb609` **8c — write-back** (`MacCloudWriteBack`): after enhance, upsert a `MemoEnhancement` (copyedit/title/
  summary + provenance) into the CloudKit Memo store — only for a memo that exists there, only when there's content;
  idempotent update-in-place. Hooked in `ProcessingCoordinator.process` + `redo`. `MemoExporter` already PREFERS it.
  **8 unit tests** (`MacCloudWriteBackTests`).
- `fa458df` **8d — reconcile + coexistence + de-Mac Settings.** `MemoCloudReconciler.sweep` (pure, testable) +
  `+Wiring` (launch/active/CloudKit-import triggers, wired in `SkriftDesktopApp`). `AppSettings.cloudKitMacSync`
  (opt-in, OFF default) + `processAllSyncedMemos`; a "Sync" Settings section (snapshot-verified). Phone's LAN "Pair a
  Mac" section demoted to "Mac · local network" with an iCloud-is-primary footer (PairMacView kept as fallback).
  **3 reconciler tests**.

**Gates:** mobile `SkriftMobileTests` 486/486; desktop `UnitTests` 309/309; desktop full
`-skipMacroValidation` build SUCCEEDED. Foundation (entitlements/signing + `MemoEnhancement`) from the prior commits.

**Follow-ups (pushed to origin):** `0040611` write-back also respects the `cloudKitMacSync` opt-in (+ documented the
capture cross-transport dedup limit, see below). `76e3747` **launch-crash fix** — pin the LOCAL `SharedStore`
(`PipelineFile`) to `cloudKitDatabase: .none`. **Durable gotcha:** once the app has the CloudKit entitlement, a
`ModelConfiguration` left at the default `.automatic` resolves to "CloudKit ON" — and `PipelineFile`'s
`@Attribute(.unique) id` is CloudKit-forbidden → `ModelContainer` init fatal-errors on launch. The gates miss it
(in-memory + unentitled test bundle never flip `.automatic`; the build doesn't launch the app). Any SwiftData store
that must stay local under an entitled app needs explicit `.none`. **The fresh Dev build is deployed to
`/Applications/Skrift Dev.app` and launches clean** (verified). `MemoCloudStore` is the only CloudKit container.

**DEVICE-VERIFIED (2026-06-22):** CloudKit-Mac sync enabled on the Dev Mac → **73 phone memos synced down** to the
Mac's CloudKit mirror; the eligible (significance>0, non-trashed) ones ingested into the queue with `id == memo UUID`
(the CloudKit-ingest signature) and `transcribe=done` (trusted transcript accepted, no re-ASR). Desktop **push
registered + 32-byte APNs token** received (`6642af4`). Launch-crash from the entitlement→`.automatic` flip fixed
(`76e3747`). Push registration code: macOS `MacAppDelegate` (`6642af4`); the phone was already fully push-ready since
`53451a6` (2026-06-18). Fresh Dev build deployed to `/Applications/Skrift Dev.app`, launches clean.

**REMAINING — user only:**
1. **Finish one round-trip:** on the Mac, **Process** an ingested memo → it enhances → the `MemoEnhancement` write-back
   syncs back → confirm the phone's Obsidian export uses the polished text (the only end-to-end leg not yet eyeballed).
2. **At prod promotion (Release):** ✅ **Release-config capabilities VERIFIED DONE 2026-06-26** — both
   `com.skrift.mobile` and `com.skrift.desktop` Release configs show iCloud (CloudKit · container
   `iCloud.com.skrift.mobile`) + Push with NO signing warnings (Xcode automatic signing had already
   registered them; the earlier "still to register" note was stale). The ONLY remaining prod-CloudKit
   step is the dashboard: confirm the `MemoEnhancement` record type exists in the **Production**
   environment of `iCloud.com.skrift.mobile` (deploy Dev→Prod if it's only in Development).

**Known limitation (follow-up):** **capture** items (URL/text/PDF shares) dedup across transports only on CloudKit
re-ingest (by `id`), NOT cross-transport — a Bonjour capture upload carries no memo UUID (random id +
`capture_<random>` filename), so the same capture sent via BOTH Bonjour AND CloudKit double-creates a `PipelineFile`.
Audio memos are fully deduped (their `memo_<uuid>.m4a` filename embeds the UUID). The clean fix is an additive contract
change — carry the memo id in the capture upload metadata so the desktop keys the capture on `memo.id` regardless of
transport. Narrow edge (needs both an active LAN pairing AND CloudKit-Mac on for the same capture); deferred.

---

## The problem it solves

Today the phone and Mac talk over **Bonjour + HTTP** (`Services/Sync/MacTransport.swift` ↔
`Server/SyncServer.swift`). The phone uploads a RAW memo; the Mac enhances/links/exports it into the
Obsidian vault. **Three pain points:**

1. **Mac polish never returns to the phone.** The transport only does `uploadMemo` / `listFilenames` /
   `health` + names LWW. The Mac's Gemma copy-edit / title / summary land in the *vault* only — the
   phone keeps showing the raw transcript forever (verified: `Memo` has **no** `enhanced*` fields).
2. **Same-network requirement.** Bonjour needs both devices on the same LAN, app foregrounded, Mac
   server running. CloudKit (already syncing the phone↔iPad in Phase 1) has none of those limits.
3. **Two transports to reason about.** Phase 1 made CloudKit the phone↔iPad spine; the Mac is the one
   participant still on the old wire.

**The fix:** make the macOS app a **CloudKit client of the same `Memo` store** the phone already
syncs. The Mac reads synced raw memos, runs its existing pipeline, and **writes the polished result
back** so it syncs to the phone + iPad. Bonjour stays as an opt-in fallback (byte-compatible, for
non-iCloud users), but CloudKit becomes the default path.

---

## Today's shapes (the two models)

| | Phone `Memo` (`SkriftMobile/Models/Memo.swift`) | Mac `PipelineFile` (`SkriftDesktop/Models/PipelineFile.swift`) |
|---|---|---|
| Role | source of truth (raw capture) | rich **processing** entity (full pipeline state) |
| Identity | `id: UUID` (no `.unique` — CloudKit) | `id: String` (`.unique`); **== the memo UUID** for synced memos |
| Has | transcript, transcriptConfidence/UserEdited/MarkersInjected, significance, tags, title, metadata blob, sharedContent blob, recordingDeviceID, word-timings/diar (as `MemoAsset`s) | everything Memo has **+** `sanitised`, `enhancedTitle/Copyedit/Summary`, `ambiguousNames`, `namePicks`, `compiledText`, `exported`, step states |
| Polish fields | **NONE** | the `enhanced*` cluster |
| Persistence | `NSPersistentCloudKitContainer`, schema `[Memo, MemoAsset, NamesRecord, VocabularyRecord, …]`, container `iCloud.com.skrift.mobile{.dev}` | plain local SwiftData (no CloudKit), **ad-hoc signed** |

The contract spine already aligns them: **`PipelineFile.id == Memo.id.uuidString`** (the upload
reconciles by filename, which embeds the UUID). That single invariant is what makes dedup + write-back
safe regardless of transport.

---

## Architecture fork — RECOMMENDED: Fork A (second `NSPersistentCloudKitContainer` client)

**Fork A — the Mac runs its own `NSPersistentCloudKitContainer` over the SAME `Memo` schema + container.**
SwiftData/CoreData does all the sync; the Mac just reads/writes `Memo` objects. The Mac **keeps
`PipelineFile`** as its processing model and bridges Memo→PipelineFile (read) / polish→Memo (write).

**Fork B — hand-rolled CKRecord bridge.** The Mac talks raw CloudKit (`CKDatabase`/`CKRecord`) and maps
records ↔ PipelineFile manually (like the audiobook raw-CloudKit transport in Phase 1g).

**→ Recommend Fork A.** Rationale:
- The phone already uses `NSPersistentCloudKitContainer`; a second client of the same container is the
  *supported* multi-device pattern and inherits conflict handling, asset (CKAsset) materialization, and
  schema evolution **for free**. Fork B re-implements all of that by hand (the Phase-1g audiobook
  transport needed epoch guards, single-flight reconcile, atomic asset copies — a lot of surface).
- Media already rides `MemoAsset` blobs (Phase 1c) → the Mac gets the `.m4a` + photos automatically,
  no separate asset transport.
- Cost of A: the Mac must **compile the `Memo`/`MemoAsset`/sidecar `@Model`s** and add the CloudKit
  capability. That's the "real change" the plan flagged — addressed below.

Fork B is the fallback only if adopting the SwiftData CloudKit container on macOS proves unworkable
(e.g. schema-sharing friction). Default to A.

---

## What moves where (Fork A model sharing)

The Mac needs the `Memo` schema. `Memo` has two iOS couplings to break:
- `Memo.audioURL` → `AppPaths.recordingsDirectory` (iOS app-container path).
- `Memo.init(recordingDeviceID: DeviceID.current())` (iOS device id).

**Plan:** lift the `@Model` definitions (`Memo`, `MemoAsset`, the names/vocab carrier records, the
diar/word-timing sidecar kinds) into a shared location compiled by both apps — the same mechanism as
`Shared/Naming` + `Shared/Export` (a **source folder**, not an SPM package; ~the established pattern).
The platform-specific bits (`AppPaths`, `DeviceID`) become small per-app providers the model reads
through, OR stay out of the shared model (the Mac resolves audio via its own working-folder path, since
it materializes CKAssets to its own disk). Exact seam is a task-#8 detail; the **principle** is: ONE
`Memo` schema definition, two CloudKit clients — no drift (mirrors the no-drift rule for the engine).

> ⚠️ This is the most invasive part. If sharing the `@Model` is messier than expected, the fallback is a
> Mac-local `Memo` mirror `@Model` with a byte-identical CloudKit schema (CoreData matches on entity
> +attribute names, not Swift type identity) — riskier (manual schema parity) but decouples the apps.
> Decide during task #8 with the code in front of us; default to true sharing.

---

## The two bridges

**Read (Memo → PipelineFile).** Reuse the exact mapping `UploadService.ingest` already does from a
multipart upload (`Pipeline/Ingest/UploadService.swift`): id, filename (`memo_<uuid>.m4a`), transcript
(trusted iff `transcriptUserEdited || confidence ≥ 0.7`), significance, `audioMetadataJSON` verbatim,
`recordedAt`, title, word-timings/diar sidecars. A new `MemoCloudIngest` produces a `PipelineFile` from
a `Memo` + its `MemoAsset`s — the CloudKit analogue of the HTTP upload handler. Because
`PipelineFile.id == Memo.id.uuidString` and `id` is `.unique`, **a memo seen via CloudKit AND Bonjour
dedups to one PipelineFile** → no double-ingest.

**Write-back (polish → Memo).** The Mac's pipeline (`BatchRunner`) produces `enhancedTitle/Copyedit/
Summary` + `compiledText`. To return them, the synced store needs somewhere to put them. Two options:

- **W1 — add `enhanced*` fields to `Memo`** (additive/defaulted → lightweight migration + CloudKit
  additive). Simplest; the phone can show polished text directly.
- **W2 — a new `@Model MemoEnhancement { memoID, copyedit, title, summary, compiledMarkdown,
  enhancedByDeviceID, enhancedAt }`** (loose `memoID` FK, no `@Relationship`) — mirrors the established
  `MemoAsset` sidecar pattern, keeps `Memo.transcript` sacrosanct (RAW stays the source of truth).

**→ Recommend W2.** It keeps the RAW contract clean (the Mac never overwrites the phone's transcript —
it adds a derived sidecar), matches the MemoAsset precedent, and lets the phone adopt the polish at its
own pace. **Integration win:** `MemoExporter` (Phase 2, task #4) prefers the Mac's `MemoEnhancement`
text when present, else the on-device-linked raw — so a paired Mac automatically upgrades the phone's
standalone Obsidian export, with zero phone-UI work required.

> The phone's *visual* presentation of polished text (raw vs polished toggle, the title chooser) is the
> **PARKED** mobile-polish UI (`STANDALONE_PLAN.md` Phase 4). Write-back lands the DATA now; the phone
> can keep showing raw until that UI is designed. Export consuming it is the immediate payoff.

---

## Coexistence with Bonjour/HTTP (no double-processing, byte-compatible)

- **CloudKit is the default ingest path when enabled; Bonjour stays opt-in** (non-iCloud users, LAN-only
  setups). The existing contract (`CAPTURE_CONTRACT.md`, multipart upload, names LWW) is **unchanged** —
  Bonjour code is not touched.
- **Dedup by id** (the `.unique` `PipelineFile.id`) means both paths can see a memo harmlessly.
- **Significance gate respected.** Today Bonjour only sends `significance > 0` ("0 = stays on phone").
  CloudKit syncs *every* memo to the Mac's mirror, so the Mac must **filter to `significance > 0` by
  default** (preserve the user's intent), with an opt-in "process everything synced" Mac setting.
- **Single processor.** Only the Mac enhances (the phone can't). The write-back sidecar carries
  `enhancedByDeviceID` + `enhancedAt`; a second Mac (rare) is LWW. The phone's **on-device name-linking
  (task #3) is deterministic + separate** from the Mac's Gemma polish, so they never fight: linking is
  re-derivable display/export; polish is a Mac-authored sidecar.

---

## ⚠️ The hard manual steps (USER — can't be done from the CLI)

1. **CloudKit capability on the macOS target.** ✅ DONE (Debug). **iCloud → CloudKit** added to `SkriftDesktop`
   declaring `iCloud.com.skrift.mobile.dev` (Debug) / `iCloud.com.skrift.mobile` (Release), per-config, literal
   entitlement values. Release container still to register at prod promotion. (`-allowProvisioningUpdates` registers
   IDs but **cannot add a capability** — the locked lesson.)
2. **Real team signing for the desktop.** ✅ DONE. The main app target now signs with `CODE_SIGN_STYLE: Automatic` +
   `DEVELOPMENT_TEAM: 9W82X49JZS` (`project.yml:53-62`, "Team signing — REQUIRED for CloudKit"); only the host-less
   test bundles keep ad-hoc (so the fast MLX-free loop needs no profile). The `/Applications/Skrift Dev.app`
   local-deploy now ships a signed build (build → quit → `ditto` → open — see `feedback_desktop_dev_deploy`).
3. **Push Notifications on the macOS target.** ✅ DONE (Debug). macOS needs NO `UIBackgroundModes` key (iOS-only) — it
   needs the `aps-environment` entitlement (committed) + `NSApplication.registerForRemoteNotifications()`
   (`MacAppDelegate`, `6642af4`) + the App-ID Push capability (added in Xcode). **Device-verified:** 32-byte APNs
   token on launch. Release App-ID Push still to add at prod promotion. Lazy sync works without it.
4. **CloudKit Dashboard:** the `MemoEnhancement` record type auto-creates in the **dev** environment; at prod
   promotion it needs **Deploy Schema Changes** (same as the Memo/MemoAsset types).
5. Both Mac + phone signed into the **same iCloud account** (single user — confirmed `tiurihartog@icloud.com`).

Dev steps #1–#3 are now DONE (the feature is live on the Dev build). Under tests the code stays inert (CloudKit `.none`
under XCTest; no container = local-only), exactly like Phase 1 before its capability.

---

## Phasing (task #8 sub-steps; commit per chunk, gate each)

- **8a — schema + capability prep.** Share the `Memo`/`MemoAsset`/sidecar `@Model`s to a folder both
  apps compile; add the `MemoEnhancement` sidecar (additive). Desktop `NSPersistentCloudKitContainer`
  wired with CloudKit `.none` under tests. *(Capability/signing = the user's Xcode step.)*
- **8b — read bridge.** `MemoCloudIngest` (Memo + MemoAsset → PipelineFile), reusing the UploadService
  mapping + trust gate; dedup by id; significance filter. Unit-test the mapping vs the HTTP path
  (golden: same PipelineFile from the same memo, both transports).
- **8c — write-back.** `BatchRunner` (or a thin `MacCloudWriteBack`) writes `MemoEnhancement` after
  enhance/compile; `enhancedByDeviceID`/`enhancedAt`. `MemoExporter` prefers it. Unit-test.
- **8d — coexistence + reconcile loop.** Launch/foreground/push-driven reconcile (mirror
  `CloudSyncMonitor`); Bonjour untouched + opt-in; Mac "process synced memos" setting (default
  significance>0).
- **Gate each:** desktop `UnitTests` + full `-skipMacroValidation` build green; phone `SkriftMobileTests`
  green (the shared `@Model` move must keep the phone suite green).

---

## Risks / open decisions (for the user)

1. **Model sharing vs Mac-mirror** (§What moves where) — default: truly share the `@Model`s; fall back
   to a schema-parity mirror only if sharing fights the iOS couplings. *(I'll decide in 8a with code in
   hand unless you want to call it now.)*
2. **W1 vs W2 write-back** — recommend **W2** (sidecar). Confirm or override.
3. **Desktop signing change** (§hard steps #2) — moving the Mac off ad-hoc to team signing is required
   for CloudKit. OK to proceed?
4. **Process-everything vs significance>0** — default to `>0` (today's intent). Confirm.
5. **Retire Bonjour eventually?** Not now — kept as opt-in fallback. Revisit once CloudKit is proven.

## Test plan

- Unit: read-bridge golden (HTTP-ingest PipelineFile == CloudKit-ingest PipelineFile for the same
  memo); write-back round-trip; significance filter; dedup-by-id.
- Device (USER, after capability): record a significant memo on the phone → it appears on the Mac via
  CloudKit (no Bonjour) → Mac enhances → the `MemoEnhancement` syncs back → the phone's Obsidian export
  uses the polished text; the iPad sees it too.
```
