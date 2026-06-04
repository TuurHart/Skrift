# Skrift Overhaul — Session Handoff

> Working doc for the multi-session "make Skrift nicer + simpler" overhaul. Delete when the overhaul lands. You are picking this up mid-stream — **read §0 fully before touching code.**

## 0. Orient yourself FIRST (don't skip this)

Read these, in order, before making any change:

1. **The plan** — `/Users/tiurihartog/.claude/plans/abundant-greeting-eagle.md` (the full 6-phase plan + context + locked decisions).
2. **Memory** (auto-loaded into your context via MEMORY.md):
   - `project_overhaul.md` — all locked design decisions + rationale. This is the source of truth for *what we're building and why*.
   - `feedback_vault_privacy.md` — **CRITICAL boundary, read it.**
3. **`CLAUDE.md`** (repo root) — project architecture overview.
4. **Git history** — `git log --oneline main..overhaul` and skim each commit's diff. That's literally what's been done so far.
5. **The key code** for the next task — see §3 (read it before designing).

Branch: **`overhaul`** (cut from `cleanup/audit-fixes`). Everything committed. Backend venv python: `~/Skrift_dependencies/mlx-env/bin/python3`. ffmpeg: `/opt/homebrew/bin`.

## 1. Where we are

- **Phase 0 ✓** — branch, `backlog.md`, decisions → memory. (Also: the old "architecture skill" chat never committed anything; `robustness-cleanup` is a stale branch to *mine, not merge*.)
- **Phase 1 ✓ (backend cleanup)** — removed chat feature, dead VLM/vision path, ~1,900 lines of dead endpoints/scripts; atomic `status.json` writes; spec-valid CORS. ~2,450 lines gone, no behavior lost.
- **Phase 2 ✓ COMPLETE** (commits `fa1b392`, `ed6ab52`, `a583ff2`, `9129763`, `7f00479`):
  - ✓ Earlier groundwork: LLM significance scoring removed (manual slider via `POST /enhance/significance/{id}`); LLM tagger → **deterministic** vault-tag matching (≥2× lemmatized nl+en + spoken `#hashtags`; whitelist = frontmatter tag NAMES only, never bodies); `voiceEmbeddings` round-trips the names store.
  - ✓ **Reorder:** all LLM steps run on the **raw transcript**; `preserve_brackets` deleted (no LLM ever sees `[[ ]]`).
  - ✓ **Non-blocking name-linking:** unambiguous names auto-link; ambiguous ones recorded in a new `ambiguous_names` field on the note (shape = old 409 `occurrences`). No more mid-pipeline 409 / `DisambiguationModal`.
  - ✓ **Auto-run orchestrator** `POST /api/batch/run/start` (`BatchManager.start_run`/`_process_run`): two model-grouped passes — transcribe-all (Parakeet hot) → enhance-all (copy-edit/title/summary on raw → tag *suggestions* → name-link → compile draft) → **Ready**. Single file = run of one. `batch_manager` folded into this one path (old transcribe/enhance batch methods + endpoints removed).
  - ✓ **Frontend:** one **Process** button (Sidebar batch + Inspector single file). Inspector Cleanup section gone; enhancement gated on transcribe; manual mid-pipeline disambiguation removed.
  - ✓ **Unify:** single `clear_transcript_derived()` invalidation helper (was 3 lists).
  - **Verified LIVE end-to-end** on a user-provided test recording (the "two friends named Jack" memo): transcribe→…→name-link→compile→Ready, 4 ambiguous "jack" occurrences recorded (non-blocking), MLX cache cleared after.
- **Key behavior changes for later phases:**
  - `steps.enhance == done` now means **auto-steps complete** (title+copy-edit+summary present), NOT "tags approved." Tags + significance are **review-time**. `_all_enhancement_parts_present` reflects this; `compile` precedence is `sanitised → enhanced_copyedit → transcript`.
  - `ambiguous_names` needs a **review-time resolver UI** (the old `DisambiguationModal` component still exists, unused — re-wire it at review in Phase 5).
  - Inspector still has per-step manual enhance/redo (per-file SSE) — harmless, but the full review redesign (Phase 5) replaces it.
  - **Intentionally NOT unified** (would not simplify / would touch vault YAML): the two image-marker fns (timestamp vs anchor-word, different stages) and the note-vs-audio frontmatter builders. Revisit frontmatter with the Phase 5 export schema.
- Verified backend-healthy + frontend-type-check-clean after every chunk. Backend currently **running** (test note "Hotel Du Vin" is in the pipeline at Ready — deletable from the app).

## 2. Rules & hard-won lessons (read — these are not optional)

