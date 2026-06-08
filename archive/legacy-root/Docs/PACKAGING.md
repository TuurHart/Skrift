# Skrift Packaging Plan (macOS)

> **OUTDATED:** This planning document predates the migration to parakeet-mlx. References to
> whisper.cpp binaries, rnnoise models, and bundled whisper resources are no longer applicable.
> The current distribution uses `setup.sh` + DMG. See CLAUDE.md for the current architecture.

**Goal:** Ship Skrift as a macOS app (`Skrift.app`) that users can drag into `/Applications` and run like any other app, with a separate download for large models and dependencies.

This document is the source of truth for how packaging works and how we measure progress.

---

## 0. High-Level Overview

### What we are shipping

1. **Skrift.app** (macOS application bundle)
   - Electron frontend (existing UI: Upload → Transcribe → Sanitise → Enhance → Export)
   - Embedded backend launcher (FastAPI + MLX + Whisper integration as a single binary)
   - Small bundled resources (whisper.cpp binary, configs, small assets)

2. **Skrift-Dependencies** (separate download, e.g. ZIP hosted on Google Drive or website)
   - Large, non-redistributable or frequently changing assets:
     - MLX enhancement models
     - Optional Whisper models
   - A small manifest file (`deps.json`) describing version and contents

### User experience

1. User downloads **Skrift.dmg** from website.
2. User drags **Skrift.app** into `/Applications`.
3. On first launch:
   - macOS may require `Right click → Open` once (unsigned app).
   - Skrift shows a simple **Dependencies Wizard** asking the user to:
     - Download `Skrift-Dependencies-mac-arm64.zip` from a link.
     - Unzip it somewhere (e.g. `~/Skrift-Dependencies`).
     - Choose that folder.
4. Skrift remembers the folder and starts the backend automatically on each run.
5. User sees the same app window they see today in development, and can run the full pipeline.

---

## 1. Milestones & Progress Checklist

### Milestone 1 — Basic Electron .app build (for own use)

**Goal:** Be able to build and run a `.app` and `.dmg` on your own machine, even if the backend is still started manually.

- [ ] Confirm `frontend/package.json` `build`/`dist` scripts work:
  - Commands:
    - `cd frontend`
    - `npm install`
    - `npm run build-renderer`
    - `npm run dist`
- [ ] Verify macOS artifacts exist (in `frontend/dist`):
  - [ ] `.dmg` (e.g. `Skrift-<version>.dmg`)
  - [ ] `.zip` (optional)
- [ ] Drag the app to `/Applications` and confirm it opens **when a backend is running**.
- [ ] Update the Electron config so the app is named `Skrift`:
  - [ ] Set `productName` to `Skrift` in `frontend/package.json`.
  - [ ] Set a matching `appId` (e.g. `com.skrift.app`).

> Once this milestone is complete, you can already open Skrift from Launchpad/Spotlight for your own development use.

---

### Milestone 2 — Backend becomes "app-aware" and path-agnostic

**Goal:** Backend can run correctly regardless of where Skrift.app lives and where the Dependencies folder is, using environment variables instead of hardcoded paths.

Back-end changes:

- [ ] Introduce environment variables:
  - [ ] `SKRIFT_APP_MODE` (e.g. `1` when running from the app bundle)
  - [ ] `SKRIFT_RESOURCES_DIR` (bundled resources path, provided by Electron)
  - [ ] `SKRIFT_MODELS_DIR` (external dependencies folder chosen by user)
  - [ ] `SKRIFT_DATA_DIR` (e.g. `~/Documents/Voice Transcription Pipeline Audio Output`)
  - [ ] `SKRIFT_LOG_DIR` (e.g. `~/Library/Application Support/Skrift/logs`)
- [ ] Add a small path resolver utility (e.g. `backend/utils/paths.py`) which:
  - [ ] Resolves Whisper binaries from `SKRIFT_RESOURCES_DIR/resources/whisper`.
  - [ ] Resolves models from `SKRIFT_MODELS_DIR/models/{whisper|mlx}`.
  - [ ] Uses reasonable defaults in dev mode (when env vars are not set).
  - [ ] Returns clear error messages if required paths are missing.
- [ ] Ensure no hardcoded personal paths remain (e.g. `/Users/…/Hackerman/mlx-env`).

Health/lifecycle endpoints:

- [ ] Add `GET /health` that returns quickly with JSON like:
  - `{ "ok": true, "pid": <int>, "version": "…" }`
- [ ] Add `POST /shutdown` that cleanly stops the backend process.

---

### Milestone 3 — Package backend into a single executable

**Goal:** Build a single backend binary (Apple Silicon) that Electron can spawn. End users do *not* need Python installed.

Build-time steps (on your dev machine):

