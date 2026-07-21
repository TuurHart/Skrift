# LANE_SURF — Mac surfaces: the band ②, one trash ③, the conveyor ④

Read `LANES-2026-07-21/BASE.md` first (base check, ownership, rules). You own the Mac's
Features/ surfaces. Three steps, one commit each, in this order. The visual spec is
`Skrift_Native/SkriftDesktop/mocks/lifecycle-ia-explorations.html` — #m2 (the band, drawn in
the direction-2 frame) and #m3 (the conveyor). Draw from the spec + current source, exact
Theme tokens; the app's verb is always **Process**, never "polish".

Data model facts you rely on (verified by the conductor):
- `MemoCloudStore.container` (App/MemoCloudContainer.swift) is the cloud store; JournalView
  already fetches all Memos from it on refresh — copy that access pattern.
- `MemoSpine` (Shared/Pipeline/MemoSpine.swift, READ-ONLY) computes station + one-liner.
  ALL status copy comes from it. `MemoSpine.Input.from(memo, backlinked:queue:)`.
- `MemoLifecycle.partition/backlinkedIDs` (Shared, READ-ONLY) — existing fade predicates.
- The Mac→cloud write lane exists: FadingShelfColumn's Keep writes memo fields directly on
  the cloud context + save. Your band's Process does the same (no new sync machinery).

## Step ② — the Queue band (commit 1)

SidebarView grows a collapsed band at the BOTTOM of the queue list (above the footer),
drawn per mock #m2's direction-2 sidebar:
- Header row: `○ Not in the pipeline · N` + a small "Process all N" capsule + disclosure.
  Collapsed by default (`@AppStorage("queueBandExpanded")`, default false). Row hidden
  entirely when N == 0. The ○ is SF Symbol `circle` (10-11pt), NOT an emoji.
- Membership: cloud Memos with `deletedAt == nil`, `significance == 0`, transcript non-empty
  is NOT required, and NO PipelineFile with the same id in `files`. Exclude non-UUID ids.
  Refresh on appear, on `files` change, and after any band Process action.
- Expanded rows: title (or transcript prefix, the `displayTitle` idiom), meta line
  `date · duration · <MemoSpine.oneLiner>` (e.g. "starts fading 19 Aug" / "kept — tagged").
  Per-row "Process" capsule. Sub-footnote under the band (muted, 1 line): "Synced to this
  Mac — not rated, so not processed. Rating one starts processing; sync is never gated."
- Process (row + all-N): set `memo.significance = 0.1` on the cloud context, save. Then
  trigger a reconcile so it appears in the queue promptly: grep App/MemoCloudReconciler+Wiring.swift
  for its public sweep entry (launch/active triggers call one) and CALL it (read-only use is
  fine — do NOT edit that file, LANE_AUTHOR owns it). If no callable entry exists, post the
  same Notification it observes; if neither is reachable, leave a `// TODO(conductor)` and
  note it in your report — do NOT invent new wiring.
- a11y ids: `sidebar.band`, `sidebar.band.process-all`, `band-row-process`.

RootView:34's flash dies: in the `onOpenInQueue` fallback, instead of
`coordinator.flash(...)`, present the new `UnpipelinedMemoSheet` (new file,
Features/Journal/UnpipelinedMemoSheet.swift): read-only memo view — title, date/place/duration
meta, transcript body (plain Text, scrollable), the same one-liner, and one "Process" capsule
(same 0.1 write) which dismisses + jumps to the queue row once it exists. Keep it modest —
this is a peek, not the editor. a11y: `unpipelined-sheet`, `unpipelined-sheet.process`.

