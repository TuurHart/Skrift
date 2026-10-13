# Q358 — built list vs the signed Q349 mock ("Skrift new" frames)

Pairs at the same scale: `compare-phone.png` (mock phone frame 402 pt screen, dark, beside the iPhone 17
sim screenshot scaled to 402 pt) and `compare-mac.png` (mock Mac sidebar 292 pt, light, beside the
`-snapshot-sidebar-selection -light` render, two 250 pt columns). Raw shots: `phone-list-*.png`,
`mac-sidebar-*.png`, `mac-card-kinds-light.png` (every note kind, rated left / unrated right).
The Mac renders and phone shots predate one last tweak (no repeated words: an image capture's
annotation and a bare link's domain no longer print twice); everything else is current.

## Differences on purpose (D194 picks, signed after the mock was drawn)
- Folder line: the mock frame still draws "• Personal" on every row; the build shows Portfolio only (D194).
- Unrated marker: not in the mock; the build draws a grey 6 pt dot + "Unrated" (folder-line size, faint
  colour) at the end of line 1, where the balls sat (D194). On a 250 pt Mac column with a pill it
  squeezes the title to ~12 characters ("Standu…").

## Colour
- Same tokens both sides (Palette: surface, bg, border, text, dim, faint, accent, amber). No differences seen.
- Mac pill colours: Queued/Enhancing use accentText on 12 % accent, as in the mock's Transcribing pill.

## Type
- Phone: header 19 bold, title 16 semibold, line 14, line 3 12.5 — matches the mock.
- Mac: header 13 bold, title 14 semibold, line 12.5, line 3 11.5 — matches.
- Line-2 date: mock uses tabular digits; build uses `.monospacedDigit()` — same.
- Media glyph: the mock's mic is a custom 11 px stroke; the build uses SF `mic.fill` / `book.closed.fill`
  / `link` / `video.fill` at 0.85 × line-3 size. Reads the same weight.

## Spacing
- Phone row padding 11 / 16 / 11 / 14, card radius 12, hairline from x = 16 to the card edge,
  52 pt thumbnail radius 7 — matches. Group header 18 above, 7 below — matches.
- Mac row padding 8 / 12 / 8 / 10, radius 9, 40 pt thumbnail, 8 pt card inset — matches.
- Mac snapshot harness columns are 250 pt wide, the mock's sidebar 292 pt, so built titles truncate earlier.
- A row with no line-2 text but a media marker (an untranscribed take) shows date alone on line 2 and
  the marker alone at the right of line 3; the mock has no such row.

## Not a row difference, seen in the phone pair
- Group ORDER follows the active sort: under "Newest" (= added date, Q105) the seeded demo note recorded
  in August but added today heads the list as "August" above "Previous 7 Days". The old per-day headers
  did the same ("Mon 11 Aug" on top). Apple Notes never shows this because it sorts by date edited.
