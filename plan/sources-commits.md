# Source ledger — commit-history slice

Date 2026-09-23. Built under SPEC.md C276 ("a cited document is not a folded document").
Repo: `.claude/worktrees/code-audit-report-4816f4`, branch
`claude/skrift-v2-core-rewrite-564928`, read-only except this file.

**Why.** Tuur asked whether feature/layout/iPad wishes from past chats live only in commit
messages, not the backlog. Answer: mostly no, not anymore. SPEC.md was built 2026-09-21/22/23
from a dedicated extraction pass and is unusually thorough — most commit-message decisions
already carry a clause, an `R`/`D` number, or shipped and are cited in FEATURES.md. The real
gap is smaller than feared: a handful of parked ideas whose precondition has since been met,
one design decision that was never given a number, and two fixes that exist on `main` only
under a different commit hash than the one an unmerged branch would suggest.

**Method.** `git log main` = 1,776 commits. Pulled full bodies for every commit whose message
matches `-i --grep=tuur` (283) and every commit matching
`-i --grep='decided|locked|signed off|verdict|direction|wants'` not already in that set (175
more, `strong-not-tuur`) — 458 commits read in full. A third bucket matching only
`never|always|feedback` (301 more, mostly "never overwrites X" engineering narration unrelated
to product wishes — spot-checked, not read in full) was scanned by subject line only. Every
hit in the 458 was checked against SPEC.md (C1–C282, D1–D100), BUGS.md, `roadmap/roadmap.yaml`
and FEATURES.md for a live verdict.

Rows below are the wishes/decisions with product weight (feature, layout, iPad behaviour, Mac
parity, naming, privacy, "don't fix back"). Pure bug-fix narration with no product statement is
skipped per the brief. Most rows are **DONE-SINCE** because this repo's commit style states the
wish and ships the fix in the same commit — that is not a gap, it is working as intended; they
are listed so the source is visible, not because anything needs doing.

## iPad

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| "the phone can't even export... only iPad and Mac can do that after they processed" | a8daa592 | 2026-08-11 | DONE-SINCE | export gated on `PolishCenter.isAvailable`, same commit |
| iPad `⋯` "should work like mac... shared code again remember" (Redo submenu) | 1fe9224c | 2026-08-18 | DONE-SINCE | one engine path, same commit |
| "if there is a Mac enhancement, I should be able to export it on the iPad" | 61dc8452, b8181a27 | 2026-08-14 | DONE-SINCE | `NoteWorkState` unified, C61/C62 |
| iPad list should show snippet/duration/place/tags/photos like desktop | 15aa31e4 → 24f0fc40 | 2026-08-18/19 | DONE-SINCE | shared `NoteCardView` (m2), FEATURES.md:62 |
| iPad verbs move to Mac's places (Record/✎ in header, Export in chrome) | 5de2b71c | 2026-08-18 | DONE-SINCE | same commit |
| massive note polished with no visible change (token budget flat 1024) | 45d78c19 | 2026-08-18 | DONE-SINCE | dynamic budget restored, same commit |
| second Process on iPad crashed (OOM, two MLX runs at once) | a18db65a | 2026-08-14 | DONE-SINCE | device-wide gate, same commit |
| iPad Connections panel loses the amber refine colour | 674e594c → 9e83d259 | 2026-08-14/18 | DONE-SINCE | `ConnectionsPanelLogic.isRefineImportance`, same fix |
| iPad polish crash / never loads model | 7bebdfc9 → acb7de8a | 2026-08-12 | DONE-SINCE | pin + entitlement + error handling, C180 |
| iPad model download never finishes (8.9 GB, no resume) | f4e6653f | 2026-08-14 | DONE-SINCE | `ResumableModelDownloader`, same commit |
| "more UI also if possible, see how other apps do this" (shared UI growth) | (C240 sitting) | 2026-09-22 | FOLDED | C240, research `plan/research/multiplatform-swiftui.md` |
| iPad `⋯`/Redo/mocks etc. — built, "his eyeball owed" | many (b148–b155 era) | 2026-07–08 | FOLDED (superseded) | C118 lists the still-owed device eyeballs as of 2026-09-22; earlier "owed" notes for the same surfaces are stale, not separate gaps |

