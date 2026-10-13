# Q355 article screens vs mock Q351-article-reader.html

Pairs: `q355-pair-*.png`, mock left, app right, both 402 x 874 (mock bezel cropped). iPhone 17 sim, dark
(the app's default), mock rendered dark. Seed data is short (`LibraryArticleDebug`), so "1 min read",
"0%" and "29%" against the mock's "41 min", "31%" are data, not layout.

## Share sheet (Article / Note): NOT SHOT
The share extension only runs inside a host app's share sheet. The one route tried,
`ShareFlowProbeUITests.testSafariShareToSkrift`, cannot find Safari's Share button on iOS 27
(`02b-no-share-button`), so it never opens Skrift. `q355-mock-share.png` is the mock frame alone.

## Tile (`q355-pair-tile.png`)
1. No type badge on the cover: the mock has an "ARTICLE" capsule top-left; the app cover has none.
2. App shows a byline line under the title ("Martin Kleppmann, Adam Wigg…", "Anil Dash"); the mock shows the title only.
3. App has a hint line "Tap a cover to open it. Hold a cover for its menu. Tap ❝ for its notes." under the sort row; not in the mock.
4. No Continue card row and no type chips (known from Q352, chips are Q356).
5. Cover colour and type match (dark brown `--cv-art`, mono site label, serif title).
6. Tab bar is the floating iOS 26 bar; the mock draws a flat bar.

## Reader with selection (`q355-pair-reader.png`)
1. No Copy / Highlight / ❝ Add note menu over the selection: the hook selects text programmatically and UITextView only shows its edit menu after a touch, so the menu is unverified, not missing.
2. Selection colour: app accent purple tint; mock system blue `rgba(10,132,255,.32)`.
3. No reading-progress line under the status bar (mock: accent line at 31%).
4. App pins a "❝ No notes yet / Add note saves a quote and your voice from here." card above the bottom bar, over the text; the mock has no such card before a note exists.
5. A system "Ready for Apple Intelligence" banner covered the nav row in this shot; `q355-pair-reader-after-note.png` shows it: back chevron, centred "inkandswitch.com", "⋯" without the mock's circle.
6. Heading weight: mock headings are heavier and larger than the app's.
7. Header block (site · article, title, byline, date · read time · Original page ↗) matches in order and colour.

## Reader after a note (`q355-pair-reader-after-note.png`)
1. Highlight is yellow (`--hl`) under the purple selection; the mock adds a ❝ glyph at the end of a noted sentence, the app has none.
2. "1 note from this article / Newest: …" row matches the mock's notes row, but it is pinned above the bottom bar instead of sitting at the end of the text.

## Capture (`q355-pair-capture.png`)
1. Mock wraps "Your highlight." + quote + link-back in one bordered card; the app has no card.
2. Mock's link-back is a boxed line "Links back to the article at 31%. The vault gets the title, the site and the URL"; app is a plain line "↗ Links back to the article at 29%." without the vault sentence.
3. Quote type: app about 15pt, mock about 17pt.
4. Header, rating pill, attribution "— *Local-first software*, inkandswitch.com" and the Record bar match.

## The note (`q355-pair-note.png`)
1. App shows an empty audio player (play, 0:00, 1x) above the tab bar on a note with no audio; the mock has none. Likely a defect: a text capture with no recording should not get a player.
2. Title: app shows the dim untitled placeholder (the quote's first words); the mock has a title because its note carries a recorded thought. Data.
3. App adds standard note chrome the mock leaves out: date chip, "Article quote · Local-first software" chip, "+ tag", "starts fading 12 Nov" warning.
4. Back control: app circular chevron + "+" / "⋯" capsule; mock "‹ Notes" text and circled "⋯".
5. Quote, attribution and "↗ Back to it at N% in Library" pill match the mock's idiom and accent colour.
