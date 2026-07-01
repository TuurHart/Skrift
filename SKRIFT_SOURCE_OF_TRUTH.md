# Skrift — Single Source of Truth

> **What this is.** One canonical, verified, chronological record of everything Skrift
> *is* and everything that's *happened* to it — consolidating ~20 scattered ledgers,
> handoffs, specs, the full git log (837 commits, 2025‑10‑18 → 2026‑06‑27), and the
> archived old app. It is both a **historical timeline** (back through every era) and
> the **current‑state + forward‑plan** reference. It is the roadmap source for the
> separate "Command Center" hub.
>
> **Provenance bar ("waterproof").** Every claim carries its source: a doc + locator
> (`file:line` or section), or a git commit hash. Anything not traceable is marked
> `[unverified]`. Where docs disagree, **both are shown** and the newer/authoritative
> one is named — see [§7 Contradictions](#7-contradictions--reconciliations).
>
> **Generated** 2026‑06‑28 by a fan‑out of 10 extraction agents (one per source group)
> + reconciliation + a completeness‑critic pass. A second **adversarial gap audit** (3 agents
> over thirds of `backlog.md`) then verified nothing actionable was lost in distillation; its
> findings are folded into §3. Source map in [§8](#8-provenance--source-map).
>
> **Two hard rules carried across every era** (current `CLAUDE.md` "Hard rules"):
> 1. **Privacy** — never point cloud AI/agents at the user's Obsidian vault. Skrift's
>    *own* on‑device code reading the vault is fine (clarified 2026‑06‑22,
>    `OBSIDIAN_EXPORT_ALTERNATIVES.md:19‑29`); the dev‑time rule (don't read the real
>    vault while building — use a sample) still binds.
> 2. **The mobile↔Mac contract is the spine** — multipart `POST /api/files/upload`; the
>    phone sends the **RAW transcript** (+ confidence/userEdited/markers/metadata/optional
>    `title`), **never `sanitised`**; the Mac links names. Trust =
>    `transcriptUserEdited || transcriptConfidence ≥ 0.7`. Names sync:
>    `GET /api/names/meta` → `GET` → LWW merge (**union** voiceEmbeddings) → `PUT`.
>    Byte‑compatible across both apps.

---

## Table of contents

1. [Timeline — the spine](#1-timeline--the-spine)
2. [Current state — features × {mobile, desktop}](#2-current-state--features--mobile-desktop)
3. [Open bugs / known issues](#3-open-bugs--known-issues)
4. [Forward roadmap (phase ledger)](#4-forward-roadmap-phase-ledger)
5. [Key decisions & rationale](#5-key-decisions--rationale)
6. [The contracts (wire specs)](#6-the-contracts-wire-specs)
7. [Contradictions & reconciliations](#7-contradictions--reconciliations)
8. [Provenance / source map](#8-provenance--source-map)

---

## 1. Timeline — the spine

Chronological, oldest → newest, dated from the git log. **Six eras.** Eras 1–2 are
**archived/superseded** (preserved under `archive/`); eras 3–6 are the native line that
is live today. Dates are ISO where the commit gives them; `[hash]` = git commit.

### Era 0 — Pre‑git prehistory `[unverified]`
- The user recalls the project being "2 years or more" old (`roadmap/HISTORY_BACKFILL.md:54`).
  **No artifacts older than mid‑2025 exist on this machine** — earliest file mtimes are
  frontend `2025‑07‑09`, backend `2025‑07‑28` (`HISTORY_BACKFILL.md:53`); git itself floors
  at 2025‑10‑18. A possible ancestor is `~/Hackerman/Shhhcribble` + `ShhcribbleiOS` (May 2025)
  (`HISTORY_BACKFILL.md:57‑59`). **Marked `[unverified]`: pre‑Oct‑2025 history is not in‑repo;
  HISTORY_BACKFILL flags "ask the user where the oldest material lives" (`:54‑56`).**

### Era 1 — Electron + Python genesis (2025‑10‑18 → 2026‑06‑05) — ⚠️ ARCHIVED
The original product: an **Electron/React desktop app** + a **Python (FastAPI) transcription
backend**, talking over `http://localhost:8000`. Now under `archive/frontend-new/` (Electron),
`archive/backend/` (Python). Full old project doc: `archive/CLAUDE-electron-python.md`.

- **2025‑10‑18** `[e96f92f]` MILESTONE — Initial commit: "Audio transcription pipeline app with React frontend and Python backend." The project's birth.
- **2025‑10‑18** `[b73b0aa]` CHANGE — Renamed the app to **"Skrift"**, externalized dependencies. (Same day: `[6006b3f]` WARP.md.)
- **2025‑10‑18** `[96614cf]` FEATURE — Batch‑processing Phase 1 (core infra). A concept that survives every era.
- *(gap Nov 2025 → Feb 2026 — no commits)*
- **2026‑03‑05** `[dbebf60]` FEATURE — Electron‑managed backend startup + loading screen.
- **2026‑03‑20** `[319fabf]` MILESTONE — Complete Skrift **v2 frontend** rewrite (`frontend-new`): batch ops + DMG distribution.
- **2026‑03‑26** `[de5fd51]` CHANGE — Migrated ASR engine **whisper.cpp → parakeet‑mlx** (the model lineage that still underpins ASR). *(Earlier sub‑layer used whisper.cpp + rnnoise; `archive/legacy-root/BACKEND_MAP.md:3‑5` is self‑labelled pre‑Parakeet.)*
- **2026‑03‑27** `[b4336dc]` FEATURE — Extract inline hashtags from Apple Notes → YAML frontmatter.
- **2026‑04‑05** `[a4730dc]` CHANGE — Switched enhancement model to **Gemma‑4‑E4B** (from `Qwen3.5‑9B‑MLX‑4bit`; "26B crashed Mac → need E4B"; `archive/legacy-root/BACKEND_MAP.md:230‑234`, memory `project_model_upgrade`).
- **2026‑04‑09** `[0a21c16]` FEATURE — Playback‑speed control, AI chat panel (later removed), markdown export preview.
- **2026‑04‑14** `[d1d3bc3]` FEATURE — Two‑phase **vision pipeline** + significance display. *(Short‑lived.)*
- **2026‑04‑27** `[c27a3e2]` CHANGE — **Removed the vision pipeline**, single E4B model. Simplification.
- **2026‑06‑04** `[c8e1c1c]` CHANGE — Removed the ask‑a‑question chat feature (ERA‑3‑precursor cleanup).
- **2026‑06‑04** `[83b76d4]` CHANGE — Replaced LLM significance scoring with a **user‑set value** (durable decision: significance is a manual slider, not AI).
- **2026‑06‑04** `[3e3acba]` CHANGE — **Deterministic vault‑derived tag matching** (drop the LLM tagger).
- **2026‑06‑04** `[a583ff2]` FEATURE — Auto‑run orchestrator to "Ready for Review" (the one‑button Process pipeline).
- **2026‑06‑04** `[5da7a2e]`/`[a41c6d5]` CHANGE — TanStack Query + shadcn primitives (the Electron "overhaul").
- **2026‑06‑04** `[e95baac]` FEATURE — Ambiguous‑name resolver + linked body text (the "two Jacks" lineage starts here).
- **2026‑06‑05** `[2f4469e]` FEATURE — Render Apple Notes images inline (HEIC→JPG). **Last Electron‑era commit.**

> Old API contract (the field names that EVOLVED into the native contract): `PipelineFile`
> with `filename` (not `name`), `uploadedAt` (not `addedTime`), `transcript` (not `output`),
> `path` (top‑level audio), no top‑level `status` (derive from `steps.{transcribe,sanitise,enhance,export}`),
> `audioMetadata.duration` as `"HH:MM:SS"` (`archive/legacy-root/API_REFERENCE.md:1430‑1497`). The
> names‑sync endpoints (`/api/names/meta`, `/api/names` GET/PUT, LWW + tombstones + 90‑day prune +
> `voiceEmbeddings`) carried **straight into native** (`archive/CLAUDE-electron-python.md:234‑263`).

### Era 2 — React Native mobile companion (2026‑04‑02 → 2026‑05‑02) — ⚠️ ARCHIVED
The iPhone companion (Expo SDK 54, RN 0.81, expo‑router), built *alongside* the Electron desktop
(overlaps Era 1). Now under `archive/Mobile/`. Introduced the two‑app architecture that survives
every rewrite.

- **2026‑04‑02** `[daf84b3]` MILESTONE — Added **Skrift Mobile** (Phase 1) — the iPhone companion.
- **2026‑04‑02** `[3c7a98b]` FEATURE — Mobile Phase 2: playback + contextual metadata capture.
- **2026‑04‑03** `[2fa554a]` MILESTONE — Mobile Phase 3: phone→Mac sync + **QR pairing** (QR later dropped).
- **2026‑04‑03** `[9ab502a]` FEATURE — Phase 4 polish (theme, prompts, swipe, YAML, Inspector, Share Sheet).
- **2026‑04‑03** `[6f24d3f]` FEATURE — Phase 5: **Lock Screen widget** + `skrift://record` deep link + Obsidian backfill script.
- **2026‑04‑11** `[80b0377]` FEATURE — Dynamic Island **Live Activity** + Quick Actions.
- **2026‑04‑11** `[818a827]` FEATURE — **Universal capture inbox** (share URLs/images/text). The "capture items" concept originates here.
- **2026‑04‑14** `[773dc2c]`/`[5d78cf8]` FEATURE — Photo capture during recording (`feature/photo-capture`, merged 04‑15).
- **2026‑04‑15** `[2a6c579]` FEATURE — Pause/resume recording with paused‑time‑aware photo timestamps.
- **2026‑04‑27** `[b3b1010]` FEATURE — Backend names‑sync API + `.opus` audio + (later‑removed) `sanitised` upload field.
- **2026‑04‑27** `[a48286b]` FEATURE — Mobile **FluidAudio Parakeet TDT v3** native module + on‑device sanitise + bidirectional names sync. *(On‑device sanitise was later REVERSED — see Era 3.)*
- **2026‑05‑02** `[a4f1527]` FEATURE — Per‑file Inspector state + real cancellation. **Last RN‑era feature.**
- **2026‑06‑05** — `MOBILE_OVERHAUL_PLAN.md` research completed; the 3 planned RN features (on‑device tag matching, CTC word boosting, diarization + voice profiles) were **never built in RN** — they became native‑era work (`archive/legacy-root/MOBILE_OVERHAUL_PLAN.md:3,36‑66`).

### Era 3 — Native SwiftUI rewrite (parallel mobile + desktop) (2026‑06‑05 → 2026‑06‑07)
Both apps rebuilt as pure native SwiftUI — **no Python, no Electron** — on two branches
(`mobile-native`, `desktop-native`), each marching through Phases 0–9 in ~two days, ending
with a verified live phone→Mac round‑trip. (Toolchain = xcodegen + xcodebuild + XCUITest.)

- **2026‑06‑05** `[4b38dad]` MILESTONE — Native SwiftUI rewrite plan for Skrift mobile (the decision to go native).
- **2026‑06‑05** `[09541e0]` MILESTONE — Mobile **Phase 0** toolchain spike green (xcodegen + first XCUITest).
- **2026‑06‑06** `[aa71b85]` MILESTONE — Desktop **Phase 0**: mlx‑swift Gemma 4 **go/no‑go = GO NATIVE** (no Python sidecar). 8bit Gemma load 3.2s, ~10.8 tok/s, peak ~8.75 GB on M4 (`DESKTOP_NATIVE_REWRITE_PLAN.md:222`).
- **2026‑06‑06** `[d67c489]` FEATURE — Mobile Phase 1: SwiftData model + names store/sync (names sync pulled forward).
- **2026‑06‑06** `[3e667a2]` FEATURE — Mobile Phase 2: recording + transcription (one‑shot‑on‑stop, not live VAD).
- **2026‑06‑06** `[8291041]` FEATURE — Desktop Phase 3b: FluidAudio adapter — **real ASR verified on M4/ANE** (Parakeet‑v3, conf 0.998).
- **2026‑06‑06** `[6624a89]` FEATURE — Desktop Phase 4b: mlx‑swift Gemma enhancement service in‑process.
- **2026‑06‑06** `[41b40c7]` FEATURE — Desktop Phase 6: BatchManager auto‑run (headless pipeline complete, Phases 0–6 green).
- **2026‑06‑06** `[108a86f]` MILESTONE — Mobile **Phase 7 design LOCKED** (mock‑first UI process, v5/mockups).
- **2026‑06‑06** `[9f7b49e]` FEATURE — Mobile Phase 7.1: **caption‑first record** + live streaming (Shhhcribble path ported).
- **2026‑06‑07** `[bb7cc95]` MILESTONE — Desktop `-runfile` harness + **REAL end‑to‑end run verified** on the two‑Jacks "Hotel Du Vin.m4a": Parakeet → Gemma copy‑edit + title + summary → Sanitiser flagged all 4 "Jack" ambiguous → 792‑char Obsidian markdown, **105s on M4, NO Python**.
- **2026‑06‑07** `[c217f69]` FEATURE — Desktop Phase 8: file/folder ingest + drag‑drop.
- **2026‑06‑07** `[55c2032]`→`[ece27b9]` FEATURE — Mobile Phase 8: SkriftShared + **Live Activity**, **App Intents** + Control Center + Siri (plain `AppIntent`+`openAppWhenRun` — **SIGTRAP‑avoided by design**), share‑to‑import audio, `skrift://record`.
- **2026‑06‑07** `[a41c1e4]` MILESTONE — Mobile Phase 9 parity sweep (RN→native matrix). Retirement of RN deferred.
- **2026‑06‑07** `[97a3bf1]` CHANGE — Phase 9a: hand‑editable transcript + **Re‑transcribe removed**; `[3773b5f]` Lock/Home record widget.
- **2026‑06‑07** — **LIVE ROUND‑TRIP VERIFIED** on a real iPhone 13 → native SkriftDesktop over Wi‑Fi: 2 memos uploaded (`memo_<uuid>.m4a`), Mac trusted the on‑device transcript (`steps.transcribe=done`), names synced (`MOBILE_NATIVE_HANDOFF.md:373‑378`). Unblockers: **ATS `NSAllowsLocalNetworking`** (iOS blocked cleartext LAN HTTP) + **Bonjour resolve forced to IPv4** (was a dead `fe80::` link‑local).

### Era 4 — Convergence to one branch (2026‑06‑07 → 2026‑06‑14)
Both branches collapsed into one trunk so cross‑app features land atomically; old apps preserved
intact under `archive/`.

- **2026‑06‑07** `[9e338b6]` MILESTONE — **MERGE: converge `mobile-native` + `desktop-native` → `native`** (conflict‑free).
- **2026‑06‑07** `[8b3a409]` CHANGE — Reorg: apps grouped under **`Skrift_Native/{SkriftMobile,SkriftDesktop}`**; old Electron/Python/RN archived intact under `archive/` (+ old doc → `archive/CLAUDE-electron-python.md`).
- **2026‑06‑08** `[150fd4f]` FIX — **Cold‑launch auto‑record** (Siri/widget) fixed after a 4‑cause device hunt; the killer = `Haptics.tap()` blocking the main actor because haptics share the audio session Siri still owns just after a voice launch.
- **2026‑06‑08** — **Phase 8 device‑verified on a real iPhone 13**: Live Activity / Control Center / Siri / Lock‑Screen widget / share‑import all work; App Intents register with **NO SIGTRAP** (`MOBILE_NATIVE_HANDOFF.md:571‑579`).
- **2026‑06‑08** `[5415b52]`/`[ebd777e]` FEATURE — **Dev/prod split** via per‑config bundle IDs (`com.skrift.{mobile,desktop}.dev`, isolated data container; macOS dev → TEST vault). The DATA‑SAFETY foundation.
- **2026‑06‑08** `[6be7847]` FEATURE — App icons for both apps; `[9a771f6]` inverted‑color dev icon (Debug only).
- **2026‑06‑09** `[d96dafb]` FIX — MemoDetail `TabView(.page)` → SwiftUI paging ScrollView (root‑cause fix for 3 broken‑on‑device features: glass refraction, significance drag, word‑tap‑seek).
- **2026‑06‑09** `[4678c1c]` MILESTONE — Diarize spike switches to **NVIDIA Sortformer** (clean splits, no tuning) — locked the diarization engine.
- **2026‑06‑09** `[8ccc3d2]`/`[245db92]` FEATURE — Embedding‑cosine **voice identity** (mobile + desktop): diarize (Sortformer) → wespeaker embedding → cosine vs `Person.voiceEmbeddings`. Measured **threshold 0.5** (diff ≤0.22, same ≥0.62; embeddings NOT unit‑norm; need ≥2s) (`CONVERSATION_MODE_HANDOFF.md:27‑30`).
- **2026‑06‑09** `[07378ea]` FEATURE — **Video import** → audio + 1 frame thumbnail (both apps).
- **2026‑06‑10** `[30fb318]` FEATURE — `pull-phone-feedback` project skill (devicectl pull → parse → verify → triage).
- **2026‑06‑11** `[4295887]` FEATURE — **Trash / Recently Deleted** (2‑week retention), mobile.
- **2026‑06‑11** `[bb00554]` CHANGE — Significance slider → 10‑circle control (signed‑off mock).
- **2026‑06‑11** `[a32436e]`/`[006eb22]` FEATURE — **Audiobook quote‑capture** built (player + library + retroactive capture; desktop quote‑aware pipeline + export).
- **2026‑06‑12** `[fbf8bd2]` FIX — **AirPods P0** closed (round 4, device‑verified): validate/install the tap with **`inputFormat` not `outputFormat`**. (4 layers: crash → policy → cache → wrong API property.)
- **2026‑06‑12** `[8d22c1f]`/`[1704f9b]` MILESTONE — **Capture items** shipped both lanes (mobile share‑ext + App‑Group inbox; desktop UploadService branch). Closed the last cross‑track parity gap. Contract = `Skrift_Native/CAPTURE_CONTRACT.md` (C3).
- **2026‑06‑12** `[8d7d7c9]` FEATURE — **Custom vocabulary** (CTC keyword‑spot + rescore, both apps).
- **2026‑06‑13** `[8c653d7]` FIX — Custom vocab "Script→Skrift never corrects" root‑caused: the booster was never WARM (per‑process, non‑blocking). Fix = pre‑warm at launch + aliases + trust guard. **Device‑confirmed working.**
- **2026‑06‑13** `[661179d]`/`[7a43c55]`/`[80c2aad]` FEATURE — Text‑capture **WAVE 2** (book transcript sidecar + ChunkFusion + resumable job); player **text‑forward A+D hybrid** redesign (read‑along, bookmarks, TOC); **chunk‑drift fix** (sample‑accurate `AVAudioFile` reads, not `AVAssetExportSession`).
- **2026‑06‑14** `[518bf58]` RELEASE — **TestFlight build 1 (0.1.0(1))** uploaded (internal, no review; via Xcode Organizer GUI — the ASC API‑key CLI export fails).
- **2026‑06‑14** `[cc4fa53]` MILESTONE — **`main` is the trunk now** — `native` fast‑forwarded into `main` (clean, 215 commits) + pushed. Work moves to `main`.
- **2026‑06‑14** `[116c7b3]` FIX — Turn‑aware conversation name‑linking + guard re‑transcribe (the conversation bug‑hunt: inline `[[Canonical|spoken]]`, first‑header‑canonical/rest‑short, merge same‑speaker turns, diarized→trusted).

### Era 5 — Standalone App Store direction + naming‑model rederivation (2026‑06‑15 → 2026‑06‑20)
The strategic pivot: ship **SkriftMobile standalone** ($0.69, no IAP) with CloudKit internal sync;
Mac + Obsidian become optional sinks over one source of truth. Plan = `STANDALONE_PLAN.md`.

- **2026‑06‑15** `[00a4304]` RELEASE — Mic glyph on voice‑memo rows + **build 2** (TestFlight).
- **2026‑06‑15** `[95dd058]` MILESTONE — Commit **`STANDALONE_PLAN.md`** + standalone mocks (WIP baseline). Locked decisions block (2026‑06‑15): **$0.69 / no IAP, full‑vision v1, CloudKit (not iCloud‑Drive), one‑way Obsidian publish, on‑device Polish as a gated spike, three coexisting modes** (`STANDALONE_PLAN.md:26‑41`). *(This commit also restates "build 2" — see [§7 #2](#7-contradictions--reconciliations).)*
- **2026‑06‑15** `[bc0b5b5]` CHANGE — Summary gate + conversation‑mode **off by default** + "Flatten to monologue."
- **2026‑06‑16** `[dd2f7e3]` MILESTONE — Re‑scope: first‑principles rethink of the WHOLE naming/sanitising solution.
- **2026‑06‑16** `[4f010c1]` MILESTONE — **LOCK the re‑derived naming model** (`NAMING_MODEL.md`): default **OPT‑OUT** + risk‑tiered auto‑write; known‑roster‑only (no NER/LLM); one body link (first mention); KILL the chip bar + per‑occurrence resolver. **SUPERSEDES** the opt‑in approach + shipped chunks 1–5.
- **2026‑06‑16** `[67de42f]`…`[chunk5]` FEATURE — Naming model built (chunks 1–5): Sanitiser opt‑out + risk‑tiering, roster seeding from `People/` titles, delete chip‑bar/resolver, in‑prose 3‑tier UX, RosterAudit. 286 UnitTests green.
- **2026‑06‑17** `[11ff8a9]` RELEASE — **build 0.1.0(4)** for the TestFlight/prod promotion *(build 3 skipped — see [§7 #1](#7-contradictions--reconciliations))*.
- **2026‑06‑17** `[ea3eeed]` MILESTONE — **Standalone Phase 0**: unify NamesData into **one shared cross‑app source folder** (`Skrift_Native/Shared/Naming/`), compiled by both apps. 288 desktop + 400 mobile tests green.
- **2026‑06‑17** `[345ea0a]` MILESTONE — **Standalone Phase 1/1b**: enable **CloudKit sync** for the Memo row (the internal‑sync backbone; drops `@Attribute(.unique)` from `Memo.id`). **Device‑verified iPhone→iPad, no Mac.**
- **2026‑06‑18** `[ec10bf5]`/`[5ca7c1e]`/`[fddf690]` FEATURE — CloudKit media (CKAsset, **device‑verified**), sidecars, **names + enrolled voices**, **custom vocabulary** all sync across devices (Phases 1c–1f).
- **2026‑06‑18** `[63bf236]`/`[563820f]` RELEASE — CloudKit silent **push** + pull‑to‑refresh; **build 0.1.0(6)** + floating sync indicator. (Builds 5–12 all land 2026‑06‑18.)
- **2026‑06‑18** `[974abfd]`/`[6d10b77]` FEATURE — **Raw‑CloudKit audiobook audio transport** (real %, `CKModifyRecordsOperation` progress) + "Turn it on" size sheet — **build (12)**.
- **2026‑06‑19** `[a9b8502]` RELEASE — **build (13)** "everything syncs" (cover + read‑along transcript + position + rate).
- **2026‑06‑19** `[e5a6b45]`/`[0c31d6d]` MILESTONE — **Visual roadmap** (`roadmap/ROADMAP.html`) — first as a tech‑tree, then rebuilt into the interactive, commentable **metro‑tree** (zoom/pan).
- **2026‑06‑19** `[c9568b3]`→`[4bcca6e]` FEATURE — **Audiobook reading‑mode redesign** + tab‑bar IA (Notes · Library · Highlights · Settings); "significance" → **"Importance"** relabel; **build 14**.

### Era 6 — Mac↔CloudKit round‑trip + 0.2.0 (2026‑06‑21 → 2026‑06‑29, current)
The Mac rejoins as a **CloudKit client** of the phone's notes (reads raw memos, enhances, writes
polish back), and the on‑device export / phone name‑linking path matures, culminating in the
**0.2.0 "iCloud round‑trip" release**. Plan = `MAC_CLOUDKIT_PLAN.md`.

- **2026‑06‑21** `[4b7682d]` FEATURE — Share a **PDF/document** into Skrift → `.file` capture (build 15).
- **2026‑06‑21** `[da9097f]`/`[946c3df]`/`[6b78dab]` FEATURE — **Standalone Phase 2** export path: extract **Compiler** into `Shared/` (DTO); **on‑device name‑linking** (MemoLinking) for export; **ObsidianPublisher** — one‑way, create‑only publish into `<vault>/Skrift/`.
- **2026‑06‑21** `[cdd5f6c]`→`[ebea929]` RELEASE — Audiobook bookmark = folded page corner (dog‑ear): **builds 16, 17, 18**.
- **2026‑06‑22** `[acdb445]` MILESTONE — **Mac→CloudKit design (option A)** locked: a 2nd `NSPersistentCloudKitContainer` client over the SAME `Memo` schema; write‑back via a sidecar `@Model MemoEnhancement`.
- **2026‑06‑22** `[845e6bc]`/`[add6a23]`/`[a2e831a]`/`[74cb609]`/`[fa458df]` MILESTONE — **Mac→CloudKit 8a–8d BUILT**: shared `Memo`/`MemoAsset` model; 2nd CloudKit container; read bridge (Memo→PipelineFile); **write‑back (Mac polish → MemoEnhancement → phone)**; reconcile loop + coexistence + de‑Mac phone Settings. **Device‑verified: 73 phone memos synced down to the Mac.** Gates: mobile 486/486, desktop UnitTests 309/309.
- **2026‑06‑22** `[6642af4]`/`[76e3747]` FIX — Register macOS for CloudKit silent push (32‑byte APNs token verified); pin the local `PipelineFile` store to `cloudKitDatabase: .none` (the entitlement→`.automatic` launch‑crash fix).
- **2026‑06‑22** `[edc4de6]`/`[85d90cd]` RELEASE — Auto‑stop live captions (default 1 min, **build 19**); active‑line bookmark dog‑ear outline (**build 20**).
- **2026‑06‑22** `[OBSIDIAN_EXPORT_ALTERNATIVES.md:8]` DECISION — Obsidian export = **overwrite + edit‑guard back‑off** (DECIDED + BUILT): Skrift updates a note until it detects a vault edit, then adopts the user's version and backs off forever. Privacy reframe same day (`:19‑29`): Skrift's own on‑device reads are fine.
- **2026‑06‑24** `[ffbbff9]`/`[555336c]` FIX — **MP3 audiobooks** rejected as "not a playable audiobook" → `AVURLAsset` built with `AVURLAssetPreferPreciseDurationAndTimingKey`; precise‑timing fix swept across every MP3‑reachable site.
- **2026‑06‑25** `[d24f113]` RELEASE — Bump CFBundleVersion → **build 21** for the MP3‑fix device test *(commit says "19→21"; build 20 already existed — see [§7 #3](#7-contradictions--reconciliations))*.
- **2026‑06‑25** `[950097f]`/`[1fc62b3]`/`[09cee37]` FEATURE — **Phone in‑place name‑linking** in the transcript: 4 tiers + tap‑to‑resolve + person editor + "People in this note" chip bar; per‑note resolution persists on `Memo.nameResolutionsData`. Phone keeps RAW, re‑derives links on demand (same engine as Mac).
- **2026‑06‑26** `[36119bb]`/`[9687c36]` FEATURE — **Phone polished‑text display**: the Mac's `MemoEnhancement` (copy‑edit/title/summary) made VISIBLE on the phone — one editable body that starts from the polish (no toggle), title chooser, summary card, "✦ Polished on your Mac" provenance.
- **2026‑06‑26** `[f4626c0]`/`[7b8d165]`/`[09d4dbd]` RELEASE — **0.2.0 (build 22) — "the iCloud round‑trip release"** (prod promotion): Mac↔phone over iCloud, polished text on phone, on‑device name‑linking, MP3 audiobook fix. (`CHANGELOG.md:8`.)
- **2026‑06‑26** — **Post‑0.2.0 prod findings** triaged (5 issues; see [§3](#3-open-bugs--known-issues)).
- **2026‑06‑27** `[e97ab35]` FEATURE — Add `/handoff` skill.
- **2026‑06‑29** `[553755a]` FIX — **Audiobook chunk‑seam**: ChunkFusion fallback redo‑tail + lead‑in tolerance + 2 regression tests; **macOS CI** workflow added.
- **2026‑06‑29** `[52e7164]`/`[16956e8]` INFRA — **roadmap.yaml = single source**: deleted `ROADMAP.html` + orphaned satellites; live docs point at the **Tiuri Command Center** hub; "How this project is run" onboarding section added across repo CLAUDE.md files. (Post‑0.2.0 prod findings mirrored into `backlog.md` `[f4701de]`; already tracked in [§3](#3-open-bugs--known-issues).)

### Version / build numbers (preserved exactly)
Marketing version was **`0.1.0`** from the first TestFlight build through build 21, then **`0.2.0`** at build 22.

| Build | Date | Commit | Note |
|---|---|---|---|
| 0.1.0 (1) | 2026‑06‑14 | `[518bf58]` | First TestFlight build |
| 2 | 2026‑06‑15 | `[00a4304]` | mic glyph; **also restated in `[95dd058]` same day** |
| ~~3~~ | — | — | **SKIPPED** (no build‑3 commit exists) |
| 0.1.0 (4) | 2026‑06‑17 | `[11ff8a9]` | TestFlight/prod promotion |
| 5 | 2026‑06‑18 | `[c97a89d]` | real version+build in About |
| 0.1.0 (6) | 2026‑06‑18 | `[563820f]` | push + sync indicator |
| 7–12 | 2026‑06‑18 | `[7c783eb]`…`[e16531c]` | audiobook sync slices; (12) = raw‑CloudKit audio |
| 13 | 2026‑06‑19 | `[a9b8502]` | "everything syncs" |
| 14 | 2026‑06‑19 | `[4bcca6e]` | audiobook reading‑mode redesign |
| 15 | 2026‑06‑21 | `[e3e7507]` | append‑path instrumentation (DEV) |
| 16,17,18 | 2026‑06‑21 | `[cdd5f6c]`,`[8b4ec22]`,`[ebea929]` | bookmark dog‑ear evolution |
| 19 | 2026‑06‑22 | `[edc4de6]` | auto‑stop live captions |
| 20 | 2026‑06‑22 | `[85d90cd]` | active‑line bookmark outline |
| 21 | 2026‑06‑25 | `[d24f113]` | MP3‑fix device test |
| **0.2.0 (22)** | 2026‑06‑26 | `[7b8d165]` | **prod — the iCloud round‑trip release** |

---

## 2. Current state — features × {mobile, desktop}

Source of truth = `FEATURES.md` (a live matrix; header says "Generated 2026‑06‑09" but carries inline
updates through 2026‑06‑26), reconciled with `backlog.md` and git. Status legend (`FEATURES.md:9`):
**✅ shipped · 🟡 partial · 🧩 stub · ➖ not present** (by design or not yet). Paths relative to
`Skrift_Native/` (Mobile = `SkriftMobile/`, Desktop = `SkriftDesktop/`).

> **App identity:** two native SwiftUI apps. **Mobile** records, transcribes on‑device (FluidAudio/
> Parakeet on the ANE), captures context + photos, plays audiobooks with quote‑capture, syncs over
> CloudKit (own devices) + Bonjour/HTTP (Mac). **Desktop** is ONE native macOS process: FluidAudio ASR
> + mlx‑swift Gemma enhancement in‑process + a Bonjour/HTTP server + a CloudKit client; it
> transcribes → enhances → name‑links → compiles → exports to Obsidian. No Python, no Electron.

### Recording & live transcription — *mobile‑owned* (`FEATURES.md:16‑31`)
| Capability | Mobile | Desktop |
|---|---|---|
| Record / pause / resume / stop; instant‑record auto‑start | ✅ | ➖ |
| Live caption (auto‑scroll + colour‑by‑confidence, anchored `[photo N]`) | ✅ | ➖ |
| Live‑transcription toggle (battery save) + auto‑stop‑on‑timer (build 19) | ✅ | ➖ |
| Live 40‑bar waveform; model‑preload status; 0.6s caption polling | ✅ | ➖ |
| Audio‑route‑change handling (AirPods pull‑out, cross‑rate tap rebuild) | ✅ | n/a |
| Conversation‑mode toggle (diarize this take) / "Flatten to monologue" | ✅ | ✅ |
| Append to an existing recording (+ button) | ✅ | ➖ |
| Stuck‑transcription + stuck‑diarization launch recovery | ✅ | ➖ |

### Memo detail & playback (mobile) / Review surface (desktop) (`FEATURES.md:33‑48`)
| Capability | Mobile | Desktop |
|---|---|---|
| Editable transcript (self‑sizing native text view, inline images, live `[[link]]` styling) | ✅ | ✅ |
| Karaoke (word highlight + tap‑to‑seek to REAL word time) | ✅ | ✅ |
| Playback bar (Liquid Glass) | ✅ | ✅ |
| Title editor (desktop = Suggested‑vs‑From‑recording chooser) | ✅ | ✅ |
| Significance **circles** (10 tappable, gates sync) | ✅ | ✅ |
| Tags add/remove; copy transcript / delete | ✅ | ✅ |
| Editable summary | n/a | ✅ |
| Speaker turns + name‑a‑speaker | ✅ (inline relabel) | 🟡 (in‑prose popover) |
| Context chips (place/weather/time); horizontal paging between memos | ✅ | ✅ / n/a |

### Memos list (mobile) / Sidebar queue (desktop) (`FEATURES.md:50‑60`)
List/queue ✅/✅ (desktop groups by status); source glyph per row ✅/✅; status pill ✅/✅;
search/sort/filter ✅/✅ (mobile 5 sort modes + date‑range filter; desktop search + Newest/Oldest/Title);
multi‑select + swipe‑delete ✅/✅; **Trash / Recently Deleted (14‑day)** ✅/✅; sync button + banner ✅/n/a.

### Photos during recording (`FEATURES.md:62‑71`)
In‑record camera + zoom + shutter ✅/n/a; front/back flip ✅/n/a; photo‑count badge ✅/n/a;
`[[img_NNN]]` markers in transcript ✅/✅; inline `[photo N]` in live caption ✅/n/a;
`[[img]]` → Obsidian embed on export n/a/✅.

### Models tab & custom vocabulary (`FEATURES.md:73‑87`)
- **Settings → Models** ✅/➖ (Parakeet v3 / diarizer+embedder / CTC 110M, downloaded state + size; manual Download added 2026‑06‑16). Mac mirror = backlog.
- **Custom vocabulary** ✅/✅ — CTC keyword‑spot + rescore (NeMo arXiv:2406.07096); **booster pre‑warm** (the Script→Skrift fix), **aliases** `"Canonical: alias"`, **trust guard** (keep boost only when EVERY replacement is trusted). Per‑device v1 (CloudKit sync added 2026‑06‑18).

### Capture items — share URL/text/image/file (C3 contract) (`FEATURES.md:89‑102`)
C3 wire contract ✅/✅; share extension + sheet ✅/n/a; **share a PDF/document → `.file`** ✅/n/a;
voice dictation in the sheet ✅/n/a; App‑Group inbox → Memo ✅/n/a; capture upload (no audio) ✅/✅;
pipeline skip + enhance‑lite n/a/✅; compile/export n/a/✅; review surface (Mac) n/a/✅; list/detail (phone) ✅/n/a.

### Audiobooks (`FEATURES.md:104‑159`)
- **Library + player** (Bound‑style: import, m4b chapters, resume, speed, sleep, background/lock‑screen transport) ✅/n/a.
- **Text‑first quote capture** (A/B won — audio mark‑in/out arm RETIRED 2026‑06‑13): build‑your‑quote selection ✅; **WAVE 2** whole‑book pre‑transcribe (`BookTranscript` sidecar, `ChunkFusion`, resumable `BookTranscriptionJob`, "Transcribe book" sheet, instant sidecar capture, real per‑device speed) ✅; sample‑accurate chunk extraction (no `AVAssetExportSession` drift).
- **Player text‑forward A+D hybrid** (read‑along Spotify‑lyrics panel, bookmarks, Chapters/Bookmarks sheet) ✅ (build 13).
- **Reading‑mode redesign + tab‑bar IA** (build 14): tab‑bar (Notes·Library·Highlights·Settings), "Importance" relabel, auto‑recede chrome, "Aa" text settings, **bookmark = page‑corner dog‑ear** (builds 16–20), Add‑note chip, sync‑aware delete‑confirm.
- **Quote‑capture pipeline (desktop)**: book metadata contract (C2) ✅/✅; quote protection in enhancement (byte‑identical assert) n/a/✅; quote export `> — [[Author]], *Book*, ch. N` (author at export only, never in names DB) n/a/✅.

### Names & voices — both, synced (`FEATURES.md:161‑168`)
Names list + add/edit/delete ✅/✅; **Names LWW sync (union voiceEmbeddings)** ✅/✅; voiceprint enrollment ✅/✅ (mobile direct "Add voice" bridged 2026‑06‑15); voice match (cosine, **thr 0.5**) ✅/✅.

### Diarization / conversation mode (`FEATURES.md:170‑180`)
Diarize (Sortformer) + fuse to turns ✅/✅ (byte‑identical pipelines); split‑speakers on existing memo ✅/✅;
persist diarization segments ✅/✅; bold speaker turn headers ✅/✅; **turn‑aware conversation name‑linking** ➖/✅
(merge same‑speaker turns; first header → full `[[Canonical]]`, later → short; inline → `[[Canonical|short]]`);
`isAttributed` requires ≥2 distinct speakers; **Re‑transcribe disabled for diarized memos** n/a/✅.

### Sync & contract — the spine (`FEATURES.md:182‑192`)
Significance‑gated upload (flag‑to‑send: only `significance>0`) ✅/✅(reads); multipart upload (RAW, never sanitised) ✅/✅;
**upload word‑timings + diarization sidecars** (additive parts → Mac karaoke + voice‑enroll‑from‑phone) ✅/✅;
diarized transcript marked trusted ✅/✅(honors); names meta/get/put + LWW ✅/✅; Bonjour discover/advertise ✅/✅; health endpoint ✅/✅.

### Internal sync — CloudKit (standalone) (`FEATURES.md:194‑215`)
Memo row sync ✅/➖ (**device‑verified** iPhone↔iPad); media (CKAsset) ✅/➖ (**device‑verified**); sidecars ✅/➖;
names + voices ✅/➖; custom vocab ✅/➖; sync visibility strip ✅/➖; **CloudKit push** ✅/✅; pull‑to‑refresh ✅/n/a;
**per‑book audiobook sync (real %)** ✅/➖. **Mac→CloudKit client** (built 2026‑06‑22): shared `Memo` model ✅/✅;
2nd CloudKit container ➖/✅; read bridge ➖/✅; **write‑back (polish → phone)** ✅(consume)/✅(author); reconcile + coexistence ➖/✅
(**device‑verified: 73 memos synced**); phone de‑Mac Settings ✅/n/a; **phone polished‑text display (Phase 4)** ✅/n/a (built 2026‑06‑26).

### Ingest, transcription, enhancement, export (`FEATURES.md:217‑260`)
- **Ingest:** audio file import ✅/✅; folder/drag‑drop n/a/✅; Apple‑Notes import (+HEIC→JPG) n/a/✅; **video import → audio + 1 frame** ✅/✅; capture items ✅/✅.
- **Transcription engine:** FluidAudio/Parakeet ASR ✅/✅; audio preprocessing (high‑pass + normalize) —/✅; BPE merge / image‑marker injection —/✅.
- **Enhancement (Gemma 4 E4B, mlx‑swift):** copy‑edit/title/summary ➖/✅ (on RAW; summary skipped for short notes); configurable prompts ➖/✅.
- **Name‑linking / tagging / export (desktop):** Sanitiser (alias→`[[Canonical]]`, ambiguity) ➖/✅; **phone in‑place name‑linking** ✅/➖; **opt‑out naming + risk‑tiering** ➖/✅; roster‑collision re‑scan ➖/✅; roster seeding from `People/` titles ➖/✅; review name interaction (3 tiers + popovers) ➖/✅; unlink a `[[Name]]` ➖/✅; names editor ➖/✅; deterministic tags (NLTagger lemma + spoken #) ➖/✅; vault tag scan (app‑only) ➖/✅; compile Obsidian markdown (YAML frontmatter incl. `people:`) ➖/✅; export to vault + copy audio ➖/✅.

### Settings, widgets, metadata (`FEATURES.md:262‑284`)
Settings ✅/✅; first‑run setup ✅(onboarding)/✅(wizard); theme Light/Dark/Auto ✅/✅; auto‑copy transcript ✅/➖;
send feedback (record+type+screenshot→Mail) ✅/➖. **Widgets/intents (mobile):** Live Activity + Dynamic Island ✅;
Start‑recording intent (Siri/Control Center, plain `AppIntent`, glyph `quote.opening` ❝) ✅; **Resume‑audiobook intent** (Siri "Resume my book", `ResumeAudiobookIntent`) ✅ (user‑test owed); Lock/Home record widget · `skrift://record` ✅.
**Metadata/sensors (mobile):** location / weather / day‑period / steps / pressure ✅ (Mac consumes into frontmatter).

> **Feature count:** ~115 capability rows across 25 sections in `FEATURES.md`. Mobile owns recording/
> capture/audiobooks/CloudKit; Desktop owns enhancement/tagging/Obsidian export; Names + diarization +
> the sync contract are shared.

---

## 3. Open bugs / known issues

Sources: `backlog.md` top‑of‑file triage (2026‑06‑26), `WALKTHROUGH_BUGS.md`, the handoffs. Status as of HEAD.

### P0/P1 — post‑0.2.0 prod findings (2026‑06‑26, after promoting to build 22) — OPEN
The single live resume point (`backlog.md:5‑33`):
1. **Phone memo won't sync to Mac; phone stuck "syncing…"** — root: prod **CloudKit PRODUCTION schema never deployed** (all testing was on Dev). Action: CloudKit Dashboard → Deploy Schema Changes (incl. `MemoEnhancement`) + prod Mac `cloudKitMacSync` ON. (`backlog.md:10`)
2. **Stale "Waiting" sync pill** — `Memo.statusKind` keys off Bonjour/HTTP upload state, not CloudKit. (`backlog.md:18`)
3. **Name added on phone not recognised** (e.g. "IJsbrand") — `AddPersonView` saves empty aliases; shared `Sanitiser` matches only by `p.aliases`. Fix: seed alias from name on add. (`backlog.md:22`)
4. **Can't select a word in the transcript and "add as name" on phone** (desktop has it). (`backlog.md:29`)
5. **Desktop shows EVERY note as a conversation; no re‑transcribe button** — ≥2 `**Name:**` headers → "conversation"; investigate stale diarized turn markers baked in. Workaround: right‑click → Re‑transcribe (`SidebarView.swift:527`). (`backlog.md:33`)

### Device‑verify‑owed fixes (fixed in code; not yet eyeballed on hardware) — `[unverified]`
- **P0 append‑transcription** (`backlog.md:216`): "the APPENDED TEXT didn't land" (reframed 3× — see [§7 #4](#7-contradictions--reconciliations)). Logging added (build 15); **owed: device repro + pull `devlog.txt`.**
- **MP3 audiobook** quote‑span export drift + append‑splice offset + `-chunksim` duration (`backlog.md:96‑116`): fixed in the ultracode sweep; **device verify owed** (fixed on Linux, no sim gate).
- **Diarization survives backgrounding** (`backlog.md:157`): keep‑alive + relaunch recovery built 2026‑06‑21; device‑eyeball owed.
- **PDF share persist** (`backlog.md:204`), **auto‑stop captions** (build 19), **bookmark affordances** (builds 16–20): built + unit‑green; device‑eyeball owed.

### Open product/design questions (pinned)
- **Note‑editing EPIC** (`backlog.md:269‑305`, pinned for a fresh chat): text selection doesn't auto‑scroll (editable body is a non‑scrolling `UITextView` inside the outer ScrollView). Recommended fix = option B (natively‑scrolling body), likely B2 (pinned title); start by mocking B1 vs B2. The pin's design thinking (the A/B/C fork + the fork‑independent "experience layer": keyboard accessory toolbar, undo/redo, tag‑chip editor, smart paste + the "must‑not‑break" list) is at `backlog.md:289‑305`.
- **Offline conflict resolution** (`backlog.md:344`): same note edited on both devices = per‑record LWW (one edit can be silently lost). **Scope:** names/voices, vocabulary, and audiobook position all *converge* (re‑merge / whole‑list LWW / newest‑play‑wins) — only same‑note‑body edits are at LWW risk. To verify: `NSPersistentCloudKitContainer` merge granularity. Decide: accept LWW vs "conflicted copy" vs field‑level.
- **Folders model** (`STANDALONE_PLAN.md:576‑577`): app‑native vs Obsidian‑subfolder — user wants to think more; blocks Phase 5 only.
- **Significance → "Importance"/pin label** — needs a label nod before the rest of the de‑Mac reframe.

### Open / owed engineering items (folded in from the 2026‑06‑28 gap audit)
Live action items that sat between §3 and §4. Each verified still‑open against `backlog.md` (items the audit flagged that turned out already‑fixed — names‑auto‑sync‑after‑enroll `:1775`, audiobook rate‑sync `[build 13]`, stuck‑transcription reconciler `[2026‑06‑17]`, the mid‑recording SIGSEGV crash — are deliberately NOT listed).
- **Confirm the "always‑warm" engine isn't draining battery** (`backlog.md:179`): user noticed (prod + dev) the engine is now always warm + much faster + "not really taking battery" — an unexplained behaviour change to **confirm is intentional + measure for silent drain**. P1, open.
- **Mac "name a speaker" review UI** (`backlog.md:1720`): backend done (diarization sidecar + `embedSpeaker`/`addVoiceEmbedding`); the desktop turn‑renderer → click‑to‑name → relabel `**[[Person]]:**` → enroll UI is **the remaining desktop build** (mock signed off). (§2 marks it 🟡.)
- **Paragrapher built but inert** (`backlog.md:430`): `Models/Paragrapher.swift` (hybrid pause + sentence‑cap, 10 tests) is demoed but **not wired into the UI** — decision owed on where to apply (read‑along / memo‑detail / stored+exported) + threshold/cap.
- **FluidAudio pinned to a moving `main` branch** (`backlog.md:419`): both apps pin FluidAudio to `main` → **should pin a fixed version (drift risk)**. Tech‑debt.
- **Audiobook unshare leaves a "phantom" entry** (`backlog.md:347`, #10): un‑sharing leaves an unplayable library entry on a device that got the carrier but never downloaded the audio; deferred fix = GC entries with no carrier AND no local audio.
- **Whole‑book transcribe memory‑pressure lead** (`backlog.md:2116`): `.ips` disk‑write warnings flagged whole‑book transcribe + model downloads as memory‑pressure suspects — a profiling lead, "not a clear fix." *(Note: the acute 2026‑06‑10 mid‑recording SIGSEGV is fixed; this is the remaining pressure lead.)*
- **Capture sentence‑split on abbreviations** (`backlog.md:1948`, suspected/awaiting‑screenshot): "sentence breaks up strangely" in text capture — likely Parakeet punctuation (e.g. "Dr.") tripping `SentenceSnap.isSentenceEnd`. *(Read‑along's split moved to `NLTokenizer(.sentence)` 2026‑06‑15; the capture path may still be affected.)*
- **Polished‑body karaoke is proportional** (`backlog.md:59`): the 2026‑06‑26 phone polished display pins word‑timings to raw words → ⭐ **fast‑follow** to re‑align polished words to raw timestamps for word‑exact scrubbing.

### Deferred / unscheduled backlog (not yet on the phase ledger)
Real items logged in `backlog.md` with no §4 phase home — parked, not lost:
- **Watched‑folder ingest** (`backlog.md:969`) — point Skrift at a folder (e.g. Mac Voice Memos export) for zero‑friction auto‑ingest.
- **Summary‑prompt quality pass** (`backlog.md:970`) — summaries read stale / "not in my voice"; a dedicated prompt‑tuning pass (gated by local‑model quality).
- **Re‑ingest the ~30 old notes** (`backlog.md:1084`) from `~/Desktop/Skrift old notes/` (do with the user — needs prod quit + real vault; also memory `project_port_electron_notes`).
- **In‑app feedback → `backlog.md`** (`backlog.md:1087`) — route dictated/typed feedback into the ledger (phone can't write the repo file → options incl. a scheduled agent).
- **Drag‑to‑multi‑select** memos (`backlog.md:1018`) — Photos/Mail‑style lasso to replace the Select button (wants a mock).
- **Phone Models/Storage management view** (`backlog.md:1096`) + the desktop Models‑tab mirror.
- **Unified source taxonomy** (`backlog.md:2124`) — glyph/label maps are duplicated (`QueueDerivations.swift:61` vs `MemoDisplay.swift:184`), coincidentally in sync, no shared module; PDF/video are not yet first‑class source *types* (the PDF→`.file` capture shipped, build 15, but not the taxonomy type).
- **Backlink Weaver** (`DESKTOP_NATIVE_HANDOFF.md:176`) — auto‑`[[link]]` vault note titles, not just people (gated by length/distinctiveness to avoid over‑linking).

### Desktop walkthrough tracker (`WALKTHROUGH_BUGS.md`)
Legend: `☐ open · ⧖ pending build‑verify · ☑ fixed`. **Still open (☐):** C1 (three green health dots unclear — design call, `:13`); ST7 + E4 (verify prompts/YAML match Electron, `:23`,`:51`). **Pending build‑verify (⧖):** several AUD‑P* polish items + W2 cursor (`:62‑66,:85,:10`). Most of the tracker is ☑.

> **Resolved — do NOT treat as open:** the desktop "A‑list audit nits" (model‑unload dead code, fake/
> proportional karaoke, hardcoded `health=true`, SwiftData off the Bonjour queue, inert preprocessing
> sliders, uncapped upload) were flagged mid‑desktop‑track then **RECONCILED 2026‑06‑13 as already‑fixed**
> (`backlog.md:1728`; desktop A1–A7 all done, `DESKTOP_NATIVE_HANDOFF.md:35`). See [§7 #18](#7-contradictions--reconciliations).

> **Open bug count:** 5 live prod (P0/P1) + ~6 device‑verify‑owed + 4 pinned design questions + ~8 open/owed engineering items (gap‑audit) + ~8 deferred backlog items + ~5 desktop‑tracker items.

---

## 4. Forward roadmap (phase ledger)

Skeleton = the **`roadmap/ROADMAP.html`** node ids (P0–P11, `Mac`, detours D1–D3, history H_mob/H_desk),
enriched from `STANDALONE_PLAN.md` + `MAC_CLOUDKIT_PLAN.md`. Structured fields per phase for 1:1
conversion to `roadmap.yaml`: **`id · title · status · ms · deps · eff · note`**.

- **Status vocabulary** (the YAML target, per the brief): `done | inprogress | now | planned | deferred`.
  ROADMAP.html itself uses `done/inprogress/next/future/deferred` — mapped here **`next`→`now`, `future`→`planned`**.
- **Milestones** (`ms`), left→right, each with its thesis (`ROADMAP.html:263‑268`):
  `Foundation` (done) · `Standalone core` (earliest shippable) · `Differentiator` (worth $0.69) · `Enrichment` (depth) · `Ship` (App Store).
- ⚠️ **ROADMAP.html `LAST_UPDATED = 2026‑06‑21`** and is **stale** vs Era 6 work. The `status` below is the
  **reconciled current** value (with the roadmap's own value noted where it diverges); the ledgers are
  authoritative (`ROADMAP.html:5‑10` update contract). See [§7 #19](#7-contradictions--reconciliations).

### Foundation (done)
- **P0** · Shared naming engine · **done** · ms:Foundation · deps:[] · eff:M
  — One name‑linking engine both apps compile (no drift). Done 2026‑06‑17 `[ea3eeed]`. (`STANDALONE_PLAN.md:161`)
- **P1** · CloudKit sync (your devices) · **done** · ms:Foundation · deps:[P0] · eff:L
  — Memos + media + names + vocab across your own devices, no Mac. Done 2026‑06‑19, **build 13**; device‑verified iPhone↔iPad. (`STANDALONE_PLAN.md:228,466`)

### Standalone core (earliest shippable)
- **P2** · Export & Obsidian publish · **inprogress** *(roadmap: `now`)* · ms:Standalone core · deps:[P0] · eff:L
  — The #1 table‑stakes gap. **Largely BUILT, newer than the roadmap snapshot:** `ObsidianPublisher`
  (one‑way create‑only, overwrite + edit‑guard) DECIDED+BUILT 2026‑06‑22 `[6b78dab]`,
  `OBSIDIAN_EXPORT_ALTERNATIVES.md:8`; on‑device name‑linking `[946c3df]` + Compiler‑to‑Shared `[da9097f]`
  + phone in‑place linking (2026‑06‑25) + phone polished display (2026‑06‑26) all shipped. **Remaining:**
  the split‑note + `skrift-id` hybrid (#6 per‑book aggregation) is a sequenced enhancement.
- **P3** · De‑Mac the UX · **inprogress** · ms:Standalone core · deps:[P1] · eff:M
  — Tab‑bar IA + "Importance" relabel done (build 14); de‑Mac phone Settings done 2026‑06‑22 `[fa458df]`.
  **Remaining:** significance→"Importance"/pin reframe (needs label nod) + standalone onboarding rewrite. (`STANDALONE_PLAN.md:287`)
- **Mac** · Mac rejoins via CloudKit · **inprogress** *(roadmap: `planned`/future)* · ms:Standalone core · deps:[P1,P2,P3] · eff:L
  — **MAJOR divergence from the roadmap:** 8a–8d **BUILT 2026‑06‑22** (`MAC_CLOUDKIT_PLAN.md:12‑40`),
  device‑verified (73 memos synced), shipped in **0.2.0**. **Owed:** one Process→write‑back→phone‑export
  round‑trip eyeball + prod CloudKit schema deploy + Release App‑ID iCloud/Push registration.

### Differentiator (worth $0.69)
- **P4** · On‑device Polish · **planned** *(risk)* · ms:Differentiator · deps:[P0] · eff:L
  — Cleanup/title/summary on‑device. **Longest pole; the spike is the gate** (`P4a`). Ideas: P4a spike on
  iPhone 13 FIRST (hard memory gate: zero jetsam + ≥300 MB headroom), P4b adaptive engine (A=Apple FM /
  B=Mac offload / C=bundled small MLX / D=no‑polish), P4c "Clean up my ramble" presets, P4d device‑gated
  Models picker. Ships no‑polish if the spike fails. (`STANDALONE_PLAN.md:307`) **⚠ Note:** the commit
  "STANDALONE Phase 4" (`[36119bb]`, phone polished‑display) is NOT this P4 — it's the Mac‑CloudKit
  display arc; the label collides. See [§7 #22](#7-contradictions--reconciliations).
- **P6** · Commonplace Book + quote cards · **planned** · ms:Differentiator · deps:[P2] · eff:L
  — Highlights feed + Daily Review + shareable quote cards (`ImageRenderer`). The headline + App‑Store marketing. Ideas P6a–P6e. (`STANDALONE_PLAN.md:355`)

### Enrichment (depth)
- **P5** · Organization · **planned** · ms:Enrichment · deps:[P3] · eff:M — Pins, nested tags, smart folders. (**Folders model is an open decision — don't build until decided.**) Ideas P5a–P5d. (`STANDALONE_PLAN.md:349`)
- **P7** · People & backlinks · **planned** · ms:Enrichment · deps:[P0] · eff:M — Person pages, linked/unlinked mentions. Near‑free given the Sanitiser substrate. Ideas P7a–P7b. (`STANDALONE_PLAN.md:365`)
- **P8** · Journal / On‑This‑Day / search · **planned** · ms:Enrichment · deps:[P1] · eff:L — On This Day, map, calendar, semantic "Related notes" (on‑device `NLContextualEmbedding`). The north‑star backbone. Ideas P8a–P8d. (`STANDALONE_PLAN.md:370`)
- **P9b** · Audiobook player polish · **planned** · ms:Enrichment · deps:[D3] · eff:M — Sleep timer, clips, annotatable bookmarks, skip‑silence — after the reading‑mode redesign. Ideas P9b1–P9b6. (`STANDALONE_PLAN.md:375`) *(No `P9a` node — D1–D3 are effectively that work; see [§7 #25](#7-contradictions--reconciliations).)*

### Ship (App Store)
- **P11** · App Store readiness · **planned** · ms:Ship · deps:[P2,P3] · eff:M — Price tier $0.69/no IAP, privacy nutrition label, onboarding rewrite, screenshots, review prep (keep plain `AppIntent`). Ideas P11a–P11e. (`STANDALONE_PLAN.md:394`)
- **P10** · Apple Watch capture · **deferred** · ms:Ship · deps:[P1] · eff:L — Fast‑follow, own target + review. (User has no Watch.) Ideas P10a–P10b. (`STANDALONE_PLAN.md:389,573`)

### Detours (done) — "Audiobook deep‑dive" (Jun 18–19, branched from P1, merged to P2)
- **D1** · Per‑book audiobook sync + real % · **done** (Jun 19) — raw‑CloudKit CKAsset transfer + size sheet.
- **D2** · Everything syncs · **done** (Jun 19, deps:[D1]) — cover + read‑along transcript + position + speed.
- **D3** · Player reading‑mode redesign · **done** (Jun 19, deps:[D2]) — **build 14**: tab‑bar IA, reading mode, Aa settings, dog‑ear bookmarks.

### History (the spine's far‑left convergence)
- **H_mob** · mobile‑native · **done** — native SwiftUI iOS rewrite (was React Native) → merges to P0.
- **H_desk** · desktop‑native · **done** — native SwiftUI macOS rewrite (was Electron + Python); converged → `native` → `main`, Jun 7–8 → merges to P0.

> **Phase count:** 12 phases (P0–P11, minus P9a) + the `Mac` phase + 3 detours + 2 history nodes = **18 nodes**.
> `roadmap/HISTORY_BACKFILL.md` stages eras 1–5 (genesis → RN) as future left‑extensions of the HISTORY array — **not yet built into the viz.**

---

## 5. Key decisions & rationale

Each with the doc that records it. (Locked = don't re‑litigate.)

### Architecture & strategy
- **Native SwiftUI rewrite of both apps** (drop Electron + Python + React Native). Rationale: one native engine, true native feel, cross‑app features land atomically; Gemma proven to run natively via mlx‑swift (no Python sidecar, `[aa71b85]`). Desktop chose **Option A (full rebuild)**, rejected Option B (reuse React UI in WKWebView) — the real cost of B was re‑implementing `window.electronAPI` natively (`DESKTOP_NATIVE_HANDOFF.md:236,241`).
- **Standalone App Store direction** (2026‑06‑15): ship SkriftMobile with **no Mac required**. **$0.69 one‑time, NO IAP** → no recurring revenue → can't afford per‑use cloud LLM → all intelligence on‑device/free‑Apple, which *is* the privacy story (tradeoff: no free trial). **Full vision for v1.** **Three coexisting modes** (standalone / +Obsidian / paired‑with‑Mac) over **one source of truth**; Mac + Obsidian = optional output sinks. **Min iOS = 26.** (`STANDALONE_PLAN.md:26‑41,571`)
- **Internal sync = CloudKit (SwiftData CloudKit mode), NOT iCloud‑Drive** — reliable cross‑device with no `filename 2.md` conflict copies. (`STANDALONE_PLAN.md:34`)
- **Mac rejoins as a CloudKit client (option A / Fork A):** a 2nd `NSPersistentCloudKitContainer` over the SAME `Memo` schema (vs a hand‑rolled CKRecord bridge) — inherits conflict handling, CKAsset, schema evolution for free. **Write‑back = W2 (sidecar `@Model MemoEnhancement`)** vs W1 (fields on `Memo`) — keeps `Memo.transcript` sacrosanct (RAW = source of truth); the phone's `MemoExporter` prefers it → a paired Mac auto‑upgrades the phone's Obsidian export. Opt‑in `cloudKitMacSync` (OFF by default). (`MAC_CLOUDKIT_PLAN.md:117‑189`)

### The naming model (re‑derived 2026‑06‑16, `NAMING_MODEL.md`)
- **Two separable jobs:** **normalisation** (names spelled right everywhere, even unlinked) + **linking** (only subjects a note is *about* become a graph edge). (`NAMING_MODEL.md:20‑24`)
- **Default = OPT‑OUT + risk‑tiered auto‑write.** Rationale (load‑bearing): in a 50‑year archive a missed link is unrecoverable, a stray link is a 2‑second prune — the asymmetry points one way. Auto‑commit a full/distinctive name; dotted‑**suggest** a common‑word or ambiguous (2+ roster) name; leave plain a stoplisted word. **This is the one place Skrift diverges from every other tool — it auto‑*writes* links, not just suggests.** (`NAMING_MODEL.md:42‑60`) **SUPERSEDES** the earlier opt‑in model (built then largely deleted).
- **Recognition = KNOWN‑ROSTER ONLY, no NER/no LLM, pure deterministic string‑match** (must be portable to the phone). Roster seeded from `People/*.md` filenames (app code, no AI, never reads note bodies). Matcher kept STRICT (whole‑word + capitalization, no edit‑distance). (`NAMING_MODEL.md:61‑81`)
- **One inline body link per subject (first mention)** + `people:` frontmatter (durable + queryable). Alias display `[[Canonical|spoken]]`. Quote protection skips YAML/code/audiobook‑quote spans. **KILL the per‑occurrence resolver + chip bar** (ambiguity = note‑level pick + per‑mention override; two genuinely‑different same‑named subjects in one memo is vanishingly rare). (`NAMING_MODEL.md:31‑41,91‑97,181‑184`)
- **NO on‑device name‑linking sent to the Mac** — the phone links for its OWN display/export AND sends RAW; the Mac re‑links identically via shared code + synced names. No double‑link, no skip‑signal. (`STANDALONE_PLAN.md:273‑280`, `MOBILE_NATIVE_HANDOFF.md:82‑88`)

### Conversation / voice identity (`CONVERSATION_MODE_HANDOFF.md`)
- **Diarization = Sortformer on both apps** (not the legacy `DiarizerManager`, which mislabels similar voices). **Identification = a separate embedding‑cosine** (wespeaker `[Float]` voiceprint vs `Person.voiceEmbeddings`). **Threshold 0.5** (measured). The embedding is what syncs (bidirectional LWW, **union** voiceEmbeddings). (`CONVERSATION_MODE_HANDOFF.md:131‑135,28‑30`)
- **Conversation mode = manual toggle, off by default** (was a blunt global auto‑diarize that over‑split monologues); "Flatten to monologue" added. (`backlog.md`, `[bc0b5b5]`)

### Product north star (the "why")
- **"See how my thinking evolved over time"** (`backlog.md:722`) — the stated eventual reason the app exists: semantic search across the whole multi‑year archive + ranked related notes + a timeline UI ("you had a similar thought in 2019…"). The backbone (on‑device embeddings + retrieval) is buildable **now/offline** and is staged as roadmap **P8**; **LLM *narration* of the evolution is deferred** until local models are good enough (the same ceiling as the stale‑summary problem). Skrift is the capture+processing front‑end feeding this, not a replacement for Obsidian.

### Product behaviours
- **Significance is a user‑set value (not LLM), and it gates phone→Mac sync** (flag‑to‑send: 0 = stays on phone, >0 = eligible to sync). CloudKit (own devices) ignores significance — every memo syncs to your own devices. (`backlog.md:996`, `STANDALONE_PLAN.md:582‑593`)
- **Tags are deterministic** (NLTagger lemma match ≥2× + spoken `#hashtags`), not LLM. **Enhancement runs on the RAW transcript** (no `[[ ]]` reaches the LLM). (Era‑1 overhaul decisions that persist; `archive/CLAUDE-electron-python.md:85,207`)
- **Post‑record flow = save‑now → Memo detail** (no Review screen). **Transcript always editable** (no Edit button); **Re‑transcribe removed**. (`MOBILE_NATIVE_HANDOFF.md:362,508`)
- **App Intents = plain `AppIntent` + `openAppWhenRun`**, never `AudioRecordingIntent` (that SIGTRAP'd in Shhhcribble). Device‑verified safe. (`MOBILE_NATIVE_HANDOFF.md:434‑437`)
- **Obsidian export = one‑way, create‑only, overwrite + edit‑guard back‑off** (option #1 + the safe core of #4): write until a vault edit is detected, then adopt the user's version and back off. (`OBSIDIAN_EXPORT_ALTERNATIVES.md:8‑17`)
- **Audiobook quote‑capture:** Skrift IS the player (model on Bound); one memo per capture; **text‑first capture is the only flow** (audio mark‑in/out arm retired); quote audio = the captured span; `[[Author]]` at export only; enhancement protects the quote byte‑identically. (`backlog.md:1219,2039`)

### Durable engineering gotchas (learned the hard way)
- **Detached Task, NOT semaphore‑on‑main** (desktop): FluidAudio ASR posts completion to main, so a semaphore‑on‑main deadlocks at inference. (`DESKTOP_NATIVE_HANDOFF.md:267`)
- **Chunk time‑drift:** `AVAssetExportSession` on compressed audio drifts word‑times late (grows with seek) → use sample‑accurate `AVAudioFile` frame reads. (`backlog.md`, memory `project_audiobook_player`)
- **SwiftData traps on Codable‑struct `@Model` attributes** on read‑back → persist as JSON `Data?` blobs (`Memo.metadata`, `PipelineFile.audioMetadata`). (`DESKTOP_NATIVE_HANDOFF.md:225`)
- **CloudKit + `@Attribute(.unique)`** is forbidden → drop unique on `Memo.id`; pin any local store under an entitled app to `cloudKitDatabase: .none` (default `.automatic` silently flips CloudKit ON → launch fatalError). (`MAC_CLOUDKIT_PLAN.md:46‑52`)
- **ATS `NSAllowsLocalNetworking` + Bonjour‑resolve‑to‑IPv4** unblocked the phone→Mac LAN upload. (`MOBILE_NATIVE_HANDOFF.md:370‑372`)
- **Build with the xcodebuild UDID `00008110-001208C902EA201E`** (not the devicectl id) or installs push a STALE binary. (memory `feedback_device_build_udid`)
- **Desktop CLI build needs `-skipMacroValidation`**; only `xcodebuild` (not `swift build`) compiles MLX's `.metallib`. (`DESKTOP_NATIVE_HANDOFF.md:226`)
- **Liquid Glass needs `.glassEffect(.clear)`** (not `.regular`, which frosts); **Reduce Motion ON throttles it on A15**; the **Simulator never renders specular/chromatic glass** → judge glass on‑device only. (`backlog.md:1005`)
- **Never run two "Skrift Dev" instances** — they race port 8000 + the shared SwiftData store (broke sync 2026‑06‑15); deploy desktop as build → `pkill` → `ditto` → `open`. (`backlog.md:920`, memory `feedback_desktop_dev_deploy`)

---

## 6. The contracts (wire specs)

### Mobile↔Mac upload (the spine) — multipart `POST /api/files/upload`
- Phone sends the **RAW transcript** + `confidence` / `transcriptUserEdited` / `transcriptMarkersInjected` / `imageManifest` / metadata / optional `title`; **NEVER `sanitised`**. Optional additive parts: `wt_<id>.json` (word‑timings → Mac karaoke) + `diar_<id>.json` (diarization → voice‑enroll‑from‑phone). (`FEATURES.md:187‑189`, `CAPTURE_CONTRACT.md:142`)
- **Trust = `transcriptUserEdited || transcriptConfidence ≥ 0.7`** → Mac sets `steps.transcribe=done` and runs its own name‑linking. A phone‑diarized conversation sets `transcriptUserEdited=true` so the Mac trusts its `**Name:**` turns regardless of confidence. (current `CLAUDE.md`; `FEATURES.md:189`)
- **Significance‑gated:** only `significance > 0` uploads (flag‑to‑send). (`FEATURES.md:186`)

### Names sync (LWW)
`GET /api/names/meta` (tiny `{lastModifiedAt}`) → `GET /api/names` (full incl. tombstones) → **LWW merge per canonical, UNION voiceEmbeddings** → `PUT /api/names`. `names.json`: per‑entry `lastModifiedAt`, `deleted` tombstones pruned after 90 days. Byte‑compatible across both apps + the CloudKit `NamesRecord` carrier. (current `CLAUDE.md`; `FEATURES.md:166,203`; `CONVERSATION_MODE_HANDOFF.md:100‑103`)

### Capture items — C3 contract (`Skrift_Native/CAPTURE_CONTRACT.md`)
A capture = something shared in (URL / text / image / file) + optional annotation + significance. **No audio, no transcription.** **Discriminator: zero audio `files` parts + `metadata.sharedContent` present.** Phone‑side = a `Memo` with `audioFilename == ""`; Mac‑side = a `PipelineFile` with `sourceType == .capture`. `sharedContent` keys: `type` ("url"|"text"|"image"|"file"), `url`, `urlTitle` (no network fetch), `text`, `fileName`, `mimeType`. Image capture adds one `images` part + `imageManifest`. Desktop pipeline: skip ASR/diarize, **enhance‑lite** (title+tags+summary, no body copy‑edit), name‑link runs; export pins a shared block above the body + `source: capture-url|text|image` frontmatter. Additive + byte‑identical for memo uploads. (`CAPTURE_CONTRACT.md:13‑144`)

### Book metadata — C2 (additive)
`bookTitle`/`bookAuthor`/`bookChapter` ride `UploadPayload`/`MemoMetadata`; quote export `> — [[Author]], *Book*, ch. N`; absent = old behaviour. (`FEATURES.md:157‑159`)

### CloudKit (internal, device↔device)
SwiftData CloudKit mode mirrors the store to the user's PRIVATE database: `Memo` rows + `MemoAsset` (media/sidecars → CKAsset for >~1 MB) + `NamesRecord` + `VocabularyRecord` carriers + audiobook `AudiobookSyncRecord` (state) / raw‑CloudKit `AudiobookAudio` (audio, determinate %). Silent push drives prompt sync. The Mac is a 2nd client over `[Memo, MemoAsset, MemoEnhancement]` in container `iCloud.com.skrift.mobile{.dev}`, separate from its local `PipelineFile` store. (`FEATURES.md:194‑215`, `MAC_CLOUDKIT_PLAN.md`)

---

## 7. Contradictions & reconciliations

Every place the inputs disagree, with the value treated as **authoritative** (newest/most‑specific wins; the ledgers beat generated views and stale checkboxes).

1. **Build 3 skipped.** No commit references build 3; the sequence jumps build 2 (06‑15) → build 4 (06‑17, `[11ff8a9]`). **Authoritative: build 3 was never cut in git** (likely an intentional skip). Not an error — a gap.
2. **Two "build 2" commits same day** (`[00a4304]` + `[95dd058]`, both 2026‑06‑15). The second (STANDALONE baseline) restates build 2 rather than bumping. **Authoritative: one build 2.**
3. **Build 21 message "19→21"** (`[d24f113]`) but build 20 (`[85d90cd]`) already existed. **Authoritative: the resulting value 21 is unambiguous;** the "from 19" is a loose commit message (the edited plist may have lagged build 20).
4. **The P0 data‑loss bug — 3 reframings** (`backlog.md:132 → :140 → :216`): "append deletes the whole note" → "MemoSaver exonerated, suspect CloudKit deletion" → **"REFRAMED: NOT a deletion — the APPENDED TEXT didn't land."** **Authoritative = the newest (`:216`):** an append‑transcription path bug, still OPEN pending device repro.
5. **Naming model: opt‑in → opt‑out.** Opt‑in model LOCKED + chunks 1–5 BUILT 2026‑06‑15 (`backlog.md:752,771`), then **flipped to opt‑out 2026‑06‑16** and the opt‑in chunks largely **deleted** (`backlog.md:810`, `NAMING_MODEL.md:3‑7`). **Authoritative = opt‑out (`NAMING_MODEL.md`).**
6. **Audio mark‑in/out capture arm — built then retired.** Hybrid audio capture signed off (`backlog.md:1504`), then text‑first added alongside (`:1812`), then **2026‑06‑13 the audio arm was retired — text capture is the only flow** (`:2039`). **Authoritative = text‑only.**
7. **Bookmarks — decided‑against then built.** "DECIDED AGAINST" 2026‑06‑12 (`backlog.md:1261`) → **BUILT 2026‑06‑13** (`:1915`, the player redesign reversed it). **Authoritative = built.**
8. **Whole‑book indexing — rejected then built.** "Explicitly REJECTED" (`backlog.md:1362`) → **WAVE 2 whole‑book pre‑transcribe built** (`:1830`). Different framing (on‑demand span vs read‑along pre‑transcribe) but the literal stance reversed. **Authoritative = built (WAVE 2).**
9. **Mobile Phase 9 status.** `MOBILE_NATIVE_REWRITE_PLAN.md:348` leaves it unchecked; `MOBILE_NATIVE_HANDOFF.md:454‑527` says **parity sweep done, retirement deferred** (user keeps the old apps operational). **Authoritative = HANDOFF.**
10. **Desktop Phase 7/8 status.** `DESKTOP_NATIVE_REWRITE_PLAN.md:229‑230` shows `[ ]`; `DESKTOP_NATIVE_HANDOFF.md:26,106‑122` + commits show both BUILT. **Authoritative = HANDOFF + commits** (the PLAN checklist wasn't re‑ticked).
11. **Branch `standalone` vs `main`.** `STANDALONE_PLAN.md:8,614` names branch `standalone`; the same file's later RESUME notes + `MAC_CLOUDKIT_PLAN.md:12` + git say work landed on **`main`**. **Authoritative = `main`** (the repo's actual branch).
12. **STANDALONE Phase 1c device‑verify.** `:519` says "✅ DEVICE‑VERIFIED 2026‑06‑18"; the handoff block `:528‑534` still lists it as an outstanding user task. **Authoritative = done (`:519`).**
13. **"Mac never pushes polished text back to the phone" — now obsolete.** `STANDALONE_PLAN.md:337‑342` states this as fact + defers it; **`MAC_CLOUDKIT_PLAN.md` (newer, 2026‑06‑22) BUILT exactly that** (W2 write‑back). **Authoritative = newer (built).**
14. **Text‑capture WAVE 2 — to‑build vs built.** `TEXT_CAPTURE_WAVE2_HANDOFF.md:22` is a pre‑build prompt ("NO whole‑book pre‑transcribe yet — that's this task"); the ledgers + `FEATURES.md:112‑119` say **BUILT 2026‑06‑13/15**. **Authoritative = built** (the handoff is a snapshot).
15. **`NAMING_MODEL.md` header "Mock next, then build" vs 5 chunks DONE** same day (`:7` vs `:233‑288`). **Authoritative = built.**
16. **Bonjour: primary vs fallback.** `CAPTURE_CONTRACT.md`/`NEXT_CHAT_HANDOFF.md` present LAN upload as THE sync path; `CHANGELOG.md:39‑44` (0.2.0) demotes it: **iCloud is primary, Bonjour is opt‑in fallback.** Version evolution — **authoritative = 0.2.0 (iCloud primary).**
17. **Min iOS 26 vs Phase‑4 "no min‑target bump."** Decision #4 locks min iOS = 26 (`STANDALONE_PLAN.md:571`); the Phase‑4 prose says FM is `#available(iOS 26)` "no forced min‑target bump" (`:139`). Wording drift, not a hard conflict — **authoritative = min iOS 26** (newer decision).
18. **Desktop "A‑list audit nits" — open vs fixed.** Listed as open mid‑desktop‑track (`backlog.md:1462‑1473`), then **RECONCILED as already‑fixed 2026‑06‑13** (`:1728`; A1–A7 done, `DESKTOP_NATIVE_HANDOFF.md:35`). **Authoritative = fixed — do NOT carry as open bugs.**
19. **`roadmap/ROADMAP.html` (LAST_UPDATED 2026‑06‑21) is stale.** It shows P2=`next`, the `Mac` phase=`future`; reality (Era 6): the Mac phase is BUILT (8a–8d, 0.2.0) and P2 is largely built. **Authoritative = the markdown ledgers + git** (the roadmap is a generated view; its own update contract says so).
20. **Video thumbnail "doesn't squish" → "portrait distortion is real."** Initial landscape‑only investigation (`backlog.md:551`) was corrected after a device eyeball (`:539`); fixed. **Authoritative = the correction.**
21. **ASR mel‑chunk‑context "revert" → toggle.** First pass concluded "revert" from one English clip (`backlog.md:407`); a Dutch A/B showed mel‑off wins on non‑English (`:410`) → resolved as a Settings toggle (default English = mel‑on). **Authoritative = the toggle.**
22. **"STANDALONE Phase 4" label collision.** Commit `[36119bb]` "STANDALONE Phase 4" = phone polished‑text display (part of the Mac‑CloudKit/de‑Mac arc), but `STANDALONE_PLAN.md` Phase 4 = **On‑device Polish (gated spike)**. **The two "Phase 4"s are different work.** Flagged so the roadmap YAML doesn't conflate them.
23. **Parakeet download (archive).** `archive/legacy-root/README.md:42` says "auto‑downloads"; `archive/CLAUDE-electron-python.md:83` says "local only, never downloads." **Authoritative for the late old‑era desktop = CLAUDE‑doc (local‑only);** mobile DID download ~600 MB.
24. **Roadmap status vocabulary.** ROADMAP.html uses `next`/`future`; the brief's YAML target uses `now`/`planned`. **Mapped** `next→now`, `future→planned` in [§4](#4-forward-roadmap-phase-ledger).
25. **No `P9a` node.** ROADMAP.html has only `P9b`; the already‑shipped audiobook reading‑mode work is detours **D1–D3**. The YAML should decide whether to model `P9a` or treat D1–D3 as it.
26. **Project age `[unverified]`.** User recalls "2 years+"; git floors at 2025‑10‑18; no in‑repo artifacts predate mid‑2025. **Unresolved — needs the user** (`HISTORY_BACKFILL.md:54‑56`).

---

## 8. Provenance / source map

What each input contributed, and which are **superseded** (safe to ignore for current state / archive).

> **Doc locations (2026‑07‑01 root cleanup):** the cited handoffs/plans now live in **`archive/handoffs/`**, and the one‑shot prompts + testing log in **`archive/`**. Every bare `Filename.md:line` citation in this doc resolves there. Root now keeps only the live set: `README.md`, `CLAUDE.md`, this file, `roadmap/`, `backlog.md`, `FEATURES.md`, `CHANGELOG.md`, `STANDALONE_PLAN.md`, `NAMING_MODEL.md`.

### Primary ledgers (LIVE — keep)
- **`backlog.md`** (2137 lines, reverse‑chronological) — THE working ledger: every feature decision, device‑test verdict, bug status, "CONTINUE HERE." Contributed: §3 open bugs, most of §5 decisions, the contradiction set. **The single live resume point is its top block (post‑0.2.0 triage, 2026‑06‑26).**
- **`FEATURES.md`** (293 lines) — the feature matrix. Contributed: all of §2. Authoritative for "what exists and where today."
- **`CHANGELOG.md`** (86 lines) — curated releases (0.1.0, 0.2.0). Contributed: release entries + the 0.2.0 ship list.

### Plans / handoffs (root: `STANDALONE_PLAN.md`, `NAMING_MODEL.md`; rest → `archive/handoffs/`)
- **`STANDALONE_PLAN.md`** (621) — the App Store direction; phases, locked decisions, device/LLM matrix. Contributed: §4 roadmap, §5 strategy.
- **`MAC_CLOUDKIT_PLAN.md`** (268) — the Mac↔CloudKit feature (8a–8d, BUILT 2026‑06‑22). Contributed: §4 `Mac` phase, §5 write‑back decision, §6 CloudKit.
- **`NAMING_MODEL.md`** (295) — the re‑derived opt‑out naming model (LOCKED 2026‑06‑16). Contributed: §5 naming.
- **`CONVERSATION_MODE_HANDOFF.md`** (286) — diarization + voice identity (Sortformer + embedding‑cosine, thr 0.5). Contributed: §5 conversation.
- **`OBSIDIAN_EXPORT_ALTERNATIVES.md`** (2026‑06‑22) — export approach (overwrite + edit‑guard) + the privacy reframe. Contributed: §5 export, the privacy clarification.
- **`Skrift_Native/CAPTURE_CONTRACT.md`** (C3) — the capture‑items wire spec. Contributed: §6.
- **`MOBILE_NATIVE_HANDOFF.md`** (922) / **`DESKTOP_NATIVE_HANDOFF.md`** (284) — full session ledgers. Contributed: Era 3–4 timeline, device‑verified findings, several decisions. **Newer than their PLAN siblings on status.**
- **`WALKTHROUGH_BUGS.md`** (85) — desktop bug tracker. Contributed: §3 desktop‑tracker items.

### Generated views / staging (keep, but NOT authoritative for status)
- **`roadmap/ROADMAP.html`** (+ `README.md`) — the interactive metro‑tree; a **generated view** whose `LAST_UPDATED 2026‑06‑21` is stale (see [§7 #19](#7-contradictions--reconciliations)). Contributed: §4 node ids/structure. **Source of truth = the markdown ledgers.**
- **`roadmap/HISTORY_BACKFILL.md`** — staged history eras 1–5 (research, NOT built into the viz). Contributed: Era 0–1 narrative + the `[unverified]` age note.

### Superseded snapshots (safe to treat as historical; don't mine for current status)
- **`MOBILE_NATIVE_REWRITE_PLAN.md`** (348) / **`DESKTOP_NATIVE_REWRITE_PLAN.md`** (231) — phase plans; **superseded by their HANDOFF siblings** on status (unchecked boxes that are actually done). Keep for the phase‑plan rationale.
- **`TEXT_CAPTURE_WAVE2_HANDOFF.md`** (74) — a **pre‑build prompt**; WAVE 2 is built (see [§7 #14](#7-contradictions--reconciliations)). **Superseded — safe to archive.**
- **`NEXT_CHAT_HANDOFF.md`** (87) — a 2026‑06‑14 session handoff; its content is folded into `backlog.md` + this doc. **Superseded — safe to archive.**
- **`Skrift_Native/SkriftDesktop/mocks/text-capture-DESIGN.md`** — signed‑off design spec; built. Keep as a spec reference; not a status source.
- **`archive/**`** — the **Electron + Python + React Native** era (Era 1–2): `CLAUDE-electron-python.md`, `legacy-root/{API_REFERENCE,BACKEND_MAP,HANDOFF,MOBILE_OVERHAUL_PLAN,README}.md`, `Mobile/`, `backend/`, `frontend-new/`. **Entirely superseded;** placed on the timeline (Era 1–2), preserved intact for reference. `BACKEND_MAP.md` is itself self‑labelled pre‑Parakeet (an even‑earlier sub‑layer).

### Other docs found in‑repo (not consumed as status sources)
`AUDIOBOOK_REDESIGN_PROMPT.md`, `CONVERSATION_BUGHUNT_PROMPT.md`, `ROADMAP_VIZ_PROMPT.md`,
`TESTING_2026-06-09.md` — prompts + a testing log (now in `archive/`); their outcomes are captured in `backlog.md`/git.
The `.claude/skills/*/SKILL.md` and `mocks/*.html` are build artifacts / process tooling — **excluded from current state** per the brief.

### `[unverified]` items (flagged, not asserted)
- **Pre‑2025‑10‑18 history** — no in‑repo artifacts; needs the user (`HISTORY_BACKFILL.md:54`).
- **iPhone 13 RAM variant (4 vs 6 GB)** for the Polish spike gate — `STANDALONE_PLAN.md` flags "confirm."
- **Device‑eyeball‑owed behaviours** (can't be falsified by sim/source, per the user's verification rule): phone voice auto‑match; read‑along `lead` tune + player screens 3–7; raw‑CloudKit audiobook audio round‑trip; the Mac↔CloudKit one‑Process→write‑back→phone‑export round‑trip; the device‑verify‑owed fixes in [§3](#3-open-bugs--known-issues). Marked "owed/unverified" wherever they appear.

---

### How to keep this waterproof (tiering rule)
This doc is a **source‑of‑truth *index*** — authoritative for every distinct fact, with the *depth*
living in the cited docs (`backlog.md:line`, the handoffs, the plans). That makes it a **two‑tier**
system:
- **Top tier = this doc.** The live layer (§3 open bugs, §4 in‑progress roadmap, §5 current decisions) is
  written to be **self‑contained** — actionable without opening the backlog. History (§1) and depth stay
  distilled‑with‑citations.
- **Archive tier = the ~20 cited source docs.** They are a **frozen deep tier — kept, not edited or pruned.**
  The index's citations are **line‑number anchors**: if `backlog.md` (or any cited doc) is reorganized or
  truncated, those line numbers **rot**. So either treat the cited docs as append‑only/frozen, or re‑run the
  extraction + gap audit and refresh the citations. Do **not** silently renumber a cited doc.
- **Don't inflate the index.** A fatter SSOT just recreates the fragmentation it replaced. Add a fact only
  when it's a distinct feature/bug/decision/release/contradiction; push detail down to the cited tier.

*End of Skrift Single Source of Truth. Update contract: when a feature, bug, decision, release, or
phase changes, update the relevant ledger (`backlog.md`/`FEATURES.md`/`CHANGELOG.md`/the plans) AND
this doc in the same pass; the roadmap viz is a generated view of §4.*
