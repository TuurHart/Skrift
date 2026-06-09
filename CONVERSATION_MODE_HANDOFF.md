# Conversation Mode — Handoff (2026-06-09, written for a fresh chat)

Context filled mid-build. This doc is **self-contained** — read it + do §0, then continue.
Repo: `/Users/tiurihartog/Hackerman/Skrift`, branch **`native`** (= `main` = origin, was clean).
Apps under `Skrift_Native/{SkriftMobile,SkriftDesktop}`. Also read the broader ledger
`MOBILE_NATIVE_HANDOFF.md` (rest of this session: glass, light/dark, inline editor, perf —
all DONE + deployed) and memory `project_unification_backlog`.

---

## 0. READ THIS FIRST — mandatory codebase exploration (do NOT skip)

A previous mistake this session: assuming a feature was missing when it already existed
(there **IS** a Settings → **"Names & voices"** tab). **Before building or claiming
anything is absent, read the actual code.** Minimum reading list:

**Conversation-mode code already built (phone):**
- `Skrift_Native/SkriftMobile/Services/SpeakerFusion.swift` — `DiarizedSegment` (Codable) + fusion (words+segments → `**Speaker:**` turns, 1-word-island smoothing). 5 unit tests.
- `Skrift_Native/SkriftMobile/Services/Diarization/DiarizationService.swift` — Sortformer engine (`Diarizing` protocol, `DiarizationOutput{segments, slotNames}`, `DiarizerFactory`, `SeededDiarizer` sim mock). **Currently matches via Sortformer `enrollSpeaker(audio)` — TO PIVOT (see §4).**
- `Skrift_Native/SkriftMobile/Services/Diarization/DiarizationStore.swift` — per-memo sidecar `diar_<id>.json` (`DiarizationData{segments, slotNames}`).
- `Skrift_Native/SkriftMobile/Services/Diarization/SpeakerVoiceStore.swift` — per-person **audio** samples (for Sortformer enroll). **Likely replaced by embeddings on the Person (§4).**
- `Skrift_Native/SkriftMobile/Services/Diarization/DiarizationStatus.swift` — the "Downloading speaker model… / Identifying speakers…" banner state.
- `Skrift_Native/SkriftMobile/Features/MemoDetail/SpeakerTurnsView.swift` — `SpeakerTranscript.parse(**Name:**)` + render turns + tap-to-name (`onTag`).
- `Skrift_Native/SkriftMobile/Features/MemoDetail/ConversationMockView.swift` — design mock (`-conversationMock`).
- `Skrift_Native/SkriftMobile/Features/MemoDetail/MemoDetailView.swift` — `transcriptSection` (turns vs editor vs karaoke), `renameSpeaker` (rewrites `**old:**`→`**new:**`, currently enrolls audio), ⋯ "Split speakers", status banner, `SignificanceSlider`, `TranscriptEditor` usage.
- `Skrift_Native/SkriftMobile/Features/Recording/MemoSaver.swift` — `runTranscription` → `diarizeIntoTurns` (on-save, gated by `conversationDefault`) + `diarizeExisting` (retro). `conversationModeOn`.
- `Skrift_Native/SkriftMobile/Features/Recording/RecordView.swift` — `@AppStorage("conversationDefault")` Conversation toggle; empty-recording guard (`emptyRecording` alert).
- `Skrift_Native/SkriftMobile/Features/MemoDetail/TranscriptEditor.swift` — the always-editable UITextView body (inline images + write-back).

