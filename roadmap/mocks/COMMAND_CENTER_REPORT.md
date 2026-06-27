# Skrift Command — build report

*Written while you were in the air. Everything below is committed to the branch
`claude/transcript-missing-content-0nsc26`; the live mock is one Artifact URL that
I redeployed at each version.*

**Live mock:** https://claude.ai/code/artifact/3363b4ed-aa73-451e-ab7c-c09065bb27c3
**Branch:** `claude/transcript-missing-content-0nsc26` (also holds the chunk-seam fix + macOS CI)

---

## 0. TL;DR

You asked me to polish the hub, use lots of agents, think through workflows,
"pretend to use the app and find weird bits we didn't consider," make my own
calls, and write this up. I ran **four multi-agent workflows (~58 agents,
~2.5M tokens)** and drove the mock from v2 → **v3 "The Tape"** → **v4 (hardened)**
with a design-direction exploration, a 30-agent adversarial review, and a
verification pass in between.

The headline outcome: **"The Tape" is the right direction** — chat is the
instrument, the roadmap rides along as a single OP-1 tape with NOW at the
playhead. All three design judges and the usability audit independently
converged on it. The audit's job was to find what we *hadn't* considered, and it
found a lot — most of it is **missing states** (first-run, empty, capture-inbox,
build/CI, failure) and **honesty fixes** (account identity, freshness, bounded
memory cost), not architecture changes. The architecture (chat → strict tool
calls → `roadmap.yaml` → pure-render canvas; GitHub = truth, Supabase = non-git
state) survived scrutiny from a skeptical engineer and product lead.

---

## 1. What I did (method)

Three workflows, each fanning out agents and adversarially checking their own
output before synthesizing:

| Workflow | Agents | What it produced |
|---|---|---|
| **Design directions** | 9 | 5 divergent interaction directions → 3-judge panel → a decisive v3 brief |
| **Usability audit** | 16 | repo grounding + 10 persona walkthroughs + 3 adversarial critiques → prioritized v3/v4 decisions, missing screens, open questions |
| **v3 review** | 30 | 6 review lenses on the *built* v3 + adversarial triage → 22 confirmed-high bugs + a v4 changelist + a "keep as-is" list |
| **v4 verify** | 3 | must-fix audit + regression hunt + a11y/CSP on the rewrite |

I built and committed at each stage so the git history is the audit trail
(`git log roadmap/mocks/`).

---

## 2. The design decision — "The Tape"

I generated five genuinely different directions and scored them on a judge panel
(daily-use, TE-design, engineer). **All three judges picked the same winner.**

**The Tape:** chat is the full-bleed main surface; the roadmap is a 56px-tall
dark "tape" pinned just above the input. NOW is parked at a center playhead;
shipped work spools left under a `←N shipped` cap (used tape); planned work feeds
in from the right with a fade. The full multi-lane metro-tree is one tap away in
a summonable tray.

**Why it won:** it's the most faithful read of your locked decisions (chat IS the
surface; the canvas is a *pure* render), it degrades to a phone with zero layout
fork, and — the engineer's decisive point — its one expensive part (the live
animation) is **optional polish over a correct static redraw**. If the animation
is cut or `prefers-reduced-motion` fires, the tape is still right. The magic is
pure upside, never a liability.

