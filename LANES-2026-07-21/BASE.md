# Lifecycle IA overhaul — lane batch 2026-07-21

**BASE MARKER.** If you are a lane agent and this file exists in your worktree, your base is
correct (it only exists at/after the intended base commit). If it is MISSING, your base is
stale — STOP and `git reset --hard main` before any work. Never recreate this file by hand.

Conductor: Fable (main session). Executors: Sonnet lanes, one worktree each.
Spec of record: `Skrift_Native/SkriftDesktop/mocks/lifecycle-ia-explorations.html`
(Direction 2 + Direction 3's conveyor; Tuur's Q1–Q7 picks = backlog.md "🧬 CONTINUE HERE").
The spine is ALREADY SHIPPED: `Skrift_Native/Shared/Pipeline/MemoSpine.swift` (+ twin tests).

## Ownership map (lane → files). Writes outside your set are FORBIDDEN.

**LANE_SURF** (brief: `LANES-2026-07-21/LANE_SURF.md`) — Mac surfaces, steps ②③④:
- Skrift_Native/SkriftDesktop/Features/Sidebar/SidebarView.swift
- Skrift_Native/SkriftDesktop/Features/Sidebar/RecentlyDeletedView.swift (retiring)
- Skrift_Native/SkriftDesktop/Features/Shell/RootView.swift
- Skrift_Native/SkriftDesktop/Features/Shell/AppModel.swift
- Skrift_Native/SkriftDesktop/Features/Shell/Snapshot.swift
- Skrift_Native/SkriftDesktop/Features/Journal/JournalView.swift
- Skrift_Native/SkriftDesktop/Features/Journal/FadingShelfColumn.swift (absorbed)
- Skrift_Native/SkriftDesktop/Features/Settings/SettingsView.swift
- Skrift_Native/SkriftDesktop/Models/AppSettings.swift (deprecation comment ONLY — see brief)
- NEW files under Skrift_Native/SkriftDesktop/Features/ (WayOutColumn.swift,
  UnpipelinedMemoSheet.swift, LifecycleSweepScheduler.swift)
- NEW test files under Skrift_Native/SkriftDesktop/SkriftDesktopTests/

**LANE_AUTHOR** (brief: `LANES-2026-07-21/LANE_AUTHOR.md`) — step ⑤:
- Skrift_Native/SkriftDesktop/Pipeline/Ingest/UploadService.swift
- Skrift_Native/SkriftDesktop/App/MemoCloudReconciler+Wiring.swift
- NEW: Skrift_Native/SkriftDesktop/Pipeline/Ingest/MacMemoAuthor.swift
- NEW test files under Skrift_Native/SkriftDesktop/SkriftDesktopTests/
- READ-ONLY: everything else in Pipeline/Ingest (esp. MemoCloudIngest.swift — the gate line
  is sacred), Shared/, App/MacCloudWriteBack.swift.

**LANE_PHONE** (brief: `LANES-2026-07-21/LANE_PHONE.md`) — phone parity:
- Skrift_Native/SkriftMobile/Features/MemosList/MemosListView.swift
- Skrift_Native/SkriftMobile/Features/MemosList/FadingShelfView.swift (absorbed)
- Skrift_Native/SkriftMobile/Features/MemosList/RecentlyDeletedView.swift (absorbed)
- NEW: Skrift_Native/SkriftMobile/Features/MemosList/WayOutView.swift
- NEW test files under Skrift_Native/SkriftMobile/SkriftMobileTests/

**EVERY lane: READ-ONLY, no exceptions:** `Skrift_Native/Shared/**` (the spine + lifecycle +
models are contracts; if they seem insufficient, ESCALATE — do not edit), `roadmap/`,
`backlog.md`, `FEATURES.md`, `SKRIFT_SOURCE_OF_TRUTH.md`, the mocks, other lanes' files.

## Cross-lane seams (pinned so nothing diverges)
- Q6 toggle retirement is SPLIT: LANE_SURF removes the Settings UI row; LANE_AUTHOR flips
  `processEverything: settings.processAllSyncedMemosEnabled` → `processEverything: false` in
  MemoCloudReconciler+Wiring.swift. SURF must NOT delete the `processAllSyncedMemosEnabled`
  accessor (AUTHOR's flip makes it dead; the conductor deletes it after both merge).
- "Bring back" semantics (both apps, identical): sets `keptAt = Date()` ALWAYS (an explicit
  rescue is a touch — the note must not re-fade the next second) and clears `deletedAt` when set.
- All countdown/status copy comes from `MemoSpine.oneLiner(for:now:)` — never hand-written.
- New-symbol names are pinned in the briefs (WayOutColumn / WayOutView / MacMemoAuthor /
  UnpipelinedMemoSheet / LifecycleSweepScheduler / AppModel.ReviewShelf.wayOut). Exact spelling.

## Lane operating rules (playbook-adapted)
1. FIRST ACTION: verify this file exists in your worktree; report your base SHA in your final
   message. Missing → `git reset --hard main`, re-verify, then start.
2. Write `LANES-2026-07-21/PLAN_<LANE>.md` from your brief, commit it, then execute.
3. EDIT-ONLY LANES: do NOT run xcodebuild/simulators (one machine; builds serialize at the
   conductor's merge gate). Swift correctness = your care + the conductor's compile gate.
4. Commit per completed step with EXPLICIT paths (never `git add -A`/`add .`). End commit
   messages with the house Co-Authored-By line.
5. An honest blocker is a SUCCESS. If blocked or a decision would change doctrine: write
   `LANES-2026-07-21/ESCALATE_<LANE>.md` (question, evidence, your best two options), commit,
   end your turn reporting `ESCALATE: <one line>`. Never guess through a contract.
6. Final message: 5 lines — verdict, what shipped (commits + SHAs), files changed, your
   uncertain-decisions table (Decision / What I chose / Alternative / How to flip), blocked items.
