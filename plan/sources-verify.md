# Source ledger — second-pass verification

Date: 2026-09-23. Rule in force: SPEC.md C276 ("a cited document is not a folded
document"). This is the mandatory second pass over the 19-agent source ledger
(`plan/sources-backlog-1..5.md`, `plan/sources-state.md`, `plan/sources-handoffs.md`,
`plan/sources-commits-1..8.md`, `plan/sources-mocks-1..3.md`). It does not repeat the
first pass's work; it hunts what that pass missed or got wrong.

Sample sizes: 125 lines across the 5 backlog slices (25 each, `grep -n` + `shuf -n 25`
on open-shaped patterns per the assigned line ranges); 25 lines across the 12
non-backlog state docs; 25 lines across the 12 handoff docs + ~40 memory files; 40
commits sampled from a from-scratch scan of all 1776 commits on `main` for
Tuur/wish-shaped language (broader than the two prior passes' own grep, described
below); 15 of 75 mocks (desktop `mocks/*.html` + `roadmap/mocks/*.html`). Plus a
targeted spot-check of ~21 citations (commit hashes and SPEC clause numbers) pulled
from FOLDED/DONE-SINCE rows across all families.

One methodology note: two different commit ledgers exist — the assigned
`plan/sources-commits-1..8.md` (8 files, sliced by `git rev-list --reverse main`
position, exactly matching the brief) and an unassigned extra file,
`plan/sources-commits.md` (a single file, built by a different grep pass —
`-i --grep=tuur` plus a `decided|locked|signed off|verdict|direction|wants` set, 458
commits). The second file isn't in this task's source list but exists in `plan/` and
does provide real, checkable coverage, so I used it too when checking commit citations.

## Coverage

### `archive/state-2026-09/backlog.md` (5 slices, 894 total open-shaped lines, 125 sampled)

**Slice 1 (1–1162), sampled 25.** 1 miss. Line 809, "Device eyeball owed: m2
photo-thumb rows + book-quote rows (iPad b155 / Dev Mac)" — inside the "rate→row"
session (753–1161), which the ledger's own text says it mined for "open threads" but
missed this one. Not in `plan/sources-backlog-1.md`, SPEC.md, BUGS.md, or
`roadmap/roadmap.yaml`. Genuinely untracked.

**Slice 2 (1163–2576), sampled 25.** 0 hard misses. 1 weak gap: lines 1205–1236,
"(was) 🔴 OPEN — the iPad's note button says 'Process'" (the Re-export flip needing a
vaulted device tap). The substance is tracked — `roadmap/roadmap.yaml:681` ("Sim-
verified; Re-export flip owed a vaulted device") and SPEC.md:1022 (A58/A65) — but
`plan/sources-backlog-2.md` has no row citing this line range at all, so a reader of
just the ledger would not find it.

**Slice 3 (2577–4420), sampled 25.** 1 miss. Lines 4332–4338, "Device eyeball owed —
build 87 INSTALLED on the phone 2026-07-20" (the 3-photo thumbnail repro). This sits
inside the "⭐ CONTINUE HERE (2026-07-18 remote session)" section, which
`plan/sources-backlog-3.md` does cover (its own `## ⭐ CONTINUE HERE 2026-07-18 session
(4329–4346)` header) — but the table under that header only pulled 2 of the 3 items
(the "pick a lane" note and the ePub spikes), and item 1 (the device-eyeball ask)
never got a row. Not in SPEC/BUGS/roadmap either.

**Slice 4 (4421–6099), sampled 25.** 1 soft miss (a cluster, not independently
severe). Lines 5699, 5707, 5713 — three "Device re-verify owed" tags on already-FIXED
memo-link bugs (SignificanceCircles gating, backlinks-missing fix, Mac chip showing
`memo_<UUID>`). None of the three appears in `plan/sources-backlog-4.md`, though the
doc's coverage elsewhere is otherwise exhaustive (it explicitly tracks the sibling "(c)
transient lost-the-link" item from the same list). Low priority — these are trailing
verify-tags on shipped fixes, not open bugs.

**Slice 5 (6100–end), sampled 25.** 1 miss. Lines 7978–8003, the entire "Device-
testing feedback — 2026-06-11" subsection: three new items (instant-record flashes
the old ready screen; AirPods re-insertion after removal doesn't resume input; Live
Activity shows stale on the lock screen after a fresh install). This subsection falls
in the numeric gap between two headers the ledger does cover ("Device-testing feedback
2026-06-10", stated range ending 7980, and "Audit findings 2026-06-09", starting
8008) — the boundary swallowed it. Confirmed absent from SPEC/BUGS/roadmap too. (One
item from the same subsection, "Reassign in the unlink popover," line 8003, IS
correctly captured under the 2026-06-10 table — so the miss is partial, not total.)

Estimated backlog miss rate: **4 solid misses in 125 sampled lines (≈3.2%)**, plus one
weak citation-only gap. All 4 misses share a pattern: a small, single-line device-
verify or eyeball-owed item nested inside a larger multi-item session dump that the
ledger otherwise covers well — the writer pulled the headline items and dropped a
minor sibling.

### Non-backlog state docs (`plan/sources-state.md`), sampled 25 lines across 12 docs

0 hard misses in the 12 docs the file explicitly scopes. 1 low-priority miss found by
following a citation, not by the direct sample: `SKRIFT_SOURCE_OF_TRUTH.md:456` names
`roadmap/HISTORY_BACKFILL.md` staging eras 1–5 "not yet built into the viz" — that file
(`roadmap/HISTORY_BACKFILL.md`) still exists in the repo today and is cited nowhere in
`plan/sources-state.md`, SPEC.md, BUGS.md, or roadmap.yaml. Low priority: the "viz" it
refers to (the in-repo `roadmap/ROADMAP.html`) was deleted 2026-06-29 per CLAUDE.md, so
whether this item is even still actionable against the current Command-Center-hosted
viz is unclear — it would need a fresh look, not a straight re-open.

Several FEATURES.md rows in my raw sample ("Device eyeball owed" trailing notes on ✅
already-shipped rows) are **correctly** out of scope — the doc's own header states
"FEATURES.md (planned/partial/owed rows only)," and the file's `OPEN items` count (0
for FEATURES.md, one flagged FOLDED-but-open) matches that stated scope. Not misses.

