# Commit-history source ledger — slice 8 of 8

Date 2026-09-23. Rule in force: SPEC.md C276 — a cited document is not a folded document; every wish
or decision gets a verdict. Commit range: rev 1630-1776 of `git rev-list --reverse main` (the end,
HEAD = 87690339). Span: 2026-08-01 to 2026-09-18. 147 commits read in full, oldest first.

Verdicts checked against: SPEC.md (C1-C282, R1-R94, D1-D100, Decisions log), BUGS.md,
roadmap/roadmap.yaml, FEATURES.md.

## Audiobooks (book sharing)

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| "Just 1 option. Share the audio with the epub... No bookmarks. No fluff." | 6a462229 | 08-01 | FOLDED | SPEC C107, D27; roadmap BookShare `done` 2026-08-12 |
| "Love it... Share what I have. No bookmarks. But all the other shit, share it." | 427dd0f1 | 08-11 | FOLDED | same, C107 |
| 5-chunk build (manifest/zip/UTI/share+arrival sheets), device round owed | 641de889 | 08-11 | FOLDED | roadmap BookShare `done`, shipped log |
| Remove transcript from Text sheet, "like removing an ePub" | 99df7014 | 08-11 | DONE-SINCE | fixed same day (65fc2733, page-cache bug) |
| Round trip proven on real bundle; "ill assume it works and tell you if it doesnt" | 59c009b5 | 08-12 | FOLDED | roadmap BookShare `done` |

## iPad

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| "the phone can't even export... only the iPad and the Mac can do that after they processed" | a8daa592 | 08-11 | FOLDED | Decisions log 08-11 "the phone does not export"; C53 |
| iPad can't process a note — reported, error text not captured | 23fb5a1e | 08-12 | FOLDED | chain fixed same week: model pin (afb93d5c/b8f8540e), crash→throw (fad9a7af), memory ceiling (19c36f72/acb7de8a); SPEC C28 |
| "1 note process, click process again on another, boem. out of memory and crash." | a18db65a | 08-14 | DONE-SINCE | one-at-a-time `busyMemoID` gate, same commit |
| "if there is a Mac enhancement, I should be able to export it on the iPad" | 61dc8452 / b8181a27 | 08-14 | FOLDED | SPEC :1021-1022, `NoteWorkState` three-state rule |
| iPad button "the counts are right, the button is not" | 86b79074 | 08-14 | FOLDED | same, NoteWorkState |
| iPad Connections panel loses amber refine colour | 674e594c | 08-14 | DONE-SINCE | fixed 9e83d259, test-pinned 0.7/0.8/1.0 |
| Connections panels twinned+drifted; looseness real, card-chrome not fixed | 71f9ef71 | 08-14 | OPEN | not in SPEC/BUGS/roadmap/FEATURES — needs a BUGS row (Mac draws cards, iPad draws bare rows) |
| iPad verbs move to Mac's places (Record/✎ header, Export in chrome) | 5de2b71c | 08-18 | DONE-SINCE | sim-verified same commit |
| "iPad can export so it should... exporting can be done in the app itself, not settings" | 807f0725 | 08-18 | DONE-SINCE | same commit, toggle+button deleted |
| iPad ⋯ "should work like mac in that menu... shared code again remember" (Redo) | 1fe9224c | 08-18 | DONE-SINCE | shared `copyEditGenerate` path, same commit |
| Export tap did nothing (no vault bookmark; author key never written) | f6a89131 | 08-18 | DONE-SINCE | fixed same commit |

## Mac parity

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| "dumb line cuz mac already did. and not just mac cuz ipad can too" (rating line) | e36bf150 | 08-14 | OPEN | wording fixed same commit; state-aware version explicitly deferred ("NOT fixed here") — not in SPEC/BUGS/roadmap |
| Mac list mock: iPad's rows (m0/m1/m2), signed off | 15aa31e4 / eed1c622 | 08-18 | DONE-SINCE | shared `NoteCardView` shipped c4dbd74b/24f0fc40/637dbd16 |
| Quiet rows printed the date twice | 64c88aa7 | 08-19 | DONE-SINCE | fixed same commit |
| "I think Mac should also have location, same as the phone and iPad" | ad52b6f2 | 08-27 | DONE-SINCE | fixed same commit; own-export gap fixed 946678de |
| "it just adds needless complexity. Can we just simplify it?" (PipelineFile⇄Memo mirror) | 66f9aaf3 | 08-27 | DONE-SINCE | `MirroredNoteFields` refactor, same commit |
| "what happens afterwards is not the same on Mac and iPad" (export outcome) | 6a08c647 | 08-28 | FOLDED | SPEC :1021, `ExportOutcomeCopy`/`NoteWorkState` tests |
| iPad export not shown on Mac — confirmed cosmetic, per-device ledger by design | 02072f5a | 08-28 | FOLDED | same, decision recorded not a bug |
| Mac prod promotion — Release build ARCHS/ONLY_ACTIVE_ARCH doctrine | e6245caa | 08-14 | FOLDED | CLAUDE.md build block carries the exact rule verbatim |

