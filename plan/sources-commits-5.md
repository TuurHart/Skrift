# Commit source ledger — slice 5 of 8

Date 2026-09-23. Built under SPEC.md C276 (a cited document is not a folded document).
Commit range: `git rev-list --reverse main | sed -n '851,1110p'` — 260 commits, oldest first.
Date span: 2026-07-01 (ed73ff35, doc consolidation) to 2026-07-13 (592a9b8a, Mac dedup sweep).
This slice is almost entirely the native-convergence "note-editing / share-ingest / audiobook
chapters / Journal v1" build week. Every row below states a WISH, DECISION, DIRECTION or
REPORTED PROBLEM in Tuur's words or clearly attributed to him, and its verdict against the live
ledgers (SPEC.md, BUGS.md, roadmap/roadmap.yaml, FEATURES.md). Pure build narration (which
build number, which test count, which xcodebuild flag) is skipped.

## iPad

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| iPad Journal panel = the same phone app at regular width, universal target | 23fa0131 | 2026-07-07 | FOLDED | C240, "Not doing" — no third app, iPad is the iPhone target |

## Mac parity

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Mac must honor locked notes, memo-links, photo-OCR search, reminders like the phone | 2d685e56 | 2026-07-07 | FOLDED | C91, C111 — Mac search-jump gap it left open is BUGS §4 |
| Mac Names screen redesigned to match the phone (avatars, voice status) | f651c660 | 2026-07-06 | DONE-SINCE | cite f651c660/b1b92585; live in FEATURES.md Names row |
| "significance" label → "Importance" on the Mac (parity with phone) | 3dd17913 | 2026-07-06 | FOLDED | C210 "user-facing word 'Importance'" |
| Mac custom vocab must push edits back, not just consume the phone's | 6f78ac10 | 2026-07-07 | DONE-SINCE | one-way-sync gap fixed; the SEPARATE concurrent-offline-add race is still open as BUGS D12/C267/R80 |
| Mac reconcile sweep must be duplicate-tolerant on a same-id clone pair | 592a9b8a | 2026-07-13 | FOLDED | C48 "same-id clones resolve to one keeper (alive > most content > latest edit)" — exact match |

## Editor / note UI

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Note-editing chunks 1-9 approved: checklists, memo-links, photo OCR, reminders, Face ID lock, doc scan, tag chip editor, accessory bar v2, PDF-inline, markup save-back | 56ed8b86 → d6d864b3 | 2026-07-06/07 | DONE-SINCE | live in FEATURES.md (Editable transcript, Locked notes, Note reminders, Photo OCR, Tag chip editor rows) |
| "Polished on your Mac" provenance caption isn't useful — drop it | d66a1ee7 | 2026-07-07 | **OPEN — contradicts SPEC** | C181 still lists "'Polished on your Mac' provenance" as required phone UI; current code has it REMOVED (`PolishedDisplayUITests.swift:27` comment) and only a stale mock (`phone-polished-display.html`) still shows it. C181 needs correcting or the removal needs re-litigating with Tuur — it cannot be both. |
| Accessory bar v2 variant B + photo display-block, picked off the mock | 0cdd7a64 | 2026-07-07 | SUPERSEDED | the photo-block half is superseded by the 2026-07-16 sentence-snap redesign (FEATURES.md row 54) and again by SPEC C10-C17 (v2 deletes `imageBreaks` entirely); accessory bar itself is FOLDED C235 |
| Shared inputs never get bubble chrome, "never ever" | 5acc049b | 2026-07-12 | FOLDED | SPEC "Not doing": "no bubble chrome on shared input" |
| A tap beside a photo shouldn't open the editor; a checkbox tap shouldn't miss | da3cfee0 | 2026-07-07 | DONE-SINCE | attachment hit-testing rewritten same commit |
| List long-press should open the context menu, not scroll the row | 5376a2fd | 2026-07-07 | DONE-SINCE | fixed same commit |

