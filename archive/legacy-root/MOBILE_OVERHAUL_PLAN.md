# Skrift Mobile Overhaul — Plan (research handoff)

> Companion to the desktop `HANDOFF.md` (desktop overhaul = done, Phases 1–6, on branch `overhaul`). This doc plans the **mobile app** (`Mobile/`) overhaul: re-sync it to the desktop's new pipeline + add the three planned features. **This is a plan, not done work — a fresh chat will implement it.** Research completed 2026-06-05; nothing in `Mobile/` has been changed yet.

## 0. Orient first — WHY + scope + rules

**The app:** Skrift = macOS voice-note → Obsidian, with a companion **iOS app** (Expo SDK 54, expo-router) that records, runs **Parakeet on-device** (FluidAudio + ANE), captures metadata/photos, and **syncs to the Mac**, sharing the Mac's names database. The desktop half was just overhauled (new pipeline + review UX). The mobile app has **drifted out of sync** with that and is **missing three planned features**.

**Scope of this overhaul:** (1) re-sync mobile to the desktop's new contract/philosophy, (2) implement the 3 features in `skrift-session-decisions.md` (on-device tag matching, FluidAudio word boosting, speaker diarization + voice profiles), (3) cut dead code / fix bugs. **Refactor, don't rebuild. Stay Expo.**

**Read before implementing:**
- `Mobile/CLAUDE.md` (mobile architecture), `CLAUDE.md` (desktop — already reflects the NEW pipeline).
- `/Users/tiurihartog/Downloads/skrift-session-decisions.md` — the locked decisions for the 3 features (lemma pre-expansion, frequency gate, spoken-hashtag commit, CTC boost of the *unusual* subset, multi-embedding-not-averaged voice profiles, `voiceEmbeddings` in `names.json`). **Read it fully; the "why" matters.**
- `HANDOFF.md` (desktop state), and §1 below.

**Hard rules (same as the desktop overhaul):**
- **PRIVACY:** never point AI/agents at the user's Obsidian vault. App code only. Test with a small sample the user provides.
- **Keep it SIMPLE.** Don't over-engineer; the user pushed back hard on that before. Suggestions-only for tags (never auto-commit), etc.
- **Bring the user along:** explain in plain terms, confirm before anything big. The user is highly visual + iterative — for UI, mock/show before building (see memory `feedback_visual_ui_iteration`).
- **Verify every chunk + commit each logical chunk.** Mobile verification is harder (no headless browser): use the iOS **Simulator** (dev account pending → device testing limited), `tsc`/expo type-check, and `npm install --legacy-peer-deps`. Confirm the **upload contract round-trips against the running Mac backend** (the real integration test).
- **Everything must talk to each other:** the mobile↔Mac contracts (upload trust, names sync, tag whitelist) are the spine — keep them in lockstep.

## 1. Current mobile state (verified) + match/mismatch vs the new desktop

