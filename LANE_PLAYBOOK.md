# LANE PLAYBOOK — how executor lanes run in this repo (lanes: read FIRST, follow exactly)

Economy model (Tuur, standing as of 2026-07-21; proven in the drone-lab and the 🧬 3-lane batch):
**Sonnet executes, Fable conducts + judges.** Executor lanes run on Sonnet with this playbook +
a short per-lane brief. This file is the standing contract — briefs stay short and never restate it.

## The contract
- Your brief names: the QUESTION/feature, your file-ownership set, pinned symbol names, the
  cross-lane seams. This file names everything else. Plan-file first: write
  `LANES-<date>/PLAN_<LANE>.md` from your brief, commit it, then execute.
- An honest blocker/refuted outcome is a SUCCESS. Forced passes and silent guesses are failures.

## Hard rules (violations poison the batch)
- FIRST ACTION: verify `LANES-<date>/BASE.md` exists in your worktree (it only exists at/after
  the intended base commit); report your base SHA in your final message. Missing → `git reset
  --hard main`, re-verify, then start. Never recreate it by hand.
- Isolation, not exclusion: every writer owns its own git worktree. You were spawned into one —
  never write outside it.
- The ownership map in BASE.md is law: writes outside your file set are FORBIDDEN. Always
  READ-ONLY for every lane: `Skrift_Native/Shared/**` (contracts — escalate if insufficient,
  never edit), `roadmap/`, `backlog.md`, `FEATURES.md`, `SKRIFT_SOURCE_OF_TRUTH.md`, the mocks,
  other lanes' files.
- EDIT-ONLY: do NOT run xcodebuild/simulators/devices (one machine; builds serialize at the
  conductor's merge gate). Swift correctness = your care + the conductor's compile gate.
  Hardware-flavored work (device installs, audio routes, BT, eyeballs) is NEVER lane work.
- New UI requires a signed-off mock (mock-first is locked process). No mock in your brief =
  that UI isn't yours to invent — escalate.
- Anything living on both apps (logic, labels, constants) is single-sourced in `Shared/`;
  lifecycle copy comes from `MemoSpine.oneLiner` — never hand-written.
- git: commit per completed step with EXPLICIT paths (never `add -A`/`add .`); end commit
  messages with the house Co-Authored-By line. Never `git checkout` another branch.
  index.lock → wait 5 s, retry once.
- FOREGROUND-ONLY: every command is a foreground Bash call that returns its exit + output in
  the same turn. Never `run_in_background`, never a trailing `&`, never a watcher/wait loop.
  A job too long for your turn → end the turn reporting `READY-WAITING: <lane>`; the conductor
  resumes you.

## Wrap block (every lane)
Final message: 5 lines — verdict · what shipped (commits + SHAs) · files changed ·
uncertain-decisions table (Decision / What I chose / Alternative / How to flip) · blocked items.

## ESCALATION (the Fable rule)
On ANY of: a contract that seems insufficient · a result contradicting the ledgers · a judgment
call that changes doctrine · evidence you're about to write something wrong — DO NOT GUESS.
Write `LANES-<date>/ESCALATE_<LANE>.md` (the question, the evidence, your best two options),
commit it, end your turn with `ESCALATE: <one line>`. Escalating early is cheap; a confident
wrong call costs a re-run of everything downstream.

## Conductor's checklist (Fable — running a batch)
1. Pre-ship shared contracts (`Shared/` spine + twin tests) BEFORE laning; lanes never edit Shared/.
2. `LANES-<date>/BASE.md` = base marker + ownership map (group lanes by file-locality so merges
   are conflict-free by construction) + cross-lane seams + pinned symbol names. One brief per
   lane; front-load every clarification — lanes get no mid-run questions.
3. One worktree per lane. The conductor never leaves loose uncommitted writes in a shared tree.
4. Merge gate: rebase the lane onto current HEAD, merge into a CLEAN tree, then the full builds —
   desktop UnitTests + `-skipMacroValidation` app build, mobile iPhone 17 sim suite — and
   vision-check any UI (render + look, never source-only).
5. Retro: append what broke + the ONE guard that prevents recurrence to LESSONS below —
   proposed to Tuur first (human-in-the-loop on rule changes; a bad rule compounds).

## LESSONS (append-only, Tuur-approved)
- 2026-06-09: a second chat sharing one working tree swept another session's uncommitted docs
  via a broad `git add` → the explicit-paths + worktree-per-writer rules above.
- 2026-07-21 (🧬 batch): `#Predicate` can't capture a model property — hoist to a local first ·
  ImageRenderer blanks ScrollView rows — snapshot via hostPNG and vision-check the PNG · a lane
  moving a file `Pipeline/`→`App/` broke the host-less test compile — target membership is part
  of the contract; escalate before moving files across target boundaries.