- **PRIVACY — never point AI/agents at the user's Obsidian vault.** Only the app's own local code may scan it. For tests, ask the user for a *small sample folder* and use only that. (I scanned the full vault via a subagent once; the user was rightly upset. See `feedback_vault_privacy.md`.)
- **Keep it SIMPLE.** The user pushed back hard when tagging got over-engineered (a "matchable vs structural" derivation). Default to the simplest thing that works; don't add classification/abstraction they didn't ask for.
- **Bring the user along.** They got lost when I moved too fast / used jargon. Explain in plain terms and confirm understanding *before* building anything big or non-obvious.
- **Commit each logical chunk** with a clear message ending `Co-Authored-By: Claude <noreply@anthropic.com>`. Stage specific files (not `git add -A`).
- **Verify every chunk**: `py_compile` the changed files; `./backend/start_backend.sh restart` then `curl -s localhost:8000/health`; frontend `npm --prefix frontend-new run type-check`. Test logic with **synthetic data**, not the user's real vault/notes. Stop the backend when you pause.
- **Delegate big mechanical chunks to subagents** (keeps your context lean — that's how Phase 1 got done) but always **verify their diffs**, and forbid them from touching the vault.

## 3. Phase 2 ✓ DONE — NEXT TASK is Phase 3 (frontend state rebuild)

Phase 2 (pipeline reorder + auto-run orchestrator) is complete and verified live — see §1 for the summary and the key behavior changes. **The next task is Phase 3** (detail in §5): replace the 3–4 overlapping ~1s polling loops (App.tsx 2×, Sidebar, Inspector) with ONE source of truth — TanStack Query keyed by file id + the existing SSE — and fix the contenteditable-vs-poll race. That is the real "feels buggy" cure. The Phase 2 detail below is kept as a record of what was built.

**Read these files before designing:**
- `backend/services/enhancement.py` — `build_enhancement_context` (source-text selection, currently `pf.sanitised or pf.transcript`), `generate_enhancement_stream` (step orchestration), `preserve_brackets` (the `[[Name]]` hack to DELETE) + its call (~line 763), `compile_file`, `_all_enhancement_parts_present`, `copy_edit_with_image_markers_stream` + `_reinsert_image_markers`.
- `backend/api/sanitise.py` — the 409-blocking name disambiguation.
- `backend/api/enhance.py` — per-step endpoints (title/copyedit/summary/significance/tags/compile/stream).
- `backend/services/batch_manager.py` — batch orchestration (fold into the canonical auto-run flow).
- `backend/utils/status_tracker.py` — `status.json` model; **note the 2–3 separate cascade-invalidation field lists** (`_TRANSCRIPT_DERIVED_FIELDS`, the list in `reset_for_retranscribe`, and one in `files.py reset_file`) — unify into one.
- Frontend `src/api.ts`, `src/features/Inspector.tsx` — the current manual sanitise→enhance flow the reorder replaces.

**Locked design (full detail in `project_overhaul.md`):**
- All LLM steps (copy-edit, title, summary) run on the **raw transcript**. **Name-linking becomes the LAST deterministic step** before compile. **Delete `preserve_brackets`** (no LLM ever sees `[[ ]]` links anymore).
- **Name-linking is non-blocking**: auto-link unambiguous names during the run; store ambiguous occurrences as a field on the note (resolved at the Review stop), instead of the mid-pipeline 409 modal.
- **Single auto-run orchestrator**: ingest → transcribe → copy-edit → title → summary → deterministic tag candidates → **"Ready for Review"**, with NO mid-flight human gates. Refactor `batch_manager` into the canonical pipeline; a single file = a batch of one. (Today the frontend drives steps manually; the new model auto-runs server-side.)
- Reconcile the carried `enhance_step` polling field (likely superseded by Phase 3's event-driven status).
- Unify the duplicated logic deferred from Phase 1: image-marker insertion (was 3 implementations) and the compile/frontmatter builder (2). Plus the invalidation lists above.

**Suggested sub-step order (commit each, verify each):**
1. Reorder source-text + delete the bracket hack (`enhancement.py`). Verify enhancement still produces output (synthetic text).
2. Non-blocking sanitise — ambiguities become note data, not a 409 block. Verify.
3. The auto-run orchestrator to "Ready for Review." Verify with a **small test recording the user provides** (this loads the MLX models — slow, expected; it's the real end-to-end test). Do NOT use the vault.
4. Unify image-markers + compile/frontmatter + the invalidation lists.

## 4. Remaining small bits (deferred, not done)
- **Two-title chooser** — store a user/phone-provided title alongside the LLM title + which is selected; capture a phone title on upload (`files.py` upload handler); `compile_file` uses the selected one. Coupled to the existing title-approval flow (`enhanced_title` + `title_approval_status` + approve/decline endpoints in `files.py`) — map that first. The chooser UI itself is Phase 5.
- **Speaker labels** — nothing to do until mobile diarization ships; transcripts store verbatim so labels are preserved. Display in Phase 5.

## 5. Then Phases 3–6
- **Phase 3 — frontend state rebuild** (the real bugginess cure): replace the 3–4 overlapping polling loops (App.tsx 2×, Sidebar, Inspector) with ONE source of truth (TanStack Query keyed by file id + existing SSE). Fix the contenteditable-vs-poll race.
- **Phase 4 — shadcn foundation**: deps already in `package.json`; install primitives; add `react-resizable-panels`, `cmdk`, `@tanstack/react-virtual`; dedupe `formatDuration` (×4).
- **Phase 5 — UX redesign**: Obsidian-mirror review surface — middle-pane editable **properties block** (two-title chooser, significance **slider**, tag **chips** + vault autocomplete) above the editable body; **karaoke-on-body** corrector (align body words → transcript `word_timings`, approximate is fine; fix the formatting-jump bug). **Mock BOTH right-pane layouts** (slim audio/status/actions rail vs 2-pane + toolbar) and let the user pick from visuals.
- **Phase 6 — polish/ship**: exercise all pipeline paths, update `CLAUDE.md`, build the DMG.

## 6. Note for the user
They don't need the overhaul finished to process notes — transcribe→enhance→export works on the app today. If they want to bring a batch of notes "to life" before the rebuild's done, that can happen on the current app anytime (it's their emotional priority — the "shower notes").