## Mac parity

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| "check to see we share as much code between them to prevent drift" | (sitting) | 2026-09-22 | FOLDED | C239, twin audit before target 3 |
| Mac should have location too, same as phone/iPad | ad52b6f2 | 2026-08-27 | DONE-SINCE | `LocationOneShot` shared, same commit |
| "when I click export, what happens afterwards is not the same on Mac and iPad" | 6a08c647 | 2026-08-28 | DONE-SINCE | one `ExportOutcomeCopy` table, same commit |
| Mac's three vault-folder fields → one picker like phone/iPad | 1a2d5f51 → fadc5c86 | 2026-08-14 | DONE-SINCE | `VaultLayout.home`, C192, D11 |
| "no way to see what node I have selected in the left sidebar" | 04c0f093 | 2026-07-28 | DONE-SINCE | shared selection chrome, same commit |
| rating line names "the Mac" when the iPad also processes now | e36bf150 | 2026-08-14 | DONE-SINCE (partial) | wording fixed; state-aware line explicitly deferred in the same commit, no later commit or ledger row found — **OPEN** |
| "PipelineFile⇄Memo mirror... just adds needless complexity, can we simplify" | 66f9aaf3 | 2026-08-27 | DONE-SINCE | `MirroredNoteFields`, same commit |
| Mac records too, transcribes on stop like phone/iPad | 82c5b4ea, 343775b3 | 2026-07-28 | DONE-SINCE | C100 |
| Mac's own take never got karaoke on phone/iPad (no asset writer) | (names probe, Dutch rambles) | 2026-09-22 | FOLDED | R34/R35, C245 |
| conversation turn headers show literal `**` on Mac | 62ad74b1 | 2026-07-27 | DONE-SINCE | turn gutter, C175, FEATURES.md:254 |
| Connections panel colour/chrome drift Mac vs iPad | 71f9ef71, 674e594c | 2026-08-14 | DONE-SINCE | C232 |
| "chrome that belongs" Mac Connections mirror — de-float toolbar | e5821f5d | 2026-07-24 | FOLDED | C232 (built to related-panel v3 / chrome-belongs v2) |

## Editor / note UI

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| "the note writing itself should be better. it's quite slow and clunky atm" | (2026-09-21) | 2026-09-21 | FOLDED | C113, editor rebuild queued on body v2, confirmed |
| "when I quickly wanna write something down I reach for Apple Notes... simple smooth and fast" | (2026-09-21) | 2026-09-21 | FOLDED | C112, D28 |
| "the tags need to be revamped, the UI is annoying to use" | (sitting) | 2026-09-22 | FOLDED | C241, mock-first, rules stay C93 |
| tag sheet "adding tags is just annoying" (auto-focus, no vault tags on phone) | a998c0e8 | 2026-08-27 | DONE-SINCE | same commit |
| frontmatter key order "put the skrift hash in a more sensible order" | d21cc097 | 2026-08-14 | DONE-SINCE | same commit |
| Mac editor restyles whole document + writes model every keystroke | (perf sweep) | 2026-09-23 | FOLDED | C277, R90, measurement gated on iPhone 13 (C282) — not yet fixed, but tracked |
| conflict handling when two devices edit the same note | (sitting) | 2026-09-22 | FOLDED | C242, D24, mock-first |

## Capture / share

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| messenger share sender name "can just be filled in on the share screen or later" | (2026-09-21 probe) | 2026-09-21 | FOLDED | C123 |
| video in a WhatsApp bundle: "why else would I select it" (one note) | (sitting) | 2026-09-22 | FOLDED | C68, D69 |
| "no dont store videos, just skip them" | 9805a285 | 2026-08-27 | DONE-SINCE, then **SUPERSEDED** | reversed 2026-08-28 (a979bd54) once the archive use case surfaced; current rule is C63/C71/D44 |
| "I may send a video... that is gold... put it in my portfolio vault" | a979bd54 | 2026-08-28 | DONE-SINCE | movie kept as synced asset for Made/Idea/Inspiration, C63 |
| YouTube link: fetch the audio? | (sitting) | 2026-09-22 | FOLDED | D14, card-only, "broken features suck" |
| Instagram/TikTok: card + caption, never login-walled | (sitting) | 2026-09-22 | FOLDED | D15 |
| empty typed notes ("ik heb er drie lege notities staan") | (2026-09-22 probe) | 2026-09-22 | FOLDED | D91 |
| custom vocab additions lost on two offline devices | (data-loss sweep) | 2026-09-22 | FOLDED | R80, C267 |
| closing an active recording discards audio + photos, zero confirm | (data-loss sweep) | 2026-09-22 | FOLDED | R71, C262, D98 |

