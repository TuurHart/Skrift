# LANE_UI2 — the "Book text" sheet (mock variant B, signed)

Read `LANE_PLAYBOOK.md` then `LANES-2026-07-22D/BASE.md` (ownership, pinned contract — you
CONSUME it verbatim; LANE_CORE2 implements in parallel; the conductor's merge gate compiles
the seam). Write `LANES-2026-07-22D/PLAN_UI2.md`, commit, execute.

**THE SPEC IS THE MOCK: `mocks/book-text-sheet.html` VARIANT B (#m2).** Open and read its
HTML/notes. Build THAT — timeline bar first, rows below, add-button, footer line. Variant A
rows / variant C options-screen are NOT this batch. House components/idioms only (Theme
colors, existing capsule/row styles from the Books surfaces); no new design inventions —
deviations from the mock → ESCALATE.

## Build (small commits, explicit paths)

1. **`BookTextSheet.swift`** (new): a presentation-detent sheet (medium), title "Book text",
   subtitle "Real book text covers N% of this audiobook" (round to whole %; when nothing is
   attached yet: "No book text attached").
   - **The bar**: full-width, 14 pt tall, rounded; segments from
     `BookAlignmentRunner.textSummary(bookID:)` — each `PerText.spans` scaled over
     `bookDuration`, colored per BASE's color rule (text 0 = accent, 1 = tan, cycle);
     uncovered = the mock's dark grey. 0:00 / total under the ends (tabular numerals).
     Legend row beneath (swatch + title-or-filename), wrapping.
   - **Rows per text** (attach order): title (fallback filename), meta line
     "58 min · full match" (coveredSeconds formatted h/min; "full match" when its aligned
     files' union ≈ its spans, else "partial"), trailing ⋯ menu → **Remove** (confirmation
     dialog, destructive; calls `removeText`) and **Re-check** (fire `alignIfNeeded`).
   - **"＋ Add book text…"** row (dashed, accent): triggers the SAME fileImporter flow the
     library owns today. Footer caption: "Texts never change your audio or transcript."
   - Empty state (no texts): bar all-grey, one dashed add row, footer.
2. **`AudiobookLibraryView.swift` wiring**: the long-press verb becomes **"Book text…"**
   (one label whether or not texts exist) and OPENS THE SHEET; the sheet owns Add from
   here on. Move/reuse the existing fileImporter + `runAttach` + busy/outcome alerts so
   they present over the sheet (attach outcome alert copy unchanged from the fix wave).
   After an attach or remove completes, the sheet's summary refreshes (re-call
   `textSummary`).
3. **Tests** (`BookTextSummaryDisplayTests.swift`, @testable — pure display logic only):
   percent rounding + the h/min duration formatting · segment fractions from a synthetic
   `BookTextSummary` (span → x/width math, if you extract it into a testable helper —
   DO extract it) · color-index cycling · "full match"/"partial" wording rule.
   No view-rendering tests; the conductor eyeballs the sheet at the gate.

## Wrap
Playbook wrap block + uncertain-decisions table (formatting choices + anything the mock
leaves ambiguous — table it, don't invent).
