# ROADMAP_HISTORY_BACKFILL.md — staged material for the roadmap's "deep history" lane

**Status:** RESEARCH / NOT BUILT. Compiled 2026-06-21 from a read-only pass over the archives.
This is the raw material for a *future* session that extends `ROADMAP.html`'s backward-looking
history (the far-left "how it got made" zone). **Nothing is built yet** — see the open decision
at the bottom.

**Why staged, not built (user, 2026-06-21):** "don't know if that's smart to do before we [settle]
the way it works" — i.e. don't backfill the history while the roadmap's mechanics are still moving,
or you'll redo it. So: gather the material now, build the lane in a dedicated session once the viz
is locked.

**Privacy (hard rule):** the backfill mines **git history + the app's own code/docs only**. NEVER
read the user's Obsidian vault contents — not in the live repo, not in any archived snapshot (they
each carried a test vault / sample notes). Git log, READMEs, CLAUDE.md, code structure = fair game.

---

## Sources (in priority order)

1. **The live repo's own git log — the authoritative, complete narrative.**
   - **779 commits, 2025-10-18 → 2026-06-21**, all in one lineage. First commit:
     `Initial commit: Audio transcription pipeline app with React frontend and Python backend`.
   - This single `git log` already contains the ENTIRE arc (Electron/Python → native → standalone).
     Mine it for dated era boundaries: `git log --reverse --format='%ad %s' --date=short`.
2. **Live repo `archive/`** — old apps preserved **intact** (the convergence kept them):
   `CLAUDE-electron-python.md` (the pre-convergence project doc), `Mobile/` (React-Native iOS),
   `backend/` (Python), `frontend-new/` (Electron), `legacy-root/`.
3. **Three external milestone snapshots** in `/Users/tiurihartog/Hackerman/archive/` — the USER's
   hand-labeled checkpoints. Not needed for commit history (the live log has it), but they capture
   what `git log` doesn't: **human milestone names, the collaborator era ("Hendri"), and preserved
   era artifacts** (e.g. the original `frontend/` React app + the transitional whisper+parakeet
   backend, both later replaced).
4. **Ledgers + memory:** `STANDALONE_PLAN.md`, `backlog.md`, the `project_*` memory files,
   `MOBILE_NATIVE_HANDOFF.md`, `DESKTOP_NATIVE_HANDOFF.md`.

### The three external snapshots (verified 2026-06-21)

| Folder (under `~/Hackerman/archive/`) | snapshot mtime | git HEAD (last commit) | ASR | frontend | mobile | marks |
|---|---|---|---|---|---|---|
| `Skrift copy - right ebfore i started messign woth the frontend with hendri` | Mar 6 2026 | `LM Studio-style MLX settings, VLM support, per-model chat templates` (20 commits) | **Whisper only** (0 parakeet) | original `frontend/` (React) + `build`/`dist` | — | the desktop app **right before the v2 frontend rewrite done with "Hendri"** |
| `Skrift still has whisper AND parakeet` | Mar 20 2026 | `complete Skrift v2 frontend rewrite with batch ops and DMG support` (21 commits) | **Whisper AND Parakeet** (3 refs each) | `frontend-new/` + "New Frontend code" | — | the **ASR transition** (both engines co-resident) + the v2 rewrite landed |
| `Skrift before starting the mobile app` | Apr 2 2026 | `rename confidence → significance, add continuous file polling` (39 commits) | **Parakeet primary** (whisper ~gone) | `frontend-new/` | `Mobile/` scaffolded | the **mature Electron/Python desktop**, the moment **"significance"** is born, right before the mobile push |

All three share the same Oct-18-2025 initial commit (same lineage as the live repo).

### Dating the eras — what's actually anchorable (investigated 2026-06-21)

**The git log floors at Oct 18 2025 — that's when git was first used, NOT when Skrift began.**
Earlier history is only datable from **file mtimes** and dated doc content.

- **Earliest concrete artifacts found:** frontend `2025-07-09`, backend `2025-07-28` (in the
  snapshots). So this Skrift incarnation is **~July 2025 onward (~11 months as of Jun 2026)**.
- **No Skrift artifacts older than mid-2025 exist anywhere in `~/Hackerman`.** The user recalls
  "2 years or more" — that origin is **NOT on this machine's `~/Hackerman`** (external drive? old
  Mac? deleted? a differently-named prototype?). **OPEN: ask the user where the oldest material lives.**