## Editor / note UI

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| New note — typed third verb ✎/⌘N, born unrated | 7bfdcc75 | 08-11 | DONE-SINCE | built + gate green same commit |
| "a lot of gaps in there" — paragraph breaks on every breath (round 11) | efb3b3fd | 08-11 | SUPERSEDED | by deterministic `ensureParagraphs` cure (f67b135d, 08-19) — the resolve-at-resumption fix alone didn't hold on long Dutch/mixed text |
| "put the skrift hash in a more sensible order in the yaml" | d21cc097 | 08-14 | DONE-SINCE | reordered same commit |
| Massive note polished with no visible change (copy-edit token budget) | 45d78c19 | 08-18 | DONE-SINCE | dynamic budget restored same commit |
| Copy-edit near-echo / missing paragraphs on Dutch text | fffe1168...f67b135d | 08-19 | FOLDED | Decisions log 08-19 "shrink guard keeps the unedited body" |
| "ill rather have the ability to remove the transcript... in line wiht what is already there" | 99df7014 | 08-11 | DONE-SINCE | (see Audiobooks row above) |
| picture-placement bug + image-drag ask (triage) | cc99d6ab | 08-18 | mixed | picture bug DONE-SINCE(e8f2a60e, 08-20); image-drag ask — OPEN, not in SPEC/BUGS/roadmap |
| "Probably because there's a picture in there" — paragraphs collapsed | e8f2a60e | 08-20 | DONE-SINCE | root cause fixed same commit (`extractAnchors` whitespace flatten) |
| "adding tags is just annoying" | a998c0e8 | 08-27 | DONE-SINCE | SPEC C93 confirms shipped behaviour |

## Capture / share

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Obsidian plugin "a good standalone chapter in the roadmap" | 884a85b0 | 08-11 | FOLDED | roadmap node ObsidianPlugin, lane 5, status `planned` |
| Vault folder model — "do it like u did in the mockup... make it smart" | 1a2d5f51 / fadc5c86 | 08-14 | FOLDED | SPEC C53, `VaultLayout.home` |
| Command Center: "the hub is a viewer, not a planner" (Huginn retired) | 0097487c | 08-27 | FOLDED | CLAUDE.md "How this project is run" section states exactly this |