**Names + voices + sync (read ALL — this is where the identity lives):**
- `Skrift_Native/SkriftMobile/Models/NamesData.swift` — `Person{canonical, aliases, short, voiceEmbeddings:[VoiceEmbedding]}`; `VoiceEmbedding{vector:[Double], condition:String?, addedAt:String?}`.
- `Skrift_Native/SkriftMobile/Services/NamesStore.swift` — `shared`, `load()/save()`, `upsert(canonical:aliases:short:)`, `delete(canonical:)`, **`addVoiceEmbedding(canonical:embedding:)`**, `livePeople()`.
- `Skrift_Native/SkriftMobile/Features/Names/NamesListView.swift` — **the "Names & voices" tab** (`PersonRow`, `PersonDetailView`, `AddPersonView`, `NamesDisplay.isEnrolled(person)` = `voiceEmbeddings` non-empty, `VoiceBars`). "Add voice" is a **status label only** today — no enroll action wired.
- Names SYNC contract (the spine): `MOBILE_NATIVE_HANDOFF.md` §4 + `Services/NamesSync*`. `GET /api/names/meta` → `GET` → LWW merge (**union** voiceEmbeddings) → `PUT`. **Byte-compatible across both apps.**
- Desktop equivalents: `Skrift_Native/SkriftDesktop/` — `NamesStore`, `Models/` Person/VoiceEmbedding, `Features/Settings/SettingsView.swift` (has a Names section), `Pipeline/`/`UploadService`/`BatchRunner` (memo ingest + name-linking + Obsidian export). The desktop links FluidAudio (has Sortformer + `DiarizerManager.extractSpeakerEmbedding`).

**FluidAudio API (the diarization SDK, pinned `branch: main`):**
- Checkout: `Skrift_Native/SkriftMobile/build/SourcePackages/checkouts/FluidAudio` (or `DiarizeSpike/.build/checkouts/FluidAudio`).
- Diarization docs: `Documentation/Diarization/GettingStarted.md` (model-choice matrix).
- Sortformer: `Sources/FluidAudio/Diarizer/Sortformer/SortformerDiarizer.swift` (`SortformerConfig.default`, `SortformerModels.loadFromHuggingFace(config:)`, `initialize(models:)`, `processComplete(samples) -> DiarizerTimeline`; `timeline.speakers` = `[Int: DiarizerSpeaker]`, `speaker.finalizedSegments`, `speaker.name`).
- Embeddings (wespeaker): `Sources/FluidAudio/Diarizer/Core/DiarizerManager.swift` → `extractSpeakerEmbedding(from audio:[Float]) throws -> [Float]` (needs `DiarizerModels.downloadIfNeeded()` — the pyannote bundle). `DiarizerSegment{speakerLabel, startTime, endTime}`.
- `AudioConverter(sampleRate: 16000).resampleAudioFile(url) -> [Float]` (16kHz mono).

**The spike (proof + experiment harness):** `Skrift_Native/DiarizeSpike/` — standalone SwiftPM CLI. `swift run DiarizeSpike <audio> [wt.json]` diarizes + fuses. Use it to prototype embedding-cosine OFF-device fast (no app rebuild).

---

## 1. The vision (LOCKED, from the user)

Conversation mode on **both** phone + Mac, with **bidirectional voice sync**:
- Phone records a conversation → split into speakers → name them → **voiceprints saved** → sync to Mac.
- Mac transcribes an old recording (or its own) → split → name/auto-recognize → saved → sync back.
- **Bidirectional LWW** → both apps always have the most up-to-date voices.
- **Both apps** have the "Names & voices" tab. The **Mac owns the canonical** `[[Name]]` + alias disambiguation (as it does now); the phone names speakers in plain text, the Mac links them.

---

## 2. Locked design — how it works (resolved with the user)

**Two distinct jobs — do not conflate:**
1. **Diarization** ("who spoke when", split into Speaker 1/2/3): **Sortformer**, from raw audio, best-in-class, on **both** apps. **No quality loss.** No embeddings involved here.
2. **Identification** ("is Speaker 1 = Tiuri?"): compare each split speaker's voice to **saved voiceprints**. This is the ONLY place voiceprints matter.

**The voiceprint = a wespeaker EMBEDDING** (`[Float]` vector, small + portable). Sortformer **cannot ingest an embedding** (it enrolls from audio), so identification is a **separate cosine-match**: diarize (Sortformer) → per-speaker embedding (wespeaker `extractSpeakerEmbedding`) → cosine vs known `Person.voiceEmbeddings` → label. The embedding is what **syncs phone↔Mac** (already the `voiceEmbeddings` contract field).

