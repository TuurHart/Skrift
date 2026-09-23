# Source ledger — commit slice 6

Date: 2026-09-23. Rule in force: SPEC.md C276 (a cited document is not a folded document).
Commit range: rev-list --reverse main, positions 1111-1370 (260 commits), first-parent, oldest first.
Date span: 2026-07-13 to 2026-07-22.

Every row is a wish/decision/direction/reported problem stated by or clearly attributed to Tuur in a
commit message in this slice. Build narration with no product statement is skipped. Verdicts checked
against SPEC.md (C1-282/R1-94/D1-100/Decisions), BUGS.md, roadmap/roadmap.yaml, FEATURES.md as they
stand today (2026-09-23) — not against the archived `archive/state-2026-09/backlog.md`, which C276
treats as a cited source, not a folded one.

## Mac parity (phone <-> Mac feature catch-up)

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Mac editor should get memo-link chips + LINKED FROM strip like the phone | 13f31e5e | 07-13 | DONE-SINCE | built same commit |
| Journal should exist on the Mac as one simultaneous surface (queue\|journal, rail, map) | 10b5fd70 | 07-13 | DONE-SINCE | built same commit; roadmap `NFeat` shipped log |
| Checklists should be live-toggleable on the Mac, synced to phone | e1b40a22 | 07-13 | DONE-SINCE | built same commit |
| device test: Mac->phone syncs, phone->Mac reflect is broken (delete, tags) | 7e49c171 | 07-15 | DONE-SINCE | fixed same day, cfaf4703 (stale ModelContext) |
| device test: importance not editable on Mac; backlinks/chip-title wrong on phone | 7e49c171 | 07-15 | DONE-SINCE | d3dff2fc |
| device test: Mac filter/sort parity gap (phone's 5 sorts + multi-axis filters vs Mac's 3-way) | dabfe3f1 | 07-15 | OPEN | only in archived `backlog.md:5737`, not in FEATURES.md/roadmap/BUGS.md; FEATURES.md:85 still says "mobile keeps its 5 sort modes"; needs a BUGS.md row or queue item |
| device: Mac link chip renders raw `memo_<UUID>` for a title-less note | e3a98b02 | 07-16 | DONE-SINCE | fixed same commit |
| device: transcription feels slow (~1min/13s clip) | e3a98b02 | 07-16 | DONE-SINCE | embedder ANE-yield fix, same commit |
| Mac note-detail should get context chips + tag autocomplete (screenshot ask) | 027bf5fd | 07-16 | DONE-SINCE | built same commit |
| "just the way Obsidian works" — bare # browse + markdown headings on Mac | 48281d68 | 07-16 | DONE-SINCE | built same commit |
| pin the full markdown suite (bold/italic/highlight/strike, phone parity) but share the last edit first | 8197cfc9 | 07-16 | OPEN | roadmap idea i10 (roadmap.yaml:2346), still an idea, no queue item or clause |
| Mac search should jump to + flash the hit like the phone | 785a8156 | 07-16 | FOLDED (conflicting) | fixed same commit, but BUGS.md:281 "From the ledger, NOT re-verified" still lists "Mac search-jump parity gap" unresolved — stale ledger entry contradicts the commit's own claim; needs BUGS.md reconciliation |
| are the source icons shared code? | 45fb569c | 07-21 | DONE-SINCE | built same commit (SourceTaxonomy.swift, both apps) |
| Mac should author a Memo for locally-ingested files, like phone captures | 170db251 / ed59ba94 | 07-21 | DONE-SINCE | Q5 lock, built + tested through f888e01e |

## Editor / note UI

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| device: tag chip WALL doesn't scale, "tag, tag" placeholder reads weird | b20a8b08 | 07-16 | DONE-SINCE | redesigned same commit (typeahead dropdown) |
| device: typing after a snapped photo flashes/re-renders every keystroke | b20a8b08 | 07-16 | DONE-SINCE | fixed same commit, device-confirmed |
| next step after field typeahead = inline #tag popup, Obsidian idiom | ba2adc19 | 07-16 | DONE-SINCE | built same commit |
| device round 1: inline-tag popup slow, typed text vanished, backspace dead | d7988760 | 07-16 | DONE-SINCE | rebuilt as passive panel same commit |
| P1 decimal readout on rows; closeness only as hover tooltip, % only | 55402749 | 07-16 | DONE-SINCE | built in 66ccb3fa |
| Connections panel: warm color clash next to flame tag | ffcb7489 | 07-16 | DONE-SINCE | fixed same commit |
| light mode: accent+amber blend reads muddy on white | 2d9a6ea8 | 07-16 | DONE-SINCE | fixed same commit |
| review-note-detail: read-only note view for unprocessed notes, 2 open questions | 7f26294f | 07-17 | OPEN | parked (f360e446, "revive trigger inside"); not in SPEC/roadmap/BUGS live ledgers |
| review card importance dots render off-pixel | eae6c488 | 07-21 | DONE-SINCE | fixed same commit (whole-pixel pitch) |
| two buttons both say "Process" with different numbers — confusing | 578aa901 | 07-21 | DONE-SINCE | fixed same commit (Flag vs Process split) |
| "flag = it just moves into the notes, right?" — band container confuses even the owner | f6c3a40e | 07-21 | DONE-SINCE | band killed, unrated interleaved in list, same commit |
| screenshot: "Not rated" and "Newest" both wrap to two lines | 04b90033 | 07-21 | DONE-SINCE | fixed same commit |
| device: unrated audiobook quotes/videos/captures show wrong glyphs | 66194777 | 07-21 | DONE-SINCE | fixed same commit |

