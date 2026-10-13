# `roadmap/` — Skrift's roadmap data

This folder holds **`roadmap.yaml`**, the single source of truth for Skrift's plan: the
node graph (phases, detours, the 5 history eras) that the **Tiuri Command Center hub**
renders. The hub is a *separate* project in its own repo
([`OsamaBinBallZak/Tiuri-Command-Center`](https://github.com/OsamaBinBallZak/Tiuri-Command-Center));
this repo only holds the data it reads.

> **History (2026-06-29):** there used to be a second renderer here, `ROADMAP.html` — a
> self-contained metro-tree viz with its *own hardcoded copy* of the plan. That made two
> sources that drifted (its history fell behind `roadmap.yaml`). It was deleted to keep
> **one source**. `git log` (e.g. `git show <commit>:roadmap/ROADMAP.html`) recovers it if
> ever needed. The old design-exploration mockups are still in `mocks/` for rationale.

## Files
- **`roadmap.yaml`** — THE source of truth. Schema: `project`/`title`/`lanes`/`nodes` (spine
  phases), `detours`, `history` (the era nodes, negative `order`, with dated `shipped` logs),
  `ideas`. Each node's layout is auto-computed from its `lane` (vertical) + `order` (horizontal)
  — to move a node, change those two numbers. Canonical detail + provenance live in
  `../SKRIFT_SOURCE_OF_TRUTH.md` §4 and the cited ledgers; this file is the model the hub renders.
- **`HISTORY_BACKFILL.md`** — staged research for a *future* "deep history" lane (pre-git-floor
  material; NOT built).
- **`mocks/`** — the A/B/C/D design-exploration mockups (tech-tree / metro / board / hybrid).
  Kept for design rationale; not live.

## Update contract
When a phase/detour/idea changes status, edit **`roadmap.yaml`** AND the markdown ledger it
mirrors (`../SKRIFT_SOURCE_OF_TRUTH.md` §4, `../STANDALONE_PLAN.md`, `../backlog.md`) in the
**same pass**, and bump `updated:`. The hub re-renders from the committed yaml — there's no
HTML to redeploy anymore.

## View
Open it in the Tiuri Command Center hub (its own repo). There is no standalone in-repo viewer;
`roadmap.yaml` is plain data — read it directly, or render it via the hub.
