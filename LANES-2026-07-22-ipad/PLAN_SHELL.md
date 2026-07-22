# PLAN — SHELL lane (iPad wave 1, mock m1 + m7)

Base SHA: `ea51c7e02ec4abdd4732e11ed69193dce88e1e57` (branch `lane/ipad-shell`). BASE.md present.

Feature: at **regular** width the Notes tab becomes list-column ↔ note-page; record
becomes a centered card; keyboard shortcuts. **Compact stays the phone app, byte-for-byte.**
Layout branches on `horizontalSizeClass == .regular`; `Adaptive.isPadIdiom` only for the
record presentation style (an idiom fact).

## Ownership (write set only)
`Features/Root/**`, `Features/MemosList/MemosListView.swift`, `Features/Recording/RecordView.swift`,
`Features/Onboarding/OnboardingView.swift`, `App/SkriftApp.swift` (`.commands` only).

## Steps

1. **Root shell** (`Features/Root/AppTabView.swift` + NEW `Features/Root/TabSelectionBridge.swift`)
   - Add `.tabViewStyle(.sidebarAdaptable)` (iPadOS top strip; free sidebar; compact falls
     back to the bottom bar untouched). Keep the existing `.tabItem`/`.tag` + `initialTab()`
     so `-openTab` routing is unchanged.
   - `TabSelectionBridge.shared` (ObservableObject, `requestedTab: Tab?`) so `.commands` can
     drive tab selection. AppTabView consumes it via `.onChange`, keeping its own `@State`.

2. **Notes split view** (`MemosListView.swift`)
   - `body` branches: regular → `NavigationSplitView(.balanced)` { sidebar = existing surface }
     detail: { `MemoDetailView(initialID:)` (`.id(sel)`, wrapped in its own `NavigationStack`
     so its toolbar renders) or quiet "Select a note" on `skBg` }. Compact → today's
     `NavigationStack(path:)` + `.navigationDestination`, unchanged.
   - Extract the ZStack + all shared modifiers (covers/sheets/onChange/overlay/importers) into
     one `notesRoot` view used by BOTH branches (no duplication). `.navigationDestination`
     stays compact-only. Sidebar width `min 320 / ideal listColumnWidth / max 420`.
   - `@State selectedMemoID: UUID?` drives the detail pane at regular width. Row tap:
     `isRegular ? selectedMemoID = id : path.append(id)`. `openMemo(id)` (onSaved +
     handleOpenRequest): `isRegular ? selectedMemoID = id : path = [id]`.
   - Selected row = `skAccentSoft` (m1): `MemoRow`/`MemoCard` gain `selected: Bool`; a
     `SelectableCard` modifier == `.skCard()` when unselected (byte-identical → compact
     untouched), accent-soft fill + accent hairline when selected. Multi-select (EditMode +
     `List(selection: $selected)` Set) and the Button/context-menu lift are untouched.

3. **Record card** (`MemosListView.swift` presentation + `RecordView.swift` internals)
   - Swap the record `.fullScreenCover` for a `RecordPresentation` modifier: `.sheet` +
     `.presentationSizing(.form)` when `Adaptive.isPadIdiom`, else `.fullScreenCover` (phone).
     Book-player cover + all controls/ids untouched.
   - `RecordView` main column capped with `.readingMeasure(620)` (no-op on phone width); the
     full-bleed camera overlay stays uncapped. Every control + accessibility id kept.

4. **Keyboard** (`App/SkriftApp.swift` `.commands` ONLY)
   - ⌘N = `TabSelectionBridge.select(.notes)` + `RecordingIntentBridge.shared.requestStart()`.
   - ⌘F = `TabSelectionBridge.select(.notes)` + `SearchFocusBridge.shared.requestFocus()`.
   - ⌘1–⌘4 = `TabSelectionBridge.select(.notes/.books/.journal/.settings)`.
   - `SearchFocusBridge` (in MemosListView.swift): MemosListView observes it to set a
     `@FocusState`. Because the shared `SearchField` (Components.swift, read-only) exposes no
     focus binding, the Notes search field is inlined in MemosListView as a faithful copy
     (same tokens, same `memo-search` id) carrying `.focused($searchFocused)`. See uncertain
     table.

5. **Onboarding** (`OnboardingView.swift`) — wrap the page column in `.readingMeasure()` so
   first-run isn't stretched on iPad. Phone width = no-op.

## Escalation watch
- Never edit `MemoDetailView.swift` (DETAIL owns it) — split view only *instantiates* it. ✓
- No `project.yml` need (family flip + orientations already on base). ✓

## Verify (conductor's gate; lane is edit-only)
Compact iPhone 17 sim suite green (zero phone regressions), iPad Pro 13" regular-width eyeball
of: list↔detail selection + accent-soft row, record card, ⌘N/⌘F/⌘1–4, onboarding measure.
