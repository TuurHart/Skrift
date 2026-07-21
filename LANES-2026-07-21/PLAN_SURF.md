# PLAN_SURF — the band ②, one trash ③, the conveyor ④

Base SHA: `11372a450faa733c28e79e5a3034debbdd0d71bb` (verified fresh via BASE.md marker).

## Architecture decision: a new pure-logic home

The brief asks for MLX-free, `UnitTests`-scheme-compatible tests of the band-membership
filter, the Bring-back mutation, the conveyor's ordering, and the footer-count arithmetic.
`SkriftDesktopTests`' `project.yml` sources are `SkriftDesktopTests`, `Models`, `Pipeline`,
and `../Shared/{Naming,Export,Model,Pipeline,Retrieval}` — **not** `Features` or `App`. Pure
logic placed in a NEW file under `Features/` (my only explicitly-granted "NEW file" location)
would be invisible to the test target; a file under `SkriftDesktopTests/` would be invisible
to the app target. Neither satisfies "one function both the UI and the test exercise."

Resolution: a new file `Skrift_Native/SkriftDesktop/Pipeline/WayOutRules.swift` (top-level
`Pipeline/`, sibling to the existing unclaimed `DesktopTrash.swift`) — compiled into BOTH
targets already (see `project.yml`), not `Shared/` (forbidden), not `Pipeline/Ingest/`
(LANE_AUTHOR's, forbidden per my own Don'ts). This is not in BASE.md's literal ownership
list — flagged in the uncertain-decisions table below; it doesn't collide with LANE_AUTHOR's
`Pipeline/Ingest/MacMemoAuthor.swift`.

`WayOutRules` is pure (`import Foundation` only, mirrors `MemoLifecycle`/`MemoSpine`'s
style — no ModelContext param, callers save). It calls `MacCloudWriteBack.memoID(for:)`
(Pipeline/Ingest, read-only use, already visible to both targets) for the mac-only test.

## View architecture: pure body + thin wrapper (ConnectionsPanelBody precedent)

`WayOutColumn` takes `let` data arrays + action closures (`onBringBack: (Memo) -> Void`,
etc.) — zero ModelContext coupling, matching `ConnectionsPanelBody`/`ConnectionsPanel`'s
split. `JournalView.column` plays the "thin wrapper" role itself (builds real closures over
`MemoCloudStore`/`localCtx`); `Snapshot.renderTrash` builds fixture arrays + no-op closures.

## Commit sequencing note