## Audiobooks

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| "Just 1 option. Share the audio with the epub... No bookmarks. No fluff." | 6a462229, 427dd0f1 | 2026-08-01/08-11 | DONE-SINCE | `.skriftbook`, C107 |
| "Why share with my own other device? Just sharing to others is fine" | cfa77f0a | 2026-07-30 | DONE-SINCE | person-to-person only, same commit |
| "Book transcription should not be stopped on low power mode" | 49ac1fc0 | 2026-07-30 | DONE-SINCE | charge-only pause policy, C106 |
| "ill rather have the ability to remove the transcript... same way as removing the epub" | 99df7014 | 2026-08-11 | DONE-SINCE | same commit |
| "the book would just stop if it was backgrounded" | (sitting) | 2026-09-22 | FOLDED, device test owed | C243 |
| "I think it took a lot of battery once" | (sitting) | 2026-09-22 | FOLDED, not yet measured | C244 |
| reading themes, player/bookmarks/Text sheet mocks | (various) | 2026-06 | FOLDED | C108, "remainder = reading themes" unverified |
| karaoke realignment for a hand-edited live take (mid-take edit) | cca2012c | 2026-07-28 | **OPEN** | "parked with its one open decision (edited takes need a timings-only pass)"; only appears in a roadmap shipped-log parenthetical (`roadmap.yaml:2114`), never promoted to a clause, `R`/`D` number, or BUGS row |
| Books tab "feels bolted on... but there is a way to make it make sense" | (Hendri, sitting) | 2026-09-22 | FOLDED, open by design | D90 |

## Names

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| "how could we keep track" otherwise — same full name = same person | (sitting) | 2026-09-23 | FOLDED | D96, C254, R61 withdrawn |
| the merge notice "should not be silent" | (sitting) | 2026-09-23 | FOLDED | C254, R62 |
| phone's "People in this note" chip bar — cut, names clickable like Mac | (sitting) | 2026-09-22 | FOLDED | D77, C80 |
| adding a person re-links every note automatically | (sitting) | 2026-09-22 | FOLDED | D32 |
| naming-review UX redesign (opt-out, in-prose) supersedes opt-in chip bar | 5ffb7de7 | 2026-06-16 | DONE-SINCE | superseded again by D77 above |

## Export / privacy

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| destination is a privacy boundary, "I know what I'm recording, I just click a button" | 5db9bc24, 37ae2c17 | 2026-08-26/27 | DONE-SINCE | no suggestion engine, C121, C133 |
| "AI reads this" boundary sharpened to cloud vs local, future local assistant "wide access" | (sitting) | 2026-09-22 | FOLDED | D86, C121 |
| archive keeps `[[names]]` — "credit where credit is due" | 8d6b6519 | 2026-08-26/27 | DONE-SINCE, reaffirmed | C137, Tuur 2026-08-27 + 2026-09-23 |
| "full name is cut off" (42-char filename cap) | c9c6b7d8 | 2026-08-28 | DONE-SINCE, then **SUPERSEDED** | raised to 120 then to 80 then to 120 again — C165, "if nobody cares let's go for 120" (2026-09-23 final) |
| "why is the name so weird" (bare timestamp filename) | c283a783 | 2026-08-28 | DONE-SINCE | title-named files, D39 |
| "we dont need the month either" (no month folder) | c9c6b7d8 | 2026-08-28 | DONE-SINCE | same commit |
| "if I select idea, I go to tags and type inspiration — that should not be possible" | 8d632df2 | 2026-08-27/28 | DONE-SINCE, then **SUPERSEDED** | tag guard added then removed one day later once the "inspiration on an idea" case was raised — current rule C93 |
| "type: idea" collides with archive's own `type:` key | 5db9bc24 | 2026-08-28 | DONE-SINCE | renamed/dropped keys, C130 |
| second destination's name "archive" not intuitive | (sitting) | 2026-09-23 | FOLDED | D100, default "Personal"/"Projects" |
| location in archive export — kept or dropped | (sitting) | 2026-09-23 | FOLDED | C137 confirmed keep |

## Lifecycle / rating

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| "pressing process shouldn't enhance unrated notes... do it the same as the phone" | 5adc8eb2 | 2026-07-28 | DONE-SINCE | `WayOutRules.unpipelined`, same commit |
| rating is consent, "until judged, Skrift spends nothing... shows it nowhere but back to you" | (2026-07-26) | 2026-07-26 | FOLDED | C87 |
| rating a one-way door | f2a47031 | 2026-07-26 | FOLDED | C88 |
| "locked can be processed no? it's just that no one should see it" | (sitting) | 2026-09-22 | FOLDED | D10, C91 |
| "when I get a phone call the recording is lost... never ever ever lose a recording" | 8b61e7b7 → (D4 fix) | 2026-08-22 | FOLDED, fix tracked | C99, D26, BUGS D4, issue #14 — still OPEN as a bug, but the wish itself has a verdict |
| three importance balls, no refine wall ("force me to pay attention... let's remove that friction") | (sitting) | 2026-09-22 | FOLDED | D30, D52, C94, C210 |

## Other (process, direction)