- [ ] Install backend dependencies (no venv creation, per project rules):
  - [ ] `python3 -m pip install --upgrade pip`
  - [ ] `python3 -m pip install -r backend/requirements.txt`
  - [ ] `python3 -m pip install pyinstaller`
- [ ] Add PyInstaller spec file (e.g. `backend/packaging/backend.spec`) that:
  - [ ] Names the binary `skrift-backend`.
  - [ ] Targets macOS `arm64`.
  - [ ] Includes FastAPI/Starlette/Pydantic/MLX/Whisper adapters as hidden imports as needed.
  - [ ] Bundles configs (`backend/config/**`) and small resources (`backend/resources/**` without huge models).
  - [ ] Plays nicely with the `paths.py` resolver (handles PyInstaller `_MEIPASS` if needed).
- [ ] Build the binary:
  - [ ] `cd backend`
  - [ ] `pyinstaller backend/packaging/backend.spec`
- [ ] Verify that `backend/dist/skrift-backend` runs standalone:
  - [ ] `./dist/skrift-backend`
  - [ ] Visit `http://localhost:8000/health` and confirm a successful response.
  - [ ] Spot-check key endpoints (e.g. file listing, transcribe, enhance) in this mode.

---

### Milestone 4 — Bundle backend and whisper binaries into the app

**Goal:** Skrift.app includes the backend binary and whisper.cpp binaries as part of the Electron build.

Backend resources:

- [ ] Ensure whisper.cpp binary and any small default models are placed under `backend/resources/whisper/`.

Electron builder configuration (in `frontend/package.json` `build` section):

- [ ] Add `extraResources` for backend:
  - [ ] Copy `backend/dist/skrift-backend` into the app bundle, e.g. `backend/bin/skrift-backend`.
  - [ ] Copy `backend/resources/whisper/**` into `resources/whisper`.
- [ ] Configure `asarUnpack` so the backend binary and whisper folder are not compressed inside ASAR.
- [ ] Confirm mac target is `dmg` + `zip`, category `public.app-category.productivity`, `arm64` only.
- [ ] Disable code signing/notarization for now (identity `null`).

Rebuild Electron app:

- [ ] `cd frontend`
- [ ] `npm run build-renderer`
- [ ] `npm run dist`

---

### Milestone 5 — Electron main process: backend launcher + readiness

**Goal:** When Skrift.app starts, it automatically launches the backend, waits until it is healthy, then loads the UI. On quit, it shuts the backend down.

Main process changes (e.g. `frontend/main.js` or its TS equivalent):

- [ ] On `app.whenReady()`:
  - [ ] Compute `userData` path and log directory.
  - [ ] Read stored `SKRIFT_MODELS_DIR` from config (if any).
  - [ ] Compute `SKRIFT_RESOURCES_DIR = process.resourcesPath`.
  - [ ] Choose a backend port (e.g. default `8000`, fallback if in use).
  - [ ] Spawn `${process.resourcesPath}/backend/bin/skrift-backend` with env:
    - `SKRIFT_APP_MODE=1`
    - `SKRIFT_RESOURCES_DIR`
    - `SKRIFT_MODELS_DIR` (if set)
    - `SKRIFT_DATA_DIR`
    - `SKRIFT_LOG_DIR`
    - `PORT`
  - [ ] Poll `http://localhost:PORT/health` with a timeout (e.g. up to 20 seconds) until the backend is ready.
  - [ ] Only then create the BrowserWindow and load the UI.
- [ ] On app quit:
  - [ ] Call `POST /shutdown` on the backend.
  - [ ] If it does not exit in time, kill the process.
  - [ ] Flush any logs.

---

### Milestone 6 — First-run Dependencies Wizard

**Goal:** On first run (or when the models folder is missing), guide the user to download and select the `Skrift-Dependencies` folder.

Dependencies folder structure (example):

```text
Skrift-Dependencies/
  deps.json
  models/
    mlx/
      <mlx_model_1>/...
      <mlx_model_2>/...
    whisper/
      <optional_whisper_model_1>/...
```

`deps.json` example:

```json
{
  "name": "Skrift Dependencies",
  "version": "1.0.0",
  "requires": {
    "macos": "13+",
    "arch": "arm64"
  },
  "models": {
    "mlx": ["mlx-model-1"],
    "whisper": ["base.en"]
  }
}
```

Electron renderer / settings changes:

- [ ] Implement a simple **Dependencies Wizard** component that:
  - [ ] Explains where to download `Skrift-Dependencies-mac-arm64.zip`.
  - [ ] Lets the user choose the unzipped folder (via IPC to main process `dialog.showOpenDialog`).
  - [ ] Validates the folder by checking for `deps.json` and required model subfolders.
  - [ ] Persists the absolute path (e.g. using `electron-store` in app’s userData).
- [ ] On startup, before launching backend:
  - [ ] If no valid dependencies path is stored, show the wizard and block backend launch until the user completes it or cancels.

