# Skrift

*Offline voice memo transcription and AI enhancement for macOS*

## What It Does

Transcribes iPhone voice recordings (.m4a) and Apple Notes exports to text using MLX-accelerated Parakeet, then cleans up names, enhances with a local LLM, and exports to Obsidian-compatible Markdown. Everything runs locally on your Mac — no cloud, no API keys.

**Features:**
- Drag-and-drop upload (audio files, folders, Apple Notes exports)
- Fast transcription via Parakeet-MLX with word-level timestamps
- Audio preprocessing: high-pass filter, adaptive denoising, loudness normalization
- Name linking with disambiguation (wiki-style `[[Name]]` links)
- AI enhancement pipeline: title, copy edit, summary, importance scoring, tags
- Two-pass tag generation: selects from your Obsidian vault's existing tags + suggests new ones
- Batch transcription and batch enhancement with live progress
- Karaoke-style word highlighting during audio playback
- Export to Obsidian vault with YAML frontmatter
- Fully configurable: edit prompts, models, audio settings, tag rules in-app

## Architecture

Electron + React frontend communicates with a FastAPI Python backend over HTTP on `localhost:8000`.

```
Skrift/
├── backend/              # FastAPI server (Python)
│   ├── api/              # Route handlers
│   ├── services/         # Transcription, enhancement, export logic
│   ├── config/           # Settings + user overrides
│   └── resources/        # Tag whitelist, names
├── frontend-new/         # Electron + React + Tailwind
│   ├── src/              # React app
│   └── electron/         # Main process + preload
├── Icons/                # App icons
└── Docs/                 # Documentation
```

**External dependencies** live outside the repo in `~/Skrift_dependencies/`:
- `mlx-env/` — Python venv with FastAPI, parakeet-mlx, mlx-lm
- `models/parakeet/` — Parakeet TDT v3 weights (auto-downloads on first use)
- `models/mlx/` — MLX language model for text enhancement

## Quick Start (Development)

```bash
# Start everything (backend + Electron dev mode)
open 'Open Skrift New.command'

# Or manually
cd frontend-new && npm run dev:electron
```

## Distribution

A distributable package lives at `~/Desktop/Skrift-Distribution/`:
- `Skrift-0.1.0-arm64.dmg` — the app
- `Skrift_dependencies/models/mlx/` — MLX model weights
- `setup.sh` — one-time setup: installs Python, ffmpeg, creates venv
- `README.txt` — setup instructions

Recipients run `./setup.sh`, drag app to Applications, point Settings to dependencies folder, done.

## Build

```bash
cd frontend-new && npm run build:electron
# Output: dist-electron/Skrift-0.1.0-arm64.dmg
```

## Pipeline

1. **Upload** — drag .m4a files or Apple Notes folders into the sidebar
2. **Transcribe** — Parakeet-MLX with audio preprocessing (single or batch)
3. **Clean Up** — name linking with `[[wikilinks]]`, disambiguation modal for ambiguous aliases
4. **Enhance** — LLM generates title, copy edit, summary, importance score, and tags (single or batch)
5. **Export** — compiles to Obsidian-compatible Markdown with YAML frontmatter

---
*macOS only (Apple Silicon). Requires Homebrew, Python 3.10+, and ffmpeg.*