| Area | Mobile does | vs desktop |
|---|---|---|
| **Transcription** (`modules/parakeet/ios/ParakeetModule.swift`, `lib/transcribe.ts`) | Parakeet TDT v3 on ANE; returns `{text, confidence, durationMs, wordTimings, markersInjected}`; injects `[[img_NNN]]` photo markers on-device (mirrors Mac `_insert_image_markers`). | ✅ **Matches** the trust contract — real confidence, markers injected, flags set. |
| **Name-linking** (`lib/sanitise.ts`) | TS port of the **OLD blocking** `sanitisation.py`; ambiguous alias → `{status:'ambiguous'}` → **blocking `DisambiguationModal`** (`app/review.tsx`). | ❌ **Biggest mismatch.** Desktop is now **non-blocking** (leave ambiguous plain, resolve at desktop review). Fails soft today (dismiss → drops `sanitised`, Mac redoes), so not broken — just divergent + unnecessary friction. |
| **Tagging** | **None automated** — free-text comma field only (`app/review.tsx`), sent as `metadata.tags`. | ❌ Missing all of session-decisions §1. Mac *consumes* `metadata.tags`, so the pipe exists — the on-device matcher doesn't. |
| **Names sync** (`lib/names.ts`) | Bidirectional LWW by canonical, tombstones, meta/GET/PUT — matches `names_store.py`. | ✅ Protocol matches. ❌ **`voiceEmbeddings` not round-tripped** — `Person` type lacks it, so a local edit **silently drops** embeddings the Mac writes (latent data-loss). Backend is already ready (`names_store`/`api/names.py` pass it through). |
| **Sync payload** (`lib/sync.ts`) | Sends `transcript`/`sanitised` (gated on local status) + `metadata` incl. `transcriptConfidence`, `transcriptUserEdited`, `transcriptMarkersInjected`, `tags`, `imageManifest`, `sharedContent`, `annotationText`, location/weather/etc. | ✅ **Matches the trust contract well.** Minor gap: sends **no title** for the desktop two-title chooser. |
| **Diarization** | **None** (zero hits for diariz/speaker/embedding/pyannote/sortformer). | ❌ All of session-decisions §3 unbuilt. |
| **Word boosting** | **None** — `AsrManager(config:.default)`, TDT only, no CTC 110M, no boost list. FluidAudio pinned **0.12.4**. | ❌ All of session-decisions §2 unbuilt; CTC availability on 0.12.4 unverified. |

## 2. What needs doing

