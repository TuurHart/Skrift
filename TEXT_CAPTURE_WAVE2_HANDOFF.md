# NEXT CHAT — build text-capture WAVE 2 + fix custom vocabulary (autonomous)

Paste-as-prompt handoff. Work **autonomously**: research first, then build without
asking, gate + commit per chunk, device-install, and end with a **proper report**.
Don't block on confirmations (memory `feedback_autonomous_execution`). The one
exception — mock-first for genuinely-new UI — does NOT apply here: both tasks are
already specced (wave 2) or backend (vocab). The "Transcribe book" button is a small
menu item mirroring existing patterns, no mock needed.

## READ FIRST (in order)
1. `CLAUDE.md` — build/run, hard rules, **dev/prod data safety** (build+install the DEBUG "Skrift Dev" only; never rebuild prod).
2. `Skrift_Native/SkriftDesktop/mocks/text-capture-DESIGN.md` — **THE spec.** Especially §2 (the seam), §4 (chunking model), §5 (battery), §6 (fusion), §11 (net-new build surface), §13 (resumability), §14 (device-walkthrough results + open items).
3. `backlog.md` — search "Text-first audiobook capture" and "round 2" for live state.
4. Memory: `feedback_autonomous_execution`, `feedback_native_ui_verification`, `reference_test_fixture`, `project_native_convergence`.

## STATE (2026-06-13)
Branch `native`, all committed, **prod untouched**. Text-capture **WAVE 1 is shipped + device-verified working**:
- Settings → Audiobooks → **Audio / Text** toggle (`Models/AudiobookCaptureStyle.swift`, default `.audio`).
- `Features/Audiobooks/TextCaptureView.swift` — scroll the recent narration, tap a grey line's **+** to add / an end line's **✕** to drop, last line pre-picked. Pure logic in `TextCaptureSelection` + `TextCaptureMath` (unit-tested).
- On confirm it builds the quote **directly from the already-transcribed window** (`QuoteCaptureProcessor.buildOutput`) — **no re-transcribe** — and the capture sheet opens straight at record-your-thoughts (`CaptureSheetView` `skipTrim`).
- The router lives in `QuoteCaptureFlowView` (`.adjust` stage branches on the flag; both modes feed the SAME `presentSheet` → processor/sheet/save/sync/export). **Audio mode is untouched.**
- Today's window transcription: `QuoteCaptureProcessor.transcribeWindowForDisplay` exports the ~90s playhead window, transcribes it, returns sentences. There is **NO whole-book pre-transcribe yet** — that's this task.

Dev build is on the iPhone 13 (devicectl UUID `A9195A77-601A-54C1-B3BD-659FBFE1DC54`, bundle `com.skrift.mobile.dev`). Mac dev build in DerivedData.

---

## TASK 1 — WAVE 2: whole-book pre-transcribe
**Goal:** a "Transcribe book" action so capture is **instant** and works **anywhere** in the book (including scrubbing back to earlier parts), per design §4/§11/§13. Build in gated chunks, commit each.

Components:
- **`BookTranscript` sidecar** — per book, in the book's folder (`Documents/audiobooks/<id>/`, see `AudiobookLibraryStore`), keyed by book id (+ a file hash for staleness on re-import). Stores sentences + word-timings. **Time basis = (fileIndex, file-local time)** — capture works file-local and is **confined to one chapter file** (code-enforced: `QuoteCaptureProcessor.swift:69-76`, "a span can never cross a file boundary"). Honor that; cross-chapter quotes stay a later enhancement.
- **Chunker** — transcribe the book file-by-file in chunks. FluidAudio's `transcribe` takes **no time range** → export each chunk to a temp `.m4a` first (the existing `QuoteCaptureProcessor.exportSpan` pattern). FluidAudio itself internally chunks ~15s for long files (`AsrManager` `streamingThreshold`) — pick chunk size aware of that. **Cut at silence / the longest nearby pause + overlap; fuse seams at sentence boundaries** using `SentenceSnap.sentenceStartIndices` (the existing tech); offset each chunk's word-times to file-local. (Design §6.)
- **Resumable job** (design §13) — save each chunk to the sidecar **as it completes** → the sidecar IS the resume state. On interruption (unplug / crash / jetsam): keep completed chunks, **discard the in-flight half-chunk, resume from the last saved boundary**. **Pause-on-unplug + auto-resume on re-plug.** Atomic append-after-complete so a capture never reads a torn chunk. **MUST run off the transcription critical path and never block live capture** (see Task 2 — the booster-hang lesson).
- **⋯ → "Transcribe book"** in the audiobook player menu (next to "Edit book details"; see `AudiobookPlayerView`). Progress bar (mirror the model-download bar). Copy: "best overnight, plugged in," "resumes if interrupted," "keep listening — capture works for done parts."
- **Instant capture from the sidecar** — in `TextCaptureView`, if the window is already chunked, read sentences from `BookTranscript` (no engine, no window transcribe). Un-chunked spots fall back to the wave-1 `transcribeWindowForDisplay`, with **pre-warm on book-open** (design §4 — warm the engine when a book opens in Text mode, not at capture-tap).
- **Per-hour estimate** on the transcribe screen is a PLACEHOLDER ("≈ 8 min/hr"). **MEASURE the real phone speed** (add a timing log + a device run, or extrapolate from `-asrbench`) and replace it. Don't ship a fabricated number.