## Export / privacy

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Export destinations — spec sign-off, four destinations one-of-four | 8d6b6519 | 08-26 | FOLDED | SPEC C120-C136, D100 |
| Destination is a privacy boundary, never two, stored field not a tag | 37ae2c17 | 08-27 | FOLDED | SPEC C121, C133 |
| Destination row on phone/iPad, collapsed chip | d7702652 | 08-27 | DONE-SINCE | built + UITest-verified same commit |
| Destination row on Mac, 3-way sync | 2d8f87d1 | 08-27 | DONE-SINCE | built + snapshot-verified same commit |
| Settings — one switch, one archive folder both apps | 020e7314 | 08-27 | DONE-SINCE | built + screenshot-verified same commit |
| Archive layout — notes land in the portfolio (folder/frontmatter/links rules) | 56e7df94 | 08-27 | FOLDED | SPEC C132-C136 |
| "no dont store videos, just skip them" | 9805a285 | 08-27 | SUPERSEDED | by a979bd54 (08-29) — reversed |
| "I may send a video... keep that in my portfolio vault, with transcription" | a979bd54 | 08-29 | FOLDED | SPEC C71, D44, C136 (movie kept as synced source asset for archive destinations) |
| Phone-imported video still loses the movie (known limit, "say the word if that flow matters") | a979bd54 | 08-29 | FOLDED | C71's synced-asset rule is device-agnostic in the v2 ingress model (C68/C69) |
| "I don't like the AI READS THIS label" / export button lying about destination | 4be836e3 | 08-27 | DONE-SINCE | fixed same commit, `NoteWorkState.label` |
| "should we have a type like personal idea inspiration... front matter" | 55417be0 | 08-27 | SUPERSEDED | `type:` pulled next day, 5db9bc24 (collision with archive's own key) |
| Archive frontmatter key collisions — type:/source:/author: squatting on the real archive's keys | 5db9bc24 | 08-28 | FOLDED | SPEC C130 |
| "if I select idea, I type inspiration — that should not be possible" then reversed: "I guess it's just an idea with a hashtag inspiration" | 8d632df2 | 08-28 | FOLDED | SPEC C93, C134 |
| "why is the name so weird" / "the name is not right, plz fix" (archive filename) | c283a783 | 08-28 | FOLDED | SPEC C132 |
| "full name is cut off" / "we dont need the month either" | 946678de / c9c6b7d8 | 08-28 | FOLDED | SPEC C132 (cap 120, flat folder) |
| Re-export after deletion refused forever, no way back | 176f5449 | 08-28 | DONE-SINCE | fixed same commit (`VaultStamp.locate`) |

## Lifecycle / rating

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Typed note pasted + rated 0.1 vanished from every list, 3 cloud copies safe | e3aff3e1 | 08-20 | FOLDED | Decisions log 08-20 "a waiting thing is never turned into a different thing"; roadmap RateToRow `inprogress` |
| Rate→row fix proven on real store; 2 stranded audiobook quotes found | b8c7e093 | 08-20 | FOLDED | roadmap RateToRow shipped note |
| Sweep tests polluting live Dev data (1987 stray folders) | a63e36ed | 08-20 | mixed | test leak DONE-SINCE(a63e36ed); cleanup of the ~1969 old folders explicitly "left for Tuur to decide" — OPEN, no ledger row |
| "Has a polish pass RUN?" answered by "is there content" — empty passes read unprocessed forever | 00e67299 | 08-26 | FOLDED | Decisions log 08-26; SPEC C37 (`processedAt`/`isProcessed`) |
| Idea: collapse importance control to 3 buttons | c72cb0a2 | 09-08 | FOLDED | SPEC D30, C94 — "three balls" decided 2026-09-22 |

## Recording

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Long recording lost after a phone call, nothing recovers it | 8b61e7b7 | 08-22 | FOLDED | SPEC D26 ("all three, fixed in v1 now" — 2026-09-22); GitHub issue #14; was BUGS.md D4, now superseded by the v2 decision |
| Rescue tool for orphaned rec_tmp files, MP4-shape parser | dd9264f5 | 08-23 | DONE-SINCE | tool built same commit; underlying bug tracked via D26/#14 |
| Low Power Mode fix — sim gate green, device-confirmed climbing 0%→7% | 50ec8a30 | 08-11 | DONE-SINCE | device-confirmed same session (65fc2733) |

## Other

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| Connections summon-on-rate / un-rate confirmed live ("very sexy, very hot") | 21907efb | 08-11 | DONE-SINCE | device-confirmed same commit |
| i17 (DICTATE ANYWHERE) near-half parked — "keep using what we have" | 26de4850 | 08-11 | FOLDED | roadmap idea i17 recorded verbatim |
| Audit plan — 3 data-loss paths (NamesStore non-atomic write, ProcessingCoordinator transcript-clear race, VaultExporter remove-then-copy) | 9f02900a | 09-01 | FOLDED | BUGS.md D1/D2/D3 |
| App "feels slow" at under 200 notes; lag leads narrowed to Release build | 9f02900a / 3ea24733 | 09-01 | FOLDED | BUGS.md §3 "Reported on device", SPEC R90-R94 |
| BUGS.md built — 21 open, 5 confirmed already-fixed, 3 corrections found | 06eb10b4 | 09-14 | FOLDED | this commit is the live BUGS.md itself |
| Lost-recording P0 filed as GitHub issue #14, re-verified against main | 34643b35 | 09-14 | FOLDED | BUGS.md D4 (superseded by D26 per above) |
| TestFlight install failures — root cause account-wide Apple force-expiry | 730e5950 | 08-30 | OPEN | tracked only in MEMORY.md `project_testflight`, not in SPEC/BUGS/roadmap/FEATURES |
| "months of AI patches accreted weird bugs" — rewrite the CORE, spec-first | d2c4592e | 09-18 | FOLDED | this decision produced the current SPEC.md; roadmap V2Core = `now` |
| Corpus is SYNTHETIC, never his real notes | 01de25af | 09-18 | FOLDED | CLAUDE.md hard rule "PRIVACY: never point AI/agents at the user's Obsidian vault"; SPEC C122 |
| Corpus gets an ingress layer — every media type through real share/import code | 87690339 | 09-18 | FOLDED | SPEC C68/C69, ingress fixtures cited throughout §Ingress |

## OPEN items in this slice

Count: 5

1. Connections panel card-chrome drift (Mac draws cards, iPad draws bare rows) — needs a BUGS row or queue item; source: 71f9ef71 (2026-08-14).
2. Rating-line wording is not state-aware (says "ready to process" on an already-processed note) — explicitly deferred, never picked back up; source: e36bf150 (2026-08-14).
3. Image-drag ask (dragging a photo within a note) — triaged, never built or ledgered; source: cc99d6ab (2026-08-18).
4. ~1969 stray `Audio Output Dev` test-leak folders on the Dev store — left for Tuur to decide, no ledger tracks cleanup; source: a63e36ed (2026-08-20).
5. TestFlight install-404 (account-wide Apple force-expiry) — resolution/status lives only in memory, not in any live ledger; source: 730e5950 (2026-08-30).
