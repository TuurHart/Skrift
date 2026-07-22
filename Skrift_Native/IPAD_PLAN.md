# iPad plan — Skrift on the iPad (wave 1, 2026-07-22)

Decision doc for the iPad edition. Extends the 2026-07-07 direction sketch (universal
target, review station) and the signed `mocks/journal-desktop.html` §2 ("the SAME phone
app at regular width"). Mock for this wave = `SkriftDesktop/mocks/ipad-app.html`.

## Roles — where the iPad sits

| Device | Role | Pipeline duty |
|---|---|---|
| iPhone | **Capture.** Record, live caption, share-ins, quick edits | Source of truth; raw transcripts |
| iPad | **Reading room.** Triage, read past thinking, books, comfortable editing | **On-demand polisher** (Polish now / polish-on-open) — never batches |
| Mac | **Factory + sink.** Batch polish, name-link, compile, Obsidian export | Automatic, unattended |

Polisher rule (locked 2026-07-07 thinking, built this wave): the Mac polishes
automatically because it runs unattended on wall power; the iPad polishes **only what
you ask for, while you look at it** (iPadOS won't run long GPU jobs backgrounded).
`MemoEnhancement` LWW by `enhancedAt` permits any author — no election protocol needed.

## Product shape (locked)

- **Never a third app.** SkriftMobile flips `TARGETED_DEVICE_FAMILY` `"1"` → `"1,2"`
  (app + widget + share extension). Same target, same code, sharing is automatic.
- **Same four tabs** (Notes · Books · Review · Settings) — phone muscle memory
  preserved; each tab **adapts at regular width** instead of stretching.
- iPhone stays portrait-locked; **iPad supports all orientations**
  (`UISupportedInterfaceOrientations~ipad`).
- Adaptation idiom: `NavigationSplitView` / standing panes at regular width,
  the phone's exact views promoted into columns — zero new logic where possible.
- Text never runs wall-to-wall: reading measure caps (~68ch) on note body,
  player, onboarding.

## Wave-1 scope (this session's lanes)

1. **Foundation** — device-family flip, per-idiom orientations, base builds green
   on the iPad Pro 13-inch sim. Conductor pre-ships (no lane).
2. **Shell + Notes** — Notes tab becomes list-column | detail-pane
   (`NavigationSplitView`); bottom chrome (record + book pill) stays in the list
   column; record/camera presentation sized for iPad; keyboard shortcuts
   (⌘N record, ⌘F search) + pointer basics.
3. **Note detail** — width-capped body, Related notes as a standing side panel at
   regular width (the Mac's signed related-panel, phone-flavored), Polish-now entry.
4. **Review (Journal)** — the signed §2 layout: river left, calendar + places
   standing right pane; selected day + map slide into the right pane.
5. **Books** — library grid at regular width (covers), player width caps,
   chapters/bookmarks as a side panel in landscape.
6. **Polish on iPad** — the local-models play: mlx-swift-lm (same pin as the Mac,
   same Gemma 4 E4B, same prompts single-sourced to `Shared/`) behind an
   `Enhancing`-shaped seam; Settings section gated to capable iPads; writes
   `MemoEnhancement` exactly like the Mac. Ships **feature-flagged**; sim can't run
   Metal-JIT MLX, so live generation is device-owed by contract.

## Out of scope (explicitly)

- Reading-mode redesign (signed 2026-06-19 mock) — its own wave; iPad inherits later.
- iPad batch/background polishing, polish elections.
- Mac-style Queue/pipeline surfaces on iPad (the Mac remains the factory).
- App Store iPad screenshots (standalone-push task).

## Risks + mitigations

- **MLX on iOS build risk** — polish lane is isolated + flagged; if it reds the
  merge gate it reverts alone, the rest of the wave ships.
- **Compat-mode → universal raises expectations** — that's this wave's point; the
  split-view IA lands in the same change as the family flip.
- **Old iPad Dev build** (erased additive fields once) — after this wave, install
  fresh Dev build on the iPad; local-only sanitize doctrine already protects fields.
