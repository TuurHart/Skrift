# BASE — iPad wave 1 batch (2026-07-22, Fable conducting)

Base = the commit that adds this file (branch `claude/ipad-app-version-3f9a3a`). Verify:
this file exists in your worktree; report `git rev-parse HEAD` in your wrap block.
Contract = `LANE_PLAYBOOK.md` (read FIRST). Design spec = `Skrift_Native/SkriftDesktop/mocks/ipad-app.html`
(m-sections referenced per brief) + `Skrift_Native/IPAD_PLAN.md` for the wave's rules.

## Groundwork already on base (do NOT redo)
- `project.yml`: TARGETED_DEVICE_FAMILY "1,2" (app+widget+share), iPad all-orientations,
  CFBundleVersion 106, mlx-swift-lm + hf/transformers/jinja pinned (app target only).
- `Shared/Pipeline/PolishPrompts.swift` (prompts + defaultModelRepo), desktop forwards to it.
- `Shared/Pipeline/ImageMarkerReinsert.swift` (MOVED from desktop Pipeline/Enhancement — now cross-app).
- `SkriftMobile/Services/Polish/PolishCenter.swift` (seam: phases, gate, MemoEnhancement write).
- `SkriftMobile/Services/Polish/PolishBootstrap.swift` (no-op; POLISH lane rewrites body).
- `SkriftMobile/DesignSystem/Adaptive.swift` (readingMaxWidth 640 · listColumnWidth 375 ·
  sidePanelWidth 300 · `View.readingMeasure()`).

## Ownership map (writes outside your set = FORBIDDEN)
| Lane | Model | Owns (write set) |
|---|---|---|
| SHELL | opus | `Features/Root/**`, `Features/MemosList/MemosListView.swift`, `Features/Recording/RecordView.swift`, `Features/Onboarding/OnboardingView.swift`, `App/SkriftApp.swift` (`.commands` only) |
| DETAIL | opus | `Features/MemoDetail/MemoDetailView.swift`, `Features/MemoDetail/NoteBodyView.swift` (width cap only), NEW `Features/MemoDetail/ConnectionsPanel.swift` |
| JOURNAL | sonnet | `Features/Journal/**` |
| BOOKS | sonnet | `Features/Audiobooks/**` |
| POLISH | opus | `Services/Polish/**` (may rewrite PolishBootstrap body + add `Engine/`), `Features/Settings/**` |

Everything else is READ-ONLY for every lane — including existing `Shared/**`, `project.yml`,
ledgers, mocks, `SkriftMobileTests/**` EXCEPT: each lane MAY add new test files under
`SkriftMobileTests/` named `IPad<Lane>*Tests.swift` for pure logic it adds (no UI tests).

## Cross-lane seams (pinned symbols — consume, never redefine)
- `Adaptive.readingMaxWidth` / `.listColumnWidth` / `.sidePanelWidth` / `.isPadIdiom`,
  `View.readingMeasure()`.
- `PolishCenter.shared`: `.isAvailable`, `.canPolish(_: Memo)`, `.polishNow(_:)`,
  `.phase(for: UUID)` (`Phase.idle/.downloading(Double)/.polishing(Double)/.failed(String)`),
  `.isWorking(_:)`. `PolishGate.isSupported`, `PolishGate.polishOnOpenKey`.
- `PolishEngine` protocol + `PolishResult` (POLISH implements; DETAIL/SETTINGS only via PolishCenter).

## The wave's layout law (every lane)
- Branch layout on `@Environment(\.horizontalSizeClass) == .regular` — NEVER on device idiom
  (Split View/Stage Manager can make the iPad compact; compact must stay the phone layout,
  pixel-untouched). `Adaptive.isPadIdiom` only for idiom facts (presentation style, keyboard).
- Compact = today's phone behavior, byte-for-byte where possible. Zero phone regressions is the
  batch's first acceptance bar.
- Prose never runs wall-to-wall: `readingMeasure()`.
- Existing launch flags (`-openTab`, seeds, UITest ids) must keep working — they're my merge-gate
  screenshot rig.
- Accessibility identifiers: keep every existing id; new interactive surfaces get ids
  (`ipad-` prefix for new ones).

## Cross-lane visual language (from the mock)
Selected list rows = `Color.skAccentSoft` fill (m1). Standing side panes = hairline
`Color.skBorder` separators, never cards-in-cards. Section labels = the existing
`SectionLabel`/uppercase-faint idiom.