## Capture / share

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| a PDF capture on Mac should be a real document card, not a bare filename | 04466edf | 07-13 | DONE-SINCE | built same commit |
| sync the PDF file itself to the Mac, not just its text | 26ca90be | 07-15 | DONE-SINCE | built same commit (MemoAsset.Kind.document) |
| photo-OCR search edges on the Mac: local ingests un-OCR'd, OCR-only match can't flash | 522cae55 | 07-16 | OPEN | only in archived `backlog.md:5970`, no BUGS.md/SPEC row |

## Audiobooks (ePub <-> audiobook alignment)

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| attach the book's ePub, align against the whole-book transcript, published text becomes source of truth | 630236a7 | 07-19 | DONE-SINCE | roadmap `EPubAlign` status: done 2026-07-22; SPEC C227 |
| 5 ePub decisions locked (ePub TOC wins, aligner-internal normalization, pin v0.15.5, ZIPFoundation approved, .epub primary) | f8f5ccba | 07-21 | DONE-SINCE (mostly) | roadmap EPubAlign note; "ePub wins" narrowed same slice, see next row |
| "ePub wins" broke chapters for books 2-3 of a trilogy | 57f9bf0b | 07-22 | DONE-SINCE | fixed same commit (per-file merge, not whole-book) |
| highlight trails the narrator in read-along | 2ff82b1d | 07-22 | DONE-SINCE | fixed same commit (exact per-word DP times) |
| phantom chapters from rejected sibling ePub files | 2ff82b1d | 07-22 | DONE-SINCE | fixed same commit (verdict-gated) |
| "no indication anything changed" after attach | 2ff82b1d | 07-22 | DONE-SINCE | fixed same commit (persistent toast + alerts) |
| "that's like ten minutes of gap" — book-text bar spacing lies about real gap size | cfeaf232 | 07-22 | DONE-SINCE | fixed same commit (strictly time-true bar) |
| full-match tolerance too strict — real file sits at 96.7% (credits + front matter) | ad5986e4 | 07-22 | DONE-SINCE | tuned same commit |
| aligner-internal number normalization must never touch display text | 925ecd69 | 07-21 | FOLDED | built per that lock, EN/NL number-word glue |

## Names / SharedKit consolidation

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Journal / Review label must read the same on both apps | 3521151f | 07-16 | DONE-SINCE | fixed same commit (SharedCopy.reviewTitle) |
| swipe-between-notes fights text editing on phone | 3521151f | 07-16 | DONE-SINCE | disabled same commit |
| rename twinned drift: renaming a person on phone drops voice enrollment; Mac lets a person save with no alias | 04e70429 | 07-16 | DONE-SINCE | fixed via shared PersonEditCore, same commit |

## Export / privacy

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| "the vault is a complete mirror of rated notes" — full-exportability doctrine (2026-07-18) | 6c95f3be | 07-18 | SUPERSEDED (in part) | SPEC C197: "superseded in part by C61 (processed-only, verb-driven). Confirm the narrowing" — still ⚠ open for Tuur to confirm |
| gaps found: no attachments reach vault, lat/lon dropped from frontmatter, remindAt/audiobook unexported, no completeness surface | 6c95f3be | 07-18 | FOLDED (partial) | attachments = phone parity chunk (still owed per 90da84c8); YAML-carries-all direction folded into later export destination work (project_export_destinations memory, not in this slice) |
| audiobook export = user's layer only (bookmarks into a Commonplace index note), never raw audio or bulk transcript by default | 90da84c8 | 07-18 | FOLDED | consistent with C195 (audio export is an opt-in per-note switch) and book-sharing decisions (later slices) |

