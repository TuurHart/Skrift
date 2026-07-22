# PLAN_UI2 — the "Book text" sheet (mock variant B, timeline-first)

Base SHA: `b4ec5d660f9808103b939073a499db6e61882c5b` (verified via `LANES-2026-07-22D/BASE.md`
present in worktree). Read `LANE_PLAYBOOK.md`, `BASE.md`, `LANE_UI2.md`, the signed mock
(`Skrift_Native/SkriftDesktop/mocks/book-text-sheet.html`, VARIANT B / `#m2`), plus the call
sites read-only first: `AudiobookLibraryView.swift` (full attach flow — `runAttach`, the
fileImporter/alert cluster, the context menu), `Audiobook.swift` (`epubFilenames`/
`attachedTextFilenames`, `AudiobookTime.clock`), `AlignedSentenceSource.swift` (house style for
a pure display/logic layer built against a not-yet-existing LANE_CORE contract),
`Theme.swift` + `Palette.swift` (color tokens), `AudiobookSyncSheet.swift` +
`ChaptersBookmarksSheet.swift` (sheet chrome idioms: grab handle, `.presentationDetents`,
`Color.sk*` usage), `Shared/UI/FlowLayout.swift` (already compiled into the SkriftMobile
target via `project.yml`'s `../Shared/UI` path — reused verbatim for the wrapping legend row,
not reinvented), `PersonEditorView.swift` (the app's one existing "＋ add" dashed-chip idiom —
nearest precedent for the sheet's Add row; Audiobooks itself has none).

LANE_CORE2's schema-3 additions to `BookAlignment.swift` (`AlignmentSource`, `BookTextSummary`,
`BookAlignmentRunner.textSummary`/`removeText`) do **not exist in this worktree** — written in
parallel in LANE_CORE2's own worktree. I build against `BASE.md`'s pinned contract verbatim;
compile-correctness is by-eye + the conductor's merge-gate `xcodebuild` (EDIT-ONLY lane, no
simulators here).

## 1. `BookTextSheet.swift` (new)

`presentationDetents([.medium])`, house grab-handle Capsule (`Color.skBorder`, 36×4 — matches
`AudiobookSyncSheet`/`ChaptersBookmarksSheet` verbatim, not the mock's literal `--elev2`
handle color, since the APP's own established handle idiom outranks a re-read of the mock's
raw CSS token). Whole body below the handle sits in one `ScrollView` (mock is one static flow
with no scroll affordance shown, but a fixed-height `.medium` detent + N rows + Dynamic Type
needs a safety net — simplest faithful port: everything scrolls together, no sticky header
invented).

- **Data**: NOT cached in `@State` — `private var summary: BookTextSummary? { BookAlignmentRunner.textSummary(bookID: book.id) }`
  is a plain computed property, re-read on every `body` evaluation. This is deliberate: it
  makes "the sheet's summary refreshes" (brief) fall out for free from ordinary SwiftUI
  re-render propagation (any `@State` mutation on THIS view OR on the presenting
  `AudiobookLibraryView` forces a fresh read) instead of a hand-rolled cache-invalidation tick.
- **Title/subtitle**: "Book text" (16/bold) + subtitle (11.5/faint) — "No book text attached"
  when `summary` is nil or `perText` is empty; else "Real book text covers N% of this
  audiobook" via a new pure `BookTextDisplay.percentCovered(covered:total:)` (rounds, clamps
  0...100, `total <= 0` → 0).
- **The bar**: a new pure helper `BookTextDisplay.barSegments(perText:bookDuration:) ->
  [BarSegment]` (`BarSegment { textIndex: Int?; startFraction; widthFraction }`) is the
  "span → x/width math" the brief says to extract. It flattens every `PerText.spans` into one
  `(range, textIndex)` list, sorts by start, and walks it left→right emitting an `uncovered`
  (`textIndex: nil`) segment for every gap plus a colored segment for every span — so the
  output already IS one contiguous, chronologically-ordered tiling of `[0, bookDuration]`.
  Rendered as a plain `HStack(spacing: 2)` inside a `GeometryReader` (gap width subtracted from
  the usable width first, so fractional widths stay pixel-exact, unlike the mock's CSS which
  lets `gap` overflow a percentage-summed flex row) — sequential proportional blocks in true
  time order reproduce the mock's "real spans, mid-file boundaries land exactly" property
  without needing absolute pixel positioning. Empty `perText` naturally yields ONE full-width
  `nil` segment (the empty state's "bar all-grey" falls out of the same helper, no special
  case). Colors: `BookTextDisplay.colorCycleIndex(_ textIndex: Int) -> Int` (`% 2`) maps to
  `Color.skAccent` (0) / `Color.skNameSuggest` (1, the app's existing "tan" text tier — closest
  Theme token to the mock's `--tan`); uncovered → `Color.skElev` (the app's general
  next-elevation-up fill, same relationship to `Color.skSurface` the mock's asr-grey has to its
  surface — NOT `Color.skBorder`, which is a near-invisible hairline alpha at this bar's 14pt
  height/opacity; picked over it deliberately, tabled below).
  `0:00` / total via the EXISTING `AudiobookTime.clock(_:)` (confirmed byte-for-byte match
  against the mock's own `0:00` / `4:33:12` example — this is clearly the intended reuse, not
  a new formatter).
