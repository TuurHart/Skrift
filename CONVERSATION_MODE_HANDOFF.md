# Conversation Mode — Handoff (2026-06-09, written for a fresh chat)

Context filled mid-build. This doc is **self-contained** — read it + do §0, then continue.
Repo: `/Users/tiurihartog/Hackerman/Skrift`, branch **`native`** (= `main` = origin, was clean).
Apps under `Skrift_Native/{SkriftMobile,SkriftDesktop}`. Also read the broader ledger
`MOBILE_NATIVE_HANDOFF.md` (rest of this session: glass, light/dark, inline editor, perf —
all DONE + deployed) and memory `project_unification_backlog`.

---

## ⭐ STATUS UPDATE — 2026-06-09 session 2 (the embedding pivot is BUILT)

The §4 pivot is **done + sim-verified on both apps**; only on-device ML + live-sync
verification remain (the phone was OFFLINE this session). Commits (newest first):
`4d20736` Mac voice indicator · `245db92` Mac diarize pipeline · `9e19baf` phone naming→enroll ·
`8ccc3d2` phone diarize→match · `f4c5624` phone SpeakerEmbedder+VoiceMatcher · `9f0b8aa` spike.

**DONE + verified:**
- **Phone identity layer (§4) — embedding-cosine, sim-green.** `SpeakerEmbedder` (wespeaker
  `extractSpeakerEmbedding`, device-only; `SeededEmbedder` for sim via `EmbedderFactory`),
  `VoiceMatcher` (pure cosine + multi-embedding max-match), `VoiceEnroller` (embed→`addVoiceEmbedding`,
  alias-safe). `DiarizationService.diarize` now drops Sortformer-enroll and instead embeds each
  slot + cosine-matches `NamesStore` voiceprints (loads the 2nd model only when voices exist).
  `renameSpeaker` → `learnVoice` enrolls the named speaker. `DiarizationStatus` +`downloadingVoiceModel`
  +`enrolling`. 56 unit + 30 UI tests green (iPhone 17 sim). **Release device build STAGED** at
  `Skrift_Native/SkriftMobile/build-device/Build/Products/Release-iphoneos/SkriftMobile.app`.
- **Threshold MEASURED on real audio (DiarizeSpike `--embed/--pair`, M4 ANE):** different people
  ≤0.22, same person ≥0.62 (in- AND cross-recording) → **threshold = 0.5** (huge gap; favours no
  false matches). Embeddings are **NOT unit-norm** (|v|≈2.6–2.9) → use TRUE cosine. Require **≥2s**
  of speaker audio (short clips gave junk 0.16–0.49). Tunable via `UserDefaults("voiceMatchThreshold")`.
- **Mac diarization (§5.3, "6a") — VERIFIED END-TO-END.** Ported pure `Diarizing`/`SpeakerFusion`/
  `VoiceMatcher`/`SpeakerTranscript.isAttributed` to `SkriftDesktop/Pipeline/Diarization/`; real
  `Engines/DiarizationService` (Sortformer + lazy wespeaker match); `BatchRunner` gained an optional
  `diarizer` + a diarize step (gated on `conversationMode` + audio + word-timings + not-already-
  attributed + ≥2 speakers) that re-emits `**[[Person]]:**`/`**Speaker N:**` turns; injected in
  `RunFile`/`ProcessingCoordinator`. `AppSettings.conversationMode` (Optional → legacy-decode-safe).
  100 UnitTests green; **`-runfile` on the real 2-person fixture split it into correct
  `**Speaker 1/2:**` turns through the whole pipeline.**
- **Mac Names & voices voice indicator ("6b-lite")** — green "Voice"/muted "No voice" per person in
  Settings (snapshot-verified). Parity with the phone.