Estimated miss rate: **1 in 25 sampled (4%)**, low severity.

### `archive/handoffs/*.md` + `memory/*.md` (`plan/sources-handoffs.md`), sampled 25

0 misses found. Spot-checked two "open-shaped" hits inside `WALKTHROUGH_BUGS.md` (W2
cursor fix, N7 karaoke reflow fix) that looked unrowed — both are marked ☑ fixed in
the source doc itself, and the doc's own "Remaining (walkthrough)" section states "All
cleared... W2 cursor... all done," so their exclusion from the ledger's table (which
only rows the doc's ☐ open items — C1, ST7, E4, N2) is correct, not a gap. The dozens
of "device-owed" phase-checkpoint notes inside `MOBILE_NATIVE_HANDOFF.md`'s raw
session ledger (real camera, location, weather, live POST — June 2026 rewrite
checkpoints) are also correctly treated as superseded noise, since the app has shipped
and been in daily use since; the file's actual surviving open items (memory-aid
prompts, photo filmstrip, Settings storage stats, several "OPEN" rows) are captured.

Estimated miss rate: **0 in 25 sampled (0%).**

### Commits (`plan/sources-commits-1..8.md` + the extra `plan/sources-commits.md`)

Built a from-scratch list of all 1776 commits on `main` (`git rev-list --reverse
main`), matched bodies against a broad Tuur/wish/decision pattern (458 hits,
coincidentally the same count the existing `sources-commits.md` reports for its own
narrower two-bucket grep), sampled 40, and checked each short hash against every
commit-ledger file. 18 of 40 (45%) resolve to a citing row in some commit ledger; 22 of
40 (55%) do not.

That raw number overstates the real gap. Manually reading the 22 "zero-hit" bodies:
most are pure merges (`Merge pull request #10...`), refactors/tests with no product
statement (`refactor(shared): ONE LockGate`, `test(align): twin AlignmentCore test
suites`), or `docs(backlog): ...` commits whose entire content is a `backlog.md`
edit — already covered by the backlog-family ledger, so a second citation in the
commit ledger would be pure duplication, not a gap. A few (P0 clobber root-cause fix
`56f360e9`, the Connections-summon consent fix `2699f64d`) are already-shipped,
already-closed bugs referenced by substance elsewhere (memory notes, other backlog
rows) even though this exact hash isn't quoted.

