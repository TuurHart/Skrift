# BOOKS — the shelf + the wide player (mock m6)

FEATURE: at regular width the library's rows become a cover shelf (grid) and the player uses
the room: transport left, read-along at a reading measure, chapters/bookmarks as a standing
rail. Compact keeps today's rows + player untouched.

Build:
1. `AudiobookLibraryView` regular width → `LazyVGrid` shelf (adaptive columns ≈ 170pt): square
   `BookCoverView` (the covers ARE square in this app — keep 1:1), title line, thin progress
   bar + "ch N · P%" + time-left line, sync glyph on the cover corner (`checkmark.icloud` /
   `icloud.and.arrow.down` — same `bookSyncState` logic). Tap = play (the 2026-07-06
   convention, same `session.open` path); long-press context menu = EXACTLY today's items
   (Transcribe book / Book text… / Sync… / Delete). Status filter chips + toolbar + —
   unchanged, above the grid. Compact width keeps the List rows byte-identical.
2. `AudiobookPlayerView` regular width (m6 frame 2): three zones — LEFT ~340pt (cover, title,
   author, transport −15/play/+15, speed + bookmark + capture verbs, time scrubber), CENTER
   read-along at `readingMeasure(560)` (the existing ReadAlongView — word karaoke unchanged),
   RIGHT `Adaptive.sidePanelWidth` standing rail = the ChaptersBookmarksSheet CONTENT (chapters
   list with current highlighted + honest partial-chapter states, bookmarks below) hosted
   inline instead of as a sheet. The sheet presentation stays for compact. Quote-capture
   (`❝ capture`) keeps working from the wide layout.
3. `ChaptersBookmarksSheet`: refactor its list into a reusable subview both the sheet and the
   rail host (your file).
4. Keep: `-seedAudiobook`/`-seedAudiobookIdle`/`-seedDetectedChapters`/`-showTOCSheet` flags
   (screenshot rig), the mini-pill/bar mounts (SHELL owns MemosListView's pill — don't touch),
   AirPlay/route behavior, `AudiobookSession` API untouched.

Escalate: any AudiobookSession/store change beyond presentation, anything touching
MergedCaptureView's capture flow (presentation-width caps are fine).