## Lifecycle / rating

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| significance copy is stale — describes a sync gate that no longer exists | efa7d359 | 07-20 | DONE-SINCE | rewritten same commit (flag-to-process, not flag-to-send) |
| say "process" — the app's own verb, not the invented "polish" | eb3cbb03 | 07-20 | DONE-SINCE | fixed same commit |
| "why is it not automatic?" — fading/trash sweeps require an arming gate | ffcfb718 | 07-18 | DONE-SINCE | gate removed same commit, sweeps run from install |
| unread fading dot is lit forever — no signal | 036a71fc | 07-18 | DONE-SINCE | fixed same commit (fadeEntersAt vs last-seen) |
| "conservative with vertical space in Notes" — fading shelf chips take too much room | 8fc90b1b | 07-18 | DONE-SINCE | v3 picked (ad703d6c), built 2409c874/3e344079/fa6cd8b8 |
| Q1-Q7 picks: Two Rooms One Spine + exit conveyor direction for the lifecycle IA overhaul | 078f146f | 07-21 | SUPERSEDED | by the 2026-07-22 one-clock model (cbf87fff) — see below |
| device: "mac and phone are similar" — conveyor should live in Review on phone too (pick B) | a15aa052 | 07-21 | DONE-SINCE | built same commit |
| "will they know where stuff goes?" — fading notes need to stay findable + self-explain | c5e41c62 | 07-21 | DONE-SINCE | built same commit (search honesty + self-narration) |
| trash stays out of search, fading stays in — LOCKED | ff3ac044 | 07-21 | FOLDED | SPEC C90 |
| one-clock lifecycle signed: touch restarts 30d clock, Parked dies, circles ARE the flag, no silent 0.1, Delete everywhere, Lock = background verb only | d27a0477 / cbf87fff | 07-22 | FOLDED | SPEC C89, C91; supersedes the 07-17 "touched never fades" doctrine explicitly per commit message |
| device: "mac notes have more information" — phone rows need the clock line too | 68dbcc2b | 07-22 | DONE-SINCE | built same commit |
| asymmetry locked: Mac list = deciding room (always-on state), phone list = notebook (unrated is default, not an alarm) | 6a096bb4 | 07-22 | FOLDED | built same commit; consistent with current C88/C89/C90 framing |
| place-triggered resurfacing / "place notes with feeling" direction | 6094f623 | 07-18 | OPEN | SPEC.md:1550 lists it explicitly under "Parked ideas that are NOT decisions today" |

## Recording / other

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| lane batches should run under a standing playbook, not per-batch rules (adapted from the drone-lab playbook) | d5eb3ece | 07-21 | FOLDED | CLAUDE.md "Parallel lane batches run under LANE_PLAYBOOK.md" |
| map re-frames/snaps mid-gesture; camera should be owned explicitly | 15ee747a | 07-16 | DONE-SINCE | fixed same commit |
| "zoom in deep takes a lot of scrolls" — pin tap should dive, not require manual zoom | 6b03129c | 07-17 | DONE-SINCE | built same commit |
| device: phone map is a generation behind the Mac's map wave | 1a66eb1d | 07-21 | DONE-SINCE | ported same commit |
| device b89: map card caps at 3 rows, dive zooms out strangely, pinned selection lies, WayOut rows should peek like Mac | 24a92520 | 07-21 | DONE-SINCE | all four fixed same commit |

## OPEN items in this slice

Count: 8

1. **Mac filter/sort parity gap** (phone's 5 sorts + multi-axis filters vs the Mac's 3-way `QueueFilter`) — dabfe3f1, 2026-07-15. Only tracked in the archived `backlog.md`. Needs a BUGS.md row or roadmap/queue item.
2. **Roadmap idea i10** — Obsidian-grade markdown (bold/italic/highlight/strike, phone heading/#tag rendering + popup, ⌘B/⌘I). Still an unbuilt idea (roadmap.yaml:2346), no clause, no queue item.
3. **Mac search-jump parity — conflicting state.** Commit 785a8156 (2026-07-16) claims this was fixed, but BUGS.md:281 still lists "Mac search-jump parity gap" as unverified. Needs re-verification and BUGS.md reconciliation either way.
4. **review-note-detail** — read-only note-detail screen for unprocessed notes, parked with two open sign-off questions (7f26294f, f360e446). Absent from SPEC/roadmap/BUGS.
5. **photo-OCR search edges on the Mac** — local ingests un-OCR'd, an OCR-only search hit can't flash. Only in the archived backlog (line 5970).
6. **Full-exportability doctrine confirmation owed.** SPEC C197 explicitly flags itself as only partially superseded by C61 and says "Confirm the narrowing" — an open ⚠ for Tuur, not this slice's problem to close but still unresolved live.
7. **Place-triggered resurfacing / "place notes with feeling."** Explicitly parked, not a decision (SPEC.md:1550).
8. Corollary of #3: **stale BUGS.md entries generally** — at least one bug this slice's commits claim fixed (search-jump) is still carried as open in the live BUGS ledger, suggesting the "already fixed" triage pass in BUGS.md §5 may be incomplete for this window.