Q6 (same commit): delete the "Process every synced memo" toggle row from
Features/Settings/SettingsView.swift (~line 115). In Models/AppSettings.swift add ONE
deprecation comment on `processAllSyncedMemos` ("dead since 2026-07-21 — the band's Process
all N replaced it; field kept for legacy decode") — do NOT remove the field or the
`processAllSyncedMemosEnabled` accessor (LANE_AUTHOR kills its last read; conductor cleans up).

## Step ③ — one Recently Deleted (commit 2)

- RootView: remove `trashOpen`, the `.sheet` presenting `RecentlyDeletedView`, and the
  `onOpenTrash` plumbing. DELETE Features/Sidebar/RecentlyDeletedView.swift (git rm — its
  job moves into the conveyor). KEEP `DesktopTrash.purgeExpired` (RootView:106) — the local
  purge is an implementation detail, not UI.
- AppModel: add `enum ReviewShelf { case wayOut }` + `var reviewShelf: ReviewShelf?`.
  JournalView's private `shelf` @State migrates to this (delete its local `Shelf` enum).
- SidebarView footer row "Recently Deleted (N)": stays visible when the count > 0 but now
  reads "Recently Deleted · in Review" and its action = `model.surface = .journal;
  model.reviewShelf = .wayOut`. N = the MEMO trash count + Mac-local deleted PipelineFiles
  (pass what you need through existing initializers you own).

## Step ④ — the conveyor (commit 3)

- NEW Features/Journal/WayOutColumn.swift replaces BOTH `FadingShelfColumn` and
  `MacTrashColumn` (delete both structs; keep `MacFadingSweep` — move it into
  LifecycleSweepScheduler below). ONE column, header `On its way out · N`, then rows in two
  quiet sections ordered by imminence:
  - Fading rows: meta + `MemoSpine.oneLiner` ("moves to Recently Deleted in Nd").
  - Deleted rows: meta + "gone for good in ~Nd".
  - ONE verb on every row: **Bring back** → `keptAt = Date()`; also `deletedAt = nil` if
    set (pinned cross-app semantics — an explicit rescue is a touch, no instant re-fade).
  - Transitional tail, only when non-empty: section "Mac-only files" listing DELETED
    PipelineFiles with no memo — Restore (`deletedAt = nil`) + the hard-delete-with-confirm
    the old RecentlyDeletedView had. Footnote: "Uploaded on this Mac before captures synced."
  - Footer line stays honest about the machinery: "Automatic: each note moves along on its
    day. Bring back = never fades again. Your iPhone does the permanent deleting."
  - a11y: `wayout-row-bringback`, `wayout-maclocal-restore`.
- JournalView rail: the two shelf rows collapse to ONE:
  `shelfRow("🍂", "On its way out", <fading+trashedMemos+macLocalTrash count>, .wayOut)`.
- NEW Features/Shell/LifecycleSweepScheduler.swift: owns the 60d sweep — runs
  `MacFadingSweep.run` on app launch, on `NSCalendar.dayChangedNotification`, and every 24h
  (a `Task.sleep` loop or Timer, MainActor). JournalView.refresh STOPS sweeping (delete that
  call) — shown dates must be true without opening Review. Wire the scheduler from RootView's
  `.task` (you own RootView).
- Snapshot.swift: repoint `-snapshot-trash` to render `WayOutColumn` with fixture rows in
  all three sections (fading / deleted / mac-only), fed by injected arrays (pure view — copy
  the ConnectionsPanelBody fixture pattern). Note in your report that the sidebar band has no
  ImageRenderer fixture (sidebar can't snapshot — known repo limitation; the conductor
  eyeballs it live).

## Tests (each step's commit includes its tests; MLX-free UnitTests-scheme compatible)
Extract the pure logic so it's testable without views: band membership (given memos + pf ids
→ the unpipelined set, non-UUID excluded), the Bring back mutation (keptAt set, deletedAt
cleared), the conveyor's row ordering, the footer-count arithmetic. New file(s) under
SkriftDesktopTests/. Do NOT run xcodebuild — conductor gates.

## Don'ts
No Shared/ edits. No Pipeline/Ingest edits. No new colors/opacities outside Theme tokens
(hairlines 0.02–0.08 — the house range). No countdown text that MemoSpine didn't produce.
No "polish". If FadingShelfColumn's deletion breaks a caller you don't own — ESCALATE, don't
edit around it.
