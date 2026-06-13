# NEXT CHAT — finish the audiobook player polish (autonomous)

Paste-as-prompt handoff. Work **autonomously**: research first, build without asking,
**gate + commit per chunk**, device-install, end with a report. Don't block on
confirmations (memory `feedback_autonomous_execution`). Mock-first only for genuinely-new
UI. **Don't push to `main`** (prod untouched). **Don't use the parallel-lanes skill.**
**Don't fabricate perf numbers.**

## READ FIRST (in order)
1. `CLAUDE.md` — build/run, hard rules, **dev/prod data safety** (build+install the DEBUG
   "Skrift Dev" only; never rebuild prod), "Open cross-app work".
2. `backlog.md` — the **⭐ CONTINUE HERE (2026-06-13 night)** block at the BOTTOM is the live
   state: what's done + what's open. Read it first.
3. `FEATURES.md` — "Audiobook player — text-forward redesign" + "Text-first quote capture" rows.
4. Memory: `project_audiobook_player` (player + read-along + the **chunk-drift gotcha**),
   `project_vocab_booster`, `feedback_native_ui_process`, `feedback_native_ui_verification`.

## STATE (2026-06-13 night)
Branch `native`, **all committed, `main` untouched/un-pushed, prod untouched**. Mobile dev build
("Skrift Dev", `com.skrift.mobile.dev`) **installed on the iPhone 13** (devicectl UUID
`A9195A77-601A-54C1-B3BD-659FBFE1DC54`). This session shipped + DEVICE-CONFIRMED: custom-vocab fix
(both apps; "Rox" + "Skrift" work), text-capture WAVE 2 (whole-book pre-transcribe), the text-forward
A+D-hybrid player (Spotify read-along, bookmarks, Chapters/Bookmarks sheet, library long-press), and
the read-along sync chase (chunk time-drift → sample-accurate `extractPCM`; tick latency →
interpolation + end-advance; stuck-nudge → live re-check; smoothness → uniform font + scaleEffect;
`lead` 0.3→0.1). Mock: `Skrift_Native/SkriftDesktop/mocks/audiobook-player-redesign.html`.

## IMMEDIATE TASKS
1. **Read-along final eyeball (device).** On a re-transcribed book, confirm the lit line tracks the
   voice the WHOLE chapter, advances smoothly (no "hustle"), and isn't early/late. The one dial is
   `ReadAlongView.lead` (0.1s). If you need to re-verify timings, the desktop harness is
   `-readalongcheck <audio> <sidecar>` / `-chunksim <audio>` (pull the book folder from the phone:
   `Documents/audiobooks/<bookID>/`).
2. **Control Center glyph — user picks the direction** (candidates were shown). Options + HOW are in
   `backlog.md` ⭐ #3: A `quote.opening` / B `pencil.line` (SF Symbols, 1-line swap in
   `SkriftWidget/RecordControlWidget.swift` + `RecordWidget.swift`) — OR C a custom carved-strokes
   mark (echoes the app icon; add an asset catalog to the SkriftWidget target + a single-colour
   SVG/PDF as a Symbol/template image; mock-first the mark for sign-off). The 3D app icon itself
   can't be a CC glyph.
3. **Wave-2 deferred** (design `mocks/text-capture-DESIGN.md` §9): cross-chapter quotes;
   auto-transcribe-ahead-while-playing; **A/B test integrity** for text-vs-audio capture (assign the
   arm, pre-transcribe the test book, define the success metric); desktop mirror of wave 2 (mobile-only).
4. **Pre-existing backlog** (untouched): prod promotion (one-time Xcode App-Group signing for the
   Release bundle IDs, then `native`→`main`); Mac "name a speaker" mock sign-off; drag-multi-select
   mock; record-a-sample voice enroll (conversation track); desktop A-list perf nits; re-ingest old
   notes; "transcription a bit weird".

## GATES (non-negotiable)
- **Mobile:** `cd Skrift_Native/SkriftMobile && xcodegen generate` after adding files. Sim:
  `xcodebuild test -scheme SkriftMobile -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build`
  (erase the sim if the XCUITest runner flakes — `xcrun simctl shutdown all; xcrun simctl erase "iPhone 17"`).
  Device: `xcodebuild build -scheme SkriftMobile -destination 'generic/platform=iOS' -derivedDataPath build-device -allowProvisioningUpdates DEVELOPMENT_TEAM=9W82X49JZS CODE_SIGN_STYLE=Automatic`
  then `xcrun devicectl device install app --device A9195A77-601A-54C1-B3BD-659FBFE1DC54 build-device/Build/Products/Debug-iphoneos/SkriftMobile.app`.
- **Desktop:** `xcodegen generate`; `xcodebuild test -scheme UnitTests -destination 'platform=macOS'`;
  `xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -derivedDataPath build`.
  Read-along harness: `-readalongcheck` / `-chunksim`. Quit the GUI app before headless runs.
- Real ASR + read-along behaviour are device-owed (sim has no ANE). **Commit per chunk; update
  FEATURES.md + backlog.md (the ⭐ block) in the same commit.**

## DURABLE GOTCHA
Per-chunk `AVAssetExportSession(timeRange:)` on COMPRESSED audio is NOT time-accurate (drift grows
with seek depth). For any extraction whose word-times must align to the source, use sample-accurate
`AVAudioFile` frame reads (`BookTranscriptionJob.extractPCM`). Verify with the anchor-diff harness.

## END WITH A REPORT
What shipped, gates, the read-along verdict, the glyph decision + result, device re-test list, deferred.