- **Legend**: `Shared/UI/FlowLayout.swift` (already in the SkriftMobile target), one chip per
  attached text (swatch + `title ?? filename`) plus an always-present "transcript" grey chip
  (kept even in the empty state — still accurate, avoids a special-cased hide/show branch).
- **Rows** (attach order): title/filename (13.5/semibold) + trailing `Menu` behind an
  `ellipsis` glyph (house idiom, copied from `AudiobookPlayerView`'s `⋯` menu) offering
  **Re-check** (`arrow.triangle.2.circlepath` — a plain, unambiguous system symbol, since I
  can't render/verify glyphs from this lane) and **Remove** (`trash`, destructive → sets
  `pendingRemove`, driving a `confirmationDialog` in the app's own established shape —
  `presenting:`, destructive + cancel — mirroring `AudiobookLibraryView`'s delete dialog). Meta
  line: `BookTextDisplay.durationText(_:)` ("58 min" / "1 h 06", zero-padded minutes,
  hand-verified against both mock examples) + `BookTextDisplay.matchWording(coveredSeconds:
  alignedFilesDuration:)` ("full match" when `coveredSeconds` is within 3% of the SUM of
  `book.fileDurations` at the row's `fileNumbers` — i.e. this text covers essentially all of
  what it aligned to — else "partial"; `alignedFilesDuration <= 0` → always "partial", never a
  false "full match" on zero coverage). A row mid-Remove/Re-check shows a small `ProgressView`
  in place of the ⋯ trigger and disables it (same "swap icon for spinner while busy" idiom
  `topBar`'s import button already uses) — both actions are `async`, `Re-check` in particular
  can take several seconds per `alignIfNeeded`'s own doc comment.
- **"＋ Add book text…" row**: literal glyph in the button's `Text` (matches the mock's literal
  string, sidesteps any icon-rendering risk entirely), dashed border, `onAdd()` callback — does
  **not** open its own picker. Styled off `PersonEditorView`'s "＋ add" chip (`Color.skAccent`
  text + `Color.skAccent.opacity(0.45)` dashed border) since Audiobooks has no add-affordance
  of its own to match and this is the nearest whole-app precedent.
- **Footer**: brief's pinned generic copy ("Texts never change your audio or transcript.") —
  NOT the mock's book-specific example line ("Add \u{201C}Keep Going\u{201D} to fill the
  rest.") since the brief explicitly overrides it with book-agnostic copy.
- **Busy toast relocated in** (see §2) — `busyMessage: String?` param, rendered as the exact
  same capsule-Text overlay `AudiobookLibraryView` already uses for `attachToast`, but hosted
  on THIS view so it's visible while the sheet covers the screen (a plain overlay on the
  presenting view is invisible once a `.sheet` is up — only UIKit-level presentations
  (`.alert`/`.fileImporter`/`.confirmationDialog`) stack over a sheet automatically). This is a
  mechanical fix to make the brief's "busy/outcome alerts present over the sheet" literally
  true for the toast half of that phrase, not a new design surface (same visual, relocated).

## 2. `AudiobookLibraryView.swift` wiring

- New `@State private var bookTextSheetBook: Audiobook?` beside the other 📖 attach state.
- Context-menu button: label fixed to **"Book text…"** (drops the
  `book.epubFilename != nil ? "Replace…" : "Attach…"` ternary entirely), action becomes
  `bookTextSheetBook = book` (was `attachBook = book; showAttachImporter = true`).
