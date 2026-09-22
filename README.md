# Skrift

Transcribe iPhone voice recordings (+ Apple Notes) to text, sanitise (name-linking),
enhance (local MLX Gemma), and export to Obsidian-compatible Markdown — **fully offline**.

Two native SwiftUI apps that sync over the local network (Bonjour + HTTP) and share a
names database (bidirectional last-write-wins):

- **`Skrift_Native/SkriftMobile/`** — iOS. Records voice memos with contextual metadata +
  photos, transcribes on-device (FluidAudio / Parakeet on the Apple Neural Engine), syncs to
  the Mac. Live caption, Live Activity, widgets, App Intents, and an audiobook player with
  quote-capture.
- **`Skrift_Native/SkriftDesktop/`** — macOS. One process: FluidAudio (ASR) + mlx-swift
  (Gemma enhancement) in-process + a thin Bonjour/HTTP server as the phone's sync target.
  Transcribe → enhance → name-link → compile → export to Obsidian. **No Python, no Electron.**

## Docs — where to look

| Doc | What |
|-----|------|
| `CLAUDE.md` | How the repo is run + conventions + build/run commands |
| `roadmap/roadmap.yaml` | The live plan (done / now / next), rendered by the Tiuri Command Center |
| `SPEC.md` | The constitution (confirmed 2026-09-22) — point, done-means, marked clauses, decisions; `gate.sh` beside it |
| `archive/state-2026-09/` | The pre-spec state docs (backlog, SSOT, plans, surveys), frozen — the why behind a clause |
| `test-fixtures/corpus/` | The synthetic note corpus (106 notes) the v2 rewrite is judged on |
| `BUGS.md` | Every open bug in one list, worst first — pulled out of the ledger, each re-checked against source |
| `FEATURES.md` | Feature matrix (every feature × {mobile, desktop} × file × status) |
| `CHANGELOG.md` | Released versions |
| `LANE_PLAYBOOK.md` | Standing contract for parallel executor lanes (Sonnet executes, Fable conducts) |
| `archive/` | History — the Electron/Python/RN era, plus `archive/handoffs/` (the native-rewrite session ledgers + plans; the SSOT's cited deep tier) |

## Build

See `CLAUDE.md` → "Build / run". Both apps are **xcodegen** projects — regenerate the
`.xcodeproj` after pulling or moving files.

## Privacy

Fully offline; no cloud AI. Only the app's own code reads the user's Obsidian vault — never
point external AI/agents at vault contents.