**Quality:** diarization is 100% Sortformer on both apps (no loss). Identification by embedding-cosine is the standard, strong approach for "recognize a known person" — fine for distinct voices. **Fallback if real-world matching is weak:** sync a short compressed **audio sample** per person and Sortformer-`enrollSpeaker` from it on each device (best identity, heavier sync) — keep this escape hatch in mind, but **start with embeddings**.

---

## 3. Current state (built + committed + deployed this session)

All on `native`, **deployed Release to the iPhone 13** (UDID `00008110-001208C902EA201E`). Conversation
mode is **device-verified working** by the user EXCEPT auto-match: recording in conversation mode splits
into Speaker 1/2, tap-to-name works, "Split speakers" retro action works, status banner shows.

Commits (newest first): `d426d4b` E-full plumbing · `c223d2d` Split speakers · `8b15a9f` status banner ·
`eda8d92` empty-recording guard + toggle-wire · `ebd0fd9` on-save diarize + tap-to-name · `9f2ed1d`
DiarizationService · `7bf9b97` render turns · `925441a` SpeakerFusion · `18b3998` UI mock · Sortformer
spike `4678c1c`/`6889881`. Tests: 40 unit + 29 UI green on the iPhone 17 sim.

**Pipeline today (phone):** record (conversation toggle on) → transcribe (Parakeet) → if `conversationDefault`
on, `MemoSaver.diarizeIntoTurns`: Sortformer `processComplete` → segments + (currently) `enrollSpeaker`-based
slotNames → `SpeakerFusion` → `**Speaker N:**` transcript → render via `SpeakerTurnsView` → tap a speaker →
`renameSpeaker` rewrites prefixes (+ currently saves audio to `SpeakerVoiceStore`). Status banner via
`DiarizationStatus`. Sidecar via `DiarizationStore`.

**Gap the user hit:** a new recording doesn't recognize previously-named people (because matching is
Sortformer-audio-local + the naming doesn't store a synced voiceprint). That's what §4 fixes.

---

## 4. THE PIVOT — identity layer = embeddings (do this first)

Replace the Sortformer-`enrollSpeaker`(audio) matching with **embedding-cosine** so it's portable +
syncs + works on both apps. Keep Sortformer for **diarization** (unchanged).

1. **`SpeakerEmbedder`** (new, `Services/Diarization/`): actor wrapping `DiarizerModels.downloadIfNeeded()`
   + `DiarizerManager.extractSpeakerEmbedding(from:[Float]) -> [Float]`. A `SeededEmbedder` mock for the
   sim + an `EmbedderFactory` (mirror `DiarizerFactory`). NOTE: this is a **2nd model** on the phone
   (pyannote/wespeaker bundle) — first naming downloads it (~minute, then cached); surface it in
   `DiarizationStatus`.
