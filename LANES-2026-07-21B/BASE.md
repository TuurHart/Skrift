# 📖 ePub alignment — lane batch 2026-07-21B (spikes 4–5)

**BASE MARKER.** If you are a lane agent and this file exists in your worktree, your base is
correct (it only exists at/after the intended base commit). If it is MISSING, your base is
stale — STOP and `git reset --hard main` before any work. Never recreate this file by hand.

Conductor: Fable (main session). Executors: Sonnet lanes, one worktree each.
**Operating rules = `LANE_PLAYBOOK.md` (repo root) — read it FIRST, follow exactly.**
Spec of record: `backlog.md` "📖 ePub ↔ audiobook alignment" (design LOCKED by research;
all 5 open decisions LOCKED by Tuur 2026-07-21 — chapter precedence, aligner-internal
normalization, pin already bumped to v0.15.5, ZIPFoundation approved, .epub primary).
Probe ground truth (same section, spike 1): a real pair aligns at ≈98% coverage with 6,515
unique 4-gram anchors, 96% monotonic; the WRONG book yields ~40 non-monotonic anchors —
150:1 separation. Your code must reproduce this shape.

## Ownership map (lane → files). Writes outside your set are FORBIDDEN.

**LANE_EPUB** (brief: `LANES-2026-07-21B/LANE_EPUB.md`):
- NEW: `Skrift_Native/Shared/Pipeline/EPubParse.swift`
- NEW: `Skrift_Native/SkriftDesktop/SkriftDesktopTests/EPubParseTests.swift`
- NEW: `Skrift_Native/SkriftMobile/SkriftMobileTests/EPubParseTests.swift` (twin)

**LANE_ALIGN** (brief: `LANES-2026-07-21B/LANE_ALIGN.md`):
- NEW: `Skrift_Native/Shared/Pipeline/AlignmentCore.swift`
- NEW: `Skrift_Native/SkriftDesktop/SkriftDesktopTests/AlignmentCoreTests.swift`
- NEW: `Skrift_Native/SkriftMobile/SkriftMobileTests/AlignmentCoreTests.swift` (twin)

Everything else is READ-ONLY per the playbook. Reference material (read, never edit):
`Shared/Pipeline/Karaoke.swift` (the miniature ancestor),
`SkriftMobile/Services/Audiobooks/ChapterDetector.swift` (`parseNumber` — EN+NL numbers),
`SkriftMobile/Services/Audiobooks/BookTranscript*.swift` (sidecar shapes), `RunFile.anchorDrift`.

## Cross-lane seams (pinned so nothing diverges)

- **Pure Foundation ONLY, both new Shared files.** No ZIPFoundation, no new imports beyond
  Foundation, no I/O, no singletons — values in, values out. The desktop test bundle compiles
  `Shared/Pipeline` host-lessly and extension targets compile it too; ONE stray import breaks
  four targets. The zip layer + `-aligncheck` harness are the CONDUCTOR's, post-merge.
- **The two lanes do not import each other's types.** EPubParse outputs and AlignmentCore
  inputs are bridged by the conductor in the harness. Pinned names (exact spelling):
  - LANE_EPUB: `EPubParse` (enum, namespace) · `EPubBook` · `EPubBlock` · `EPubTOCEntry` ·
    `EPubDRMVerdict`. Input: already-unzipped entries as `[String: Data]` keyed by
    archive-relative path. `EPubBlock { text: String, sourceFile: String }`.
  - LANE_ALIGN: `AlignmentCore` (enum, namespace) · `AlignmentCore.Word { text: String,
    start: Double, end: Double }` · `AlignmentCore.Block { text: String, sourceFile: String }`
    (structurally mirrors EPubBlock on purpose; do NOT reference the EPub types) ·
    `AlignmentCore.Result` · `AlignmentCore.Verdict { aligned | partial | rejected }`.
- Image alt text is NEVER book text (probe finding: real alts are filenames).
- Tests use in-source string/synthetic fixtures only — no bundled files, no real book text
  beyond short public-domain snippets you write yourself (copyright).
