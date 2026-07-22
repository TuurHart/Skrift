# SHELL — universal shell + Notes split view + record presentation (mock m1, m7)

FEATURE: at regular width the Notes tab becomes list-column ↔ note-page; record becomes a
centered card; keyboard shortcuts. Compact stays the phone app untouched.

Build (mock m1 + m7 + BASE law):
1. `MemosListView` regular width → `NavigationSplitView` (`.balanced`, sidebar ≈
   `Adaptive.listColumnWidth`): sidebar = today's entire list UI (headerRow, SearchField, rows,
   day groups, bottom chrome INSIDE the sidebar column); detail = `MemoDetailView(initialID:)`
   driven by selection (replace push-nav at regular; keep `.navigationDestination` at compact —
   the existing `path: [UUID]` NavigationStack stays for compact). Selected row wears
   `skAccentSoft` (m1). Detail empty state: quiet "Select a note" on `skBg`.
   GOTCHA: rows are Buttons (iOS-26 context-menu lift) — selection must not break long-press
   menus or edit-mode multi-select.
2. `RecordView` on regular width: presented as a centered card (m7) — swap the
   `.fullScreenCover` in MemosListView for a sheet with detents/`presentationSizing` sized
   ~620pt when `isPadIdiom` (fullScreenCover stays on phone). RecordView internals: cap content
   width with `readingMeasure(620)`; keep every existing control + accessibility id. The camera
   sheet + live caption + waveform must keep working unchanged.
3. `AppTabView`: adopt `.tabViewStyle(.sidebarAdaptable)` (iPadOS 18 top strip; free sidebar).
   Verify the `-openTab` routing still works.
4. Keyboard (`App/SkriftApp.swift` `.commands` ONLY): ⌘N = start recording (reuse
   `RecordingIntentBridge.shared.requestStart()`), ⌘F = focus notes search (add a
   FocusState bridge in MemosListView), ⌘1–⌘4 = tabs (a small `TabSelectionBridge` in
   Features/Root is yours to add).
5. `OnboardingView`: wrap pages in `readingMeasure()` so first-run on iPad isn't stretched.

Escalate (don't guess): any need to touch MemoDetailView (DETAIL owns it) — the split view may
only instantiate it; any project.yml need.