## Capture / share

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Share-ingest survey verdict pass: GO on the big wave (WhatsApp/Signal audio-first, always-one-note photos, podcasts→Books, email/Maps/text-file shares), SKIP vCards, no Highlights tab | cee92d7a, 59b0badb, 2fccab9e | 2026-07-10 | FOLDED | C67-C79, C123-C148, D33 (podcasts), "Not doing" (no vCard→Names), C229 (no Highlights tab) |
| Every share jumps to its note on next app-open; audio shares carry no ramble UI | aa0aa77c | 2026-07-10 | FOLDED | C66 |
| A WhatsApp multi-ITEM bundle (not multi-select) still only reads the first item | 9f31c26b | 2026-07-12 | FOLDED | C67 "⚠ required difference" — still listed as unfixed in the live spec, same shape |
| Share sheets can't record audio — iOS blocks extension recording, confirmed by Apple forum threads | 18da97ad | 2026-07-10 | FOLDED | Decisions log 2026-07-10 "Share-sheet dictation retired (iOS blocks it)" |
| No migration for pre-round-3 image captures — "the old version can go", it's test data | 18da97ad | 2026-07-10 | FOLDED | D4 / C203 "old test image-captures... stay as-is" |
| Voice-annotate a capture in-app (mic pill → live caption strip) replaces the dead sheet mic | c0e8e99e | 2026-07-12 | FOLDED | D71 |
| Shared PDF text renders as a collapsed disclosure row, "Show all N pages" reader | 85863dae | 2026-07-12 | FOLDED | D61 (PDF text is search-only, not exported) — live in FEATURES.md, Wave-3 row |
| Audio ≥ 1 hour should route to the Books importer, not a voice memo | b1c162a8 | 2026-07-11 | FOLDED | C79 |
| A Maps share should become a place-anchored note, no network fetch | 4ac6cbd6 | 2026-07-11 | FOLDED | C144 |
| Shared links should enrich on drain: title/description/thumbnail + readable article text, offline-only | d79c21a8 | 2026-07-12 | FOLDED | C72 |
| A mixed bundle (voice + photos + text) must become ONE note | ce0d5a3e | 2026-07-12 | FOLDED | C68 |
| PDF-from-Files was saved as a dead Link card; Safari PDF pages missing from the share sheet | 227861f4, 178cfb92 | 2026-07-10/11 | DONE-SINCE | root-caused and fixed same commits |
| In-app "Audio or video from Files" + "Video from Photos" import menu | c9566c6c | 2026-07-11 | FOLDED | C145, C199 |
| Wave-3 user retest list (share sheet from real apps, choosers, import menu) parked "with zero urgency" | 9d3e64d2 | 2026-07-12 | **OPEN** | never re-surfaced in BUGS.md or a queue item; C276 requires a verdict on every backlog item, this one has none |

## Audiobooks

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Chapter boundaries must come from the narration (silences + spoken headings), not file splits | ddc0c497, ce884357 | 2026-07-11 | FOLDED | C105 |
| Incomplete/holey chapter numbering must degrade to a book-level jump point, never a wrong list | 24c57d18, ce50a2e5, 548ad490 | 2026-07-12 | FOLDED | C105 "better no information than bad information" |
| One bad audiobook part shouldn't reject the whole book; report what was skipped | 6251cd06 | 2026-07-05 | DONE-SINCE | device-verified same commit |
| Book chunking moves to in-memory PCM + 180s chunks (no temp-WAV I/O, no CTC second pass) | ddc0c497 | 2026-07-11 | FOLDED | C106 |

