# Mocks source ledger — slice 2/N (files 25-48, alphabetical)

Date 2026-09-23. Rule in force: SPEC.md C276 — a cited document is not a folded
document; every mock gets a verdict. Range: `journal-desktop.html` through
`phone-name-linking.html` (24 files) under `Skrift_Native/SkriftDesktop/mocks/`.

Evidence sources: each mock's own `<h1>`/decision blocks, `FEATURES.md`,
`archive/state-2026-09/backlog.md`, `git log --all -- <path>`, and
`plan/extraction/mocks-roadmap.md` (an existing spec-extraction pass over all 71
mocks — cited here as evidence, cross-checked against FEATURES.md/git/SPEC.md/
roadmap.yaml, not taken on faith; that doc is itself a candidate for folding,
not a fold). SPEC.md/roadmap.yaml direct-citation counts were checked by grep;
most of this slice is not yet named in SPEC.md by filename — the "live id"
column gives the roadmap.yaml node that carries the underlying feature instead.

| mock file | screen | verdict | evidence (commit / doc:line) | live id or OPEN |
|---|---|---|---|---|
| journal-desktop.html | Journal on Mac (+iPad) — rail/column/map, iPad §2, body-parity §3 | BUILT (§3 Mac PDF-inline remainder open) | commit ca50c389 (sign-off 2026-07-11); FEATURES.md:117,385; mocks-roadmap.md:25 | DParityB — roadmap.yaml:1309, status `inprogress` |
| journal-retrieval.html | Journal & retrieval home — river, calendar, map, thread, search, Related card | BUILT 2026-07-06/07; tab renamed "Review" | commit d93399b5; mocks-roadmap.md:26; backlog.md:546,554 | P8 — roadmap.yaml:1504, status `done` (2026-07-07) |
| lifecycle-ia-explorations.html | Lifecycle IA — 3 directions for the overlapping-state mess, spine, Q1-Q7 | BUILT 2026-07-21 (walkthrough owed) | commit 7b970938; FEATURES.md:87; mocks-roadmap.md:27 | LifeIA — roadmap.yaml:522, status `inprogress` |
| lifecycle-triage-peek.html | Triage peek repair — say no, say why, show the photo; m0-m6 | BUILT 2026-07-22 (m6 = build spec) | commit d27a0477; FEATURES.md:87; mocks-roadmap.md:28 | LifeIA — roadmap.yaml:522, status `inprogress` |
| mac-live-transcription.html | Mac live transcription — three surfaces (m1 pane/m2 dictation/m3 card); m2 picked | BUILT 2026-07-28 | commits 9eb305fd, c0d56bf6, ddc72503; SPEC.md:1122 (C220); mocks-roadmap.md:29 | W8 — roadmap.yaml:2094, status `inprogress` (owed: mid-take edit check, paragraph eyeball, clean phone re-run) |
| mac-new-note.html | New note (typed) on the Mac — header placement + empty note; m2 compose chip | BUILT 2026-07-28 | commit e1474ebc; FEATURES.md:61; mocks-roadmap.md:30 | W9 — roadmap.yaml:2125, status `done` (2026-07-28) |
| mac-note-header.html | Mac note header, lighter, at the iPad's weight | BUILT 2026-07-25 | commits 544dda76, 1756b9bd; FEATURES.md:58; mocks-roadmap.md:31 | IPadWave1 (r3) — see below, status `inprogress` |
| mac-notes-list-rich.html | Mac notes list — rich rows (iPad parity); m2 picked | BUILT 2026-08-19 (thumbnails + place/tags chips open) | commit 15aa31e4; FEATURES.md:62; mocks-roadmap.md:32 | NoteCardM2 — roadmap.yaml:683, status `inprogress` |
| mac-record-button.html | Recording on the Mac — where the button lives; option B picked | BUILT 2026-07-28 | commit bb77ace9; FEATURES.md:307; mocks-roadmap.md:33 | W7 (per mocks-roadmap.md map col) — treat as done, folds into W8/W9 line |
| name-a-speaker.html | Name a speaker — Mac review, conversation turns, Speaker N → person picker | BUILT (naming chunk 4, 2026-06-16) | FEATURES.md:74 ("learns the voice on pick" on Mac unverified); mocks-roadmap.md:34 | P0 — roadmap.yaml:22, status `done` |
| name-unlink.html | Unlink a [[name]] — click-a-linked-mention popover; 2 scopes + undo | BUILT | commit 7cb634d3; FEATURES.md:342 (per mocks-roadmap citation); mocks-roadmap.md:35 | P0 — roadmap.yaml:22, status `done` |
| names-mac.html | Mac Names screen — redesign to match the phone (avatars, voice status, side-by-side editor) | EXPLORATION / unsigned — list-to-detail editor built 2026-06-15 without this mock's sign-off; full parity NOT built | commit f651c660 (mock authored, no sign-off recorded); mocks-roadmap.md:36,469 | i6 — roadmap.yaml:2409, status idea/`planned` tier — **needs Tuur** |
| naming-review.html | Naming review — opt-out model, 3 risk tiers | BUILT, signed off 2026-06-16; supersedes opt-in-naming.html | commit 5ffb7de7; backlog.md; mocks-roadmap.md:37 | P0 — roadmap.yaml:22, status `done` |
| note-destination-tags.html | Destination + tag input — 3 versions; B collapsed signed off 2026-08-26 | BUILT 2026-08-26/27, merged to main (commit 8d6b6519 confirmed ancestor of origin/main) | commit 8d6b6519; FEATURES.md:68; mocks-roadmap.md:38 | ExportDestinations — roadmap.yaml:755, status `inprogress` (node text predates the main-merge check done here) |
| note-editor-redesign.html | Note editor re-foundation — B2 pinned title; the spec v2 | BUILT 2026-07-06/07 | commits 8727f7bb, 30822948, 2f0e4aef; mocks-roadmap.md:39 | NEdit — roadmap.yaml:275, status `done` (2026-07-10) |
| notes-book-presence-debate.html | The Hendri debate — card vs live chrome vs dashboard, where the book lives on Notes | EXPLORATION — 3-way debate; resolved as "cards for starting, chrome for controlling" (build 48), with notes-compact-header.html as the paired signed mock | commit 32f27bfd; backlog.md:5012-5076; mocks-roadmap.md:40 | D4 — roadmap.yaml:1997, status `done` (2026-07-07; later rounds built on top through b48-51 per backlog) |
| notes-bottom-chrome.html | Notes bottom chrome — record + book bar; split row (A) vs centered record (B) | EXPLORATION — A picked, BUILT (60pt row, build 46) | commit 7d51bcd3; backlog.md:5072; mocks-roadmap.md:41 | D4 — roadmap.yaml:1997, status `done` |
| notes-compact-header.html | Notes — compact header + continue-listening card above search | BUILT (build 49), signed | commit 5f6792be; backlog.md:5076; mocks-roadmap.md:42 | D4 — roadmap.yaml:1997, status `done` |
| notes-pill-v2-iterations.html | V2 pill separation iterations a/b/c (Henry's crowding critique) | EXPLORATION — V2a picked, BUILT into build 47, survives as the "pill-when-live" state after the Hendri-debate redesign | commit b6b4f5f1; backlog.md:5076; mocks-roadmap.md:43 | D4 — roadmap.yaml:1997, status `done` |
| notes-pill-variants.html | Notes book pill — three interiors (V1/V2/V3) | EXPLORATION — V2 picked, iterated further in notes-pill-v2-iterations.html | commit c2f48d50; backlog.md:5076; mocks-roadmap.md:44 | D4 — roadmap.yaml:1997, status `done` |
| obsidian-plugin-menu.html | Skrift x Obsidian — the plugin, as a menu; 10 wireframes | SIGNED-OFF-NOT-BUILT (partial) — Tuur picked a v1 bundle (real inbox + sync doctor + listen-to-any-note), full menu order still open | commit 66e2f159; mocks-roadmap.md:45,384,469 | ObsidianPlugin — roadmap.yaml:834, status `planned` |
| opt-in-naming.html | Opt-in naming — proposal, locked 2026-06-15 | SUPERSEDED by naming-review.html (2026-06-16, opt-out model) | commits 103df154, 3d077df2; backlog.md:7315,7375; mocks-roadmap.md:46 | superseded — no live id (see naming-review row) |
| pdf-inline-capture.html | Scanned/shared PDF — inline in the note; variant A signed off, built same day (phone) | BUILT (phone) 2026-07-07; Mac inline remainder SIGNED-OFF-NOT-BUILT (flagged follow-up) | commits e1a78c15, 0f7e4800; FEATURES.md:52,147; mocks-roadmap.md:47 | DParityB — roadmap.yaml:1309, status `inprogress` (Mac half) |
| phone-name-linking.html | Phone name-linking — interactive; 4-tier linking, dialogs, chip bar, person editor | BUILT 2026-06-25 | commits dce53c31, c4b35fb6; FEATURES.md:335,339; mocks-roadmap.md:48 | P0 — roadmap.yaml:22, status `done` |

## Signed off, not built

**names-mac.html** — Mac Names screen redesign, matching the phone.
- Avatars + voice status per person, mirroring the phone's person card.
- Side-by-side list -> detail editor layout (phone's editor was built 2026-06-15, this mock's full-parity redesign was not signed).
- Mac in-place name-linking: a dotted/tappable linkable word on the RAW transcript before enhance (today the Mac only dots suggestions AFTER enhance).
- No sign-off date recorded anywhere searched (backlog, FEATURES, SPEC, mocks-roadmap all say "unsigned" / "EXP").
- Tracked as roadmap idea `i6` (roadmap.yaml:2409), not yet promoted to a lane node.

**obsidian-plugin-menu.html** — the Obsidian plugin, drawn as 10 wireframe options.
- Recommended v1 bundle: (1) listen to any note inline with karaoke, (2) the real inbox filing a note into PARA with Skrift following moves, (4) a sync doctor naming conflict copies.
- Connections as a plugin feature REJECTED — Tuur: "dont like stale data" (static sidecar tier killed; Mac-live only).
- Menu order/scope beyond the v1 bundle: no recorded pick — "don't start until Tuur picks off the menu" (mocks-roadmap.md:384).
- Nothing built; tracked as roadmap.yaml `ObsidianPlugin` (line 834), status `planned`.

**pdf-inline-capture.html (Mac half)** — phone variant A is built; the Mac side of the same decision is not.
- First page of a scanned/shared PDF renders inline full-width in the Mac note column with an "N pages" chip (same rule as phone).
- Tap opens a zooming viewer with markup (phone-parity).
- Named as a follow-up in FEATURES.md:147, not a separate sign-off — same decision, unbuilt half.

## Needs Tuur

- **names-mac.html** — no recorded sign-off date found in backlog.md, FEATURES.md, SPEC.md, or git commit messages (the authoring commit f651c660 is a "design" commit, not a "sign-off" one, unlike naming-review.html's explicit `design(mock): signed-off …`). Confirm whether this redesign is approved before it gets scheduled.

## OPEN count

- BUILT: 17 (journal-desktop, journal-retrieval, lifecycle-ia-explorations, lifecycle-triage-peek, mac-live-transcription, mac-new-note, mac-note-header, mac-notes-list-rich, mac-record-button, name-a-speaker, name-unlink, naming-review, note-destination-tags, note-editor-redesign, notes-compact-header, pdf-inline-capture [phone half], phone-name-linking)
- BUILT via EXPLORATION (variant picked and shipped): 4 (notes-book-presence-debate, notes-bottom-chrome, notes-pill-v2-iterations, notes-pill-variants)
- SIGNED-OFF-NOT-BUILT (partial or full): 2 (obsidian-plugin-menu, pdf-inline-capture [Mac half, counted once above as partial])
- SUPERSEDED: 1 (opt-in-naming)
- UNKNOWN / needs Tuur: 1 (names-mac)
- Total mocks in slice: 24

No filename in this slice is directly cited by SPEC.md except journal-desktop, mac-notes-list-rich, name-a-speaker, name-unlink and lifecycle-ia-explorations (1 hit each, grep-verified) — the rest of this slice's decisions live only in FEATURES.md/backlog.md/git history and the roadmap.yaml node graph, not yet folded into SPEC.md as clauses.