Given that, I don't have confidence the true commit-ledger miss rate is as low as the
other families' — the two-ledger split plus the heavy backlog/commit redundancy makes
"did this get a row" a much fuzzier question here than for the other four families.
Treat the commit family's coverage as unverified rather than confirmed-good.

## Wrong verdicts

Two confirmed citation errors, both found while spot-checking commit-hash citations
(not from the coverage sample above):

1. **`plan/sources-backlog-1.md`, "Copy-edit fix-wave board item 3 — shrink guard | 988
   | DONE-SINCE | Same commit `f67b135d`."** Claimed: the shrink guard shipped in
   commit `f67b135d`. True: `f67b135d` ("the wall cure — deterministic paragraphs...")
   is a *different*, sibling commit — the shrink guard itself shipped 3 minutes
   earlier the same day in `10705445` ("shrink guard in both engines + A/B harness
   flag"). Both commits are real and both fixes did ship, so the DONE-SINCE
   *conclusion* is still correct — only the cited hash is wrong.

2. **`plan/sources-backlog-5.md:193`, "Task A: auto-sync names after voice enrollment
   | 7670 | DONE-SINCE | ... (commits `23a1e3a`/`79975a7`)."** `23a1e3a` does not
   resolve to any object in this repository (`git cat-file -t 23a1e3a` → "Not a valid
   object name"; not found via `git log --all --oneline | grep 23a1e3a` either). It
   looks fabricated or badly mistyped. `79975a7` is real and does match the claim
   ("fix(sync): push names/vocab to CloudKit on edit..."), so the row's conclusion is
   still supported by its second citation — only the first hash is fake.

Every other citation checked (11 commit hashes: `cb096394`, `5de2b71c`, `0dab500`,
`b8f8540`, `fad9a7af`, `a6126e0`, `08bcdf57`, `f150455a`, `79975a7`, plus the external
FluidAudio package revision `7f963cdc`; and 9 SPEC clause numbers: C99, D26, C50, R8,
C232, C219, D71, C75, C72) resolved to real objects/clauses whose content matched the
row's claim. One early false alarm on C219 turned out to be my own error (its first
line reads generically, "the schema is additive-only," but the clause is a grab-bag
that also carries the exact "numeric seconds and legacy HMS" text a few lines later —
the citation was correct, I just under-read it).

## Estimated miss rate

| family | sampled | misses | rate |
|---|---|---|---|
| backlog.md (5 slices) | 125 | 4 solid + 1 weak | ≈3.2% (solid) |
| state docs (12 files) | 25 | 1 (low-priority) | 4% |
| handoffs + memory | 25 | 0 | 0% |
| mocks (15 of 75) | 15 | 0 | 0% |
| commits | 40 checked for citation | 2 wrong citations found (not the same as a coverage miss) | unverified, see above |

## Verdict on the ledger

Trust the backlog, state, handoffs, and mocks passes — miss rates are at or under 5%,
and every miss found is a small, low-blast-radius item (a device-eyeball tag, not a
data-loss bug or an undecided spec question). No full re-read needed for those four
families; the 5 items found above are cheap to fold in directly (see the exact
line/verdict text above — each is ready to paste into the right slice file as OPEN).

The commit-ledger family is the one place I'd flag for more than a spot-fix. Not
because I found a high true miss rate — I couldn't establish one, which is the
problem. The dual-ledger structure (8 rev-list slices vs. the separate grep-based
`sources-commits.md`) plus heavy overlap with `backlog.md` content makes "is this
commit covered" ambiguous by construction, and it's the only family where I found
actual wrong citations (2, both hash-level, both with conclusions that still happen
to be correct). I would not re-read all 1776 commits again, but I would: (a) decide
whether `sources-commits.md` is kept as a second source or retired now that the 8
slices exist, since carrying both invites exactly this kind of citation drift, and
(b) spot-check commit-hash citations specifically (not just SPEC-clause citations)
across the existing 8 slices before treating them as fully trustworthy — the sample
size here (11 hashes) is too small to bound the true error rate.