## Names

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Names/vocab sync must push on edit, not wait for next foreground/refresh | 79975a7c | 2026-07-06 | DONE-SINCE | fixed same commit; general LWW doctrine is C85 |
| A phone-added person still has no aliases and never links (Stz020 #3) | c658a9a9 | 2026-07-06 | FOLDED | C83 / R12 — still a live required difference in the spec |

## Export / privacy

(covered above under Editor/UI — "no bubble chrome" — and under Capture/share — "no Highlights tab")

## Lifecycle / rating

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| The related/search floors must be calibrated from a real device histogram, not guessed | d118d232 | 2026-07-07 | FOLDED | C109 — his measured 0.45 related floor is the exact number in the spec today |

## Recording

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| A call/Siri/alarm interruption must not silently kill a recording while the timer keeps counting | 940da12f | 2026-07-07 | SUPERSEDED | this fix was insufficient — BUGS D4 shows the same "recording lost mid-call" report recurred 2026-08-22 in prod and is still open; C99/D26 ("never ever ever") is the later, fuller treatment |
| Pin FluidAudio to an exact commit instead of floating branch:main | 54930175 | 2026-07-11 | FOLDED | C167 "every engine and model are revision-pinned" |

## Other

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Reading the Obsidian vault "to compare notes over years" is wanted (vault lens) | f469e209 | 2026-07-07 | FOLDED | listed as a parked idea, "vault-read direction" — not a v2 decision |
| Roadmap history is wrong: the phone (H_rn) reads as a sibling of the Electron start, but it came half a year later | 8b4266fd | 2026-07-13 | DONE-SINCE | roadmap.yaml carries `H_whisper`/`H_rn` at the corrected order today |
| Anything living on both apps gets single-sourced in Shared/, in the same change | a5d3d5be, c73643dc, e53b50d6, 6e4ab098 | 2026-07-07 | FOLDED | C115, C239 |
| Bonjour/LAN sync is retired; CloudKit is the only transport | 36ff35bb, 510ad0c4, 0dab5002 | 2026-07-06 | FOLDED | CLAUDE.md hard rule, "Not doing" |
| Embedder choice: EmbeddingGemma-300M via CoreML-LLM wins the bake-off 10/10, Apple's NLContextualEmbedding eliminated | 4dbf2662, 6ab4d170 | 2026-07-07 | FOLDED | C109 — same engine named in the spec today |
| Tab rename Journal → Review; map gets Apple-Photos-style zoom-adaptive clustering | 6aa2295b | 2026-07-07 | FOLDED | C229 |
| Print-to-wall (crossing into the top rating tier silently prints a card) + "Important lately" card | 5eb3ede0 | 2026-07-07 | FOLDED | C233, C231 |
| "scan-into-this-note" and "Backlink Weaver" flagged as open design questions | cb4ac211, 7ae136ef | 2026-07-07/08 | FOLDED | both appear verbatim in SPEC's "Parked ideas" list — acknowledged, not decisions |
| "office-printer guard rule" (don't silently print-to-wall on a random/office printer) | 7ae136ef | 2026-07-08 | **OPEN** | mentioned once in an archived backlog note; no clause, BUGS row or roadmap idea names this guard — C233 only states "to the saved printer" with no office-network guard |

## OPEN items in this slice

Count: **4**

1. **C181 vs d66a1ee7** — SPEC C181 still requires the "Polished on your Mac" provenance caption on the phone; Tuur explicitly killed it 2026-07-07 and it has stayed dead since (current code and its own test comment confirm removal). The clause is stale and needs a decision, not a silent carry-forward.
2. **Wave-3 share-ingest user retest list** (9d3e64d2, 2026-07-12) — parked "with zero urgency," never turned into a BUGS row or queue item; falls through C276's own rule.
3. **Office-printer guard rule** (7ae136ef, 2026-07-08) — a named idea for the wall-printer feature that never got a clause, a BUGS row, or a roadmap idea id.
4. **Multi-item WhatsApp bundle** (9f31c26b) is technically folded (C67), listed here only as a flag that it's the SAME unresolved bug reported three times across this slice (827965fb, 394a9168, 9f31c26b) before finally landing in the spec — worth confirming C67's fix is actually queued, not just documented.