Commits are logically ordered, not each independently buildable — matches "EDIT-ONLY...
Swift correctness = your care + the conductor's compile gate" (singular gate, at the tip).
Concretely: commit 2 (step③) mechanically migrates `JournalView`'s local `Shelf` enum to
`AppModel.ReviewShelf { case wayOut }` (per step③'s own text) — since that enum has exactly
one case, the rail must already collapse to one row and `column`'s switch must already
target `.wayOut`. Rather than forward-reference `WayOutColumn` (a step④ file), commit 2's
`.wayOut` case renders a stopgap `VStack` of the two EXISTING columns (`FadingShelfColumn`
+ `MacTrashColumn`, untouched, still present); commit 3 replaces that stopgap with the real
`WayOutColumn` and deletes the two old structs. Keeps each commit's diff honestly scoped to
its step's description.

## Per-commit file manifest

**Commit 1 — step② the band:**
- NEW `Pipeline/WayOutRules.swift`: `unpipelined(memos:files:)`, `displayTitle(_:)`,
  `oneLiner(for:backlinked:now:)`.
- NEW `Features/Journal/UnpipelinedMemoSheet.swift`: read-only peek, Process capsule.
- NEW `SkriftDesktopTests/WayOutRulesTests.swift`: band membership + non-UUID exclusion.
- EDIT `Features/Sidebar/SidebarView.swift`: collapsed band (header/rows/footnote), cloud
  Memo fetch (`.task` + `.onChange(of: files.count)`), Process → `significance = 0.1` +
  save + `MemoCloudReconciler.reconcileSoon()` (read-only call, per BASE's grep instruction).
- EDIT `Features/Shell/RootView.swift`: `onOpenInQueue` fallback presents
  `UnpipelinedMemoSheet` instead of `coordinator.flash(...)`.
- EDIT `Features/Settings/SettingsView.swift`: delete the "Process every synced memo" row.
- EDIT `Models/AppSettings.swift`: deprecation comment on `processAllSyncedMemos` ONLY.

**Commit 2 — step③ one Recently Deleted:**
- DELETE `Features/Sidebar/RecentlyDeletedView.swift` (git rm).
- EDIT `Features/Shell/RootView.swift`: remove `trashOpen`/sheet/`onOpenTrash`; SidebarView
  call passes `trashedFiles:` (renamed from `trashedCount:`).
- EDIT `Features/Shell/AppModel.swift`: add `enum ReviewShelf { case wayOut }` +
  `var reviewShelf: ReviewShelf?`.
- EDIT `Features/Journal/JournalView.swift`: migrate `shelf`/`Shelf` → `model.reviewShelf`
  (stopgap rendering, see above).
- EDIT `Features/Sidebar/SidebarView.swift`: `trashedCount: Int` → `trashedFiles: [PipelineFile]`;
  footer row text "Recently Deleted · in Review", action sets `model.surface`/`reviewShelf`
  directly (drop `onOpenTrash` param); count = `WayOutRules.wayOutFooterCount`.
- EDIT `Pipeline/WayOutRules.swift`: add `isMacOnly`, `macOnlyTrashed`, `wayOutFooterCount`.
- EDIT `SkriftDesktopTests/WayOutRulesTests.swift`: footer-count arithmetic tests.

**Commit 3 — step④ the conveyor:**
- NEW `Features/Journal/WayOutColumn.swift`: merged column (fading/deleted/mac-only
  sections, ordered by imminence), `capsuleButton` moved here.
- NEW `Features/Shell/LifecycleSweepScheduler.swift`: launch + `NSCalendarDayChanged` +
  24h heartbeat sweep (fresh `ModelContext(cloud)` per the reconciler's documented
  stale-mainContext gotcha; also gates on `cloudKitMacSyncEnabled` like the reconciler does).
- DELETE `Features/Journal/FadingShelfColumn.swift` (git rm — both structs absorbed,
  `MacFadingSweep` moved into the scheduler).
- EDIT `Features/Journal/JournalView.swift`: real `WayOutColumn` wiring; `macLocalTrash`
  fetch (local ctx); rail collapses to one `shelfRow` with the full 3-way count;
  `refresh()` drops the `MacFadingSweep.run` call.
- EDIT `Features/Shell/RootView.swift`: wire `LifecycleSweepScheduler.start()` in `.task`.
- EDIT `Features/Shell/Snapshot.swift`: `-snapshot-trash` renders `WayOutColumn` with
  fixture arrays (fading/deleted/mac-only), not `RecentlyDeletedView`.
- EDIT `Pipeline/WayOutRules.swift`: add `bringBack`, `fadingOrdered`, `deletedOrdered`.
- EDIT `SkriftDesktopTests/WayOutRulesTests.swift`: Bring-back mutation + ordering tests.

## Correctness note vs. old precedent (not a doctrine change, just a bug I'm not carrying forward)

The mock's worked conveyor example ("deleted 7 Jul" / "~1d" ABOVE "deleted 14 Jul" / "~8d")
proves the Deleted section sorts **oldest-deletedAt-first** (soonest to purge = most
imminent). The old `MacTrashColumn` sorted newest-deleted-first (recency, not imminence).
"Ordered by imminence" in the brief is unambiguous once cross-checked against the mock's
own numbers, so `WayOutRules.deletedOrdered` intentionally does NOT mirror
`MacTrashColumn`'s old comparator.

## Uncertain decisions (see final report table)

1. `Pipeline/WayOutRules.swift` placement (not literally in BASE's ownership list).
2. Band positioned as a fixed element between `queue` and `bottomBar` (always visible,
   including the empty-queue/no-matches states) rather than nested inside the scrollable
   row list as the mock's raw HTML nesting shows (mock only renders the populated-list
   state) — chosen so a first-sync-no-ratings-yet user isn't blind to the band.
3. Footer trash count and mac-only-file detection use `MacCloudWriteBack.memoID(for:) == nil`
   (filename/id-shape test) rather than cross-checking against the live fetched `Memo` array
   — simpler, sufficient today (Q5: zero `Memo(` constructions on desktop), matches how
   `MacCloudDeleteSync` already establishes memo-linkage.
