# Handoff — finish Bonjour removal (mobile) + live bidirectional sync

Written 2026-07-06 at the end of a long session. On `main`, 14 local commits (not pushed).
Prereq reading: `backlog.md` "⭐ CloudKit-only sync epic", plan `~/.claude/plans/do-all-the-work-lively-sedgewick.md`.

## ✅ STATUS — both parts done in code (updated 2026-07-06, later session)

- The **14 commits were already pushed** (a later push; `origin/main` had them).
- **Part A — DONE + pushed** (`0dab500` on `main`): mobile Bonjour code deleted (~1700 lines),
  onboarding/Settings/list de-Mac'd, per-memo sync pill removed, docs + roadmap updated, build 28→29.
  Verified: build ✅, 481/481 mobile unit tests ✅.
- **Part B — BUILT + UNIT-TESTED (device round-trip OWED)**: live bidirectional edit sync,
  desktop-only (the phone already edits/consumes `MemoEnhancement`). Mac→phone =
  `App/MacCloudEditSync.swift` (debounced write-back off `NoteBody`/`NoteProperties` edits) +
  `MacCloudWriteBack.upsert(bodyOverride:)` + `Sanitiser.unlinkToSpoken`. Phone→Mac =
  `Pipeline/Ingest/MemoCloudUpdate.swift` + `MemoCloudReconciler.sweep` (`SweepOutcome`) +
  `PipelineFile.syncedSourceEditedAt` watermark + wiring re-export. Policy: **re-link + recompile,
  NO LLM re-enhance** (user call). Verified: desktop UnitTests ✅ (324), desktop app build ✅,
  mobile build ✅. **⏳ The only thing left is the two-device CloudKit round-trip on real hardware
  (see "Verify (device)" below).**

## Where we are
The **CloudKit-only sync epic is functionally done and device-verified** (names, vocab, memo
round-trip all sync phone↔Mac over CloudKit with Bonjour off). **Desktop Bonjour is fully deleted**
(commit `510ad0c`, 312 tests green). Two things remain:

- **A. Delete the MOBILE Bonjour code** (dead + gated off since Phase 3 — safe cleanup).
- **B. Live bidirectional editing** — the "edit anywhere → syncs everywhere" feature the user wants.
  This is the real net-new work.

Deployed now: **Mac Dev** (latest, Bonjour server deleted) + **phone build 28**.

---

## Part A — delete the mobile Bonjour code

All of this is **dead code** (Phase 3 gated it off; the user runs CloudKit-only), so deletion can't
regress a live path. Verify with `xcodebuild test -scheme SkriftMobile -destination 'platform=iOS
Simulator,name=iPhone 17'`.