- **The enroll→recognize loop is PROVEN on real audio (Mac, headless).** `c98410f`: desktop
  `NamesStore.addVoiceEmbedding` (alias-safe) + `DiarizationService.embed`/`embedSpeaker` + a
  `-voiceloop <A> <B>` probe (enroll A's dominant speaker → diarize B → match?). Results:
  same person `memo_417DC6B2`→`memo_3AD9BBDE` cosine **0.6701 → RECOGNIZED**; different
  `memo_6C0C4C75`(2-spk)→`memo_3AD9BBDE` cosine **0.0678 → NOT recognized**. Correct accept/reject
  at 0.5 — the SAME wespeaker model + VoiceMatcher the phone uses, so the phone device-test (still
  owed) is now low-risk. (Run it: `<debug app> -voiceloop <A> <B>`; isolates+restores the dev names store.)
- **BUG FIXED (`c45bcfe`): Gemma copy-edit was STRIPPING `**Name:**` turn prefixes** → Mac
  conversation notes exported with no attribution. BatchRunner now skips copy-edit for attributed
  transcripts (verbatim, like the phone); title/summary/name-link still run. `-runfile`-confirmed
  turns now survive into SANITISED + COMPILED. Also fixes phone conversation memos processed on the Mac.

**PENDING (need the phone / UI review / future sessions):**
1. **Device-test the phone auto-match (THE thing the user is waiting on).** Phone was offline
   (`tunnelState: unavailable`). When reconnected+unlocked: install the STAGED build (§6), then
   name people in recording A → record B with the same people → B should auto-label. Tune the 0.5
   threshold on real device audio if needed. Confirm the "Voice enrolled" badge + that sync writes
   `voiceEmbeddings`.
2. **Bidirectional voice-sync verify (§5.4, "6c").** Contract is byte-compatible + both apps union
   `voiceEmbeddings`, so phone-enroll → Mac-recognize should already work — needs a live round-trip
   (phone + running Mac server). Then Mac→phone once 6b-full lands.
3. **Mac-originated enrollment ("6b-full") — backend DONE, UI owed.** `NamesStore.addVoiceEmbedding`
   + `DiarizationService.embedSpeaker(audioURL:segments:slot:)` already exist + are proven (the
   `-voiceloop` probe uses exactly this path). REMAINING: (a) persist the diarization segments per
   memo (the desktop discards them — add a `diar_<id>.json` sidecar like the phone, or a PipelineFile
   blob), (b) a review-UI affordance in `NoteDisplayView` to name a `**Speaker N:**` → relabel +
   `embedSpeaker` + `addVoiceEmbedding` → syncs back. **UI — mockup-review with the user first**
   ([[feedback_visual_ui_iteration]]).
4. **(F) Live diarization while recording (§5.5).** Phone; deferred (lowest priority).

The §0 reading list + §1–§2 design below are still accurate. §4 is now BUILT (read it for the design,
not as a TODO). Skip to "PENDING" above for what's left.

---

## 0. READ THIS FIRST — mandatory codebase exploration (do NOT skip)

A previous mistake this session: assuming a feature was missing when it already existed
(there **IS** a Settings → **"Names & voices"** tab). **Before building or claiming
anything is absent, read the actual code.** Minimum reading list:

**Conversation-mode code already built (phone) — §4 pivot DONE:**
- `Skrift_Native/SkriftMobile/Services/SpeakerFusion.swift` — `DiarizedSegment` (Codable) + fusion (words+segments → `**Speaker:**` turns, 1-word-island smoothing). 5 unit tests.
- `Skrift_Native/SkriftMobile/Services/Diarization/DiarizationService.swift` — Sortformer engine. **NOW embedding-cosine matches** (`identifySpeakers`: per-slot `SpeakerEmbedder.embed` → `VoiceMatcher` vs `NamesStore` voiceprints; static `clip()`). `SeededDiarizer` reads enrolled `NamesStore` people.
- `Skrift_Native/SkriftMobile/Services/Diarization/SpeakerEmbedder.swift` — **NEW.** wespeaker `extractSpeakerEmbedding` actor (device-only) + `EmbedderFactory` + `SeededEmbedder` (sim). `minSamples`=32k(2s), `maxSamples`=160k(10s).
- `Skrift_Native/SkriftMobile/Services/Diarization/VoiceMatcher.swift` — **NEW.** pure cosine + `bestMatch` (multi-embedding max), threshold 0.5 (UserDefaults-overridable). 8 unit tests.
- `Skrift_Native/SkriftMobile/Services/Diarization/VoiceEnroller.swift` — **NEW.** `enroll(name:clip:using:)` → `NamesStore.addVoiceEmbedding` (alias-safe). 4 unit tests.
- `Skrift_Native/SkriftMobile/Services/Diarization/DiarizationStore.swift` — per-memo sidecar `diar_<id>.json`.
- `Skrift_Native/SkriftMobile/Services/Diarization/SpeakerVoiceStore.swift` — per-person audio samples. **NOW UNUSED** in the active path; kept as the §7 audio-sample fallback.
- `Skrift_Native/SkriftMobile/Services/Diarization/DiarizationStatus.swift` — banner; +`downloadingVoiceModel`/`enrolling`.
- `Skrift_Native/SkriftMobile/Features/MemoDetail/SpeakerTurnsView.swift` — `SpeakerTranscript.parse(**Name:**)` + render turns + tap-to-name (`onTag`).
- `Skrift_Native/SkriftMobile/Features/MemoDetail/ConversationMockView.swift` — design mock (`-conversationMock`).
- `Skrift_Native/SkriftMobile/Features/MemoDetail/MemoDetailView.swift` — `transcriptSection`, `renameSpeaker`→`learnVoice` (rewrites `**old:**`→`**new:**` THEN embeds the slot + `VoiceEnroller.enroll`), ⋯ "Split speakers", status banner.
- Test isolation: `-resetNames` launch flag wipes names.json (the split test needs a clean slate).
- `Skrift_Native/SkriftMobile/Features/Recording/MemoSaver.swift` — `runTranscription` → `diarizeIntoTurns` (on-save, gated by `conversationDefault`) + `diarizeExisting` (retro). `conversationModeOn`.
- `Skrift_Native/SkriftMobile/Features/Recording/RecordView.swift` — `@AppStorage("conversationDefault")` Conversation toggle; empty-recording guard (`emptyRecording` alert).
- `Skrift_Native/SkriftMobile/Features/MemoDetail/TranscriptEditor.swift` — the always-editable UITextView body (inline images + write-back).

**Names + voices + sync (read ALL — this is where the identity lives):**
- `Skrift_Native/SkriftMobile/Models/NamesData.swift` — `Person{canonical, aliases, short, voiceEmbeddings:[VoiceEmbedding]}`; `VoiceEmbedding{vector:[Double], condition:String?, addedAt:String?}`.
- `Skrift_Native/SkriftMobile/Services/NamesStore.swift` — `shared`, `load()/save()`, `upsert(canonical:aliases:short:)`, `delete(canonical:)`, **`addVoiceEmbedding(canonical:embedding:)`**, `livePeople()`.
- `Skrift_Native/SkriftMobile/Features/Names/NamesListView.swift` — **the "Names & voices" tab** (`PersonRow`, `PersonDetailView`, `AddPersonView`, `NamesDisplay.isEnrolled(person)` = `voiceEmbeddings` non-empty, `VoiceBars`). "Add voice" is a **status label only** today — no enroll action wired.
- Names SYNC contract (the spine): `MOBILE_NATIVE_HANDOFF.md` §4 + `Services/NamesSync*`. `GET /api/names/meta` → `GET` → LWW merge (**union** voiceEmbeddings) → `PUT`. **Byte-compatible across both apps.**
- Desktop equivalents: `Skrift_Native/SkriftDesktop/` — `NamesStore` (`livePeople`, `writeWithSmartBumps` preserves voiceprints, **`addVoiceEmbedding`** alias-safe), `Models/NamesData` (byte-identical to phone), `Features/Settings/SettingsView.swift` (Names section + voice indicator), `BatchRunner` (+`diarizer` step; skips copy-edit for conversations), `Engines/DiarizationService` (+`embed`/`embedSpeaker`), `RunFile` (`-voiceloop` proof + injects `DiarizationService.shared`)/`ProcessingCoordinator`.
- Desktop conversation code (NEW, §5.3 done): `Pipeline/Diarization/{Diarizing,SpeakerFusion,VoiceMatcher}.swift` (pure, in UnitTests), `Engines/DiarizationService.swift` (Sortformer + wespeaker, app-only), `AppSettings.conversationMode`, `SkriftDesktopTests/DiarizationTests.swift` (9 tests). The desktop links FluidAudio (Sortformer + `DiarizerManager.extractSpeakerEmbedding`).
- **The spike now has `--embed`/`--pair`** (off-device threshold tuning on the Mac's ANE) — `Skrift_Native/DiarizeSpike/`.

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

> Resume the Skrift native rewrite — **conversation mode, voice identity layer**. Repo
> `/Users/tiurihartog/Hackerman/Skrift`, branch `native` (= main = origin, clean). Apps under
> `Skrift_Native/{SkriftMobile,SkriftDesktop}`.
>
> **FIRST read `CONVERSATION_MODE_HANDOFF.md` — especially the "⭐ STATUS UPDATE — 2026-06-09
> session 2" block at the top: the §4 embedding pivot is BUILT + sim-verified on BOTH apps and
> Mac diarization is verified end-to-end; the code in §0's reading list now EXISTS (read it, don't
> re-build it). A past mistake was assuming a feature was missing when it existed — verify before
> building.**
>
> What's DONE (don't redo): phone embedding-cosine identity (`SpeakerEmbedder`/`VoiceMatcher`/
> `VoiceEnroller`; diarize→match; naming→enroll; 56 unit + 30 UI green; **Release device build
> STAGED** at `Skrift_Native/SkriftMobile/build-device/.../SkriftMobile.app`). Threshold = **0.5**
> (measured in DiarizeSpike: different ≤0.22, same ≥0.62; embeddings NOT unit-norm; need ≥2s).
> Mac diarization in `BatchRunner` (Sortformer + match → `**[[Person]]:**`/`**Speaker N:**` turns),
> `-runfile`-verified on the real 2-person fixture. Mac Settings voice indicator.
>
> Do, in order (the phone was OFFLINE last session — start by checking it's reachable:
> `xcrun devicectl list devices`):
> **(1) Device-test the phone auto-match** (THE thing the user wants). Install the staged Release
> build (UDID `00008110-001208C902EA201E`, unlocked): `xcrun devicectl device install app --device
> <UDID> <stagedapp>`. Record A, name the speakers, record B with the same people → B should
> auto-label. Tune the 0.5 threshold on real device audio if it mis/over-matches (iterate in
> `DiarizeSpike --embed/--pair` on the Mac; the override is `UserDefaults("voiceMatchThreshold")`).
> Confirm the "Voice enrolled" badge + that sync writes `voiceEmbeddings`.
> **(2) Verify bidirectional voice sync** (phone enroll → run the Mac server → Mac recognizes; both
> union `voiceEmbeddings`). NOTE: the enroll→recognize loop is already PROVEN on real audio on the
> Mac (`-voiceloop`, cosine 0.67 match / 0.07 reject), so this is mostly a live round-trip check.
> **(3) Mac-originated enrollment ("6b-full") — backend DONE** (`addVoiceEmbedding` + `embedSpeaker`
> exist + proven); owed: persist diarization segments per memo + a name-a-speaker affordance in
> `NoteDisplayView` (mockup-review first). **(4) (F) live diarization while recording** (phone; lowest).
>
> Rules: commit per chunk; verify each (iPhone 17 sim build+test; desktop UnitTests +
> `-skipMacroValidation`); Mobile↔Mac contract byte-exact (union `voiceEmbeddings`, never send
> `sanitised`). Device deploy = Release + `DEVELOPMENT_TEAM=9W82X49JZS` + devicectl (§6). Diarization
> is **device-only** (sim has no ANE) — SeededDiarizer/SeededEmbedder for sim wiring, device-test the
> ML. Dev=Debug "Skrift Dev"; prod=Release "Skrift". Commit co-author trailer:
> `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
