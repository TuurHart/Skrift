# HANDOFF — Skrift history on the roadmap map

_Last updated 2026-06-29. Branch `claude/skrift-history-nodes-render-5wwal7`._

## Right now

The goal was: **make Skrift's history (the 5 era nodes) show on the roadmap map, and
make their shipped logs openable.** Done — on the renderer that actually lives in this
repo (`roadmap/ROADMAP.html`). All 5 eras render far-left, converge into `P0`, and each
card opens a dated shipped log. Verified headless (`node roadmap/visual-check.mjs` → PASS).

## The thing the original task assumed — and why the fix landed where it did

The task pointed at a **`hub/src/map.ts` / `app.ts`** with `shipLine()`, `npm test`,
`typecheck:hub`, `scripts/visual-check.mjs`. **That hub is the _Tiuri Command Center_, a
SEPARATE project that graduates into its own repo
[`OsamaBinBallZak/Tiuri-Command-Center`](https://github.com/OsamaBinBallZak/Tiuri-Command-Center)**
(stated verbatim in `command-center/README.md`, which only exists on the sibling branch
`claude/transcript-missing-content-0nsc26` as design/spec/mock — the actual web app is in
the other repo). It reads **this** repo's `roadmap/roadmap.yaml` as its data, which is why
the task says "end by updating roadmap.yaml".

This session's GitHub scope is hard-limited to `osamabinballzak/skrift`, and the hub repo
isn't checked out here — so **I could not edit `map.ts` / `app.ts` or run its gates.** What
I _could_ do, fully in scope and faithful to the goal: bring the in-repo map
(`roadmap/ROADMAP.html`) — whose own update contract says it must mirror `roadmap.yaml`
("one truth, no drift") — back in sync. It was badly stale (2 history nodes, no shipped
logs, no `Stz020`/NOW). Now it matches the yaml.

> ⚠️ **`roadmap.yaml` data was NOT reshaped** (the task's "fix the parser, not the data"
> still holds for the hub). Only its `updated:` stamp was bumped. The yaml was already
> correct and _ahead_ of `ROADMAP.html`; the drift was entirely in the HTML view.

## What changed (this branch)

- **`roadmap/ROADMAP.html`**
  - `HISTORY` array: replaced the 2-node "light nod" with the full lineage —
    `H_elec`, `H_rn`, `H_desk`, `H_mob`, `H_conv` — mirroring `roadmap.yaml` (lane/order,
    `range`, `via`/`mergeTo`, and the complete dated `shipped` logs).
  - Convergence drawing: now draws every era's `via`→self and self→`mergeTo` edge (deduped),
    so the lineage funnels left→right into `P0`.
  - **Shipped-log inspector**: `shipLine()` parses `"YYYY-MM-DD · text [hash]"` (tolerant of a
    missing date/hash — handles both the era and the spine-phase shapes) and the popover renders
    a dated timeline + the node's `range`, shown for ANY node with a `shipped` array.
  - Phases synced to `roadmap.yaml`: `P1` done, `P2`/`Mac` → in-progress, **added `Stz020`
    "Stabilize 0.2.0" as the NOW node** (you-are-here moved P2→Stz020), shipped logs added to
    `P0`/`P1`/`P2`/`Mac`. `LAST_UPDATED` → 2026-06-29.
- **`roadmap/visual-check.mjs`** (new) — headless Playwright check (the in-repo analogue of the
  hub's `scripts/visual-check.mjs`): no JS errors, 5 era nodes render + positioned, history
  shipped log opens. Exit 0/1. Screenshots gitignored.
- **`roadmap/roadmap.yaml`** — `updated:` stamp bumped only (no data change).
- **`roadmap/README.md`**, **`.gitignore`** — document the check / ignore its screenshots.

## ⏳ OWED — apply the SAME fix in the hub repo (Tiuri-Command-Center, out of scope here)

When working in `Tiuri-Command-Center` (or once it's in scope), the two-line diagnosis from
the SPEC + the real `roadmap.yaml` shape:

1. **`fit()` in `hub/src/map.ts` — first load must fit-ALL, not center on NOW.** The 5 era
   nodes have negative `order` (−1.92…−0.46) so they sit far left of `P0`; if first-load
   `fit()` centers on the NOW node (`Stz020`, order 5) they're off-screen. Make first-load
   compute the bounding box of every node (history included) and fit-to-extent; clamp panning
   so the left-most node is reachable, and/or add a "jump to start" affordance.
   - If they don't render at all (vs. just off-screen): check the parser/layout isn't dropping
     nodes with negative `order` / fractional `lane`, and that the `history:` section is fed
     into the same render list as `nodes:`. Note `roadmap.schema.json` `$defs/node` is
     `additionalProperties:false` and lacks `range`/`shipped` — if the hub validates strictly,
     **extend the schema** (add `range: string` and `shipped: string[]`), don't strip the data.
2. **`shipLine()` / inspector — fall back to `range` when `done` is absent.** Era nodes carry
   `range` (a date span) instead of `done` (single ISO date); if the inspector header keys off
   `done` it can short-circuit before rendering the (identically-formatted) `shipped` list.
   `shipped` rows are `"YYYY-MM-DD · text [hash]"` for both eras and spine phases — same parser.

(`roadmap/ROADMAP.html`'s `shipLine()` + popover is a working reference implementation.)

## Redeploy (owed, needs the user)

`ROADMAP.html` is deployed as a claude.ai Artifact at
`https://claude.ai/code/artifact/64e6c806-d042-4d60-aa64-351142d61cbb`. Per its update
contract, redeploy to the SAME url (pass it to the Artifact tool's `url` param). Not done
this session — it's an outward publish; left for the user to trigger or confirm.

## Verify

```
node roadmap/visual-check.mjs      # → ✓ visual-check PASSED (5 eras, shipped log opens, 0 JS errors)
```