Reuse `QuoteCaptureProcessor` (`exportSpan`, `buildSentences`, `buildOutput`) and `SentenceSnap`. **Seam = `QuoteCaptureOutput`** — don't touch the shared sheet / ramble / save / sync / export. Mirror the desktop side only if it's cheap; mobile is the priority (the player is mobile).

---

## TASK 2 — fix custom vocabulary (CONFIRMED broken)
Custom vocab does **not** correct "Script" → "Skrift" even with the ctc110m model loaded (re-confirmed by the user 2026-06-13). The booster (`Services/Transcription/VocabularyBooster.swift` mobile; `Engines/VocabularyBooster.swift` desktop) is **instrumented with DevLog** (`vocab:` lines: ready-state, spot logProbs, rescore `wasModified` + each `original→replacement(shouldReplace)` + `minSimilarity`/`cbw`).

**FIRST — pull the phone devlog** (the user just tested, so fresh `vocab:` lines are there):
```
xcrun devicectl device copy from --device A9195A77-601A-54C1-B3BD-659FBFE1DC54 \
  --domain-type appDataContainer --domain-identifier com.skrift.mobile.dev \
  --source "Documents/devlog.txt" --destination /tmp/devlog.txt
```
(or use the `pull-phone-feedback` skill). Read the `vocab:` lines and branch:
- **Rescorer declined** (`wasModified=false` / `shouldReplace=false`): loosen `minSimilarity`/`cbw`, OR — strong lead — add the mis-heard forms as **aliases**. `CustomVocabularyTerm` has an `aliases` field that the booster currently sets to **`nil`**; teaching the spotter that "script"/"scrift" map to "Skrift" is the most likely real fix. Consider letting the user add aliases, or auto-deriving phonetic near-misses.
- **Spotter never detected the term** (`spot returned no logProbs`, or the term absent from replacements): dig into the CTC keyword-spotter in the FluidAudio source (`Skrift_Native/SkriftMobile/build/SourcePackages/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/CustomVocabulary/`). May be a phonetic limit; aliases or a lower `minScore` may help.
- **"not ready" lines only**: the model still wasn't loaded when transcribe ran — confirm via the Models tab that ctc110m downloaded, then re-test (less likely now; the user said it WAS loaded).

**Verify on the DESKTOP** (real ASR, headless): `-runfile <audio> -vocab "Skrift"`. CAVEAT: the non-blocking booster now **skips the first (model-loading) transcribe**, so a one-shot `-runfile` won't boost — you'll need to either pre-warm the CTC model before the run or add a debug flag that force-prepares synchronously for the test. Repo fixture `test-fixtures/Hotel Du Vin.m4a` is the two-Jacks clip; you may need audio that actually says the target word, or pick a word that mis-transcribes in that fixture to prove the mechanism end-to-end.

**Keep the booster NON-BLOCKING** — it must never jam transcription (the bug fixed this session: `await prepare` inline downloaded the 97MB model in the transcribe path and serialized-jammed every memo into "Transcribing"). Apply any fix to BOTH apps' boosters.

---

## PROCESS / GATES (non-negotiable)
- **Mobile:** `cd Skrift_Native/SkriftMobile && xcodegen generate` after adding files. Sim gate: `xcodebuild test -scheme SkriftMobile -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build`. Device build: `xcodebuild build -scheme SkriftMobile -destination 'generic/platform=iOS' -derivedDataPath build-device -allowProvisioningUpdates DEVELOPMENT_TEAM=9W82X49JZS CODE_SIGN_STYLE=Automatic`. Install: `xcrun devicectl device install app --device A9195A77-601A-54C1-B3BD-659FBFE1DC54 build-device/Build/Products/Debug-iphoneos/SkriftMobile.app`.
- **Desktop:** `cd Skrift_Native/SkriftDesktop && xcodegen generate`. Tests: `xcodebuild test -scheme UnitTests -destination 'platform=macOS'` (`killall -9 testmanagerd` first if flaky). Full build: `xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -derivedDataPath build`. Headless: `-runfile` / `-processfile` / `-asrbench` / `-vocab`. **Quit the GUI app before `-runfile`** (shared SwiftData store race).
- **Real ASR is device-owed** (sim has no ANE; seeded `SeededTranscriber` for logic). Verify the chunker + the vocab fix on the **Mac** (real ASR) wherever possible; pure logic via unit tests.
- **Commit per chunk; update `FEATURES.md` + `backlog.md` in the same commit.** Don't push to `main` (prod untouched).
- **Don't use the parallel-lanes skill** (orchestrator-direct; the user dislikes it).
- **Don't fabricate perf numbers** — measure or state unknown.
- SwiftData gotcha: don't add raw Codable-struct `@Model` attributes (decode trap) — persist as JSON `Data?` blobs (see `Memo.metadata`/`PipelineFile.audioMetadataJSON`).
- Sim share-extension cache: reboot/erase the sim after reinstalling or you screenshot a stale appex (don't rely on sim screenshots for the share sheet — device-verify).

## END WITH A PROPER REPORT
What wave-2 components shipped (with the chunker + resume design as actually built); the **vocab verdict** (devlog said X → fix Y applied + verified, or it's a phonetic limit because Z); all gates green; what's **device-owed / the user's re-test list**; anything deferred. Everything committed + the dev build installed on the phone so the user can test immediately.
