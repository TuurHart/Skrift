# Resume prompt — rebuild the roadmap into an INTERACTIVE, COMMENTABLE visual dashboard (paste into a fresh chat)

Rebuild **`ROADMAP.html`** (repo root, `/Users/tiurihartog/Hackerman/Skrift`) from the current dense Civ-tech-tree
into a **visual-first, interactive planning dashboard** the user can think *in* — pan/zoom a clean tech tree, and
**click any node to drop a comment + reaction** ("👍 like / 👎 not this / 🤔 think about" + free text) so they can
decide what to build next. HTML-only; no Xcode, no device — fast edit→render→redeploy loop.

## START BY READING
1. `CLAUDE.md` — the **ROADMAP update contract** (PHASES/DETOURS arrays + markdown stay in sync; redeploy to the same Artifact URL).
2. `ROADMAP.html` — what exists today. The data is two arrays at the top (`PHASES`, `DETOURS`); the rest is vanilla JS/SVG that lays out columns + dependency edges + the detour branches. **Render it to see it:** `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --screenshot=/tmp/r.png --window-size=1600,1000 file://<abs path>` then Read the PNG.
3. `STANDALONE_PLAN.md` — the **`## Phases` section** is the full improvement list (Phases 0–11, incl. the Phase 5–11 "steal-list" differentiators). Source of the nodes; consider surfacing ALL of them so the user can comment on every option.
4. Memory `project_standalone_app_store` — cross-session record; the steal-list summary.

## LOCKED decisions (user, 2026-06-19)
- **Format = HTML** (the existing claude.ai Artifact). **Self-contained + dependency-FREE** — the Artifact CSP blocks
  external CDNs/scripts/fonts, so **inline everything** (vanilla JS + SVG, system fonts). Do NOT try to load React Flow /
  Cytoscape / D3 from a CDN — they won't load. (Hand-rolled SVG is what's there now and is the right call.)
- **Commentable nodes (the headline new feature).** Click a node → a popover to set a **reaction** (like / not-this /
  think-about — drive a colored dot or ring on the node) + a **free-text note**. A node with a comment shows a small
  badge. Persist in **`localStorage`** keyed by a STABLE node id (survives reloads + redeploys of the same URL).
- **Round-trip to the repo (so comments aren't trapped in one browser).** Add **"Export comments → JSON"** (copy/
  download) + **"Import"** (paste). The user hands the JSON back; the agent commits it (e.g. `roadmap-comments.json`) and
  the next regenerate **bakes the saved comments in as defaults**. Source-of-truth = repo, same as every other ledger.
  Suggested schema: `{ "<nodeId>": { "reaction": "like|dislike|think|null", "note": "…", "ts": <ms> } }`.
- **De-clutter (the main visual complaint — "cramped, too many arrows").** Keep the long horizontal Civ-tech-tree feel
  but: generous spacing + bigger nodes; **zoom + pan**; and **show a node's dependency edges only on hover/select**
  (dim the rest) instead of drawing all the spaghetti at once. (This hover-highlight-edges pattern is exactly how the
  Roadmap-Graph Obsidian plugin + Graphviz-SVG examples keep dense DAGs readable.)
- **Keep it GENERATED from data.** `PHASES`/`DETOURS` arrays remain the source; the markdown ledgers
  (`STANDALONE_PLAN.md` / `backlog.md`) stay canonical. The viz is a view. **Update contract still applies.**

## NICE-TO-HAVE (offer; user's call)
- Surface the full Phase 5–11 "steal-list" ideas as their own (future) nodes so the user can react to each.
- Filter/collapse by milestone; a "show only: next / in-progress / commented" toggle.
- A legend + a tiny "N commented / N liked" summary so the dashboard answers "what do I want next?" at a glance.

## PRIOR ART to steal from (gathered 2026-06-19)
- **Roadmap-Graph** (Obsidian DAG plugin) — hover a node → tooltip + highlight adjacent edges. The de-clutter model.
  https://github.com/DR-LLL/Roadmap-Graph
- **nikomatsakis/skill-tree** — GitHub Project → Graphviz/SVG skill tree. https://github.com/nikomatsakis/skill-tree
- **Skill Tree App** — pan/zoom canvas, node=skill, edge=dependency. https://www.skilltreeapp.com/
- **Graphviz SVG edge-highlight-on-hover** (CSS technique). https://gist.github.com/sverweij/93e324f67310f66a8f5da5c2abe94682
- **svg-toolbelt** — framework-agnostic SVG pan/zoom ideas (don't import; borrow the approach). https://www.cssscript.com/zoom-pan-svg-toolbelt/
- **Civ interactive tech trees** (CivFanatics; Civ:BE radial "Tech Web" as a non-linear option). https://forums.civfanatics.com/threads/new-interactive-tech-tree-web-page.167331/
- **Node-graph sticky notes** (n8n / Nuke) — the "comment lives on the canvas" pattern. https://docs.n8n.io/workflows/components/sticky-notes/

## HOW TO WORK
- Edit `ROADMAP.html` → render to PNG (Chrome headless, above) → Read it → iterate. (Reusable: don't trust HTML-only
  review; render + Read the PNG.)
- **Redeploy to the SAME Artifact URL** `https://claude.ai/code/artifact/64e6c806-d042-4d60-aa64-351142d61cbb` by
  passing it to the Artifact tool's `url` param (a fresh session otherwise mints a new URL). The URL is also recorded in
  the comment at the top of `ROADMAP.html`.
- Commit `ROADMAP.html` (+ `roadmap-comments.json` once it exists). `git log ROADMAP.html` = the history.
- No test gate — it's a static HTML view. Verify = render-and-eyeball.
- **Persistence caveat:** the Artifact can't call a backend (CSP). Comments live in `localStorage` + the export/commit
  loop. That's the durable, cross-device path; there is no live cloud sync from inside the Artifact.

## Current state (2026-06-19)
The app side is in great shape (audiobook reading-mode redesign + transcription work all shipped, `main` local/unpushed,
build 14). This task is a **standalone, low-risk HTML/visual task** — a palette-cleanser from the Swift work, on the same
roadmap whose data already exists. The app's actual next ship-blocker remains **Phase 2 — Export & Obsidian publish**
(unrelated to this viz; tracked in `STANDALONE_PLAN.md`).