---

### Milestone 7 — Settings, errors, and UX polish

**Goal:** Make the app understandable and recoverable for non-technical users.

- [ ] Settings panel additions:
  - [ ] Show current Dependencies folder.
  - [ ] Button to change Dependencies folder (re-runs the selection dialog).
  - [ ] Dropdowns to select default Whisper model / MLX model (from what the backend reports).
  - [ ] Button to show logs (open log folder in Finder).
- [ ] Error handling:
  - [ ] If backend reports missing models, show a clear banner and shortcut to open Dependencies settings.
  - [ ] If backend fails to start, show an error dialog with next steps (e.g. reinstall dependencies, send logs).

---

### Milestone 8 — QA on a clean Apple Silicon Mac

**Goal:** Confirm a fresh user (no dev tools, no Python) can install and run Skrift.

Test scenarios:

- [ ] Fresh install flow:
  - [ ] Download `.dmg` and Dependencies zip.
  - [ ] Drag Skrift.app to Applications.
  - [ ] Right-click → Open the first time.
  - [ ] Complete Dependencies Wizard.
  - [ ] Full pipeline runs successfully.
- [ ] Missing models / corrupt deps folder:
  - [ ] App shows helpful error, not a crash.
  - [ ] User can fix by reselecting folder or redownloading zip.
- [ ] Long-running transcriptions and enhancements:
  - [ ] UI stays responsive, `lastActivityAt` heartbeats work.
- [ ] Restart behavior:
  - [ ] Quit app, reopen; backend starts cleanly, port is free.

---

### Milestone 9 — Release packaging and website

**Goal:** Have a repeatable release process and a simple download page.

Release artifacts per version:

- [ ] `Skrift-<version>-mac-arm64.dmg`
- [ ] Optional: `Skrift-<version>-mac-arm64.zip`
- [ ] `Skrift-Dependencies-mac-arm64-<depsVersion>.zip`
- [ ] SHA256 checksum file(s).

Website / documentation:

- [ ] Simple download page with:
  - [ ] Links to `.dmg` and Dependencies zip.
  - [ ] Hardware requirements (Apple Silicon, macOS 13+ etc.).
  - [ ] 3-step install guide.
  - [ ] One small section on macOS security: right-click → Open the first time.

---

## 2. How to Use This Document

- Treat each **Milestone** as a unit of work you can focus on for a session or two.
- Check items off as they’re completed in code (feel free to edit this file as you go).
- When questions come up (e.g. where to store a file, how to handle a specific error), we update this document so it remains the source of truth.

When you want to work on packaging again, pick the next unchecked item in the current milestone and we’ll implement it together.

---

## 3. Renderer Packaging Fix (dist Collision)

**Goal:** Make the packaged `Skrift.app` render the real UI (not gibberish) by separating the Vite renderer build output from Electron Builder’s output, so you can:

- Develop in dev mode (`npm run dev`)
- Cut a test DMG/`.app` (`npm run dist`)
- Use Skrift like a real app, write down bugs, then iterate

This is a **Milestone 1.5** between current Milestone 1 and the later backend-bundling milestones.

### 3.1 Root Cause (Why the Packaged App Is Gibberish)

Currently there is a single `dist/` directory doing two jobs:

- Vite writes the renderer (HTML/JS/CSS) into `frontend/dist/`
- Electron Builder uses `frontend/dist/` as its **output directory** and is also told to include `dist/**` in the app

During packaging:

- Vite writes `dist/index.html` (the correct small Vite HTML shell)
- Electron Builder then dumps DMGs, zips, `.app` folders, and internal builder files into the same `dist/`
- The `build.files` config says “include `dist/**` in the app”, so whatever ends up as `dist/index.html` inside `app.asar` might not be the real Vite HTML

Electron calls:

```js
mainWindow.loadFile(path.join(__dirname, 'dist', 'index.html'));
```

and loads whatever junk file landed there, which DevTools shows as “binary-ish text” with no network/console activity.

**Key point:** The UI code isn’t broken; the **packaging layout** is.

### 3.2 Target Layout (Clean Separation)

After the fix, the frontend folder should conceptually look like this:

```text
frontend/
├── main.js                  # Electron main process
├── preload.js
├── vite.config.ts
├── package.json
├── renderer-dist/           # Vite build output (ships inside app.asar)
│   ├── index.html
│   └── assets/**            # JS/CSS/assets emitted by Vite
└── dist/                    # Electron Builder output (installers and app bundles)
    ├── mac-arm64/
    │   └── Skrift.app
    ├── Skrift-<version>-mac-arm64.dmg
    └── Skrift-<version>-mac-arm64.zip
```

Rules:

- `renderer-dist/` = only the renderer bundle; this is what the app loads.
- `dist/` = only Electron Builder artifacts; not included as app content.

