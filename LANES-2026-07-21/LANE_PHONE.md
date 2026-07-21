# LANE_PHONE — phone parity: one "On its way out", spine one-liners

Read `LANES-2026-07-21/BASE.md` first (base check, ownership, rules). Phone-only lane.
Q4 (locked): the phone's two shelves merge into ONE surface named **"On its way out"**, verb
**"Bring back"**. All status copy comes from `MemoSpine.oneLiner` (Shared, READ-ONLY, already
on your base with twin tests).

Current state (verified): `MemosListView.swift` — the Notes-header ⋯ menu (~line 463) holds
`Fading (N)` + `Recently Deleted (N)` as two items; `showFading` presents `FadingShelfView()`
(~line 182); the amber ⋯ dot is UNREAD-semantics (lights only for fade-entries newer than the
last shelf visit — `fadeEntersAt` vs an AppStorage stamp; opening the shelf clears it). The
phone owns PERMANENT deletion (its purge + any hard-delete UI in RecentlyDeletedView).

## Build (small commits, explicit paths)

1. NEW `Features/MemosList/WayOutView.swift` — absorbs FadingShelfView + the phone
   RecentlyDeletedView into one screen, matching their existing row/list idiom (draw from
   those two files, not from memory):
   - Title "On its way out · N". Two quiet sections ordered by imminence:
     fading rows → meta + `MemoSpine.oneLiner` ("moves to Recently Deleted in Nd");
     deleted rows → meta + "gone for good in ~Nd".
   - ONE verb per row: **Bring back** → `keptAt = Date()` + `deletedAt = nil` when set
     (pinned cross-app semantics — identical on the Mac).
   - Keep the phone-owned destructive controls the old trash screen had (hard delete w/
     confirm, and its purge notes) inside the deleted section.
   - Empty state: "Nothing on its way out. Untouched notes start fading after 30 days."
   - a11y: `wayout-row-bringback`, plus keep any identifiers the old screens' UI tests use
     (grep SkriftMobileUITests for references BEFORE deleting; if a UI test names the old
     screens, keep those ids on the new rows and note it).
2. `MemosListView.swift`: the ⋯ menu's two items become ONE — `On its way out (N)` where
   N = fading + trashed counts; `showFading` renamed/rewired to present WayOutView. The
   amber-dot unread semantics stay EXACTLY as they are (same stamp, cleared on open).
   a11y: `notes-menu-wayout`.
3. DELETE `FadingShelfView.swift` + `Features/MemosList/RecentlyDeletedView.swift` (git rm)
   once nothing references them. The sweep cadence (launch/foreground) is NOT yours — no
   timers on the phone.
4. Tests — NEW `SkriftMobileTests/WayOutViewTests.swift` for the pure parts: the merged
   count, row ordering by imminence, Bring back mutation (keptAt set + deletedAt cleared).
   Extract helpers so they're testable without UI. Do NOT run xcodebuild — conductor gates.

## Don'ts
No Shared/ edits (if MemoSpine seems to lack something, ESCALATE). No desktop files. No new
copy that MemoSpine didn't produce for countdowns. Do not change the fade/trash thresholds,
the purge, or the ⋯ dot semantics. Keep diffs tight to the three files + your new ones.