- **Possible ancestor lineage:** `~/Hackerman/Shhhcribble` + `ShhcribbleiOS` (May 2025) — the user's
  native FluidAudio transcription app (the native rewrite's live-caption was ported from it). Only
  ~1 month older than the July files, so it doesn't explain a 2-year origin, but it's a related root.
- **Bogus dates to ignore:** `1985-10-26` mtimes appear on some copied assets in a nested
  `.claude/worktrees/.../mobile/` — corrupted timestamps, not history.
- **Privacy:** did NOT open `Obsidian_LLM_Test_Vault` or `Obsidian Backup` (vault rule).

**Implication for the backfill:** eras are cleanly datable from **~Jul 2025** (mtimes) and
**precisely from Oct 2025** (git commits). Anything claimed before Jul 2025 needs a source the user
provides — don't invent dates. So in the viz, pre-git eras may need approximate/"~2025" stamps or an
explicit "exact date unknown" treatment.

---

## Draft era timeline (candidate `HISTORY` content — for the future build)

The arc the backfill would render as a left-flowing "deep history" lane that feeds into the current
spine. (The roadmap's current `HISTORY` array is only the last hop — `mobile-native` + `desktop-native`
→ P0 — i.e. the boundary between eras 6→7 below. Backfill = add eras 1–5 to its left.)

1. **Genesis — Whisper desktop** · *Oct 18 2025* — initial React + Python transcription pipeline;
   renamed to Skrift, dependencies externalized to `~/Skrift_dependencies/`.
2. **Whisper-era desktop matures** · *→ Mar 6 2026* — Electron + React (`frontend/`), Metal Whisper
   ASR with word-timings, MLX enhancement (Qwen), name-linking → `[[Obsidian]]`, Markdown export,
   LM-Studio-style MLX/VLM settings. *(Snapshot A)*
3. **v2 frontend rewrite (with Hendri) + Parakeet arrives** · *Mar 6 → Mar 20 2026* — `frontend-new`
   rewrite (batch ops, DMG packaging); backend gains **Parakeet** alongside Whisper. *(Snapshot B)*
4. **Parakeet migration + "significance" + mobile scaffold** · *→ Apr 2 2026* — Parakeet-MLX becomes
   primary; audio preprocessing (HP filter / denoise / loudness), two-pass tag generation, karaoke
   read-along, **confidence → significance rename**, `Mobile/` scaffolded. *(Snapshot C)*
5. **React-Native mobile app** · *Apr–May 2026* — Expo RN `Mobile/`: recording + metadata capture,
   sync to the Mac, Lock-Screen widget, share-sheet import. *(now in live `archive/Mobile/`)*
6. **Native rewrite + convergence** · *Jun 2026* — `mobile-native` (SwiftUI iOS, FluidAudio/Parakeet)
   + `desktop-native` (SwiftUI macOS, FluidAudio + mlx-swift, **no Python/Electron**); merged →
   `native` → fast-forwarded into `main` (Jun 7–8); old apps archived intact. **← the current
   `HISTORY` array starts here.**
7. **Standalone App Store push** · *Jun 2026 →* — P0 shared naming engine, P1 CloudKit sync, the
   audiobook detour, P2 export… = the current forward roadmap (already in `PHASES`/`DETOURS`).

---

## How to build it later (keep it data-driven, no rework)

- Extend the existing **`HISTORY` array** in `ROADMAP.html` (same `track`/`order` layout contract) —
  each era = one node flowing left→right into the next, the last merging into `P0`. Optionally group
  by era-band labels like the milestone columns.
- Consider a **collapsed-by-default "‹ history" affordance** that expands the deep lane on click, so
  the default view stays the de-cluttered forward roadmap (the history is depth, not the headline).
- Each history node: `{ id, era, when, title, note, commit/doc pointer }`. The pointer (a commit hash
  or an `archive/…` path) lets a reader jump to the artifact. **The agent's primary source stays git +
  the ledgers; the visual is the human dashboard** (per the backlog principle).
- Reuse the snapshots only for human labels + artifacts; pull dated boundaries from the live `git log`.

## Open decision (for the user)

Build the deep-history lane **as its own session, after** you're happy with the current viz mechanics
(so the history isn't redone when the layout/interaction changes). This doc is the fast-start material
for that session. Also open: how far back / how granular (per-era vs per-notable-commit), and whether
history is collapsed-by-default.