### 3.3 Code Changes (One-Time)

#### 3.3.1 Update Vite: build into `renderer-dist/`

**File:** `frontend/vite.config.ts`

- Change `build.outDir` from `"dist"` to `"renderer-dist"`.
- Keep `base: './'` (or use `mode === 'development' ? '/' : './'`) so assets resolve correctly under `file://` in production.

Example (adapt to existing config):

```ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import * as path from 'path';

export default defineConfig(({ mode }) => ({
  plugins: [react()],
  root: '.',
  build: {
    outDir: 'renderer-dist',
    rollupOptions: {
      input: {
        main: path.resolve(__dirname, 'index.html'),
      },
    },
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'src'),
      '@/components': path.resolve(__dirname, 'shared'),
      '@/lib': path.resolve(__dirname, 'src/lib'),
      '@/types': path.resolve(__dirname, 'src/types'),
      '@/hooks': path.resolve(__dirname, 'src/hooks'),
      '@/styles': path.resolve(__dirname, 'styles'),
    },
  },
  server: {
    port: 3000,
    strictPort: true,
  },
  base: mode === 'development' ? '/' : './',
}));
```

If you prefer to keep a simpler config, you can just update `outDir` to `renderer-dist` and keep your existing `base: './'`.

#### 3.3.2 Update Electron main: load `renderer-dist/index.html`

**File:** `frontend/main.js`

In `createMainWindow`, change the **production** path from `dist/index.html` to `renderer-dist/index.html`.

Before:

```js
// Production mode: load built renderer from dist/index.html
const indexPath = path.join(__dirname, 'dist', 'index.html');
console.log('Loading from:', indexPath);
try {
  await mainWindow.loadFile(indexPath);
} catch (error) {
  console.error('Failed to load index.html:', error);
}
```

After:

```js
// Production mode: load built renderer from renderer-dist/index.html
const indexPath = path.join(__dirname, 'renderer-dist', 'index.html');
console.log('Loading from:', indexPath);
try {
  await mainWindow.loadFile(indexPath);
} catch (error) {
  console.error('Failed to load index.html:', error);
}
```

The dev path (`http://localhost:3000`) remains unchanged.

#### 3.3.3 Update Electron Builder config: package `renderer-dist/**`, not `dist/**`

**File:** `frontend/package.json` (inside the `build` section)

Replace the `files` config that currently includes `"dist/**"` with one that includes `renderer-dist/**` and explicitly excludes `dist/**`:

Before:

```json
"directories": {
  "output": "dist",
  "buildResources": "build"
},
"files": [
  "dist/**",
  "main.js",
  "preload.js",
  "package.json",
  "styles/**",
  "src/lib/**"
],
```

After:

```json
"directories": {
  "output": "dist",
  "buildResources": "build"
},
"files": [
  "renderer-dist/**",
  "main.js",
  "preload.js",
  "package.json",
  "styles/**",
  "src/lib/**",
  "!dist/**"
],
```

Notes:

- `directories.output: "dist"` still tells Electron Builder to put DMGs/ZIPs/`.app` into `frontend/dist/`.
- `renderer-dist/**` is what goes into `app.asar` and is loaded by `main.js`.
- `"!dist/**"` prevents builder artifacts from being accidentally included in the app.

Your build scripts already follow the required order:

```json
"build-renderer": "vite build",
"dist": "npm run build-renderer && electron-builder"
```

### 3.4 Execution Steps

From `frontend/`:

1. **Clean old outputs (once after changing config):**

   ```bash
   rm -rf dist renderer-dist
   ```

2. **Build and package:**

   ```bash
   npm run dist
   ```

   Expected:

   - `renderer-dist/` is created by Vite with `index.html` and `assets/**`.
   - `dist/` is created by Electron Builder containing the DMG/ZIP and `.app`.

3. **Install and run the app:**

   - Open the new DMG in `frontend/dist/`.
   - Drag `Skrift.app` to `/Applications` (overwrite old one).
   - Launch `Skrift.app`.

4. **Verify the renderer:**

   - The window shows the real Skrift UI (no gibberish).
   - DevTools → Elements: you see a normal `index.html` DOM.
   - DevTools → Network: assets load from `file://` URLs, no HTTP failures.

5. **Connect to backend (for now, still manual):**

   - Start the backend the same way as in dev.
   - Confirm the packaged app behaves like your dev app once the backend is reachable.

### 3.5 Relation to the Overall Packaging Plan

This fix completes the missing structural step under **Milestone 1 — Basic Electron .app build**:

- Electron packaging is now layout-correct and stable.
- Renderer output (`renderer-dist/`) is cleanly separated from Electron Builder artifacts (`dist/`).
- Later milestones (bundling backend binary, resources, and dependency wizard) can rely on this layout without revisiting renderer packaging.
