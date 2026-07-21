# PLAN_PHONE — "On its way out" merged shelf

Base: `11372a450faa733c28e79e5a3034debbdd0d71bb`. Brief: `LANES-2026-07-21/LANE_PHONE.md`.

## Pre-flight findings

- **UI test grep (required before deleting):** `SkriftMobileUITests/` has ZERO references
  to `FadingShelfView`, `RecentlyDeletedView`, or any of their accessibility identifiers
  (`trash-done-button`, `trash-confirm-delete-button`, `trash-restore-button`,
  `trash-delete-now-button`, `trash-list`, `trash-empty`, `shelves-menu`). `MemosListUITests.swift`
  never touches the shelves/trash flow at all. Nothing to carry over 1:1 — fresh `wayout-*`
  identifiers are safe, matching the brief's pinned `wayout-row-bringback` /
  `notes-menu-wayout` plus a few natural siblings for future test coverage.
- **`FadingSweep.sweepAllFading(repository:)`** (Services/FadingSweep.swift) has exactly one
  caller: FadingShelfView's "Sweep all" toolbar button. The brief's build list for WayOutView
  doesn't include a sweep-all control, and the mock (`lifecycle-ia-explorations.html` #m3,
  ~line 823: "One list, one ordering, **one verb**") is explicit that Bring back is the only
  verb. Dropping "Sweep all" — `sweepAllFading` becomes dead code in a file outside my
  ownership (Services/), left as-is for the conductor. Flagged in final report.
- **Mock content check** (spec of record, ~lines 793-825): deleted-section rows show
  `deleted <date>` as their meta line, not `recordedAt` (the old TrashRow showed recordedAt).
  Following the mock for this since it's cited as spec of record. Fading-section rows keep
  the old FadingShelfView's meta (recordedAt + place) unchanged.

## Design decisions (translating the brief into code)

1. **One row component, two kinds.** A private `WayOutRow` view takes `kind: .fading | .deleted`
   and renders: title, kind-specific meta line, `MemoSpine`-sourced one-liner, one "Bring back"
   button. Deleted-kind rows additionally get a trailing swipe + context menu "Delete Now"
   (destructive, confirmed) — kept as a *secondary* gesture, not a second button, so the row
   still shows exactly one verb.
2. **Countdown copy** comes from one pure static helper `WayOutView.oneLiner(for:now:)` that
   builds a `MemoSpine.Input` from the memo and lets the spine's priority chain pick the branch
   (`deletedAt` set → `.deleted`; else untouched+past 30d → `.fading`). No hand-written countdown
   strings anywhere in this file.
3. **Bring back** = pinned cross-app semantics from BASE.md: `memo.keptAt = Date()` (always) +
   `memo.deletedAt = nil` (always — a no-op for a still-fading row). NOT
   `repository.restore(_:)` (that only clears `deletedAt`, not `keptAt` — Restore alone would
   let a rescued note re-fade immediately, which the seam note explicitly forbids).
4. **Ordering.** Two pure static helpers, `orderedByImminence(fading:)` (ascending
   `MemoLifecycle.fadesAt`) and `orderedByImminence(deleted:)` (ascending `deletedAt`) — both
   "soonest first," matching the mock's per-section ordering. The deleted `@Query` already
   sorts this way; the pure helper re-applies it so the ordering is independently unit-tested
   rather than only trusted to the query's sort descriptor.
5. **Merged count.** `WayOutView.total(fading:deleted:) -> Int` — trivial, but named/tested
   directly since the OLD code showed two independent counts and a silent "only counted one"
   regression is exactly the kind of bug a merge introduces.
6. **Layout risk (flagged, unverified — EDIT-ONLY lane, no simulator).** MemoSpine's one-liners
   are meaningfully longer than the old copy ("moves to Recently Deleted in 29d" vs. old
   "fades in 29 days") and "Bring back" is wider than old "Keep"/swipe-"Restore". Laying the
   one-liner + button out as a width-capped trailing `VStack` (not a flat HStack) so the text
   can wrap instead of clipping or squeezing the title. Cannot visually confirm — flagged as
   unverified in the final report per CLAUDE.md.
7. **⋯ menu.** `showFading` → renamed `showWayOut`; `showTrash` removed entirely. The Menu
   wrapper stays (still called from the same header ellipsis+dot control) with its two Buttons
   collapsed to one: `On its way out (N)`, N = `lifecycle.fading.count + trashedMemos.count`
   (same two existing counts, just summed instead of shown separately). Outer identifier
   renamed `shelves-menu` → `notes-menu-wayout` (nothing referenced the old name). Dot/stamp
   logic (`fadingLastSeenAt` AppStorage key, `fadeEntersAt` comparison) untouched byte-for-byte.

## Commits (small, explicit paths)

1. This file.
2. NEW `Features/MemosList/WayOutView.swift`.
3. Edit `MemosListView.swift`: merge the ⋯ menu item, rewire the sheet, rename state.
4. `git rm` `FadingShelfView.swift` + `RecentlyDeletedView.swift`.
5. NEW `SkriftMobileTests/WayOutViewTests.swift` — merged count, both orderings, Bring back
   mutation (fading case + deleted case), one-liner wiring smoke test (both branches).

No Shared/ edits. No desktop files. No xcodebuild/simulator runs (conductor's compile gate).
