# PLAN — JOURNAL lane (iPad wave 1, 2026-07-22)

Base verified: `LANES-2026-07-22-ipad/BASE.md` present at HEAD `ea51c7e02ec4abdd4732e11ed69193dce88e1e57`.
Ownership: `Skrift_Native/SkriftMobile/Features/Journal/**` only. Read-only: everything else
(`Shared/**` incl. `LookbackProvider.swift` / `PlaceCluster.swift` / `SourceTaxonomy.swift`,
`DesignSystem/Adaptive.swift`, `DesignSystem/Theme.swift`, `DesignSystem/Components.swift`).

## Read
- `mocks/ipad-app.html` m4 (Review split: river left ~520pt + standing calendar/places pane
  right) + m4b (Places → map takes the pane, "⨯ back to calendar").
- `IPAD_PLAN.md` wave-1 scope item 4 (Review/Journal).
- Current `Features/Journal/{JournalHomeView,JournalCalendarView,JournalMapView}.swift` —
  read in full; `Shared/Pipeline/{LookbackProvider,PlaceCluster}.swift`,
  `Shared/Pipeline/SourceTaxonomy.swift` (glyph taxonomy), `DesignSystem/Adaptive.swift`
  (pinned: `readingMaxWidth`/`listColumnWidth`/`sidePanelWidth`/`isPadIdiom`), `Theme.swift`
  (`skBorder` hairline-divider precedent: `Rectangle().fill(Color.skBorder).frame(height: 0.5)`
  in `NamesListView.swift`/`AudiobookSyncSheet.swift`/`MemoDetailView.swift`).

## Design decisions (from the mock, literal)
- Across the WHOLE wave's mocks (m1 Notes `.lhead`+`.rows` exception aside), m4/m5/m6 all put
  the column's `<h2>` INSIDE the `overflow:auto` container — title scrolls away with content at
  regular width (verified: `.setlist h2`/`.shelf h2` same pattern as `.jriver h2`). Built literally:
  `ScreenTitle` is the first item in the river's ScrollView, not a fixed header (unlike compact).
  Flagged in the wrap block's uncertain-decisions table — cheap to pin instead if the conductor's
  vision-check disagrees.
- River width 520pt (mock `.jriver{width:520px}`) — a local constant in `JournalHomeView`
  (`Adaptive.swift` has no journal-specific width token and is out of my ownership to add one).
- Side-pane day rows = a NEW minimal row (glyph + title + time, mock `.dayrow`), not the fuller
  `JournalMemoRow` (which carries snippet/meta/location) — brief spells out "glyph + title + time"
  explicitly, and the mock's row is visually thinner than a `JournalMemoRow`.
- "Places" section + a specific place row both open map mode; a place row pre-focuses
  `JournalMapCanvas` on that cluster (dive), the section header opens unfocused (fit/in-frame).
  Places section hides entirely when there are zero located memos (matches the phone's existing
  `if !placeMemos.isEmpty { placesCard }` gating — no perpetually-empty section title).

## Build steps
1. `Features/Journal/JournalMapView.swift` — refactor: extract the existing interaction logic
   (state, `dive`/`pin`/`bottomCard`/`inFrameMemos`) into a host-agnostic `JournalMapCanvas`
   (adds `var initialFocus: PlaceCluster? = nil`, dives into it `onAppear`); `JournalMapView`
   becomes a thin wrapper adding `.navigationTitle`/`.navigationBarTitleDisplayMode` for the
   compact push destination. Zero behavior change for compact/existing callers.
2. NEW `Features/Journal/JournalSidePane.swift` — the regular-width standing right pane:
   calendar mode (reuses `MonthGrid` verbatim; month header; selected-day `JournalDayRow` list;
   Places list from `PlaceCluster.build`) and map mode (`JournalMapCanvas` + "⨯ back to
   calendar" header). Local `@State` only — no navigation stack involvement (day-select/map-mode
   are in-pane state swaps, not pushes).
3. `Features/Journal/JournalHomeView.swift` — add `@Environment(\.horizontalSizeClass)`; split
   `body` into `compactStack` (existing code, byte-identical incl. calendarCard/placesCard/Route
   pushes) and `regularSplit` (river minus calendarCard/placesCard + hairline divider +
   `JournalSidePane(memos: memos)`). `Route`/`navigationDestination(for:)` wiring stays as-is
   (compact-only in practice now, unchanged registration).
4. Accessibility: new interactive surfaces get `ipad-` prefixed ids
   (`ipad-journal-pane-calendar`, `ipad-journal-pane-map`, `ipad-journal-month-prev/next`,
   `ipad-journal-places-header`, `ipad-journal-place-row-<id>`, `ipad-journal-day-row-<uuid>`,
   `ipad-journal-map-back`). Existing ids (`review-wayout-row`) untouched.
5. Commit per completed step, explicit paths.

## Explicitly NOT doing
- No edits to `JournalCalendarView.swift` (its `MonthGrid`/logic reused as-is, no refactor
  needed there).
- No edits to `Shared/**`, `Adaptive.swift`, ledgers, mocks, or any other lane's files.
- No builds/xcodegen/simulator runs (edit-only per playbook; conductor's merge gate compiles).
- No new tests: the new logic is thin view composition over already-tested `LookbackProvider`/
  `PlaceCluster` pure functions; nothing new pure-logic-shaped enough to warrant a
  `IPadJournal*Tests.swift` file.