- New `.sheet(item: $bookTextSheetBook) { book in BookTextSheet(book: book, busyMessage:
  attachToast, onAdd: { attachBook = book; showAttachImporter = true }) }` — the EXISTING
  `.fileImporter(isPresented: $showAttachImporter, …)`, `runAttach`, and the three attach
  alerts (`attachOutcome`/`attachError`/`attachRejected`) are all left exactly where they are
  (untouched bodies, untouched copy, per the brief) so they keep presenting from the same
  origin view — which, per SwiftUI/UIKit's normal nested-presentation behavior, means they
  stack correctly on top of the now-presented `BookTextSheet` with zero extra plumbing beyond
  passing `attachToast` through as `busyMessage` (§1).
- "The sheet's summary refreshes" after attach: falls out for free — `runAttach` mutates
  `attachToast`/`attachOutcome` (both `@State` on `AudiobookLibraryView`), which forces
  `AudiobookLibraryView.body` to re-run, which re-evaluates the `.sheet(item:)` closure and
  produces a fresh `BookTextSheet`, whose (uncached, per §1) `summary` re-reads on that render.
  No manual tick/refresh plumbing needed for this half.
- After remove/re-check (sheet-internal): the sheet's OWN `busyFilename` `@State` mutation
  around each `async` call forces `BookTextSheet.body` to re-run, same free mechanism.

**Known gap, deliberately NOT touched (flagged, not fixed):** the existing `attachRejected`
alert's "Remove" button calls `removeAttachedText(_:)`, which clears only the LEGACY single
`epubFilename`/`epubChapters` slot — under LANE_CORE2's additive multi-text `attach()`, a
rejected SECOND-OR-LATER text would need the new `removeText(filename:bookID:)` instead (which
needs the just-attached filename; `attachRejected` today only carries the `Audiobook`, not the
filename, so wiring this correctly means widening that alert's payload type — out of this
brief's named scope, and not a regression for the common first-attach case where the two slots
coincide). Reported in the wrap block, not silently patched or silently ignored.

## 3. `BookTextSummaryDisplayTests.swift` (new)

`@testable import SkriftMobile`, pure — no store IO, no `Audiobook`/`BookAlignmentRunner`
dependency beyond the `BookTextSummary`/`PerText` value types themselves (fixtures built
inline, same style as `AlignedSentenceSourceTests.swift`). Covers every `BookTextDisplay`
function named in §1: percent rounding (incl. 0-duration guard, clamp at 100), duration h/min
formatting (sub-hour, over-hour zero-padded minutes, 0s), `barSegments` span→fraction math
(single span, multiple texts with a gap between, zero gap/back-to-back spans, spans clamped to
`bookDuration`, empty `perText` → one full-width uncovered segment, `bookDuration <= 0` →
empty), color-index cycling (0/1/2/3 → 0/1/0/1), and the full-match/partial wording rule at
its boundary (exactly at the 97% tolerance, just under, zero `alignedFilesDuration`). No view
rendering — the conductor eyeballs the sheet at the merge gate.

## Self-check (EDIT-ONLY lane — no xcodebuild/simulator here)

Careful re-read of every touched call site against the file as it stands on disk, and every
field/function name against `BASE.md`'s pinned contract block verbatim (`AlignmentSource`,
`BookTextSummary`/`PerText`, `textSummary(bookID:)`, `removeText(filename:bookID:)`,
`attach(bookFileAt:bookID:)` unchanged signature). `BookTextSheet.swift` and its test file
depend on LANE_CORE2's not-yet-existing types, so a standalone `swiftc -typecheck` isn't
meaningful here (same situation the predecessor `LANES-2026-07-21C/PLAN_UI.md` documented) —
real gate is the conductor's merge-time build + vision-check.

## Uncertain decisions (see wrap table)
- `Color.skElev` for the bar's "uncovered" grey (vs. `Color.skBorder`, which is closer to the
  mock's literal `--elev2` grab-handle token but reads as near-invisible at 14pt solid fill).
- 97% tolerance constant for "full match" vs "partial" (not pinned anywhere; the aligner will
  essentially never claim literally 100% of a file down to the millisecond).
- Legend keeps its "transcript" grey chip even in the empty state, rather than hiding the
  legend row entirely when nothing is attached.
- Relocating the busy toast into the sheet (`busyMessage` passthrough) — a mechanical fix, not
  asked for verbatim, needed to make "busy alerts present over the sheet" literally true.
- Dashed Add-row styling sourced from `PersonEditorView`'s "＋ add" chip (cross-feature reuse,
  since Audiobooks has no add-affordance of its own) rather than the mock's literal
  `--elev2`-bordered dashed rule.
- `attachRejected`/`removeAttachedText`'s legacy-slot-only clear under multi-text — flagged as
  a known gap, not fixed (out of named scope; see §2).