**Grafted in from the runner-up directions:**
- **Shared cursor** — the node under the playhead *is* the chat's scope. Tapping a
  node centers it AND scopes the conversation. (This collapsed our open "detail
  card vs. chat?" question: neither — the node centers and the chat *is* its detail.)
- **Slash palette** whose verbs *are* the `roadmap.yaml` tool schema (`/now`,
  `/defer`, `/reconcile`…), generated from the schema so it can't drift.
- **Tracked-changes** confirm for destructive/bulk edits, with a 40%-opacity ghost
  preview on the tape.
- **Version stamp → plan history** (read-only list of yaml commits = free undo).
- **Zero-decision capture** wired to Skrift's existing iOS capture plumbing.

**The signature moment to nail:** the *peripheral-vision delta* — you hold the
orange circle, dump a scrambled voice ramble, and as Claude streams its tool calls
the receipt chips land in chat AND the tape animates the same change in your
peripheral vision (the node you made NOW slides to center and lights orange; a
deferred node fades to dashed and drifts right) — one ~270ms motion you never had
to look away from the conversation to see.

---

## 3. The usability audit — what we hadn't considered

16 agents "used" the hub across 10 scenarios and adversarially critiqued it. The
big finding: **the mock only ever rendered the happy steady state.** The entire
real surface area around it is unbuilt. Organized by theme:

### 3a. The painful-today loop is *capture*, not planning
The product critique landed hard and I agree: the daily, phone-shaped, genuinely
painful action is **capturing a stray idea and not losing it** — not in-hub build
orchestration (that's the procrastination surface). Implications:
- **Capture must be the hero, built properly:** big eyes-off target (not a 28px
  dot), push-and-hold (no silent record-while-walking), **local-first** save with
  an **offline queue**, an **Inbox** default destination, and a **post-capture
  confirm** chip (gist + editable destination + low-confidence ⚠ + undo).
- The current mock hides the destination on mobile and silently routes everything
  to "Skrift · backlog" regardless of project — both bugs.
- **Two record buttons** (chat "hold to talk" → planning turn vs. transport
  "capture" → inbox) currently share one handler and one clock/LED. They must be
  physically distinct and never both armed.

### 3b. Missing states (the mock is all happy-path)
First-run auth (Supabase sign-in → Connect GitHub OAuth → Anthropic key with an
**org-identity readback**); add-project modal; **repo-scan/import** (Skrift's real
roadmap lives in `ROADMAP.html` as JS arrays, *not* `roadmap.yaml` — a naive
connect shows an empty tape, so we need a one-click previewable import); empty-tape
state; connect-failure states (private repo / no write access / work-org key);
capture confirm + Inbox triage; ASR-failure/low-confidence; the **transcript→intent
review** (3 min of rambling shown as one clean paragraph hides the hard middle);
**build/CI read-only surface** (job card + CI states + run link); plan-history;
privacy "where your data goes" panel; resurrect/welcome-back for parked projects;
archive (reversible) vs. gated delete.

### 3c. Honesty fixes (things sold as pure wins that aren't)
- **"Whole-project memory" is the spend-creep engine** if it's a literal unbounded
  prompt. Make it bounded: cached stable prefix (`roadmap.yaml` + backlog snapshot,
  `cache_control` so re-sends are ~10%) + a rolling summary + last-N turns +
  focus-scoped retrieval. Optionally surface a `context: 14k tok` line.
- **Account identity must be first-class chrome** — a `personal · tiuri@…` chip that
  warns (orange) if the configured key resolves to a **work org**. This is the one
  privacy fix that's cheap and matters (your instinct from the Supabase isolation).
- **"live view" must be honest** — a freshness stamp (`roadmap.yaml @ abc123 · 2m
  ago`) and a stale badge once the off-device build session can write the file.

### 3d. Architecture held up (with sharpening)
The skeptical engineer endorsed the model/view split and sharpened it:
- **GitHub is the single source of truth** for all node data; **Supabase holds only
  non-git state** (auth, audio blobs, capture inbox, build-job rows, per-node
  reactions keyed by stable id). Node title/status/track/order **never** live in
  Supabase. This one boundary kills the entire sync/merge bug class.
- **Tool calls are field-level patches** committed with the file's **expected
  blob SHA** (409 → re-read → re-apply), never full-file YAML rewrites — because two
  writers (the planning chat *and* the off-device build session) both edit
  `roadmap.yaml`. Single commit per batch = free `git revert` undo.
- **`set_status → now` atomically demotes the prior active node** in the tool layer
  — fixes "two live nodes" confusion at the model level, not in the legend.
- **`id` is immutable** across all ops (it keys reactions/comments).

---

## 4. Data model (locked, grounded in the real roadmap)

`roadmap.yaml` mirrors `ROADMAP.html`'s node shape **exactly** so import is 1:1.
Per-node: `id` (stable), `ms` (milestone), `track` (lane: 0=Core, -1=Diff,
1/2=Enrich, ~1.35 detour, ±0.55 history), `order` (column), `status`
(done|inprogress|next|future|deferred), `title`, `eff`, `done`, `deps[]`
(hover-only risers), `via` (backbone flow source), `risk`, `note`. Layout
auto-computes from `track`+`order` — Claude sets meaning, never pixels. Full
schema + the strict tool set is in `command-center-spec.md`.

Real scale (reassuring): Skrift's roadmap is ~18 positioned nodes across ~4 lanes
+ 1 detour + a history lane, plus 33 ideas that live only in popovers. It's a
curated single spine with two short fan-outs and one closed detour — **not** a
dense graph. The 80-node stress scenario is hypothetical headroom, not today.

---

## 5. Evolution v1 → v4

- **v1** — tabbed hub (Projects / Project / Replan); channels wall; project view
  with metro-tree + talk-to-Claude + build handoff; replan tab.
- **v2** — chat-centric pivot: multi-lane metro-tree canvas *beside* a main chat;
  node-click focuses the chat; replan folded into chat as tool-call edits.
- **v3 "The Tape"** — chat full-bleed; roadmap as the OP-1 tape (NOW at playhead);
  shared cursor; slash palette; tracked-changes; version/history; summonable
  full-map tray; the tape is a **real data-driven render** (mutating the `nodes[]`
  model re-renders/animates it — the model/view split demonstrated, not faked).
- **v4** — *(completed after the review workflow; see §6)* visual-identity
  discipline pass + the highest-value missing states.

---

## 6. v4 — what the review changed

The v3 review (30 agents) was the most valuable pass: it caught **real code-level
bugs I'd introduced**, not taste calls. The standout: a hardcoded `-90` "gutter
fudge" in the centring math meant **NOW never actually sat on the playhead** — it
parked ~90px left — quietly breaking the single load-bearing illusion of the whole
design. v4 fixes that and 21 other confirmed-high findings, while a **"keep as-is"
list** stopped me over-correcting (the single-NOW playhead, the model/view split,
B/W+orange, the cost-split label, and the CSP cleanliness were all validated as
*correct* and left alone).

**Correctness (the bugs):**
- **NOW truly centres on the playhead** — deleted the `-90`; one `centreOn(fi)`
  helper owns it; the lane/shipped/freshness chrome moved to a caption row *above*
  the tape so nothing overlaps the track.
- **`cursor` is the single source of truth** — `renderTape` is the sole owner of the
  transform + focus chip; tapping a node now *visibly re-scopes the chat* (per-node
  stubs), and clearing returns to whole-project view. (v3's shared cursor was inert.)
- **Shipped nodes keep their real order** and spool under a fade-mask instead of
  sliding behind the chrome; after a ship with no NOW, the next planned node
  auto-promotes.
- **Ghost preview is delta-driven** — confirm/discard actually mutate `nodes[]`, and
  the reconcile defers nodes that are really on the tape so something visibly moves.
- **Lane-aware playhead** — dims to grey when a lane has no active node (it used to
  imply NOW in 2 of 3 lanes); the `◆` NOW-tick doubles as a "home" button.

**One orange record:** the transport bar's capture is the only orange control
(real hold-to-talk via pointer events); the field gets a quiet mono outline
*dictate* mic. The "which orange dot?" ambiguity is gone.

**Identity discipline:** orange rationed to LIVE-only (tool-chips demoted to
mono-on-paper with a grey ✓ — they're a log, not an alarm); the SaaS pills killed
for a 2-value radius system; **machine speaks mono, you speak sans** (Claude's
prose is mono, your dictated turns are the one humanist element); a structural grid
replaced the decorative dot wallpaper; an **account-identity chip** that flips to an
orange work-org warning; a **freshness stamp** (`roadmap.yaml @ sha · 2m ago`).

**Accessibility:** real `<textarea>` + `<button>` tape nodes with roving tabindex,
arrow-key navigation and aria-current; Escape + focus-return on the overlays;
visible focus rings.

**New states built (the mock was all happy-path):** empty/first-run, a build→CI
**job card** (requested → landed → CI running → ship-at-desk), a capture-confirm
chip routed to the cursor or Inbox, and a **real project-model swap** in the
switcher. The full-map **tray now renders from the same `nodes[]` model** as the
tape (v3 had two disagreeing data models).

A 3-agent **verification pass** then audited the rewrite. Verdict: **sound to ship
as a mock** — it confirmed 5 of 6 must-fixes landed correctly (NOW genuinely
centres, one orange record, delta-driven ghost that mutates, shipped spool, CSP
clean). It caught follow-on bugs, which I then **patched**: the shared cursor only
re-scoped the chat for 3 stubbed nodes (so tapping Export/CloudKit fell back to the
whole-project view) → now *every* focused node re-scopes via a synthesised turn;
lane-cycle dropped the cursor without re-rendering the chat; swapping to the empty
project leaked Skrift's chat; the dictate toggle stuck the placeholder on
"listening…"; the modal had no focus trap (added trap + background `inert`); tape
nodes were `role="listitem"` buttons (fixed); capture was pointer-only (added
keyboard); and initial centring could read a 0-width container (added `load`/rAF
re-centre). All committed; the live URL is the patched build.

**Deliberately deferred** (documented, not built — they'd bloat the mock and the
audit says v1 should be lean): the full 3-step auth flow, the add-project modal, the
standalone privacy/data panel, a node-search minimap, and momentum scrubbing. The
spec + audit already specify these; they're build-time work, not design-unknowns.

---

## 7. Open questions for you (the real forks)

The audit surfaced six decisions that are genuinely yours, not mine:

1. **Scope of v1:** lean (capture→inbox→backlog is the only *daily* loop; planning
   stays in Claude Code; build/CI read-only) **or** full chat-instrument-plus-tape
   from the start? *My rec: lean-then-grow — but it's the biggest fork.*
2. **Cost-split UI:** keep it as an honest *label* only (my rec — cut billing
   meters, keep the one org-identity guard) or actually surface per-turn spend?
3. **Capture transcription:** on-device via Skrift's Parakeet (zero new
   billing/privacy surface, but implies capture routes through the native app's
   intent, not the web page) — acceptable? Or do we need a cloud STT for the web hub?
4. **Project lifecycle source of truth:** add a `projects.yaml` manifest in GitHub
   (ledger-backed, can't drift) with Supabase as a cache, or keep lifecycle in
   Supabase as the one piece of non-git state?
5. **`ROADMAP.html`'s fate:** after import, does it become a generated view *of*
   `roadmap.yaml`, or do we retire it and make the tape/tray canonical? (Two
   hand-maintained copies is the thing to avoid.)
6. **First dogfood target:** Skrift (exercises the full 18-node import + detours)
   or the simpler Study app (cleaner first light)?

---

## 8. Recommended next steps

1. **Answer the six forks above** (especially #1 scope).
2. **Build the spine first:** `roadmap.yaml` schema + the strict tool layer
   (field-level patches, expected-SHA commits, immutable id, one-NOW enforcement).
   Everything writes through it.
3. **`ROADMAP.html → roadmap.yaml` importer** so Skrift has real data + history.
4. **Ship the capture hero loop** (the only thing that must be frictionless day one).
5. Then first-run/empty/failure states, then the live tape, then bounded memory,
   then the visual-identity pass, then read-only build/CI.
6. **Graduate to its own repo** (per your note) once the spine + capture exist.

---

*Artifacts in `roadmap/mocks/`: `command-center.html` (live mock),
`command-center-spec.md` (data model + tool schema), this report. Workflow
scripts are under the session's `workflows/` dir.*
