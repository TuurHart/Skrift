# Tiuri Command Center

A **personal, single-user command center** for running many side projects from one
place — chat is the instrument, and each project's plan rides along as a calm
Teenage-Engineering "tape." You talk (voice-first), Claude edits the plan, and the
canvas re-renders from the data. Cheap **planning** runs on the Claude API;
token-heavy **building** runs in Claude Code under a Max subscription; **GitHub
Actions** verifies.

> **Status:** design phase complete. This folder is **extraction-ready** — it's a
> self-contained project staged inside the Skrift repo, graduating into its own repo
> [`Tiuri-Command-Center`](https://github.com/OsamaBinBallZak/Tiuri-Command-Center).
> See [Extracting to its own repo](#extracting-to-its-own-repo).
> It is **separate from Skrift** — Skrift is just one of the projects it manages.

## What's here

| File | What it is |
|---|---|
| [`mock/index.html`](mock/index.html) | The interactive **v4 mock** ("The Tape") — self-contained HTML, runs in any browser |
| [`SPEC.md`](SPEC.md) | The **data model + tool schema** — `roadmap.yaml`, the strict planning-tool set, the resolved design decisions |
| [`REPORT.md`](REPORT.md) | The **build report** — method (4 multi-agent workflows, ~58 agents), the design verdict, the usability audit, the v1→v4 evolution |
| [`tools/roadmap-tools.ts`](tools/roadmap-tools.ts) | **The spine (starter code)** — the strict tool defs for the Claude API + a pure `applyTool` reducer enforcing the invariants (immutable id, one-NOW, position-only moves, preview-then-commit reconcile) |
| [`schema/roadmap.schema.json`](schema/roadmap.schema.json) | JSON Schema for `roadmap.yaml` (the data contract) |
| [`schema/roadmap.example.yaml`](schema/roadmap.example.yaml) · [`schema/projects.example.yaml`](schema/projects.example.yaml) | Worked examples of a project's node graph and the lifecycle manifest |

Live mock (claude.ai Artifact): <https://claude.ai/code/artifact/3363b4ed-aa73-451e-ab7c-c09065bb27c3>

## The idea in one diagram

```
   you (voice/text)
        │
        ▼
   planning chat ──(strict tool calls)──▶  roadmap.yaml   ──(pure render)──▶  the tape
   [Claude API]      add_node / set_status            [GitHub = truth]        [TE metro-tape]
                     move_node / defer / reconcile     [Supabase = state]
        │
        └── "build" ──▶ Claude Code (Max subscription) ──▶ GitHub ──▶ CI ──▶ your device
```

- **Chat is the main surface.** One persistent-memory chat per project.
- The roadmap is a **single OP-1 "tape"** with NOW at a centre playhead; shipped
  spools left, planned feeds right; the full multi-lane map is one tap away.
- Claude **never touches pixels** — it edits `roadmap.yaml` via strict-schema tool
  calls; the canvas is a pure function of that data (auto-layout from lane + order).
- **GitHub is the single source of truth** (`roadmap.yaml` + `projects.yaml` +
  markdown ledgers). **Supabase** holds only non-git state (auth, voice audio,
  capture inbox, build-job rows, per-node reactions).

## Locked decisions (see SPEC §5 for the full list)

- **Full** chat-instrument scope (not a lean read-only v1).
- **Real spend meter** (computed from token usage) + an org-identity guard that warns
  on a work-org API key.
- **`projects.yaml` in GitHub** is the lifecycle source of truth; Supabase mirrors it.
- **`ROADMAP.html` becomes a generated view of `roadmap.yaml`** (one truth, no drift).
- **Import = structure + substance:** a project's ~high-level roadmap nodes are
  *milestones*, not todos — the real todos live in its `backlog.md`. The importer
  wires both, so a tape node expands into its constituent backlog items in the chat.

## Capture (the open one — iOS reality)

Voice capture is the daily hero, and it's the one genuinely-open piece. The honest
constraint: **iOS does not allow silent background mic** — no app can record from
cold/background without a foreground moment (the friction Shhhcribble hit).

The refinement that makes this fine: **most capture happens *in-app*, already
foregrounded** — you're looking at your plan, you have a thought, you tap record.
That's instant, on-device, no cold-launch. So a small standalone app (its *own*
build, optionally bundling the open-source FluidAudio/Parakeet package — **not**
coupled to Skrift) gives great in-app, on-device, private capture. The only residual
hard case is a *stray idea while the app is closed*; for that, don't fight iOS —
fire it into whatever's already frictionless (Voice Memos / a Shortcut) and let the
hub pull it in and triage later.

**Decision still open:** how much to invest in cold/external capture vs. letting the
phone be the plan/triage surface (keyboard dictation in chat is fine) with the Mac
doing heavy capture. Tracked in SPEC §5.

## Build order (when breaking ground)

1. **The spine** — `roadmap.yaml` schema + the strict tool layer (field-level patches,
   expected-SHA commits, immutable `id`, one-NOW enforcement). Everything writes through it.
2. **The importer** — `ROADMAP.html`/`backlog.md` → `roadmap.yaml` + linked todos.
3. **The hub** — web app (great on Mac/iPad immediately): tape + chat + tool calls.
4. **Capture** — in-app on-device (own FluidAudio) once it's a small app; web cloud-STT
   fallback meanwhile.
5. **Build/CI loop** — read-only first (job cards from GitHub Actions), then interactive.

## Stack (intended)

- **Frontend:** a self-contained web app (the mock is the design spec). Hosts on
  GitHub Pages / similar; reachable from phone + iPad + Mac.
- **State:** a **separate, isolated Supabase project** (auth, audio, inbox, jobs,
  reactions). Never the same DB as anything work-related.
- **Truth:** GitHub (`roadmap.yaml`, `projects.yaml`, markdown ledgers) + Actions for CI.
- **Planning model:** Claude API (`claude-opus-4-8`), prompt-cached project context,
  strict-schema tool calls. **Building:** Claude Code under Max.
- **Phone capture (later):** a thin native app bundling FluidAudio for on-device ASR.

## Extracting to its own repo

This folder is staged so it lifts out cleanly, with history:

The repo already exists: **<https://github.com/OsamaBinBallZak/Tiuri-Command-Center>**.

```sh
# from the Skrift repo root — split this folder into its own branch (keeps history)
git subtree split --prefix=command-center -b command-center-export

# push that branch as main into the existing repo
git push git@github.com:OsamaBinBallZak/Tiuri-Command-Center.git command-center-export:main
```

Or, simplest (no history): copy the folder and start fresh —
`cp -r command-center ../Tiuri-Command-Center && cd ../Tiuri-Command-Center && git init && git add -A && git commit -m "init: Tiuri Command Center"`.

---

*Designed 2026-06-27 via four multi-agent workflows. Full method + findings in
[`REPORT.md`](REPORT.md).*