2. **On naming** (`MemoDetailView.renameSpeaker`'s detached Task): extract the speaker's audio (from the
   `DiarizationStore` segments for that slot, via `AudioConverter.resampleAudioFile` + slice) → embed →
   `NamesStore.shared.upsert(canonical: new, …)` + `addVoiceEmbedding(canonical: new, VoiceEmbedding(vector: emb.map(Double.init), condition:"conversation", addedAt: ISO8601.now()))`. → the Person shows **"Voice enrolled"** in Names & voices (existing `isEnrolled`) + **syncs to the Mac**.
3. **On diarize** (`DiarizationService.diarize`): after `processComplete` segments, for each slot extract its
   audio → embed → cosine-match against `NamesStore.shared.livePeople()` `voiceEmbeddings` (best match above
   a threshold; tune it like the diarization spike) → `slotNames[slot] = matchedPersonName`. Drop the
   `enrollSpeaker` calls + `SpeakerVoiceStore` (or leave dead). `SeededDiarizer` already reads known names —
   keep its mock-match.
4. Verify on device: name people in recording A → record B with the same people → B auto-labels them. Tune
   the cosine threshold on real audio (use `DiarizeSpike` to iterate fast off-device).

---

## 5. Ordered next steps

1. **Phone embedding pivot (§4)** — the auto-match the user is waiting on. Device-test.
2. **Names & voices wiring (phone)** — naming a speaker links/creates a Person (done in §4 via `upsert`);
   confirm the "Voice enrolled" badge shows; consider a "record a voice" action in `PersonDetailView`
   (currently just a label) so voices can be enrolled directly, not only via conversation.
3. **Mac conversation mode (desktop track)** — a desktop `DiarizationService` (FluidAudio Sortformer on the
   Mac) so the Mac can diarize multi-speaker recordings/imports; embedding match against synced
   `voiceEmbeddings`; render `**[[Person]]:**` turns; ensure the desktop has the **"Names & voices"** voice
   UI (it has a Names list — add the voice indicator/enroll). The Mac keeps **canonical [[ ]] + disambiguation**.
4. **Bidirectional voice sync — verify end-to-end:** name on phone → embedding syncs → Mac recognizes; name
   on Mac → syncs back → phone recognizes. (Contract already unions `voiceEmbeddings`; confirm both write it.)
5. **(F) Live diarization while recording** — feed the record tap (the same `AVAudioEngine` tap as live
   caption, `LiveRecordingService`) to Sortformer streaming for live speaker labels.
6. **Watch-list:** the empty-recording root cause (0-frame capture) — guard shipped; if it recurs on a
   PROPER-length recording, capture device logs (`idevicesyslog -u <UDID>`) while reproducing.

---

## 6. Build / test / deploy / device / gotchas

```
cd Skrift_Native/SkriftMobile && xcodegen generate           # after adding files
xcodebuild test  -scheme SkriftMobile -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build
# device (Release = prod "Skrift"; UDID 00008110-001208C902EA201E, must be UNLOCKED):
xcodebuild build -scheme SkriftMobile -configuration Release -destination 'platform=iOS,id=00008110-001208C902EA201E' \
  -derivedDataPath build-device -allowProvisioningUpdates DEVELOPMENT_TEAM=9W82X49JZS CODE_SIGN_STYLE=Automatic
xcrun devicectl device install app --device 00008110-001208C902EA201E build-device/Build/Products/Release-iphoneos/SkriftMobile.app
# pull the app's recordings/sidecars/voices off the device to inspect:
xcrun devicectl device copy from --device 00008110-001208C902EA201E --domain-type appDataContainer \
  --domain-identifier com.skrift.mobile --source Documents/recordings --destination /tmp/sk
# desktop: cd Skrift_Native/SkriftDesktop && xcodegen generate; xcodebuild test -scheme UnitTests -destination 'platform=macOS'; xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation
# diarization spike (fast off-device prototyping): cd Skrift_Native/DiarizeSpike && swift run DiarizeSpike <audio> [wt.json]
```

**GOTCHAS / hard facts:**
- **Diarization is DEVICE-ONLY** — the sim has no ANE; like ASR, it can't really run there. Use `SeededDiarizer`/`SeededEmbedder` for sim wiring tests; device-test the real ML. The iPhone 17 sim DOES render the rest of the UI (screenshot via XCUITest + `xcrun xcresulttool export attachments`).
- **First-time models are slow:** Sortformer ~90s download+compile (one-time, cached); the wespeaker bundle is a SECOND first-time download. Always surface via `DiarizationStatus`.
- **Sortformer config:** `SortformerConfig.default`, no `clusteringThreshold` games — it splits real convos correctly (the legacy pyannote `DiarizerManager` needed 0.45 and was worse; do NOT use it for diarization).
- **Commit per chunk; verify each** (sim build+test mobile; UnitTests + `-skipMacroValidation` desktop). Mobile↔Mac contract byte-exact (no `sanitised`; union `voiceEmbeddings`). Co-author trailer on commits: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Don't push unless asked.
- **Dev/prod:** Debug = "Skrift Dev" (`com.skrift.mobile.dev`, isolated data); Release = prod "Skrift". User runs prod.
- **The conversation test fixture:** the user's real 2-person memo is `memo_6C0C4C75-…m4a` (pulled to `/tmp/skrift-rec/` earlier; re-pull if needed). Sortformer split it into the correct turns (matched the user's manual ground truth).

