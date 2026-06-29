# `roadmap/` — Skrift's interactive visual roadmap

This folder is **one self-contained thing**: a visual, commentable roadmap of Skrift's plan,
deployed as a claude.ai Artifact. New chat? Read this first, then `ROADMAP.html`'s top-of-file
comment (the update contract).

## Files
- **`ROADMAP.html`** — the whole app. A single dependency-free HTML file (vanilla JS + inline SVG,
  no framework, no build step — it must be self-contained because the claude.ai Artifact sandbox
  blocks external scripts/CDNs). It renders a **"metro-tree"**: one line left→right that runs green
  while done, **branches** off for detours and merges back, then fans into the planned tracks; far
  left is the native-rewrite history converging in. **Click any card to react** (👍/👎/🤔 + a note);
  big phases list their individual ideas. Pan/zoom; hover a card to reveal just its dependency lines.
- **`roadmap-comments.json`** — the durable, committed copy of reactions/notes (mirror of the file's
  `BAKED_COMMENTS`). See "Comments round-trip".
- **`visual-check.mjs`** — headless render check (Playwright/Chromium). Asserts the file loads with no
  JS errors, that all 5 history era nodes render + are positioned, and that opening a history card shows
  its shipped log. Run `node roadmap/visual-check.mjs` (also drops two screenshots beside the file). Use
  this instead of `chrome --headless` (Chrome was removed from the dev Mac).
- **`HISTORY_BACKFILL.md`** — staged research for a *future* "deep history" lane (NOT built yet).
- **`mocks/`** — the A/B/C/D design-exploration mockups (tech-tree / metro / board / the chosen
  hybrid `D`). Kept for design rationale.

## It's a GENERATED VIEW — don't hand-place anything
The picture is computed from four data arrays at the top of `ROADMAP.html`:
`PHASES` / `DETOURS` / `HISTORY` / `IDEAS`. Each node has a **`track`** (vertical lane) and **`order`**
(horizontal index); layout, lines, branches, merges and overlap-avoidance all auto-compute. **To move
a node, change those two numbers** — never drag/hand-position. Source of truth for the *content* stays
the markdown ledgers (`../STANDALONE_PLAN.md` "## Phases", `../backlog.md`); this is just a view of them.

## Update contract (so it can't drift)
When a phase/detour/idea changes, in the **same pass**: edit the arrays here **and** the markdown
ledger, bump `LAST_UPDATED`, then redeploy. Full checklist is in `ROADMAP.html`'s header comment.

## View / verify
- **Live (hosted):** the claude.ai Artifact — `https://claude.ai/code/artifact/64e6c806-d042-4d60-aa64-351142d61cbb`.
  To redeploy to the SAME url from a new chat, pass that URL to the Artifact tool's `url` param.
- **Locally:** open `roadmap/ROADMAP.html` in a browser, or render via the preview server
  (`.claude/launch.json` → `roadmap-static`, then `http://localhost:8765/roadmap/ROADMAP.html`) and
  screenshot. (Chrome was removed from this machine — use the preview server, not `chrome --headless`.)
- **Automated:** `node roadmap/visual-check.mjs` (Playwright/Chromium) — asserts no JS errors, all 5
  history era nodes render, and a history card's shipped log opens; writes two screenshots beside the file.
- `git log --follow roadmap/ROADMAP.html` = its history (the `--follow` picks up the pre-2026-06-21
  root-level path).

## Comments round-trip (no backend — CSP)
Reactions auto-save to the browser instantly. The Artifact can't call back to the repo, so to make a
comment durable/shared: in the app click **Export** → hand the JSON to the agent → it's written to
`roadmap-comments.json` **and** pasted into `BAKED_COMMENTS` (kept mirrored) and committed. On next
load `BAKED_COMMENTS` are the defaults (local edits win per-node).

## Planned
Extract a **standalone template** (generic engine + a per-project data file) so any project can drop in
its own arrays and get the same viz. Until then this is Skrift-specific in its *data* only.
