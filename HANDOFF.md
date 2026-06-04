# Skrift Overhaul — Session Handoff

> Working doc for the multi-session "make Skrift nicer + simpler" overhaul. Delete when the overhaul lands. You are picking this up mid-stream — **read §0 fully before touching code.**

## 0. Orient yourself FIRST — understand WHY before WHAT

Read these, in order, before making any change. The point of this reading is **not** "what's the next ticket" — it's to understand **why this app exists and why the next phase matters**, so your design choices serve the real goal instead of just closing a task:

1. **The plan** — `/Users/tiurihartog/.claude/plans/abundant-greeting-eagle.md`. Read the **Context** section first (the problems being fixed + the *intended outcome*), then the locked decisions and the 6 phases.
2. **Memory** (auto-loaded via `MEMORY.md`):
   - `project_overhaul.md` — locked design decisions + rationale + **the app's identity and north star**. Read the identity part twice; that's the WHY.
   - `feedback_vault_privacy.md` — **CRITICAL, non-negotiable boundary. Read it.**
3. **This doc** — §1 (state), §2 (rules), §3 (next task).
4. **Git history** — `git log --oneline main..overhaul` and skim the diffs. That is literally what's been built.
5. **The key code for Phase 5** — see §3 (read before designing).

**The WHY, in one paragraph** (confirm it yourself from the plan + memory — don't take my word): Skrift is the **front door to the user's Obsidian vault-brain**. They capture voice notes — often fleeting "shower thoughts" they genuinely care about — the app processes them **unattended**, they do **one fast, mandatory review per note**, and it ships to Obsidian. *Reading* happens in Obsidian; the desktop note view is an **editor, not a reader**. North star (deferred): "see how a thought evolved over time." **Phase 5 builds the review surface — the one screen the user touches every day** — so it has to feel right. That's why the plan says to mock layouts and let the user choose *before* building, not after.

Branch: **`overhaul`** (cut from `cleanup/audit-fixes`). Everything committed; tree clean. Backend venv python: `~/Skrift_dependencies/mlx-env/bin/python3`. ffmpeg on `/opt/homebrew/bin`. Run the app: `open '/Users/tiurihartog/Hackerman/Skrift/Open Skrift New.command'` (or `cd frontend-new && npm run dev:electron`).

## 1. Where we are

- **Phase 0 ✓** — branch, `backlog.md`, decisions → memory. (Also: the old "architecture skill" chat never committed anything; `robustness-cleanup` is a stale branch to *mine, not merge*.)
- **Phase 1 ✓ (backend cleanup)** — removed chat feature, dead VLM/vision path, ~1,900 lines of dead endpoints/scripts; atomic `status.json` writes; spec-valid CORS. ~2,450 lines gone, no behavior lost.
- **Phase 2 ✓ COMPLETE** (commits `fa1b392`, `ed6ab52`, `a583ff2`, `9129763`, `7f00479`):
  - ✓ Earlier groundwork: LLM significance scoring removed (manual value via `POST /enhance/significance/{id}`); LLM tagger → **deterministic** vault-tag matching (≥2× lemmatized nl+en + spoken `#hashtags`; whitelist = frontmatter tag NAMES only, never bodies); `voiceEmbeddings` round-trips the names store.
  - ✓ **Reorder:** all LLM steps run on the **raw transcript**; `preserve_brackets` deleted (no LLM ever sees `[[ ]]`).
  - ✓ **Non-blocking name-linking:** unambiguous names auto-link; ambiguous ones recorded in a new `ambiguous_names` field on the note (shape = old 409 `occurrences`). No more mid-pipeline 409 / `DisambiguationModal`.
  - ✓ **Auto-run orchestrator** `POST /api/batch/run/start` (`BatchManager.start_run`/`_process_run`): two model-grouped passes — transcribe-all (Parakeet hot) → enhance-all (copy-edit/title/summary on raw → tag *suggestions* → name-link → compile draft) → **Ready**. Single file = run of one. `batch_manager` folded into this one path (old transcribe/enhance batch methods + endpoints removed).
  - ✓ **Frontend:** one **Process** button (Sidebar batch + Inspector single file). Inspector Cleanup section gone; enhancement gated on transcribe; manual mid-pipeline disambiguation removed.
  - ✓ **Unify:** single `clear_transcript_derived()` invalidation helper (was 3 lists).
  - **Verified LIVE end-to-end** on a user-provided test recording (the "two friends named Jack" memo): transcribe→…→name-link→compile→Ready, 4 ambiguous "jack" occurrences recorded (non-blocking), MLX cache cleared after.
- **Phase 3 ✓ COMPLETE** (commits `5da7a2e`, `ffca320`, `fbe2699`, `2872964`): replaced the 4 racing polling loops with **one source of truth** — `useFiles` (`['files']` query of full objects, polls 1s only while something is processing) + `useCurrentBatch`. App derives the selected file + enhance-lock from it; Sidebar/Inspector consume it; edits go through optimistic cache patches (`useFilesCache`) + invalidation. Fixed the contenteditable race with a **dirty-guard** in `NoteBody` (an in-flight refetch can't revert unsaved edits). SystemStatus keeps its own 15s `/health` poll (not a file-state race). **Verified live in-browser**: list/status load, zero console errors, a **blurred edit survived 3.5s of active refetches + the save with no revert**, enhance-lock banner accurate.
- **Phase 4 ✓ COMPLETE** (commits `769f571`, `a41c6d5`, `fc936ce`, `adf5c48`): shadcn component foundation. Deduped `formatDuration` (3 copies → `lib/format.ts`; `formatDate` left — two intentional formats). Added `src/components/ui/` primitives (button, dialog, input, tabs, tooltip, slider, sonner, command) **adapted to the app's tokens** (bg-accent / bg-surface / text-text-*), plus deps (radix slot/slider/tabs, sonner, cmdk, react-resizable-panels, @tanstack/react-virtual). Migrated 4 bespoke modals → Dialog (Sidebar delete, Inspector RAM, AddNameModal, EnhancementTab chat-template) — gains escape/focus-trap. **SetupWizard + Settings left as-is** (full-screen flows, not dialogs); **DisambiguationModal skipped** (orphaned since Phase 2). Inspector `Btn` now wraps Button (call sites unchanged); `<Toaster/>` mounted. **Verified in-browser**; full build passes. The not-yet-adopted primitives (input/tabs/tooltip/slider/command) + resizable-panels/virtual deps are foundation for Phase 5.
- **Startup heal ✓** (commit `1f0312a`): `status_tracker.load_existing_files` now demotes any stale `processing` step on load (no work survives a restart) — transcribe/sanitise/export → pending, enhance → done when title+copy-edit+summary present else pending. Fixes phantom spinners/locks (and, post-Phase-3, perpetual polling).
- **Phase 5 ✓ COMPLETE — all 7 chunks done** (Option B layout chosen by the user from rendered mockups: 2-pane + toolbar, no third column). **One thing still needs the user's eyes: the native titlebar (chunk 7b) can't be verified in the Vite preview — confirm in the real Electron app and tune `trafficLightPosition`/sidebar-header `pt-9` if the lights overlap the logo.** Commits:
  - `dbf8c70` **properties block**: significance **slider** (added `api.setSignificance` → existing `POST /enhance/significance`), tag chips + **vault autocomplete** (cmdk over cached `/tags/whitelist`, no vault scan), metadata grid. Reworked `NoteProperties.tsx`.
  - `24f35f9` **two-title chooser**: new non-lossy `title_suggested` field (model + `status_tracker.set_enhancement_title(suggested=)` + `POST /title` `suggested` flag + batch_manager passes `suggested=True`). Cards = Suggested vs From-recording (cleaned filename); active card editable; legacy notes (no suggestion) keep single title.
  - `696ca9e` **audio toolbar** `NoteToolbar.tsx`: skip ±10s (circular-arrow-with-10), play, draggable scrubber, speed; retired `AudioPlayer.tsx`.
  - `d97e0d0` **tag suggestions** one-tap dashed chips in properties block; **removed the `tag_suggestions=None` wipe** in `set_enhancement_fields` (was clearing all on first apply).
  - `296d148` **2-pane**: extracted `NoteActions.tsx` (contextual primary Process→Export→Re-export + ⋯ overflow re-transcribe/per-step redo; RAM dialog; lock→toast) onto the toolbar right; **deleted `Inspector.tsx`, `ExportPreview.tsx` (export-preview cut), `TagSuggestions.tsx`**. `NoteToolbar` now renders inline so transport + actions share one bar (bar shows even for no-audio notes).
  - `f17f0ec` **karaoke-on-body**: `KaraokeText` renders the body text (same words+typography) and uses transcript timings only for a moving highlight + click-to-seek (proportional alignment) — **fixes the play-time formatting jump**.
  - `e95baac` **ambiguous-name resolver + body=linked**: `getBestText` + NoteBody save-field now prefer `sanitised`, so the desktop body shows the **name-linked** text (what exports). New `ResolverStrip` surfaces `ambiguous_names` (alias + context + candidate people + "leave plain"); applying → new `POST /enhance/resolve-names` → `apply_resolved_names()` links each chosen alias into the current body (first mention `[[Canonical]]`, rest short name; preserves existing links + edits), clears `ambiguous_names`, recompiles. Deleted the superseded `DisambiguationModal` + `api.ts` `startSanitise`/`resolveSanitise`/`groupOccurrences`/`Ambiguity`/`SanitiseResponse`. (Backend `POST /sanitise/{id}` + `/resolve` + `resolve_name_disambiguation` are now frontend-orphaned — prune in Phase 6 after checking the mobile contract.)
  - `1c448b6` **virtualized queue + status chips**: sidebar list renders via `@tanstack/react-virtual` (windowed, dynamic measure); per-step `StepDots` replaced with one honest status chip (Queued/Transcribing/Transcribed/Enhancing/Ready/Exported/Error). Deleted orphaned `StepDots`.
  - `97eb381` **resizable panes**: queue|note split via `react-resizable-panels` **v4** (`Group`/`Panel`/`Separator`, `orientation`, **sizes are % strings** e.g. `defaultSize="22%"` — a bare number is PIXELS). Sidebar fills its panel (dropped the 280px hard-width). Resize works (keyboard-verified; synthetic pointer-drag won't trigger the lib's capture handler — that's a test limitation, real drag is fine). No layout persistence yet (resets to 22% per launch) — add via `useDefaultLayout` if wanted.
  - `02bacce` **native titlebar**: `titleBarStyle:'hiddenInset'` + `trafficLightPosition` in `electron/main.cjs`; sidebar header `pt-9` band holds the inset lights. **NEEDS user verification in the real Electron app.** Vibrancy deferred (would need translucent surfaces — a theme change to do with the user watching).
  - **Cleanup done:** deleted the throwaway `public/mockup.html` and the synthetic test-note folder.
  - **Verified** each chunk in-browser against a **synthetic note** (privacy: never screenshotted the user's real transcripts) + `npm run build`. The throwaway `public/mockup.html` and the synthetic note folder have since been **deleted** (cleanup done). To re-verify later, recreate a synthetic note: a folder under `~/Documents/Voice Transcription Pipeline Audio Output/` with a hand-written `status.json` (steps done, a `sanitised` body, optional `ambiguous_names`), an `original.md` (so `path` exists), a silent `processed.wav` (`ffmpeg -f lavfi -i anullsrc ...`) for source_type `audio`, and a `word_timings.json` (`{segments:[{words:[{word,start,end}]}]}`) for karaoke — then restart the backend.
  - **Lesson:** editing/deleting files corrupts the Vite dev-server HMR graph (cascade errors referencing deleted files / "Invalid hook call" / Toaster). `npm run build` is authoritative; **restart Vite (preview_stop+preview_start) for a clean console read.** Screenshots sometimes render small on a fresh server — take a second one or scale the element via `preview_eval`.

**Key behavior changes to honor in later phases:**
- `steps.enhance == done` now means **auto-steps complete** (title+copy-edit+summary present), NOT "tags approved." **Tags + significance are review-time.** `_all_enhancement_parts_present` reflects this; `compile_file` body precedence is `sanitised → enhanced_copyedit → transcript`.
- **State is ONE `useFiles` query.** Mutate via `useFilesCache` (optimistic patch) + invalidate — **do not reintroduce polling loops**. Never clobber the editor mid-edit (the `NoteBody` dirty-guard).
- `ambiguous_names` (on each note) → **RESOLVED in chunk 5 (`e95baac`).** The fork (body showed unlinked copy-edit while export used linked `sanitised`) was settled with the user: **the body now prefers `sanitised`** (`getBestText` + NoteBody save-field), so what you see/edit == what exports ([[links]] visible). The resolver (`ResolverStrip` + `POST /enhance/resolve-names` + `apply_resolved_names`) links chosen aliases into the current body and is edit/link-preserving. **Honor this precedence in later work: `sanitised` is the body's source of truth once sanitise has run.** (Edge: per-step "Redo copy-edit" sets `enhanced_copyedit` but not `sanitised`, so after a redo the body still shows the older `sanitised` until re-processed — acceptable; revisit if it bites.)
- **Intentionally NOT unified** (would not simplify / would touch vault YAML): the two image-marker fns (timestamp at transcription vs anchor-word post-copy-edit — different stages) and the note-vs-audio frontmatter builders (`compile_file` vs `_ingest_markdown_note`). Revisit frontmatter with the Phase 5/6 export schema.
- Backend currently **running** (test note "Hotel Du Vin" sits at Ready — deletable). A Vite dev server may also be running from Phase 3/4 browser checks.

## 2. Rules & hard-won lessons (read — these are not optional)

- **PRIVACY — never point AI/agents at the user's Obsidian vault.** Only the app's own local code may scan it. For tests, ask the user for a *small sample folder* and use only that. (I once scanned the full vault via a subagent; the user was rightly upset. See `feedback_vault_privacy.md`.)
- **Keep it SIMPLE.** The user pushed back hard when tagging got over-engineered. Default to the simplest thing that works; don't add classification/abstraction/foundation they didn't ask for. (When in doubt, ask whether a thing is worth the churn — e.g. they chose which modals to migrate.)
- **Bring the user along.** Explain in plain terms and **confirm understanding before building anything big or non-obvious.** For Phase 5 specifically: mock + let them pick *before* implementing.
- **Verify every chunk**: `py_compile` changed Python; `backend/start_backend.sh restart` + `curl -s localhost:8000/health`; frontend `npm --prefix frontend-new run type-check` (strict + `noUnusedLocals` — prune dead symbols). For UI behavior, **verify in the browser** (Vite dev + the `preview_*` tools), not just type-check. Test logic with **synthetic data**, never the user's real vault. (Note: brand-new files trip Vite HMR "failed to reload" — a hard reload clears it; a full `npm run build` is the authoritative check.)
- **Commit each logical chunk** with a clear message ending `Co-Authored-By: Claude <noreply@anthropic.com>`. Stage specific files (not `git add -A`).
- **Delegate big mechanical chunks to subagents** when it keeps your context lean, but always **verify their diffs** and forbid them from touching the vault.

## 3. NEXT TASK — Phase 5: the Obsidian-mirror review surface (design-heavy)

> **STATUS:** **Phase 5 COMPLETE — all 7 chunks built, verified in-browser (synthetic note), committed** (see §1). The review surface is the chosen Option B (2-pane + toolbar). **NEXT = Phase 6 (polish & ship, §5).** Two carry-overs: (1) **the native titlebar (chunk 7b) needs verification in the real Electron app** — tune `trafficLightPosition`/sidebar `pt-9` if the lights overlap the logo; (2) the two-title chooser's dedicated **phone-title capture on upload** (§4) is still deferred (the "From recording" candidate is the cleaned filename). Phase 6 should also prune the now frontend-orphaned backend sanitise endpoints (see the `e95baac` note) and **update `CLAUDE.md`** to match the new review surface.

This is the **core daily-use screen** and it is **visual + iterative** — unlike Phases 2–4, do **NOT** big-bang it. **Why it matters:** capture + unattended processing are pointless if review is annoying; review is where the user actually lives. Get it right and the app earns its identity (the front door to the vault-brain).

**Start with the gating step — DON'T build yet:** **mock BOTH right-pane layouts** for the user to choose from visuals (the plan + `project_overhaul.md` deliberately leave this undecided):
- (a) a slim audio/status/actions **rail**, vs
- (b) a **2-pane + toolbar** layout.

Present the mockups, let the user pick, **then** build. Confirm the middle-pane properties-block design with them too.

**Then build (browser-verify + commit per chunk):**
- **Middle-pane editable properties block** (Obsidian-style header) above the editable body: **two-title chooser**, significance **slider** (`ui/slider` ready), **tag chips** + vault autocomplete (`ui/command` ready), source/date. Reworks `NoteDisplay.tsx` / `NoteProperties.tsx`. These controls live in the Inspector today — the redesign moves them into the middle pane (the Inspector becomes the chosen right-pane layout).
- **Karaoke-on-body corrector:** align body words → transcript `word_timings.json` for click-to-seek (approximate within seconds is fine — copy-edit is minimal). **Fix the formatting-jump bug** in `KaraokeText.tsx`. No re-enhance on edit.
- **Ambiguous-name resolution at review:** surface each note's `ambiguous_names` (recorded in Phase 2) so the user picks the right person; re-wire `DisambiguationModal` or build fresh against that data.
- **Left-pane virtualized queue** (`@tanstack/react-virtual` ready) with honest status chips; one batch progress bar to "Ready."
- **Resizable panes** via `react-resizable-panels` (installed) in `App.tsx`; **native macOS feel** via window `vibrancy` + `hiddenInset` titlebar in `electron/main.cjs`.

**Read before designing (Phase 5 is mostly frontend):**
- `frontend-new/src/features/NoteDisplay.tsx`, `src/components/NoteProperties.tsx`, `src/components/NoteBody.tsx`, `src/components/KaraokeText.tsx` — the current middle pane + karaoke.
- `frontend-new/src/features/Inspector.tsx` — where significance/tags/title controls live today.
- `frontend-new/src/features/Sidebar.tsx` — the queue (virtualize it).
- `frontend-new/src/App.tsx` — pane layout + the one-query state wiring.
- `frontend-new/src/components/ui/*` — the primitives to compose with.
- `frontend-new/electron/main.cjs` — titlebar / vibrancy.
- Backend data is already in place (mostly no backend changes): `POST /api/process/enhance/{significance,tags,title}/{id}`, the `ambiguous_names` field, the `word_timings` endpoint.

## 4. Remaining small bits (fold into Phase 5, or 6)
- **Two-title chooser** — store a user/phone title alongside the LLM title + which is selected; capture a phone title on upload (`files.py` handler); `compile_file` uses the selected one. Map the existing `enhanced_title` + `title_approval_status` + approve/decline endpoints first.
- **Speaker labels** — nothing to do until mobile diarization ships; transcripts store verbatim so labels are preserved. Display in Phase 5.
- **Optional dead-code cleanup** (offered, user hasn't decided): orphaned `DisambiguationModal` + the uncalled `api.ts` sanitise helpers (`startSanitise` 409 branch, `resolveSanitise`, `groupOccurrences`) + the stale `needs_disambiguation` docstring in `sanitisation.py`. Either delete, or repurpose for the Phase 5 review resolver.

## 5. Phase 6 — polish & ship (last)
Exercise all distinct pipeline paths (Mac audio, Apple Notes, mobile trusted/untrusted, capture). **Update `CLAUDE.md` to match reality** — it predates the overhaul and does NOT reflect: the pipeline reorder (raw-transcript LLM + name-linking last), the auto-run orchestrator / Process button, the one-query frontend state, or the shadcn primitives. Build the DMG; confirm the packaged app spawns the backend and works.

## 6. Note for the user
You don't need the overhaul finished to process notes — transcribe→Process→export works on the app today. If you want to bring a batch of notes "to life" before the rebuild's done, that can happen on the current app anytime (your "shower notes" — the emotional priority).

## 7. Kickoff prompt for the next chat
Paste this to start the next session:

```
Resume the Skrift overhaul. Skrift is a macOS voice-note → Obsidian app
(Electron + React in frontend-new/, FastAPI backend in backend/) at
/Users/tiurihartog/Hackerman/Skrift, on git branch `overhaul`.

Before doing ANYTHING, get up to speed — and prioritise understanding WHY
this app exists and why the next phase matters, not just what the next task is:
1. HANDOFF.md at the repo root — read it FULLY, especially §0 (the WHY) and §3.
2. The plan: /Users/tiurihartog/.claude/plans/abundant-greeting-eagle.md —
   read the Context section (problems + intended outcome) before the phases.
3. Memory: project_overhaul.md (locked decisions + the app's identity/north
   star — the WHY) and feedback_vault_privacy.md (a hard rule — read it).
4. Run `git log --oneline main..overhaul` and skim diffs to see what's done
   (Phases 1–4 + a startup heal are complete and committed).
5. The Phase 5 frontend files listed in HANDOFF.md §3 — read them before
   designing anything.

In your own words, tell me WHY we're building the Phase 5 review surface and
how it serves the app's purpose — I want to know you understand the goal, not
just the ticket.

The next task is Phase 5: the Obsidian-mirror review surface. It is the core
daily-use screen and it's visual + iterative, so do NOT big-bang it. Per the
plan, START by mocking BOTH right-pane layouts (slim rail vs 2-pane+toolbar)
and let me pick from visuals before you build. Then design the middle-pane
editable properties block (two-title chooser, significance slider, tag chips +
vault autocomplete), the karaoke-on-body corrector (fix the formatting-jump
bug), ambiguous-name resolution at review, and the virtualized queue.

Hard rules (also in HANDOFF.md §2): NEVER point AI/agents at my Obsidian vault
— only the app's own local code may scan it; test with a small sample I give
you. Keep it simple (don't over-engineer or build speculative foundation).
Bring me along — explain in plain terms and confirm before building anything
big. Verify every chunk (py_compile + backend restart + /health for backend;
type-check + a real browser check via the preview tools for UI). Commit each
logical chunk.

Do NOT write code until you've read all of the above, can explain the WHY, and
we're aligned on the layout choice. Start by telling me what you found, the
WHY in your words, and present the right-pane layout mockups for me to pick.
```
