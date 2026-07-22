# PLAN — BOOKS lane (base `ea51c7e`)

Scope: `Features/Audiobooks/**` only. Branch every layout on
`@Environment(\.horizontalSizeClass) == .regular`; compact stays byte-for-byte.

## 1. `AudiobookLibraryView.swift` — the shelf
- Add `horizontalSizeClass` env + `isRegular`; body's list slot becomes
  `booksContent` = `bookShelf` (regular) / `bookList` (compact, untouched).
- Extract two things out of `row(_:)`/`bookList`'s `ForEach` so the grid can
  reuse them byte-identical instead of forking behavior:
  - `openOrPlay(_:syncState:)` — today's Button-action (play/resume/redownload).
  - `contextMenuItems(_:)` — today's 4 long-press items (Transcribe book /
    Book text… / Sync…/Sync settings… / Delete).
- `bookShelf`: `ScrollView` + `LazyVGrid(adaptive, minimum: 170)` of new
  `BookShelfTile`s (square cover via `.aspectRatio(1, .fit)`, title, progress
  bar, "ch N · P%" / time-left line, sync glyph corner), tap → `openOrPlay`,
  long-press → `contextMenuItems`. Reuses `visibleBooks`/`bookSyncState`
  unchanged. Empty/no-match states mirror `bookList`'s text.
- New file `BookShelfTile.swift`: dumb, parent-driven (mirrors `BookCoverView`
  style). Static `progressLabel(for:)` is pure — unit-tested.

## 2. `ChaptersBookmarksSheet.swift` — shared rows + the new rail
- Extract the sheet's inline row bodies into bare, reusable top-level structs
  (no padding/chrome added — sheet's List rendering stays pixel-identical):
  `AudiobookChapterRow`, `AudiobookChapterSeparator`, `AudiobookBookmarkRow`.
- Extract the "row i → playable index" mapping (`chapterPlayableIndices`) to a
  free function so the sheet and the rail index "current" identically.
- New `ChaptersBookmarksRail`: both sections STACKED in one `ScrollView`
  (mock's `.chaps` pane, not tabbed like the sheet) — current chapter gets a
  `skAccentSoft` fill (BASE's pinned selected-row idiom); bookmark rows get a
  context-menu Remove (no `List`, so no native swipe). Parent-driven
  (`currentTime`/`bookmarks` passed in, seek/delete via callbacks) — no
  independent store reads, so it can never drift from the player's own
  `currentBookmarks`.
- Sheet keeps its exact public init/behavior — still presented for compact,
  and still reachable from the ⋯ menu at regular width (redundant-but-harmless
  over the always-visible rail; not forking `menu(_:)` to suppress it).

## 3. `AudiobookPlayerView.swift` — the three-zone regular layout
- `content(_:)` becomes a `@ViewBuilder` branch; today's body renamed
  `compactContent(_:)`, untouched. New `regularContent(_:)`:
  - LEFT 340pt (`regularLeftColumn`): collapse chevron + `menu(book)` reused
    at top (mock only draws "close" — kept the ⋯ so Edit/Transcribe/Book
    text/Sync/End-session stay reachable, a functionality-parity call over
    literal mock fidelity), 220×220 cover (tap = edit, reused id), title/
    author, reused `transport`, a new `regularUtilityRow` (today's
    `textSettingsButton`/`addNoteChip`/`speedMenu`/`sleepMenu` PLUS one new
    bookmark-toggle chip — additive, `utilityRow` itself untouched so compact
    can't regress), reused `scrubber(_:time:)`.
  - CENTER: a new chapter-heading label (`shortChapterLabel`, existing
    accessor) above `ReadAlongView` (unmodified per brief — "word karaoke
    unchanged"), wrapped in `.readingMeasure(560)`.
  - RIGHT `Adaptive.sidePanelWidth`: `ChaptersBookmarksRail`.
  - No `dismissDrag`/`toggleChrome` on the regular branch (chevron is the only
    dismiss; avoids a drag gesture fighting the rail/read-along's own scroll).
- New `bookmarkToggleChip` + `toggleBookmarkAtPlayhead()`: point-tolerance
  toggle (reuses `BookmarkStore.dedupeWindow`) against `currentBookmarks` —
  same store, same state, same toast/haptics idiom as the existing
  `toggleBookmark(inSpan:)`; not a new store or session API.
- New ids get the `ipad-` prefix (`ipad-library-book-shelf`,
  `ipad-library-book-tile`, `ipad-chapters-rail`, `ipad-player-bookmark`);
  every existing id (`player-collapse`, `player-cover-edit`, `player-menu`,
  `player-scrubber`, transport/utility ids, `player-readalong`) is reused as-is
  at both widths.

## 4. Tests
- `SkriftMobileTests/IPadBooksLogicTests.swift` (new, pure logic only):
  `BookShelfTile.progressLabel(for:)` — chapter/percent formatting, the
  "finished" threshold, and the no-chapters fallback.

## Untouched (confirms brief's "Keep")
`-seedAudiobook`/`-seedAudiobookIdle`/`-seedDetectedChapters`/`-showTOCSheet`
flag consumers (Root/App, not ours), `AudiobookMiniPlayerBar.swift` mounts,
AirPlay/route code, `AudiobookSession`/`Audiobook`/`AudiobookLibraryStore`
(Services/Audiobooks/** stays read-only).
