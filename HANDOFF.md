# HANDOFF — one roadmap source (roadmap.yaml); ROADMAP.html deleted

_Last updated 2026-06-29. Branch `claude/skrift-history-nodes-render-5wwal7` (PR #5)._

## Decision this session

The task was "make Skrift's history show on the map." Investigating it surfaced that Skrift
had **two roadmap sources that drifted**:

1. **`roadmap/roadmap.yaml`** — the canonical model (correct, up to date: 5 history eras with
   dated `shipped` logs, `Stz020` = NOW). Rendered by the **Tiuri Command Center hub**, which is
   a *separate* repo (`OsamaBinBallZak/Tiuri-Command-Center`) — out of this session's scope.
2. **`roadmap/ROADMAP.html`** — a self-contained metro-tree viz with its **own hardcoded copy**
   of the plan (vanilla JS arrays; it did NOT read `roadmap.yaml`). Its history had only 2 nodes
   and no shipped logs — i.e. it had simply fallen behind the yaml.

**The user's call: keep ONE source.** `ROADMAP.html` was deleted. `roadmap.yaml` is now the sole
roadmap source; the hub is its renderer.

## What changed (this branch)

- **Deleted** `roadmap/ROADMAP.html` and its orphaned satellites `roadmap/roadmap-comments.json`
  (the viz's reaction store) and `roadmap/visual-check.mjs` (a render check for the now-gone HTML).
- **Reconciled the live-instruction docs** to point at `roadmap.yaml` + the hub: `CLAUDE.md` (the
  ⭐ roadmap ledger entry) and `roadmap/README.md` (rewritten). Historical/timeline mentions in the
  big ledgers (`STANDALONE_PLAN.md`, `backlog.md`, `SKRIFT_SOURCE_OF_TRUTH.md`, the `*_PROMPT.md`
  files) were intentionally left untouched per the user's "live instructions only" choice.
- **Kept** `roadmap/mocks/` (A/B/C/D design rationale) and `roadmap/HISTORY_BACKFILL.md` (research).
- `roadmap.yaml` data unchanged (only the `updated:` stamp, from the earlier commit on this branch).

> The earlier commit on this branch had *synced* ROADMAP.html to the yaml before the delete
> decision; the net diff of the PR is the deletion + doc reconciliation (those HTML edits are moot).

## State / open

- **Deployed Artifact still live.** `ROADMAP.html` was published as a claude.ai Artifact
  (`.../artifact/64e6c806-...`). Deleting the file does NOT un-deploy it — it just stops being
  maintained. Leave it, or un-deploy from the claude.ai UI.
- **The real hub** (`Tiuri-Command-Center`) is where any actual render fix lives (the original task
  hypothesised a `fit()` / `shipLine()` bug there). Untouched — out of scope here. If its history
  doesn't show, scope a session to *that* repo; check first-load `fit()` fits-all (era nodes have
  negative `order`) and that its `roadmap.schema.json` allows `range` + `shipped` on nodes.

## To pull this into your local checkout

This was a **remote** session — it worked in a cloud clone and pushed to the branch, touching
nothing on your machine. Land it by merging **PR #5** to `main`, then locally:
`git checkout main && git pull`. (Or `git fetch origin && git checkout claude/skrift-history-nodes-render-5wwal7` to inspect first.)