**DELETE these files** (`Skrift_Native/SkriftMobile/`):
- `Services/Sync/MacDiscovery.swift`, `Services/Sync/MacTransport.swift`,
  `Services/Sync/NamesAutoSync.swift`, `Services/Sync/SyncCoordinator.swift`,
  `Services/Sync/UploadPayload.swift`, `Services/Sync/BonjourFallback.swift`,
  `Services/MacConnection.swift`, `Features/Settings/PairMacView.swift`,
  `Services/NamesSync.swift` (the Bonjour `NamesSync` + `NamesTransport` +
  `URLSessionNamesTransport`; **`NamesMerge` is NOT here — it's in `Shared/Naming/NamesData.swift`, KEEP it**).
- Tests: `SkriftMobileTests/SyncTests.swift`, `SkriftMobileTests/NamesAutoSyncTests.swift`.

**EDIT these (real changes, need judgment):**
- `Features/Onboarding/OnboardingView.swift` — has a **Mac-pairing step** (`MacDiscovery()`,
  `MacConnection.load()`, "Connected · host"). Remove that onboarding step entirely (CloudKit needs
  no pairing; the "signed into iCloud" state is the implicit connection).
- `Services/Export/PublishCoordinator.swift:38` — `isMacPaired: { MacConnection.load() != nil }`.
  Decide the new meaning: there's no LAN pairing anymore. Likely drop the `isMacPaired` gate (Obsidian
  publish shouldn't depend on a paired Mac) or key it off CloudKit availability. Read the coordinator.
- `Services/Diarization/VoiceEnroller.swift:34` — `NamesAutoSync.kick()` → replace with
  `NamesCloudSync.run(NotesRepository.shared)` (push the new voiceprint to CloudKit immediately).
- `Models/MemoDisplay.swift:85` — remove the `BonjourFallback.isEnabled &&` guard in `statusKind`.
  Bonjour is gone, so the per-memo waiting/synced pill (Bonjour-era) should not show — return `nil`
  for the sync dimension, keep `transcribing`/`error`. (Global "Syncing with iCloud…" chip stays.)
- `Features/MemosList/MemosListView.swift` — remove the `runSync()` Bonjour branch + the "Pair a Mac
  in Settings to sync" banner (both already gated behind `BonjourFallback`). Pull-to-refresh can
  trigger a CloudKit reconcile (`NamesCloudSync`/`VocabularyCloudSync`/`AssetMaterializer` — the
  `.refreshable` already calls these) or become a no-op.
- `Features/Settings/SettingsView.swift` — delete the (already-gated) Pair-a-Mac "Connection" section.
- `App/LaunchArgs.swift` — remove any `-mockMac` / `-seedDiscoveredMacs` flags if present.
- Comments only (no logic): `Services/Capture/CaptureDictation.swift:15`,
  `Services/NotesRepository.swift:50` mention `SyncCoordinator` — reword.
- Fix any UI tests that reference the removed types (`SettingsUITests`, `OnboardingUITests`) and
  incidental references in `NamesTests`/`TrashTests`/`CaptureUploadTests`/`QuoteCaptureSaveTests`.

**BUILD GOTCHA (learned on the desktop half):** after deleting files, remove the matching
`- path: <dir>` from `project.yml` if a whole dir empties, then `rm -rf SkriftMobile.xcodeproj &&
xcodegen generate`. A stale `- path:` → "missing source directory"; a leftover file ref → "Build
input files cannot be found". `Services/Sync/` still has kept files, so its path stays.

Then update docs: `CLAUDE.md` (Mobile↔Mac contract → CloudKit, not the HTTP multipart spine),
`FEATURES.md` (Bonjour rows → removed), `Skrift_Native/CAPTURE_CONTRACT.md`, `SKRIFT_SOURCE_OF_TRUTH.md`.
And ask Huginn to flip the roadmap (`Stz020` + a "Bonjour retired" node).

---

## Part B — live bidirectional editing ("edit anywhere → syncs everywhere")

**Problem.** Today it's a **one-shot pipeline**: phone records → Mac ingests once (`MemoCloudIngest`,
dedups) → processes → writes polish back ONCE (`MacCloudWriteBack.upsert`, fired only from
`ProcessingCoordinator.process`/`redo`). After that:
- A **manual edit on the Mac** (note body / title / summary) does NOT propagate to the phone.
- A **later edit on the phone** to an already-processed memo doesn't re-reach the Mac (dedup blocks
  re-ingest). The user wants Apple-Notes-style: edit on either device, it shows everywhere.

**Mac → phone (the easier half):**
- The carrier already exists: `MemoEnhancement` (copyedit/title/summary), synced via CloudKit, and the
  phone's `MemoExporter` already prefers it. So a Mac edit just needs to **re-upsert the enhancement**.
- Wire a **debounced write-back** into the Mac note-edit path: `Features/Review/NoteBody.swift`
  `bodyBinding` setter (writes `sanitised`/`enhancedCopyedit`/`transcript`) + title/summary edits →
  after ~1–2s idle, call `MacCloudWriteBack.upsert(for: pf, ...)`. Reuse the Phase-2c write-back;
  add the retry flag noted in the plan. Debounce to avoid CloudKit churn per keystroke.
- LWW is handled (`MemoEnhancement.enhancedAt`).

**Phone → Mac (the harder half):**
- A phone edit updates the raw `Memo` (CloudKit). The Mac ingested it once and **dedups** on re-see
  (`MemoCloudIngest.alreadyIngested`). Need an **update path**: when a synced `Memo` changes AFTER
  the Mac already has a `PipelineFile` for it, refresh the Mac's copy (transcript/metadata) and decide
  policy — re-link names only, or re-run enhance? (Re-running enhance on every phone edit is heavy;
  a name-relink + recompile is cheap. Probably: update the transcript, re-sanitise + recompile, don't
  auto-re-LLM unless asked.) The reconciler (`MemoCloudReconciler`) sees the CloudKit import event —
  extend it to update an existing `PipelineFile` when the source `Memo.lastModified` is newer.

**Loop/provenance guard:** stamp who made an edit (device id + timestamp — `MemoEnhancement` already
has `enhancedByDeviceID`) so a device doesn't re-process/echo an edit that originated from the other
side. Don't write back an enhancement that just arrived from CloudKit.

**Verify (device):** edit a note body on the Mac → phone reflects it within seconds; edit the same
memo on the phone → the Mac's queue/export updates. Both directions, no echo loop.

**Scope note:** this is a real feature (both-directions edit sync + conflict/provenance), best done as
its own focused session with device round-trips. It's separate from Part A (which is pure cleanup).

---

## Housekeeping
- **Push** the 14 commits when ready (nothing pushed yet).
- **Prod gate** still owed (Phase 4): deploy the CloudKit **Production** schema (now incl. `NamesRecord`
  + `VocabularyRecord`) + one prod round-trip before promoting a Release build.
- Other backlog parity item: **Mac in-place name-linking** (dotted/tappable in the review body,
  immediate not post-enhance) — see `backlog.md`.