| his words (short) | commit | date | verdict | id / why |
|---|---|---|---|---|
| "months of AI patches accreted weird bugs" → rewrite v2 core one subsystem at a time | (2026-09-18) | 2026-09-18 | FOLDED | SPEC.md Point, C1 |
| "will you copy over the bugs?" → v1 is the change detector, never the judge | (2026-09-18) | 2026-09-18 | FOLDED | C5 |
| "the app is filled with my thoughts already... make a testing vault" (synthetic corpus) | (2026-09-18) | 2026-09-18 | FOLDED | C4 |
| "I don't like the start stop start stop" (whole project in one sitting) | (2026-09-18) | 2026-09-18 | FOLDED | SPEC.md Point |
| "dont build yet" / unrated-note doctrine as his own sentence | bf4f6a97 | 2026-07-26 | FOLDED | C87 (doctrine now codified) |
| Timeline-in-Review parked as an open design question | bf4f6a97 | 2026-07-26 | FOLDED (loose match) | roadmap idea P8c ("Calendar / timeline view") is the closest live tracker; not a verbatim link to his Review-screen framing — worth a sharper idea row if this specific shape still matters |
| Connections tightness lens — deferred until Obsidian vault connected | 97c8caad | 2026-07-25 | FOLDED, precondition now met | roadmap idea i13; SharedExport (the vault connection) shipped 2026-08, i13 has not been revisited since — ripe to re-raise, not a lost wish |
| "fleet ledger takes priority" (session prioritisation) | 98086a3d | 2026-08-12 | N/A | process note, not a product decision |
| the obsidian plugins as "a good standalone chapter in the roadmap" | 884a85b0 | 2026-08-11 | FOLDED | roadmap node ObsidianPlugin, lane 5 |
| i17 "maybe we should build both... dictate anywhere... but let's leave that for now" | (2026-07-28) | 2026-07-28 | FOLDED | roadmap idea i17 |

## Unmerged branch check

**(a) `ac9bbe3e`** ("Fix chunk-seam dropped word / merged sentences on run-on sentences",
`origin/claude/transcript-missing-content-0nsc26`, unmerged) — **exists on `main`.** Commit
`d14095ec6316f8d2b2471e4430f0fc1b9d872ee8` on `main` has the identical subject line and an
identical patch (`git show ac9bbe3e -- '*ChunkFusion*'` vs `git show d14095ec -- '*ChunkFusion*'`
diff to nothing but the commit hash line). `git log main -- '**/ChunkFusion.swift'` shows only
two commits ever touched the file: the original feature commit and `d14095ec`. Current
`ChunkFusion.swift` on `main` (lines 70–80) still carries the "device bug 2026-06-27" / rewind
comment from the fix. The branch's own commit was superseded by a same-day duplicate landing
directly on `main`, not lost.

**(b) `302c1d8a`** ("Add macOS CI: build + test gate for both native apps", same branch) —
**also exists on `main`.** `904d9792` on `main` has the identical subject and is followed by
merge commit `553755a4` "Merge transcript chunk-seam fix + macOS CI into main" (2026-06-27),
which explicitly folded both of that branch's commits into `main` under new hashes. `.github/workflows/ci.yml`
is present and live on `main` today. The `claude/transcript-missing-content-0nsc26` branch
itself was never merged (no merge commit references it by name), but its content was —
someone re-applied the same two commits by hand or via cherry-pick rather than merging the
branch, then the branch was abandoned unmerged. Nothing from it is missing on `main`.

## OPEN items

**3 items found with no live-ledger verdict, out of ~70 product-weight wishes reviewed:**

1. **Mac rating line stays stateless** ("ready to process" shown on an already-processed note) —
   `e36bf150`, 2026-08-14, explicitly deferred in-commit ("NOT fixed here, and worth its own
   pass"). No later commit, clause or BUGS row addresses it. Needs a BUGS.md row or a clause.
2. **Karaoke realignment after a hand-edited live take** — `cca2012c`, 2026-07-28, "parked with
   its one open decision (edited takes need a timings-only pass)". Only surfaces in a
   parenthetical inside a roadmap shipped-log line, never promoted to a decision, idea, or BUGS
   row. Needs an idea id or a `D` number so it can't be silently dropped.
3. **Timeline-in-Review** (the Review-screen timeline framing from the 2026-07-26 unrated-note
   doctrine session) — only loosely covered by generic roadmap idea P8c ("Calendar / timeline
   view", sourced from an old import list, not from this session). If the Review-screen shape
   still matters, it needs its own idea row citing `bf4f6a97`.

None of these block `/2-plan` under C276's letter (that rule targets archived plan/handoff/audit
docs, not raw commit history), but all three are genuine "his words, no verdict" gaps.

**By theme:** iPad 0 · Mac parity 1 (rating line) · editor/note UI 0 · capture/share 0 ·
audiobooks 1 (karaoke-after-edit) · names 0 · export/privacy 0 · lifecycle/rating 0 ·
other 1 (Timeline-in-Review, loose match only).
