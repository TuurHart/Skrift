# Mock source ledger — slice 1 of 3

Date 2026-09-23. Rule in force: SPEC.md C276 — a cited document is not a folded document;
every mock gets a verdict. This slice covers the first 24 files, alphabetically, under
`Skrift_Native/SkriftDesktop/mocks/*.html`: `accessory-bar-v2.html` through
`ipad-player-position.html`. Two other slices cover the rest of that directory plus
`roadmap/mocks/`. 24 mocks in this slice.

Evidence keys used below: commit hashes are `git log --all -- <mock path>` /
`git log -i --grep`; `roadmap.yaml` node ids are from `roadmap/roadmap.yaml`; `FEATURES.md:N`
is a line number in that file; `backlog.md:N` is `archive/state-2026-09/backlog.md`.

| mock file | screen | verdict | evidence (commit / doc:line) | live id or OPEN |
|---|---|---|---|---|
| accessory-bar-v2.html | iOS note keyboard accessory bar v2 + inline photo display-block | BUILT | commit 0cdd7a64 "SIGNED OFF" same day 2026-07-07; FEATURES.md:48; roadmap.yaml:421-427 (NFeat shipped log) | roadmap NFeat (status inprogress overall; this chunk shipped) |
| audiobook-bookmark-fold.html | audiobook reading-mode bookmark = page-corner dog-ear fold, gated to the now-playing line | BUILT | commits 1c5f2ba6→ebea929a→8b4ec223→85d90cd7 (builds 16-20); FEATURES.md:207-211 | roadmap D3 (done 2026-06-19) |
| audiobook-capture-merged.html | full-screen audiobook player + ONE note-style merged capture screen; retires the audio mark-in/out arm | BUILT | commit 605efec2 (2026-06-13); FEATURES.md:177 (`MergedCaptureView.swift`) | roadmap H_sprint (done) |
| audiobook-capture.html | original audiobook quote-capture spec: library / player / capture-moment mark-in-out / capture sheet / mini-player | SUPERSEDED | commit d33476e8 (2026-06-11, base); library + mini-player screens carried into the built app, but capture-moment + capture-sheet states were retired one day later — audiobook-capture-merged.html's own text: "the audio mark-in/out arm is retired... CaptureMomentView... removed" | roadmap H_sprint (done; superseded inside the same sprint) |
| audiobook-player-reading-mode.html | audiobook player e-reader "reading mode" + tab-bar IA redesign | BUILT | FEATURES.md:196 "built 2026-06-19 (build 14)"; roadmap D3 status done, done 2026-06-19 | roadmap D3 (done) — **CLAUDE.md's Ledgers bullet is stale**, it reads "signed off 2026-06-19 — not yet built" |
| audiobook-player-redesign.html | audiobook player redesign, text-forward A+D hybrid | BUILT | commit 25aa039d "signed-off mock" (2026-06-13); FEATURES.md:182; roadmap.yaml H_sprint shipped log | roadmap H_sprint (done) |
| book-sharing.html | share a book device-to-device as one `.skriftbook` file (AirDrop/Files/Messages) | BUILT | sign-off 427dd0f1; built 064114f5→d3535679; merged to main db9b6ff6 (confirmed ancestor of `main`); round-trip proven on-device 62ceaa0c; roadmap node BookShare status done, done 2026-08-12 | roadmap BookShare (done) — **CLAUDE.md's Ledgers bullet and memory `project_book_sharing.md` are both stale**, they read "NOT signed off yet" / branch not merged, written before the 2026-08-11/12 build and the later merge |
| book-text-sheet.html | book-text/coverage sheet, 3 variants: A list-first, B timeline-first, C options-row | mixed: B BUILT, A/C EXPLORATION | book-text-unified.html's own text: "Steady state = today's Book text sheet ... UNCHANGED from the signed-off book-text-sheet.html variant B"; roadmap EPubAlign shipped log "the timeline-first Book-text sheet (mock B)" | roadmap EPubAlign (done 2026-07-22) |
| book-text-unified.html | unified "Text…" sheet — merges Transcribe-book + Book-text into Level 1 (transcript) / Level 2 (book text) + A0 post-import prompt | BUILT | FEATURES.md:190 "signed off same day" 2026-07-23; roadmap idea i12 "SIGNED OFF AND BUILT 2026-07-23" | roadmap idea i12 (nodeHint EPubAlign) — the file's own `<title>` says "(PROPOSAL)" and an internal HTML comment says "NOT BUILT — awaiting sign-off"; both are stale artifacts left in the file itself, contradicted by FEATURES.md and roadmap.yaml |
| books-tab-and-resume.html | Books tab + one-tap resume: 3-tab IA, global mini-player, launch restore, sort/filter | BUILT | commit 122dbe6f (2026-07-07, code-first with the mock); FEATURES.md:213; roadmap D4 status done | roadmap D4 (done) |
| capture-items.html | capture items: share sheet (URL/text/image) → phone → Mac, annotation-as-note-body | BUILT | CLAUDE.md Ledgers "Capture items — BUILT 2026-06-12"; roadmap H_sprint shipped log "2026-06-12 Capture items shipped both lanes"; `CAPTURE_CONTRACT.md` (C3) | roadmap H_sprint (done) |
| capture-redesign.html | audiobook capture-moment mark-in/out interaction, 3 concepts + a Hybrid: tape deck / two-tap replay / phrase hopper / hybrid⭐ | SUPERSEDED | dated 2026-06-12 (commits 2c170de1/decab9cd/9cdd2b3c); the whole audio-marker approach was cut the next day (605efec2, 2026-06-13) — none of the 4 concepts, including the internally-favored Hybrid⭐, were built as designed | roadmap H_sprint (done; this exploration was cut inside the same sprint) |
| capture-sheet-trim.html | capture sheet sentence-level trim — tap a grey context sentence to include, tap an edge quote-sentence to drop | SUPERSEDED | dated 2026-06-12 (fb8cf340); explicitly named as removed in audiobook-capture-merged.html's own decisions text: "the old capture sheet's sentence-trim are removed" — though its tap-to-include sentence mechanic reappears via `TextCaptureSelection`, reused in the merged screen | roadmap H_sprint (done; cut inside the same sprint) |
| conversation-turn-headers-D.html | conversation speaker-label treatment, D-direction wireframes: D1-D6 gutter placements | BUILT (D1 picked) | file's own text, line 79: "The version you picked" (D1, right-aligned gutter); roadmap W6 status done, done 2026-07-27, "Design signed from mocks/conversation-turns-D-hifi.html: E1 (right gutter...)" | roadmap W6 (done) |
| conversation-turn-headers.html | how much markdown syntax should a speaker label wear — A/B/C/D exploration | mixed: D BUILT, A/B/C EXPLORATION | D ("the label leaves the paragraph") won over A (marks 22%, as-built-then), B (marks 10%), C (caret-reveal); D was refined into conversation-turn-headers-D.html then conversation-turns-D-hifi.html and built | roadmap W6 (done 2026-07-27) |
| conversation-turns-D-hifi.html | full-fidelity render of the D/E1 gutter direction, at real app scale, pre-build | BUILT | roadmap W6 (done 2026-07-27) cites this file by name: "Design signed from mocks/conversation-turns-D-hifi.html: E1"; memory `project_conversation_turn_gutter.md` "E1 SHIPPED + Tuur-confirmed 2026-07-27" | roadmap W6 (done) |
| fading-shelf.html | the note lifecycle "fading shelf" surface — untouched notes auto-fade toward trash | BUILT | FEATURES.md:87 "design LOCKED 2026-07-17, mock fading-shelf.html v3 ... 2026-07-18"; commit ad703d6c "v3 — phone shelves behind the Notes ⋯ (picked)" | FEATURES.md "Fading lifecycle" row (✅ both apps) |
| index.html | byte-identical copy of v2.html — an early Mac desktop-shell iteration ("review surface v2, critique applied") | SUPERSEDED | `md5` of index.html and v2.html match exactly; both superseded by v5.html, the "locked design" (commit eba5576d "v5 = locked design"); v5.html is what CLAUDE.md's Ledgers bullet cites as the signed-off desktop shell | OPEN — no roadmap node names `index.html` itself; it is dead weight, a leftover duplicate of a superseded file |
| ipad-app.html | "Skrift on the iPad — wave 1": Notes list↔note, Review standing calendar/places, Books shelf, record card (7 screens, m1-m7) | BUILT | FEATURES.md:103 "## iPad (universal target) — wave 1 built 2026-07-22 (mock ipad-app.html)"; every m1-m7 section carries its own inline "PICKED"/"not picked" verdict, dated 2026-07-22/23 (Tuur's own review pass, recorded in the file) | roadmap IPadWave1 (status inprogress — later iPad polish still open; memory `project_ipad_polish_fix.md` "iPad polishes FIXED 2026-08-12 b142") |
| ipad-chrome.html | iPad top-chrome, three directions: A = the Mac's bar ported, B = edge rails, C = quiet | BUILT (A picked) | file's own line 455: "✅ SIGNED — A, with Tuur's bar refinements (2026-07-23)"; FEATURES.md "Note bar (signed mocks/ipad-chrome.html A) ✅ 2026-07-23" | roadmap IPadWave1 (inprogress); B and C are EXPLORATION siblings, not picked |
| ipad-note-chrome-belongs.html | iPad note-view chrome v2 — Connections becomes an on-demand visitor sheet, word-only summon (no ◨ glyph, no count), one pinned ◧ | BUILT | backlog.md:3745 "iPad note view: signed 'chrome that belongs' BUILT + installed (build 132, 2026-07-24)"; commit 3c871ed confirmed an ancestor of `main` (merged via a1324974) | roadmap IPadWave1 (inprogress); the word-only-summon decision was later mirrored to the Mac too (FEATURES.md:386, 2026-07-25) |
| ipad-note-stacking.html | rebuild of the iPad note-view layout stacking — flat HStack, chrome band above the sliding columns, ◨ pins to the screen corner | BUILT | backlog.md:3838 "THE REDO — STACKING REBUILT (1f81136, build 130, installed on the iPad 2026-07-24)" | roadmap IPadWave1 (inprogress) |
| ipad-note-surfaces.html | visual-materiality pass on the same iPad note-view geometry — sidebars = grey surface, note = paper, chrome = real toolbar, player docks | BUILT | backlog.md:3768, cited alongside chrome-belongs v2 as part of the same signed spec: "+ mocks/ipad-note-surfaces.html for the tones"; build-132 board step 2 ("Surfaces: at regular, list column content bg → skSurface") | roadmap IPadWave1 (inprogress) |
| ipad-player-position.html | where the audio player should live on the iPad note — 3 directions (A/B/C) | BUILT (A picked, then rebuilt) | backlog.md:3812 "Tuur picked A ('make the right toggle match the native one on the left')"; build 127 installed, corrected in 128/129, then rebuilt in 130 (ipad-note-stacking.html) | roadmap IPadWave1 (inprogress); A's core call (player docks at the bottom) survived through to build 132, its chrome layout was superseded by the stacking rebuild |

## Signed off, not built

None in this slice.

## Needs Tuur

None in this slice — every mock in this 24-file slice resolved to a verdict from git
history, FEATURES.md, roadmap.yaml, or backlog.md. No unknown-status mock to flag.

## OPEN count

1 — `index.html`, a leftover byte-identical duplicate of the superseded `v2.html`. Not a
design decision to track, just a stale file; worth deleting in a cleanup pass but that is
out of scope for this ledger.

Verdict counts (24 mocks): **BUILT 18** (accessory-bar-v2, audiobook-bookmark-fold,
audiobook-capture-merged, audiobook-player-reading-mode, audiobook-player-redesign,
book-sharing, book-text-unified, books-tab-and-resume, capture-items,
conversation-turn-headers-D, conversation-turns-D-hifi, fading-shelf, ipad-app, ipad-chrome,
ipad-note-chrome-belongs, ipad-note-stacking, ipad-note-surfaces, ipad-player-position) ·
**SUPERSEDED 4** (audiobook-capture, capture-redesign, capture-sheet-trim, index.html) ·
**mixed BUILT+EXPLORATION 2** (book-text-sheet — B built, A/C exploration;
conversation-turn-headers — D built, A/B/C exploration) · **SIGNED-OFF-NOT-BUILT 0** ·
**UNKNOWN 0**.

Two files carry a genuine CLAUDE.md staleness finding, not just a mock-ledger gap:
audiobook-player-reading-mode.html and book-sharing.html are both fully BUILT and merged,
but CLAUDE.md's `mocks/*.html` Ledgers bullet still describes them as not-yet-built /
not-signed-off. Worth a CLAUDE.md correction pass.
