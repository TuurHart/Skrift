# Skrift Command — architecture & data model (working spec)

> Draft written 2026-06-27 alongside the v2/v3 mock. This is the **model** half of
> the model/view split: the structured data Claude edits and the canvas renders.
> Source-grounded in the real `roadmap/ROADMAP.html` node shape.

## 0. One-paragraph thesis

A personal, single-user web hub to run all your side projects. **Chat is the
surface**; each project has one persistent-memory planning chat. You talk, Claude
edits a per-project **`roadmap.yaml`** via strict-schema tool calls, and a calm
Teenage-Engineering canvas re-renders from that file. Cheap **planning runs on the
Claude API**; token-heavy **building runs in Claude Code under the Max
subscription**; **GitHub Actions CI** verifies; it ships to the iOS app at the
desk. GitHub is the source of truth (yaml/markdown ledgers + Actions); a separate
isolated Supabase project holds auth + voice audio + mutable hub state.

## 1. The model/view split (the whole point)

```
   you (voice/text)
        │
        ▼
   planning chat ──(strict tool calls)──▶  roadmap.yaml   ──(pure render)──▶  canvas
   [Claude API]        add_node / set_status            [git + supabase]        [TE metro-tree]
                       move_node / defer / …
```

- Claude **never** touches pixels or the canvas code. It edits **data**.
- The canvas is a **pure function** of `roadmap.yaml` (+ live status from CI/build).
- Tool calls are **strict-schema** (`strict: true`) so Claude *cannot* emit a
  malformed edit — no parse fragility.
- Layout is **auto-computed** from each node's `track` (lane) + `order` (column).
  Claude sets semantic position; a layout function assigns x/y. Claude does no
  coordinate math — it can even position relationally ("after Export, before Mac")
  and the layout resolves `order`.

## 2. `roadmap.yaml` — the per-project node graph

One file per project (in that project's repo, mirrored to Supabase for the live
hub). Field set lifted from the real `ROADMAP.html` `PHASES`/`DETOURS` arrays so
the existing roadmap imports 1:1.

```yaml
project: skrift
title: Skrift
status: active           # active | paused | parked | archived
repo: OsamaBinBallZak/Skrift
updated: 2026-06-27T08:10:00Z

# vertical lanes, top→bottom. track 0 is the spine ("CORE").
lanes:
  - { track: -1, label: "Differentiator" }
  - { track:  0, label: "Core" }
  - { track:  1, label: "Enrichment" }
  # detours render in a half-lane (e.g. track 1.35) between two lanes

nodes:
  - id: P2                       # stable slug, referenced by deps/via
    title: Export & Obsidian publish
    lane: 0                      # which track
    order: 2                     # column index within the lane
    status: now                  # done | now | inprogress | planned | deferred
    effort: L                    # S | M | L  (optional)
    deps: [P0]                   # ids this depends on
    via: P1                      # the node this visually flows from (edge source)
    done:                        # ISO date when status==done (else null)
    risk: false                  # draws the small risk pip
    note: "#1 gap — a phone-only note can only escape via copy-paste."
    detour: false                # true → render in the detour half-lane
    branchFrom:                  # (detours) id it branches off
    mergeTo:                     # (detours) id it merges back into

ideas:                           # unplaced captures awaiting triage into nodes
  - { id: i1, text: "per-book resume position", source: voice, ts: ... , nodeHint: P3 }

history: []                      # shipped/converged nodes kept for the "green tail"
```

**Status → render mapping (B/W + orange only):**

| status       | marker                                  |
|--------------|------------------------------------------|
| `done`       | filled black square                      |
| `now`        | orange dot + halo + `◆ NOW` label        |
| `inprogress` | orange ring (hollow centre)              |
| `planned`    | hollow grey circle                       |
| `deferred`   | dashed grey circle                       |
| `detour`     | small filled diamond on the half-lane    |
| `risk`       | tiny orange pip on the node              |

## 3. Planning-agent tool schema (what the chat can do)

Every tool is `strict: true`, `additionalProperties: false`. Each call mutates
`roadmap.yaml` and returns the changed node(s) so the canvas can animate the delta.
These are the chips the user sees as a receipt ("✓ set_status …").

| tool | inputs | effect |
|------|--------|--------|
| `add_node` | `{title, lane, after?, status?, deps?, note?}` | create a node; `after` resolves `order` relationally |
| `update_node` | `{id, title?, note?, effort?, risk?}` | edit fields |
| `set_status` | `{id, status}` | move through the lifecycle |
| `move_node` | `{id, lane?, after?}` | re-lane / re-order |
| `defer` | `{id, reason?}` | status→deferred (reversible) |
| `add_dep` / `remove_dep` | `{id, dep}` | edit edges |
| `make_detour` | `{id, branchFrom, mergeTo}` | move to the detour half-lane |
| `add_idea` | `{text, source, nodeHint?}` | drop an unplaced capture into `ideas` |
| `triage_idea` | `{ideaId, → add_node args}` | promote an idea to a node |
| `reconcile` | `{focus: [id], defer: [id], note}` | the "mixdown": batch re-plan into a v1 |

**Reads** the agent always has in context (cached): the full `roadmap.yaml`, the
project's `backlog.md`, and a rolling summary of prior planning chats =
"whole-project memory".

**Confirmation policy (from the audit's wrong-edit scenario):** non-destructive
edits (`add_*`, `set_status`, `move_*`) apply optimistically and show an inline
**undo**; destructive/bulk edits (`reconcile`, deleting a node, `defer` of an
`inprogress` node) render a **diff to confirm** before writing. Every write is a
versioned commit to the yaml so the canvas has full history → trivial revert.

## 4. Cost / auth / sync model

- **Planning = Claude API** (personal API key, ~$/mo, prompt-cached whole-project
  context). **Building = Claude Code under Max** (flat-rate, token-heavy). The UI
  labels both so spend is never a surprise.
- **Privacy:** personal content must not silently flow through a work Anthropic org
  — use a dedicated key; voice audio lives in the **isolated** Supabase project,
  never the work DB. (Mirrors the user's Supabase-isolation rule.)
- **Source of truth = GitHub** (`roadmap.yaml` + markdown ledgers); **Supabase**
  holds auth + audio + the live mutable mirror. Last-write-wins across devices on
  the yaml, with the commit history as the safety net.

## 5. Open decisions (resolve with the audit synthesis)

- Node detail on tap: expand a small detail card on the canvas, or keep the canvas
  pure and put all detail in the chat?
- Canvas/chat split ratio on desktop; canvas placement on mobile (top strip vs.
  swipe-to-reveal).
- Whether tool-call receipts are always shown, shown-then-collapsed, or silent.
- Search / jump-to-node at 80+ nodes.
- How "building done" reflects back into the hub (CI webhook → status flip).