---

## 7. The fallback (if embedding-cosine identity is weak on real audio)

Sync a short **compressed audio sample** per person (additive contract field, optional, stays byte-compatible)
+ Sortformer-`enrollSpeaker(withAudio:)` on each device. Best identity quality, heavier sync. `SpeakerVoiceStore`
(already built) is the local-audio piece. Only do this if embeddings underperform in testing.

---

## 8. Rest-of-session context (DONE — don't redo)
Item-0 TabView→ScrollView, light/dark (both apps), Liquid Glass solved (`.clear` + the device's **Reduce Motion**
was throttling it; sim can't render specular glass — `GlassLab/` harness), slimmer player bar, always-editable
inline transcript editor, perf (downsampled images + slider-commit-on-release). All committed + deployed.
Video-import is in `backlog.md`. Full detail: `MOBILE_NATIVE_HANDOFF.md`.

---

## 9. ▶ NEXT-CHAT PROMPT (paste verbatim)

> Resume the Skrift native rewrite — **conversation mode, identity (voice) layer**. Repo
> `/Users/tiurihartog/Hackerman/Skrift`, branch `native` (= main = origin, clean). Apps under
> `Skrift_Native/{SkriftMobile,SkriftDesktop}`.
>
> **FIRST, before writing ANY code: read `CONVERSATION_MODE_HANDOFF.md` end-to-end and actually DO
> its §0 — open every file in the exploration list, especially the Settings → "Names & voices" tab
> (`Features/Names/NamesListView.swift`), `Services/NamesStore.swift`, `Models/NamesData.swift`, and
> the FluidAudio diarization API. A past mistake was assuming a feature was missing when it existed —
> don't repeat it.** Also skim `MOBILE_NATIVE_HANDOFF.md` and memory `project_unification_backlog`.
>
> State: conversation mode is built + deployed to the iPhone 13 (UDID `00008110-001208C902EA201E`,
> prod "Skrift") — Sortformer diarization, on-save + retro "Split speakers", tap-to-name, status
> banner — all device-verified working EXCEPT auto-recognition of previously-named people.
>
> Locked design (§2): **Sortformer diarizes** on both apps (no quality loss); the portable voice
> identity is a **wespeaker embedding** on `Person.voiceEmbeddings` (the names sync contract),
> matched by **cosine** (Sortformer can't ingest embeddings). Bidirectional voice sync; both apps get
> Names & voices; the **Mac owns canonical `[[ ]]`** + disambiguation.
>
> Do, in order (§4–§5): **(1) pivot the phone matcher from Sortformer-audio-enrollment to
> embedding-cosine** — add `SpeakerEmbedder` (wespeaker `DiarizerManager.extractSpeakerEmbedding`,
> needs `DiarizerModels.downloadIfNeeded()`, a 2nd device model — surface in `DiarizationStatus`);
> on naming, compute the speaker's embedding → `NamesStore.addVoiceEmbedding` + `upsert` (shows
> "Voice enrolled" + syncs); on diarize, cosine-match each speaker vs known `voiceEmbeddings` →
> label. Device-test name-once→recognized-next-recording; tune the cosine threshold (iterate fast
> in `Skrift_Native/DiarizeSpike`). (2) confirm Names & voices integration. (3) Mac conversation-mode
> track (desktop Sortformer + voice UI). (4) verify bidirectional voice sync. (5) live diarization (F).
>
> Rules: commit per chunk; verify each (iPhone 17 sim build+test; desktop UnitTests +
> `-skipMacroValidation`); Mobile↔Mac contract byte-exact (union `voiceEmbeddings`, never send
> `sanitised`). Device deploy = Release + `DEVELOPMENT_TEAM=9W82X49JZS` + devicectl (§6). Diarization
> is **device-only** (sim has no ANE) — use SeededDiarizer/SeededEmbedder for sim wiring, device-test
> the ML. Dev=Debug "Skrift Dev"; prod=Release "Skrift". Commit co-author trailer:
> `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