**A. Desktop-sync mismatches (correctness):**
1. **Non-blocking name-linking** — rewrite `lib/sanitise.ts` + `app/review.tsx` to the desktop model: link unambiguous aliases, leave ambiguous **plain** (don't block); let the Mac's review resolver handle them. Retire/repurpose mobile `components/DisambiguationModal.tsx` (the desktop deleted its own). **Biggest divergence — do early.**
2. **`voiceEmbeddings` round-trip** in `lib/names.ts` — extend the `Person` type + `mergeByCanonical` + `writeData`/`upsertPerson` to preserve it. Small; unblocks §3; backend already done.
3. *(Minor/optional)* send a `metadata.title` (e.g. first annotation line / user title) so the desktop two-title chooser has a phone candidate (backend would need to read + store it — coordinate with desktop HANDOFF §4 "phone-title capture", still deferred there).

**B. The 3 session-decisions features (read the doc for locked rationale):**
- **§1 On-device tag matching** — *backend + mobile*. Backend: have `/tags/whitelist/refresh` emit a **`matchable` subset** + **pre-expanded lemma forms** per tag, and a way to **ship the whitelist to the phone** (piggyback on names sync or a new GET). Mobile: fetch + cache the whitelist, lemma-matched + **frequency-gated (≥2×)** candidate matching, **spoken `#hashtag`** extraction (commits directly), tap-to-confirm UI in `review.tsx`. **Suggestions only** — never auto-commit. (`lib/prompts.ts` already nudges "say your tags out loud" — good fit.)
- **§2 Word boosting** — *gated on a FluidAudio check*. Confirm CTC custom-vocab boosting is exposed on **0.12.4** (the open item); load CTC 110M alongside TDT; plumb a boost list (the **unusual-terms subset** — coined words/names/jargon, NOT common words) into Swift `transcribe`. Shares the §1 list.
- **§3 Diarization + voice profiles** — *last, highest memory risk*. Offline pyannote pipeline; per-recording toggle on the recorder; self-enrollment from an existing recording (`extractEmbedding`); relabel UI (relabel = enrollment for others); **multi-embedding per person, max-cosine, never average** (AirPods vs phone mic); write embeddings back into `names.json` on manual correction. Follow the doc's own build order (schema → self-enroll → toggle → relabel).

**C. Dead code / bugs / risks:**
- Mobile `DisambiguationModal.tsx` + the ambiguous branch of `sanitise.ts` — divergent; remove/rewrite (see A1).
- **`voiceEmbeddings` silent-drop** in `names.ts` — latent data-loss the moment the Mac writes embeddings (see A2).
- **Memory crash (OS-kills the app)** — *not root-caused.* `_native` caches `asr`/`models` for the app lifetime with **no unload/teardown** in `ParakeetModule.swift`. §2 (2nd CTC model) and §3 (diarizer) will **raise peak memory on an already-killed app** — investigate + add model teardown BEFORE/with those features (desktop fought the analogous MLX Metal leak via `mx.clear_cache()`).
- **FluidAudio 0.12.4 pin** blocks 0.13.x (Swift 6 concurrency error). Both §2 and §3 availability must be confirmed against 0.12.4; may force a version bump + the concurrency fix.
- Marker insertion uses NSString/UTF-16 indexing vs Python `str` — spot-check parity on multibyte/emoji transcripts.

## 3. Recommended build order
1. **`voiceEmbeddings` on mobile** (small, unblocks §3, backend done) — A2.
2. **Non-blocking sanitise rewrite** (desktop-sync correctness, independent) — A1.
3. **Tag-matching track (§1)** — backend `matchable`+lemma+ship endpoint, then mobile matcher + hashtag commit + review UI. Separable, high value, low memory risk.
4. **Word boosting (§2)** — after a FluidAudio 0.12.4 CTC check; reuses §1's unusual-terms list.
5. **Diarization (§3)** — last; pair with the **memory-crash investigation + model teardown**; sequence enrollment → toggle → relabel per the doc.

## 4. Confirm first (open questions)
- **FluidAudio 0.12.4:** is CTC boosting exposed? are pyannote/Sortformer diarization APIs available? (If not → version bump + Swift 6 concurrency fix.)
- **Matchable-subset mechanism:** flag-per-tag in the whitelist vs a separate list (session-decisions §Deferred). Decide with the user.
- **Whitelist-to-phone transport:** extend names sync vs a dedicated endpoint.
- **Phone title:** does the user want it (two-title chooser) or skip (minor)?
- **Memory crash:** reproduce + profile before adding more models.

## 5. Key files
Mobile: `lib/sanitise.ts`, `lib/names.ts`, `lib/sync.ts`, `lib/transcribe.ts`, `lib/metadata.ts`, `lib/prompts.ts`, `app/review.tsx`, `contexts/RecordingContext.tsx`, `app/(tabs)/record.tsx`, `modules/parakeet/ios/ParakeetModule.swift`, `components/DisambiguationModal.tsx`.
Backend (contracts): `api/files.py` (`upload_files` trust gate), `api/names.py`, `api/enhance.py` (`/tags/whitelist*`), `services/enhancement.py` (tag engine), `services/sanitisation.py`, `utils/names_store.py`.

## 6. Kickoff prompt for the next chat
```
Resume the Skrift MOBILE overhaul (Expo iOS app in Mobile/, at
/Users/tiurihartog/Hackerman/Skrift). The desktop half was overhauled on branch
`overhaul`; now re-sync the mobile app to it + add 3 planned features.

Read FIRST: MOBILE_OVERHAUL_PLAN.md (this plan), Mobile/CLAUDE.md, CLAUDE.md
(desktop), /Users/tiurihartog/Downloads/skrift-session-decisions.md (locked
feature decisions), and memory (project_overhaul, feedback_vault_privacy,
feedback_visual_ui_iteration).

Hard rules: never point AI at the Obsidian vault (code only; test with a sample
I give you); keep it simple; bring me along (mock/confirm before building big);
verify each chunk (tsc + iOS Simulator + round-trip against the running Mac
backend) and commit each chunk. Branch off `overhaul` (it has the new backend
contracts) or coordinate the branch with me first.

Start with the build order in §3: (1) voiceEmbeddings round-trip on mobile,
(2) non-blocking sanitise rewrite, then the tagging/boosting/diarization tracks.
Confirm the §4 open questions with me before the features. Tell me what you
found + the plan before writing code.
```
