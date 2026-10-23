# QUEUE — Skrift
gate: ./gate.sh
code: Skrift_Native/ gate.sh
protected: SPEC.md QUEUE.md gate.sh plan/mtest.sh test-fixtures/corpus Skrift_Native/SkriftDesktop/SkriftDesktopTests Skrift_Native/SkriftMobile/SkriftMobileTests

Wave 1 of the v2 rewrite (2026-09-24): the mocks, rewrite target 1 (body/image) end to end,
the lost-recording fix, three data-loss/privacy fixes, the perf baseline. Phone-side checks
use `plan/mtest.sh <TestClass>` (the default gate runs the Mac suite only). Mocks go in
`Skrift_Native/SkriftDesktop/mocks/`, current-app parts drawn from source (C117).

## Later

Staged, not dropped. Each comes back as items at the next resync (`/2-plan`), in this order:
- Builds of the Q3 tag UI (C241), Q4 conflict prompt (C98, C242) and Q6 sources tab (D90, D126, D128) mocks, once signed.
- The perf lane: one item per site in `plan/perf-sweep.md` §2 and `plan/sources.md` rows 29 30 37 38 52 58 59 60 61 62 115 (C277–C281, C296), after the Q20 baseline.
- The editor rebuild on body v2 with Apple Notes formatting (C113, C234, D112, D115), mock first.
- Mock refreshes: Mac Names screen (D108); `resolver-inline` A vs the shipped popover (D109).
- Library imports after Q352–Q356: Kindle/Readwise highlights and talks (D90), and Library on iPad/Mac widths.
- Mac feedback transport (D111, host owed).
- The rest of the import layer (C66–C79, C123–C124, C128, C140, C143, C145, C147) once Q439 lands.

## Items

### Q1 [tuur] (done) mockup: quick note
spec: C112 C114 C43
needs: -
do: One clickable HTML page: the app opening into the list with the New Note action one tap away; the Lock Screen / Control Center widget and the Siri path each landing in an empty note with the keyboard up; leaving an untouched empty note discards it (D91). Phone and iPad frames.
check: Tuur clicked through it and said go.

### Q2 [tuur] (done) mockup: three-ball importance
spec: C94 C210 C183
needs: -
node: i23
do: The importance control as three balls (Passing 0.3 / Useful 0.6 / Important 1.0), tap sets, re-tap clears to Not rated, no fourth button, "Importance" label; shown on the Mac note column, the phone note and the iPad note, one size smaller than today (D107). Draw the current control from source beside it.
check: Tuur clicked through it and said go.

### Q3 [tuur] (done) mockup: tag UI revamp
spec: C241 C93
needs: -
do: A redesigned tag editor for phone and Mac that keeps the C93 rules (comma/newline split, `#` stripped, case kept, case-variants fold to the first spelling, destination words allowed). Start from today's tag chips drawn from source, show add / remove / suggest / typeahead.
check: Tuur clicked through it and said go.

### Q4 [tuur] (done) mockup: edit-conflict prompt
spec: C242 C98
needs: -
do: The conflict shown on a note edited on two devices before they synced: the note's marker in the list, the dialog with Keep this device / Keep the other / Keep both (two notes), and where the unkept version sits for the trash window. Modelled on Shapr3D's "Version Conflict Detected". Phone and Mac.
check: Tuur clicked through it and said go.

### Q5 [tuur] (done) inspiration board: the long-form sources tab
spec: C229
needs: -
node: Podcasts
do: One HTML page of screenshots from Apple News, Readwise Reader, Matter, Snipd, Apple Podcasts, Flipboard and Bound, grouped by how each mixes media types (books, episodes, articles, PDFs, talks), with one line per app on what to take. Ends with 3 named directions for Tuur to pick from (D90).
check: Tuur picked a direction.

### Q6 [tuur] (done) mockup: the long-form sources tab
spec: C229 C79
needs: Q5
node: Podcasts
do: The tab in direction A "Shelf" from `Skrift_Native/SkriftDesktop/mocks/Q5-long-form-inspiration.html`, named "Library"; captures stay in Notes, not on the tab (D134): long-form sources only (book, episode, article, PDF, talk), door-based routing (share-sheet PDF → the tab with "Added to Library · add to a note instead"), capture and "send to a note" on every source, "move to Library" on a note, per-book "N notes" with jump-back, the empty-tab call to action (D90, D126, D127, D128).
check: Tuur clicked through it and said go.

### Q7 [auto] (done) build quick note
spec: C112 C114 C43
needs: Q1 Q22 Q26
gate+: yes
do: Build the signed Q1 mock (`Skrift_Native/SkriftDesktop/mocks/quick-note.html`, D134: cursor in the body, silent discard; the phone's New Note placement follows the signed Q22 second pass, D135 — the same Import · Record · New Note verbs as iPad/Mac) on the phone and iPad: an in-app New Note action, a Lock Screen / Control Center widget and a Siri App Intent (plain `AppIntent`, no haptic before the session is ours, C222) that open an empty typed note with the keyboard up; an untouched empty typed note is discarded on leave and never listed (D91). `Memo.newTyped` saves on the tap today, so create the Memo on the first keystroke, or an empty note syncs to the Mac (Q1 finding). Test the routing and the discard in `QuickNoteTests`.
check: `plan/mtest.sh QuickNoteTests`

### Q8 [auto] (done) build three-ball importance on all three devices
spec: C94 C210 C183 C240
needs: Q2
gate+: yes
node: i23
do: Build the signed Q2 mock (`Skrift_Native/SkriftDesktop/mocks/three-ball-importance.html`, D134: one row, cumulative fill, word-only readout) as ONE shared view in `Skrift_Native/Shared/UI/` with a per-app style struct (C240), used on the Mac, phone and iPad. The scale lives in Shared: legacy values bucket (0.1–0.3 → 0.3, 0.4–0.6 → 0.6, 0.7–1.0 → 1.0), re-tap → 0 (Not rated). Test the bucketing and the tap rules in a NEW `ThreeBallScaleTests` (desktop test target); the existing `SignificanceScaleTests` covers the old 10-circle scale and is retired or rewritten with it.
check: `grep -rqE "class ThreeBallScaleTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && grep -rqE "ThreeBallImportanceView" Skrift_Native/SkriftDesktop/Features && grep -rqE "ThreeBallImportanceView" Skrift_Native/SkriftMobile/Features`

### Q9 [auto] (done) corpus expectations become data + v1 body goldens
spec: C4 C5 C10 C11 C12 C13 C14 C15 C19 C20 C253
needs: -
gate+: yes
node: V2Core
do: `CorpusSeed.Note` decodes `expect` (prose: note / bug / bug-fixed). For every corpus note a body clause names (`pic-*`, `typed-crlf-tabs-nbsp`, `voice-en-triple-blank-lines`, `typed-wall-one-paragraph`, `cap-image-voice-ramble`, `pic-shared-no-timestamp`), add a machine-checkable expected stored body as `test-fixtures/corpus/notes/<n>/expect_body.txt`, written from the prose expect + the clause. Record v1's body output for every note (strip markers from the stored transcript, re-place them with v1's `ImageMarkers.insert` from `word_timings.json` + manifest offsets, then `BodyTransform` display + export body) into `test-fixtures/corpus/goldens/v1-body/<slug>.txt`, recorded only when `SKRIFT_RECORD_GOLDENS=1`.
check: `test $(ls test-fixtures/corpus/goldens/v1-body | wc -l) -ge 109 && test $(ls test-fixtures/corpus/notes/*/expect_body.txt | wc -l) -ge 10`

### Q10 [auto] (done) body diff harness + body invariants
spec: C5 C6 C9 C253
needs: Q9
gate+: yes
node: V2Core
do: `BodyDiffHarnessTests` (desktop target) runs every registered body engine (v1 now) over the whole corpus and classes each note identical / expected-different / unexplained against the v1 goldens and `expect_body.txt`; `test-fixtures/corpus/expected-differences.json` maps slug → R id (R1 R2 R25 R33 R74, R95: every voice note with a picture, which v1 never speech-paragraphs — confirmed D134); any unexplained row, or an R row where the engine MATCHES v1, fails (C5). For v1 itself, the notes failing their `expect_body` must be exactly the registered set. Body invariants from C6 as assertions: markers in = markers out, paragraph count never drops, `BodyTransform` round-trip identical, idempotent, pieces cover the body, and (for any non-v1 engine) no `[[img_` inside a sentence.
check: `grep -qE '"R74"' test-fixtures/corpus/expected-differences.json && grep -rqE "class BodyDiffHarnessTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q11 [auto] (done) body/image v2 beside v1
spec: C10 C11 C12 C13 C14 C15 C16 C19 C20 C169 C170 C2 C3
needs: Q10
gate+: yes
node: V2Core
do: Write body v2 in `Skrift_Native/Shared/BodyV2/`: a picture is its own paragraph (`\n\n[[img_NNN]]\n\n`), placed after the sentence spoken at `offsetSeconds` (paused time excluded), no-moment pictures keep their sequence place or go to the top, same-second pictures in manifest order, `%03d` writers / `\d+` readers via one shared regex, whitespace normalised once at commit, paragraphs at a 2.0 s gap on every device, typed text never paragraphed; thumbnail = first resolving marker in body order. Register it in the Q10 harness; the app keeps calling v1 (C2). The two `knownSnapIdempotenceGaps` in `BodyInvariantTests` die with snap (C17), so v2 is never excused from idempotence (Q10 finding). Register v2 against BOTH mapping sets: the Q10 files and the additive `manifest-q23.json` / `expected-differences-q23.json` (Q23 finding), so R74 is judged on its real notes. Write `plan/reads/body-v2.md`: for every note whose body changed, v1 and v2 side by side, for Tuur's read.
check: `test $(cat Skrift_Native/Shared/BodyV2/*.swift | wc -l) -le 3176 && test -s plan/reads/body-v2.md`

### Q12 [tuur] (done) read the body v2 corpus output
spec: C8 C27
needs: Q11
node: V2Core
do: Three rulings owed with the read (Q11 finding): (a) four fixtures put a picture mid-sentence against C11 (pic-at-start, pic-ocr-text, pic-three-spread #3, ingress-p3) — fix the fixtures' offsets, or allow a boundary tolerance; (b) pic-in-task-list cannot satisfy R95 under C20+D3 — drop its R95 entry; (c) the 13 extra differences in `expected-differences-q11.json` are accepted. -
check: Tuur read `plan/reads/body-v2.md` and said it reads right.

### Q13 [auto] (done) swap: every body write site calls v2
spec: C10 C17 C65 C2
needs: Q12 Q30
node: V2Core
do: (Q11 finding: call `BodyV2.committed(BodyV2.Input(text:words:manifest:source:userEdited:))` at every write site, `.speech` only with real word times; `BodyTransform.snappedImageBody` and v1's `ImageMarkers.insert → Paragrapher` leave in the same swap; thumbnail = `BodyV2Thumbnail.pick`.) Point every place a body is WRITTEN at body v2: phone capture (`MemoSaver`), share drain, editor commit, imports, the Mac author path and Mac recordings. Renderers and both exporters stop calling the render-time snap (`snapImages`, `SnapResult`), the display-only `imageBreaks` and the export-time `snappedImageBody` (the v1 functions stay in place for Q15 to delete). The three offset remaps collapse to one (marker → one glyph).
check: `! grep -rnE "snapImages\(|snappedImageBody\(|imageBreaks" Skrift_Native/SkriftDesktop/Pipeline Skrift_Native/SkriftDesktop/Features Skrift_Native/SkriftMobile/Features Skrift_Native/SkriftMobile/Services`

### Q14 [auto] (done) old notes normalised once
spec: C10 C203
needs: Q13 Q31
gate+: yes
node: V2Core
do: (Q23 finding: the corpus has no name-offset field — `CorpusSeed.Note`/`makeMemo` hardcode `nameResolutionsData = nil`; add one so `migrated-stale-name-offsets` proves R25.) At first open on any device, a note whose stored body breaks C10 is rewritten once to the v2 layout and its name offsets re-derived (D4, R25); a local per-note flag makes it one-time and a second run a no-op; the C203 legacy shapes (old test image-captures, pre-build-76 PDF captures) are left alone. Test in `BodyNormaliseMigrationTests` (desktop target) using the v1 goldens as the legacy bodies.
check: `grep -rqE "class BodyNormaliseMigrationTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q15 [tuur] (done) delete v1 body after the tag
spec: C2 C17 C65 C252
needs: Q14
node: V2Core
do: Tag the current commit `v1-body`, then in ONE commit delete the v1 snap code (`snapImages`, `SnapResult`, `imageBreaks`, `snappedImageBody`) and the tests that pin it: `NoteBodyTests` render-time snap cases and `VaultExporterTests` export-time snap case (C252). This touches protected test files on purpose, so accept.sh parks it stuck; Tuur approves the diff in the sitting and the orchestrator merges it.
check: `git rev-parse -q --verify refs/tags/v1-body >/dev/null && ! grep -rqE "snapImages|SnapResult|snappedImageBody|imageBreaks" Skrift_Native --include='*.swift'`

### Q16 [auto] (done) a recording is never lost
spec: C99 C287 C288 C263
needs: Q25
gate+: yes
node: AuditFix2
do: The phone persists audio in segments on every interruption and every 60 s with a marker; a launch sweep rebuilds the note from the segments and says so; a force-quit finalises; disk full stops the take with an honest error and keeps what landed (R46). D131: on a low-memory warning the audio is flushed and a checkpoint row written FIRST, then the transcriber unloads, captions stop, the model reloads after Stop; in the background live captions stop and the recording continues. Recovery never runs over a `transcriptUserEdited` memo (C263); unrecoverable `rec_tmp_*` are cleaned after a failed sweep (C288); every lifecycle transition logs a Release-safe `os_log` line (C287). Test in `RecoverySweepTests`. Hardware-flavoured: per CLAUDE.md the orchestrator owns route/audio-session changes; the worker keeps to persistence + sweep.
check: `plan/mtest.sh RecoverySweepTests`

### Q17 [tuur] (tuur) iPhone 17 Pro: call and force-quit mid-take
spec: C99
needs: Q16
node: AuditFix2
do: Dev 190 is on the iPhone 17 Pro (Q407). Take 1: record, take a phone call mid-take, hang up. Take 2: record, force-quit mid-take. Relaunch after each; pull `Documents/devlog.txt` with `devicectl` from device `00008150-001658662223C01C`.
check: On the phone, start a recording, take a call (or force-quit Skrift) mid-take, then reopen. Are both notes there with all the audio up to the interruption?
ask: Start a recording and let someone call you while it is still recording; answer, then hang up. Open Skrift: is the note there with everything you said before the call? Then do the same again, but swipe Skrift closed while it records.

### Q18 [auto] (done) a corrupt local file is never loaded as empty
spec: C50 C265 C218
needs: -
gate+: yes
node: AuditFix2
do: One shared doctrine for every locally cached JSON file: `names.json` (atomic write, actor-guarded, merge never shrinks — R8), phone `library.json` and `bookmarks.json`, the Mac's `settings.json`, the audiobook-bookmark sync blob (R42, R59, R78). A file present but undecodable is kept aside as `<name>.corrupt-<date>`, recovery is surfaced, and nothing is written over it. One helper in `Skrift_Native/Shared/`. Tests: `CorruptStoreTests` in BOTH test targets (Mac: names + settings; phone: library + bookmarks).
check: `grep -rqE "class CorruptStoreTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && plan/mtest.sh CorruptStoreTests`

### Q19 [auto] (done) re-transcribe keeps the text; attachments obey ownership
spec: C51 C58 C54
needs: -
gate+: yes
node: AuditFix2
do: Re-transcribe clears nothing until the new transcript exists; a missing audio file is an error on the row (R9). Every attachment lane — the Mac `VaultExporter` attachment copy and the shared `VaultWrite.writeAsset` `.file` branch — goes through the same stamp/ownership check as the markdown lane and never removes a file it doesn't own (R7, R77). Tests `RetranscribeKeepsTextTests` and `AttachmentOwnershipTests` (desktop target).
check: `grep -rqE "class RetranscribeKeepsTextTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && grep -rqE "class AttachmentOwnershipTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q20 [tuur] (done) perf baseline before any perf fix
spec: C282
needs: -
node: AuditFix2
do: Claude prepares the `xctrace` commands; Tuur runs Time Profiler on the iPhone 13 during a list scroll, a note open AND typing in a note (D145: "super laggy"), and a typing session in a 5,000-word note on the Mac (Dev, the corpus `typed-wall-7k` note). Claude writes the top frames of both traces into `plan/perf-measured.md`.
check: `test -s plan/perf-measured.md`

### Q21 [auto] (done) a locked note stays locked in Fading and Recently Deleted
spec: C161 C213 C91
needs: -
node: AuditFix2
gate+: yes
do: One Shared predicate decides whether a note's content may show without auth; `WayOutView` (Fading / Recently Deleted) shows the "Locked note" placeholder the list already shows; the three delete entry points in `MemosListView` check the lock; `copyTranscript` / `copyableText` are gated behind auth (R88). Test in `LockedNoteVisibilityTests` (phone target).
check: `plan/mtest.sh LockedNoteVisibilityTests`

### Q22 [tuur] (done) mockup: one notes list across phone, iPad and Mac
spec: C117 C114
needs: -
do: Tuur 2026-09-24 (D134): "the way the notes are viewed, the list of notes… we need to unify that over all three devices". One clickable page: today's list row on the phone, iPad and Mac drawn from source side by side, then ONE unified row + list for all three, with the signed Q1 header ✎ and Q2 three balls in place. Phone, iPad and Mac frames.
check: Tuur clicked through it and said go.

### Q23 [auto] (done) corpus notes for R25, R33 and R74 that SPEC cites but never existed
spec: C4 C13 C12 C10
needs: -
gate+: yes
node: V2Core
do: Add the synthetic corpus notes the R table names but the corpus never had (Q10 finding): `pic-during-pause-two-shots` and `pic-burst-same-offset` (R74: two pictures tie on one nearest word), an ingress-P3 note (R33: 5 clips + 1 picture between clip 3 and 4), and a migrated note with name offsets (R25). Follow `test-fixtures/corpus/README.md` and `generate.py`; fictional roster only (C4). Record their v1 goldens (BodyGoldenTests, re-record recipe in plan/RUN.md Q9 finding), add them to `expected-differences.json`, and drop them from `_missing_fixtures` by adding a new mapping file rather than editing the existing one if gate+ forbids the edit.
check: `test -d test-fixtures/corpus/notes/pic-during-pause-two-shots && test -d test-fixtures/corpus/notes/pic-burst-same-offset && ./gate.sh`

### Q24 [auto] (done) the old 10-stop scale and refine pass leave the code (litCount)
spec: C210 C183 C94
needs: Q8
node: i23
do: Q8 finding: `litCount` and the refine-pass concept still live in `Shared/Model/SignificanceScale.swift`, `Shared/Pipeline/NoteConsent.swift`, `SkriftDesktop/Pipeline/NoteConsent+PipelineFile.swift`, both `ConnectionsPanel.swift`, `SkriftDesktop/Features/Shell/RunFile.swift`, `JournalView`, `LookbackProvider`. Move every caller to `ThreeBallScale` (three stops, legacy values bucket, no refine wall), delete `SignificanceScale` and the `SignificanceCirclesView` wrapper name. The protected tests `SignificanceScaleTests`, `SignificanceCirclesTests`, `SignificanceCirclesRenderTests`, `UnratedTakeTests`, `NoteConsentTests` reference the old scale: Tuur APPROVED retiring/rewriting exactly those five (D138); accept.sh will still REJECT the protected change, so the dispatcher merges by hand after checking the rejected paths are only those five files, then runs the gate.
check: `! grep -rqE "litCount|SignificanceScale\b" Skrift_Native --include='*.swift'`

### Q25 [auto] (done) pin swift-collections to 1.6.0 (Xcode 27 _swift_initBorrow crash)
spec: C4
needs: -
node: AuditFix2
do: Per `plan/research/swift-collections-initborrow.md`: add a `packages:` entry `swift-collections` (url https://github.com/apple/swift-collections, `exactVersion: 1.6.0`) to BOTH `Skrift_Native/SkriftMobile/project.yml` and `Skrift_Native/SkriftDesktop/project.yml`, with a one-line comment citing swiftlang/swift#92574 and swift-collections#733 (drop the pin when a fixed toolchain ships). Regenerate both, confirm each generated Package.resolved says 1.6.0, and that the phone test host launches on the iPhone 17 sim.
check: `grep -q "exactVersion: 1.6.0" Skrift_Native/SkriftMobile/project.yml && grep -q "exactVersion: 1.6.0" Skrift_Native/SkriftDesktop/project.yml && plan/mtest.sh CorpusSeedTests`

### Q26 [auto] (done) build the one notes list on phone, iPad and Mac
spec: C117 C114 C240
needs: Q22 Q8
gate+: yes
do: Build the signed `Skrift_Native/SkriftDesktop/mocks/one-notes-list.html` ("One list" tab; D134–D137) on all three devices through the shared `Shared/UI/NoteCardView.swift` + per-app style: the phone gets the iPad/Mac Import · Record · ✎ verb row and loses the red mic corner button; all three on the phone's grey `Palette.bg.phone`; status pill only while working/broken; display-only three balls on rows; day groups everywhere; chip bar All · Needs Work N · Done N · Unrated N + icon-only Filter; the "ready to review · to process" line and "Mark all as Passing" are REMOVED (Process button unaffected). Fix the two BUGS §4 leads on the way: unrated rows double-dimmed (MemoCard 0.55 × NoteCardView 0.62) and the Mac untitled-row first-line repeat (QueueRowView). Test the chip counts and row inputs in a new `NotesListModelTests` (desktop target).
check: `grep -rqE "class NotesListModelTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ! grep -rqE "Mark all as Passing|ready to review" Skrift_Native --include='*.swift'`

### Q27 [auto] (done) recovery sweep quarantines unreadable orphans, never deletes them
spec: C99 C288
needs: Q16
gate+: yes
node: AuditFix2
do: Device evidence 2026-09-24 (iPhone 13, Dev build 171, devlog 15:34:49): the Q16 launch sweep logged `rec recover-failed — no readable audio — cleaned 1 file(s)` for 5 legacy pre-segment `rec_tmp_*` orphans and DELETED them. An m4a with no moov atom is unreadable to AVFoundation but often rescuable (`tools/rescue-lost-recordings.py`), so on prod's first launch this would destroy his real orphaned recordings. Change the failed-recovery branch: MOVE every unreadable orphan (rec_tmp_*, rec_seg_*, rec_ckpt_*) into `Documents/QuarantinedRecordings/` with a sidecar JSON (take id, sizes, first-seen date), never delete it; log `rec quarantined`; a later explicit user action or the rescue tool is the only way out. C288's cleanup now means "out of the recording dir", not "deleted". Test in a NEW `RecoveryQuarantineTests` (phone target): a truncated m4a is quarantined byte-identical, nothing is removed.
check: `plan/mtest.sh RecoveryQuarantineTests && ! grep -rnE "removeItem" Skrift_Native/SkriftMobile/Features/Recording/RecordingRecovery.swift`

### Q28 [auto] (done) build the tag editor on phone, iPad and Mac
spec: C241 C93 C240
needs: Q26 Q3
gate+: yes
do: Build the signed `Skrift_Native/SkriftDesktop/mocks/tag-ui-revamp.html` (D139 picks: inline field in the tag row, no sheet; tap-twice remove + 4 s Undo, Mac ✕ on hover; own row under the title, 14 pt / 30 pt) as ONE shared view in `Shared/UI/` with a per-app style (C240). Tag rules single-sourced in Shared: comma/newline split, `#` stripped ONCE, case kept on first use, and a new tag whose case-folded form exists ANYWHERE in the library reuses that spelling (D139). Fix the three BUGS §4 tag leads on the way (Mac `NoteProperties.swift:460` lowercases on pick; no case fold; `Memo.splitTagInput` strips every `#`). Test in a new `TagRulesTests` (desktop target).
check: `grep -rqE "class TagRulesTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh`

### Q29 [auto] (done) build edit conflicts: detect, prompt, keep both
spec: C98 C242
needs: Q26
gate+: yes
do: Build the signed `Skrift_Native/SkriftDesktop/mocks/Q4-edit-conflict.html` (D139): a same-note edit on two devices that meet after being apart becomes a conflict record, never a silent overwrite (C98) — only body, title and tags conflict; rating, lock and reminder stay newest-wins; new notes never conflict. The note shows the "2 versions" pill in the list and the prompt on open (Keep both = default/Return; Keep this device / Keep the other); editing blocked until picked, "Later" leaves the amber banner; the unkept version goes to Recently Deleted as a "replaced" row (14 days); the Mac holds processing/export until picked. Test in a new `EditConflictTests` (desktop target): two in-memory stores with diverging edits → a conflict record, no loss.
check: `grep -rqE "class EditConflictTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh`

### Q30 [auto] (done) body v2: photo in a sentence's first second goes before it
spec: C11 C10
needs: Q11
gate+: yes
node: V2Core
do: Apply D140 in `Shared/BodyV2/`: a picture whose `offsetSeconds` falls within the first 1.0 s of a spoken sentence lands BEFORE that sentence, otherwise after it. Re-run the v2 harness: resolve the `registrationConflicts` / `expectBodyConflicts` carve-outs in `BodyV2HarnessTests` for pic-at-start, pic-ocr-text, pic-three-spread (each either now matches its expect_body or stays listed with the reason); D141: drop `pic-in-task-list` from R95 — that edits the protected `expected-differences.json`, which Tuur approved (D141), so the dispatcher hand-merges after checking it is the ONLY protected edit. Regenerate `plan/reads/body-v2.md`. ingress-p3 stays open (no clip boundaries in the fixture).
check: `./gate.sh && test -s plan/reads/body-v2.md`

### Q31 [auto] (done) body v2 everywhere: the last four write sites + keep leading indentation
spec: C10 C19 C170
needs: Q13
gate+: yes
node: V2Core
do: Q13 finding (plan/RUN.md): switch the four write sites Q13 left on v1 to `BodyV2.committed` — dictation text append, voice-annotate text append, Mac text imports, the Mac editor commit. Fix the v2 bug: `BodyV2Text.normalised` must collapse whitespace runs INSIDE a line only (C19) and keep leading indentation, so nested lists survive; add a corpus-style test with a nested list. Remove the two stopgaps: `ASRPostProcess`'s v1 `ImageMarkers.insert` call, and the typed-body-with-photo passed to `BodyV2Thumbnail.pick` as `.speech` (make `pick` handle a typed body that has a picture, C170). Test in a new `BodyV2WriteSitesTests` (desktop target).
check: `grep -rqE "class BodyV2WriteSitesTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ! grep -rnE "ImageMarkers\.insert\(" Skrift_Native/Shared/Pipeline/ASRPostProcess*.swift && ./gate.sh`

### Q32 [auto] (done) the .data attachment lane obeys ownership too
spec: C58 C54
needs: Q19
gate+: yes
node: AuditFix2
do: Q19 finding: `VaultWrite.writeAsset`'s `.data` branch (phone MemoAsset blobs) still overwrites an existing vault file blind. Route it through the same `VaultAttachmentOwnership` check Q19 added for `.file` (byte-identical → no-op; foreign file → never touched, ours lands under the id8 name with embeds rewritten). Test in a new `DataAttachmentOwnershipTests` (desktop target), temp dirs only (never the real vault).
check: `grep -rqE "class DataAttachmentOwnershipTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh`

### Q33 [auto] (done) list visual check against the signed mock + UI tests follow the verb row
spec: C117 C240
needs: Q26
node: V2Core
do: Q26 was never looked at on screen. Seed the synthetic corpus (`-corpus test-fixtures/corpus`, never real data) and render: the phone list (iPhone 17 sim screenshot, light + dark), the iPad list (iPad sim), and the Mac sidebar (the desktop `-snapshot` harness or a Dev-app screenshot). Compare each against the "One list" tab of `Skrift_Native/SkriftDesktop/mocks/one-notes-list.html` by LOOKING at the PNGs: verb row, chip bar with counts + icon Filter, grey ground, day groups, display-only balls, pill only while working/broken, no clipping/overflow, long titles, empty list. Fix what differs. Also update `SkriftMobileUITests` RecordingUITests + ConversationMockUITests to tap Record in the verb row (the corner FAB `new-recording-button` is gone, D136). Commit the PNGs under `plan/reads/list-q33/`.
check: `test $(ls plan/reads/list-q33/*.png | wc -l) -ge 4 && ! grep -rqE "new-recording-button" Skrift_Native/SkriftMobile/SkriftMobileUITests && ./gate.sh`

### Q34 [auto] (done) vault embeds follow a disambiguated attachment name
spec: C58 C54 C56
needs: Q32
gate+: yes
node: AuditFix2
do: Q32 finding: when `VaultAttachmentOwnership` writes our attachment under an id8-disambiguated name (a foreign file holds the original name), the note's markdown embed on the commit path still points at the ORIGINAL name, so Obsidian shows the foreign file. Make the written name flow back: every `![[…]]` / link the exporter writes for that attachment uses the name actually written, on both apps' export paths (`VaultWrite` commit path, Mac `VaultExporter`, phone publisher). Test in a new `AttachmentEmbedNameTests` (desktop target, temp dirs only): foreign `IMG_0001.jpg` present → our photo lands as `IMG_0001 <id8>.jpg` AND the note embeds exactly that name.
check: `grep -rqE "class AttachmentEmbedNameTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh`

### Q35 [auto] (done) Mac sidebar reshoot from the synthetic corpus: left-edge clip, quiet rows, iPad fade line
spec: C117 C4
needs: Q33
node: V2Core
do: Q33 finding. (1) DELETE `plan/reads/list-q33/mac-sidebar-dark.png` from the tree — it shows Tuur's real Dev notes. (2) Render the Mac sidebar ONLY from a fresh, isolated store seeded with the synthetic corpus (`-corpus test-fixtures/corpus`, C4): point the Dev app / `-snapshot-shell` at a temp store directory so the live Skrift Dev store (and its CloudKit data) is never read; if the harness cannot isolate the store, stop and report. (3) Look at the new PNG: if the sidebar's left edge is clipped (Q33 showed "ODAY", "UE 22 SEP", cut "All" chip), fix the layout; if it is a harness artefact, prove it with a real window screenshot of the same isolated store. (4) Mac unrated (quiet) rows get the snippet + chips of the signed mock's "One list" tab (`Skrift_Native/SkriftDesktop/mocks/one-notes-list.html`), duration as a chip. (5) Re-shoot the iPad list to confirm the always-on "starts fading" line is gone. Commit the new PNGs under `plan/reads/list-q35/`.
check: `test ! -e plan/reads/list-q33/mac-sidebar-dark.png && test $(ls plan/reads/list-q35/*.png | wc -l) -ge 2 && ./gate.sh`

### Q36 [auto] (done) tag editor matches the signed mock: Mac keyboard menu, Undo toast, screenshots
spec: C241 C117 C4
needs: Q28
node: V2Core
do: Q28 finding: bring the built tag editor to the signed `Skrift_Native/SkriftDesktop/mocks/tag-ui-revamp.html` (D139): restore the Mac's keyboard-navigable suggestion menu (↑↓, Tab/Return accept, a "Create #x" row) that Q28 replaced with a chip strip; Undo as the mock's floating 4 s toast, not an inline row. Rewrite or retire `SkriftMobileUITests/TagSheetUITests.swift` (it drives the deleted sheet and the pre-2026-08-27 "destination words refused" rule; destination words ARE tags per C93). Screenshots from the SYNTHETIC corpus only in an isolated store (`-inMemoryStore -corpus test-fixtures/corpus`, never the live Dev store): phone note header with tags, the armed-remove state, the Undo toast, the Mac menu open — LOOK at each vs the mock and fix differences. Commit PNGs under `plan/reads/tags-q36/`.
check: `test $(ls plan/reads/tags-q36/*.png | wc -l) -ge 4 && ./gate.sh`

### Q37 [auto] (done) Mac sidebar left-edge verdict from a real window + one chip count on every device
spec: C117 C4 C240
needs: Q35
gate+: yes
node: V2Core
do: Q35 finding. (1) The dispatcher sees the Mac sidebar's left ~12 px cut in `plan/reads/list-q35/mac-sidebar-dark.png` ("ODAY", "AT 19 SEP", logo, "All" chip). Launch the DEV Mac app built from your worktree against an ISOLATED store seeded from the synthetic corpus (never the live Dev store, never /Applications/Skrift.app; quit it after; one instance only) and capture the real window with `screencapture -l <windowid>`. If the left edge is cut there, fix the layout; if not, fix `-snapshot-shell`'s crop so its PNG matches the real window. (2) The same corpus shows "Needs Work 6 · Unrated 5" on the Mac and "Needs Work 99 · Unrated 6" on the iPad: find why, and make every device count from the shared `NotesListModel` on the same inputs (one definition per chip), with a test in a new `ChipCountParityTests` (desktop target) feeding the corpus. Commit PNGs under `plan/reads/list-q37/`.
check: `test $(ls plan/reads/list-q37/*.png | wc -l) -ge 1 && grep -rqE "class ChipCountParityTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh`

### Q38 [auto] (done) edit conflicts also catch edits to a Mac-polished note
spec: C98 C242
needs: Q29
gate+: yes
do: Q29 finding: conflict detection watches `Memo` only, but a body edit on a Mac-polished note lands in `MemoEnhancement.copyedit` — the most common edit. Extend the `MemoEditHead` / edit-vector scheme to the polished body (the text he actually edits), so two devices editing the same polished note apart yield a conflict record, not an LWW overwrite. Keep new fields optional/additive (CloudKit). Test in a new `PolishedEditConflictTests` (desktop target, two in-memory stores).
check: `grep -rqE "class PolishedEditConflictTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh`

### Q39 [auto] (done) edit-conflict prompt, banner and pill rendered and checked against the mock
spec: C242 C117 C4
needs: Q29
do: Q29 never rendered its UI. From an ISOLATED store seeded with the synthetic corpus plus one forced conflict (never the live Dev store), capture: the phone prompt, the phone banner after "Later", the list row "2 versions" pill, the Mac prompt; LOOK at each against `Skrift_Native/SkriftDesktop/mocks/Q4-edit-conflict.html` and fix clipping/overflow/differences. Confirm editing is blocked on the iPad workbench until a pick. Commit PNGs under `plan/reads/conflict-q39/`.
check: `test $(ls plan/reads/conflict-q39/*.png | wc -l) -ge 4 && ./gate.sh`

### Q40 [auto] (done) old-note normalisation covers the polished text + v2 drops v1's leading space
spec: C10 C19
needs: Q14
gate+: yes
node: V2Core
do: Q14 finding. (1) The one-time migration (`Shared/BodyV2/BodyNormaliseMigration.swift`) rewrites only `Memo.transcript` on the phone; the Mac-polished `MemoEnhancement.copyedit` (the text he reads and edits) keeps v1's mid-sentence markers. Apply the same guarded, undoable, once-per-note rewrite to the polished text on both apps (words/markers in == out; local ledger; editedAt untouched). (2) `BodyV2.committed` treats v1's wrap `one.

[[img_001]]

 That` as finished and keeps the leading space, so the body still breaks C10: strip the leading horizontal run of a paragraph that follows a picture paragraph (C19), and drop the migration's plain-marker-move fallback once v2 handles it. Test in a new `PolishedNormaliseTests` (desktop target) incl. `conv-with-picture`.
check: `grep -rqE "class PolishedNormaliseTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh`

### Q41 [auto] (done) tag Undo toast centred at the bottom of the screen, not on the tag row
spec: C241 C117
needs: Q36
node: V2Core
do: Q36 finding: on the phone the "Removed #x · Undo" toast is overlaid on the tag row, so it runs off the left screen edge and covers the remaining chips (`plan/reads/tags-q36/phone-undo-toast.png`). Hoist the toast to the note screen (phone + iPad) and the Mac note column so it is a centred pill near the bottom, above the player/keyboard, as in `Skrift_Native/SkriftDesktop/mocks/tag-ui-revamp.html`; also show per-tag usage counts in the Mac menu rows as the mock does. Re-shoot the toast on the phone (synthetic corpus, isolated store) and LOOK at it; commit under `plan/reads/tags-q41/`.
check: `test $(ls plan/reads/tags-q41/*.png | wc -l) -ge 1 && ./gate.sh`

### Q42 [auto] (done) a first touch with no word change never counts as a conflicting edit
spec: C98
needs: Q38
gate+: yes
do: Q38 finding: `EditConflicts.recordEdit` stamps the first touch on a never-stamped (pre-Q29) note even when no words changed, so a first audio trim / annotation counts as a word edit and can produce a false "2 versions". Seed the stamp from the current words WITHOUT bumping the edit vector on first touch; bump only when words actually differ. Same for `recordPolishedEdit`. Also make the Mac `MacCloudEditSync.flush` compare the polished body before/after `unlinkToSpoken` round-trip so a title-only edit is not a polished edit. Test in a new `ConflictFirstTouchTests` (desktop target).
check: `grep -rqE "class ConflictFirstTouchTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh`

### Q43 [auto] (done) quick-note screen rendered and matched to the note editor and the mock
spec: C112 C117 C4
needs: Q7 Q46
node: V2Core
do: Q7 finding: the quick note opens a NEW minimal `QuickNoteView` (title field + TextEditor, no accessory bar) that was never rendered. The signed `Skrift_Native/SkriftDesktop/mocks/quick-note.html` shows the app's normal note screen, empty, keyboard up, cursor in the body. Either route the quick note into the normal note editor in a draft state (preferred: one editor) or make QuickNoteView match it; keep first-keystroke creation + empty discard (QuickNoteTests must stay green). Screenshot on the iPhone 17 SIM only (synthetic corpus, isolated store; the sim renders offscreen) and LOOK at it: keyboard up, cursor in body, nothing clipped. Commit under `plan/reads/quicknote-q43/`. NEVER `open -a` a Skrift app, never capture the whole screen.
check: `test $(ls plan/reads/quicknote-q43/*.png | wc -l) -ge 1 && plan/mtest.sh QuickNoteTests && ./gate.sh`

### Q44 [auto] (done) tag Undo toast sits just above the player and keyboard, over no content
spec: C241 C117
needs: Q41
do: Q41 finding: `plan/reads/tags-q41/phone-undo-toast.png` shows the toast centred horizontally but floating mid-screen over the Importance card. Place it as the mock does (`Skrift_Native/SkriftDesktop/mocks/tag-ui-revamp.html`): a centred pill anchored to the bottom safe area, just above the player (keyboard down) or above the keyboard accessory bar (keyboard up), never covering note content; same on iPad and the Mac column. Re-shoot on the iPhone 17 sim (synthetic corpus, isolated store) with the keyboard up AND down; LOOK at both. Commit under `plan/reads/tags-q44/`. NEVER `open -a` a Skrift app; never capture the whole screen.
check: `test $(ls plan/reads/tags-q44/*.png | wc -l) -ge 2 && ./gate.sh`

### Q45 [auto] (done) non-word edits (audio trim, annotation) never stamp words for conflicts
spec: C98
needs: Q42
gate+: yes
do: Q42 finding: the first-touch false conflict can't be fixed inside `recordEdit` without breaking protected tests. Fix it at the call sites: every `markEdited` caller that does not change the words (audio trim, audio append's non-text part, voice annotation audio, photo add/remove/markup, rating, lock, destination) passes `stampWords: false`, as `ReminderSheet` already does. Grep every `markEdited(` call on both apps, list them in the report with the value chosen. Test in a new `NonWordEditTests` (desktop target): a pre-Q29 note trimmed on A while B edits words → no conflict.
check: `grep -rqE "class NonWordEditTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh`

### Q46 [auto] (done) phone test target builds again (onCommit accepts the old no-argument form)
spec: C98
needs: Q45
do: Regression from Q45: `NoteBodyView.onCommit` is now `(Bool) -> Void` and the protected `SkriftMobileTests/NoteBodyTests.swift` + `QuotePresentationTests.swift` call `onCommit: {}` (17 sites), so the phone test target no longer compiles. Without touching any protected file, make the zero-argument form compile again (e.g. an extra `init` overload taking `onCommit: @escaping () -> Void` that forwards as `{ _ in onCommit() }` treating it as wordsChanged = true, or a default) while Q45's `wordsChanged` path keeps working. Prove with `xcodebuild build-for-testing` for SkriftMobile AND two phone test classes.
check: `plan/mtest.sh NoteBodyTests && plan/mtest.sh QuickNoteTests && ./gate.sh`

### Q47 [auto] (done) quick note opens the full note screen; ✎ never opens an old note; toolbar stays
spec: C112 C114 C43
needs: -
gate+: yes
do: D145 + BUGS §3 (build 172): the quick note must be the FULL note screen (MemoDetailView in a draft state: date, tags, importance visible, cursor in body, keyboard up) — retire the separate `QuickNoteView`; keep first-keystroke creation + empty discard. Fix: the first ✎ tap opened an OLD note (the recovered recording) — find why the route resolved to an existing memo (stale deep link / draft id / selection state) and add a test; the keyboard accessory bar must never disappear while typing. QuickNoteTests stay green; add `QuickNoteRouteTests` (phone target). Sim screenshot, synthetic corpus, isolated store; LOOK; commit under `plan/reads/quicknote-q47/`.
check: `plan/mtest.sh QuickNoteRouteTests && plan/mtest.sh QuickNoteTests && test $(ls plan/reads/quicknote-q47/*.png | wc -l) -ge 1 && ./gate.sh`

### Q48 [auto] (done) filter chips switch with one consistent animation; verb row a little bigger
spec: C117 C240
needs: -
do: D145 + BUGS §3 (build 172): switching chips (All / Needs Work / Done / Unrated) animates differently per chip (Needs Work flies up from the bottom, Done's date headers fly in last). Make a chip switch one consistent, quick transition on all three devices (no per-section insertion animations; list identity stable). Make the Import · Record · ✎ row a little taller (Tuur: "a bit small") on phone and iPad. Sim screenshots before/after; LOOK; commit under `plan/reads/list-q48/`.
check: `test $(ls plan/reads/list-q48/*.png | wc -l) -ge 1 && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q49 [tuur] (done) mockup: one filter mechanism instead of chips + Filter icon
spec: C117
needs: -
do: D145: "two types of filters… difficult or tricky". One page showing today's chip bar + Filter icon (drawn from source) and 2–3 ways to make it ONE mechanism (e.g. chips carry everything, or one Filter menu with the chips inside), phone + Mac.
check: Tuur clicked through it and said go.

### Q50 [tuur] (dead) mockup: one compact note header (date + place, tags, importance)
spec: C117 C94
needs: -
do: Tuur 2026-09-25 on build 172: the importance card takes a lot of vertical space, tags sit above it, the date above that "with time but without location for some reason". Mock the note header drawn from source today, then 2–3 compact options that fold date + place + tags + importance into one top area ("not sure if that will look good" — show it honestly), phone + iPad + Mac. Also check why the location is missing on the date chip.
check: Tuur clicked through it and said go.

### Q51 [tuur] (done) mockup: Apple Notes import wizard (for when Skrift replaces Notes)
spec: C117 C238
needs: -
do: Tuur 2026-09-25: "a proper import wizard with full mockups… once I trust Skrift to be good enough to replace it". First read what the app imports from Apple Notes today (source) and the shared-import clauses (C238, C66–C79, C123–C128, C140–C147); then a clickable multi-step wizard mock: pick folders/notes, preview mapping (attachments, checklists, tags, dates), dry-run count, import, a report of what didn't map. LATER: not before the perf + editor work; Tuur decides when.
check: Tuur clicked through it and said go.

### Q52 [auto] (dead) typing never re-renders the notes list behind the editor (R92)
spec: C277 C282
needs: -
gate+: yes
node: AuditFix2
do: Measured 2026-09-25 (`plan/perf-measured.md`, phone typing, Dev 172, FAST state): 93% of SkriftMobile samples on the main thread; the top app-code cost while typing is the notes LIST behind the editor re-evaluating on every keystroke — `MemosListView.body`/`notesRoot` (258 samples), `listContent` (225), recomputing `allTags`, `allMemos`, `backlinkedIDs`, `filterChips` — plus `MemoPageView.body` (174), `NoteBodyTextView.layoutSubviews` (37), `NoteBodyView.Coordinator.sanitizeTypingAttributes` (33), `NotesRepository.save` (15). This is R92. Make the list's derived collections cached/memoised and invalidated only when the memo set changes (not on a body edit), so a keystroke in the editor does not re-run the list's body; debounce the editor's save like the phone's 1 s `commitDraft`. Prove with a test in a new `ListNotReRenderedWhileTypingTests` (desktop target, shared model) and a re-recorded trace in the laggy state if Tuur can reproduce it.
check: `grep -rqE "class ListNotReRenderedWhileTypingTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh`

### Q53 [auto] (done) phone typing: nothing heavy runs per keystroke
spec: C277 C282
needs: -
gate+: yes
node: AuditFix2
do: Merge with Q52's scope. From `plan/sweep-a-editor.md` + `plan/sweep-b-list-launch.md` + `plan/perf-measured.md`: debounce Quick Note's per-keystroke `context.save()` (QuickNoteDraft.swift:20-31, QuickNoteView.swift:104,115) like the editor's 1 s commit; stop `NotesRepository.allTags()` refetching every memo while typing (NotesRepository.swift:164-170 ← MemoDetailView.swift:1278) — cache it, invalidate on memo-set change; parse `SpeakerTranscript` once per text with a cached regex (MemoDetailView.swift:914,1564,1612,1633,1749); fire `recomputeSpans()` once per commit, not twice (MemoDetailView.swift:932,935,1171-1177); plus Q52 (the list behind the editor must not re-render per keystroke). Test in a new `TypingPathCostTests` (desktop target, shared code) asserting each runs at most once per commit.
check: `grep -rqE "class TypingPathCostTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteRouteTests && ./gate.sh`

### Q54 [auto] (done) phone notes list: one scan per render, not dozens
spec: C278
needs: -
gate+: yes
node: AuditFix2
do: From `plan/sweep-b-list-launch.md`: `filterChips` re-runs uncached `chipCounts` per chip (MemosListView.swift:846-895, ~16 full-corpus scans per render) — compute once per render/memo-set change; hoist per-row lookups (`enhancedTitleByMemoID`, `searchFadingIDs`, `backlinkedIDs`, partition — R92/C278) into one pre-render pass; use the shared `NotesListModel.dayGroups` instead of the hand-rolled `groups(from:)` (MemosListView.swift:1171-1183); delete the ~90 dead MemoCard helper lines it lists. Test in a new `ListRenderCostTests` (desktop target) counting scans per render.
check: `grep -rqE "class ListRenderCostTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteRouteTests && ./gate.sh`

### Q55 [auto] (done) phone launch and foreground do only what changed
spec: C279
needs: -
gate+: yes
node: AuditFix2
do: From `plan/sweep-b-list-launch.md` + SPEC R91/R93/R94: `SkriftApp` runs ~10 main-actor sweeps unconditionally on every launch AND foreground — gate each on what changed, move the heavy ones off the main actor; `AppPaths.recordingsDirectory` calls `createDirectory` on every read (R93) — create once; `AssetMaterializer.captureMissing` unscoped fetch (R91) — scope it. Keep the recording-recovery sweep FIRST (C99). Test in a new `LaunchWorkTests` (phone target) asserting a foreground with no changes runs no full-store sweep.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh LaunchWorkTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh RecoverySweepTests && ./gate.sh`

### Q56 [auto] (done) Mac: sidebar, editor and export stop blocking the main thread
spec: C277 R90
needs: -
gate+: yes
node: AuditFix2
do: From `plan/sweep-d-mac.md` + R90: `backlinkedIDs` recomputed per quiet row in SidebarView (SidebarView.swift:79,641,718) — once per render; `VaultExporter.export` runs file copies + compile + vault write synchronously on main, and multi-select export loops it (ProcessingCoordinator.swift:331 → VaultExporter.swift:69-186, SidebarView.swift:981) — make it async off-main like IngestService; `TagLibrary` full fetch as a body expression in NoteProperties.swift:53-54 — cache; R90: BodyTextView restyles the full document and writes the model per keystroke — scope restyle to the edited paragraph and debounce the model write (1 s). Remove the dead `quietMeta`/`process(_:)` in SidebarView. Test in a new `MacMainThreadCostTests` (desktop target).
check: `grep -rqE "class MacMainThreadCostTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh`

### Q57 [auto] (done) audiobooks: no full decodes on main, linear alignment, quiet player ticks
spec: C218
needs: -
gate+: yes
node: AuditFix2
do: From `plan/sweep-c-record-books-share.md`: `localAlignmentSignature` full-decodes every alignment sidecar on @MainActor on every reconcile — fired by each bookmark tap (AudiobookCloudSync.swift:611-620 ← AudiobookPlayerView.swift:482, ChaptersBookmarksSheet.swift:97) — use cached file stats like its transcript twin (:421-432); `BookAlignment.mergeSentences` is O(n²) (BookAlignment.swift:723-747) — make it linear (sorted merge) without changing output (prove on an existing alignment test); `AudiobookSession` is ObservableObject re-rendering the whole player every 0.5 s tick — move to @Observable with the tick isolated, like LiveRecordingService. Load shared photos/audio concurrently in SharePayloadLoader.swift:227-264,345-370. Test in a new `AudiobookCostTests` (phone target).
check: `plan/mtest.sh AudiobookCostTests && ./gate.sh`

### Q58 [auto] (done) twins and dead code from sweep E fixed (vocab re-warm, lock predicate, tombstones, durations)
spec: C240 C50
needs: -
gate+: yes
node: AuditFix2
do: From `plan/sweep-e-shared-twins.md`, `plan/sweep-d-mac.md` and BUGS §4 (2026-09-25 rows): phone re-warms `VocabularyBooster` after adopting a synced word (SkriftMobile/Services/VocabularyCloudSync.swift:21-24, like the Mac :63-69); Mac lock check routes through `NoteVisibility.contentVisible` (LockGate+PipelineFile.swift:6-9); call `NamesStore.pruneOldTombstones` (Shared/Naming/NamesStore.swift:277-291) on a sensible cadence (keep names.json byte-compatible, LWW + voiceprint union intact); ONE duration formatter so the Mac header/player agree with the sidebar past 60 min; cache the per-call regexes in Shared/Pipeline/Tags (VaultTagScanner/TagMatcher) and SpeakerTurnStyle.swift; surface or delete the unused ePub DRM result. Test in a new `SweepETwinsTests` (desktop target).
check: `grep -rqE "class SweepETwinsTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteRouteTests && ./gate.sh`

### Q59 [auto] (done) split the three oversized files along clear seams (no behaviour change)
spec: C240
needs: Q53 Q54 Q56
node: AuditFix2
do: Elegance pass after the perf items land (sweeps A, B, E): split `SkriftMobile/Features/MemoDetail/MemoDetailView.swift` (~2,560 lines, one struct with 138 members), `SkriftMobile/Features/MemosList/MemosListView.swift` (~1,780) and `Shared/Naming/Sanitiser.swift` (781, four jobs in one enum) into files along the seams the sweeps name. Pure moves + extracted subviews/types; no behaviour change; every existing test stays green unchanged; phone `build-for-testing` passes.
check: `test $(wc -l < Skrift_Native/SkriftMobile/Features/MemoDetail/MemoDetailView.swift) -lt 1200 && test $(wc -l < Skrift_Native/SkriftMobile/Features/MemosList/MemosListView.swift) -lt 900 && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteRouteTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q60 [auto] (done) dead-code scan with Periphery on both apps (report only)
spec: C240
needs: -
node: AuditFix2
do: Tuur 2026-09-25: "clean away the bullshit and just keep to the core and be very careful about it". Install Periphery (Homebrew, approved by Tuur) and scan SkriftMobile (+ extensions) and SkriftDesktop (full MLX scheme). Write `plan/periphery.md`: totals, then findings grouped by folder with line counts, each marked SAFE (no references, not @objc/intent/entitlement/Codable/SwiftData/preview/test-only), CHECK (reflection, AppIntents, SwiftData models, string-based lookups, DEBUG harness) or KEEP (false positive + why). No deletions in this item.
check: `test -s plan/periphery.md`

### Q61 [auto] (done) remove the SAFE dead code from plan/periphery.md, folder by folder
spec: C240
needs: Q60
node: AuditFix2
do: Tuur 2026-09-25: "clean away the bullshit… be very careful". Delete the SAFE list in `plan/periphery.md` (245 items, ≤ ~1,976 lines) one folder per commit. Before each deletion re-grep the symbol across the WHOLE repo incl. tests, Info.plists, entitlements, .intentdefinition, AppShortcuts, storyboards and string-based lookups; anything referenced moves to CHECK in the report instead. Never touch CHECK/KEEP items, @Model types, Codable fields, AppIntents or anything under Tests. After each folder: `./gate.sh` and phone `xcodebuild build-for-testing`; a red folder is reverted, not fixed forward. Update `plan/periphery.md` with what was removed per commit and the real line count removed.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteRouteTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet) && grep -qE "removed" plan/periphery.md`

### Q62 [tuur] (done) decide: wire in or delete the 116 built-and-tested-but-unused functions
spec: C240
needs: Q60
do: `plan/periphery.md` CHECK section: 116 functions have their own tests but no caller in the app (like `NamesStore.pruneOldTombstones`). A sitting sheet groups them by feature with one line each (what it was for, who built it when — git log), and Tuur picks per group: WIRE IN (becomes an auto item) or DELETE (with its tests; protected-test change approved per group).
check: Tuur picked per group.

### Q63 [tuur] (tuur) Mac typing feel after Q56: headings and links while typing
spec: C277 R90
needs: Q56
do: Q56 made BodyTextView restyle only the edited paragraph and debounce the full pass 1 s, so typing inside a heading or link shows plain styling for up to 1 s (never rendered on screen). Install Skrift Dev on the Mac from the session branch (build → pkill → ditto to /Applications/Skrift Dev.app → open), type in a long note inside a heading and a link. If the flash bothers him: keep the edited paragraph's heading/link styling live. ALSO (speed sweep 2, plan/perf2/f-mac-ui.md M6b, static read): type in a long note, then within 1 s drag the sidebar or resize the window — does any just-typed text disappear?
Also, in the same Dev window: does the sidebar's left edge cut the first letter of every row and day header ("ODAY", "AT 19 SEP")? The headless snapshot always shows it (Q35, Q37, Q65); a real window has never been checked.
check: On the Mac, type a heading and a link in a note. Does the brief flash while typing feel fine, or should it go?
ask: On the Mac, type a heading and a link in a note. The styling can lag up to a second behind your typing. Does that bother you? Also: right after typing, drag the sidebar or resize the window. Do any letters you just typed disappear?

### Q64 [tuur] (done) iPhone 17 Pro: quick note full screen, ✎ opens a new note, toolbar stays
spec: C112 C114
needs: Q47
do: Q47's two device fixes are unverified (NoteRoute replaces the desyncable draft-id pair; NoteAccessoryBar intrinsicContentSize for the vanishing toolbar). Dev 190 is on the iPhone 17 Pro (Q407); tap ✎ right after launch and after a recovered recording exists; type a paragraph; check date, tags and importance show and the toolbar never leaves.
check: On the phone, open a quick note full screen and tap ✎. Does it open a new note with the toolbar still up?
ask: Start a quick note and expand it to full screen, then tap the pencil button. Does a fresh empty note open, and does the bar above the keyboard stay visible?

### Q65 [auto] (done) Mac sidebar looks like the phone list: grey background, white card rows (D135 miss)
spec: C115 C240
needs: -
do: D135 said all three devices use the iPhone's GREY list background; Tuur 2026-09-26 ("why are the background colors different again? I already mentioned this once… the way it looks on the phone I like best"): the Mac sidebar still draws flat rows on its own grey (seen in the Q49 mock, drawn from source). First screenshot the real Mac sidebar next to the phone list (synthetic corpus, isolated store) and confirm the difference; then make the Mac sidebar match the phone: the same grey ground and white rounded card rows from the shared NoteCardView style, same spacing, light + dark. After-screenshots of both side by side, LOOK, commit under `plan/reads/list-q65/`.
check: `test $(ls plan/reads/list-q65/*.png | wc -l) -ge 2 && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q66 [auto] (done) build one filter mechanism, option A of the Q49 mock, on phone, iPad and Mac
spec: C117 C115
needs: Q65
do: Build option A of the signed mock `Skrift_Native/SkriftDesktop/mocks/Q49-one-filter.html` (Tuur 2026-09-26: "one filter bar I pick A"): the chip row carries everything — after the four status chips come Date and Unsynced chips; the Filter icon and sheet go; sort becomes a word at the end of the row (`Newest ↓`) that steps to the next sort on each tap; the row scrolls sideways when it does not fit. Removes the duplicate Unrated toggle (BUGS §2 "The phone filters Unrated twice"). Phone, iPad and Mac through shared code where the list already is. Take ONLY the chip row from the mock: its Mac panel draws the rows transparent, which is wrong — the app's Mac rows are already white cards on the phone's grey (Q65). Screenshots phone + Mac, LOOK, commit under `plan/reads/filter-q66/`.
check: `test $(ls plan/reads/filter-q66/*.png | wc -l) -ge 2 && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteRouteTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q67 [tuur] (dead) mockup: Apple Notes import as a triage, 10 notes at a time (rate / skip / delete)
spec: C117 C238
needs: -
do: Revise `Skrift_Native/SkriftDesktop/mocks/Q51-apple-notes-import.html` to Tuur's 2026-09-26 answer: "it should happen in groups of 10, where you can go through them and rate them as they come in, or skip import / delete them". Replace the quiet-vs-rated question with a triage: the import brings 10 notes at a time; each shows its preview and three actions (rate with the three balls / skip = don't import / delete); next batch after the ten. Keep the today panel, the drawings marker and the end report. Phone + Mac. The A/B/C and option buttons must actually work on tap in the artifact viewer (storage wrapped in try/catch). Publish, one numbered question at the top.
check: Tuur clicked through it and said go.

### Q68 [auto] (done) Mac list rows show the note's tag chips like the phone (QueueRowView.cardModel)
spec: C115
needs: -
gate+: yes
do: Q65 (2026-09-26) found the Mac row carries fewer chips than the same note's phone row: `QueueRowView.cardModel` fills only duration/source chips, never the note's tags (#studio etc.) — possibly because `PipelineFile` does not carry tags the way `Memo` does. Feed the Mac row the same tag chips the phone row gets, from the same shared source (one card model, C115). Test that one note yields the same chip list on both apps' card models (desktop test target); screenshot the Mac sidebar from the synthetic corpus, LOOK, commit under `plan/reads/list-q68/`.
check: `test $(ls plan/reads/list-q68/*.png | wc -l) -ge 1 && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q69 [auto] (done) a Mac import never diarizes on its own (C102 opt-in); one label per person; no raw markup in list snippets
spec: C102
needs: -
gate+: yes
do: Tuur 2026-09-27 on the prod Mac: videos dragged in from Photos came out diarized ("the automatically did diarization. no good"); C102 = diarization is opt-in per note. First check the CURRENT branch (prod is older): find the path that diarizes a Mac import without the user's toggle (IngestService / BatchRunner / DiarizationSidecar / MemoCloudIngest) and write a failing desktop test (a Mac-imported video with no opt-in comes out as a monologue). Fix. On the same screen one person showed as both "Tiuri Hartog" and "Tiuri", and list snippets showed raw `**Speaker 1:**` / `[[Tiuri Hartog]]` markup — fix both if they reproduce from the synthetic corpus, else log what you found. NEVER run SkriftDesktopUITests (they take the real mouse); Mac proof = unit tests + full build + headless `-snapshot-shell`.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q70 [tuur] (dead) mockup: compact note header, two versions — B refined, and today's layout squeezed
spec: C117 C94
needs: -
do: Tuur 2026-09-27 on `mocks/Q50-compact-note-header.html`: A no ("the balls carrying [no] label, nobody will know what to do with them"), C no ("I don't like it to take part of the title"), B "probably the best one" — Not rated + the orange "starts fading on 25 Oct · Rate it to keep it" line, one tap to Passing. "Either we're going with B or we just go with what is today but then have it take up way less vertical space… so make two versions." Version 1 = B refined; version 2 = today's header (date chip row, tags, importance card with labels and the sync line) squeezed: cut the gaps between Not rated / Importance / the balls / the sync line. Phone + iPad + Mac, voice note AND typed note, each frame showing its height in pt against today's 243 pt. Every control must respond on tap in the artifact viewer. Publish; one numbered question: "1 or 2?"
check: Tuur clicked through it and said go.

### Q71 [tuur] (done) mockup: Apple Notes triage v3 — his picks, rename Delete, resumable, import-so-far, tags
spec: C117 C238
needs: Q72
do: Tuur 2026-09-27 on `mocks/Q67-apple-notes-triage.html`. Picks: A = the next batch stays locked until all ten are decided; B = a declined note is never offered again; C = one note at a time on the phone. Changes: (1) "Delete" is the wrong name — Skrift cannot delete in Apple Notes; rename (e.g. "Never import") and show how a declined note is recognised next time (per Q72's finding; not by title — "if you change the title it might come in again"); (2) resumable over days: 500 notes are not one sitting — progress saved, a clear "continue where you left off"; (3) "import what I've decided so far" at any point, so he can go delete those in Apple Notes; (4) Apple Notes tags become Skrift tags on import; (5) the button he could not find: label it plainly ("Next 10") and show it locked until the ten are decided; (6) no folder step when the export has no folders (his Notes are one flat list; Skrift gets no folders); (7) a panel listing every Apple Notes media type and what happens to it, from Q72 (drawings included). Keep: tapping importance advances to the next note ("I quite like that"), the end report. Every control responds on tap. Publish; one numbered question.
check: Tuur clicked through it and said go.

### Q72 [auto] (done) research: what an Apple Notes export contains per media type, and what identifies a note across exports
spec: C238
needs: -
do: Research only (researcher agent, open web, no project code or data): Tuur needs to know, before the Apple Notes import is built: (1) which export routes exist from Apple Notes on macOS/iOS 26 (File → Export as PDF/Markdown/Pages, Share, third-party exporters, the NoteStore.sqlite route) and what each produces; (2) per media type inside a note — drawings/sketches, scanned documents, tables, checklists, attachments (images, PDF, audio, video), links, tags (#hashtags), mentions, locked notes, folders/smart folders — whether it survives each route and in what form; (3) what stable identity a note carries in each route (creation date, modified date, an ID) so a declined note can be recognised on a later export even after its title changes. Report in `plan/research/apple-notes-export.md` with URLs and one recommendation per question.
check: `test -s plan/research/apple-notes-export.md`

### Q73 [auto] (done) a typed note records place and weather when created, like a voice recording
spec: C112 C43
needs: -
gate+: yes
do: Tuur 2026-09-27: "yes typed should also record". Today only a voice recording runs `MetadataService.capture()` (RecordView.swift:160, MemoSaver.applyMetadata:740); `Memo.newTyped` (Shared/Model/Memo.swift:398) stores only {"mediaSource":"typed"}, so a typed note's header shows date + time and nothing else. Capture place, weather and daypart for a typed note the moment the note is created (first keystroke, D91), asynchronously — the keyboard must still be up in under a second (C112) and an empty discarded note must leave nothing behind. Same on the phone, iPad and quick note; the Mac only if it already has a location path. A nil GPS fix or geocode stays nil silently, as for voice notes. Test in the phone target (new file) that a typed note gets the metadata a voice note gets, with a stubbed capture.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh TypedNoteMetadataTests && ./gate.sh`

### Q74 [auto] (done) Mac import of several audio files asks: one note or N notes (C68 chooser on the Mac)
spec: C68 C145 C238
needs: -
gate+: yes
do: Tuur 2026-09-30: "when I upload three audio messages into Skrift desktop it should ask if I want it 1 note or three separate". The phone already has this chooser (C68 share sheet, C145 Files importer); C238 says a Mac drop of the same files must yield the same notes. Give every Mac entry point (Import button, sidebar drop incl. the Photos file-promise path, Finder open) the same One note / N notes chooser when 2+ audio files arrive together, reusing the phone's shared merge logic (clips merged in order, one transcription pass; default One note). Mock the Mac sheet first if the phone's has no Mac form. Desktop test (new file) that 3 audio files → 1 merged note or 3 notes per the choice. NEVER run SkriftDesktopUITests; Mac proof = unit tests + full build + headless snapshot.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh AudioShareDrainTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q75 [tuur] (done) mockup: note header final — the pill cycles all four states on tap, destination row included
spec: C117 C94 C62
needs: -
do: Tuur 2026-09-30 on `mocks/Q70-note-header-two-versions.html`: version 1, the pill ("the card becomes one pill, I think that's good"). Change: tapping cycles Not rated → Passing → Useful → Important → Not rated ("just tapping through it"; un-rating is allowed, C88) — no second tap to open a picker; also show a left-right drag across the pill as an alternative to compare. Missing today: the mocks left out the note's destination (Personal / Made / Idea / Inspiration, C62) — draw the destination row from source (`Shared/UI/DestinationRowView.swift`, NoteDestination) in its real place. Phone + iPad + Mac, voice and typed note (typed with place + weather, D151), heights in pt. Every control responds on tap; node --check the script; no copy inside JS strings. Publish; one numbered question.
check: Tuur clicked through it and said go.

### Q76 [auto] (done) research: can a Mac app move notes between Apple Notes folders, and read NoteStore.sqlite inside the App Store sandbox
spec: C238
needs: -
do: Research only (researcher agent, open web): Tuur picked reading Apple Notes' own database on the Mac (D153) and asks: after a note is imported, can the app MOVE it into a folder in Apple Notes (e.g. "Imported to Skrift" / "Not imported yet") without deleting anything? Answer with URLs: (1) can the Notes AppleScript/JXA dictionary move a note between folders (`move note … to folder …`), does that survive iCloud sync, and what permission prompt it needs (Automation); (2) is writing NoteStore.sqlite directly ever safe (expected: no); (3) can a sandboxed Mac App Store app read ~/Library/Group Containers/group.com.apple.notes with Full Disk Access, or does it need to be outside the App Store; (4) whether AppleScript can read locked notes' titles. Report `plan/research/apple-notes-folders.md`, one recommendation per question.
check: `test -s plan/research/apple-notes-folders.md`

### Q77 [auto] (done) Mac sidebar: shift-click selects a range; imports transcribe on their own; right-click Process works every time
spec: C49 C115
needs: -
gate+: yes
do: Tuur 2026-09-30 on the prod Mac (an older build — reproduce on the current branch first, headless, synthetic corpus): (a) "I can't shift select multiple" notes in the sidebar — add range selection (shift-click) and ⌘-click to the Mac list, feeding the existing multi-select actions; (b) "when I uploaded the voice memos they didn't auto transcribe" — C49: a Mac import floors to 0.1 and must enter the pipeline without a manual Process; find why an imported voice memo sat untranscribed; (c) right-click → Process "worked flaky" — find the failure (race with the batch runner? selection vs clicked row?) and fix. Desktop tests (new file) for (b) and (c) through the ingest/processing seams; (a) proven by the full build + a headless snapshot with 3 rows selected. NEVER run SkriftDesktopUITests (they take the real mouse).
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q78 [auto] (done) phone Journal previews show plain text, not raw markdown (use NoteSnippet.plain)
spec: C115
needs: -
do: Q69 made one shared `Shared/Pipeline/NoteSnippet.plain` (no `**…**`, no `[[…]]`) and used it in the Mac sidebar and Mac Journal; the phone's `JournalHomeView.snippet` (SkriftMobile/Features/Journal/JournalHomeView.swift:381) still builds its own and shows raw markup. Route it (and any other phone snippet builder that shows raw `**Speaker n:**` / `[[Name]]`) through NoteSnippet.plain. Phone proof via `plan/mtest.sh` on an existing class.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteRouteTests && ./gate.sh`

### Q79 [auto] (done) quick note: typing fast never loses a character or Return while the first keystroke creates the note
spec: C112 C113
needs: -
gate+: yes
do: The Q64 simulator run (2026-09-30) typed "Tram 28 idea\nBuy pastel de nata\n…" at full speed into a fresh quick note and the FIRST Return was lost ("Tram 28 ideaBuy pastel de nata"); with 1.5 s pauses every Return survived. Suspect: `QuickNoteBodyTextView.updateUIView` (`if tv.text != text { tv.text = text }`) writing back a stale binding while the first keystroke creates the draft Memo (Q47/Q53/Q73 all touch that moment). Reproduce with a phone UI test typing fast (the Q64sim test in SkriftMobileUITests/QuickNoteQ64SimUITests.swift is the pattern; take the sim lock), fix so the text view is the source of truth while editing, and prove every character and Return survives at full speed, including a paste. Phone UI tests stay in the simulator; never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteTests && ./gate.sh`

### Q80 [auto] (done) delete the 43 dead functions and the unused sharing/batch export (Q62, D154), with their tests
spec: C240
needs: -
gate+: yes
do: Tuur approved per group on 2026-09-30 (D154) from the explainer https://claude.ai/artifact/TQKfanHMQasHHxFDmLQeyc (source list plan/reads/q62-unused-tested.md — its line anchors are wrong in places; the explainer re-derived them from tree 0d2779a6, re-grep every symbol by NAME on both apps before deleting). DELETE exactly the explainer's DELETE rows: 1 (edit-conflict record ids, PillRule — 3), 2 (old parseTagInput), 3 (touchedAt, attachmentsWritten), 4 (silenced set, plainOccurrences), 5 (15: old IN/OUT quote-capture math ×12, textSummary(bookID:), headings(in:), audioURL(of:)), 6 (normalize), 7 (the unused `now` parameter only), 9 (touch, MemoSpine.name(for:), ProcessPile.done), 10 (the three old paragraph splitters + the Mac DEBUG command that calls one), 11 (bodyRange), 12 (removedCount), 13 (createdAt), 14 (importance warm colour), 15 (PDF, quote card, plain-text share, publishAll ×2, the 3 convenience overloads — "delete it and if I want it we'll rebuild it later"). Delete each one's own tests with it: protected-test deletions are APPROVED (D154) and will be hand-merged like Q15 (D146). Never delete a KEEP row. One commit per group. Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteRouteTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q81 [auto] (done) wire in the 7 unfinished pieces: Undo for the old-note tidy-up, and the tag editor's 'already on this note' line
spec: C240 C93
needs: -
gate+: yes
do: From the Q62 explainer (D154): wire in the 7 built-and-tested-but-unused pieces. (1a, 5 pieces) the Undo for the one-time old-note tidy-up (body normalisation, Q14/Q40) — find where the tidy-up runs and give the user a way back; (2b, 2 pieces) the signed tag mock's (`mocks/tag-ui-revamp.html`) "already on this note as #x" line that the build dropped (Q28/Q36). Phone, iPad and Mac. Screenshots, LOOK, commit under `plan/reads/wirein-q81/`. Never run SkriftDesktopUITests.
check: `test $(ls plan/reads/wirein-q81/*.png | wc -l) -ge 1 && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteRouteTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q82 [auto] (done) phone and Mac run one shared implementation for word highlight, Looking back, list core, conversation turns, recording helpers and search by meaning
spec: C115 C240
needs: Q80
gate+: yes
do: Tuur 2026-09-30 on the Q62 explainer: make phone and Mac use the SAME shared code, the Mac matching the phone where they differ: group 6 word highlight / karaoke ("which word is playing — unify between devices, also in karaoke mode"; tapping a highlighted word seeks there on every device), 8 Looking back, 9 notes-list core (fading, duplicates — "all devices use it the same way"), 11 conversation turns, 12 recording helpers, 13 search by meaning ("match the Mac to the phone and unify the code"). First write `plan/reads/unify-q82.md`: per group, what each app does today, file:line, and the one shared implementation it moves to; then move them one group per commit into `Shared/` with a test each that the same input gives the same output on both targets. Never run SkriftDesktopUITests.
check: `test -s plan/reads/unify-q82.md && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteRouteTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q83 [auto] (done) audiobook quote captures: tap a word to jump the audio there, like a voice note
spec: C113 C218
needs: -
gate+: yes
do: Tuur 2026-09-30: "when a word is being highlighted you can click anywhere and the audio jumps to that. Apparently that doesn't work with audiobook quotes — I can't click those. Maybe there's no timestamps generated when the book is transcribed." Find why a quote-capture note's words are not tappable (no word timings stored for the quote, timings relative to the book not the clip, or the view never wires tap-to-seek for quotes), and make tapping a word in the quote seek the quote's audio, on phone and Mac. Test with a synthetic quote capture. Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteRouteTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q84 [auto] (done) destinations read Personal · Inspiration · Idea · Project under PRIVATE ¦ PORTFOLIO, with a dashed line between the two sides
spec: C62
needs: -
gate+: yes
do: Tuur 2026-09-30: a PROPER rename everywhere, "I don't want old words creeping through again", even if the portfolio folders must change (D156, supersedes D155's keep-the-raw-value). (1) Words: Archive → Portfolio and Made → Project in every user-visible string, SPEC/FEATURES wording, code identifiers (`isArchive` → `isPortfolio`, `.made` → `.project`, types/functions/comments with archive/made in their names — 22 Swift files mention them) on phone, iPad and Mac; order Personal · Inspiration · Idea · Project; PRIVATE ¦ PORTFOLIO labels with a dashed divider between the two sides (Shared/UI/DestinationRowView.swift:155-164). (2) No migration: the destinations feature was never used on any device (Tuur 2026-09-30: "nothing has been saved with it"), so rename the raw value to "project" outright — no "made" decoding, no folder move. (3) Portfolio folders match the words (Tuur 2026-09-30: "projects to projects, ideas to ideas, inspiration to inspiration"): Project → `_projects/` (was `_inbox/`), Idea → `_ideas/`, Inspiration → `_inspiration/`; nothing to move, the feature was never used. (4) After the change `grep -rniE "\\bmade\\b|archive" ` over Swift sources, mocks for the destination row, SPEC.md and FEATURES.md shows only unrelated uses (list each one left in the commit message). Screenshots phone + Mac (headless), LOOK, commit under `plan/reads/dest-q84/`. Never run SkriftDesktopUITests; never read the real vault or portfolio folder.
check: `test $(ls plan/reads/dest-q84/*.png | wc -l) -ge 1 && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteRouteTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q85 [auto] (done) build the note header pill (tap steps Not rated → Passing → Useful → Important) on phone, iPad and Mac
spec: C117 C94 C88
needs: Q84
gate+: yes
gate+: yes
do: Build the signed header (mock `Skrift_Native/SkriftDesktop/mocks/Q75-note-header-final.html`, behaviour A — Tuur 2026-09-30: "tap is good, not drag"): the importance card becomes one pill; each tap steps Not rated → Passing → Useful → Important → Not rated (un-rating allowed, C88; a toast names each step); the orange "starts fading … — rate it to keep it" line beside it when unrated; the destination row (as renamed by Q84) 12 pt under it, shown only when destinations are on. Phone, iPad and Mac through the shared ThreeBallScale/NoteConsent model (C115). Phone header ≈173 pt at rest per the mock. Screenshots, LOOK, commit under `plan/reads/header-q85/`. Never run SkriftDesktopUITests.
check: `test $(ls plan/reads/header-q85/*.png | wc -l) -ge 2 && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteRouteTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q86 [tuur] (done) mockup: Split speakers on the Mac as a per-note toggle, matching the phone, with the user flow walked end to end
spec: C102 C117
needs: -
do: Tuur 2026-09-30: "yes split speaker should be a button or toggle or something. Have an agent verify the user flow and make sure it makes sense." Q69 made diarization a per-note opt-in (`PipelineFile.diarizeRequested`) with NO Mac control yet; the phone has a conversations toggle (draw it from source). Mock the Mac control (and the phone's, drawn as-is) in the note header/menu: turn it on for a note → the note re-transcribes with speakers → turns in the gutter (full name on a speaker's first turn, short name after — confirmed 2026-09-30, C84); turn it off → "Flatten to monologue". Then a SECOND agent walks the flow cold, step by step, and writes where a user would get stuck; fix those in the mock. Publish; one numbered question.
check: Tuur clicked through it and said go.

### Q87 [auto] (done) build Split speakers per the Q86 mock: a header switch on the Mac, the phone flow with Flatten, all 15 walk fixes
spec: C102 C84 C117
needs: Q85
gate+: yes
do: Build the signed mock `Skrift_Native/SkriftDesktop/mocks/Q86-split-speakers.html` (Tuur 2026-09-30: "looks great, on both phone and Mac… I like it all. Do the switch in header"). Mac: a Split speakers SWITCH in the note header under "Include audio in export", separated by a hairline, off by default; turning it on asks first (re-transcribes from the audio, replaces hand edits — the popover names the last-edit date and an estimate from the recording length), sets `PipelineFile.diarizeRequested` (Q69) and queues through RunQueue (Q77); progress with a ticking time and Cancel; "Only one voice found. Nothing was split."; speakers named from the gutter ("+ name", a person names all of that speaker's turns); switching off runs the existing Flatten to monologue after a confirm that says words, fixes and names stay; greyed "Rate the note first" on unrated notes (C187). Phone: keep the two-people icon + "How many speakers?" (Auto explained, edits warning), add "Split speakers…" and "Flatten to monologue" (with confirm) to the ⋯ sheet, "Move just this line to another speaker" wording, the one-voice toast. Full name on a speaker's first turn, short after, hover/long-press shows the full name (C84). Tests: desktop (opt-in flag, one-voice outcome, flatten keeps names) + phone (flatten). Headless Mac snapshots + phone sim screenshots under `plan/reads/split-q87/`, LOOK. Never run SkriftDesktopUITests.
check: `test $(ls plan/reads/split-q87/*.png | wc -l) -ge 2 && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteRouteTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q88 [auto] (done) quick note, share sheet and capture sheets use the new rating pill too (one header everywhere)
spec: C115 C112 C94
needs: Q85
gate+: yes
do: Q85 built the signed pill header (`Shared/UI/NoteRatingPill.swift`: NoteRatingPill, NoteRatingRow, RatingToastView) into the note screen on phone, iPad and Mac, but left the OLD importance card in the quick note (QuickNoteView — D145 says the quick note IS the full note screen), MergedCapture, the share sheet and UnpipelinedMemoSheet. Move all of them to the same pill + fading line + destination row, so there is one header everywhere (C115). Update the phone UI tests that look up `importance-balls` (QuickNoteQ64SimUITests, QuickNoteFastTypingUITests…) to the pill's identifier — those are UITests, not the protected unit targets. Phone sim screenshots of each sheet → `plan/reads/pill-q88/`, LOOK. Never run SkriftDesktopUITests.
check: `test $(ls plan/reads/pill-q88/*.png | wc -l) -ge 2 && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q89 [auto] (done) delete the test-only audiobook quote-capture function and the old importance circles, with their tests (D158)
spec: C240
needs: -
do: Tuur 2026-09-30: "the two deletions, if we don't use them, we can get rid of them" (D158). Delete (1) `QuoteCaptureProcessor.process(bookAudio:span:bookDuration:)` and the four helpers only it calls — `CaptureSpan.transcriptionBuffer`, `SentenceSnap.snap`, `isSentenceEnd`, `inForwardSnapThreshold` (Q80 kept them because this function still called them; it has no production caller, only tests); (2) the old importance circles now used only by `SignificanceCirclesRenderTests` after Q88: `SignificanceCircles` (phone + Mac), `ThreeBallImportanceView`, `ThreeBallStyle` — keep `ThreeBallScale` and the new rating pill and its PhoneRatingRow/MacRatingRow. Re-grep every symbol by NAME across both apps, Shared, tests and project.yml files before deleting; a hit outside its own definition and own tests means keep and report. Delete their own tests with them (approved, hand-merge). Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteRouteTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q90 [auto] (done) a Mac import arrives unrated: transcribed, but not queued for polish until rated (C49 reversed, D159)
spec: C49 C87 C40
needs: -
gate+: yes
do: Tuur 2026-09-30: a Mac import should arrive UNRATED ("yes it should") — reverses the 2026-07-26/28 rule "an import is consent, floors to 0.1" (plan/extraction/ledgers.md:263, decisions.md:145; memory project_note_consent). Make a Mac import author an unrated memo exactly like a Mac recording: it keeps its row, is transcribed on arrival (Q77's transcribeImport stays — words are not polish), shows Not rated in the pill with the fading line, and enters the Process queue / polish / export only once rated. Pressing Polish or Process on an unrated note still floors it to 0.1 (C40 — that door stays). Update NoteConsent's nil table and the MacMemoAuthor/ArrivalPath paths; protected tests that pin the old import floor (MacMemoAuthorSignificanceTests, ArrivalPathTests, any other) change to the new rule — approved (D159), will be hand-merged; add a test that an import is unrated, transcribed, and absent from the process queue. Update SPEC C49 wording and FEATURES.md. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q91 [auto] (done) update the two UI tests that still drive the old Filter button to the new chip ids (never run the Mac one)
spec: C117
needs: -
do: Q66 (D148, option A) deleted the Filter button/sheet; two protected UI tests still drive it: `SkriftMobile/SkriftMobileUITests/MemosListUITests.swift:79` (`testFilterUnsyncedHidesSynced`: sort-filter-button → filter-unsynced → sortfilter-done) and `SkriftDesktop/SkriftDesktopUITests/SidebarSearchSortUITests.swift:26,42` (`sidebar.filter`). Point them at the new ids (`chip-unsynced`, `chip-date`, `sort-cycle-word`, `sidebar.chip.Date`, `sidebar.sort-word`) with the same assertions — the change follows Tuur's D148, hand-merge. Run the PHONE test in the simulator (sim lock). NEVER run the Mac UI test (it takes the real mouse) — compile-check it only with `xcodebuild build-for-testing` of the Mac UI-test target.
check: `./gate.sh`

### Q92 [auto] (done) Mac drop of voice clips + a picture: one note, the picture placed between the clips by its time (C68, ingress P3)
spec: C68 C12 C238 C70
needs: -
gate+: yes
do: Tuur 2026-10-01 on Skrift Dev (Mac, 1ad5737a): dragging five Signal voice clips in at once worked ("fucking perfect, very nice"), but the picture dragged with them (signal-2026-10-01-080349.jpeg, between clips 07:56 and 08:04 by its filename time) "didn't come in" at all. Q74 merged only the audio clips and sent other files down their own path; here the image was lost entirely. C68: a mixed bundle → ONE note in order — pictures per C12 as their own paragraph at their place — exactly the corpus fixture `ingress-p3-five-clips-one-picture` (5 clips + 1 picture between clip 3 and 4). Find why the image vanished (dropped by audioClips(in:)? the file-promise path? the chooser?), then make a Mac mixed drop produce the one-note result: clips merged in time order (filename-date ladder C70), the picture placed between the clips at its time. When the user picks "N notes", the picture becomes its own note (never lost). Desktop test over the P3 fixture + a test that no dropped file is ever silently skipped. Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteRouteTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q93 [auto] (done) phone share of clips + pictures places each picture between the clips by its time (shared MixedBundle, C12)
spec: C68 C12 C238
needs: Q92
gate+: yes
do: Q92 found the phone's share drain (CaptureInboxDrainer ~l.238-260) pins every bundled photo at offsetSeconds 0, so a phone share of clips + pictures puts all pictures at the top — C12 is not implemented on the phone either. Q92 wrote the shared composer `Shared/Pipeline/MixedBundle.swift` (order by filename time when every name is dated, else selection order; a picture's offset = merged-clip seconds before it). Route the phone share drain through MixedBundle so the same bundle gives the same note on both apps (C238); phone test over the ingress P3 shape (5 clips + 1 picture between clip 3 and 4). Phone only; never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteRouteTests && ./gate.sh`

### Q94 [auto] (done) the phone reads dates from filenames like the Mac (C70 required difference): one shared filename-date ladder, the share extension carries each file's name
spec: C70 C124 C12 C238
needs: Q93
gate+: yes
do: C70 is a required difference: recordedAt = embedded date → date in the filename (WhatsApp / Signal / Telegram / recorder patterns, Mac parity) → file date → now; the phone never parses the filename today. Q92 extended the Mac's `IngestService.dateFromFilename` (incl. compact HHMMSS like `signal-2026-10-01-080349`); Q93 found the share extension hands the drain no filenames — clips carry file mod dates, pictures only EXIF (empty for Signal JPEGs) — so a real Signal share of clips + a picture falls back to pictures-first. Move the filename-date ladder into `Shared/` (one copy, the Mac calls it too), make the share extension carry each item's original filename / suggestedName and its selection position, and let the drain date clips and pictures from it so MixedBundle places a Signal picture between the clips at its time and the note is dated to the first message (C124). Tests: the ladder's patterns (shared, desktop + phone), a Signal-named share bundle → picture between clip 3 and 4. Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteRouteTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q95 [auto] (done) Mac sidebar reflows when dragged narrow instead of clipping its left edge
spec: C115 C240
needs: -
gate+: yes
do: Tuur 2026-10-02 on Skrift Dev (real window — the Q35/Q37/Q65 'left-edge clip' question answered): at the normal sidebar width nothing clips, but "I can drag the sidebar in and then it just clips off weirdly": the logo, the Import · Record · ✎ row, the chip row, day headers ("RI 3 APR") and every card lose their left edge instead of shrinking. Make the sidebar content lay out to the sidebar's actual width (cards, chips and verb row shrink/wrap; the chip row keeps scrolling sideways), or set a minimum sidebar width at which nothing clips — pick the one that matches the phone's list. Prove with headless `-snapshot-shell` renders at 220, 260 and 292 pt (add a width flag if missing), LOOK, commit under `plan/reads/sidebar-q95/`. Never run SkriftDesktopUITests. ADDED 2026-10-02 (same sidebar, same worker): (a) the chip row scrolls sideways on the phone but NOT on the Mac ("on the phone I can scroll through it and on the Mac I cannot") — make the Mac chip row scroll sideways like the phone's shared FilterChipRow; (b) on the phone the day header stays pinned at the top while scrolling; the Mac has no pinned day header — pin the Mac sidebar's day headers the same way.
check: `test $(ls plan/reads/sidebar-q95/*.png | wc -l) -ge 3 && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q96 [auto] (done) a merged import is dated to its first clip's filename time, not the import moment; each clip starts a paragraph (C124, C70)
spec: C124 C70
needs: -
gate+: yes
do: Tuur 2026-10-02: five Signal clips from 1 Oct (signal-2026-10-01-07-44-33-032.m4a … 08-06-25-049.m4a + a 080349.jpeg) dragged onto the Mac on 2 Oct merged into one note — but the note reads "Fri, 2 Oct 2026" on the Mac and "Today · 08:08" on the phone, the import moment. C124: a merged multi-clip note is dated to the FIRST message (filename date, C70) — here Thu 1 Oct 07:44 — and each clip's own time is kept in the manifest, not shown in the body. Also verify in the same note that each clip starts its own paragraph (C124): the merged body reads "…a pause between every word so the Um this is gonna be a hard one to fix…", which looks like a clip boundary inside one paragraph. Fix both in the Mac merge path (IngestService.ingest(combineAudio:) / AudioClipMerge / MixedBundle, Q74/Q92/Q94) and confirm the phone share path (CaptureInboxDrainer) dates and breaks the same way. Desktop test over the ingress P1/P3 shapes: recordedAt = first clip's filename time, one paragraph per clip. Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteRouteTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q97 [auto] (done) phone list puts most notes under Yesterday: group by the note's real date, not when it arrived on this phone
spec: C70 C115
needs: -
gate+: yes
do: Tuur 2026-10-02 on Skrift Dev, iPhone 17 Pro (a NEW phone — Skrift Dev was installed on it fresh and filled from CloudKit): "most notes are considered to be yesterday… there's a whole ton of notes yesterday, but yesterday I didn't record anything". Suspect: the phone's day groups key on a per-device `createdAt` / arrival time (when the note first landed on this phone) instead of the note's real date. C70: recordedAt = the content's true date; createdAt = when it entered Skrift (the ORIGINAL moment, which must sync, not reset per device). Find what the phone list groups and sorts by (NotesListModel.dayGroups, MemosListView+Derived, the sort chip default), and what CloudKit sync does to createdAt on a fresh install; make the day headers group by the note's recorded date (the date shown on the card) and keep createdAt the original value across devices. Check the Mac and iPad group the same way (one shared rule, C115). Phone test: a memo arriving via sync today with recordedAt 3 weeks ago lands in that day's group. Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteRouteTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q98 [auto] (done) the Separate destinations switch syncs: on one device turns it on everywhere (folder bookmarks stay per device)
spec: C62
needs: -
gate+: yes
do: Tuur 2026-10-02: "the export to different places should be synced across devices — if I turn it on somewhere, it turns on everywhere" (D162). Today `DestinationSettings.isEnabled` is per device (phone Settings → Obsidian → "Separate destinations", ObsidianSettingsSection.swift:107; the Mac has its own), so the phone hid the Personal chip until he flipped it there too. Sync the on/off switch through CloudKit the way other shared settings already sync (find the existing pattern — custom vocabulary / names records, LWW), so turning it on or off on any device does the same on all. The portfolio folder bookmark stays per device (C62: a destination is a per-device folder bookmark) — a device with the switch on but no folder still shows the chips and simply cannot export yet; say so in its Settings. Tests: the switch round-trips through the sync record, LWW. Update C62 wording. Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteRouteTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q99 [auto] (done) split speakers on a merged note keeps one paragraph per clip (pass clipStarts in the diarisation rebuild on phone and Mac)
spec: C124 C102
needs: -
gate+: yes
do: Q96 made a merged multi-clip note keep one paragraph per clip (ClipManifestEntry: Mac clip_manifest.json beside original.m4a, phone MemoMetadata.clipManifest; BodyV2.Input.clipStarts), but the diarisation rebuild paths call BodyV2.committed without clipStarts — the phone `diarizeIntoTurns` and the Mac rebuild (guard widened to clipStarts by Q96, not wired). Pass the clip starts there too so split speakers on a merged note keeps the clip paragraphs inside the turns (C124 with C102). Tests on both apps with a synthetic merged note. Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteRouteTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q100 [auto] (done) Mac list: a locked note shows the locked placeholder, and deleting or unlocking it asks LockGate
spec: C161 C213 C91 R88
needs: -
gate+: yes
do: Q21 gated the phone only. On the Mac: `QueueRowView.cardModel` never sets `locked`, so a locked rated note shows words, balls and chips in the list (list-sidebar-72); `deleteFiles` / `deleteQuiet` / bulk delete never ask `LockGate` (list-sidebar-87); `toggleLock` (SidebarView.swift:855) is a bare `locked.toggle()` + save, with no auth to unlock, no `canAuthenticate`, no "Already in your vault" notice and no `markEdited` (list-sidebar-88, setexp-96); locking a never-rated note drops its row from the Mac list because `WayOutRules.unpipelined` excludes locked (list-sidebar-73). Make the Mac call the same shared `LockGate` / `NoteVisibility` the phone's `MemosListView.deleteMemo` and `toggleLock` call; if the phone's lock-toggle policy lives in phone-only code, move it to `Skrift_Native/Shared/Session/` first. A locked quiet row stays in the list with the lock glyph. Desktop test `MacLockGateTests` with a synthetic locked note (rated and unrated). Never run SkriftDesktopUITests.
check: `grep -rqE "class MacLockGateTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P1

### Q101 [auto] (done) a locked note stays locked on every other surface: Mac Way-out + peek, Review rows on phone and Mac, Share note, search
spec: C161 C213 C91 R88
needs: Q100
gate+: yes
do: Mac `WayOutColumn.memoRow` and `UnpipelinedMemoSheet` show title, date, place and body with no lock check (list-sidebar-116, recsj-110); phone `JournalMemoRow` / `JournalSidePane` show the transcript snippet of a locked note and Mac Review checks the flag but not the per-session unlock (recsj-096); the phone's `Share note…` builds `shareItems(for:)` with transcript and audio and no gate (note-lock-03); search on both apps matches a locked note's body text and can surface it (recsj-053 missed note). Route every one of these through `NoteVisibility.contentVisible` / `LockGate`, and keep a locked note's body out of the search match until unlocked (the row may still show as 'Locked note'). Phone test `LockedSurfacesTests`, desktop test `MacLockedSurfacesTests`. Never run SkriftDesktopUITests.
check: `grep -rqE "class MacLockedSurfacesTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh LockedSurfacesTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P2

### Q102 [auto] (done) ProcessPile.isWaiting follows C182/C215: a locked note is in the Process pile on phone, iPad and Mac
spec: C182 C215 D10
needs: -
gate+: yes
do: `ProcessPile.isWaiting` (Shared/Pipeline/ProcessPile.swift:25) returns false for `memo.locked`; the Mac's `pendingFiles` has no lock check, so the chip count and the Process button disagree between devices (list-sidebar-26). C182/C215/D10 say lock gates the eyes, not the pipeline: a locked note counts in "Process N". Remove the lock term from `isWaiting` (line 25) and from `isDone` (line 36), keep the real-transcript term, and correct FEATURES.md (the row that says 'unlocked'). `unrated` (line 32) and the `.notRated` chip (line 52) also drop locked notes, so a locked unrated note sits under no chip but All: C182 does not cover unrated notes, so leave those two and add the question to the 'Needs Work / Done' decision brief. Test `ProcessPileLockedTests` (desktop target; `ProcessPile.swift` compiles into the Mac): a locked, rated, transcribed, unprocessed note is waiting.
check: `grep -rqE "class ProcessPileLockedTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P3

### Q103 [auto] (done) one shared note-search matcher on phone, iPad and Mac, with the C236 fields
spec: C236 C111 C115 C240
needs: -
gate+: yes
do: Three hand-written matchers: phone `Memo.matches` (MemoDisplay.swift:81-97), Mac rated `AppModel` (85-94), Mac quiet `WayOutRules` (158-164) (list-sidebar-32, recsj-053). Phone matches raw title, transcript, tags, place, annotation, link title, shared text, OCR but not the generated title or summary; Mac rated matches queueTitle, transcript, summary, OCR; Mac quiet matches displayTitle + transcript only. C236 lists title, transcript, tags, place name, summary, OCR, PDF and article text. Write ONE `NoteSearch.matches` in `Skrift_Native/Shared/` taking a plain snapshot (the same snapshot shape `SemanticSearch.snapshot` already uses), include every C236 field the data holds, and call it from the three sites. OCR hits stay list-search-only. A locked note's body is excluded (see the lock-surfaces item). Test: one note fixture gives the same hit list through the phone and the Mac adapters.
check: `grep -rqE "class NoteSearchTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh NoteSearchParityTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P4

### Q104 [auto] (done) filters apply to every row kind: Mac date range on unrated, stranded and fading rows; Related rows obey chip + date; fading hits show under any chip
spec: C115 D148 C212
needs: -
gate+: yes
do: Mac `AppModel.visible` applies `matchesDate` to PipelineFile rows only; `visibleMemoRows` (SidebarView.swift:759-779) filters by search alone, so a date range leaves unrated, stranded and fading rows in place (list-sidebar-47). Mac `relatedEntries` only drops exact hits while the phone's `relatedDisplay` applies `matchesFilter` (list-sidebar-36, recsj-055). Fading hits appear under every chip on the phone, only under All / Not rated on the Mac and with no date filter (list-sidebar-34, recsj-054). Move the three rules into the shared list model (`NotesListModel`, Shared/UI) and have both apps call them. Test with one synthetic library: same chip + date + search gives the same row ids on both adapters.
check: `grep -rqE "class NotesListFilterTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh NotesListFilterParityTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P5

### Q105 [auto] (done) Mac sidebar: one row per note id, Recorded/Added date picker, Newest sorts on the note's added date
spec: C70 C115
needs: -
gate+: yes
do: Mac sidebar fetches raw `Memo` rows without `MemoDuplicates.canonicalRows`, so a duplicated clone can show twice (list-sidebar-102; the reconciler and Journal already call it). The Mac date filter is labelled 'Uploaded' and keys on `uploadedAt` where the phone offers a Recorded / Added picker (list-sidebar-46); the Mac's Newest sorts on `uploadedAt` (= recorded date) where C70 and the phone sort on `addedAt` = `createdAt ?? recordedAt` (list-sidebar-51). Call `canonicalRows` in the sidebar fetch; the day headers call `NotesListModel.groupDate` (the Mac `SidebarEntry.date` re-derives it and agrees only because `uploadedAt` equals the recorded date, list-sidebar-58); give the Mac the same Recorded / Added field picker (shared `DateRangeStrip` already holds it); sort Newest on `addedAt`. Desktop test `MacSidebarOrderTests`.
check: `grep -rqE "class MacSidebarOrderTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P6

### Q106 [auto] (done) Mac rows get the same card model the phone feeds: quote + book chip, shared-item title + domain chip, source chip for video and audiobook
spec: C115 C240 C172 C78
needs: Q138
gate+: yes
do: `QueueRowView.cardModel` and the quiet-row builder (SidebarView.swift:1277-1326, 797-832) never set `quote`, never show a book chip, never run the URL-title / text-head logic, and add the source chip only when `sourceType != .audio`, so a book capture or a video import (both `.audio` rows) shows neither (list-sidebar-62..65, 68; capture-source-04, -05, -13, -14; books-103). Build ONE card-model builder in `Skrift_Native/Shared/UI/` (title + snippet precedence from `NoteSnippet`, the capture title, `SourceKind` glyph and label, book chip from `CaptureQuote.attribution`, domain chip) and have the phone `MemoCard` and the Mac `QueueRowView` call it. Titled row snippet follows the phone (one clipped line). Test: one corpus note of each kind (voice, video, book quote, link, text, image, PDF) yields the same `NoteCardModel` from both adapters. Screenshot the Mac sidebar from the synthetic corpus in an isolated store, LOOK, commit under `plan/reads/list-p-cardmodel/`.
check: `test $(ls plan/reads/list-p-cardmodel/*.png | wc -l) -ge 1 && grep -rqE "class NoteCardModelParityTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh NoteCardModelParityTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P7

### Q107 [auto] (done) Mac quiet (unrated) rows carry tags, place and weather chips, the D136 fading-line rule, balls when not locked, and the 2-versions pill
spec: C115 D136 D135 C98
needs: Q106
gate+: yes
do: Quiet rows append only a duration chip (list-sidebar-69, -67 via Q68, which fixed rated rows only); the Mac draws a faint spine line on every quiet row where the phone draws an amber line only inside 7 days of fading (list-sidebar-75, D136); balls show on a locked rated Mac row but not on the phone (list-sidebar-71); quiet rows never read `EditConflictWatch` (list-sidebar-79). Feed the quiet row from the same shared card model as the previous item: tags, place, weather chips; spine/fading line only inside the 7-day window; no balls when locked; the '2 versions' pill. Place and weather chips need the Mac `PipelineFile`/`Memo` metadata that `MemoNoteProjection` already carries; check it reaches the row. Desktop test `MacQuietRowChipsTests`; screenshot under `plan/reads/list-p-quiet/`, LOOK.
check: `test $(ls plan/reads/list-p-quiet/*.png | wc -l) -ge 1 && grep -rqE "class MacQuietRowChipsTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P8

### Q108 [auto] (done) strings written twice move to SharedCopy: empty library, no results, Way-out, peek, Review headings, lock/copy menu verbs
spec: C115 C240 D136
needs: -
gate+: yes
do: One string per fact in `Skrift_Native/Shared/UI/SharedCopy.swift`, read by phone, iPad and Mac. Empty library: phone 'No notes yet / Tap the mic…', Mac 'No memos yet / click + Upload' — both bodies are stale (the mic button is gone, the button is 'Import') (list-sidebar-97, recsj-060, capture-import-07). No-results (list-sidebar-98, recsj-059). Way-out intro, section labels, footer, empty state, peek 'No transcript.' vs 'No transcript yet.', retention days read from `TrashPolicy.retentionDays` / `fadeAfterDays` instead of the Mac's literal 30 and 14 and 'Your iPhone' (list-sidebar-108..111, recsj-105, -106, -109). Review: 'Nothing recorded this day.' vs 'No notes this day.', 'back to calendar' vs 'Back' (recsj-093, -103). Menus: 'Lock Note' / 'Lock' / 'Lock note', the Mac Copy submenu and the compact dialog's hard-coded 'Copy transcript' / 'Delete' all read `NoteMenuItem` (list-sidebar-84, -85, note-menu-11). Record verb literal gets `SharedCopy.recordVerb` (recsj-001). Mac Process row reads `SharedCopy.processVerb` / `processingStep` / `processingDownload` instead of its hand-written 'Loading transcription model' (list-sidebar-25, -28). Test `SharedCopyUsageTests` (desktop target) reads both apps' source files and asserts each of these constants is referenced from the phone tree and the Mac tree.
check: `grep -rqE "class SharedCopyUsageTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P9

### Q109 [tuur] (done) decide: what 'Needs Work' and 'Done' mean on every device
spec: C115 C61 D135
needs: -
do: -
check: Tuur picked one definition and it went into SPEC.
brief: Phone `ProcessPile.matches` (ProcessPile.swift:50-51): Needs Work = rated and not yet processed, Done = processed (the iPhone never exports). Mac `AppModel.matchesFilter`: Needs Work = pipeline row not exported plus stranded rated notes, Done = exported (list-sidebar-40, -41). A processed-but-unexported note is Done on the phone and Needs Work on the Mac, and the Mac Done list can hold stranded notes that are not done (list-sidebar missed note). Recommended: Done = processed, on every device; 'exported' becomes the destination row's own state. One sentence in SPEC D135/C61, then the build is one shared predicate (`QueueFilter`). Also: ProcessPile.unrated (ProcessPile.swift:32) and the .notRated chip (:52) drop locked notes, so a locked unrated note sits under no chip but All; C182 does not cover unrated notes. Should locked unrated notes count under Unrated? (from Q102) Also (Q104): a stranded note (rated, no pipeline row) shows under BOTH Needs Work and Done on the Mac but one of them on the phone; a locked unrated note shows under Not rated on the Mac (lockedQuiet) but not on the phone (ProcessPile.matches(.notRated) excludes locked).
source: plan/reads/parity-audit.md P10

### Q110 [tuur] (done) decide: the Unsynced chip (D148) against D68, and the Mac status pill (D135)
spec: D68 D148 D135
needs: -
do: -
check: Tuur picked and it went into SPEC.
brief: (1) Unsynced chip: D148 signed it into the chip row, D68 says drop the filter as dead under CloudKit, and nothing sets `syncStatus = .synced` outside the seeders, so the chip is a no-op on the phone and absent on the Mac (list-sidebar-48). Phone `MemoFilter.hasPhotosOnly` and `.place` are dead too. Recommended: remove the chip and the dead filters, supersede D148's chip line. (2) Status pill: D135 says a pill only while working or broken on all three devices; the Mac shows Queued / Transcribed / Enhancing / Ready / Exported on every rated row (list-sidebar-76). Recommended: keep the Mac dashboard pills and write that into D135 as the one platform difference, or drop them. No code until he picks.
source: plan/reads/parity-audit.md P11

### Q111 [tuur] (done) decide: keyboard shortcuts — ⌘N on iPad, a Record chord, ⌘F and ⌘1-4 on the Mac
spec: C112 C114
needs: -
do: -
check: Tuur picked the table and FEATURES.md follows it.
brief: iPad binds ⌘N twice: the app menu 'New Recording' (SkriftApp.swift:243-248) and the list pencil 'New note' (MemosListView+Header.swift:116); which one wins is unverified; FEATURES.md:61 says new note, :126 says record (list-sidebar-22, capture-quick-02, recsj-037). The Mac has only ⌘N (new note) and ⌥⌘C; no menu command for Record, no ⌘F, no ⌘1-3 surfaces (list-sidebar-24, recsj-036, -052). Recommended: ⌘N = new note on every device; Record = ⇧⌘N; Mac gets ⌘F (search), ⌘1 / ⌘2 for Notes / Review, and a Record menu command. He picks; then it is one `.commands` block per app.
source: plan/reads/parity-audit.md P12

### Q112 [auto] (done) Mac: the audiobook / shared-text quote block is read-only, only the ramble edits (C172)
spec: C172 C31 C21
needs: -
gate+: yes
do: The Mac editor is one `NSTextView` over the whole body; `styleLeadingQuote` (BodyTextView.swift:897-940) only restyles, and nothing refuses an edit inside the quote range, so a Mac edit can alter or delete the quote (note-body-29, books-108). The phone editor holds only the ramble and re-prepends the raw quote lines on write-back. Add a `shouldChangeTextIn` guard that rejects edits whose range touches the leading quote block (`CaptureQuote.split` gives the range), on Mac. Desktop test `MacQuoteReadOnlyTests`. (The explicit 'Fix quote' verb of D50 is its own mock item.) Never run SkriftDesktopUITests.
check: `grep -rqE "class MacQuoteReadOnlyTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P13

### Q113 [auto] (done) phone creates people only through PersonEditCore.materialise (speaker naming, Add Person sheet)
spec: R12 C83 C80
needs: -
gate+: yes
do: Phone speaker naming relabels, then `VoiceEnroller.enroll` adds a person only if a clip embeds; a short clip or a missing sidecar leaves NO person, and one that is created has `aliases: []`; `SpeakerAssignSheet.swift:9` promises 'creates a new person' (note-speaker-02). The phone `AddPersonView.save` calls `store.upsert(canonical:aliases: [],short:)`, skipping the default-alias rule, so the person never links, and an existing canonical has its aliases wiped (setexp-107). The Mac creates `[full, first]` with `short = first`, then relinks, then enrols. Route all three phone doors through `PersonEditCore.materialise` + `upsert(_, replacing:)`; the person exists before enrolment is attempted; `upsert(canonical:aliases:short:)` stops overwriting an existing person's aliases. Phone test `PersonCreationRulesTests`; fix the stale 'managed on your Mac' footer and the NamesListView header comment.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh PersonCreationRulesTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P14

### Q114 [auto] (done) one display-title ladder in Shared (C25): derived title, capture title, placeholder, link-picker rows
spec: C25 C239 C115
needs: -
gate+: yes
do: Four ladders for one rule: phone `Memo.displayTitle`, Mac `WayOutRules.displayTitle` (no enhancedTitle, no capture step), Mac `firstBodyLine` (reads sanitised first, strips only `[[img]]`/`[[memo:]]` so it can show `[[Name]]` and `**Name:**`) and the capture ladder (phone: urlTitle→host→'Link', 'Text snippet', annotation-or-'Image'; Mac `BatchRunner`: existing title, urlTitle, first 8 words, file name, 'Capture' — the Mac one matches C25) (note-title-02, capture-source-12, -13, -16, note-body-22, -23). Write one `NoteTitle.display(...)` in `Skrift_Native/Shared/Model/NoteTitle.swift` following C25 exactly, read by the phone list, header placeholder, link picker, the Mac list, pane, link candidates and `BatchRunner`. Also: the phone list row for a capture ignores a user-typed or Mac-polished title (`MemosListView+Row.swift:110-112` sets `m.title = shareCaptureTitle`) — it must honour the title first. Test `NoteTitleLadderTests` on both targets with the same fixture list; the unrated Mac capture reads `annotationText` for snippet and body (capture-source-15).
check: `grep -rqE "class NoteTitleLadderTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh NoteTitleLadderTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P15

### Q115 [auto] (done) Mac 'From the recording' title suggestion never offers memo_<uuid>
spec: C181 C25
needs: -
gate+: yes
do: The Mac chooser value is `SkriftFormat.cleanFilename(file.filename)` (NoteProperties.swift:36); a phone memo's filename is `memo_<uuid>.m4a`, so picking it writes 'memo_<uuid>' as the title and syncs it through `MacCloudMetaSync.setTitle` (note-title-03). Use the shared first-transcript-line cut (60 chars, as the phone's 'From the recording: …') as the 'from the recording' value, and show the chooser only when it differs from the suggested title. Desktop test `MacTitleSuggestionTests`: a `memo_<uuid>.m4a` file never produces that title.
check: `grep -rqE "class MacTitleSuggestionTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P16

### Q116 [auto] (done) name decisions (unlink, pick, silence) sync between devices; one wording set for the actions
spec: C81 D20 R37
needs: -
gate+: yes
do: SPEC C81/D20/R37 say name picks sync on every device. Today the phone keeps `Memo.namePicks` / `nameResolutionsData`, the Mac keeps `unlinkedNames` / `namePicks` on `PipelineFile`, and the Mac CloudKit ingest ignores `Memo.nameResolutionsData` (Memo.swift:155-164; no reference in SkriftDesktop non-test code) (note-name-03). Mac reads and writes the shared field both ways in `MemoCloudIngest` / `MacCloudMetaSync`; delete the Mac-only copies once migrated. The action labels ('Unlink — keep as plain text' vs 'Unlink — just a side-mention', 'Switch to X' vs 'Change person…') come from one shared table (note-name-02). plan/parity.md:44 ('deliberately not') is stale: fix it. Test: a decision made through the Mac adapter appears in the phone's resolution set and back.
check: `grep -rqE "class NameResolutionSyncTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh NameResolutionSyncTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P17

### Q117 [auto] (done) one input for the Process / Export / Re-export button and for the export outcome line
spec: C194 C180 C61
needs: -
gate+: yes
do: The label table `NoteWorkState` is shared, the inputs are not: iPad `hasPolish` = `MemoEnhancement.isProcessed` (true after an empty pass), Mac = `steps.enhance == .done || all three parts` (NoteActions.swift:25-39); `isExported` = per-destination ledger on iPad, `steps.export == .done` on the Mac; `MemoEnhancement.isProcessed` has no Mac caller although its comment says 'all three apps read it' (note-verb-01, setexp-69). The outcome line quotes `exportTitle` on the iPad and the written file stem on the Mac, passes `assetCount` on the Mac only, and the iPad folds `blockedLegacy` into `blockedForeign` so a legacy file shows the wrong sentence (note-verb-06, setexp-77, -78). Add one `NoteWorkState.Inputs.from(memo:enhancement:ledger:)` in Shared that both call; pass the written path and `assetCount` on iPad; keep the legacy/foreign distinction through `PublishOutcome`. Tests `NoteWorkStateInputsTests` (both targets).
check: `grep -rqE "class NoteWorkStateInputsTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh NoteWorkStateInputsTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P18

### Q118 [auto] (done) Mac note shows per-note progress and a failure line with Retry; the iPad shows the failure reason without hover
spec: C194 C182
needs: -
gate+: yes
do: The iPad note bar shows a progress bar + step line and replaces the verb while a run goes; the Mac note has none (only the split-speakers band) and its primary button stays enabled while running (note-verb-04). On a failure the regular-width iPad puts the reason only in `.help(message)` (MemoDetailView.swift:288), invisible by touch; the Mac prints the global `coordinator.lastError` until its X is tapped, with no Retry (note-verb-05). Mac: take the run state for THIS note from `ProcessingCoordinator` and draw the same bar + step line the iPad draws, disable the primary verb while running, show 'Couldn't process — Retry' on a failed run. iPad regular: print the reason as the compact layout does. Desktop test `MacNoteRunStateTests` on the state mapping; screenshot the Mac note, LOOK, `plan/reads/note-p-progress/`.
check: `test $(ls plan/reads/note-p-progress/*.png | wc -l) -ge 1 && grep -rqE "class MacNoteRunStateTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P19

### Q119 [auto] (done) Connections: one set of rules on iPad, Mac and the phone footer (importance stops, row cap, failure states, consent gate, default sort)
spec: R58 C110 C210 C232 D30
needs: -
gate+: yes
do: iPad prints the raw stored importance (legacy 0.7 → '0.7', amber at ≥0.8) where the Mac prints the `ThreeBallScale` stop (0.7 → '1.0'); C210 buckets 0.7–1.0 to 1.0 (note-conn-06, recsj-071). iPad `load()` ends in `.prefix(relatedK = 4)` so 'Show all' (>7) never appears; the Mac shows 7 then 'Show all' (note-conn-11, recsj-069, R58). iPad `aiZone` has gate / finding / empty / list only: no downloading / preparing / indexing, and a failed lookup returns [] and reads 'No connections yet'; the Mac shows 'Connections unavailable' + the error (note-conn-09, recsj-076, -077, R58). iPad defaults to Closest and its comment says the Mac default is Closest (the Mac is Date) (note-conn-04, recsj-067). The compact phone footer loads Related and LINKED FROM with no rated/locked gate (note-conn-02, recsj-081; C215 `canSummon`). Change: importance through `ThreeBallScale`; the cap through `EmbeddingIndex.cappedRelated` with the Mac's 7; `RetrievalGate.derive` drives the iPad panel states and the failure line; one default (the Mac's Date, per the signed related-panel mock); the footer uses `NoteConsent.canSummon`. Phone test `ConnectionsRulesTests` (pure state/cap/bucket functions).
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh ConnectionsRulesTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P20

### Q120 [auto] (done) one backlink scan and one note-title-for-display helper in Shared
spec: C239 C115 C25
needs: Q114
gate+: yes
do: LINKED FROM exists in four implementations: phone `recomputeBacklinks` (MemoPageView.swift:718-743), iPad `scanBacklinks` (ConnectionsPanel.swift:584-606), Mac `backlinkScan` (ConnectionsPanel.swift:116-129) and `MemoLifecycle.backlinkedIDs`, which scans `transcript` only, so a Mac-made link that syncs into the copy-edit does not stop a note fading although the panel lists it (note-conn-08, recsj-074, note-editor missed). Titles for link chips and candidates come from five chains (phone `liveLinkTitle`, `memoLinkCandidates`; Mac `liveTitle`, `linkCandidates`; the Mac chain can return the cleaned filename 'memo_<uuid>' and overwrite a good snapshot, and does not skip trashed targets) (note-body-22, -23). One `Backlinks.scan(...)` over transcript + copy-edit with `MemoLinkSyntax.targets`, used by lifecycle, the panels and the footer; chips and candidates use the shared title ladder from the display-title item. Tests `BacklinkScanTests` (both targets), same fixture.
check: `grep -rqE "class BacklinkScanTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh BacklinkScanTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P21

### Q121 [auto] (done) iPad note player follows the Mac transport order; one speed list and one time format
spec: C115 C240
needs: -
gate+: yes
do: `PlayerBar` has `macTransportOrder` / density but its only call site is `PlayerBar(player:clock:)`, so the iPad dock shows play, back, forward where the Mac shows back, play, forward (note-player-02). Speeds: phone [1, 1.5, 2] with a label that knows only 1 and 1.5; Mac [0.75, 1, 1.25, 1.5, 2] (note-player-03). Time labels: Mac h:mm:ss, phone player and stats title m:ss only, so a long note reads 125:33 (note-player-04, list-sidebar-66). Mac `showsTransport` is true when `file.path` exists, a capture's path is its folder, so a dead dock likely shows on captures (note-player-06). Shared `PlaybackRates` and `DurationFormat` in Shared; iPad passes the Mac order; the Mac shows the dock only when an audio file exists. Test `DurationFormatTests` both targets; screenshot the iPad note dock, LOOK, `plan/reads/note-p-player/`.
check: `test $(ls plan/reads/note-p-player/*.png | wc -l) -ge 1 && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh DurationFormatTests && grep -rqE "class DurationFormatTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P22

### Q122 [auto] (done) Mac header chips read the shared date label and the shared source labels
spec: C78 C115 C240
needs: Q138
gate+: yes
do: The Mac date chip bypasses `MemoDate.label` and uses `SkriftFormat.breadcrumbDate` ('Fri, 19 Jun 2026', no time), while the Mac sidebar rows use `MemoDate` (note-header-01). One link reads 'Shared link' on the phone (its own `shareCaptureTypeLabel`, MemoDisplay.swift:306-314), 'Link' on the Mac list and header, and 'Shared link · domain' in the Mac strip (note-header-03, capture-source-03). Both apps read the label from `SourceKind` (SourceTaxonomy.swift). The Mac keeping a time-less date chip is a signed-mock call (mac-note-header.html): ask Tuur at the sitting if he wants the time added; do not change it here. Desktop test `MacHeaderChipLabelsTests`.
check: `grep -rqE "class MacHeaderChipLabelsTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P23

### Q123 [auto] (done) end-of-edit body normalisation is one rule on phone and Mac
spec: C10 C19
needs: -
gate+: yes
do: The phone calls `BodyV2.committed` at the end of an edit only when the text has picture runs; the Mac calls it on every end of editing (`.typed`, no manifest), which runs `BodyV2Text.normalised` and collapses whitespace runs and 3+ breaks, so the same keystrokes store different text on the two devices (note-body-04). C10 and C19 say the normalisation applies to every body. Make the phone `commitDraft` call the same entry for every note. Phone test `PhoneEndOfEditNormaliseTests`: a typed body with a double space and 3 blank lines stores the same string the Mac adapter stores.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh PhoneEndOfEditNormaliseTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P24

### Q124 [auto] (done) Mac note body is read-only while its transcription runs (C173)
spec: C173 C182
needs: -
gate+: yes
do: Phone `.reading` mode blocks edits while a note is transcribing so a draft cannot clobber the landing text, and shows a pill; the Mac `isEditable` is gated only by karaoke and 'Transcribing' appears only in the sidebar (note-body-06; the first audit row cited C263, the right clause is C173). Gate Mac `isEditable` on the pipeline state and show the same pill. Desktop test `MacBodyEditableStateTests` on the state mapping.
check: `grep -rqE "class MacBodyEditableStateTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P25

### Q125 [auto] (done) Mac: find in the note
spec: D125 C113
needs: -
gate+: yes
do: D125 decided yes; the phone has a find bar (NoteBodyView.swift:100, 600-602), the Mac has none (note-body-24; FEATURES.md:49 says Mac not built). Add the system find bar to the Mac editor (`NSTextView.usesFindBar` + ⌘F while the note has focus) and keep the existing search-hit flash. Never mix with the list search field's ⌘F: the shortcut item decides the final key. Desktop test `MacFindBarTests` asserts the text view enables the find bar.
check: `grep -rqE "class MacFindBarTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P26

### Q126 [auto] (done) Mac: checklist button and Return continues a task line
spec: C113 C234
needs: -
gate+: yes
do: Phone has a checklist button and Return-continuation (NoteBodyView.swift:640-668, 857-913); the Mac splices task boxes only when a note opens and has neither (note-body-13; FEATURES.md:45 'Return-continuation on the Mac not yet'). Share the continuation rule (`BodyTransform` task-line logic) and add the Mac Return handler plus a Format menu item. Desktop test `MacTaskContinueTests` on the pure rule.
check: `grep -rqE "class MacTaskContinueTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P27

### Q127 [auto] (done) Mac: the ⋯ menu of an unrated note offers Process (which floors the rating), Lock and Delete
spec: C40 D159 C187
needs: Q100
gate+: yes
do: Mac unrated note menu is copy-only: no Process, no Lock, no Delete. C40/D159 say pressing Process on an unrated note floors it to 0.1; the Mac note has no Process to press, the iPad does (note-menu-17, note-menu-16). Give the Mac unrated note the same `NoteMenuItem` set as the iPad (Process floors the rating through `NoteConsent`, Lock through the shared gate from the lock item, Delete soft). Desktop test `MacUnratedMenuTests`.
check: `grep -rqE "class MacUnratedMenuTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P28

### Q128 [tuur] (done) mockup: photos in a Mac note — add at the caret, tap to zoom and mark up, the picture with no file yet
spec: C119 D126 C113
needs: -
do: One clickable page: the Mac note with a photo added at the caret (open panel / paste / drop), a tapped photo opening the zoom + markup viewer, and a `[[img_NNN]]` whose file has not arrived yet (today it shows raw marker text; the phone shows a grey card and 'Downloading from iCloud…'). Draw today's Mac note and the phone's viewer from source (C117). Covers note-body-16, -17, -18, capture-import-41.
check: Mac photos mock (claude.ai/artifact/Li25ppmZmB5fVXHYCdHZxa): should one click on a photo select it like Apple Notes (double-click opens), or open the viewer straight away? Anything else to change before it gets built?
source: plan/reads/parity-audit.md P29

### Q129 [tuur] (dead) mockup: Mac reminders — set and clear from the note, the chip is tappable, the synced alarm rings on the Mac (D122)
spec: D122 C162
needs: -
do: One clickable page: the Mac note header chip becoming tappable (today a static chip with year), the picker (the phone's `ReminderSheet` drawn from source), 'Remind me…' in the list and note menus, and the notification the Mac shows when a synced reminder fires; first acknowledgement clears the other devices (C162). Covers note-header-06, note-menu-09, note-remind-01, list-sidebar-86.
check: Mac reminders mock (claude.ai/artifact/9SVbKnUhn2Re1wyUWcjiD5): when you close the Mac reminder banner with ✕, should that silence the iPhone and iPad too? Go to build?
source: plan/reads/parity-audit.md P30

### Q130 [tuur] (done) decide: boxed capture cards on the Mac against the no-bubbles rule
spec: C240 D135
needs: -
do: -
check: Tuur picked and the rule went into SPEC.
brief: Phone shared-text capture is a borderless italic quote (Tuur 2026-07-12, memory feedback_no_bubbles_on_shared_input, not in SPEC); the Mac draws a bordered, tinted 'SHARED CONTENT' card for all four capture types; the phone's own link and file cards are bordered boxes, so the rule is not uniform on the phone either (note-capture-02, capture-drain-07). Recommended: write the rule into SPEC with the exact scope (text quote only), then the Mac text capture draws the accent-bar quote and the other three keep their cards.
source: plan/reads/parity-audit.md P31

### Q131 [auto] (done) Mac new typed note: the Memo is created on the first keystroke, an empty one is discarded, the body has focus, place is stamped
spec: C43 D91 C112 D151
needs: -
gate+: yes
do: Mac `newTypedNote` (SidebarView.swift:370-375) calls `MacMemoAuthor.typedNote` at the click and saves it, so an untouched note leaves a quiet row titled 'Note' that syncs to the phone (list-sidebar-23, capture-quick-04, -05). The phone creates the Memo on the first non-empty edit and drops a blank one on leave (`QuickNoteDraft.edited`, `leave`). Nothing focuses the Mac body (capture-quick-07, unverified at runtime), and the Mac typed note keeps only the typed marker where the phone stamps place, weather and daypart (capture-quick-14; Q73 left the Mac as 'only if it has a location path', it has one: `MacLocationStamp`). Move the draft rules (`edited` guard, discard on leave) into Shared and use them from both; the Mac stamps place (and weather when the weather item lands). Desktop test `MacTypedNoteDiscardTests`: click then leave leaves no row and no `Memo`; first keystroke creates one. Never run SkriftDesktopUITests.
check: `grep -rqE "class MacTypedNoteDiscardTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P32

### Q132 [auto] (done) phone: the One note / N notes chooser at every door (Files importer, Open-in, AirDrop), through the shared AudioImportChoice
spec: C145 C68 C238
needs: -
gate+: yes
do: Q74 gave the Mac every door but said the phone 'already has' the chooser. It does not: the in-app Files importer loops `AppURLHandler.handle` per URL, so three m4a picked in Files or AirDropped become three notes without a question (list-sidebar-17, capture-import-08). The share sheet hand-writes the chooser strings (ShareSheetView.swift:388-405, 690-694) instead of reading `AudioImportChoice` (capture-import-09). Collect the URLs of one pick, show the chooser for 2+ audio files, merge through `AudioClipMerge` on 'One note'; the share sheet and the importer both read `AudioImportChoice`. Phone test `FilesImportChooserTests`.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh FilesImportChooserTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P33

### Q133 [auto] (done) ONE accepted-types list in Shared, used by Open-in, the share extension, the Files picker and the Mac ingest
spec: C238 C199 D19
needs: -
gate+: yes
do: Three audio lists: phone `AppURLHandler` (m4a mp3 wav aac caf aiff aif opus flac), share extension (adds ogg oga), Mac `IngestService` (m4a wav mp3 mp4 mov opus aac aiff caf: no flac, aif, ogg, oga); video lists differ too (Mac adds webm, mkv); the phone Files picker is `[.audio, .movie]` and cannot pick a PDF, text, markdown or image (capture-import-18, -19, -03). C199 says Open-in must accept what the share sheet accepts; C238 says no per-app accept list remains. One `ImportKinds` in `Skrift_Native/Shared/Pipeline/` (extensions → kind) and `allowedContentTypes` derived from it; both ingests dispatch on it. Overlaps the staged 'one shared import layer' (Later). Test `ImportKindsTests`: the same file names resolve to the same kind in both targets.
check: `grep -rqE "class ImportKindsTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh ImportKindsTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P34

### Q134 [auto] (done) one date ladder at every door: Files / AirDrop audio and video date from the filename, Mac images read EXIF, merged clips agree
spec: C70 R24 C74
needs: Q133
gate+: yes
do: Q94 fixed the share extension only. A Signal / WhatsApp file with no embedded date, picked in Files or AirDropped, is dated now on the phone and from its filename on the Mac (`MemoSaver.importAudio` never calls `FilenameDate`) (capture-import-28); phone video never reads filename or file date (capture-import-22); the Mac never reads EXIF for an image (`ImageDates` compiles into the phone and the extension only) (capture-import-17); merged clips: the phone lets the first clip's embedded date win, the Mac keeps the filename time; bundle ordering uses the full ladder on the phone and filenames only on the Mac, and `MixedBundle.ordered` has no 2 s equal-date rule (capture-import-11, capture-share-14). Make `FilenameDate.ladder` + `ImageDates` + the 2 s rule live in Shared and call them from `MemoSaver`, `CaptureInboxDrainer`, `SharePayloadLoader` and `IngestService`. Test `ImportDateLadderTests` on both targets with the same file names.
check: `grep -rqE "class ImportDateLadderTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh ImportDateLadderTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P35

### Q135 [auto] (done) pictures on import follow C74 on both apps: PNG stays PNG, GIF kept, downsample to 2048, no re-encode
spec: C74 D17
needs: -
gate+: yes
do: Phone `SharePayloadLoader.loadImages` always writes JPEG 0.85 at 2048 px, so a PNG becomes a JPEG and a GIF loses animation; the Mac `IngestService.writePictures` keeps PNG/GIF bytes with no cap and converts HEIC at 0.9 (capture-import-16). One shared `ImageNormalise` in Shared: PNG stays PNG, GIF unchanged, longest side ≤ 2048 (a downsample only when larger), HEIC/TIFF/BMP → JPEG 0.9. Test `ImageNormaliseTests` on both targets: a 3000 px PNG stays PNG at 2048; a GIF stays byte-identical.
check: `grep -rqE "class ImageNormaliseTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh ImageNormaliseTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P36

### Q136 [auto] (done) Mac accepts what the phone share accepts: .txt, PDF and URL, with link enrichment
spec: C77 D19 C72 C73
needs: Q133
gate+: yes
do: A Mac drop of `notes.txt` reports 'Couldn't import'; a PDF is refused (`ingestFile` returns nil); a web URL is skipped; the phone share makes a text capture, a PDF capture and a link capture with `LinkEnrichment` (description, thumbnail), follows a link that points at a PDF, and parses a Maps share to a place (capture-import-35, -36, -37, capture-drain-01..03). Move `PDFTextExtract`, `LinkEnrichment` and `PlaceLink` use behind Shared protocols and call them from `IngestService` for .txt, .pdf and URL drops (the `.md` question is its own decision). A Mac drop of the same file yields the same note kind and title as the phone share. Overlaps 'the one shared import layer' (Later). Desktop test `MacImportDoorsTests`; never hit the network in the test (stub the fetch).
check: `grep -rqE "class MacImportDoorsTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P37

### Q137 [auto] (done) import failures are shown on both apps: skipped files, a video with no audio, a folder of photos
spec: C199 C202 C77
needs: -
gate+: yes
do: Phone `AppURLHandler.handle` ignores an unsupported or failed file silently (list-sidebar-96, capture-import-24). Mac writes `coordinator.lastError`, which is rendered only inside an open pipelined note (NoteDisplayView.swift:183-198), so a drop with no note open shows nothing; a video with no audio track throws and creates no row where the phone creates a visible failed note 'Video had no audio track' (capture-import-23, C202); `ingestFolder` ignores pictures in a dropped folder with no skipped-file report. One shared `ImportReport` (created, skipped, failed with reason) shown as a list banner on both apps; the Mac video failure creates a failed note like the phone. Test `ImportReportTests` both targets.
check: `grep -rqE "class ImportReportTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh ImportReportTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P38

### Q138 [auto] (done) SourceKind.of reads the right blobs: phone captures and videos classify correctly; one classifier for rows, panes and projection
spec: C78 C239 C71 R36
needs: -
gate+: yes
do: `SourceKind.of(memo)` decodes `SharedContent` from `memo.metadataData` expecting a `{"sharedContent":{…}}` wrapper (SourceTaxonomy.swift:63-70, SharedContent.swift:39-44), but the phone stores the capture in the separate bare `Memo.sharedContentData` (Memo+Mobile.swift:35-38; `CaptureInboxDrainer` writes `sharedContent:` and no metadata wrapper); the unit test passes only because it seeds the wrapped shape into `metadataData` (SourceTaxonomyTests.swift:30-33). So a no-audio capture falls to `.appleNote`, `MemoNoteProjection.sourceType(for:)` projects an unrated phone capture as `.note` and the Mac pane skips `CaptureBanner` and `CaptureSharedContentBlock`, and the iPad Journal pane shows the wrong glyph (capture-source-01, source missed). Likewise `MemoMetadata` has no `CodingKeys`, a phone video encodes `sourceType`, `SourceKind.of` reads only `mediaSource`, so an unrated phone video reads as a voice memo on the Mac and in the iPad Journal (capture-source-06). Fix `SourceKind.of` to read `memo.sharedContent` and both keys; replace the three classifiers (`SourceKind.of`, Mac `sourceDescriptor`, phone `isShareCapture` helpers + `MemoDisplay` glyph table) with it. The test seed in `SourceTaxonomyTests` is the wrong shape: that protected-test change is the point of this item, hand-merge. Test `SourceKindRealShapeTests` seeds what the drainer really writes.
check: `grep -rqE "class SourceKindRealShapeTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh SourceKindRealShapeTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P39

### Q139 [auto] (done) MacMemoAuthor writes what a phone memo carries: mediaSource, clip manifest, photo assets
spec: R36 R34 C71 C124
needs: Q138
gate+: yes
do: `MacMemoAuthor.author` builds the Memo with no metadata and one audio `MemoAsset`: a Mac video import reads as a voice memo on the phone (capture-source-07); a Mac Apple Note or picture note authors a non-empty `audioFilename`, so `SourceKind.of` returns voiceMemo and the phone row shows a 0:00 duration (capture-source-08); photos of a Mac picture-only or clip+picture import and a Mac video frame never become `MemoAsset.Kind.photo`, so `[[img_NNN]]` markers cannot resolve on the phone (capture-source-20); the Mac clip manifest stays in a local `clip_manifest.json`, so a Mac-merged note loses its paragraph breaks on a phone re-transcribe (capture missed note). Author the metadata blob (`mediaSource`, location, clip manifest), the photo assets and the right `audioFilename` for note, capture and video kinds. Whether a `.mov` blob keeps its name on the phone is unverified: the test round-trips it. Desktop test `MacAuthoredMemoShapeTests`; phone test `MacAuthoredMemoReadTests` reading a fixture the Mac wrote.
check: `grep -rqE "class MacAuthoredMemoShapeTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh MacAuthoredMemoReadTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P40

### Q140 [auto] (done) phone quick-note Delete is a soft delete like every other delete
spec: C212 C90
needs: -
gate+: yes
do: `QuickNoteDraft.discard` does `context.delete`, a hard delete, where `MemoDetailView.deleteCurrent` uses `repository.softDelete` and C212 says delete is soft everywhere (capture-quick-15). Keep the confirm (C212 allows it), route Delete through `softDelete`; an untouched empty draft still vanishes silently (D91). Phone test `QuickNoteSoftDeleteTests`.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteSoftDeleteTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P41

### Q141 [auto] (done) an Apple Note import is dated to its creation date, or shows date unknown, never the import moment
spec: C76 D18
needs: -
gate+: yes
do: `IngestService.ingestNote` builds the `PipelineFile` without `uploadedAt`, so the note takes the import time (capture-import-32). C76/D18: creation date from the export or 'date unknown', never the import time. Read the export's creation date where it exists; otherwise store nil and show 'date unknown'. Desktop test `AppleNoteDateTests`.
check: `grep -rqE "class AppleNoteDateTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P42

### Q142 [auto] (done) exported frontmatter source: a typed note says the same thing from phone and Mac
spec: D65 C57
needs: Q138
gate+: yes
do: The shared source map has no typed value: the same typed note exports `source: Voice-memo` from the phone (`MemoExporter` maps typed to `.audio`) and `source: Apple-Note` from the Mac (capture-source-11). Add a typed value to `Compiler`'s source map, set by both exporters from `SourceKind`. Test `ExportSourceFieldTests` both targets, one typed-note fixture.
check: `grep -rqE "class ExportSourceFieldTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh ExportSourceFieldTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P43

### Q143 [auto] (done) Mac note shows captures like the phone: image pixels, link description + thumbnail, PDF first page, the typed thought, an honest banner
spec: C119 D126 C25
needs: Q138
gate+: yes
do: Mac review of an image capture draws a glyph and a file name, no pixels, though the images are on disk (note-capture-03); the Mac link block drops description and thumbnail (capture-drain-06); a PDF shows a doc card with no first page, page chip or text disclosure (note-capture-04, capture-drain-08; C119 'approved, not built', D126 decided the inline render; no PDFKit in SkriftDesktop); `annotationText` rides the metadata blob but nothing in Features/Review shows it as the lead of a non-capture note (note-capture-09); the capture banner says 'Enhancement-lite still ran: title, tags, summary…' on every capture, false for an unrated one (capture-drain-13); the Mac has no 'Add a note about this…' placeholder (note-capture-06). Build these on the Mac from the data it already has. Screenshots from the synthetic corpus, LOOK, `plan/reads/capture-p-mac/`.
check: `test $(ls plan/reads/capture-p-mac/*.png | wc -l) -ge 3 && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P44

### Q144 [tuur] (done) mockup + key: Mac records weather and daypart (the OpenWeatherMap key row on the Mac)
spec: C237 D92 R36
needs: -
do: A Mac recording or typed note carries place only: no weather, no daypart, no steps, no chips (recsj-024, setexp-37, capture-quick-14; R36 lists it as required). The Mac has no weather key row and no `weatherAPIKey`. One page: the Mac Settings row for the key (draw the phone's from source) and the chips on a Mac note header. Needs his key typed by him; nothing is entered by the agent.
check: Mac weather mock (claude.ai/artifact/43NTAjUbFrB6C8vHw1NL3m): should the Mac take the OpenWeatherMap key from the phone over iCloud, or have its own field? Go to build?
source: plan/reads/parity-audit.md P45

### Q145 [tuur] (done) decide: a plain .md file — Apple Note on the Mac, Text capture on the phone
spec: C76 C77 D19
needs: -
do: -
check: Tuur picked one kind for a .md file and it went into SPEC.
brief: The same `.md` file becomes a note of kind 'Apple Note' with the heading as title on the Mac (`IngestService.ingestNote`) and a shared 'Text' capture (UTF-8, ≤ 512,000 bytes) on the phone (`CaptureInboxDrainer`) (capture-import-34). Recommended: a `.md` is a typed note whose body is the file (kind note, no capture card), title from the first heading, on both. He picks; then it is one rule in `ImportKinds`.
source: plan/reads/parity-audit.md P46

### Q146 [tuur] (done) decide: keep the source movie of an imported video (C63/C148) or drop the synced-asset plan
spec: C63 C148 C71 D153
needs: -
do: -
check: Tuur picked and SPEC C63/C148 follow.
brief: C63/C148 want a video filed Inspiration / Idea / Project to keep its source movie as a SYNCED asset (≤ ~200 MB) exported from whichever device exports it. Today neither side does it: the Mac keeps every imported movie locally for any destination (`IngestService.swift:364-384`, stale comment at :355 still says 'NOT kept'), the phone keeps none and its share card says 'the video file itself isn't kept'; `MemoAsset.Kind` has no video kind, so it also needs a CloudKit schema deploy (capture-import-21, setexp-94). Choose: build the synced asset (schema deploy owed) or drop the plan and delete the Mac copy.
source: plan/reads/parity-audit.md P47

### Q147 [auto] (done) book cover colour and name avatar colour are stable (no per-process hashValue)
spec: C229 C115
needs: -
gate+: yes
do: `BookCoverView` picks 1 of 5 gradients with `abs(book.id.uuidString.hashValue) % 5` under a 'stable across launches' comment; Swift `hashValue` is seeded per process, so the colour likely changes each launch and differs between phone and iPad for one synced book (books-10). The phone Names avatar does the same with `abs(name.hashValue) % 4` where the Mac uses a stable 31-hash, and initials differ (first+last word vs first two) (setexp-104). One shared stable hash (FNV or the Mac's 31-hash) and one initials rule in Shared. Test `StableHashTests` both targets: the same id gives the same index.
check: `grep -rqE "class StableHashTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh StableHashTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P48

### Q148 [auto] (done) Books: the shelf tile shows what the row shows, and the delete dialog does not say iPhone on an iPad
spec: C229 C218
needs: -
gate+: yes
do: Row: author line, determinate transfer bar with 'Uploading audio · 38%', live re-align status. Tile (iPad): title only (author only in the a11y label), a bare `ProgressView()` with no label or fraction, no `BookTextActivity` line, and its a11y label omits the sync state (books-20, -21, -22, -23, -24). 'Remove from this iPhone only' and 'removes … from this iPhone' have no iPad variant (books-30). Give the tile the author line, the transfer fraction and the re-align line; use 'this device' in the delete dialog. Phone test `BookTileStateTests` (pure label/fraction functions); screenshot the iPad shelf, LOOK, `plan/reads/books-p-shelf/`.
check: `test $(ls plan/reads/books-p-shelf/*.png | wc -l) -ge 1 && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh BookTileStateTests && ./gate.sh`
source: plan/reads/parity-audit.md P49

### Q149 [auto] (done) one quote attribution builder and one quote-block splitter
spec: C172 C60
needs: -
gate+: yes
do: Attribution is built three ways: `MergedCaptureView` hand-builds '— author, ' + italic title + ', ch. N' with no empty-author guard ('— , Title'); `CaptureQuote.attribution` drops an empty author and joins chapter with ' · '; the vault line uses ', ch. ' (books-101, -117); `MemoDisplay.bookCaptionLabel` re-implements the chapter-prefix rule (books-105). Quote splitting has three parsers: `CaptureQuote.split` (blank-line and indent tolerant), `QuoteProtection.splitLeadingQuote` (`hasPrefix('>')` at offset 0), `MemoDisplay.quoteSnippet`; a body with a leading blank line or an indented '>' displays as a quote but is copy-edited, name-linked and exported as plain text (books-116). C172: no second splitter. One `CaptureQuote.split` and one `attribution` used by the preview, caption, polish escrow, linking and export. Test `QuoteSplitParityTests` both targets, same fixtures.
check: `grep -rqE "class QuoteSplitParityTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuoteSplitParityTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P50

### Q150 [auto] (done) audio of an hour or more offers Audiobook vs Voice note at Open-in and the Files importer, not only in the share sheet
spec: C79 C145
needs: Q132
gate+: yes
do: Only the share extension (`hasLongClip`, ShareSheetView.swift:35-37) offers Books for audio ≥ 1 h; Open-in, AirDrop and the Files importer make a memo with no Books offer (books-82; plan/extraction/ingress.md:396 records 'Book only via share'). Offer the same choice at those doors, reusing the share sheet's choice type. Phone test `LongAudioOfferTests`.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh LongAudioOfferTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P51

### Q151 [auto] (done) Library: per-book 'N notes' pill and jump-back (D127, Q6 mock)
spec: D127 C229
needs: -
gate+: yes
do: The Q6 mock signed a '❝ N' pill opening a book's notes and a jump-back to the audio position. Nothing reads `bookID` / `bookPosition` beyond the writer in `MemoSaver` (books-115; FEATURES.md:227 says join key only). Count and open a book's capture notes through `MemoMetadata.bookID`, and jump the player to `bookPosition`. Phone test `BookNotesJoinTests`; screenshot per the Q6 mock, LOOK, `plan/reads/books-p-notes/`.
check: `test $(ls plan/reads/books-p-notes/*.png | wc -l) -ge 1 && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh BookNotesJoinTests && ./gate.sh`
source: plan/reads/parity-audit.md P52

### Q152 [tuur] (dead) mockup: 'Fix quote' — correct a misheard word inside a captured quote (D50)
spec: D50 C160 C172
needs: -
do: D50/C160 decide the user can correct a misheard word in a captured quote; the quote block is read-only on the phone and (after the Mac read-only item) on the Mac, and no 'Fix quote' verb exists anywhere (books-118). One page: the verb in the note menu, the edit state of the quote, and how the corrected text stays attached to the audio window.
check: Fix-quote mock (claude.ai/artifact/Xoe9ccY5K7yHysRUMyBxrP): is fixing one word at a time plus 'Include next word' enough for real mishearings, or do you want to free-type over the whole quote?
source: plan/reads/parity-audit.md P53

### Q153 [auto] (done) export: file name, title, link stems and date: phone and Mac produce the same file for one note
spec: C57 C64 C165 D65
needs: Q114
gate+: yes
do: iPad names the file from `exportTitle` (user title, else first body line, never the polished title) while its frontmatter title prefers `enhancement.title`; the Mac names the file from `pf.enhancedTitle`; the export ledger is per device, so one note can end up as two files (setexp-90, -95). `date:` is the phone's local day `yyyy-MM-dd` while the Mac passes none and `Compiler` takes `prefix(10)` of the stored string, so a note recorded at 23:30 can differ (setexp-91, R15, C64). One shared `ExportNaming.stem(...)` (C25 title ladder + C165) and one local-day function, both exporters call them. Overlaps the staged 'Target 4 export v2' (Later). Test `ExportNamingParityTests`: a corpus note recorded at 23:30 with an enhanced title gives identical stem and `date:` through both bridges.
check: `grep -rqE "class ExportNamingParityTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh ExportNamingParityTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P54

### Q154 [auto] (done) export: picture markers become embeds the same way on both exporters; a dangling marker is dropped
spec: C57 C196 R51
needs: -
gate+: yes
do: Phone `convertPhotoMarkers` drops dangling markers and uses `profile.imageMarkdown` (`![[x]]` vault, `![](x)` portfolio); Mac `convertImageMarkers` leaves unresolvable markers as literal `[[img_NNN]]` and always writes `![[x]]` even for a portfolio note, and resolves by filename / the N-th file where the phone uses the manifest (setexp-93). C196: a dangling marker is dropped, never printed. One shared converter in `VaultWrite`/`ExportProfile`. Test `ExportImageMarkerParityTests` both targets: a portfolio note gets `![](x)`, a missing file leaves nothing.
check: `grep -rqE "class ExportImageMarkerParityTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh ExportImageMarkerParityTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P55

### Q155 [auto] (done) export: one CompilerInput builder (voice, body source, link stems) on both exporters
spec: C196 C57 R37
needs: Q153 Q142
gate+: yes
do: Two builders: phone `MemoExporter.compilerMetadata` (voice from `enhancement.hasContent` = copy-edit OR title OR summary → cleaned; body = copy-edit else raw, re-linked on device) and Mac `CompilerBridge` (voice from a non-empty copy-edit; passes sanitised, copy-edit and transcript separately): a title-only enhancement is 'cleaned' on the phone and 'raw' on the Mac (setexp-88, -89). Move the input building into `Skrift_Native/Shared/Export/` with one `CompilerInput.make(...)`; equality of the two bodies (C81) gets a test. Overlaps 'Target 4 export v2' (Later). Test `CompilerInputParityTests` both targets.
check: `grep -rqE "class CompilerInputParityTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh CompilerInputParityTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P56

### Q156 [auto] (done) export gate and refusal sentences: one predicate and one set of strings
spec: C61 C194
needs: -
gate+: yes
do: iPad `shouldPublish` checks folder, trash, lock, rated, body/title, processed; Mac `VaultExporter.export` checks lock, two-versions hold and non-empty folder only and leaves rating / trash / processing to callers; `reexportEdited` checks locked + deleted but not rated (setexp-70). Refusal wording differs ('No vault folder is set on this device yet…' vs 'Set your Obsidian vault path in Settings first.'), the Mac portfolio note with no portfolio folder throws `noVault` and tells the user to set the Obsidian vault path (setexp-71, -72), the locked refusal has four wordings (setexp-73), and the two-versions hold is Mac-only so the iPad exports a note the Mac would hold (setexp-75; the hold is Mac-only in `EditConflictHold`, SPEC D139 does not require it on the iPad: leave the hold, name the difference in the refusal table). One `ExportGate.check(note, device)` returning the first failing gate, and `ExportOutcomeCopy` owning every refusal sentence. Test `ExportGateParityTests` both targets.
check: `grep -rqE "class ExportGateParityTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh ExportGateParityTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P57

### Q157 [auto] (done) Mac polish prompt: blank falls back to the default, Reset to default, and a blank never syncs
spec: C28 C150
needs: -
gate+: yes
do: iPad Save is disabled on a blank prompt, an empty prompt falls back to the shared default, and there is 'Reset to default'. The Mac autosaves any text including blank; `EnhancementService.run` sends prompt + text with no fallback; no Reset; a blanked Mac prompt polishes with an empty prompt and syncs as an empty blob, which the iPad then treats as 'default' (`adoptSynced` removes the key), so two devices polish with different prompts for one synced value (setexp-48, settings missed note). Route the Mac text through `PolishPromptsStore` rules (empty = default), add Reset, and never push an empty blob. Test `MacPromptBlankTests` against the store rule.
check: `grep -rqE "class MacPromptBlankTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P58

### Q158 [auto] (done) export author name is one synced setting
spec: C62 D162
needs: -
gate+: yes
do: Two unsynced stores: iPad `@AppStorage skrift.publish.author` (shown only when a folder is picked and the device can process) and Mac `AppSettings.authorName`; the export file comment demands identical bytes from both devices, but a blank iPad author writes `author: ` where the Mac writes the name (`Compiler.swift:89`), so hash and edit guard differ per exporter; an iPad that never opened Settings after picking a folder exports with a blank author (setexp-61, settings missed note). Sync the author as one LWW setting the way Q98 synced the destinations switch; the iPad field is always shown. Test `AuthorSyncTests` (round-trip + LWW).
check: `grep -rqE "class AuthorSyncTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh AuthorSyncTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P59

### Q159 [auto] (done) Settings sync wording from shared copy: what syncs, the iCloud account note, language footer, model sizes
spec: D119 C217
needs: -
gate+: yes
do: Phone iCloud footer lists notes, names, custom words and per-book audiobooks; the Mac help mentions only memos and polish although its one switch also gates names, vocab, language, destinations and prompts (setexp-13, settings missed). Only the Mac says it needs the same iCloud account (setexp-15). The Mac prints the shared `ASRLanguageMode.footer` (says it syncs), the phone prints its own and never says so (setexp-25). Model sizes: Parakeet '494 MB' vs '~0.6 GB', Gemma '8.9 GB' / '~9 GB free' vs '~9 GB' (setexp-42). Put each sentence and size in `SharedCopy` / `ModelSizes` and read them from both. Test `SettingsCopySharedTests` (usage assertion like the SharedCopy item).
check: `grep -rqE "class SettingsCopySharedTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh SettingsCopySharedTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P60

### Q160 [auto] (done) names: delete a person confirms first and pushes at once; the phone Names list refreshes on sync
spec: R79 C266 R67
needs: -
gate+: yes
do: Delete-person fires with no confirmation on all four entry points (PersonEditorView.swift:218-223, PersonDetailView.swift:116-120, PersonEditor.swift:102-110 → SettingsView.swift:55-59) (setexp-118, R79); `PersonDetailView.deletePerson` does not call `NamesCloudSync.run`, so its tombstone waits for a sweep; the Mac listens for `.namesDidChangeFromSync`, the phone Names list reloads only on appear and after an edit (setexp-119, R67). Add a confirmation at every entry point, push at once, and observe the notification on the phone. Phone test `NamesDeleteConfirmTests` (pure confirm-state), desktop test `NamesSyncRefreshTests`.
check: `grep -rqE "class NamesSyncRefreshTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh NamesDeleteConfirmTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P61

### Q161 [auto] (done) Mac can turn semantic indexing off; one name for the feature on Settings and in the panel
spec: C110 C232
needs: -
gate+: yes
do: The Mac only ever sets `isEnabled = true` (ConnectionsIndexService.swift:61); there is no Settings control and consent cannot be withdrawn, where the phone has a 'Semantic journal index' switch (setexp-55, recsj-080). The feature has three names: 'Semantic journal index' (phone/iPad Settings), 'Find connections between your notes' / 'Turn on Connections' (Mac panel) (setexp-51). Add the switch to Mac Settings and read the names from `RetrievalGate.Copy`. Desktop test `MacIndexConsentTests`.
check: `grep -rqE "class MacIndexConsentTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P62

### Q162 [tuur] (done) mockup: the Mac shows iCloud sync state — a Settings row, the in-list capsule, a signed-out message
spec: D119 C217
needs: -
do: The phone has an iCloud status row ('Syncing… / Up to date') and an in-list 'Syncing with iCloud…' capsule; the Mac observes CloudKit events only to trigger sweeps and shows no state, and BUGS.md:184 notes the old pill reads dead Bonjour state; a failed Mac container (`MemoCloudContainer`) silently disables sync, and neither app tells the user note sync is off when signed out (setexp-12, -14, -16, -18, -130). One page: the Mac Settings sync row, the capsule above the sidebar list, and the signed-out / failed state on both apps; the Mac's 'CloudKit sync with the Mac' switch (default on) shown with what it gates.
check: Mac iCloud mock (claude.ai/artifact/7wi8J65uDFC1oCu3d6H8AL): when sync is broken or off, should the note list show a capsule until it's fixed, or only Settings say so?
source: plan/reads/parity-audit.md P63

### Q163 [auto] (done) Mac recorder survives a kill: segments + launch sweep, and a disk-full stop saves what landed
spec: C99 D131 R46 C224
needs: -
gate+: yes
do: The phone writes `rec_seg_<take>_NNN.m4a` segments every 60 s plus a marker and rebuilds an interrupted take on launch (Q16/Q27); a full disk stops the take, saves what landed and titles it with the reason (R46). The Mac has neither: no recovery code (grep `recoverInterrupted`, `RecordingCheckpoint`, `applicationWillTerminate` finds nothing in SkriftDesktop or Shared), and `MacRecorder` only logs 'write failed' (MacRecorder.swift:598-603) (recsj-034, -033). A route/device loss with signal held tears the take down with no message (recsj-029). Port the segment + marker + launch sweep to `MacRecorder` through the shared recovery core; a write failure stops the take, keeps the file and titles the note; a device loss tells the user in the draft pane. Desktop test `MacRecoverySweepTests` with a synthetic orphan segment set (no microphone). This is data loss: sequence first. Never use the real microphone in a test. Never run SkriftDesktopUITests.
check: `grep -rqE "class MacRecoverySweepTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P64

### Q164 [auto] (done) phone: a take with no signal is a dead take, like the Mac; denied or restricted mic shows an alert with Open Settings
spec: C222 C224
needs: -
gate+: yes
do: Phone discards only a take shorter than 0.4 s (RecordView.swift:561); a long silent take saves as a note (no signal check exists in SkriftMobile); the Mac fails on size ≤ 1024 B or no non-zero sample and fail-fasts at 1.5 s (MacRecorder.swift:310-314, 396-401) (recsj-014). A refused mic on the phone shows 'Nothing recorded' after the fact with no Settings button, retries 16 × 300 ms silently and logs only to DevLog; permission is requested only in OnboardingView:119 (list-sidebar-20, recsj-013). Put the 'saw a signal' verdict in `RecordingCore`, call it from both; the phone shows the Mac's typed refusal with 'Open Settings'. Phone test `DeadTakeVerdictTests`; this is hardware-flavoured: the sim cannot prove the mic path, so the device check stays with Tuur.
check: `grep -rqE "class DeadTakeVerdictTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh DeadTakeVerdictTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P65

### Q165 [auto] (done) Mac live recording shows the model state and a loading placeholder, like the phone
spec: C220 C224
needs: -
gate+: yes
do: The phone recorder shows Downloading / Preparing / ready / Couldn't load / not downloaded and a caption placeholder while the model loads; the Mac awaits `TranscriptionService.beginStream()` with no UI, so loading looks like silence (recsj-005, -006). Put the strings in shared recording copy and show them in `RecordingDraftView`. Desktop test `MacRecordingModelStateTests` on the state mapping.
check: `grep -rqE "class MacRecordingModelStateTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P66

### Q166 [auto] (done) Review reads one note set: Calendar and Map exclude fading notes, Then vs Now uses the same input, map pins clear on a real gesture
spec: C212 C87 C233
needs: -
gate+: yes
do: Only `JournalHomeView.reload` partitions fading from live; `JournalCalendarView.onAppear` and `JournalMapCanvas.onAppear` (`PlaceCluster.build(from: canonicalMemos())`, JournalMapView.swift:87) read the unpartitioned list, which includes fading notes (recsj-113). Then vs Now: the phone reads `repository.allMemos()` (including fading), the Mac the live partition, so the phone can pick a fading note (recsj missed). Mac `onMapCameraChange` does not clear the pinned place on a real pan or zoom (the phone does since b89) and its heading shows `shownMemos.count` but renders `prefix(20)` (recsj-100, -101). One `ReviewNotes.live(...)` in Shared used by every Review surface; the Mac map clears on a gesture and shows an honest count. Tests `ReviewNoteSetTests` both targets.
check: `grep -rqE "class ReviewNoteSetTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh ReviewNoteSetTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P67

### Q167 [auto] (done) Review dots and print-to-wall read the three stops, so a legacy 0.7 is Important everywhere
spec: C210 D30 C233
needs: -
gate+: yes
do: Phone `ImportanceDots` uses ≥0.8 / ≥0.4 thresholds (JournalHomeView.swift:410) where the Mac uses `ThreeBallScale.step`: 0.7 shows 2 dots on the phone, 3 on the Mac (recsj-095). `WallPrinter` prints at ≥0.8 where C233/C210 say the top ball (0.7 buckets to 1.0), so a legacy 0.7 note never prints (recsj-090). Both read `ThreeBallScale`. Phone test `ImportanceStopsTests`.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh ImportanceStopsTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P68

### Q168 [auto] (done) semantic index embeds the same text on every device; the Mac warms the embedder on the first search keystroke
spec: C87 C231 C110
needs: -
gate+: yes
do: Phone passes user title + annotation + enhancement title / summary / copy-edit to `SemanticSearch.snapshot`; the Mac passes `userTitle: nil`, `annotation: nil`, polished = sanitised ?? copy-edit, from PipelineFile rows only, so the same note embeds differently per device (recsj-079). The phone warms the engine on the first search keystroke; the Mac does not (a warm-up exists in ConnectionsPanel.swift:78 when a note opens) (recsj-058, list-sidebar-37). Have the Mac build its snapshot from the `Memo` + `MemoEnhancement` the phone uses, and warm on search. Desktop test `MacEmbeddingSnapshotTests`.
check: `grep -rqE "class MacEmbeddingSnapshotTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P69

### Q169 [auto] (done) Review note row uses the source glyph; map and Way-out entry glyphs agree
spec: C78 C115
needs: Q138
gate+: yes
do: Phone `JournalMemoRow` hard-codes `Image(systemName: "mic")` for every note, the iPad day row uses the `SourceKind` glyph, the Mac card shows none (recsj-094). The Way-out entry is an SF leaf glyph + unread dot on the phone and a '🍂' emoji with no dot on the Mac, and the Mac count adds Mac-local trash (list-sidebar-106, recsj-104). Use `SourceKind.glyph` in all three rows and one entry-row view. Phone test `ReviewRowGlyphTests`.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh ReviewRowGlyphTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P70

### Q170 [tuur] (done) decide: Mac look-back anchors on the selected day; Mac gets pause / resume and a discard; Mac Add recording
spec: C231 C220 D122
needs: -
do: -
check: Tuur picked per question and FEATURES.md / SPEC follow.
brief: Three calls. (1) Mac `river(for:now: selectedDay)` re-anchors Looking back on the selected calendar day; the phone and iPad always anchor on today and the journal-desktop mock says 'same rules as the phone' (recsj-086). (2) The Mac recorder has no pause / resume and no way to discard a take; the phone has both and its X discards with no confirm (R71/C262 open); FEATURES.md:21 lists the Mac '➖' with no decision behind it (recsj-010, -015). (3) The Mac has no 'Add recording' to an existing note although it can record (note-menu-03, capture-quick-16, recsj-045; FEATURES.md:30 '➖'). Recommended: (1) anchor on today, matching the mock text; (2) build pause and a confirmed discard; (3) build it.
source: plan/reads/parity-audit.md P71

### Q171 [auto] (done) single-source the UI strings and views written twice (twin-same rows)
spec: C239 C240
needs: -
gate+: yes
do: Rows where the two apps agree today only because two copies were typed: the status chip view and `dateChipLabel` (list-sidebar-38, -44), the Connections sub-captions and the `connectionsHiddenPairs` key (recsj-068, -078), the 'starts fading … — rate it to keep it' suffix typed three times (capture-quick-12), the Mac note-header chip drawing (note-header-09), the 'best match first …' lines, the toggle-notes-list chip (the Mac `sidebarToggle` is a hand copy of `PanelToggle`, list-sidebar-08) and the Record / New note / Import button views (list-sidebar-18, -21). Move each to `Skrift_Native/Shared/UI/` with a per-app style struct (C240); no `#if os()` in a shared view (the existing `DateRangeStrip` has one at lines 66-74: remove it, list-sidebar-45). No behaviour change; screenshots before and after for each moved view are identical (`plan/reads/twin-p-ui/`).
check: `test $(ls plan/reads/twin-p-ui/*.png | wc -l) -ge 2 && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P72

### Q172 [auto] (done) single-source the logic written twice (twin-same rows)
spec: C239 C240
needs: -
gate+: yes
do: appTheme → ColorScheme (SkriftApp.swift:272-278 and Theme.swift:105-120, setexp-08); `summaryMinWords` 75 in `PolishEscrow` and `AppSettings` (setexp-36); the tag ranking in `NotesRepository.allTags` and twice in the Mac (`TagLibrary.mostUsedFirst` + an inline sort) (note-tags-04); the add-custom-word rule (setexp-31); names sort re-done on the Mac instead of `NamesMerge.sortPeople` (setexp-102); soft delete's `deletedAt` + `trashSeenAt` pair hand-written at 5 Mac sites where `bringBack` is shared (list-sidebar-89); the fading sweep loop twice over `MemoLifecycle.sweepDue` (`FadingSweep` vs `MacFadingSweep`); `PhoneMetadata` in `CompilerBridge.swift:19-35`, a second decoder of the shared `MemoMetadata` (books-102); `PictureOnlyBody` marker loop re-typed in `CaptureInboxDrainer` (capture-import-14); the picture-only/standalone chip rules. Each becomes one Shared function, both apps call it, a test per function. No behaviour change.
check: `grep -rqE "class TwinLogicSharedTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh TwinLogicSharedTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P73

### Q173 [auto] (done) small phone bugs and dead code the audit turned up
spec: C115 C229
needs: -
gate+: yes
do: Phone onboarding shows a green check for the permission step whatever the user answered, and sets the location flag at once (`OnboardingView.swift:117-128`, setexp-125); `ObsidianSettingsSection.pickError` is never cleared after a later success (setexp-60); `sleepLabel` has no caller (books-48); `ChaptersBookmarksRail` has no call site (books-64); `NotesBottomChrome.recordButton` and `showRecordButton` are dead after D136 (list-sidebar-101); the Settings text 'Sync this book to my devices' names a menu item that reads 'Sync this book…' (books-87); the player idle-recede guard `!isRegular` cites a retired layout (books-49). Fix the two bugs; delete the dead code with its tests. Phone test `OnboardingPermissionStateTests`.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh OnboardingPermissionStateTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md P74

### Q174 [auto] (done) FEATURES.md and plan/parity.md match the code again
spec: C239
needs: -
do: Stale rows found by the audit: FEATURES.md:119 (iPad list '320-420 draggable', it is fixed 375), :61 vs :126 (⌘N), :377 (Quick note Desktop n/a, the Mac has the compose chip), :53 (search-hit flash Mac ➖, it jumps), :238 (quote rendering Desktop n/a), :161 (captures 'Mobile n/a' predates iPad polish), the 'Quote protection in enhancement' row (omits phone `PolishEscrow`), the 'Custom vocabulary sync' row (~:292, Desktop 'not built', it exists), :120 ('unlocked' in the Process pile); plan/parity.md:44 name resolutions 'deliberately not' (SPEC C81/D20 say sync). SPEC wording for C220 ('Mac rotates at 7 s', code is 20 s) and C199/C145 stays with Tuur: list them in the commit message. Edit only FEATURES.md and plan/parity.md.
check: `./gate.sh`
source: plan/reads/parity-audit.md P75

### Q175 [tuur] (done) approve the twin gate: add plan/twin-check.sh to gate.sh
spec: C239 C240
needs: -
do: -
check: Tuur approved the hook and ran `./plan/twin-check.sh --baseline` once.
brief: Section 6 of plan/reads/parity-audit.md has the script. gate.sh and plan/ are protected, so the item is the hand-merge: add `plan/twin-check.sh`, generate `plan/twins.baseline`, and add one line to `gate.sh` before xcodegen. It also gives C239 its named `plan/twins.md` (generated from `--report`), which does not exist today.
source: plan/reads/parity-audit.md P76

### Q176 [auto] (done) settings + names: one copy set and one names filter on phone, iPad and Mac
spec: C239 C240 R58
needs: -
gate+: yes
do: Rows setexp-29 -30 -53 -54 -58 -59 -67 -99 -101 -103 -109 -112 -113 (plan/reads/parity-audit.md §3.5). Move every Settings and Names string typed twice (custom-word field + help, index progress lines, Obsidian folder row + help, destinations on-without-folder text, names empty state, voice-state words, person editor titles/buttons, full-name help + placeholder) into Shared copy and delete the per-app literals. Fix the stale ones: phone names empty state 'so the Mac can link their names' (C80/D77), phone editor 'record in a note or on your Mac' which contradicts the detail recorder. One shared names matcher (display name OR alias) used by phone 'Search people' and Mac 'Filter names…'. Index sweep failure shows on phone/iPad as on the Mac (R58), same toggle behaviour after a failed download on both. Name row size from one shared token set. Winner per row: a signed mock or SPEC clause if one names it; otherwise the phone's wording and look; keep a Mac-only extra only when it carries information (a shortcut in a tooltip, a failure line). List every pick in the commit message so Tuur can veto. Never run SkriftDesktopUITests. Desktop test `SharedSettingsCopyTests` (names matcher + strings come from Shared).
check: `grep -rqE "class SharedSettingsCopyTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md §3 (uncovered shareable rows, added 2026-10-02)

### Q177 [auto] (done) list + note chrome: one copy and token set (headers, empty pane, fallback word, search field, locked screen, new-note label, title placeholder)
spec: C239 C240 C161 C25
needs: Q108
gate+: yes
do: Rows list-sidebar-04 -09 -11 -31 -35 -57 -63, note-empty-01, capture-quick-03 -09, note-lock-01. Empty detail pane: one string and glyph on iPad and Mac. Day and RELATED section headers: one shared header style (size, tracking, colour). Selected-row fill: one accentSoft token in Palette (iPad 0.13 vs Mac 0.16 today). Phone uses the shared SearchField instead of its inline copy, and both clear buttons get the a11y label. Fallback word for a note with no title and no words: `SourceKind.emptyTitleFallback` on Mac rated rows too. New-note button: a11y label and tooltip on both. Mac title field on a brand-new note shows 'Add a title' (today the prompt is displayTitle, likely empty). Locked note screen: one shared copy including 'hidden, not encrypted' (C161). Winner per row: a signed mock or SPEC clause if one names it; otherwise the phone's wording and look; keep a Mac-only extra only when it carries information (a shortcut in a tooltip, a failure line). List every pick in the commit message so Tuur can veto. Never run SkriftDesktopUITests. Desktop test `ListChromeCopyTests`.
check: `grep -rqE "class ListChromeCopyTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md §3 (uncovered shareable rows, added 2026-10-02)

### Q178 [auto] (done) Way-out: one intro, row meta line and urgency colour rule on phone, iPad and Mac
spec: C239 C240 D136
needs: Q108
gate+: yes
do: Rows list-sidebar-109 -110 -111, recsj-107. Mac `WayOutColumn` hard-codes 30 days and says the iPhone does permanent deleting; read the constant from `Shared/Pipeline/WayOut.swift` and use the shared copy. One meta-line builder (date, place, duration, deleted/replaced word) and one urgency-colour rule (fading and deleted, inside 3 days) in Shared, called by `WayOutView` and `WayOutColumn`. Winner per row: a signed mock or SPEC clause if one names it; otherwise the phone's wording and look; keep a Mac-only extra only when it carries information (a shortcut in a tooltip, a failure line). List every pick in the commit message so Tuur can veto. Never run SkriftDesktopUITests. Desktop test `WayOutDisplayTests`.
check: `grep -rqE "class WayOutDisplayTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md §3 (uncovered shareable rows, added 2026-10-02)

### Q179 [auto] (done) every source glyph and label comes from SourceKind: delete the phone's second glyph table, fix the Mac picture-only import label, journal rows use it
spec: C78 C239 C240
needs: Q106 Q138
gate+: yes
do: Rows list-sidebar-65 -68, capture-import-15, capture-source-02, books-114. Delete the capture glyph table in `SkriftMobile/Models/MemoDisplay.swift:257-265`; callers read `SourceKind`. A Mac picture-only import (IngestService.swift:224-231) reads 'Image' like a phone image share, not 'Capture'. Phone `JournalMemoRow` stops hard-coding 'mic' and the Mac journal card gets the glyph, both from `SourceKind.of`. Mac rows (rated and quiet) show the source chip for video and audiobook quote and the shared-item title + domain chip — check what P7 already did and finish only the rest. Desktop test `SourceGlyphParityTests`.
check: `grep -rqE "class SourceGlyphParityTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md §3 (uncovered shareable rows, added 2026-10-02)

### Q180 [auto] (done) note menus: list context menus, Redo and Copy transcript follow one rule set from NoteMenu
spec: C239 C240 C179 C161
needs: -
gate+: yes
do: Rows list-sidebar-83, note-menu-07 -13. Both list context menus build from `Shared/UI/NoteMenu.swift` `NoteMenuItem`, with any per-platform absence declared there with its reason (NoteActions.swift:59-63 documents Lock/Remind absent on the Mac). Redo: one availability rule in NoteMenu (iPad = any part exists, Mac = all three today) and the phone's compact dialog gets Redo. Copy transcript: one rule on both — empty says 'Nothing to copy yet', locked authenticates then copies. Winner per row: a signed mock or SPEC clause if one names it; otherwise the phone's wording and look; keep a Mac-only extra only when it carries information (a shortcut in a tooltip, a failure line). List every pick in the commit message so Tuur can veto. Never run SkriftDesktopUITests. Desktop test `NoteMenuParityTests`.
check: `grep -rqE "class NoteMenuParityTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md §3 (uncovered shareable rows, added 2026-10-02)

### Q181 [auto] (done) Connections panel: one width, header, why-chips and hide verb on iPad and Mac
spec: C239 C240 R58
needs: Q119
gate+: yes
do: Rows recsj-066 -070 -072 -073, note-conn-03 -07 -10. One panel width and header constant in Shared (300 vs 280, 11 vs 10pt today). Why-chips from one shared builder over `Shared/Retrieval/ConnectionWhy.swift`: iPad passes the real name lists (it passes empty today, so no person chip), cap 3 + '+N', colour per kind. Hide a pairing: one wording and available on flat and Date-rail rows on both (the Mac Date rail, its default, has no hide). Date-rail date line one size. Winner per row: a signed mock or SPEC clause if one names it; otherwise the phone's wording and look; keep a Mac-only extra only when it carries information (a shortcut in a tooltip, a failure line). List every pick in the commit message so Tuur can veto. Never run SkriftDesktopUITests. Desktop test `ConnectionsPanelParityTests`.
check: `grep -rqE "class ConnectionsPanelParityTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md §3 (uncovered shareable rows, added 2026-10-02)

### Q182 [auto] (done) Journal: one Then-vs-Now picker, one calendar grid builder, one first-day rule, one intro copy
spec: C239 C240 D136
needs: -
gate+: yes
do: Rows recsj-084 -088 -091 -092. Move the recents → related-scores → pick loop (JournalIndexService.swift:136-151 and JournalView.swift:112-136) into `Shared/Retrieval/ThenVsNow.swift`; both read the same partition (phone reads allMemos incl. fading, Mac the live partition — use what SPEC's fading rules allow; if silent, the live partition, and say so in the commit). One calendar grid builder (makeCells/gridDays, weekday symbols) and one dot rule in Shared. One first-day rule (today) for phone Calendar, iPad pane and Mac. Review intro sentence into Shared copy. Winner per row: a signed mock or SPEC clause if one names it; otherwise the phone's wording and look; keep a Mac-only extra only when it carries information (a shortcut in a tooltip, a failure line). List every pick in the commit message so Tuur can veto. Never run SkriftDesktopUITests. Desktop test `JournalParityTests`.
check: `grep -rqE "class JournalParityTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md §3 (uncovered shareable rows, added 2026-10-02)

### Q183 [auto] (done) conversations: phone karaoke uses KaraokeTrack, split speakers has Cancel and a read-only body on the phone, speaker sheet shows the all-turns line
spec: C239 C240 C124
needs: -
gate+: yes
do: Rows note-speaker-07, note-split-03, note-speaker-01. Phone conversation karaoke (SpeakerTurnsView.swift:124-125, 205-216) uses `Shared/Pipeline/KaraokeTrack.swift` like the Mac and the phone monologue, not `Karaoke.activeWordIndex` (word N = timing N, no alignment). Split speakers on the phone: shared progress copy (`SplitSpeakersCopy`), a Cancel, and the body read-only while it runs, as on the Mac. Phone 'Who is Speaker N?' sheet shows `SplitSpeakersCopy` namesAllTurns like the Mac popover. Phone test `ConversationKaraokeTests`.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh ConversationKaraokeTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md §3 (uncovered shareable rows, added 2026-10-02)

### Q184 [auto] (done) one new-person-from-a-name flow and one note-link picker on phone and Mac
spec: C239 C240 C81
needs: Q113
gate+: yes
do: Rows note-name-06, note-body-21. New person from a name in the note: one shared flow — check 'already in your names' first, prefill name and alias, save through PersonEditCore, re-derive the note. Today the phone skips the check and the Mac does it. Note-link picker: one title, search placeholder, empty-state text and row cap from Shared copy (phone 'Link a note' no empty text, Mac 'Link a note…' 'No notes match' 50 rows). Desktop test `NewPersonFromNameTests`.
check: `grep -rqE "class NewPersonFromNameTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md §3 (uncovered shareable rows, added 2026-10-02)

### Q185 [auto] (done) note look tokens in Shared: inline photo size, memo-link chip, top band, list toggle
spec: C239 C240
needs: -
gate+: no
do: Rows note-body-15 -19, note-chrome-01 -02. One shared token file (e.g. `Skrift_Native/Shared/UI/NoteLook.swift`): inline photo max size (phone fills column max 320pt, Mac ~360pt), memo-link chip look and title cut (phone '→ Title' accent-soft 28 chars, Mac '🗒 Title' bordered full), top band padding and hairline (14 vs 18), list-toggle label ('Hide notes list' vs 'Hide the notes list'). Both apps read the tokens. Winner per row: a signed mock or SPEC clause if one names it; otherwise the phone's wording and look; keep a Mac-only extra only when it carries information (a shortcut in a tooltip, a failure line). List every pick in the commit message so Tuur can veto. Never run SkriftDesktopUITests. Prove the look with a Mac headless `-snapshot` PNG and a phone sim screenshot attached to the run log.
check: `test -f Skrift_Native/Shared/UI/NoteLook.swift && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md §3 (uncovered shareable rows, added 2026-10-02)

### Q186 [auto] (done) import bundling and audio export follow one rule on phone and Mac
spec: C68 C239 C240
needs: -
gate+: yes
do: Rows capture-import-13, setexp-92. One accept set in `Shared/.../MixedBundle.swift`: voice clips + pictures + text become one note on both (the Mac refuses .txt today, IngestService.swift:314-323); a video joins the bundle per C68 on both, or record why not in the commit. Original audio into Recordings/: the Mac honours a Mac-local `includeAudioInExport`, the phone always copies; sync the setting (the way destinations sync) and both honour it. Desktop test `ImportBundleParityTests`.
check: `grep -rqE "class ImportBundleParityTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md §3 (uncovered shareable rows, added 2026-10-02)

### Q187 [auto] (done) small twins: polish prompt row order, transcribe-book copy, quote-note header chips, recording waveform heights
spec: C239 C240 C172
needs: -
gate+: no
do: Rows setexp-47, books-75, books-109, recsj-009. Polish prompts in one order on iPad and Mac (Copy-edit, Summary, Title vs Copy-edit, Title, Summary). One transcribe-book battery/overnight copy set in Shared for TranscribeBookView, BookTextSheet and ReadAlongView. Phone quote-note header shows the 'Audiobook quote · <title>' and duration chips like the Mac (NoteProperties.swift:140-150). Phone `RecordWaveform` uses `Meter.height(at:)` from `Shared/Recording/RecordingCore.swift` instead of its own mapping. Winner per row: a signed mock or SPEC clause if one names it; otherwise the phone's wording and look; keep a Mac-only extra only when it carries information (a shortcut in a tooltip, a failure line). List every pick in the commit message so Tuur can veto. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/parity-audit.md §3 (uncovered shareable rows, added 2026-10-02)

### Q188 [auto] (done) delete the dead audio-trim machinery in quote capture
spec: C240
needs: -
gate+: no
do: `applyTrim`, `TrimResult` and `isUnchangedTrim` in `SkriftMobile/Services/Audiobooks/QuoteCaptureProcessor.swift` (the "Apply trim" block, lines 208-296) have no production caller; Q89 removed `process()` and left these. Delete them, then the fields only they read: `QuoteCaptureOutput.bufferSentences`, `bufferOffset`, `spanEnd` (both initialisers) and `BufferSentence.isInInitialSpan`; drop the `snappedStart`/`snappedEnd` parameters (every production caller passes 0, 0) from `buildSentences`, `AlignedSentenceSource.sentences`, `asrFallback` and the call sites `ReadAlongView.swift:96-97`, `MergedCaptureView.swift:384,393`, `QuoteCaptureProcessor.swift:98`. Extract the shared bounds/slice/export/rebase block of `buildOutput` and `buildOutputFromSidecar` into one private helper. Keep `exportSpan`, `bufferAudioURL`, `audioURL`, `quote`, `duration`, `wordTimings`, `spanStart`. Tests: delete `testTimingRebaseFormula`, `testApplyTrimTranscriptAndSpan`, `testTrimRebaseDataContract`, `testTrimExpandToContextSentence` and the `isUnchangedTrim` cases (`AudiobookCaptureMathTests.swift:74-193`, `QuoteCaptureSaveTests.swift:123-212`); edit the `BufferSentence(isInInitialSpan:)` and snapped arguments in `AlignedSentenceSourceTests.swift` (86-100 asserts non-zero snapping, delete those), `TextCaptureTests.swift:43-57` and the buildSentences cases in `AudiobookCaptureMathTests.swift`. Fix the stale docs: `QuoteCaptureProcessor.swift:22-47,71`, `AlignedSentenceSource.swift:44`, the `applyTrimIfNeeded` pointer at `QuoteCaptureSaveTests.swift:125-126`, and `FEATURES.md:236`. Re-grep every symbol by NAME in both apps and tests before deleting; a hit outside its own definition and its own tests means keep and report. Protected-test deletions need Tuur's yes (hand-merge). Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuoteCaptureSaveTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAS-d01 MAS-d02 MAS-c05 MAU-d-m1 (cleanup-audit P1)

### Q189 [auto] (done) audiobook services: small dead code, one interruption rule, comment fixes
spec: C240
needs: -
gate+: no
do: Delete in `SkriftMobile/Services/Audiobooks/`: the single-URL `importBook(from:libraryDirectory:)` overload (`AudiobookImporter.swift:86-91`); `BookBundle.typeIdentifier` (`BookBundle.swift:43-45`) and the `SkriftBookUTI` line and its comment in `SkriftMobile/project.yml:227-229` (keep `SkriftBookExtension`; xcodegen drops the generated Info.plist key); the `starts` parameter of `publishValue`/`publishProgress` and `let starts` at `BookTranscriptionJob.swift:129,181,242,253,397-402`; `AttachSummary.rejectedFiles`, `AttachOutcome.rejected` and the `rejected` counter in `BookAlignment.swift:338,421,436-470`; the unused `derivedSidecars(bookID:)` parameter (`BookBundle.swift:258` and the two callers at 79 and 138); the write-only `levelObserver` (`BookTranscriptionJob.swift:79,478`); the computed `Audiobook.audioFilename` (`Audiobook.swift:76-77`; keep the init label); the redundant `segments.count >= 2` at `ChapterDetector.swift:188`, the unused 999 default on `Heading.init` (name the sentinel `fileStartGap`), and the no-op `total` in `spelledValue` (`ChapterDetector.swift:644-659`); the duplicate chapter-duration loop (`ChapterDetector.swift:539-543`, `BookAlignment.swift:1436-1448`) into one `[AudiobookChapter].fillingDurations(bookDuration:)`. `AudiobookLibraryStore.sortedByRecent` returns `BookSort.recentlyPlayed.sorted(books)` (`Audiobook.swift:535-546`). Move `InMemoryAudiobookTransport` (`AudiobookAudioTransport.swift:48-85`) into `SkriftMobileTests` beside `AudiobookCloudSyncTests`; keep the protocol in the app. Make `resumeAfterInterruptionIfOurs` call `shouldResumeAfterInterruption` and keep its per-branch DevLog lines, `isActive` becomes `var isActive: Bool { book != nil }` (`AudiobookSession.swift:30,136,187,592-648`); the 4 `AudiobookInterruptionTests` stay and now guard the shipped path. `ReadAlongView.swift:78` calls `FileTranscript.isCovered`. Fix comments: `BookTranscriptionJob.swift:336-343` ("~2 s", `chunkLead` is 3.0), `BookTranscriptStore.swift:161-175` (`removeTranscripts` backs the "remove transcript" action only). `sleepLabel` is Q173. Re-grep every symbol by NAME first; a hit outside its own definition and own tests means keep and report. Moving a test double is a protected-test change (hand-merge).
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh AudiobookLibraryStoreTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAS-d04 MAS-d05 MAS-d06 MAS-d07 MAS-d08 MAS-d09 MAS-d11 MAS-d13 MAS-d15 MAS-d-m1..m4 MAS-c29 (cleanup-audit P2)

### Q190 [auto] (done) audiobook plumbing: stop hashing the ePub, one attached-text setter, one folder-path owner
spec: C239
needs: Q189
gate+: no
do: (1) `FileAlignment.epubSignature` is documented as compared nowhere and read nowhere (`BookAlignment.swift:136-140,970`), yet every attach and stale re-align reads the whole ePub into memory and SHA-256s it. Keep the field and its Codable shape (persisted in `alignment_f<n>.json`, give it `= ""` so old sidecars still decode); stop computing it: delete `sha256Hex`, the CryptoKit import, `epubSig`/`epubSignatures` plumbing and the two `Data(contentsOf:)` reads (`BookAlignment.swift:1,416,439,452,581,596,617,859-871,942,1452-1454`). Do NOT touch `AudiobookSyncRecord.epubSignature` (the live manifest signature, `AudiobookCloudSync.swift:558-599`). Update the tests that pass `epubSignature:` to `mergedFileAlignment` (`BookAlignmentTests.swift:502,520,541`, `OdysseyRealDataDiagnostics.swift:112`). (2) `Audiobook.setAttachedTexts(_:)` sets `epubFilenames` and the legacy `epubFilename` together; use it at the five write sites (`BookAlignment.swift:510,714,994`, `AudiobookCloudSync.swift:595`, `BookBundleManifest.swift:148`) and collapse `detachedTextFields` to the filtered list; both fields stay Codable. (3) One `AudiobookPaths` enum (root and `folder(for:)`) used by `AudiobookLibraryStore`, `BookTranscriptStore`, `BookAlignmentStore`, `BookmarkStore` and the four `BookTranscriptStore().folder(forBookID:)` calls in `BookAlignmentRunner`; folder layout and file names do not change. (4) One shared file-signature function for `BookAlignmentStore.sidecarSignature` and `BookTranscriptStore.signature(forFileAt:)`; one file-size helper for the five `attributesOfItem` reads; `Audiobook.fileStart(_:)`/`fileDuration(_:)` clamped accessors for the 8 `indices.contains(i) ? a[i] : 0` sites. Never remove a persisted or synced field.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh TextDetachTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAS-d10 MAS-d14 MAS-c02 MAS-c17 MAS-c18 MAS-c24 (cleanup-audit P3)

### Q191 [auto] (done) audiobook CloudKit sync: one sidecar helper, one tolerant continuation, shared decode
spec: C239
needs: Q190
gate+: yes
do: In `AudiobookCloudSync.swift` the transcript and alignment sidecar sets (`transcriptRecordName/Filename/RecordNames/Parts/Refs`, `sendTranscripts`; lines 410-467 vs 602-657) are the same code. Add a small `SidecarKind` (record-name infix, filename format, signature closure, key path to the carrier signature) and one generic `parts/refs/recordNames/send`. The record-name infixes `_t`, `_al`, `_txt` and the sidecar file names are CloudKit wire names and must stay byte-identical; keep both receive functions separate (transcripts restamp, alignments verdict-gate and derive chapters) and leave the ePub manifest block alone. In `CloudKitAudiobookTransport.swift:145-185` one async helper for the tolerant continuation (`unknownItem` counts as success) shared by download and delete; upload stays strict. `setDownloadRemoved(_:_:defaults:)` for the three `removedDownloads` read-modify-writes, an `AudiobookSyncRecord.book` accessor for the five `JSONDecoder().decode(Audiobook.self, ...)` calls, and one iCloud container-id constant used by `AudiobookCloudSync` and `NotesRepository` (the Mac copy `SkriftDesktop/App/MemoCloudContainer.swift:25-27` may import it if Shared; if not, leave it). Existing `AudiobookCloudSyncTests` and `CloudSignaturePartTests` must stay green unchanged.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh AudiobookCloudSyncTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAS-d12 MAS-c26 MAS-c27 (cleanup-audit P4)

### Q192 [auto] (done) BookAlignment: one align-one-text helper, single-text mergeSentences
spec: C239
needs: Q190
gate+: no
do: In `SkriftMobile/Services/Audiobooks/BookAlignment.swift`: (1) `mergeSentences` (771-847) carries a second structure (`appended`, `appendedRemoved`, `appendedTextFiles`, `(inKeep, idx)` tuples) only for an incoming batch that mixes texts, which no caller does (the one caller `mergedFileAlignment:865`, every test in `MultiTextMergeTests`/`AudiobookCostTests` use one `textFile` per batch). Assert that precondition, drop the second structure and the `inKeep` flag; contests happen only between different texts, so incoming sentences never contest each other. Keep the Q57/C218 binary search and the same-text no-contest rule. (2) The per-file align loop (load transcript, skip empty, progress string, `alignFile`) and the transcript-signature loop appear in both `attach` and `alignIfNeeded`; extract one align-one-text helper that takes a progress closure (they differ in sink, `Task.yield` and the `deferring` flag), and one `transcriptSignatures(for:)`. Compute `AttachOutcome`'s aligned/rejected/total from `perFile` so it collapses into `TextAlignOutcome`. Do not change the order assess, pre-check, blobs, commit. Result of `MultiTextMergeTests`, `PerTextChapterMarksTests` and `BookAlignmentStoreTests` must be identical.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh MultiTextMergeTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAS-c06 MAS-c09 (cleanup-audit P5)

### Q193 [auto] (done) audiobook screens: dead state, orphan comments, small shared pieces, a toast bug
spec: C240
needs: Q173
gate+: no
do: In `SkriftMobile/Features/Audiobooks/` and the files named: delete the unused `ChaptersBookmarksSheet.initialTab` stored property, its custom init and `AudiobookPlayerView.tocInitialTab` with its two assignments (give `tab` a default `.chapters`; keep the `Tab` enum); delete `session` (`MergedCaptureView.swift:67`), `touched` (71, 425), `repository` (`SyncedAudiobooksView.swift:10`), `dismiss` (`AudiobookSyncSheet.swift:14`); delete the orphan "Attach book text (spike 6)" MARK and its two doc comments (`AudiobookLibraryView.swift:648-660`) and the stray `@ViewBuilder` at 425, rewrite the player class doc (speed and sleep moved to the utility row) and the mini-bar width comment (the chevron was cut), remove `ContinueListeningCard.swift:71` DevLog; inline `AudiobookPlayerView.content(_:)` into `body` (the `!isRegular` idle-recede guard is Q173); keep one UIActivityViewController wrapper (move to `DesignSystem/Components.swift`, update `BookShareSheet.swift:113` and `MemoDetailView.swift:488`); `BookTextSheet.swift:101-132` becomes one status toast fed by `busyMessage ?? (textActivity.isActive(book.id) ? textActivity.stage : nil)`; a store helper for the fresh-alignment half shared by `ReadAlongView.swift:84-91` and `MergedCaptureView.swift:376-379` (leave the two ASR fallbacks separate: MergedCaptureView windows the words before `buildSentences`); `Audiobook.isFinished` replaces the predicate in `BookStatusFilter.matches`, `BookShelfTile.isFinished` and `progressLabel`; `AudiobookSyncSheet` uses `BookTextDisplay.durationText` and the `BookShareCopy.subtitle` doc is corrected (check the format against the book-sharing mock first; `BookShareCopyTests` pins `BookTextDisplay.durationText`); `BookTranscriptionJob.isWorking(on:)` for the four `activeBookID == book.id && isRunningOrPaused` sites; `MergedCaptureView` uses `createdMemoID != nil` instead of `handedOff` and throws one `QuoteCaptureError` so one catch shows the failure toast; one `captureWindow` helper for the 90 s look-back in `AudiobookPlayerView.swift:543-547` and `MergedCaptureView.swift:93-94`; `ContinueListeningCard.today()` uses a `static let` formatter. Bug: `Player.showToast` (`AudiobookPlayerView.swift:485-491`) clears after 1.6 s without checking the text, so a second toast inside that window is cleared early; add the same text guard `showSplitToast` has (`MemoDetailView.swift:835-841`).
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh BookTextSummaryDisplayTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAU-d04 MAU-d05 MAU-d06 MAU-d07 MAU-d08 MAU-d10 MAU-d13 MAU-d16 MAU-d17 MAU-c14 MAU-c18 MAU-c21 MAU-c23 MAU-c29 (cleanup-audit P6)

### Q194 [auto] (done) retire TranscribeBookView: the read-along nudge opens the Text sheet
spec: C240 C115
needs: Q193
gate+: no
do: `TranscribeBookView.swift` is reachable only from the read-along nudge (`ReadAlongView.swift:427` to `AudiobookPlayerView.swift:165`, `showTranscribe`); `BookTextSheet` Level 1 shows the same status, progress, ETA and start/pause/resume. Tuur decides: the nudge would open the two-level Text sheet (`bookTextBook = book`) instead of a one-purpose sheet (the audiobook-player-redesign mock routes the nudge to the old sheet, so a signed mock changes). If yes: first port the one thing only `TranscribeBookView` shows, the `.failed(why)` "Stopped: ..." line (`TranscribeBookView.swift:127-132`; the job sets `.failed` at `BookTranscriptionJob.swift:179,250` and BookTextSheet never reads it, so a plain delete would make a failed transcribe silent); then delete the file, `showTranscribe` and its `.sheet`, `reflectSavedProgress` and `estimatedRemainingSeconds` (`BookTranscriptionJob.swift:98,135`); move `shortDuration` (`BookTextSheet.swift:331,346`, `BookTextPromptSheet.swift:105`) into `BookTextDisplay`; fix the comments at `AudiobookPlayerView.swift:284` and `BookTextSheet.swift:9,341`; trim Q187's transcribe-book copy clause. Test: `BookTextSummaryDisplayTests` gains a failed-phase case.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh BookTextSummaryDisplayTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAU-d02 MAU-c01 (cleanup-audit P7)

### Q195 [auto] (done) shared book sheet pieces: progress bar, grabber, scaffold, glass chrome, labelled field
spec: C239 C240
needs: Q193
gate+: no
do: In `DesignSystem/Components.swift` add `ThinProgressBar(fraction:height:fill:)` (BookShareSheet, BookImportSheet, BookTextSheet, BookShelfTile; the shelf tile turns green when finished, so the fill is a parameter), `SheetGrabber` (the 34 and 36 pt capsules in `AudiobookSyncSheet`, `BookTextPromptSheet`, `TextSettingsSheet`, `BookShareSheet`, `BookTextSheet`, `BookImportSheet`, `ChaptersBookmarksSheet`; keep the drawn handle, the signed mocks draw it, do not switch to the system indicator), `LabeledTextField` and a cancel/confirm row for `AudiobookImportConfirmSheet` (move it to its own file) and `EditBookDetailsView`, a `miniGlass(height:)` modifier plus one `.bookSessionCovers(showPlayer:showCapture:)` for `AudiobookMiniPlayerBar.swift` bar and pill (keep the two layouts), and a `BookTransferSheet` scaffold for `BookImportSheet` and `BookShareSheet` (cover view and detents stay parameters). In the same sheets: compute `totalBytes` once, drop the phases that render like the one before them (`.done`, `.landed`), `packagedBytes`, `attachedTexts`; keep `guard case .packaging = phase` in the progress callback (it blocks late callbacks after cancel); a `.textCard()` modifier for the three card chrome sites in `BookTextSheet`. Sheets must look the same: render the sheets headlessly (`-showTextSheet` etc.) before and after and compare.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh BookShareCopyTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAU-d09 MAU-d14 MAU-d15 MAU-c11 MAU-c12 (cleanup-audit P8)

### Q196 [auto] (done) memo detail: dead conversation mock, unused state, imports, stale comments
spec: C240
needs: Q199
gate+: no
do: In `SkriftMobile/Features/MemoDetail/` and the files named: delete `ConversationMockView.swift`, the `LaunchFlags.conversationMock` flag and RootView branch (`App/LaunchArgs.swift:47-48`, `App/SkriftApp.swift:290-291`) and `testConversationMock` (`SkriftMobileUITests/ConversationMockUITests.swift:13-23`; the other tests in the file stay, including `testRealConversationMemoRendersTurns`); then make `SpeakerTurnsView.speakerSlots` required and delete the first-appearance fallback (`SpeakerTurnsView.swift:8-12,31-43`; only the mock ever passed no slots). Delete `exportedBump` and its comment fragments (`MemoDetailView.swift:57-60,255-257,815`; the re-render already comes from `exportFlash = nil`). Delete `QuickLookTarget` (`MemoPageView.swift:23-29`) and change `photoWasEdited` to take `marker: Int?` at the three sites. Delete the `Coordinator.init(memo:onCommit: () -> Void)` convenience (`NoteBodyView.swift:264-269`) and change the 12 test sites to `onCommit: { _ in }` (`NoteBodyTests` x11, `QuotePresentationTests.swift:177`; `{}` would not satisfy the `(Bool) -> Void` form). Drop `enroll:` from `assign(_:to:enroll:slot:turnSlots:)` (`MemoPageView.swift:194,196,909,919-921`). Remove the 8 unused import lines (`MemoDetailView.swift:4-6`, `MemoDetailSupportTypes.swift:2-6`, `MemoPageView.swift:4`; keep MemoPageView's PhotosUI and FluidAudio). `SpeakerTurnsView.segmentItems` uses the static `BodyV2Marker.regex` instead of compiling one per turn per render (do NOT switch to `BodyTransform.pieces`, it also tokenises tasks and links). The compact dialog uses `NoteMenuItem` labels for lock, share, copy and delete (`MemoDetailView.swift:462-467`). Fix stale comments: `MemoDetailView.swift:8-13,36-38,427-431,663-667,743-745`, `MemoPageView.swift:45,141,148-155,389-393,1547`, `NoteBodyView.swift:338,521` ("Q14 removes it": `BodyV2Legacy.swift:3` says Q14 kept it), `ConnectionsPanel.swift:4-16,47-53` (the importance doc sits on the wrong declaration), `MemoDetailSupportTypes.swift:78-82`. Do not touch `PlayerBar.density` (Q121), `ConnectionsPanelLogic.ordered` (after Q181) or the draft/selection probes in `NoteBodyView` (an open device bug). Re-grep every symbol by NAME first.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh NoteBodyTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MMD-d01 MMD-d02 MMD-d03 MMD-d05 MMD-d07 MMD-d13 MMD-d14 MMD-d15 MMD-d16 MMD-c08 (cleanup-audit P9)

### Q197 [auto] (done) move the v1 body fixtures into the tests: Paragrapher.paragraphed and ImageMarkers.insert
spec: C240
needs: -
gate+: no
do: `Paragrapher.paragraphed` and `defaultGap` have no production caller (`Shared/Pipeline/Paragrapher.swift:20-21,32-79`); `plan/RUN.md:109` records that Q80 kept `paragraphed` only as the fixture for `BodyNormaliseMigrationTests.swift:49`. `ImageMarkers.insert` (`Shared/Pipeline/ImageMarkers.swift`, 63 lines) is used in production only by the phone's `SeededTranscriber` (`SkriftMobile/Services/Transcription/TranscriptionService.swift:300-318`); real transcription uses `BodyV2.committed` (`ASRPostProcess.swift:60-68`). Make `SeededTranscriber` call `BodyV2.committed` the same way. Move the v1 paragraph splitter and the v1 marker inserter into `BodyNormaliseMigrationTests` as one private fixture helper (both test targets compile it; the Mac and phone test files each get their own copy only if they share no file), delete `ImageMarkers.swift`, `Paragrapher.paragraphed`/`defaultGap`, `ParagrapherTests` cases for them, the two `ImageMarkers` cases in the transcription-logic tests (`SkriftMobileTests/TranscriptionLogicTests.swift:54-84`, find the class name with grep), and fix the doc at `SkriftMobile/Models/FillerFilter.swift:33`. Keep `Paragrapher.endsSentence` and `longFormGap` (live in `LiveCaptionEngine`). Run the photo-bearing `MemoSaverTests` that use `SeededTranscriber` (e.g. `MemoSaverTests.swift:47`): they will now see v2 placement; if any expectation changes, list it in the commit message. Protected-test edits: hand-merge after Tuur's yes.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh MemoSaverTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SPL-d01 SPL-d02 (cleanup-audit P10)

### Q198 [auto] (done) shared pipeline: unused overloads, always-default parameters, stale headers
spec: C240
needs: -
gate+: no
do: In `Shared/Pipeline/` (all compiled into both apps; re-grep each symbol by NAME in both apps and all tests first): delete `Karaoke.activeWordIndex(_:at:hint:)` (`Karaoke.swift:26-38`); `TranscriptionResult.durationMs` and the `durationMs` parameter of `ASRPostProcess.finish` with the three engine fills and the 22 test/stub constructions (`TranscribingContract.swift:14`, `ASRPostProcess.swift:31-69`, both `TranscriptionService.swift`, `StubEngines.swift:18`; the assertion at `ASRPostProcessTests.swift:26` goes); `SplitSpeakersCopy.rateFirstShort` only if Tuur confirms (it is signed Q86 copy: keep by default), `ASRLanguageStore.mode(defaults:)`, `VocabularyTermParsing.canonical(_:)` (+2 tests), `KaraokeTrackCache.invalidate()`, `CommitOnceCache.invalidate()` (`ProcessPile.isDone` is Q102's); the explicit `AlignmentCore.Config.init` and `SpeakerTranscript.Turn.init` (keep memberwise; `Karaoke.swift:75` calls `Config()`, tests call `.init(anchorN: 2)`); the unreachable `?? timings[0].start` and final `out.map { $0 ?? firstKnown }` in `Karaoke.wordTimes`; `EPubTOCEntry.fragment` and the second tuple value of `splitFragment` (11 test constructor lines); reduce `Karaoke.seekTarget` to the in-range check plus clamp and port `QuoteSeekTests.swift:28` to `KaraokeTrack.seekTime`; inline the rms/wordCount overload of `shouldDropAsPhantom` (`BPEMerge.swift:72-93`, 5 test lines) and flush `pending` directly in `mergeBPETokens`; `KaraokeTrackCache` becomes a `CommitOnceCache<KaraokeTrack.CacheKey, KaraokeTrack>` at `SkriftDesktop/Features/Review/NoteBody.swift:38` and both `KaraokeTrackTests:63`; delete the redundant `distantPast` guard at `LanguageSyncCore.swift:34-39` (keep the "never broadcast a default" sentence); merge the two `collectBlocks` branches and drop `ManifestItem.id` in `EPubParse.swift` (keep `lenientParse`). Fix the stale headers (`Karaoke.swift:40-71`, `AlignmentCore.swift:8-14`, `Paragrapher.swift:11-15,23-29`, `MemoSpine.swift:5-9`). Do not touch `ASRLanguageStore.isMultilingual`, `Karaoke.seekTime(forWord:in:)` or `Paragrapher.endsSentence`.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh KaraokeTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SPL-d04 SPL-d05 SPL-d06 SPL-d08 SPL-d10 SPL-d15 SPL-d16 SPL-d17 SPL-d18 SPL-c02 SPL-c07 SPL-c17 SPL-c18 SPL-c20 (cleanup-audit P11)

### Q199 [auto] (done) lifecycle and spine: delete the unbuilt queue states, one ceil-days, one displayRange
spec: C240
needs: Q102
gate+: yes
do: (1) `MemoSpine` (`Shared/Pipeline/MemoSpine.swift`): `QueuePhase`, `Input.queue`, `Input.macLocalFile` and the Station cases `.processing`, `.stuck`, `.ready`, `.exported` are never built by production (all 11 callers use `.from(memo, backlinked:)`); delete them with their `oneLiner` arms and `testActiveTrackFollowsTheQueuePhase` in both `MemoSpineTests`; collapse the rated branch to `if input.rated { return .toProcess }`; delete the explicit `Input.init` (inline defaults) and fix the header (it claims the Mac builds this from `Memo + PipelineFile`). Keep `.toProcess` and its one-liner. (2) `MemoLifecycle.daysUntilSweep` has no production caller: delete it and its 3 asserts per test file (6 lines in all). `MemoSpine.daysUntil` calls `WayOut.daysLeft(until:now:)`; one shared `days(_:)`; rename `MemoLifecycle.fadesAt` (it returns the trash date) to `trashesAt` (`WayOut.swift:23`, `WayOutViewTests`, `MemoLifecycleTests:52`); `WayOut.isUrgent` uses one pattern `case .fading(let d), .deleted(let d)`. (3) `BodyTransform.displayRange(forRaw:in:)` becomes `displayRanges(forRaw: [raw], in: text)[0]`; delete the private unused `NoteBodyView.Coordinator.displayRange(forRaw:transcript:)` (`NoteBodyView.swift:548-555`); delete `displayLength` (use `r.length - 1`); fix the stale comments `BodyTransform.swift:74-77,92-93`. Coordinate: Q102 edits `ProcessPile.isDone`; do not touch it here. Do not touch `MemoLifecycle.goneAt` (P43 owns it). Protected-test edits: hand-merge after Tuur's yes.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh MemoSpineTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SPL-d03 SPL-d07 SPL-d11 SPL-c20 SPL-c30 MMD-d06 (cleanup-audit P12)

### Q200 [auto] (done) one number-word table for AlignmentCore and ChapterDetector
spec: C239
needs: -
gate+: no
do: `AlignmentCore.swift:286-340` and `SkriftMobile/Services/Audiobooks/ChapterDetector.swift:607-668` hold the same EN and NL units/teens/tens tables, the linking-word filter, the hundred rule and `dutchGlued`; AlignmentCore's own comment (279-285) says "consolidate later". Add `Shared/Pipeline/NumberWords.swift` with the tables, `dutchGlued` and `value(of parts:)`. `AlignmentCore.canonicalizeNumberWord` keeps its lowercase, diaeresis fold, trim and hyphen split and calls it; `ChapterDetector.spelledValue` calls it after joining tokens. Delete both table blocks. Behaviour must not change: `AlignmentCoreTests` and `ChapterDetectorTests` (including 379-383, which exercise `spelledValue`) stay green unedited.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh ChapterDetectorTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SPL-c01 (cleanup-audit P13)

### Q201 [auto] (done) delete the one-clock migration once every device has run it
spec: C240
needs: -
gate+: no
do: `migrateParkedToOneClock` and `runOneClockMigrationOnce` (`Shared/Pipeline/MemoLifecycle.swift:147-184`, defaults key `oneClockMigrated.v1`, from 2026-07-22) run at launch on both apps: `RootView.swift:164`, `SkriftApp.swift:132` and `:201`. `Memo.keptAt` syncs through CloudKit, so one device's run already propagated, but a build that predates the change would not have run it. Tuur confirms the prod iPhone, iPad and Mac each launched a build with it; then delete both functions, the three call sites and their tests (`MemoLifecycleTests ~177-190` in both apps; `MemoSpineTests:166-167` uses it as a setup helper: replace with `memo.keptAt = now`). Do nothing if he cannot confirm.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh MemoLifecycleTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SPL-d14 (cleanup-audit P14)

### Q202 [auto] (done) Mac review column: unused parameters, one title builder, comments in the right place
spec: C240
needs: Q116
gate+: no
do: In `SkriftDesktop/Features/Review/` (and `Features/Shell/RootView.swift:101-107` for the caller): delete `ConnectionsModel.count` (`ConnectionsPanel.swift:50`; the header recomputes at 199) and the "toolbar badge" comments (`ConnectionsPanel.swift:40-42`, `NoteDisplayView.swift:55-58`); remove `UnratedNotePane.onRated` (`UnratedNotePane.swift:15,19-21,56`, caller passes `{ _ in }`); drop `enabled` and `fadingLine` from `MacRatingRow` (`SignificanceCircles.swift:15-21`; the one caller is `UnpipelinedMemoSheet.swift:172`); use `inspectorOpen` at `NoteDisplayView.swift:233`, make `capabilities` a function of the non-optional file so the nil guard goes (keep the `NoteCapabilities` struct: two channels, spend vs claim; drop its unused `Equatable`); `NoteActions.swift:91` `if isConversation {` and one `copyItems` view for the two copy buttons (the two branches order `undoTidyUpItem` differently, hold only the buttons); `NoteProperties.swift:170-207` `titleSection` = chooser VStack or `titleLine` (re-render the `-snapshot` title once), one `.onChange(of: file.significance)`; `contextChips(includeDayPeriod:)` default true instead of the literal 4 SF Symbol set (`NoteProperties.swift:138-141`, `PipelineFile.swift:296-310`; `MemoNoteProjectionTests:138-140` keeps passing); `PipelineFile.sharedContent` for the four `SharedContent.decode(from:)` sites (`CaptureViews.swift:12,69,115`, `NoteProperties.swift:271`) and delete the no-op `u.path.isEmpty ? "" : u.path`; `MemoCloudStore.memo(id:context:)` (predicate fetch, limit 1) for `SplitSpeakersRow.swift:175` and `UnratedNotePane.swift:88`; use `NoteConsent.isRated(new)` instead of `value > 0` at `UnratedNotePane.swift:55` and `UnpipelinedMemoSheet.swift:72`; inline `sourceLabel(_:)` (`NoteDisplayView.swift:586-590`); move `KaraokePlayback.init(fractionOf:fraction:)` into a `#if DEBUG` extension in `Snapshot.swift` (`BodyTextView.swift:93-103`); the "this note" `ThreadEntry` in `ConnectionsPanel.swift:272-283` gets a stable id instead of `UUID()` per render. Comments: delete the two ReviewHelpers tombstones (`ReviewHelpers.swift:35-43`), fix "Actions are stubbed" (`NoteActions.swift:7`), "10-circle control" (`NoteProperties.swift:9`), "chunk 4" (`BodyTextView.swift:14-17`), "Q14 removes it" (`BodyTextView.swift:193,505`), and move the doc blocks onto the right declaration (`BodyTextView.swift:5-18,1215-1218`, `NoteDisplayView.swift:330-331,454-458`, `NoteActions.swift:54-64`). Q116 rewrites the naming overrides in `NoteDisplayView.swift:356-403`; do not touch that block. Never run SkriftDesktopUITests; Mac proof = unit tests + full build + headless `-snapshot-shell`.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DRV-d01 DRV-d02 DRV-d03 DRV-d04 DRV-d05 DRV-d06 DRV-d09 DRV-d10 DRV-d11 DRV-d12 DRV-d16 DRV-d19 DRV-c16 DRV-c18 DRV-c19 DRV-c21 DRV-c27 (cleanup-audit P15)

### Q203 [tuur] (dead) retire the second SwiftUI-Text note renderer: move three snapshots to the hosted render
spec: C240 C117
needs: Q202
gate+: yes
do: `NoteBody.swift` (`BodyText`, `readBody`, `quoteCard`, `karaoke`, `summaryAside`, the Text fallbacks, lines 15-288) and the `scrollable`/`interactive` flags in `NoteDisplayView`, `NoteProperties`, `SidebarView` (`SidebarView.swift:20,700-714`) and `SplitSpeakersRow.swift:73-76` exist only so three ImageRenderer snapshots (`Snapshot.swift:1013-1016,1163-1166,1249-1252`, `-snapshot`, `-snapshot-light`, `-snapshot-capture`) can avoid ScrollView and NSTextView; live `interactive` always takes the NSTextView editor. About 150 lines and the flags can go if those three move to the hosted `renderShell`/`hostPNG` path. Tuur decides, because CLAUDE.md names the headless `-snapshot` as the Mac proof and `plan/RUN.md:57,86-87` records that `hostPNG` misdraws `.bordered` system buttons, truncates unwrapped text and still shows a ~12 px left-edge cut: so each moved snapshot needs an eyeball pass (render before and after, view both PNGs) and nothing is deleted until all three look right. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DRV-d15 DSH-c14 (cleanup-audit P16)

### Q204 [auto] (done) one word-split rule for Mac karaoke: emoji no longer splits a word
spec: C113 C240
needs: -
gate+: yes
do: Bug found by reading, not run: `BodyTextView.Coordinator.wordRanges` (`SkriftDesktop/Features/Review/BodyTextView.swift:569-585`) calls `UnicodeScalar(c) ?? UnicodeScalar(32)` on a UTF-16 unit; that initialiser returns nil for a surrogate half, so every emoji or non-BMP character is classed as whitespace. A word like `great😀day` is split in two there, while `NoteBody.karaokePlayback` (`NoteBody.swift:167`) and `KaraokePlayback.init(fractionOf:)` count one word, so karaoke highlight and click-to-seek drift one word per emoji after it. First write a failing test on the shared `KaraokeMap.wordRanges` with an emoji. Then make the Mac coordinator use `Shared/Pipeline/KaraokeMap.swift:17-45` (add `countAttachmentOnlyTokens: Bool = false`; the Mac passes true, since its gutter attachment must count as a word, comment near `BodyTextView.swift:695`), delete `Coordinator.wordRanges`, and update its other callers (`BodyTextView.swift:535,1009`, `Snapshot.swift:819`). If the emoji case does not reproduce, log what you found and still do the dedupe. Never run SkriftDesktopUITests; Mac proof = the shared unit test + full build.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DRV-d14 DRV-d-m1 DRV-c08 (cleanup-audit P17)

### Q205 [auto] (done) Mac shell: delete the unused stub engines, naming demo and dead members
spec: C240
needs: -
gate+: no
do: In `SkriftDesktop/`: delete `Features/Shell/StubEngines.swift` and the DEBUG `-stubEnhancement` branch (`ProcessingCoordinator.swift:33-66`); make `transcriber`/`enhancer`/`diarizer` plain `= Service.shared`, delete `stubbedEngines` and un-guard the five sites (186, 285, 376, 496, 637); fix the comment at `SkriftDesktopUITests/ReviewWalkthroughUITests.swift:11`. Nothing launches the flag (`BatchRunnerTests` has its own private stub). Delete `-naming-demo` and `DemoSeed.seedNamingDemo` (`DemoSeed.swift:19-61`, `RootView.swift:166-177`; `-snapshot-naming` covers it) and fix the stale `DemoSeed.swift:3-6` header; wrap the `-demo` branch and `DemoSeed.seedIfEmpty`'s call in `#if DEBUG` (`RootView.swift:178-179`; today a Release `Skrift -demo` on an empty store seeds fake notes; the UI tests run Debug). Delete `Theme.violet` (`Theme.swift:42`), `LifecycleSweepScheduler.activationObserver` (49,57: call `addObserver` without storing it), the unused `in pf:` parameter of `ProcessingCoordinator.diarizationSlot` (520, call at 489), `SidebarSort` raw values, the unreachable `guard !isRunning` at the top of `runProcess` and `runTranscribe` (134, 271). `RootView`: `@State private var coordinator: ProcessingCoordinator` with no default (init assigns it), `model.select(id)` instead of `activeID = id; selection = [id]` at 48-50, 135-137, 226-230 (it also sets the selection anchor; keep the `surface = .queue` lines), drop `onRated`, one `.frame(minWidth: 480...)` on the pane switch. Replace `AppModel.ReviewShelf` and `JournalView.mapMode` with one `enum JournalColumn { lookback, map, wayOut }` kept as `@State` in `JournalView` (`JournalView.swift:42,149-308`; not on AppModel, so map mode does not start surviving a surface switch); inline `shelfRow`. `SkriftDesktop/project.yml:187-190`: remove the redundant `Pipeline/Recording` test-source entry and its comment. Do not touch `LiveRecordingSession.cancel` (Q at QUEUE.md:1225 may wire it). Never run SkriftDesktopUITests; Mac proof = unit tests + full build + headless `-snapshot-shell`.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DSH-d01 DSH-d02 DSH-d05 DSH-d06 DSH-d13 DSH-d14 DSH-d16 DSH-d17 DSH-d20 DSH-c08 DAU-c04 DPE-d20 PER-d12 (cleanup-audit P18)

### Q206 [tuur] (done) delete finished Mac headless probes
spec: C240
needs: -
gate+: no
do: These DEBUG flags have no invoker in `plan/*.sh`, `gate.sh`, UITests, SPEC or QUEUE. Tuur picks which to delete: `-aligncheck` (`RunFile.swift:7,574-632`; also drops the Mac's only ZIPFoundation use: remove the package and the target dependency from `SkriftDesktop/project.yml:19-21,161-162`, regenerate; it is the only headless way to run `AlignmentCore.align` on a real ePub); `-asrsweep` plus `wer`, `wordCount`, `import CoreML` (`RunFile.swift:3-4,383-471`; `Shared/Pipeline/ASRLanguageMode.swift:7` and `SkriftMobile/Services/Transcription/TranscriptionService.swift:84` cite it as the language-mode evidence: reword both, and fix the stale `7f963cd` pin in the comment at `RunFile.swift:388`, the pin is `19600a48`); `-audiodate` (`RunFile.swift:320-332`); `-vaultpreview` (`RunFile.swift:293-318`); `-voiceloop` (`RunFile.swift:334-384`; it backs up, clears and restores the Dev names.json in memory with no `defer`, `plan/data-loss.md:51` row 31); `-asrbench` (`RunFile.swift:181-213`, cited for a measured speed in `FEATURES.md:183`); `-snapshot-wizard`, `-snapshot-run`, `-snapshot-settings` and `ProcessingCoordinator.preview` (`Snapshot.swift:41-43,1135-1170,1329-1334`, `ProcessingCoordinator.swift:68-73`; `-snapshot-settings-hosted` supersedes the last). Keep `-chunksim`, `-readalongcheck`, `-runfile`, `-snapshot`, `-corpus`. Update `FEATURES.md:74,183` and `plan/extraction/decisions.md:334` for whatever goes. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DSH-d07 DSH-d08 DSH-d09 DSH-d19 PER-d13 (cleanup-audit P19)

### Q207 [auto] (done) one relink helper for the four conversation-or-monologue sites, bestBodyText in the model layer
spec: C239
needs: Q116
gate+: yes
do: The block "conversation ? `Sanitiser.processConversation` : `Sanitiser.process`, then write `sanitised` and `ambiguousNames` (empty means nil)" is typed four times: `ProcessingCoordinator.swift:664-672,694-704`, `BatchRunner.swift:278-282`, `MemoCloudUpdate.swift:151-160` (its comment at 146-148 admits it is inlined from the coordinator to stay pure). Add one helper in `Models/PipelineFile.swift` or `Pipeline/` (host-less, not on the coordinator) `relinkNames(_ pf:, working:, isConversation:, people:)`; each site keeps its own `isConversation` decision (BatchRunner derives it once from the transcript at 216 and reuses it for tags and copy-edit; the others derive it from `working`), `sanitiseStatus` and compile step. Move `bestBodyText` (`sanitised ?? enhancedCopyedit ?? transcript`, `Features/Review/ReviewHelpers.swift:10`) into `Models/PipelineFile.swift`, use it in `SplitSpeakers.swift:9-11` (delete `shownBody`), `SidebarView.swift:1295`, `ConnectionsPanel.swift:123,134` (Q120 also edits `backlinkScan`: keep your edit to the call). `BatchRunner:199,201,237` compare optionals and `CompilerBridge:98` reads a `CompilerInput`; they do not use it. The phone's `MemoLinking.swift:18-29` routes on a looser predicate (`parse != nil`, 2 headers, vs `isAttributed`, 2 distinct names): do not unify the routing here; record the difference in the commit message and ask Tuur. Existing `BatchRunnerTests`, `MemoCloudUpdateTests`, naming goldens stay green unedited. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DSH-d11 DPE-c02 DRV-c17 (cleanup-audit P20)

### Q208 [auto] (done) Mac process queue: a Process asked during a Redo no longer gets stranded
spec: C49 C239
needs: Q205
gate+: yes
do: Bug found by reading, not run: `ProcessingCoordinator.redo` sets `isRunning` itself (`ProcessingCoordinator.swift:625`) and never goes through `submit()`; `submit` (111-114) enqueues when `isRunning` and returns, and the only drain loop lives in the `submit` call that holds `draining`. A Process, Transcribe or Split request that arrives during a Redo (recording-stop transcribe, import auto-transcribe with `announce: false`) therefore sits in `waiting` until some later `submit` happens to drain it. The sidebar button is disabled while `isRunning` (`SidebarView.swift:484`) but the automatic paths are not. Write a failing test through the coordinator seam (queue a job during a redo, expect it to run when the redo ends), then fix: either drain `waiting` in `redo`'s `defer`, or add `.redo` to `RunQueue.Job` (note a queued redo changes its `await`: callers at `SidebarView.swift:1086-1092` and `NoteActions.swift:101` do not expect it to return early). Same file: `isRunning` becomes `runState != nil` (they are always set and cleared together; `runState` is read at `SidebarView.swift:916`); one `beginRun/endRun` pair for the lifecycle pasted in `runProcess`, `runTranscribe` and `redo` (lines 144-155, 276-283, 625-632), keeping the real differences: `runTranscribe` loads only the ASR model and never sets `modelsLoaded`, only `runProcess` and `redo` call `ConnectionsIndexService.shared.sweepSoon`; one constant for the "A run is already going" message (134, 580, 609, 621); `setSplitNotice` clears by a per-id token like `flash()` instead of by text compare (`ProcessingCoordinator.swift:460-516`). Do NOT share a `hasAudio` helper: `runProcess` requires `sourceType == .audio`, `runTranscribe` (304) does not; note that divergence in the commit message. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DSH-d12 DSH-d21 DSH-c02 DSH-c17 (cleanup-audit P21)

### Q209 [auto] (done) Mac headless harnesses: one arg parser, one runner, and a swallowed error fixed
spec: C240
needs: Q206
gate+: yes
do: `RunFile.swift` has 17 `...IfRequested` entry points; 16 define their own `log()` (two to stdout, `runVaultExportIfRequested` at 226 and `runVaultPreviewIfRequested` at 309, the rest to stderr: keep both) and each parses its argument with `firstIndex(of: "-flag"), i + 1 < count` (19 sites). Add `LaunchArgs.value(after:)` (move the phone's `[String].boolFlag/stringValue` from `SkriftMobile/App/LaunchArgs.swift` into `Shared/Model` so both apps and `Snapshot.swift:26`, `CorpusSeed.swift:242`, `ProcessingCoordinator.swift:50`, `LifecycleSweepScheduler.swift:68`, `NoteDestination.swift:145,153`, `PortfolioVault.swift:54` use it; the phone helper also accepts `-key=value`, harmless) and a small `Harness` helper (arg lookup, log, `main(body)` that catches, prints and exits 0 or 1). Bug first: `runRateToRowIfRequested` (`RunFile.swift:863-923`) uses `try` inside `Task { @MainActor in }` with no catch, so a throw from `typedNote` (878) or `cloudCtx.save()` (887) is swallowed, `exit()` is never reached and the process carries on as a GUI app; fix it before the refactor. `-readalongcheck` (`RunFile.swift:141-172`) calls `anchorDrift` after extending it to return its rows and percentiles (it prints p10/p90/min/max and a per-anchor listing; the harness stays, `SPEC.md:1218`, `CLAUDE.md:190`). `fixtureStore(full:)` in `Snapshot.swift` for the ten in-memory containers (eight seed `DemoSeed.snapshotFiles()`; schemas differ, so the schema is a parameter). One constant for `-isolatedRun` (`SkriftDesktopApp.swift:14`, `MemoCloudContainer.swift:55`, `RootView.swift:192`) and one `isXCTest` for the six `XCTestConfigurationFilePath` sites. Flag names and output formats must not change (plan/*.sh and RUN.md use them). Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DSH-c10 DSH-c09 DSH-c12 DSH-d10 DAU-c21 PER-c02 (cleanup-audit P22)

### Q210 [auto] (done) Mac settings: delete the dead toggles and the old wire DTOs
spec: C240
needs: -
gate+: no
do: In `SkriftDesktop/`: delete `Models/FileDTO.swift` (`StepsDTO`, `FileDTO`, `UploadResponseDTO` reference only each other; xcodegen globs `Models/`); `AppSettings.audioFolder` and `attachmentsFolder` (`AppSettings.swift:8-9`) and their two harness lines `RunFile.swift:561-562` (leave the legacy keys in the `CustomVocabularyTests.swift:22` JSON fixture: unknown keys are ignored on decode, it proves old settings.json files still load; update the comment at `AppSettings.swift:6-7`); `processAllSyncedMemos` and the `processEverything` parameter of `MemoCloudReconciler.sweep` and `MemoCloudIngest.ingest` with the `|| NoteConsent.isRated` arm (`MemoCloudReconciler.swift:49,139`, `MemoCloudIngest.swift:27-40`, `MemoCloudReconciler+Wiring.swift:105-107`; SPEC D57 already says delete it; update `FEATURES.md:301`), delete the two true-case tests (`MemoCloudReconcilerTests.swift:80`, `MemoCloudIngestTests.swift:138`) and drop `processEverything: false` from the other 29 + 1 + 1 test lines; `AppSettings.conversationMode`, `conversationModeEnabled` and the nil-ing in `SettingsStore.load()` (`AppSettings.swift:39-50,159-162`), reduce `BatchRunner.swift:146` to `pf.diarizeRequested`, point `DiarizationTests:119,132,175,473` at `pf.diarizeRequested`, and rewrite `DiarizationOptInTests.legacySettingsFile()` (:30-34) to write raw JSON containing the legacy `conversationMode: true` key so the regression guard survives (the typed field will not exist). Re-grep every symbol by NAME first. Protected-test edits: hand-merge after Tuur's yes. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DPE-d01 DPE-d02 DPE-d03 DPE-d04 DAU-d11 DAU-d12 DAU-d13 (cleanup-audit P23)

### Q211 [auto] (done) Mac and phone engines: unread fields, a one-field wrapper, one unused sweep helper
spec: C240
needs: -
gate+: no
do: Desktop `Engines/TranscriptionService.swift`: delete `models` (the strong ref is redundant: `AsrManager.loadModels` holds them), `ready` and its writes, `isModelReady`, `liveCaption()` (`:22,36-42,52-53,65,68,82-84,179-183`) and, since only `finalTail` is read, make `finishStreamParts` return just that (keep the Shared `LiveCaptionEngine.finishParts` API); `EnhancementService.isModelReady` (29); `MacRecorder.isRecording` (114) and the write-only `deviceInput` (130, 272, 354; keep `cancel()`); `RunQueue.isWaitingSplit` (`RunQueue.swift:69`, one assertion at `SplitSpeakersTests.swift:107` becomes `q.jobs.contains(.split(id: "a"))`; check the Q62 verdicts first); `MemoCloudReconciler.existingFile` (`:93,182-191`; keep `SweepOutcome.stranded`, `MemoCloudReconcilerTests.swift:340` asserts it); the `PipelineFile.steps` setter (`PipelineFile.swift:238-243`; `PipelineFileTests.swift:17-18` assigns `transcribeStatus`/`enhanceStatus` instead). `Boosted.replacementCount` and the `Boosted` wrapper: `boost()` returns `String?` in both `SkriftDesktop/Engines/VocabularyBooster.swift:29-32,95-96` and `SkriftMobile/Services/Transcription/VocabularyBooster.swift:65-68,129-130` and their one consumer (`TranscriptionService.swift:121-123`, phone `:175-177`). The phone-side `isModelReady` (x3) and `finishStream` are P38's. Do NOT touch `StepStatus.skipped` or the `RunReconciler` lines that heal old stores (persisted SwiftData column). Re-grep by NAME first. Protected-test edits: hand-merge after Tuur's yes. Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh VocabularyBoosterTrustTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DPE-d05 DPE-d06 DPE-d07 DPE-d10 DPE-d11 DPE-d23 MSV-d16 DPE-c11 (cleanup-audit P24)

### Q212 [auto] (done) Mac pipeline: drop the WayOut forwarders, one ISO parser, a few tidy-ups
spec: C239 C240
needs: Q114 Q178
gate+: no
do: In `SkriftDesktop/`: delete the four pure forwarders in `Pipeline/WayOutRules.swift` (`oneLiner`, `bringBack`, `fadingOrdered`, `deletedOrdered`, lines 124-134, 168-189) and call `WayOut.*` at `WayOutColumn.swift:58,65`, `JournalView.swift:282`, `UnpipelinedMemoSheet.swift:307`, `SidebarView.swift:811`, `NoteProperties.swift:67`; move the matching `WayOutRulesTests` assertions (124-135, 208-235, 280) to `WayOut.*` (`WayOutSharedTests.swift:20-30` already covers three of them: delete the duplicates). Delete `DesktopTrashPolicy` (`Pipeline/DesktopTrash.swift:4-8`) and use `Shared/Model/Memo.swift` `TrashPolicy` at `DesktopTrash.swift:46`, `PipelineFile.swift:205-213`, `DesktopTrashTests.swift:63`. Add `ISO8601.lenientDate(from:)` (fractional seconds, else plain) with static formatters to `Shared/Model/ISO8601.swift`; delete `AudioMetadata.parse`, `IngestService.parseISODate` and `MetadataDate` (`PipelineFile+BodyNormalise.swift:136-143`); point `VideoIngestTests:34-39` at it; do not change `ISO8601.date(from:)` (names sync compares strings lexicographically). Move the async `AudioMetadata.recordingDate(of:)` into `Pipeline/` so `IngestService.ingestVideo` (already async, 400) can call it and delete the sync `embeddedRecordingDate` (this also removes the test comment re-implementation at `MergedNoteDateAndParagraphsTests.swift:78`). `IngestService.makeFolder` returns only the `URL` (all 5 callers discard the id), delete `let vault = picked` (`VaultExporter.swift:87-90`), inline `VaultName.stem` in `noteStem(_ pf:)` and delete the two-argument wrapper (`VaultExporterTests:266-269`), inline the three `Prompts.default*` aliases (`AppSettings.swift:121-131`), and compute the outcome once in `SplitSpeakers.settle` (`:31-43`). Q114 and Q178 edit `displayTitle`/`matchesSearch` in `WayOutRules`: keep your edit to the forwarders. Protected-test edits: hand-merge after Tuur's yes. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DPE-d15 DPE-d17 DPE-d18 SMU-d08 DPE-c10 DPE-c30 DPE-c28 (cleanup-audit P25)

### Q213 [auto] (done) drop the write-only Mac diarization sidecar
spec: C182 C240
needs: -
gate+: yes
do: The Mac's `diar_<id>.json` sidecar (`Pipeline/BatchManager/DiarizationSidecar.swift`) is written at `BatchRunner.swift:175`, `UploadService.swift:195`, `MemoCloudIngest.swift:225` and deleted at `BatchRunner.swift:125` and `SplitSpeakers.swift:59`, but `load(in:id:)` is read only by tests; voice enrollment reads `pf.diarizationSegments`. Tuur decides, because `SPEC.md:1034` (C182, "re-transcribe also clears diarization + its sidecar") names it: amend that clause in the same change. If yes: delete the struct, its 3 writes and 2 deletes, the `sidecar:` parameter of `adoptLateDiarization`, and the wrong comment at `MemoCloudIngest.swift:207-208`; retarget the sidecar tests (`UploadTests.swift:58`, `DiarizationTests.swift:435-460`) to `pf.diarizationSegments`; `DiarizationData.slotNames` and `turnSlots` then go unread on the Mac, so shrink it to a segments-only decode of the phone blob (the phone's blob arrives as a `MemoAsset`, not this file). Also fold the repeated empty-path guard (`PipelineFile.workingFolder` is the existing helper; `BatchRunner.swift:124,174`) and keep the field lists of retranscribe and flatten separate (retranscribe also clears `titleSuggested`, flatten resets statuses and keeps the title). Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DPE-d09 DPE-c03 (cleanup-audit P26)

### Q214 [auto] (done) Mac ingest: one typed path instead of fake multipart parts
spec: C238 C240
needs: Q207
gate+: yes
do: The only production ingest path is `MemoCloudIngest.swift:48` calling `upload.ingest(parts:)`; `buildParts` (122-171) re-encodes a Memo into fake multipart parts and `UploadService.prepare` (66-345) parses them back, reading keys the same file just wrote in `metadataJSON`. The Bonjour/HTTP server this mirrored is retired (`MultipartPart.swift:3-5`; header comments `UploadService.swift:9-14`). First port the tests that feed parts: `UploadTests.swift` (12 `ingest` calls with no `memoID`, lines 26-289) and `MemoCloudIngestTests.swift:59,170` to build a `Memo` and `MemoAsset`. Then replace `buildParts` and `prepare` with one typed `UploadService.prepare(memo:assets:)` that reads memo fields directly and decides audio, text or capture once (retiring `isTextOnly` and `isTranscriptTrusted`, which must stay exact complements today), make `memoID` non-optional (drop the random-id branches at `UploadService.swift:53-55,88,117`), keep `metadataJSON(for:)` only to fill `pf.audioMetadataJSON`, and delete `MultipartPart` and `contentType`. Also delete the video branch in `prepareAudio` (138-149) and `IngestService.extractAudioSync` (498-525): its only caller; the phone converts video before sync (`MemoSaver.swift:373`) and the async `extractAudio` stays for `ingestVideo`. Keep exactly: the textOnly rule (no audio ASSET and empty `audioFilename`), the capture-payload-does-not-parse fallback, the trust gate. This touches the trust path: the corpus tests (`MemoCloudIngestTests`, `RoundTripParityTests`, `MemoCloudReconcilerTests`) must stay green. Protected-test edits: hand-merge after Tuur's yes. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DPE-d12 DPE-d13 DPE-d14 (cleanup-audit P27)

### Q215 [auto] (done) Mac sidebar and app: unused pill and helpers, wrong comments
spec: C240
needs: Q205
gate+: no
do: In `SkriftDesktop/`: delete `StatusPill`, `PulseDot`, `QueueStatus.color` and `QueueStatus.tint` (`Features/Sidebar/SidebarView.swift:1345-1373`, `QueueDerivations.swift:20-34`; keep `label` and `pulses`, `QueueRowView.cardModel` uses them); `View.sidebarRowSelection` (`SidebarView.swift:1326-1343`); `queuedCount` (48); `SkriftFormat.shortDate` and `shortDF` (`QueueDerivations.swift:136-147`); the `asRecording` parameter of `ingest`/`runIngest` and the unreachable tail at `SidebarView.swift:203-232` (pass `asRecording: false` to `ArrivalPath.run`; `ArrivalPath.run` keeps the parameter, `LiveRecordingSession` and `RunFile:729` pass true); `actionButton(filled:)` (486, call at 302); `showDateStrip`'s launch-argument seed (76); `JournalView.coordinator` (16) and the argument at `RootView.swift:46`, `Snapshot.swift:969,979`; `UnpipelinedMemoSheet.backlinked`/`effectiveBacklinked` (keep `derivedBacklinked`, fill it in `load()`); `RecordingDraftBody.everEdited` (19, 56) with `Snapshot.swift:531,535`, the orphan doc at `RecordingDraftView.swift:189` and the `LiveRecordingSession.everEdited` proxy (63; keep `LiveRecordingDraft.everEdited`); `PersonEditor.request` stored property (19, 39); the unused `import FluidAudio` (`SkriftDesktopApp.swift:4`); `NamesCloudSync.run`'s unread `Bool`, `MacCloudEditSync.debounce` as `let` and `flush` private (leave the phone twin's shape). Fix false comments and strings: `WayOutColumn.swift:239-241`, `SidebarView.swift:14,611-616,972-976` and the empty-state "click + Upload above" at 906 (the button reads Import; use `SharedCopy.importVerb`), `MemoCloudContainer.swift:14-20,33-36` (Bonjour/HTTP fallback is retired; "opt-in" is wrong, `cloudKitMacSyncEnabled` defaults ON), `SkriftDesktopApp.swift:6-7,83-84`, `RootView.swift:26-29,211-213` ("day-change + 24h", the scheduler runs on launch and activation), `LiveRecordingSession.swift:12-14`, `Snapshot.swift:495-511`, `RecordingDraftView.swift:42-44` (LIVE-ENGINE is built), `Theme.swift:9-14`, `RunFile.swift:926-927`, and in `IngestService.swift:351-355,587-591,615`, `MemoNoteProjection.swift:22-27`, `MacRecorder.swift:27-30`, `MemoCloudReconciler.swift:7-14`, `MemoCloudIngest.swift:4-20,97,103`, `UploadService.swift:9-14,46-59` (shorten the Q5 essay), `AppSettings.swift:39-47,94-106`, `MemoCloudUpdate.swift:27-37` (`isFreshRow` doc sits between the attribute and the function). Keep rationale comments that record why a behaviour exists (`SidebarView.swift:226,430,442`, `LifecycleSweepScheduler` removed-trigger note, the `RootView` minWidth note). Never run SkriftDesktopUITests; Mac proof = unit tests + full build + headless `-snapshot-shell`.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DAU-d01 DAU-d02 DAU-d03 DAU-d04 DAU-d05 DAU-d06 DAU-d07 DAU-d08 DAU-d09 DAU-d10 DAU-d16 DAU-d17 DAU-d18 DAU-d-m1 DAU-d-m2 DSH-d15 DPE-d16 DPE-c12 (cleanup-audit P28)

### Q216 [tuur] (done) delete the 2026-07-27 sync trace
spec: C240
needs: -
gate+: no
do: `syncTrace` and `eventTypeName` in `SkriftDesktop/App/MemoCloudReconciler+Wiring.swift:45,53,57,87,113-115,189-216` are a DEBUG diagnostic that says "delete once the cause is known"; commit `cd086137` says the trace cleared the transport and the real fix was the `.cloudMemosDidChangeFromSync` post at line 122. Tuur confirms the "memo only appears after relaunch" bug is gone on his Mac. Then delete `syncTrace`, `eventTypeName`, the five call sites, the `visible` `fetchCount` (a fetch on every Release reconcile that only feeds the trace), the DEBUG `synctrace` log block in `MemoCloudUpdate.swift:130-134` and the `why: [String]` array with its appends (`MemoCloudUpdate.swift:73,77-79,96,102,111,123,128`). No script, SPEC or BUGS entry uses the `synctrace` category. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DAU-d14 DPE-d19 PER-d14 (cleanup-audit P29)

### Q217 [auto] (done) two display bugs: the 125:00 duration and a place name containing a plus
spec: C115 C240
needs: Q182
gate+: yes
do: (1) `SkriftDesktop/Features/Journal/JournalView.swift:584-587` formats a note's duration with `Duration.seconds(...).formatted(.time(pattern: .minuteSecond))`, which prints `125:00` for a 2 h 05 note; every other Mac site uses `SkriftFormat.duration(seconds:)`, whose doc (`ReviewHelpers.swift:41-45`) says it was unified for exactly this. Use it. The phone's `WayOutView.swift:384` has the same bug: use the phone's equivalent (Q121 is introducing `DurationFormat`; if it has landed use that). Write a test that a 7500 s duration does not render `125:00`. (2) A merged `PlaceCluster` keeps its member count and base name inside its `id` and `name` and recovers them with `split("+")` at six sites (`Shared/Pipeline/PlaceCluster.swift:58-85`, `JournalView.swift:441,469`, `RailMiniMap.swift:95`, phone `JournalMapView.swift:102,113`), so a place called "C+ Cafe" gives a wrong count and title. Add `memberIDs: [String]` and `mergedCount` (default 1; `PlaceClusterTests:9` and `WallPrinterTests:12` construct it with named args and keep compiling) and replace the splits with membership tests. The merged label stays `base +<count before the merge>`, i.e. new total minus 1. Q182 rewrites the calendar grid and Then-vs-Now, not this. Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh WallPrinterTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DAU-c27 DAU-c20 SPL-c24 MLJ-c08 (cleanup-audit P30)

### Q218 [auto] (done) phone recording and quick note: unread state, forwarders, doc fixes
spec: C240
needs: Q173
gate+: no
do: In `SkriftMobile/`: delete `RecordingActivityManager.isRunning` (`Services/Recording/RecordingActivityManager.swift:69`); `PhotoCaptureService.isReady` and both writes (`PhotoCaptureService.swift:16,46,68`); `LiveRecordingService.level` and its five writes, pass the local to `pushWaveform` (`LiveRecordingService.swift:28-29,448,634,1019-1022,1671-1673`); `QuickNoteView.draftID` (`QuickNoteView.swift:20-23`, call sites `MemosListView.swift:217,372`; line 372 keeps `id` for `.id(id)`); `MemoSaver.importVideoAsync` (make `processVideo` internal and point `VideoImportTests` x4 at it; keep `saveAndTranscribe`, Tuur kept it in Q62; `persist` and `applyMetadata` are private); `RecordingSweepReport.kept` and its append (`RecordingRecovery.swift:10-21,84`; keep the struct Equatable, two tests compare it to empty); `NoteRoute.isDraft` (`NoteRoute.swift:24-27`; `QuickNoteRouteTests:40` pattern-matches instead) and the `Memo?` return of `QuickNoteDraft.edited` (7 test sites incl. `QuickNoteHeaderQ88Tests:14,25`); make `extractAudio` return `Void` and move the failure handling into the catch (`MemoSaver.swift:301-311,404-423`); drop the `duration:` parameter of `appendRecording*` (`MemoSaver.swift:526-546`, `RecordView.swift:568-569`, 9 test call sites: `QuoteCaptureSaveTests:94`, `MemoSaverTests` x7, `AutoCopyAndCameraFlipTests:115`); `RecordClock` forwarder (`RecordView.swift:597-600`; use `RecordingCore.elapsedLabel`); `LiveRecordingService.captionPollDelay` (call `LiveCaptionEngine.pollDelay` at 1589, retarget the 9 `LiveCaptionCadenceTests` assertions, do not delete them, the Mac suite only has 3 nominal cases); `MemoryWarningStep.allCases` instead of `memoryWarningOrder` (keep an order assertion for D131); `LiveRecordingService.name(_ reason:)` becomes `String(describing:)` (output unverified, log-only); one `waveformBars` constant for `Meter(width: 40)`, `waveformBars` and `RecordView.barCount`; the closed-investigation DevLog at `MemosListView.swift:317-319`; fix the doubled "rec rec quarantined" prefix (`RecordingRecovery.swift:79,103,209`: pass `quarantined`, `quarantine-failed`; no test matches the string). Comments: move the orphan `settleSession` doc (`LiveRecordingService.swift:210-218`) onto the function (261), fix `RecordingIntentBridge.swift:4-9,30` (RecordView only observes `stopRequestID`; start goes through `MemosListView.handleStartRequest` + `consumePendingStart`; the FAB is gone) and `MemosListView.swift:338-340` (`[NoteRoute]`). The hardware paths (route changes, tap install, session settle) are not touched. Re-grep every symbol by NAME first. Protected-test edits: hand-merge after Tuur's yes.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh RecoverySweepTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MRC-d02 MRC-d03 MRC-d04 MRC-d05 MRC-d06 MRC-d08 MRC-d09 MRC-d10 MRC-d11 MRC-d14 MRC-d15 MRC-d16 MRC-d19 MRC-d24 MRC-d25 MRC-d26 MRC-c20 (cleanup-audit P31)

### Q219 [auto] (done) one AVAudioFile duration, one buffer copy, one retrying transcribe
spec: C239
needs: Q218
gate+: yes
do: (1) `Double(f.length) / f.fileFormat.sampleRate` is written 11 times (`MemoSaver.swift:91,174,195,328`, `RecordingRecovery.swift:147`, `LiveRecordingService.swift:571,688`, `CaptureInboxDrainer.swift:312`, `SharePayloadLoader.swift:214,276`, `IngestService.swift:156`, `AudiobookImporter.swift:351`) with the `sampleRate > 0` guard at only some. Add `extension AVAudioFile { var seconds: Double }` with the guard in `Shared/Recording/` (an extension on the open file fits every site; `LiveRecordingService.swift:571` is still open for writing, so a URL helper would not); check `SkriftShare`'s source list in `project.yml` before touching `SharePayloadLoader`. Do NOT merge `MacMemoAuthor.audioDuration` (uses `AVURLAsset.duration`, returns nil on failure). (2) The phone's private `copyBuffer` (`LiveRecordingService.swift:1551-1560`, call at 984) is identical to `LiveCaptionEngine.copyBuffer` (`Shared/Recording/LiveCaptionEngine.swift:422-431`) which `MacRecorder.swift:607` already uses: delete it and call the shared one. (3) The retry-transcribe loop is copied in `MemoSaver.swift:577-585` and `Services/Capture/CaptureDictation.swift:65-73` (delays `[0,2,5,15]` vs `[0,2,5]`): add `extension Transcribing { func transcribeRetrying(audioURL:imageManifest:delays:) async -> TranscriptionResult? }` next to the protocol in `Shared/Pipeline/TranscribingContract.swift` and keep both delay arrays at the callers (tests set them). No behaviour change; the recording tap and settle paths are not touched.
check: `perl -e 'alarm 1500; exec @ARGV' plan/mtest.sh RecoverySweepTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MRC-d20 MRC-c02 MRC-c04 SRS-d09 (cleanup-audit P32)

### Q220 [auto] (done) appending a recording: use AudioClipMerge, not the export session
spec: C240
needs: Q219
gate+: no
do: `MemoSaver.appendAudio` (`SkriftMobile/Features/Recording/MemoSaver.swift:652-694`) still stitches with `AVMutableComposition` + `AVAssetExportSession`, the path `Shared/Pipeline/AudioClipMerge.swift` replaced after a phantom silent tail (header comment, and `MemoSaver.swift:211-217`). Replace it with: open the base with `AVAudioFile(forReading:)` first and let that throw (frames/rate is the splice offset), run `AudioClipMerge.merge([base, clip])` to a temp file in a detached task, then `replaceItemAt(base)`; delete the composition code and `AppendError`. The explicit base-open must stay a hard failure: `AudioClipMerge` `continue`s past an unreadable source and only throws `noAudio` if nothing was written, so an unreadable base would otherwise be silently replaced by the new clip alone and the original audio lost; the current code throws `noBaseTrack` and keeps the base. The base can be an imported `.mp3`. Tuur checks the append on the iPhone 17 Pro: record, append a clip, play both ends, check karaoke timing at the seam. `appendRecordingAsync` already tolerates a failed merge. Tests (`MemoSaverTests`, `QuoteCaptureSaveTests`) use placeholder audio and rely on falling back to the base; they stay green.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh MemoSaverTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MRC-c01 MRC-d17 (cleanup-audit P33)

### Q221 [auto] (done) camera pinch zoom compounds, and a media-services reset brings the Bluetooth mic back
spec: C115
needs: -
gate+: no
do: Two hardware-flavoured defects found by reading; neither run on a device. (1) `CameraSheet.swift:91-98,144-150`: `setZoom` writes `zoomBase = zoom` on every call, while the pinch's `onChanged` passes `zoomBase * scale` with a cumulative scale, so each callback rebases the baseline and zoom compounds (base 1, scale 1.1 gives 1.1, then 1.1 x 1.2 = 1.32). The comment above the gesture says the baseline must be snapshotted at gesture start. Make `setZoom` write only `zoom`; set `zoomBase = zoom` in `.onEnded`, in the zoom-selector taps and in `flip()`. (2) `LiveRecordingService.handleMediaServicesReset` (`:1246`) sets a hard-coded `[.allowBluetooth, .defaultToSpeaker]` while the other two `setCategory` sites use `recordingCategoryOptions(avoidBluetoothMic:)`, bringing back the HFP mic path the b117 policy (2026-07-26) removed. Add `static func configureSession(_ s: AVAudioSession) throws` using `recordingCategoryOptions(avoidBluetoothMic: avoidBluetoothMicNow(s))` and call it from `settleSession`, `startEngine` (inside the `!warm` branch) and the reset handler. CLAUDE.md: hardware bugs are diagnosed from the devlog and belong to the orchestrator, not a lane; Tuur or the orchestrator tries both on the iPhone 17 Pro (pinch from 1x; trigger a media services reset with a Bluetooth headset connected) and marks them unverified until then.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh LiveRecordingRouteChangeTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MRC-c28 MRC-c11 MRC-d18 (cleanup-audit P34)

### Q222 [auto] (done) phone list, journal and settings: unused chrome, filters, launch flags, comments
spec: C240
needs: Q173 Q110
gate+: no
do: In `SkriftMobile/`: delete `SelectableCard` (`Features/MemosList/NotesBottomChrome.swift:58-77`, plus its "iPad shell helpers" MARK; Q173 does not name it; if Q173 landed first, only this struct remains); `quietLine` from `MemoRow` and `MemoCard` and the `quietLine: nil` call with its comment (`MemosListView+Row.swift:18-90`, `MemosListView.swift:505-510`; keep the Shared `NoteCardModel.quietLine`, the Mac sets it at `SidebarView.swift:810`); build the `MemoCard` once in `MemoRow.body` (selected: `editing ? false : selected`) with an if/else between the bare card and the Button wrapper; `LaunchFlags.destinationsOn`, `seedPortfolioFolder`, `selectFirstMemo` and `Array.intValue` accessors (`App/LaunchArgs.swift:18,31-40`; the raw-argument reads at `Shared/Model/NoteDestination.swift:145` and `Services/Export/PortfolioVault.swift:54` stay, which should `guard LaunchFlags.seedPortfolioFolder`); `-openJournal` and `-openSettings` and their two lines in `AppTabView.initialTab()` (`-openTab` replaces them; update `FEATURES.md:396`); the closed-investigation diagnostics `MemosListView.swift:317-337` and `MemosListView+Derived.swift:135-140` (DEBUG only; keep them if Tuur wants more device rounds); `Identifiable` and `id` from `MemoSort` and `MemoDateField` (keep `MemoDateField`'s raw type, `MemosListView+Header.swift:248` uses it); `NamesDisplay` (call `person.displayName` and `PersonEditCore.isEnrolled(person)` directly, `NamesListView.swift:159-163`); `let pile = processPile` once in `processRow` (`+Header.swift:151-169`). Do NOT touch `MemoFilter.hasPhotosOnly/.place/.isActive` (Q110, gated on Tuur) or the `AddPersonView` and Names headers (Q113). Comments: `MemosListView.swift:49-52,99-103`, `+Header.swift:6-20,304-306` (the Filter moved out, Q66), `+Actions.swift:78-79,107-112`, `WayOutView.swift:7-8,243-244` (reached from Review, `JournalHomeView.swift:49`; `FadingShelfView` no longer exists), `JournalHomeView.swift:159-160`, `PersonDetailView.swift:4-8`. Leave the `-showTOCSheet`, `-showTextSheet`, `-showTextPrompt`, `-seedAudiobook`, `-seedDetectedChapters`, `-showFilterSheet`, `-seedJournal`, `-journalMemoDemo` rig alone (lane briefs keep them; Tuur's call). Re-grep every symbol by NAME first.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh MemoModelTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MLJ-d02 MLJ-d04 MLJ-d07 MLJ-d08 MLJ-d11 MLJ-d13 MLJ-d16 MLJ-c14 MLJ-c15 MLJ-c20 MSV-d17 (cleanup-audit P35)

### Q223 [auto] (done) feedback: a single-item mail composer, a store that only saves, no duplicate draft
spec: C240
needs: -
gate+: no
do: `FeedbackCaptureView` is the only consumer (`FeedbackCaptureView.swift:82-83,183`) of `FeedbackStore`, `FeedbackItem` and `FeedbackMailComposer`; nothing observes `items`, no Feedback list screen exists, and `FeedbackMailComposer.init(items:)` has no caller. Make the composer single-item (one item, `onSent: (FeedbackItem) -> Void`, fixed subject and zip name; update `sent.forEach` at `FeedbackCaptureView.swift:82-83`). Make `FeedbackStore` a plain struct or enum: delete `count`, `delete(_:)`, `items`/`@Published`/`ObservableObject`, `reload()`, both `load(from:)`, `makeDecoder`, and `FeedbackItem.screenshotURL`, `hasScreenshot`, `durationSeconds`; `save()` returns `FeedbackItem(folder:metadata:)`, `markSent` keeps working; use the built-in `.iso8601` date strategies (same internet-date-time format, existing files still decode). KEEP the on-disk `Documents/Feedback/<uuid>/metadata.json` layout and field names: `.claude/skills/pull-phone-feedback` reads those files over USB. `sendNow` (182-191) saves a second draft folder when the user taps again after the no-mail alert: keep a `@State savedItem` so a retry reuses the folder; reword the alert that says "send it from the Feedback list" (92), a screen that does not exist. `FeedbackRecorder` is also used by `VoiceEnrollView` (`PersonDetailView.swift:138`): leave it where it is, set `elapsed` from `audioRecorder?.currentTime` only if the change is trivial. Run the feedback flow once in the simulator with the pull-phone-feedback parse step on the result.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh MemoModelTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MLJ-d05 MLJ-d06 MLJ-c23 MLJ-c24 (cleanup-audit P36)

### Q224 [auto] (done) three phone state bugs: lost print card, stuck model spinner, re-stamped language
spec: C115
needs: Q173
gate+: yes
do: Found by reading; each gets a failing test first where one can be written, otherwise log what you found. (1) `WallPrinter.tryDrain` (`SkriftMobile/Features/Journal/WallPrinter.swift:30-120`) snapshots the queue, awaits printing, then writes `remaining` back over the key, dropping any card `ratingCommitted` enqueued during the drain; queue and ledger are re-read from UserDefaults in five places and `queuedCount` is a hand-synced mirror. Hold queue and ledger as stored properties with `didSet` persistence, loaded once in `init`, derive `queuedCount`, fetch memos once into a dictionary in `tryDrain`. `WallPrinterTests`: enqueue during a drain survives. (2) `OnboardingView.modelRequested` is never reset (`Features/Onboarding/OnboardingView.swift:13-51,130-134`): after a failed download the row shows a spinner forever (`try?` swallows the error and `ModelLoadStatus.ready`/`downloadProgress` are false/nil after `.failed`); reset it after `ensureLoaded` as `ModelsView.downloadASR` does and show the failure. Q173 also edits this view (the permission step): rebase on it. (3) The language picker (`Features/Settings/SettingsView.swift:19,87-99`) writes the Bool through `@AppStorage` and then `.onChange` calls `ASRLanguageStore.save`, so when sync adopts a value while Settings is open the `.onChange` re-stamps it as now and overwrites the remote stamp. Keep `@AppStorage(ASRLanguageMode.settingKey)` (so sync still re-renders the picker) and put the save and `VocabularyCloudSync.run` in a `Binding` setter; delete the `.onChange`. Do NOT replace it with `Binding(get: ASRLanguageStore.mode())`.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh WallPrinterTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MLJ-c09 MLJ-c26 MLJ-c01 (cleanup-audit P37)

### Q225 [auto] (done) phone services: unread members, unused overloads and test-only helpers
spec: C240
needs: Q211
gate+: no
do: In `SkriftMobile/Services/` (re-grep each symbol by NAME in both apps and tests first): `PublishCoordinator.memosProvider` and the `live()` argument and test-helper parameter (`PublishCoordinator.swift:23,40`, `PublishCoordinatorTests.swift:24,33`; Q80 left it, nothing reads it); `NotesRepository.allAssets()` (unscoped blob fetch, 6 test calls in `MemoAssetTests`: use `repo.context.fetch(FetchDescriptor<MemoAsset>())` in a private test helper) and `NotesRepository.delete(_:)` (one caller, `MemoModelTests.swift:65`; use `repo.context.delete` + `repo.save()`), fix the stale docs (`permanentlyDelete` says MemoDetailView mirrors the cleanup, it calls `softDelete`; move the `hasAsset` doc down to line 190); `MemoDeduper.isContentClone` pass-through (`MemoDeduper.swift:43-46`); `CaptureInbox.imageURL(for:entryDir:)` (`CaptureInbox.swift:246-250`) and the never-passed `imageData:` parameter of `CaptureInbox.write` with its branch (156-176; keep the persisted `imageFileName` field and `imageURLs(for:)`; `SkriftShare` compiles this file too); `ObsidianVault.clear()` and `PortfolioVault.clear()`; the three phone `isModelReady` (`TranscriptionService.swift:43`, `SpeakerEmbedder.swift:40`, `DiarizationService.swift:27`); `ensureLoaded()` on the `SpeakerEmbedding` protocol and the `SeededEmbedder` stub (make the two real ones private); `TranscriptionService.finishStream()` and `LiveCaptionEngine.finish()` (keep `finishParts()`); `TranscriptionService.liveCaption()` (phone) with `LiveCaptionEngine.caption()` (the Mac `liveCaption()` is P24's; do the shared function after both are gone); `TranscriptionService.multilingualKey` (update the comment at `SettingsView.swift:16`); the `useANE` defaults read (`TranscriptionService.swift:66-67`: set `.cpuAndNeuralEngine`); `TranscriptionService.shouldRotate` and `LiveCaptionEngine.shouldRotate` (point `LiveCaptionCadenceTests:47-63` and `LiveCaptionSettleTests:54-56` at `rotationTrigger(...) != nil`); `WeatherClient.setAPIKey` and `testSetAPIKeyRoundTrip` (keep the legacy-key fallback, Tuur's call). Fix stale mentions: `ShareViewController.swift:15` (`complete(entry:imageData:)`), `SkriftDesktop/Engines/TranscriptionService.swift:191-194` (the Mac has no `finishStream`), `MemoExporter.swift:7-9` (the phone has an author setting). `PolishCenter.swift:300-302` keeps its dated verdict note. Protected-test edits: hand-merge after Tuur's yes.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh PublishCoordinatorTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MSV-d01 MSV-d04 MSV-d05 MSV-d06 MSV-d07 MSV-d08 MSV-d09 MSV-d10 MSV-d11 MSV-d12 MSV-d13 MSV-d14 MSV-d15 MSV-d18 MSV-d20 MSV-d-m1 MSV-c29 SRS-d06 SRS-d08 (cleanup-audit P38)

### Q226 [auto] (done) the phone export gate has one rule and no paired mode
spec: C240 C65
needs: Q156
gate+: no
do: `PublishCoordinator.live()` hard-codes `isMacPaired: { false }` and `policy: { .importantOnly }`; `skrift.publish.whenPaired` is read (`PublishCoordinator.swift:48`) and written nowhere; `Policy.all` is built only in tests. `plan/extraction/code-core.md:260` holds it as "needs-verdict, delete in v2?" and `plan/reads/parity-audit.md` setexp-74 calls the paired refusal unreachable: Tuur gives the verdict. If delete: remove `Policy`, `isMacPaired`, `publishWhenPaired`, `policy`, the four guard lines and the pairing doc paragraph; make the rated check unconditional via `NoteConsent.isRated`; define `shouldPublish(_:) = exportRefusal(_:) == nil` and delete the duplicated guard list (60-86 vs 94-113: they carry the same 8 guards in the same order; keep the 74-85 comment about `isProcessed`, next to the matching refusal) so `MemoDetailView.swift:769-790`'s `case nil` arm is the only path; delete the paired and `.all` cases in `PublishCoordinatorTests` and rewrite `UnratedConsentTests.testLivePublishPolicyIsRatedOnlyRegardlessOfStoredSetting` (it asserts `coordinator.policy()`) to store the old "all" key and assert an unrated memo still fails `shouldPublish`. Q156 unifies the phone gate with the Mac gate: land after it. Protected-test edits: hand-merge.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh PublishCoordinatorTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MSV-d02 MSV-d03 (cleanup-audit P39)

### Q227 [auto] (done) the lock flow asks the right ledger whether a note was exported
spec: C115
needs: Q225
gate+: yes
do: `ObsidianVault.hasPublished(_ memoID:)` (`SkriftMobile/Services/Export/ObsidianPublisher.swift:35-38`) keys the ledger on the picked root (`ExportLedger.default(for: vault)`) while the writer and `PublishCoordinator.hasPublished` (`PublishCoordinator.swift:126-138`) key it on the vault home (`VaultLayout.home(forPicked:profile:)`, `<pick>/Skrift` unless the pick is already named Skrift or already holds Skrift notes, `VaultLayout.swift:50-66`) and on the note's destination. So the lock-flow notice at `MemoDetailView.swift:731` and `MemosListView+Actions.swift:126` can say "not in your vault" for a note that was exported. Write a failing test that exports a memo into a picked folder named something other than Skrift and then asks the lock flow's check, then delete `ObsidianVault.hasPublished` and have both callers use `PublishCoordinator.hasPublished(memo)`. Found by reading, not run on a device; if the test passes today, log why and still remove the duplicate predicate.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh PublishCoordinatorTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MSV-m1 (cleanup-audit P40)

### Q228 [auto] (done) share extension: drop the share-side dictation that was retired on 2026-07-10
spec: C240
needs: Q132
gate+: no
do: Share-sheet dictation is gone (`SkriftMobile/project.yml:448-450`; iOS blocks recording in an extension), yet `SkriftShare/ShareSheetView.swift:779` hard-codes `let dictationData: Data? = nil` and that nil still flows through `onSave`'s third parameter (line 20), `ShareViewController.complete(...dictationData:)` and its retry closure (`ShareViewController.swift:92-94,158,170,184-185`), and into `CaptureInbox.write(dictationData:)` (`CaptureInbox.swift:164,183-186`); `ShareSheetView.swift:828` (`dictationFileName` ternary) is always nil. Remove the parameter end to end, the `dictationFileName` expression, and the unused `imageData:` branch if P38 has not (check first). Delete `testDictationRecordingInSheet` in `SkriftMobileUITests/ShareFlowProbeUITests.swift` (it taps `capture-dictation-record` and `capture-dictation-chip`, which no source file defines; the probe is opt-in behind `RUN_SHARE_PROBE`). KEEP everything the drain side reads for pending legacy inbox entries: `CaptureInboxEntry.dictationFileName`, `dictationURL`, the drainer's `hasDictation` branch, `CaptureDictation` and `CaptureInbox.write(dictationData:)` (the last is used by `CaptureDictationTests.swift:114`), P42 is the separate decision on those. Q132 and Q150 reshape the audio choice in this sheet: rebase on them. Both extension and app targets compile these files, so edit both together. Protected-test edit: hand-merge after Tuur's yes.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh AudioShareDrainTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAM-d14 PER-d05 (cleanup-audit P41)

### Q229 [auto] (done) delete the drain-side half of the retired share dictation
spec: C240
needs: Q228
gate+: no
do: `Services/Capture/CaptureDictation.swift` (120 lines), `CaptureDictationTests.swift` (174), `CaptureInboxDrainer.swift:169,566-598,651-653` (the `hasDictation` block and the `resumePending` call that runs on every drain), `CaptureInboxEntry.dictationFileName`/`dictationURL` (`CaptureInbox.swift:39,252-256`) exist only for inbox entries written by a build before 63; the only producer is gone after P41. `CaptureInboxEntry` is a transient inbox JSON, not SwiftData or CloudKit, but an old pending entry that no longer decodes is skipped and never deleted. Tuur confirms no device holds a pre-build-63 pending entry (or accepts losing one). Then delete those, reword `MemoSaver.swift:828` and `MemoSaverTests.swift:268,301` (`testRecoverSkipsCaptureDictationsAndBookCaptures` case (a) names `CaptureDictation.resumePending`; keep the empty-`audioFilename` carve-out for audiobook captures). KEEP `CaptureVoiceAnnotate`: it is the live in-app dictation path and does not use `CaptureDictation`.
check: `perl -e 'alarm 1500; exec @ARGV' plan/mtest.sh CaptureDictationTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md PER-d06 (cleanup-audit P42)

### Q230 [auto] (done) phone app: dead launch hook, status enums, unused tokens, seeders out of Release
spec: C240
needs: Q222 Q233
gate+: no
do: In `SkriftMobile/` (re-grep each symbol by NAME in both apps and tests first): delete the DEBUG one-shot P0 restore hook `LaunchFlags.restoreEnhancement` and the `#if DEBUG` block in `SkriftApp.init` (`App/LaunchArgs.swift:139-151`, `App/SkriftApp.swift:43-61`; the restore was aborted, nothing launches it, it rewrites a CloudKit-synced `MemoEnhancement` from base64 arguments); the chain `Memo.trashCountdownLabel` to `Memo.trashDaysRemaining` to `MemoLifecycle.goneAt` (`Models/MemoDisplay.swift:57-76`, `Shared/Pipeline/MemoLifecycle.swift:125-131`), reached only by tests (the shipped countdown uses MemoSpine's `.deleted(goneAt:)`), with `TrashTests.swift:192-217` and the `goneAt` assertions in both `MemoLifecycleTests`; keep the Mac `PipelineFile.trashDaysRemaining` (`WayOutColumn.swift:188`) and the enum case label `goneAt`; `MemoStatusKind.synced/.waiting` (`MemoDisplay.swift:329-340`, `MemosListView+Row.swift:96-101`; `MemoModelTests:96-111` assert nil for those states and stay valid; leave `SyncStatus` alone) and `PillStyle.synced/.waiting` (`DesignSystem/Components.swift:55-78`; only `.working` and `.error` are built, `MemoPageView.swift:574,626`); `TagChipStyle`, `Theme.Space.sm/md/lg`, `Theme.Radius.chip/sheet/group`, `SectionLabel.trailing` (`Components.swift:3-5,31-50,151-173`, `Theme.swift:87-101`; `Theme.swift` also compiles into `SkriftShare`, checked); `SharedImageItem.mimeType` (`SkriftShare/SharePayloadLoader.swift:27,404`); `Memo.rambleSnippet` (`Models/MemoDisplay.swift:201-215`, used only by `BookCaptureDisplayTests:76,83,88`) unless Tuur wants it wired into the capture row; the private `symbolEffectPulseFallback()` wrapper (`Components.swift:109-115`); tombstone comments (`ShareViewController.swift:216-219`, `MemoDisplay.swift:325-347`, `SkriftLiveActivity.swift:17-19`, `project.yml:308,335-336` "8a/8b", unused `import UniformTypeIdentifiers` at `ShareViewController.swift:3`, `SharePayloadLoader.swift:76-77`). Seeders: `DemoDataSeeder.seedIfRequested` starts with `guard repo.allMemos().isEmpty`, a sorted fetch of every live memo before any flag is checked, so every production launch fetches and discards the list (`plan/perf-sweep.md:24`). Wrap `DemoDataSeeder`, `NamesSeeder`, `AudiobookSeeder`, `DestinationSettings.resetIfRequested` and `PortfolioVault.seedIfRequested` and their call sites (`SkriftApp.swift:17-23`, `AppTabView.swift:90-93`) in `#if DEBUG` like `CorpusSeed`. Keep `LaunchFlags.inMemoryStore`, `skipOnboarding`, `seedTranscript`, `fakePolish*` readable in Release (production code reads them: `SkriftApp.swift:164-185,314-316`, `NotesRepository.swift:8`, `TranscriptionService.swift:323`, `PolishBootstrap.swift:21`). The test scheme builds Debug, so the UI tests keep working; confirm with a full phone test run of one UI-adjacent class. Protected-test deletions: hand-merge after Tuur's yes.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh TrashTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAM-d03 MAM-d04 MAM-d07 MAM-d08 MAM-d09 MAM-d15 MAM-d20 MAM-d22 MAM-d-m1 MAM-c24 MAM-c25 (cleanup-audit P43)

### Q231 [auto] (done) one quick-action widget, and the share extension stops compiling files it does not use
spec: C239
needs: -
gate+: no
do: `SkriftWidget/RecordWidget.swift` and `NewNoteWidget.swift` differ only in names, display text, SF Symbol, URL and kind (`diff` shows nothing else); add one parameterised quick-action view and provider (kind, url, symbol, title, caption) and keep the two `Widget` structs as thin wrappers so the bundle kinds `com.skrift.mobile.recordwidget` and `.newnotewidget` are unchanged (installed widgets reference them; `SkriftWidgetBundle.swift:12,14`; D135 requires separate widgets). Compile `Shared/UI/Palette.swift` (Foundation-only) into `SkriftWidget` and read the dark values (accent `7c6bf5`, red, amber, bg `0f1117`) from it with one `Color(hex:)` helper instead of the inlined copies in the two widgets and `SkriftLiveActivity.swift:7-15`. In `SkriftMobile/project.yml:412-432` drop `DesignSystem/Components.swift` from the `SkriftShare` sources (nothing there uses its symbols) and, after moving the `extension TagRowStyle { static let phone }` at the end of `DesignSystem/Theme.swift:119-128` into an app-only file, drop `FlowLayout.swift`, `TagRules.swift` and `TagEditorRow.swift` too. Regenerate. This is a compile-list change: build the extension with the phone scheme (`xcodebuild -scheme SkriftMobile`, which builds the extensions) and report the result; widgets and the share sheet are unverified on a device until Tuur looks (add a widget to the Home Screen and open the share sheet from Safari).
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh SharedContentParityTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAM-d17 MAM-d19 MAM-c10 (cleanup-audit P44)

### Q232 [auto] (done) remove the SkriftShared framework target
spec: C240
needs: Q231
gate+: no
do: A framework target exists only to share one 41-line `ActivityAttributes` file (`SkriftShared/RecordingActivityAttributes.swift`; `SkriftMobile/project.yml:301-333,390,542`, and the 64-70 comment records the version drift it already caused). Compile the file into the app and the widget by multi-target membership, the way the intents already are; drop `public` modifiers and `import SkriftShared`; drop the never-read `sessionId` and the static attributes-level `startedAt` (the widget reads `context.state.*`; `RecordingActivityManager.reapOrphans` limits any in-flight activity). Tuur decides because ActivityKit encodes these attributes and the Live Activity cannot be proven by a unit test: after the build he starts a recording on the iPhone 17 Pro and checks the Lock Screen and Dynamic Island, and ends it.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh RecordingActivityCaptionTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAM-c12 MAM-d18 (cleanup-audit P45)

### Q233 [auto] (done) shared model: unused helpers, one marker vocabulary, false comments
spec: C240 C239
needs: Q197 Q154
gate+: no
do: In `Shared/` (compiled into both apps; re-grep each symbol by NAME in both apps and tests first): delete `ThreeBallScale.toggling` and `syncCopy` (`Model/ThreeBallScale.swift:50-57,72-76`) with their cases in `SkriftDesktopTests/ThreeBallScaleTests.swift:76-116` and `SkriftMobileTests/SignificanceCirclesTests.swift:43-80` (keep `names`/`stops`, they are asserted); `Memo.splitTagInput` (`Model/Memo.swift:291-314`, 24 lines with the long essay) and the three tests at `NoteDestinationTests.swift:104-118` (keep `NoteDestination.reserved`, `Compiler.swift:128` uses it), fix the `TagRules.swift:6-7` header and `BUGS.md:377`; `TagRules.Fold`, `folds` and `keptSpelling` (`UI/TagRules.swift:47-80`; `fold` returns the tags to add; the four fold tests in `SkriftDesktopTests/TagRulesTests.swift:51-88` assert the returned array only); `BodyNormaliseMigration.remap(_:from:to:)` (`BodyV2/BodyNormaliseMigration.swift:147-150`); `BodyV2Legacy.isUnnormalised` pass-through (`BodyV2Legacy.swift:18-20`); the private `reflowMarkerLiteral` (use `BodyV2Marker.literal`); the no-op `.interactiveDismissDisabled(false)` at `UI/EditConflictViews.swift:265` and one `choiceButtons` for the three pills in `phoneBody` and `macBody` (the Mac passes `.keyboardShortcut(.defaultAction)` on the first); the `limit:` parameter of `NoteTitle.clip` (never passed, 9 callers; the open NoteTitleLadder item touches this file, coordinate). Marker vocabulary: route the hand-formatted `[[img_%03d]]` sites through `BodyV2Marker.literal/block`: `Pipeline/ImageMarkers.swift:52` (gone after P10), `ImageMarkerReinsert.swift:12,115`, `MixedBundle.swift:98`, `BodyV2Legacy.swift:90`, `SkriftMobile/Features/MemoDetail/NoteBodyView.swift:1236`, `SkriftDesktop/Features/Review/BodyTextView.swift:1170`, `SkriftMobile/Services/Capture/CaptureInboxDrainer.swift:622`; C14/C15 say readers accept `\d+` and no `\d{3}`-only matcher remains: `ImageMarkerReinsert.swift:12` is `\d{3}`-only, fix it in the same change. Leave `convertPhotoMarkers` in the exporters to Q154. `Paragrapher.endsSentence` forwards to `BodyV2Text.endsSentence(Substring(word))` and the closer set is defined once. `isC203Legacy` takes a `SharedContent?` (`BodyNormaliseMigration.swift:55-70`; callers `Memo+BodyNormalise.swift:28`, `PipelineFile+BodyNormalise.swift:52`; rewrite the dict-based asserts at `BodyNormaliseMigrationTests.swift:185-193`). `BodyV2Text.normalised` computes the collapse once per line and hoists the two regexes (`BodyV2Text.swift:17-103`). `EditConflict.swift:108-129`: one private `digest(_:)` for the SHA256-prefix expression. Fix false comments: `BodyV2.swift:5-6` ("nothing calls it": 15+ callers), `Memo.swift:36-41` (`SharedContent` lives in `Shared/Model/SharedContent.swift`), `Memo.swift:91-95` (rating gates processing, CloudKit mirrors everything, `ThreeBallScale.swift:6-8`). Protected-test edits: hand-merge after Tuur's yes.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh NoteDestinationTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SMU-d04 SMU-d05 SMU-d06 SMU-d07 SMU-d09 SMU-d11 SMU-d-m1 SMU-c03 SMU-c04 SMU-c06 SMU-c07 SMU-c11 SMU-c14 SPL-c15 (cleanup-audit P46)

### Q234 [auto] (done) shared naming, export and corpus: unread members and unused overloads
spec: C240
needs: Q225
gate+: no
do: In `Shared/` (re-grep each symbol by NAME first, both apps and all tests): delete `Sanitiser.hasCanonicalLink` (`Naming/NameUnlinking.swift:49-58`; fix `FEATURES.md:347` and `plan/extraction/decisions.md:366`); `Sanitiser.unlinkOccurrence` and `relinkOccurrence` (`NameUnlinking.swift:61-67,82-90`) with their tests (`SkriftDesktopTests/UnlinkTests.swift:38-70,173-186`, `DiarizationTests.swift:363`: re-point `testLinkOccurrencesAndUnlinkArePipeAware` at `unlinkAll` to keep the pipe-aware coverage), fix the doc at `NameUnlinking.swift:30` and `FEATURES.md:348`; keep `unlinkAll`, `linkDisplay`, `linkOccurrences`, `linkTarget` (the Mac popover at `BodyTextView.swift:1085-1100` builds from `namePicks`/`neverLink`); the three `static let ... = true` flags `wholeWord`, `avoidInside`, `preservePossessive` and their false branches (`Naming/Sanitiser.swift:37-39,209-282`; inline the true branches, drop the flags from the regex cache key); `Overrides.prunedKeys` (51, 65); `LiveCaptionEngine.caption()` (`Recording/LiveCaptionEngine.swift:178-183`, after P24 and P38 removed both `liveCaption()` forwarders); `CorpusSeed.Note.expect`/`Expect` (`Corpus/CorpusSeed.swift:68-84`; keep `Manifest.count`, `CorpusSeedTests:42,43,48` reads it; `generate.py` keeps writing the key, `Decodable` ignores it); the `renamedFrom` half of `PersonEditCore.materialise` (`Naming/PersonEditCore.swift:44-64`, assertions in both `PersonEditCoreTests`); `ExportLedger.Entry.exportedAt` (`Export/VaultWrite.swift:38,361`; the ledger is a local JSON file, old files with the extra key still decode); the `VaultWriter` `var` folders and `now` that no construction overrides (`VaultWrite.swift:212-221`); `Assessment.proceed(creates:)` becomes `proceed(relativePath:)` and `Standing.absent` with `standing(of: String?)` (non-optional) goes (`VaultWrite.swift:225-297`, `VaultStamp.swift:57-99`; update `VaultWriteTests:157`, `VaultStampTests:58`); `VaultLayout.swift:59-65` `if fileExists(nested) { return nested }` followed by `return nested`, merge the two `home(forPicked:)` overloads (profile defaults to `.obsidian`), add `VaultStamp.head(of:)` for the 2048-byte read written twice, move the stray doc comments (`VaultLayout.swift:37-43`, `VaultStamp.swift:124-128`, `VaultName.stem`). Do NOT delete `CorruptFileRegistry` (SPEC C265 surfaces corruption through it; no UI yet), `EmbeddingIndex.rowCount`, or `NamesStore.upsert(canonical:aliases:short:)` (the Mac calls it, `ProcessingCoordinator.swift:486`). Update `plan/periphery.md`: LockGate, `wikiNames`, `gistPairScores`, `writeWithSmartBumps`, `seedRoster`, `pruneOldTombstones` are live. Protected-test edits: hand-merge after Tuur's yes.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh PersonEditCoreTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SRS-d01 SRS-d02 SRS-d03 SRS-d04 SRS-d06 SRS-d10 SRS-d12 SRS-d15 SRS-d16 SRS-d20 SRS-c02 SRS-c03 (cleanup-audit P47)

### Q235 [auto] (done) naming: one match key, one pipe split, one link finder
spec: C239
needs: Q116
gate+: no
do: `NamesMerge.keyName(x).trimmingCharacters(in: .whitespaces)` (sometimes `.lowercased()`) is typed 11 times (`Sanitiser.swift:58,64,72`, `NamesStore.swift:205,241,268,270` with two identical local `key()` helpers, `Compiler.swift:276,298`, `SpeakerTurnStyle.swift:49`, `RosterAudit.swift:41`) with inconsistent combinations. Add `NamesMerge.bareName(_:)` (keyName + trim) and `matchKey(_:)` (+ lowercase) and an alias-side key for `trim.lowercased()` at `Sanitiser.swift:70,81,95,119,122` and `NameLinking.swift:33,36`; trim is almost always a no-op because `normaliseCanonical` already trims. Three sites re-implement `Sanitiser.linkDisplay` (`NameLinking.swift:69`, `Compiler.swift:308`, `BodyTextView.swift:1091-1092`): use `linkDisplay(core) ?? fallback`; check `A|`, `|x`, `a|b|c` give the same display, run the NameLinking and Compiler tests. `Sanitiser.process`, `ConversationLinking.process` and `NameLinking` repeat the alias derivation, the earliest-eligible-match loop (`Sanitiser.swift:170-182`, `ConversationLinking.swift:134-147`, `NameLinking.swift:77-83`) and the demote-later-mentions loop (`Sanitiser.swift:191-197`, `ConversationLinking.swift:157-163`): extract `linkable`, `firstSafeMatch(of:in:)` and `demoteMentions(of:to:in:)`; the demotion string differs (`process` uses the short name behind `guard !short.isEmpty`, `linkInline` short-or-canonical), so pass it in; `linkInline` guards `!unambiguous.isEmpty`; `nameSpans` records a span instead of rewriting. Pinned by `SanitiserSmokeTests`, naming goldens and the conversation tests: they must pass unedited. Q116 changes the Mac naming overrides: land after it.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh SanitiserSmokeTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SRS-d18 SRS-d19 SRS-c07 (cleanup-audit P48)

### Q236 [auto] (done) two real bugs in model loading and location, plus a glob that lies about itself
spec: C115
needs: -
gate+: yes
do: Found by reading, not run. (1) `GemmaEmbedder.prepare()` (`Shared/RetrievalEngine/GemmaEmbedder.swift:84-94`): two concurrent calls both pass the `loadTask == nil` check before the `TranscriptionActivity` wait loop suspends, each creates a Task, the second overwrites the first, so the 295 MB model loads twice (the exact failure the single-flight comment at 75-79 describes). Move the wait loop inside the single-flight Task; write a test that two concurrent `prepare()` calls start one load (inject the loader). Also keep ONE idle-unload Task: `scheduleIdleUnload()` spawns a new 605 s sleeping Task on every `prepare()` and `embed()` calls `prepare()` per chunk (`EmbeddingIndex.swift:124,127,133`), so a sweep leaves thousands of sleepers; use one task that loops until `lastUse + 600 s`. (2) `MacLocationStamp` shares one `LocationOneShot` instance (`SkriftDesktop/Pipeline/Ingest/MacLocationStamp.swift:31,40-45`); a second `current()` before the first fix returns overwrites the continuation and leaves the first caller suspended. Create `LocationOneShot()` per call as the phone does (`MetadataService.swift:20`). Reachability is low (one stamp per Mac recording). (3) `ResumableModelDownloader.glob` (`ModelDownload/ResumableModelDownloader.swift:245-262`) is a 17-line hand-written matcher whose doc says `*` stays within a path segment while the code lets it cross `/`: replace the body with `fnmatch(pattern, name, 0) == 0` (flag 0, `*` crosses `/` as today) and fix the doc; the patterns mlx-swift-lm passes (`*.safetensors`, `*.json`) are unaffected. The file imports MLXLMCommon, so it is not in the Mac test bundle: put the test in the phone suite. Leave the `hubCacheCopy` migration shim (it saved an 8.9 GB download once; Tuur's call). Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh EmbeddingIndexTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SRS-m1 SRS-c15 SRS-c16 SRS-c23 (cleanup-audit P49)

### Q237 [auto] (done) archive the finished spikes and the stray duplicate mock
spec: C240
needs: -
gate+: no
do: Move, never delete (repo rule): `Skrift_Native/GlassLab/` to `archive/spikes/GlassLab` (its own `project.yml` says to port the result to `MemoDetailView`, which now has `.glassEffect(.clear, ...)` at line 619 with `SkriftMobileUITests/GlassUITests.swift`; only two `archive/handoffs/*.md` prose mentions refer to it); `Skrift_Native/DiarizeSpike/` to `archive/spikes/DiarizeSpike` (its `Package.swift` pins FluidAudio `branch: main` while the apps pin revision `19600a48`; three code comments cite it for measured thresholds, `SpeakerFusion.swift:8`, `VoiceMatcher.swift:16`, `DiarizationService.swift:12`: change the path in the comment); `git rm mockups/Q51.html` (byte-identical to `Skrift_Native/SkriftDesktop/mocks/Q51-apple-notes-import.html`, `plan/RUN.md:73` calls it a stray copy); `Skrift_Native/SkriftMobile/scripts/mklongm4a.swift` (one-off, no target compiles it; remove the `FEATURES.md:158` cell mention); rewrite the docstring of `tools/rescue-lost-recordings.py:1-40` (since Q16 the app sweeps and quarantines orphaned takes: `RecordingRecovery.swift:10-45`, so say it diagnoses quarantined and orphaned takes, drop the stale line cites `LiveRecordingService.swift:433`, `RecordView.swift:548`, pull `Documents/QuarantinedRecordings` too, and merge `pull`/`pull_devlog` into one `copy_from`; keep the tool, `BUGS.md:25`, `RecordingRecovery.swift:24` and `RecoveryQuarantineTests.swift:9` name it). Leave alone: `spikes/EmbeddingBakeoff/` (cited by five live paths: `GemmaEmbedder.swift:9`, `EmbeddingEngine.swift:8`, `SkriftMobile/project.yml:25`, `FEATURES.md:391`, `roadmap.yaml:1520`), `SkriftMobile/mockups/*.html` (`Theme.swift:5` cites them as the signed token source), `plan/sources*.md`, `tools/twin-scan.py`. Confirm with `git grep` that nothing in `gate.sh`, `plan/*.sh` or either `project.yml` references the moved paths before moving.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md PER-d01 PER-d02 PER-d04 PER-d17 PER-d18 PER-c21 (cleanup-audit P50)

### Q238 [auto] (done) one place for preference keys, the isXCTest check and the optional-binding shim
spec: C239
needs: Q222
gate+: no
do: (1) A `PrefKey` enum with each key and its default beside it in `Shared/Model`, used by every writer and reader: `liveTranscription` (x4: `RecordView.swift:52`, `LiveRecordingService.swift:167,445,469`), `liveCaptionAutoOffSeconds` (x2, default 60 in two files), `autoCopyTranscript` (reuse `MemoSaver.autoCopySettingKey`), `karaokeTapToSeek` (x3: `NoteBodyView.swift:84`, `MemoPageView.swift:45`, `SettingsView.swift:13`; fix the "must match TranscriptBodyView" comment, that view is gone), `fadingLastSeenAt` (`WayOutView.swift:54`, `JournalHomeView.swift:20`), `continueCardDismissedDay` (x3, `NotesBottomChrome.swift:19`, `ContinueListeningCard.swift:27`, `AudiobookSeeder.swift:23`), `skrift.publish.author` (`ObsidianSettingsSection.swift:27`, `MemoDetailView.swift:768`; Q158 owns the author-name rule, coordinate), `weatherAPIKey` (reuse `WeatherClient.apiKeyDefaultsKey`), `appTheme` (Q172 owns the ColorScheme mapping), `macSidebarVisible` and the appearance default `"dark"` on the Mac (`RootView.swift:23,25`, `SettingsView.swift:14`, `Theme.swift:108`, `NoteDisplayView.swift:65`). (2) One `isXCTest` for the six `XCTestConfigurationFilePath` lookups (`Shared/Model/Memo.swift:283`, `NotesRepository.swift:33`, `JournalIndexService.swift:49`, `ConnectionsIndexService.swift:105`, `SkriftDesktopApp.swift:66`, `MemoCloudContainer.swift:47`; `LaunchFlags` is phone-only so it cannot host it). (3) One `Binding<Value?>.isPresent` in `Shared/UI` replacing the hand-written `Binding(get: { x != nil }, set: { if !$0 { x = nil } })` at about 14 sites (`AudiobookLibraryView.swift:147-168`, `BookTextSheet.swift:146`, `BookTextFlow.swift:112-143`, `MemoDetailView.swift:475`, `MemoPageView.swift:1035`, `WayOutView.swift:87`, `SkriftApp.swift:100`, Mac `RootView.swift:127`, `WayOutColumn.swift:91`, `SidebarView.swift:127`); `BookShareSheet.swift:111-112` is a different pattern, leave it. Behaviour must not change; `-selectFirstMemo`-style launch flags are untouched. Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh MemoModelTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MRC-d21 MLJ-d17 MMD-c20 MSV-c35 MAU-c07 (cleanup-audit P51)

### Q239 [auto] (done) phone WayOut: call the Shared WayOut directly, one partition
spec: C239
needs: Q178
gate+: no
do: Delete the static forwarders `orderedByImminence`, `oneLiner` and `total` in `SkriftMobile/Features/MemosList/WayOutView.swift:279-312` (production callers 30, 32, 33, 201: use `WayOut.fadingOrdered`, `deletedOrdered`, `oneLiner`; keep `bringBack`, it adds `repository.save()`). `WayOutViewTests.swift:27-100` and `LockedNoteVisibilityTests.swift:75` use them: drop the cases that `WayOutSharedTests` already covers and retarget the rest. Add `MemoLifecycle.partition(_:backlinked:now:)` taking a precomputed backlink set, make the existing `partition` call it and replace `MemosListView.lifecycle(backlinked:)` (`MemosListView+Derived.swift:44-50`) with it, keeping the single backlink scan the comment at 42-43 protects (R92/C278). Q178 edits the one-liner and meta line in `WayOutView`: land after it. Protected-test edits: hand-merge after Tuur's yes.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh WayOutViewTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MLJ-d14 MLJ-d15 (cleanup-audit P52)

### Q240 [auto] (done) speaker transcript: one rebuild, one header regex, one slot assigner
spec: C239
needs: Q183
gate+: no
do: `SpeakerTranscript.swift` rebuilds `**name:** text` joined by blank lines in `setText`, `reassign`, `mergeAdjacentTurns`, `relabel`, `relabelSlot` (lines 138,148,169,180,193) and `SpeakerFusion.swift:44` does the same. Add `Turn.markdown` and one `renamed(_:_ pick: (Int, Turn) -> String?)`; `reassign`, `relabel`, `relabelSlot` become one-liners (`relabelSlot` keeps its count guard). `SpeakerTurnStyle.headerRegex` (line 85) recompiles the pattern `SpeakerTranscript` already compiles at 39: make that one internal and delete `headerPattern`; add `SpeakerTranscript.parsedLabel(_:)` for the bracket strip used at `SpeakerTranscript.swift:66-67` and `SpeakerTurnStyle.swift:96-97` and one `preamble(of:)` for `parseWithPreamble:83-84` and `withPreamble:93-97`. First-appearance slot assignment in `turns(in:)` and `slots(forParsedNames:)` becomes one `SlotAssigner`; drop `HeaderResolver.ambiguous` (`person(for:)` already requires `cands.count == 1`) and add `HeaderResolver.identity(forDisplayed:)` for the four `identity(for: SpeakerTurnStyle.label(for: x))` calls in `SpeakerNaming.swift`. Do NOT touch `SpeakerFusion`'s three scans (re-fusing the same segments must give the same turns). Q183 edits `SpeakerTurnsView` and the active-word code, not these files; keep the public names. `SpeakerTranscriptTests`, `SpeakerFusionTests`, `SpeakerNamingTests` stay green unedited.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh SpeakerTranscriptTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SPL-c10 SPL-c11 SPL-c12 (cleanup-audit P53)

### Q241 [auto] (done) six suspected bugs the audit tripped over: prove each with a test or log why not
spec: C115
needs: -
gate+: yes
do: Each is a reading, not a run. One commit per bug; write the failing test first; if it does not reproduce, log what you found in `BUGS.md` and do nothing else. (1) `SourceKind.of` (`Shared/Pipeline/SourceTaxonomy.swift:54-63`) reads only the raw `mediaSource` key, but the phone writes video notes as `sourceType: "video"` (`MemoSaver.swift:318,354`, `MemoMetadata.swift:51`), so a phone-made video note may classify as a voice memo on the Mac and in the phone's row chips (`MemosListView+Row.swift:131`; `MemoDisplay.swift:55` checks `sourceType` separately). (2) The typed-note marker is raw JSON `{"mediaSource":"typed"}` built by `Memo.newTyped` (`Shared/Model/Memo.swift:386`) and `EditConflicts.makeCopy` (`EditConflict.swift:352`), and `MemoMetadata` does not model that key: any later `memo.metadata = ...` write on a typed note would drop it and turn it into an "Apple Note"; check whether adding a photo to a typed note does. (3) `CloudSyncMonitor.runImportSweeps` (`SkriftMobile/Services/CloudSyncMonitor.swift:143-157`) omits `MemoDeduper`, but `SkriftApp.swift:223-229` says CloudKit dupes land mid-session and the 2026-07-12 crash loop was duplicate memo UUIDs; the foreground gate is the only mid-session dedupe path. (4) `IngestService.ingestNote` (`SkriftDesktop/Pipeline/Ingest/IngestService.swift:417-451`) is the only Mac import that does not stamp `isLocalImport`, while SPEC C49 (as reversed by D159) says a Mac import arrives unrated, and `NoteConsent.isRated(pf)` reads an unstamped inserted row as rated (legacy). (5) `SidebarView.refreshCloudMemos` says `mainContext` returns stale memos after a CloudKit import and fetches through a fresh `ModelContext(cloud)`, but `JournalView.refresh` and `UnpipelinedMemoSheet.load` read `cloud.mainContext`, and `SidebarView.toggleLock`/`deleteQuiet` mutate memos fetched through the throwaway context and then save `mainContext` (`SidebarView.swift:855-880`, `JournalView.swift:78`); check that the change persists and that the Journal river is not stale. (6) Open Settings keeps a stale copy of settings.json (`SettingsView.swift:15,40,494-504`) while the CloudKit runners write vocab, language and prompts to disk; an autosave from the open sheet can write older values back (LWW stamps may self-heal; check). Never run SkriftDesktopUITests; Mac proof = unit tests + full build.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh SourceTaxonomyTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SPL-c25 SMU-c13 MAM-c01 DPE-m1 (ingestNote, missed) DAU-c05 DAU-c15 (cleanup-audit P54)

### Q242 [auto] (done) Mac cloud adapters: one sync gate, one logger, one batch write helper
spec: C239
needs: Q216
gate+: yes
do: Eight App adapters hand-write `cloudKitMacSyncEnabled && MemoCloudStore.container` (`MacCloudDeleteSync.swift:24-26`, `MacCloudMetaSync.swift:26-28,41-43`, `MacCloudEditSync.swift:37`, `VocabularyCloudSync.swift:16`, `PolishPromptsCloudSync.swift:15`, `NamesCloudSync.swift:32-37`, `MemoCloudReconciler+Wiring.swift:86`) and five more sit outside App/ (`ProcessingCoordinator.swift:344,471`, `LifecycleSweepScheduler.swift:86`, `NoteActions.swift:66`, `NoteDisplayView.swift:110`), each loading settings.json afresh. Add `MemoCloudStore.syncContainer` (nil when sync is off or there is no container) and `enum AppLog { static let cloudkit }` for the 16 inline `Logger(subsystem: "com.skrift.desktop", category: "cloudkit")` constructions (also the second Logger in `ConnectionsIndexService.swift:51-53`, use its existing `logger`). `MacCloudMetaSync` already has a single-file `write` helper; add a batch variant that saves once per batch (not per file) and use it from `MacCloudMetaSync.mirror` and `MacCloudDeleteSync.mirror` (the `trashSeenAt` stamp stays in the closure). In `VocabularyCloudSync.run` keep the ordering (destinations re-fetch after the vocab insert) and collapse the four `SettingsStore.shared.save` calls into one dirty flag and one save, with one prewarm call. Do not merge the adapters into one runner. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md DAU-c06 DAU-c07 DAU-c08 (cleanup-audit P55)

### Q243 [auto] (done) polish: one prompt descriptor, one title/summary turn, no redundant canPolish clause
spec: C239
needs: Q187
gate+: no
do: `PolishPromptsStore.swift` has three parallel switches over `PolishPromptKind` (`isEdited`, `key(for:)`, `fallbackText(for:)`, lines 38-44, 88-103) plus 3 key constants, 3 accessors and 3 `store(...)` lines in `adoptSynced`; `PolishSettingsView.PromptEditorView.defaultText` and `currentText` (191-205) add two more. Expose `PolishPromptKind.defaultText` (the store's `fallbackText`) and `PolishPromptsStore.text(for:)`; `isEdited` is `text(for:) != kind.defaultText`; `setText`, `adoptSynced`, `blob` loop over `allCases` with one private descriptor (key, fallback). Do not touch the `promptsTick` mechanism. `MLXPolishEngine.swift:129-158` spells the title turn (budget 64) and summary turn (256) in both `redo` and `polish`: add `titleTurn(plain:)` and `summaryTurn(plain:)` with named budgets (take `plain` as a parameter, `polish` computes it once). `PolishCenter.canPolish` has `|| busyMemoID == memo.id`, redundant because `!isWorking(memo.id)` follows (both are set together in `run` and `runRedo`): drop it. Q187 reorders the polish prompt rows on iPad and Mac: land after it or rebase. `PolishPromptsSyncTests` and `IPadPolishTests` stay green unedited.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh PolishPromptsSyncTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MLJ-c27 MSV-c14 MSV-c15 MSV-c16 (cleanup-audit P56)

### Q244 [auto] (done) export services: one scoped-folder bookmark, one destination root, one outcome mapping
spec: C239
needs: Q225 Q154
gate+: no
do: `ObsidianVault` and `PortfolioVault` (`SkriftMobile/Services/Export/ObsidianPublisher.swift:6-41`, `PortfolioVault.swift:16-48`) are the same security-scoped-bookmark store with a different defaults key (set, resolve, `isConfigured`, `displayName`, clear): add one `ScopedFolderBookmark(key:)` value type; the two enums keep their own extras (`PortfolioVault.folder(for:)`, `seedIfRequested`) and forward to it. The "portfolio destination uses the portfolio folder, otherwise the vault root" derivation with its scope start/stop is written in `ObsidianPublisher.publish` (136-143) and `PublishCoordinator.hasPublished` (129-135): one helper returning picked root, scope root and profile. Do NOT fold the gate sites (63, 95-100): they call the injected `portfolioConfigured()`/`obsidianEnabled()` closures. `ObsidianPublisher.publish` maps `VaultWriteOutcome` to `PublishOutcome` twice (160-165, 217-223): one `PublishOutcome.init(_:relativePath:)` and a `stem(ofRelativePath:)` helper. Q154 replaces the photo-marker converter in the same file; keep your edit away from `convertPhotoMarkers`. `ObsidianPublisherTests`, `PortfolioExportTests`, `PublishCoordinatorTests` stay green unedited.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh ObsidianPublisherTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MSV-c08 MSV-c09 MSV-c10 (cleanup-audit P57)

### Q245 [auto] (done) share sheet: one card chrome, a split saveTapped, one theme
spec: C239
needs: Q228 Q132
gate+: no
do: `SkriftShare/ShareSheetView.swift` draws its card chrome (skSurface fill plus a 0.5 pt white 0.09 hairline, radius 13) in six places (216-310, 315-357, 479-522, 531-574, 576-626): add a private `shareCardChrome(radius:)` and call `honestyLine` from `audioCard` (510-518 inlines it). The cards are not identical (video tile 46x34, url card has no honesty line), so only the chrome is shared. `saveTapped()` (716-842, 127 lines) splits into `audioEntries()`, `videoEntry()`, `fileEntry()`, `mediaEntry()`; add a `trimmedThought` property (trim and empty-to-nil three times), `if let fileURL` instead of the `payload.fileURL!` at 800, one helper for the four index-aligned image arrays, reuse the local `iso` helper at 744 and 835. `ShareTheme` for the `#0e0f16` backdrop (`ShareViewController.swift:29,34,119`, `ShareSheetView.swift:50`, `ShareFeedbackView.swift:24`), the `#1b1d28` surface and the `10_000` constant, with one `shareSheetSurface()` modifier for the sheet block repeated at `ShareSheetView.swift:90-103` and `ShareFeedbackView.swift:48-59`. Q132 and Q150 change the audio chooser and P41 removes `dictationData`: rebase on them. Verify the sheet with the existing probe or by rendering it before and after; extension UI is unverified on a device until Tuur opens the share sheet.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh AudioShareDrainTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md MAM-c02 MAM-c04 MAM-c08 (cleanup-audit P58)

### Q246 [auto] (done) VaultWriter: one ownedName and one place-bytes step for URL and Data attachments
spec: C239
needs: Q234
gate+: yes
do: `Shared/Export/VaultWrite.swift:330-524`: `ownedName` exists for URL (478-484) and Data (489-495) differing only in the equality test; `resolvedName` (384-394) and `writeAsset` (425-442) are two switch-on-`Source` wrappers; `writeAtomic` and `copyOwned` repeat the `NSFileCoordinator` dance. Collapse to one `ownedName(preferred:in:id:isIdentical:)` and one place-bytes step on `VaultAsset.Source`; keep `copyOwned` and `writeOwned` as thin public wrappers (Mac `VaultExporter.swift:238,274,308`, `AttachmentOwnershipTests`, `DataAttachmentOwnershipTests` call them). Keep the second resolve inside `writeOwned`/`copyOwned`: it is the only guard against a clobber when the id-suffixed name is itself taken. Test first (found by reading): `resolvedName` returns `disambiguated(preferred)` without checking that name is free, so if `X id8.png` is occupied by different bytes the embed is patched to `X id8.png` but `writeOwned` writes `X id8 id8.png` and the embed points at the wrong file. Write that test; fix by resolving the id8 name in the same pass that patches the embed. `AttachmentOwnershipTests` and `DataAttachmentOwnershipTests` stay green unedited. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SRS-c01 SRS-m2 (cleanup-audit P59)

### Q247 [auto] (done) compiler: typed shared content and one wiki-link scanner
spec: C239
needs: Q155
gate+: yes
do: `CompilerSharedContent` (`Shared/Export/CompilerInput.swift:53-64,84`) is a string-typed five-field copy of `Shared/Model/SharedContent.swift` compiled into the same targets (both `project.yml`s list `../Shared/Model` and `../Shared/Export`); `Compiler.swift:52,59-65,234-257` switches on `"url"/"text"/"image"/"file"` strings and a default hides a new capture type. Use `SharedContent?` and switch exhaustively on `ShareContentType` (add an explicit `.file: break`, today the default swallows it); delete `CompilerSharedContent`, `MemoExporter.compilerShared` (`SkriftMobile/Services/Export/MemoExporter.swift:58,125-128`) and the lambda in `CompilerBridge.swift:69`; update the five `CompilerTests.swift:325-354` constructors (memberwise init, optionals default nil). Leave `CompilerMetadata` and `PhoneMetadata` to Q155. Add `Sanitiser.bodyLinks(in:)` (`linkOccurrences` minus `![[` embeds) and one replacing-ranges helper (`Sanitiser.nsReplace` exists at `Sanitiser.swift:300`; the right-to-left loop is repeated at `Compiler.swift:312`, `VaultExporter.swift:247,317`, `ObsidianPublisher.swift:257`): `peopleLinks` and `plainifyNonPeopleLinks` use it. `ConnectionWhy.wikiNames` may use `linkOccurrences` + `linkTarget` but keeps its `memo:` exclusion and the length-60 guard; it does not skip embeds or `img_NNN` markers today, so accept that one small change and say so. `CompilerTests` and the corpus goldens stay green unedited; the frontmatter key order is a pinned contract. Q155 moves input building: land after it. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md SRS-c05 SRS-c06 (cleanup-audit P60)

### Q248 [auto] (done) one temp-dir helper and one corpus-root helper per test bundle
spec: C239
needs: -
gate+: no
do: Test-only. `tempDir()` is defined 17 times in 15 desktop test files (some with `addTeardownBlock` cleanup, others without, e.g. `RoundTripParityTests:14-19` vs `UploadTests:13`) and `BookAlignmentTests.swift:11,116` on the phone; the four-level `#filePath` climb to `test-fixtures/corpus` is copied in `BodyGoldenTests.swift:11-18`, `ChipCountParityTests.swift:19-25` and both `CorpusSeedTests.swift:8-14`. Add one `makeTempDir()` (with teardown) per test bundle and one `CorpusSeed.fixtureRoot(file: #filePath)` (`CorpusSeed` is compiled into both test bundles). The 11 phone UI tests that repeat the climb cannot use it (separate bundle): leave them. Behaviour and assertions do not change; this is a protected-path edit that goes through hand-merge after Tuur's yes. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`
source: plan/reads/cleanup-audit.md PER-c13 (cleanup-audit P61)

### Q249 [auto] (dead) accept.sh learns --approve-protected and hand-merge.sh goes
spec: C239
needs: -
gate+: no
do: `plan/hand-merge.sh` re-implements `plan/accept.sh` steps 2-5 with drift: it always sets `done` (accept.sh:129-135 parks `[tuur]` items), leaves the worktree and branch, and runs `git reset --hard $PRE` without the queue backup that `accept.sh`'s `undo_merge` makes (96-100), which can discard uncommitted QUEUE.md state because `queue.sh set` writes into the working tree. Add `--approve-protected "<why>"` to `accept.sh` that skips only the protected-paths block and logs the reason; put the xcodebuild-idle `busy()` wait in one place (`accept.sh --wait`, so `accept-chain.sh` is only a loop); delete `hand-merge.sh`; update the mentions in SPEC.md, QUEUE.md and `plan/RUN.md`. This is the gate machinery and the protected list: Tuur reviews the diff before it merges and nothing else touches `plan/*.sh` in the same session.
check: `./gate.sh`
source: plan/reads/cleanup-audit.md PER-c18 (cleanup-audit P62)

### Q250 [auto] (done) approve: rewrite protected SourceTaxonomyTests.testCaptureSubtypes to seed sharedContentData, then drop the SourceKind.of metadataData fallback
spec: C78 C239
needs: Q138
do: Q138 left a legacy `?? SharedContent.decode(from: memo.metadataData)` fallback in `SourceKind.of` because the protected `SourceTaxonomyTests.testCaptureSubtypes` seeds the `{"sharedContent":…}` wrapper inside metadataData, a shape the phone never writes. On Tuur's yes: rewrite that test to seed `memo.sharedContentData`, delete the fallback, and land it with plan/hand-merge.sh. Never run SkriftDesktopUITests.
check: `./gate.sh`

### Q251 [tuur] (done) decide: Mac quote read-only applies to any note opening with '> ' (Q112, text-only per C172) — keep, or gate on a capture flag so a hand-typed blockquote stays editable
spec: C172
needs: -
do: -
check: Tuur picked; if 'gate it', a follow-up [auto] item is added.

### Q252 [tuur] (done) verify: Q116's SwiftData column rename (@Attribute(originalName:) legacyUnlinkedNames/legacyNamePicksJSON) opens a COPY of the prod Mac store and keeps existing name decisions, before the next prod promotion
spec: -
needs: -
do: -
check: Before the next prod promotion: OK to test the Mac name-store column rename on a COPY of your prod Mac store (never the real one)?
ask: Before the next release: OK to test the Mac name-store change on a COPY of your real Mac data (never the real one)?

### Q253 [tuur] (done) decide: merged-clip and import dating is filename, then file date, never the embedded date (Q134, because AVAudioFile stamps the write moment) — confirm as a SPEC Decision superseding C70's embedded-first order, or say otherwise
spec: -
needs: -
do: -
check: Tuur decided or approved; follow-up item added if needed.

### Q254 [auto] (done) hand-merge: delete IPadDetailConnectionsTests' 0.7/0.8 importance assertions, then the unused ConnectionsPanelLogic.importanceText and isRefineImportance (left by Q119)
spec: -
needs: -
do: Under SPEC D163 (deleting tests of code being deleted): delete the 0.7/0.8 importance assertions in protected SkriftMobileTests/IPadDetailConnectionsTests.swift that pin ConnectionsPanelLogic.importanceText and isRefineImportance, then delete those two now-unused members (left by Q119). Never run SkriftDesktopUITests.
check: `! grep -rq --include='*.swift' 'isRefineImportance' Skrift_Native && perl -e 'alarm 1500; exec @ARGV' plan/mtest.sh IPadDetailConnectionsTests && ./gate.sh`

### Q255 [auto] (done) phone Open-in of .m4b and .epub opens the Books import (ImportKinds .book -> the Books library door via AppURLHandler), finishing C199's .m4b clause left open by Q133
spec: C199
needs: Q133
gate+: yes
do: Q133 made Shared/Pipeline/ImportKinds resolve .m4b and .epub to kind .book, but phone Open-in (AppURLHandler) still ignores them. Route a .book Open-in to the same Books library import the Library tab uses (the BookImportBridge / AudiobookLibrary import path; grep it), so opening an .m4b or .epub from Files or another app adds it to Books. Phone test `BookOpenInRoutingTests` on the pure routing decision. Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh BookOpenInRoutingTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q256 [tuur] (done) review Q108's picked wording: empty library 'No notes yet / Tap Record to capture your first note, or Import audio you already have.'; Way-out footer drops the phone's 'clock only starts once you've opened the app' and the Mac's 'Your iPhone does the permanent deleting'; iPad 'back to calendar' -> 'Back'; Mac loading row 'Getting the model — N%'
spec: -
needs: -
do: -
check: Tuur decided; follow-up item added if he changes it.

### Q257 [tuur] (done) review Q177's picks: empty pane 'Select a note' + doc.text on both (Mac sparkles gone); day/RELATED headers use the phone's 11.5/0.5/secondary; accentSoft 0.13; 'New note (⌘N)' tooltip on both; 'Add a title' prompt on both; locked screen shared body with 'hidden, not encrypted', Mac verb 'Unlock' (was 'Unlock…')
spec: -
needs: -
do: -
check: Tuur decided; follow-up item added if he changes it.

### Q258 [auto] (done) phone suite: MemoExporterTests + PortfolioExportTests fail on export title/filename after Q153 — find the cause, make the code satisfy the protected tests (or report which assertions contradict SPEC for a hand-merge)
spec: C25 C59
needs: -
gate+: yes
do: Reported by the Q155 worker on top of session head (after Q153 merged at 7041ea92): protected phone tests fail — MemoExporterTests.testExportTitleFallback ('Note' vs expected 'Untitled Memo'), MemoExporterTests.testMarkdownPrefersMacEnhancement ('uses the Mac title'), PortfolioExportTests x5 (file named 'the-bench-outside-cafe-garrett.md', expected 'a-bench-made-of-an-oak-slab.md'). The gate runs the Mac suite only, so this slipped. 1) Confirm on the session head: `plan/mtest.sh MemoExporterTests` and `plan/mtest.sh PortfolioExportTests`; then on 9a5f0868~ ancestors if needed to name the commit that broke them (Q153 7041ea92 suspected: ExportNaming / ExportProfile file-name + title ladder; also Q114's NoteTitle ladder and Q177's titlePlaceholder). 2) Fix the CODE so the protected tests pass again while keeping the Q153 parity intent (same file from phone and Mac); never edit those tests. 3) If an assertion genuinely contradicts SPEC C25/C59, stop and report it as 'needs hand-merge: <test, line, why>'. Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh MemoExporterTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh PortfolioExportTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh ExportNamingParityTests && ./gate.sh`

### Q259 [auto] (done) phone: a store that fails to start shows a 'couldn't start' state instead of crashing (NotesRepository.swift:41 fatalError)
spec: C115
needs: -
gate+: yes
do: Found by the Q162 mockup agent: Skrift_Native/SkriftMobile/Services/NotesRepository.swift:41 calls fatalError when the SwiftData/CloudKit store fails to build, so the phone crashes at launch instead of telling the user. Replace the crash with a recoverable path: keep the error, show a plain full-screen 'Skrift couldn't open your notes' state with the error text and a hint (reopen / check iCloud storage), and log it via DevLog. Never delete or recreate the store automatically (data safety). Put the decision in a pure, testable function. Phone test `StoreStartFailureTests`. Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh StoreStartFailureTests && ./gate.sh`

### Q260 [auto] (done) sync a link capture's thumbnail to the Mac as a MemoAsset (phone writes it, Mac card shows it)
spec: C78 C143
needs: Q143
gate+: yes
do: Found by Q143: the phone's link thumbnail lives as a relative file in the phone's recordings dir (`urlThumbnailUrl`, CaptureInboxDrainer.swift:451) and AssetMaterializer syncs only audio, manifest photos, the document and sidecars, so the Mac card always falls back to the globe tile. Ship the thumbnail as a MemoAsset (reuse Kind.photo or add a kind — prefer reuse if it doesn't pollute the photo manifest), materialize it on the Mac into the capture folder where `PipelineFile.captureThumbnailURL` (PipelineFile+CaptureFacts.swift) already looks. Never break existing synced memos (additive only). Desktop test `LinkThumbnailSyncTests`; phone test for the writer side. Never run SkriftDesktopUITests.
check: `grep -rqE "class LinkThumbnailSyncTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q261 [tuur] (done) decide: should list cards follow C25 for captures (needs hand-merge of protected CaptureDisplayTests/NoteCardModelParityTests), and should a Mac import with a real file name show 'Voice note' until it has words (C25 letter) instead of its file name (Q114 kept the name)
spec: -
needs: -
do: -
check: Tuur decided; follow-up item added if he changes it.

### Q262 [tuur] (done) review the Mac unrated-capture banner copy Q143 wrote: 'Not rated, so it is not polished: rate it and the Mac adds a title, tags and summary.'
spec: -
needs: -
do: -
check: Tuur decided; follow-up item added if he changes it.

### Q263 [tuur] (done) Q126 shipped Mac Format > Checklist (⇧⌘L) but no on-screen checklist button — want a toolbar button too? Also eyeball once on Dev: ⌘F find bar docking (Q125) and Return continuing a task line (Q126)
spec: -
needs: -
do: -
check: Tuur decided; follow-up item added if he changes it.

### Q264 [tuur] (done) decide: capture source label — signed mock capture-items.html says 'Shared link', Q122 made every surface read SourceKind.label ('Link' / 'Link · domain'); keep 'Link' or restore 'Shared link' everywhere? Also: hand-merge to delete the unused MemoDisplay.shareCaptureTypeLabel + its protected CaptureDisplayTests case; and should the Mac header date chip show the time?
spec: -
needs: -
do: -
check: Tuur decided; follow-up item added if he changes it.

### Q265 [auto] (done) note card chips wrap instead of clipping: NoteCardView.chipsRow overflows the card with 5+ chips on Mac and phone
spec: C115 C240
needs: -
gate+: yes
do: Found by Q107 and visible in plan/reads/list-p-quiet/mac-quiet-rows-light.png: the shared Skrift_Native/Shared/UI/NoteCardView.swift chipsRow lays chips out with fixedSize and no wrapping, so a row with duration + place + weather + 2 tags runs past the card edge and clips (Mac sidebar and phone list). Wrap the chips with the existing Shared/UI/FlowLayout.swift (max 2 lines, then a '+N' chip if more remain), keeping chip order and spacing. Prove it with a Mac headless -snapshot PNG of a 5-chip and an 8-chip row (look at it) plus a host-less layout test of the line-break decision if one is extractable. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q266 [auto] (done) link captures: the Mac retries a failed link fetch up to 3 times (C72) and the phone titles an untitled link by its host, not 'Capture'
spec: C72
needs: Q136
gate+: yes
do: Left by Q136: (1) the Mac's link capture (IngestService+Captures.swift, LinkFetching seam) does not retry a failed fetch — C72 says up to 3 retries; add a bounded retry with backoff behind the seam (testable with a stub fetcher). (2) The phone still shows 'Capture' for a link with no page title, while the Mac uses the host per C72 — make the phone use the same shared rule (Shared/Pipeline/ImportDoors.swift / LinkCard). Desktop test `LinkFetchRetryTests`, phone test `LinkUntitledHostTests`. Never run SkriftDesktopUITests.
check: `grep -rqE "class LinkFetchRetryTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh LinkUntitledHostTests && ./gate.sh`

### Q267 [auto] (done) hand-merge: update protected IngestServiceTests.testUnsupportedTypeSkipped + MacMixedDropTests.testNoDroppedFileIsEverSilentlySkipped to 'a PDF becomes a file capture', then delete IngestService.acceptsDocuments and its ArrivalPath line (Q136 workaround)
spec: -
needs: -
do: Q136 made a dropped PDF become a file capture; two protected tests still encode the old 'documents are skipped' rule. Under SPEC D163: update IngestServiceTests.testUnsupportedTypeSkipped and MacMixedDropTests.testNoDroppedFileIsEverSilentlySkipped so a PDF is expected to become a file capture (matching shipped behaviour, no new behaviour), then delete IngestService.acceptsDocuments and its ArrivalPath line (the Q136 workaround). Never run SkriftDesktopUITests.
check: `! grep -rq 'acceptsDocuments' Skrift_Native/SkriftDesktop --include=*.swift && ./gate.sh`

### Q268 [tuur] (done) review Q176/Q159 picks (in the Q176 commit message): person editor 'Person'/'New person' + Done on both (Mac was Edit person/Save); Mac names filter always shown when the list has people
spec: -
needs: -
do: -
check: Tuur decided or approved; follow-up item added if needed.

### Q269 [tuur] (done) decide the exported source spelling for a typed note: Q142 writes 'source: Typed-note' (portfolio 'capture: Typed-note') — keep, or another word?
spec: -
needs: -
do: -
check: Tuur decided or approved; follow-up item added if needed.

### Q270 [tuur] (done) Q180 pick to confirm: the Mac now offers Redo when ANY polish part exists — a note with only your chosen title shows Redo too (Mac enhancedTitle also stores a chosen title). Keep, or require a real polish?
spec: -
needs: -
do: -
check: Tuur decided or approved; follow-up item added if needed.

### Q271 [tuur] (done) promotion note: after Q141, undated Apple Note imports carry recordedAt=1970 (MemoDate.unknown); an older installed phone/Mac build would fade them at once — promote both apps together before importing Apple Notes on the new build
spec: -
needs: -
do: -
check: Undated Apple Note imports now carry a 1970 date. An older installed build would fade them at once. Promote phone and Mac together before importing Apple Notes, agreed?
ask: Undated Apple Note imports get a 1970 date, which an older build would fade at once. Release phone and Mac together?

### Q272 [tuur] (done) review Q187/Q185 look picks: the phone memo-link chip now uses the Mac look ('🗒 Title', bordered; was '→ Title' accent-soft) based on Mac-only mocks; inline photos on the Mac now fill the column with a 320pt cap; one transcribe-book battery sentence; phone record waveform silent-bar floor 0.12. Glance at both apps on Dev
spec: -
needs: -
do: -
check: Look on Dev: the phone memo-link chip now looks like the Mac's ('🗒 Title', bordered), Mac inline photos fill the column (320 pt cap), and the record waveform has a quiet-bar floor. Keep all of it?
ask: Three small look changes. 1) On the phone, a link to another note now looks like the Mac's: note icon plus title in a thin box. 2) On the Mac, photos in a note fill the text width. 3) While recording on the phone, quiet moments still show short bars. Keep all three?

### Q273 [auto] (done) Library jump-back does not move the book's own resume place (Q6 mock: 'The book's own place is not moved')
spec: D127
needs: Q151
gate+: yes
do: Q151 built the per-book notes jump-back as open + seek + play, and the player's normal progress persistence then overwrites the book's resume place. The signed mock Skrift_Native/SkriftDesktop/mocks/Q6-library-tab.html says the jump-back toast reads 'The book's own place is not moved'. Make a jump-back playback session not persist position (or restore the saved resume place when the jump-back session ends / the user leaves), and show the mock's toast. Pure, testable decision for 'should this session write progress'. Phone test `BookJumpBackPlaceTests`. Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh BookJumpBackPlaceTests && ./gate.sh`

### Q274 [tuur] (done) device check on the iPhone (Q164): deny the mic in Settings and tap Record — expect one alert with Open Settings, no retry loop; then record a silent take (cover the mic) — expect it treated as a dead take
spec: -
needs: -
do: -
check: On the phone: deny the mic in Settings, tap Record. Do you get one alert with Open Settings and no loop? And does a silent take (mic covered) get treated as a dead take?
ask: Deny the mic in Settings and tap Record: one alert with Open Settings and no loop? Then record with the mic covered: treated as an empty take?

### Q275 [tuur] (done) Q151 picks to settle: the compact phone Library row got an invented trailing '❝ N' capsule (the Q6 mock only draws the tile grid) — keep? Should the jump-back also appear on non-book notes (PDF/podcast)?
spec: -
needs: -
do: -
check: Tuur decided; follow-up item added if needed.

### Q276 [tuur] (done) decide: what makes a note a 'conversation' for name linking — phone: transcript parses with two speaker headers; Mac: two distinct named speakers (Q207 left both, documented)
spec: -
needs: -
do: -
check: Tuur decided; follow-up item added if needed.

### Q277 [auto] (done) hand-merge: rewrite protected CompilerTests.swift:325-354 constructors to SharedContent(type: .url/.text/.image/.image/.file, …) (the unknown-type case becomes .file = 'a .file capture pins nothing'), then delete the Q247 shim SkriftDesktopTests/CompilerSharedContentShim.swift
spec: -
needs: -
do: Under SPEC D163 (ports of tests of deleted code): rewrite the constructors in protected SkriftDesktopTests/CompilerTests.swift (~325-354) to build SharedContent(type: .url/.text/.image/.image/.file, ...) directly — the old unknown-type case becomes .file = 'a .file capture pins nothing' — then delete the Q247 temporary shim SkriftDesktopTests/CompilerSharedContentShim.swift. Assertions keep their meaning. Never run SkriftDesktopUITests.
check: `! test -f Skrift_Native/SkriftDesktop/SkriftDesktopTests/CompilerSharedContentShim.swift && ./gate.sh`

### Q278 [tuur] (done) promotion check (Q260): confirm an older installed phone/Mac build tolerates a synced MemoAsset with the new kind 'thumbnail' (decode/skip, no crash) — or promote both apps together
spec: -
needs: -
do: (fill in)
check: Before promoting only one app: OK if I test whether an older build survives a synced link thumbnail (new asset kind), or do we always promote phone and Mac together?
ask: Always release phone and Mac together (recommended), or first test that an older build survives the new link-thumbnail data?

### Q279 [tuur] (done) SPEC wording to update (from Q174's commit message): C220 says the Mac rotates at 7 s but TranscriptionService.swift:179 uses 20; C199 'silently ignored today' is stale (Open-in routes via ImportKinds); C145 should mention the built Files chooser + Q150 long-audio offer
spec: -
needs: -
do: (fill in)
check: SPEC fixes to match the code: the Mac rotates live captions at 20 s (SPEC says 7 s); Open-in now routes via ImportKinds (C199 says 'silently ignored'); C145 gains the Files chooser and the long-audio offer. OK to update the SPEC wording?
ask: Update the SPEC wording to match the code (Mac captions rotate at 20 s, Open-in routing, Files chooser)?

### Q280 [tuur] (done) look (Q171): phone list header Import/Record/New-note row + filter date picker after the shared VerbRow/ChipRowStyle move — compile-checked only, never seen on a sim or device
spec: -
needs: -
do: On the iPhone 17 Pro (Dev 190, Q407), open the notes list and look at the Import / Record / New-note row and the filter's date picker, against how they looked before Q171.
check: Look on the phone: the list header's Import / Record / New-note row and the filter date picker moved to shared code. Do they look the same as before?
ask: On the phone, look at the top of the notes list: the Import, Record and New-note buttons, and the date picker in the filter. The code behind them moved. Do they look the same as before?

### Q281 [tuur] (done) look (Q245): share a voice memo, a video, a URL and a photo into Skrift on the phone and check the share sheet cards look unchanged after the shared card-chrome refactor — compile-checked only
spec: -
needs: -
do: On the iPhone 17 Pro (Dev 190, Q407), share into Skrift Dev a voice memo from Voice Memos, a video from Photos, a link from Safari and a photo from Photos; look at each share-sheet card.
check: On the phone, share a voice memo, a video, a link and a photo into Skrift. Do the share-sheet cards look unchanged?
ask: From other apps, share into Skrift a voice memo, a video, a web link and a photo. Do the cards Skrift shows look the same as before?

### Q282 [auto] (done) Done means processed on every device: one shared QueueFilter predicate
spec: C61 C115 D167
needs: -
gate+: yes
do: Tuur 2026-10-03 (D167): a note is Done once processed, on phone, iPad and Mac; 'exported' is the destination row's own state, never the filter. Today phone ProcessPile.matches (ProcessPile.swift:50-51) and Mac AppModel.matchesFilter disagree, and the Mac Done list can hold stranded notes. Add one Shared `QueueFilter` (Needs Work / Done) both apps call; delete the two local predicates. Desktop test `QueueFilterSharedTests`, phone test `QueueFilterPhoneTests`. Never run SkriftDesktopUITests.
check: `grep -rqE "class QueueFilterSharedTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QueueFilterPhoneTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q283 [auto] (done) remove the Unsynced chip and the dead photo/place filters
spec: D68 D148 D168
needs: -
gate+: yes
do: Tuur 2026-10-03 (D168): delete the Unsynced filter chip (nothing sets syncStatus=.synced outside seeders) and the dead `MemoFilter.hasPhotosOnly` / `.place` on the phone; supersedes D148's chip line. Keep the Mac status pills (D135 platform difference, no change). Phone test `FilterChipsPrunedTests` asserts the chip row no longer offers Unsynced. Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh FilterChipsPrunedTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q284 [auto] (done) keyboard shortcuts: ⌘N new note, ⇧⌘N Record everywhere; Mac ⌘F, ⌘1/⌘2, Record menu
spec: C112 C114 D169
needs: -
gate+: yes
do: Tuur 2026-10-03 (D169): on every device ⌘N = new note and ⇧⌘N = Record. iPad binds ⌘N twice today (SkriftApp.swift:243-248 'New Recording' and MemosListView+Header.swift:116 'New note'): make the app menu Record ⇧⌘N. Mac: add a Record menu command (⇧⌘N), ⌘F focuses search, ⌘1 Notes / ⌘2 Review. One `.commands` block per app; the key table lives in Shared (`AppShortcuts`) so both read one source. Update FEATURES.md:61/:126. Desktop test `AppShortcutsTests` asserts the table. Never run SkriftDesktopUITests.
check: `grep -rqE "class AppShortcutsTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q285 [auto] (done) Mac shared-text capture draws the accent-bar quote, not a SHARED CONTENT box
spec: C240 D170
needs: -
gate+: yes
do: Tuur 2026-10-03 (D170): the no-bubbles rule covers the shared TEXT quote only. On the Mac, a text capture renders as the phone's borderless italic accent-bar quote; link, file and photo captures keep their cards on both apps. Reuse the phone's quote style via a Shared view/style struct if one exists. Prove it with a Mac headless -snapshot-capture PNG of a text capture (look at it) committed under plan/reads/Q-no-bubbles/. Never run SkriftDesktopUITests.
check: `./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q286 [auto] (done) .md import becomes a typed note on phone and Mac
spec: C76 C77 D171
needs: -
gate+: yes
do: Tuur 2026-10-03 (D171): a plain .md file imports as a typed note on both apps — body is the file, title from the first heading, no capture card. Today the Mac makes an 'Apple Note' (IngestService.ingestNote) and the phone a 'Text' capture (CaptureInboxDrainer). One rule in Shared ImportKinds. Desktop test `MarkdownImportTests`, phone test `MarkdownImportPhoneTests`. Never run SkriftDesktopUITests.
check: `grep -rqE "class MarkdownImportTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh MarkdownImportPhoneTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q287 [auto] (done) a video filed Inspiration/Idea/Project keeps its movie as a synced asset
spec: C63 C148 D172
needs: -
gate+: yes
do: Tuur 2026-10-03 (D172): 'take a video of something cool — a bridge, a lamp — keep the video and the transcript, for portfolio ideas'. Build C63/C148: a new `MemoAsset.Kind.video` (≤ ~200 MB, refuse larger with a clear message), written by the phone share/import path and the Mac import path when the note is filed Inspiration / Idea / Project; whichever device exports it copies the movie into the export. Phone share card copy 'the video file itself isn't kept' changes accordingly; fix the stale Mac comment IngestService.swift:355. Other destinations keep no movie. CloudKit: the new kind is a schema change — note it for promotion. Desktop test `VideoAssetSyncTests`, phone test `VideoAssetPhoneTests`. Never run SkriftDesktopUITests.
check: `grep -rqE "class VideoAssetSyncTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh VideoAssetPhoneTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q288 [auto] (done) Mac Looking back anchors on today
spec: C231 D173
needs: -
gate+: yes
do: Tuur 2026-10-03 (D173): the Mac `river(for:now: selectedDay)` re-anchors Looking back on the selected calendar day; anchor on today like the phone, iPad and the signed journal-desktop mock. Desktop test `LookbackAnchorTests`. Never run SkriftDesktopUITests.
check: `grep -rqE "class LookbackAnchorTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q289 [tuur] (done) mockup: Mac recorder pause/resume and a confirmed discard
spec: C220 C262 D173
needs: -
gate+: yes
do: Tuur 2026-10-03 (D173): the Mac recorder gets pause / resume and a discard that asks first (the phone has both; its X discards without confirm, R71/C262). Mock first (locked process for new UI): draw the Mac record bar from SOURCE (Features/Recording/), with pause, resume and discard + confirm states. Publish the artifact; the build item follows sign-off.
check: Mac recorder mock (claude.ai/artifact/QztPhoVwuVYKVouVVHBeUW): after × asks 'Discard this recording?', should the take keep recording until you answer, or pause? Go to build?

### Q290 [auto] (done) Mac: add a recording to an existing note
spec: C220 D173
needs: -
gate+: yes
do: Tuur 2026-10-03 (D173): the Mac can record but has no 'Add recording' to an existing note (note-menu-03, capture-quick-16; FEATURES.md:30 '➖'). Add it to the note menu, appending via Shared AudioClipMerge the way the phone appends (see Q220). Desktop test `MacAppendRecordingTests` on the append step. Never run SkriftDesktopUITests.
check: `grep -rqE "class MacAppendRecordingTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q291 [auto] (done) Mac quote read-only only for real captured quotes
spec: C172 D175
needs: -
gate+: yes
do: Tuur 2026-10-03 (D175): Q112 made any Mac note opening with '> ' read-only; gate it on the capture flag (an audiobook/text capture) so a hand-typed blockquote stays editable. Desktop test `QuoteReadOnlyGateTests`. Never run SkriftDesktopUITests.
check: `grep -rqE "class QuoteReadOnlyGateTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q292 [auto] (done) one shared 'conversation' rule: two or more speaker headers
spec: D175
needs: -
gate+: yes
do: Tuur 2026-10-03 (D175): a note is a conversation for name linking when its transcript parses with two or more speaker headers (named or 'Speaker N'), on both apps. Today the phone uses headers and the Mac two distinct named speakers (Q207). One Shared predicate. Desktop test `ConversationRuleTests`. Never run SkriftDesktopUITests.
check: `grep -rqE "class ConversationRuleTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q293 [auto] (done) an import with a real file name shows the name until it has words, on both apps
spec: C25 D176
needs: -
gate+: yes
do: Tuur 2026-10-03 (D176): amend C25 — an imported audio with a real file name (not a generic 'New Recording N' / 'Audio N' default) shows that name until it has words, on phone and Mac; generic names fall back to 'Voice note'. One rule in the Shared NoteTitle ladder. Desktop test `ImportFileNameTitleTests`, phone `ImportFileNameTitlePhoneTests`. Never run SkriftDesktopUITests.
check: `grep -rqE "class ImportFileNameTitleTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh ImportFileNameTitlePhoneTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q294 [auto] (done) delete the unused MemoDisplay.shareCaptureTypeLabel
spec: D176
needs: -
gate+: yes
do: Tuur 2026-10-03 (D176): 'Link' / 'Link · domain' (SourceKind.label) stays; the capture-items mock's 'Shared link' is superseded. Delete the unused `MemoDisplay.shareCaptureTypeLabel` and its protected CaptureDisplayTests case (blanket rule D163). Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh CaptureDisplayTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q295 [auto] (done) Mac Redo only after a real polish
spec: D176
needs: -
gate+: yes
do: Tuur 2026-10-03 (D176): Q180 shows Redo when ANY polish part exists, including a title Tuur chose himself (Mac enhancedTitle stores chosen titles). Redo only when a real polish ran (summary, tags or a generated title); a chosen-title-only note offers Polish. Desktop test `RedoOfferTests`. Never run SkriftDesktopUITests.
check: `grep -rqE "class RedoOfferTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

### Q296 [tuur] (dead) mockup: a checklist button in the Mac editor toolbar
spec: D177
needs: -
gate+: yes
do: Tuur 2026-10-03 (D177): add an on-screen checklist button next to the Mac's Format > Checklist (⇧⌘L). Mock first: draw the current Mac editor toolbar from SOURCE, add the button and its on-state. Publish the artifact; the build follows sign-off.
check: Mac checklist button mock (claude.ai/artifact/QyS5vmkXQKAhSdK1QU1Cv5): left next to the notes-list toggle (A) or right before Process (B)? A multi-line selection would become a checklist on both apps, OK?

### Q297 [auto] (dead) jump-back on PDF and podcast notes too
spec: D177
needs: -
gate+: yes
do: Tuur 2026-10-03 (D177): the audiobook jump-back (Q151/Q273, `AudiobookSession.isJumpBack`, `beginJumpBack(to:)`) also appears on non-book notes that have a source position — PDF captures and podcast clips. Keep the '❝ N' Library capsule. Phone test `JumpBackNonBookTests`. Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh JumpBackNonBookTests && ./gate.sh`

### Q298 [tuur] (done) promotion (Q186 + Q287): deploy the CloudKit prod schema for the new synced Memo.includeAudioInExport (and MemoAsset kind video once Q287 lands) before promoting either app
spec: -
needs: Q366
do: (fill in)
check: Before promoting the new build: OK to deploy the CloudKit prod schema for the new synced export-audio setting (and the video asset once it lands)? It needs you in the CloudKit console.
ask: When we release to the real Skrift: I release phone and Mac on the same day, I first test the Mac upgrade on a copy of your real data, and I need you for about ten minutes on Apple's iCloud developer website to switch on the new kinds of synced data. OK?

### Q299 [auto] (done) in-app feedback button on phone and iPad (FeedbackKit, app id skrift)
spec: D179
needs: -
gate+: yes
do: Tuur 2026-10-04: adopt the shared FeedbackKit (~/Hackerman/feedback-kit, read its ADOPTING.md first and follow it) in SkriftMobile only (iOS + iPad; the Mac app is untouched). Approved design: https://claude.ai/artifact/JyZDsYr7HaEjsBoWTepjo6. Skrift deviations from ADOPTING, on purpose: (a) package path is ABSOLUTE `/Users/tiurihartog/Hackerman/feedback-kit` in Skrift_Native/SkriftMobile/project.yml (relative paths break in .claude/worktrees); (b) tracked `Skrift_Native/SkriftMobile/Config/Feedback.xcconfig` = `FEEDBACK_KEY =` then `#include? "/Users/tiurihartog/.config/feedback-kit/skrift.xcconfig"` (the key already exists there, mode 600, outside git — NEVER print, copy or commit it); set it as the SkriftMobile target's configFiles for Debug and Release. Info.plist (project.yml info properties): FeedbackAppID = skrift, FeedbackKey = $(FEEDBACK_KEY); keep Skrift's existing NSMicrophoneUsageDescription. Start it in the App init with Skrift's own accent token (Shared/UI/Palette) and privacy line 'Private, only Tuur reads it. Voice notes are deleted 30 days after they are transcribed.' Tag every top-level screen and sheet with .feedbackScreen("Name"): Notes list, note detail, Record, Books library, Player, Journal/Review, Settings, and the iPad split equivalents. AUDIO (hard rule, hardware-flavoured): FeedbackKit's recorder sets .playAndRecord and deactivates the session afterwards, which would cut Skrift's own audio. Call FeedbackKit.setVoicePaused("Voice notes are off while Skrift is recording or playing.") whenever Skrift is recording, running live caption, playing an audiobook or a memo, or capturing a quote, and setVoicePaused(nil) when all of those stop — drive it from the one place that already knows (find the recorder/player state owners), not per view. Prove it: a phone test FeedbackWiringTests (Info.plist FeedbackAppID == 'skrift', FeedbackKey non-literal; the voice-pause rule as a pure function over the audio states); then build Debug on the iPhone 17 sim, launch, tap the feedback button, and save a screenshot of the sheet reading 'From the Notes screen' to plan/reads/feedback-kit/sheet.png (LOOK at it). Device behaviour (audio interplay) stays UNVERIFIED — say so. Update FEATURES.md. Never run SkriftDesktopUITests.
check: `grep -rqE "class FeedbackWiringTests\b" Skrift_Native/SkriftMobile/SkriftMobileTests && ls plan/reads/feedback-kit/sheet.png >/dev/null && perl -e 'alarm 1500; exec @ARGV' plan/mtest.sh FeedbackWiringTests && ./gate.sh`

### Q300 [auto] (done) feedback sheet + button use Skrift's own palette and follow dark mode
spec: D179
needs: -
gate+: yes
do: Q299 shipped FeedbackKit with Pike's default light cream palette (plan/reads/feedback-kit/sheet.png) on a dark Skrift. Pass Skrift's tokens from Shared/UI/Palette into every FeedbackAppearance colour (background, surface, ink, muted, line, gold label, recording) for light AND dark, in Features/Feedback/FeedbackKitWiring.swift; if FeedbackAppearance can't switch with the colour scheme, pass dynamic UIColor-backed Colors. Re-screenshot the sheet + button in dark and light to plan/reads/feedback-kit/ and LOOK. Never run SkriftDesktopUITests.
check: `ls plan/reads/feedback-kit/sheet-dark.png >/dev/null && ./gate.sh`

### Q301 [auto] (done) remove the old Mail-based feedback screen now that FeedbackKit is in
spec: D179
needs: -
gate+: yes
do: Q299 left Features/Feedback/FeedbackCaptureView.swift (the Mail-based feedback screen) in place. Find its entry points; replace them with FeedbackKit.present() (e.g. the Settings row) and delete the old view and its helpers. Phone test that the Settings feedback row calls the kit. Never run SkriftDesktopUITests.
check: `./gate.sh`

### Q302 [tuur] (tuur) check on Skrift Dev Mac (Q242): add a custom word, a person and edit a polish prompt on the phone — do all three arrive on the Mac, and does a deleted note disappear from the Mac? (cloud adapters were refactored, gate-only)
spec: -
needs: -
do: With Dev 190 on the iPhone 17 Pro and the Mac (Q407): on the phone add a custom word, add a person, change one polish instruction, then delete a note; check the Mac a minute after each.
check: On Skrift Dev Mac: add a custom word, a person and edit a polish prompt on the phone. Do all three arrive on the Mac, and does a note you delete on the phone disappear from the Mac?
ask: On the phone, add a custom word, add a person, and change one polish instruction. Do all three show up on the Mac a minute later? Then delete a note on the phone. Does it disappear from the Mac too?

### Q303 [auto] (done) Mac -snapshot modes never read the live Dev store
spec: -
needs: -
gate+: yes
do: PRIVACY (found by Q285, same slip as Q33): the Mac -snapshot-capture sidebar renders from Tuur's live Dev SwiftData store, so real note titles land in PNGs workers save. Make every headless -snapshot* mode run against an in-memory store seeded by DemoSeed (never the on-disk Dev container), and assert it in a test that the snapshot path's ModelContainer is in-memory. Never run SkriftDesktopUITests.
check: `./gate.sh`

### Q304 [tuur] (tuur) On Skrift Dev Mac: open a rated voice note, ⋯ > Add recording, say a sentence, stop. Is the new audio appended (plays through), the words added after a blank line, and does the phone show the same after sync?
spec: -
needs: -
do: On the Mac (Dev 190, Q407): open a rated voice note, ⋯ > Add recording, say a sentence, stop, play across the join; then open the same note on the iPhone 17 Pro after sync.
check: On Skrift Dev Mac: open a rated voice note, ⋯ > Add recording, say a sentence, stop. Is the new audio appended (plays through), the words added after a blank line, and does the phone show the same after sync?
ask: On the Mac, open a voice note, choose ... > Add recording, say one sentence and stop. Does the note play straight on into your new sentence, are the new words a new paragraph, and does the phone show the same?

### Q305 [auto] (done) feedback sheet follows Skrift's theme natively (FeedbackKit interfaceStyle + onAccent)
spec: -
needs: -
gate+: yes
do: WAIT until ~/Hackerman/netcup-server main contains the dark-host change (commit 14cb39a or later: FeedbackAppearance.interfaceStyle + onAccent) — check with git -C ~/Hackerman/netcup-server log main --oneline 
check:  grep -i dark. Then in Features/Feedback/FeedbackKitWiring.swift pass interfaceStyle: .unspecified (Skrift follows its own appTheme) and onAccent: white (Skrift's own on-accent token), drop the UIColor-provider FeedbackPalette workaround from Q300 where the kit now handles it, and re-screenshot sheet-dark/sheet-light (LOOK: the 'What gets sent' chevron and the mic glyph must be legible). Update FeedbackPaletteTests to match (it is a NEW-ish file from Q300; if protected now, keep edits to ports). Never run SkriftDesktopUITests.|`ls plan/reads/feedback-kit/sheet-dark.png >/dev/null && ./gate.sh`

### Q306 [auto] (done) phone devlog prints audio route-change reasons by name
spec: -
needs: -
gate+: yes
do: Q218 made the DEV devlog route-change line print 'AVAudioSessionRouteChangeReason(rawValue: N)'. That trace is the first tool for hardware audio bugs (CLAUDE.md), so map the reason (and the category/mode where logged) to readable names (newDeviceAvailable, oldDeviceUnavailable, categoryChange, override, wakeFromSleep, noSuitableRouteForCategory, routeConfigurationChange, unknown) in one small helper with a phone test RouteChangeNameTests. Log-only, no audio-session behaviour change. Never run SkriftDesktopUITests.
check: `perl -e 'alarm 1500; exec @ARGV' plan/mtest.sh RouteChangeNameTests && ./gate.sh`

### Q307 [auto] (done) a PDF inside a dropped folder becomes a file capture, like a loose PDF
spec: -
needs: -
gate+: yes
do: Q267 made a loose dropped PDF a file capture, but IngestService.ingestFolder still skips a PDF with ImportReport.pdfNotOnMac (ImportReportTests.testFolderOfPicturesIsReportedNotIgnored ~121 pins it). Make the folder path use the same rule as a loose drop (one decision in ImportKinds / skipReason(onMac:)), port that protected test's PDF expectation (it encodes the old, now-inconsistent rule), and fix plan/parity.md:28/64/97 mentions of acceptsDocuments. Never run SkriftDesktopUITests.
check: `./gate.sh`

### Q308 [auto] (done) pull-phone-feedback can read FeedbackKit's outbox over USB
spec: -
needs: -
gate+: yes
do: Until the feedback server is deployed, notes sit in the phone app's container at Library/Application Support/FeedbackKit/outbox/ (<id>.json + .m4a + .png). Extend .claude/skills/pull-phone-feedback/ so it copies that folder with xcrun devicectl device copy from --domain-type appDataContainer --domain-identifier com.skrift.mobile.dev, transcribes the .m4a with the same ASR the skill already uses (or ~/Hackerman/netcup-server/tools/feedback.sh's parakeet path), and folds them into the digest with screen, app version and answered-question id. Docs/tooling only; no app code. Test on a fixture outbox folder, never on the vault.
check: `test -f .claude/skills/pull-phone-feedback/SKILL.md && grep -q 'FeedbackKit/outbox' .claude/skills/pull-phone-feedback/SKILL.md`

### Q309 [tuur] (tuur) On the Mac and iPad (Dev): press ⌘N (new note), ⇧⌘N (record), ⌘F in a note and outside one, ⌘1/⌘2. Do they all do what you expect? Note the Mac's File > New Window is gone (⌘N is New Note now) — OK?
spec: -
needs: -
do: On the Mac (Dev 190, Q407) and the iPad (install Dev 190 first if it runs an older build): press ⌘N, ⇧⌘N, ⌘F inside a note and in the list, ⌘1 and ⌘2.
check: On the Mac and iPad (Dev): press ⌘N (new note), ⇧⌘N (record), ⌘F in a note and outside one, ⌘1/⌘2. Do they all do what you expect? Note the Mac's File > New Window is gone (⌘N is New Note now) — OK?
ask: Try these shortcuts on the Mac and iPad: Cmd-N new note, Shift-Cmd-N record, Cmd-F search (inside a note it finds in that note), Cmd-1 and Cmd-2 switch tabs. Do they all work? The Mac no longer has File > New Window, because Cmd-N now makes a note. OK?

### Q310 [auto] (done) fix the flaky photo-OCR test MemoSaverTests.testSavedPhotoBecomesSearchableWithoutRelaunch
spec: -
needs: -
gate+: yes
do: It fails intermittently on the iPhone 17 sim (Vision OCR returns text: nil within the 10 s poll on a freshly erased or loaded simulator) — RUN.md Q13 finding; it blocked Q219's accept on 2026-10-04 though Q219 touched no OCR code. Make the test deterministic: inject a fake OCR recogniser for the save->searchable contract (the real Vision call belongs in a separate, tolerant test), or wait on the index notification instead of a fixed 10 s poll. This edits a protected test: report 'needs hand-merge' with the exact diff; do not weaken what the test proves (a saved photo's text is searchable without relaunch). Never run SkriftDesktopUITests.
check: `perl -e 'alarm 1500; exec @ARGV' plan/mtest.sh MemoSaverTests && ./gate.sh`

### Q311 [tuur] (tuur) On the phone (Dev 177+): open a voice note, add a recording to it, then play across the join. Does the audio continue cleanly with no silent tail, and do the karaoke words stay in time after the join?
spec: -
needs: Q453
do: On the iPhone 17 Pro (Dev 190, Q407): open a voice note, ⋯ > Add recording, say a sentence, stop; play from a few seconds before the join.
check: On the phone (Dev 177+): open a voice note, add a recording to it, then play across the join. Does the audio continue cleanly with no silent tail, and do the karaoke words stay in time after the join?
ask: On the phone, open a voice note and add a recording to it. Play from just before the point where the two recordings meet. Does it run on without a silent gap, and does the word highlighting stay in time with your voice?

### Q312 [auto] (done) phone MemosListUITests fail at the first seeded-memo wait
spec: -
needs: -
gate+: yes
do: Found by Q230 on 2026-10-04: SkriftMobileUITests/MemosListUITests fails 6/6 at the first wait for a seeded memo (testSearchFiltersMemos line ~62), already on head 5b576277 before Q230. The gate does not run phone UI tests, so a recent merge broke the UI-test seeding unnoticed — suspects: Q222 (LaunchFlags accessors removed; UITests read raw -seed args), Q230 (seeders now #if DEBUG — UI tests run Debug, should be fine), Q282/Q283 (list filters/chips changed). Bisect over the session's merges with the one class, find the cause, fix the app or the UI test's seed/launch args (UI test files are not protected). Run ONLY this phone UI class on the iPhone 17 sim; never run SkriftDesktopUITests or any Mac UI test.
check: `perl -e 'alarm 1800; exec @ARGV' xcodebuild test -project Skrift_Native/SkriftMobile/SkriftMobile.xcodeproj -scheme SkriftMobile -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath Skrift_Native/SkriftMobile/build -skipMacroValidation -skipPackagePluginValidation -only-testing:SkriftMobileUITests/MemosListUITests -quiet && ./gate.sh`

### Q313 [auto] (done) perf library: a separate, never-synced Dev store seeded with ~2,000 realistic notes on phone and Mac
spec: -
needs: -
gate+: yes
do: For the speed sweep (Tuur 2026-10-05). Add a DEBUG-only launch flag `-perfLibrary` on the phone (LaunchArgs.swift) and the Mac. With the flag, the app opens a SEPARATE on-disk SwiftData store file (e.g. `perf.store` next to the normal one) with CloudKit OFF (`cloudKitDatabase: .none`), and on first launch seeds it once; without the flag the normal Dev store and its sync are untouched, and the perf store can never upload. Also use a separate names.json/vocab path under the flag so fake people never reach the real names DB or NamesRecord sync. Seeder lives in Shared/ (one generator both apps call), deterministic (fixed RNG seed): 2,000 memos spread over 3 years — ~70% voice notes with transcripts (lengths: most 50-400 words, 5% 2,000-6,000 words), 10% conversations (**Name:** turns), 10% typed notes, 5% link captures, 5% audiobook quotes; ~300 with 1-4 photos (generated images ~2000 px, real JPEG bytes as MemoAssets), ~60 with a short generated audio file (AAC, few seconds, real bytes), tags from a pool of 80, 150 people with aliases in the perf names file, memo links between ~200 notes, a mix of ratings incl. unrated, ~100 fading and ~50 in trash, some locked. Seeding must be fast enough (<2 min on an iPhone 13) and run off the main thread with a progress line. Mac: same flag on Skrift Dev, PipelineFile rows as the Mac ingest would make them. Do NOT touch Release behaviour (all of it #if DEBUG). Unit test `PerfLibrarySeederTests` (phone target): the generator is deterministic, produces the counts above into an in-memory store, and the perf store configuration has no CloudKit database and a different URL from the default store.
check: `perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh PerfLibrarySeederTests && ./gate.sh`

### Q314 [auto] (done) perf: opening a note does no whole-library work; the hidden neighbour pages go
spec: -
needs: -
gate+: yes
do: From plan/perf2/MEASURED.md (iPhone 13, 2,000 notes): each note open costs 1-3 s of main thread in MemoPageView's .task/body — recomputeBacklinks (full allMemos + Backlinks.targets over every transcript) and ladderTitle()/NoteTitle.firstLine/NoteSnippet.plain for EVERY note, repeated for each page the horizontal pager realises; tapping a related note animates the pager across the LazyHStack and stalls halfway (Tuur saw it). Swipe-between-notes has been OFF since 2026-07-16 (MemoDetailView.swift scrollDisabled), so: replace the pager with ONE MemoPageView for the current selection (memo-link / related-note hops swap the note, no sideways slide; keep the edit-conflict gate, the player bar, back navigation, iPad column layout). Build backlinks and link-picker titles from ONE shared cache (Shared/) keyed on a memo-set version that bumps on save/insert/delete/sync import, computed off the main actor, titles built only for notes that link here. Readers: plan/perf2/b-phone-note-editor.md N1 N2 N11, e-search-review.md E7 E8, h-shared-data.md P2. Update FEATURES.md if the note-hop behaviour line changes. Tests: new `NoteOpenWorkTests` (phone target) — opening a note with 2,000 in-memory memos does not call a full-corpus title build, the backlink cache is reused across two opens with no save between and rebuilt after a save.
check: `perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh NoteOpenWorkTests && ./gate.sh`

### Q315 [auto] (done) perf: the phone notes list and search do work per change, not per redraw over the whole library
spec: -
needs: -
gate+: yes
do: From plan/perf2/MEASURED.md (iPhone 13, 2,000 notes): searching 'morning' + clearing = ~10 s main thread (letters appear ~5x slower than typed); stopping a recording = 6.4 s; Done after typing = 2.9 s; all in MemosListView.body → derived → filtered/listRows/matchesSearch and MemoLifecycle.backlinkedIDs. Make the list's derived data (rows, sections, chip counts, backlinkedIDs, enhanced titles, fading set) a cached model rebuilt only when the memo set version changes, not on every body pass; precompute each memo's lowercased search text once per memo version (shared matcher in Shared/ stays the one matcher for phone, iPad, Mac — Q103); debounce search input ~150 ms and narrow from the previous result when the query extends; stop MemosListView observing all of CloudSyncMonitor (observe only the fields it shows). Readers: a-phone-list-launch.md A1 A2 A3 A9, e-search-review.md E1 E2 E4, h-shared-data.md S1 L1. Keep every list behaviour identical (filters, sort, sections, fading, locked, search fields per C236). Tests: new `ListDerivedCacheTests` (phone target) — a body pass with an unchanged memo set does not rebuild rows; a search keystroke does not re-lowercase unchanged memos; results identical to the uncached path for a fixed corpus.
check: `perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh ListDerivedCacheTests && perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh LaunchWorkTests && ./gate.sh`

### Q316 [auto] (done) perf: phone launch and return-to-app sweeps leave the main thread and run once
spec: -
needs: -
gate+: yes
do: From plan/perf2/MEASURED.md (iPhone 13, 2,000 notes): cold launch = 4.11 s to first frame; returning from the home screen = ~4 s main thread ('froze for a second'). Main cost: AssetMaterializer.captureMissing/captureFiles/fileSize (1.4 s at launch, lstat-heavy), allMemos, FadingSweep, MemoSaver.recoverStuck*, PhotoTextIndexer, MemoDeduper — all on the main actor, and LaunchWorkGate is never marked at launch so the first foreground repeats the sweeps. Keep the recording-recovery sweep FIRST (C99) and correct; move the rest off the main actor (background ModelContext / ModelActor), first frame must not wait on them; mark LaunchWorkGate at launch; captureMissing checks only memos changed since its last run (persisted checkpoint) instead of stat-ing every file. CAVEAT: the perf seed gives ~1,540 voice notes an audioFilename with no file on disk — measure and test with files PRESENT too. Readers: a-phone-list-launch.md A5 A6 A7, c-phone-record-capture.md C2, i-images-memory-energy.md. Tests: extend `LaunchWorkTests` — launch then first foreground runs each sweep once; captureMissing with an unchanged store stats no files; add `LaunchOffMainTests` asserting the sweeps run off the main actor.
check: `perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh LaunchWorkTests && perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh LaunchOffMainTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh RecoverySweepTests && ./gate.sh`

### Q317 [auto] (done) perf: the Books tab and the player stop decoding the library and the sidecars on the main thread
spec: -
needs: -
gate+: yes
do: From plan/perf2/MEASURED.md (iPhone 13, 2,000 notes, 5 books): opening Books + a book = 2.7 s main thread: AudiobookLibraryView.row → BookNotesJoin.counts (decodes Memo.metadata for every memo, per row) and ReadAlongModel.reloadIfNeeded → FileTranscript / BookAlignmentStore sidecar decodes on main. Compute per-book note counts once per memo-set version (one pass, cached, off main); decode transcript/alignment sidecars off the main actor once per open (no isFresh re-decode); downsample covers to display size (ImageIO thumbnail) and cache. Readers: d-books.md D-B1a-d D-B2a-c D-B3, i-images-memory-energy.md I5. Behaviour identical. Tests: new `BookNotesCountCacheTests` (phone target) — counts computed once for N rows and equal to the old per-row counts; sidecar decode happens off the main actor.
check: `perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh BookNotesCountCacheTests && ./gate.sh`

### Q318 [auto] (done) phone MemoDetailUITests: drop the swipe test, rewrite the tag test for TagEditorRow
spec: -
needs: -
gate+: yes
do: Run 2026-10-05 after Q314: MemoDetailUITests 5/7 pass (open non-first memo, delete-to-next, edit, split speakers, open). Two stale failures, both older than Q314: testSwipeBetweenMemos (swipe-between-notes OFF since 2026-07-16, pager removed by Q314) — delete it; testAddTagInDetail taps 'tag-editor-done', which Q28 (0c2a90fa, shared TagEditorRow: own row, no sheet) removed — rewrite it to add a tag through TagEditorRow and assert the chip appears. Also add testRelatedNoteHopOpensInPlace if the seeded memos can link (seed a [[memo:]] link if needed). UI test files are not protected. Run ONLY this phone UI class on the iPhone 17 sim; never run any Mac UI test.
check: `/usr/bin/lockf -t 3600 /tmp/skrift-sim.lock xcodebuild test -project Skrift_Native/SkriftMobile/SkriftMobile.xcodeproj -scheme SkriftMobile -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath Skrift_Native/SkriftMobile/build -skipMacroValidation -skipPackagePluginValidation -only-testing:SkriftMobileUITests/MemoDetailUITests -quiet && ./gate.sh`

### Q319 [tuur] (done) re-run the 7-minute speed flow on the iPhone 13 (Dev 179, perf library) to measure Q314-Q317
spec: -
needs: -
do: Same flow as plan/perf2/MEASURED.md: the orchestrator launches the app under Instruments with -perfLibrary (xctrace --launch, time in SECONDS), Tuur scrolls, opens 5 long notes and taps a related note, types and presses Done, searches 'morning' and clears it, goes home 5 s and back, records 15 s and stops, opens Books and a book. Compare each moment against the b178 column.
check: `test -d .queue/perf/b179/2-flow.trace`

### Q320 [auto] (done) perf: the list rebuild and the [[ link picker reuse the shared backlink index and title cache
spec: -
needs: -
gate+: yes
do: Leftovers named by Q314 and Q315 (plan/RUN.md findings, plan/perf2/MEASURED.md: Stop = 6.4 s main incl. MemoLifecycle.backlinkedIDs 774 ms). (1) ListDerivedCache's base rebuild still rescans every transcript for backlinks: read `repository.backlinkIndex()` (Shared/Pipeline/BacklinkIndex.swift, keyed on memoSetVersion) instead of MemoLifecycle.backlinkedIDs over allMemos, keeping the result identical (fading/way-out rules that depend on 'is linked to'). (2) The '[[' link picker builds a title for every note on its first open after a save, on main: make NoteTitle's emptyFallback lazy (autoclosure) in Shared/Model/NoteTitle.swift and cache SourceKind.of per memo version so building picker rows does no per-note JSON parse; build the picker titles off main once per memoSetVersion. Shared code: keep the Mac callers compiling and identical. Tests: extend `ListDerivedCacheTests` (rebuild uses the index: results equal MemoLifecycle.backlinkedIDs on a fixed corpus incl. copy-edit-only links and trashed linkers) and `NoteOpenWorkTests` (picker titles built once per version, equal to the old builder).
check: `plan/mtest.sh ListDerivedCacheTests && plan/mtest.sh NoteOpenWorkTests && ./gate.sh`

### Q321 [auto] (done) search hit in a note: bright yellow highlight, the hit scrolled to the middle of the screen
spec: -
needs: -
gate+: yes
do: Tuur 2026-10-05 on the iPhone 13: opening a note from a search result highlights the hit too faintly and scrolls it to the BOTTOM of the screen. Want: a bright yellow highlight (like a highlighter; readable in light and dark mode — dark text on yellow) on every occurrence of the term, and the first hit scrolled to the vertical middle of the visible editor area (above the keyboard/player bar). Code: Skrift_Native/SkriftMobile/Services/SearchHitBridge.swift, Features/MemoDetail/NoteBodyView.swift (search-hit path), MemosListView.swift (sets the hit). Check whether the Mac and iPad have the same search-hit path; if so single-source the highlight colour and centring rule in Shared/ (feedback_shared_code_first) and apply it there too. Render it and look: sim screenshot of a note opened from a search for a word near the end of a long note, light and dark. Test: `SearchHitCenteringTests` (phone target) — the computed scroll offset puts the hit's rect centre at the visible area's centre (clamped at the top/bottom of the text).
check: `plan/mtest.sh SearchHitCenteringTests && ./gate.sh`

### Q322 [auto] (done) perf: a save with no changes is a no-op, and a note edit does not rebuild the list or the hidden Books tab
spec: -
needs: -
gate+: yes
do: From plan/perf2/MEASURED.md (b179 flow re-run): NotesRepository.save() bumps memoSetVersion even when the context has no changes; MemoDetailView's onDisappear save therefore makes every note CLOSE rebuild the Notes list base (allMemos ~1.0 s + ListDerivedCache.base ~1.0 s over 5 closes) — Tuur feels a stutter on open/close; each typing commit's save also re-runs the list base and the hidden AudiobookLibraryView.body behind the editor (Tuur: lag after a space). Fix: save() returns early (no save, no bump) when !context.hasChanges; split the version so a body-text edit of ONE memo updates that memo's row/search text incrementally instead of rebuilding the whole base (keep results identical to a full rebuild — ListDerivedCacheTests' equality corpus); AudiobookLibraryView must not re-evaluate on memo edits when its counts are unchanged (Q317's BookNotesCountCache already keys counts). Tests: `SaveNoopTests` (phone target) — save with no changes leaves memoSetVersion unchanged; extend ListDerivedCacheTests — editing one memo's transcript rebuilds one row, not the base; results equal a full rebuild.
check: `plan/mtest.sh SaveNoopTests && plan/mtest.sh ListDerivedCacheTests && plan/mtest.sh NoteOpenWorkTests && ./gate.sh`

### Q323 [auto] (done) perf: the phone notes list scrolls and filters without re-measuring and re-diffing every row
spec: -
needs: -
gate+: yes
do: From plan/perf2/MEASURED.md (b179 flow re-run, iPhone 13, 2,000 notes): fast scrolling keeps the main thread ~75% busy (self-sizing cells: ListCollectionViewCellBase.preferredLayoutAttributesFitting → hostSizeThatFits 3.9 s, cell creation 4.5 s per 20 s), and typing in search still diffs the whole sectioned List (ListDiffable.sectionIndex 1.9 s). Investigate with the trace first (scratchpad scripts in plan/perf2/MEASURED.md header), then fix the biggest: candidates — give NoteCardView a cheap, stable size (no ChipFlowLayout measure pass per sizing; keep the Q312 ChipSlot clipping rule), stable row identity and Equatable row values so SwiftUI skips unchanged rows, fewer/cheaper section headers during search. Do NOT change how a card looks: render before/after sim screenshots of the list (cards with 0, 2 and 5+ chips, photo, quote) and compare by eye. Test: `ListRowEquatableTests` (rows with unchanged inputs compare equal; section identity stable across a search keystroke).
check: `plan/mtest.sh ListRowEquatableTests && plan/mtest.sh ListDerivedCacheTests && ./gate.sh`

### Q324 [auto] (done) phone notes list: day headers scroll away with the notes (D180)
spec: -
needs: -
gate+: yes
do: D180 (Tuur 2026-10-06): the phone/iPad notes list's day-section headers stop pinning; they scroll with the rows. Measured cost of pinning: UIKit's pinned-supplementary solve (_UICollectionCompositionalLayoutSolver updatePinnedSectionSupplementaryItemsForVisibleBounds) = ~27% of main-thread scroll work at 2,000 notes on the iPhone 13 (plan/perf2/MEASURED.md, Q323 finding in plan/RUN.md). Keep the header's look identical (text, spacing, colour) — only the pinning goes; keep sections for search/filter grouping. Check whether the Mac sidebar pins its day headers too: if it shares the code, change both; if not, leave the Mac alone and say so. Render and look: iPhone 17 sim screenshots (UDID 4962056D-2AE0-46AD-A04F-3663AE7698CF, -perfLibrary) before and after, mid-scroll, light and dark — the header must no longer sit over the rows at the top. Run SkriftMobileUITests/MemosListUITests. Test: `ListHeadersScrollTests` (the list's section header style/config is the non-pinned one).
check: `plan/mtest.sh ListHeadersScrollTests && ./gate.sh`

### Q325 [auto] (done) build: Mac note photos — add at the caret, zoom + markup viewer, 'Downloading from iCloud…' (Q128 mock, D182)
spec: -
needs: -
gate+: yes
do: Build Skrift_Native/SkriftDesktop/mocks/Q128-mac-note-photos.html as signed in SPEC D182, WITHOUT the toolbar photo button (D181): a photo is added at the caret by paste, drag-drop and an Edit/Insert-menu item; one click selects a photo, double-click opens the zoom + markup viewer (reuse the phone's markup model where shared); an `[[img_NNN]]` whose file has not arrived shows the grey card + 'Downloading from iCloud…' like the phone instead of raw marker text. Shared code first (C117 / feedback_shared_code_first). Test: `MacNotePhotoTests` (desktop UnitTests: insert at caret writes the marker at the caret offset; missing-file marker renders the placeholder state). Mac proof = headless -snapshot PNGs you LOOK at + full SkriftDesktop build (-skipMacroValidation); never run any Mac UI test. Build to the signed mock; draw nothing the mock doesn't show.
check: `./gate.sh`

### Q326 [auto] (done) build: Mac records weather and daypart; the OpenWeatherMap key comes from the phone (Q144 mock, D182)
spec: -
needs: -
gate+: yes
do: Build Skrift_Native/SkriftDesktop/mocks/Q144-mac-weather-daypart.html as signed in SPEC D182: a Mac recording gets weather + daypart metadata like the phone (same shared MemoMetadata types); the OpenWeatherMap key syncs from the phone over iCloud (no separate Mac field unless none ever synced — then the Settings row the mock shows); a file dragged into the Mac gets no place and no weather. Never log or commit the key. Test: `MacWeatherMetadataTests` (desktop UnitTests: a Mac take with a synced key + stubbed fetch writes weather/daypart; a dropped file writes none). Mac proof = headless -snapshot PNGs you LOOK at + full SkriftDesktop build (-skipMacroValidation); never run any Mac UI test. Build to the signed mock; draw nothing the mock doesn't show.
check: `./gate.sh`

### Q327 [auto] (done) build: Mac shows iCloud sync trouble — Settings row, in-list capsule only when broken, signed-out message (Q162 mock, D182)
spec: -
needs: -
gate+: yes
do: Build Skrift_Native/SkriftDesktop/mocks/Q162-mac-icloud-state.html as signed in SPEC D182: a Settings row with the sync state; the note list shows the capsule ONLY when sync is broken, turned off or signed out (never during normal syncing); the signed-out message per the mock. Read state from the existing CloudKit account/monitor APIs. Test: `MacSyncStateTests` (desktop UnitTests: each account/monitor state maps to the right row text and capsule visibility). Mac proof = headless -snapshot PNGs you LOOK at + full SkriftDesktop build (-skipMacroValidation); never run any Mac UI test. Build to the signed mock; draw nothing the mock doesn't show.
check: `./gate.sh`

### Q328 [auto] (done) build: Mac recorder pause/resume and a discard popover that pauses while it asks (Q289 mock, D182)
spec: -
needs: -
gate+: yes
do: Build Skrift_Native/SkriftDesktop/mocks/Q289-mac-recorder-pause.html as signed in SPEC D182: pause/resume on the Mac recorder; × asks 'Discard this recording?' in a POPOVER anchored to ×, not a window alert; the take pauses while it asks, Discard throws it away, Keep resumes recording. Recording safety first (C99: segments + launch sweep must still recover a killed take). Test: `MacRecorderDiscardTests` (desktop UnitTests on the recorder model: ask pauses, keep resumes, discard deletes the segments). Mac proof = headless -snapshot PNGs you LOOK at + full SkriftDesktop build (-skipMacroValidation); never run any Mac UI test. Build to the signed mock; draw nothing the mock doesn't show.
check: `./gate.sh`

### Q329 [auto] (done) captured quotes edit like normal text on phone and Mac; tapping a quote word seeks the audio everywhere (D183)
spec: -
needs: -
gate+: yes
do: SPEC D183 (Tuur 2026-10-06): no 'Fix quote' verb; a captured audiobook/shared-text quote is editable like the rest of the note on phone and Mac — undo Q112's read-only quote (C172) and the phone's equivalent; karaoke keeps highlighting the words that still line up after an edit (word index alignment via the existing KaraokeMap; no crash or wrong-word highlight when the edit changes the word count — degrade to no highlight for unmatched words). Tapping a word in a quote during playback seeks the quote audio there: the phone already has QuoteWordSeek (CaptureQuoteViews.swift:61, Q83) — check it actually fires in the current note screen (Q314 rebuilt it) and add the same on the Mac (shared seek lookup). Update FEATURES.md + C172 wording. Tests: `QuoteEditKaraokeTests` (phone target: edited quote keeps highlighting matched words, no out-of-range) + desktop UnitTests for the Mac seek. Phone: sim screenshot of an edited quote during playback, LOOK at it. Mac proof = headless -snapshot PNGs you LOOK at + full SkriftDesktop build (-skipMacroValidation); never run any Mac UI test. Build to the signed mock; draw nothing the mock doesn't show.
check: `plan/mtest.sh QuoteEditKaraokeTests && ./gate.sh`

### Q330 [auto] (done) 'New person…' in the text menu for any selected word, phone and Mac (D184)
spec: -
needs: -
gate+: yes
do: SPEC D184 (Tuur 2026-10-06): selecting/long-pressing a word the app does not know as a name offers 'New person…' in the system text menu (UIEditMenu on the phone's NoteBodyView, the NSTextView context menu on the Mac's BodyTextView); it opens the existing person editor (phone PersonEditorView via PersonEditCore.materialise, Q113; the Mac's new-person-from-a-name flow, Q184) prefilled with the selection, and after saving, that mention links like any known name. Hide the item for empty/whitespace selections and for text already linked. Test: `NewPersonFromSelectionTests` (phone target: the menu offers the item for a plain word, not for a linked name; materialise gets the trimmed selection). Phone sim screenshot of the menu, LOOK at it. Mac proof = headless -snapshot PNGs you LOOK at + full SkriftDesktop build (-skipMacroValidation); never run any Mac UI test. Build to the signed mock; draw nothing the mock doesn't show.
check: `plan/mtest.sh NewPersonFromSelectionTests && ./gate.sh`

### Q331 [auto] (done) remove note reminders on phone, iPad and Mac (D185)
spec: -
needs: -
gate+: yes
do: SPEC D185 (Tuur 2026-10-06): remove note reminders everywhere. Phone/iPad: the bell chip, '⋯ > Remind me…', the list long-press 'Remind me…' (context-remind-button), ReminderSheet, ReminderScheduler/ReminderPlan and every launch/foreground/sync call into it, and any reminder filter or count. Mac: the reminder row/chip (2d685e56) and any alarm code. On first launch after the update, each device removes the app's pending/delivered reminder notifications (UNUserNotificationCenter, the reminder identifiers only — keep FeedbackKit's and any other notifications). KEEP the synced `Memo.remindAt` property in the SwiftData model, unused, with a comment pointing at D185 (CloudKit schema + older installed builds). Lifecycle: a reminder no longer holds a note off the fading clock (MemoLifecycle touch/held lists) — update the shared rule and its tests; export already skips the reminder. Update FEATURES.md (Note reminders row → removed, D185) and the SPEC clauses C92/C162 wording to 'removed by D185'. Fix or delete every test that only pins reminders (UI tests are not protected; protected unit tests that only pin removed behaviour: list them in your report, do not edit them). Tests: `RemindersRemovedTests` (phone target: no code path schedules a notification for remindAt; the launch cleanup removes only reminder identifiers; a note with remindAt set fades like any other). Run SkriftMobileUITests/MemosListUITests. Never run any Mac UI test; Mac proof = full build + headless -snapshot you look at.
check: `plan/mtest.sh RemindersRemovedTests && ./gate.sh`

### Q332 [auto] (done) Personal videos keep and sync their movie like every other video (D188)
spec: -
needs: -
gate+: yes
do: SPEC D188 (Tuur 2026-10-06): the Personal boundary is 'never goes to Claude', not 'never to iCloud'. Q287 (merged @212d1a78, finding in plan/RUN.md) syncs a video's movie as MemoAsset kind 'video' only while filed Inspiration/Idea/Project and withdraws the synced blob when filed Personal. Change it: every video keeps its movie (<= the 200,000,000-byte cap in Shared/Pipeline/VideoKeep.swift) as a synced asset whatever its destination, on phone and Mac (MacMemoAuthor.syncVideoAsset / MacCloudMetaSync.setDestination, phone MemoSaver.keepMovie / AssetMaterializer); filing to Personal no longer deletes the synced blob. The portfolio export (ObsidianPublisher.movieProvider, VaultExporter) still copies the movie only for Inspiration/Idea/Project; no movie ever goes into the Obsidian vault. Make sure no Personal note content reaches any AI/Claude path (grep the polish/enhancement and semantic-index entry points for a destination check and say what you found). Update FEATURES.md rows 'Four export destinations' and 'Video import'. Tests: update the Q287 tests you own (VideoAssetSyncTests, VideoAssetPhoneTests are new from Q287 — if the gate marks them protected, list the change instead) and add `PersonalVideoSyncsTests` (a Personal video keeps its synced asset; refiling Personal↔Project never deletes it; the Personal export copies no movie).
check: `plan/mtest.sh PersonalVideoSyncsTests`

### Q333 [auto] (done) build the Apple Notes import triage per the Q71 mock (Mac reads the Notes database)
spec: C117 C238
needs: Q71
gate+: yes
do: Build Skrift_Native/SkriftDesktop/mocks/Q71-apple-notes-triage-v3.html (artifact https://claude.ai/artifact/LhvR3Dimcr6H5JpCQPFzqA), signed with Tuur's picks: route 1 = the Mac reads the Apple Notes database (NoteStore.sqlite, Full Disk Access is fine) and keys every note on ZICCLOUDSYNCINGOBJECT.ZIDENTIFIER (Q72 finding), so a declined note is never offered again even if renamed; locked notes stay behind; batches of 10, 'Next 10' locked until all ten are decided; 'Never import' (not 'Delete'); 'Skip for now' kept; resumable over days with a clear 'continue where you left off'; 'import what I've decided so far' at any point; Apple Notes tags become Skrift tags; no folder step when the export has no folders; dates per Q141 (creation date or 'date unknown'). Moving imported notes into an Apple Notes folder is OUT (Q76: needs an unsandboxed non-App-Store build). FIRST step, before any UI: prove the Mac app can open a read-only COPY of ~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite under its current sandbox/entitlements with Full Disk Access granted; if it cannot, stop and report (file:line of the entitlement, the exact error) — do not change signing or sandbox settings. Never read Tuur's real notes content beyond a schema/count probe; tests use a fixture database you generate. Screen proof: headless -snapshot PNGs of each triage state put next to the mock file, every difference in colour, type and spacing listed. Never run any Mac UI test. Tests: `AppleNotesTriageTests` (desktop UnitTests: declined UUID never re-offered, renamed note still recognised, batch lock, resume state persists, tags mapped, locked notes skipped).
check: `./gate.sh`

### Q334 [tuur] (done) On the iPhone 17 Pro (Dev, after Q232): start a recording, look at the Lock Screen and Dynamic Island Live Activity, end it
spec: -
needs: -
do: -
check: Live Activity after Q232 (SkriftShared framework removed): Lock Screen + Dynamic Island show the recording and end cleanly.
ask: Start a recording on your phone and look at the Lock Screen and Dynamic Island. Does the recording show there, and does it go away when you stop?

### Q335 [tuur] (stuck) Mac (the REAL Skrift, after Q337 and the release; D189/Tuur 2026-10-11): grant Full Disk Access, open Import > Apple Notes…, report the start screen (Q333's first real read)
spec: -
needs: Q370
do: -
check: The Q333 triage opens your real Notes database (row count, first batch shows real titles), or the start screen names the exact error.
ask: Give Skrift Dev Full Disk Access (System Settings > Privacy & Security), then on the Mac open Import > Apple Notes…. Does it show your notes in batches of 10, or what does the start screen say?

### Q336 [auto] (done) Skrift Dev fills its own synced store with the fake test library, on phone and Mac, and can remove it again
spec: -
needs: -
gate+: yes
do: Tuur 2026-10-10: Skrift Dev is the test environment and should carry the fake notes everywhere; his real notes (incl. the Apple Notes import) go in the real Skrift only. Today the Q313 perf library (Shared/Corpus/PerfLibrarySeeder.swift, `-perfLibrary`) seeds a SEPARATE never-synced store, so the 2,000 fake notes only live on the iPhone 13. Add a DEBUG-only Settings action on phone/iPad and Mac Dev: 'Fill with test notes' seeds the same deterministic library into the NORMAL Dev store, so it syncs through the Dev CloudKit environment to every Dev device (memos, assets, the 150 fake people into the Dev names DB). Every seeded memo carries a marker (e.g. metadata `testLibrary: true`) and 'Remove test notes' deletes exactly the marked ones everywhere (soft-delete path, then purge) and their fake people. Seeding twice never duplicates (deterministic ids). Never compiled into Release (#if DEBUG, checked by a test). Keep `-perfLibrary` working for perf traces. Tests: `TestLibrarySyncSeedTests` (phone target: seeds into the given store with the marker; idempotent; remove deletes only marked notes and fake people; Release guard). Mac: full build + headless -snapshot of the Settings row you look at. Never run any Mac UI test.
check: `plan/mtest.sh TestLibrarySyncSeedTests`

### Q337 [auto] (done) Apple Notes importer: fix the review's blocker and should-fixes before the first real run
spec: -
needs: Q333
gate+: yes
do: Review of Q333 (2026-10-11, read-only, paths under Skrift_Native/SkriftDesktop/). Fix all of these, each with a fixture-backed test: (1 BLOCKER) NotesBodyDecoder.swift:126-133 reads Note at top-level field 3, but real ZDATA is NoteStoreProto{2: Document{2: version, 3: Note}} (apple_cloud_notes_parser proto/notestore.proto): descend into field 2 when present; the fixture must write the real wrapper (AppleNotesTriageTests.swift:51 writes the bare Document today). (2) NotesBodyDecoder.swift:265-275 paragraph styles: 100 dotted and 101 dashed → '- ', 102 numbered, 103 checkbox (with tick state from Todo), 4 monospaced → plain or code fence; fix the test at :337-339. (3) a rated note whose body is nil or whose import throws must stay retryable: pendingImports scans ALL rated decisions with skriftID == nil, not only the open batch (AppleNotesTriage.swift:134-147, TriageModel.swift:184-191), and the report lists them. (4) idempotent import: persist() after every markImported (TriageModel.swift:154-156), and store the Notes ZIDENTIFIER on the PipelineFile/Memo so a retry reuses the existing note instead of minting a new UUID (AppleNotesImporter.swift:26, :41-48). (5) a note whose media was dropped (pictures etc.) never appears under 'Safe to delete in Apple Notes' (TriageView.swift:357,383); persist `unmapped` in TriageDecision so it survives a relaunch. (6) cap the sanitised title in the import folder name at 80 characters (AppleNotesImporter.swift:27-28). (7) hashtag alt-text lookup by the attachment ZIDENTIFIER from the runs, not ZNOTE/ZNOTE1 (NotesStoreReader.swift:155-172). (8) denied-screen copy: grant Full Disk Access, then quit and reopen Skrift (TriageView.swift:141). (9) sweep stale $TMPDIR/skrift-notes-* copies at load (NotesStoreReader.swift:84-87); Never-import decisions store only the UUID, no title (AppleNotesTriage.swift:14-15). Also: creation-date order 3→2→1 like the Obsidian importer; the 'one flat list, no folders' text only when there really are no folders (TriageView.swift:166,171); decode bodies off the main thread (TriageModel.swift:100). Never open the real Notes database or ~/Library/Application Support/Skrift/. Mac proof = desktop UnitTests + full build + headless -snapshot you look at; never run any Mac UI test.
check: `./gate.sh`

### Q338 [auto] (done) two destinations: Personal and Portfolio; idea / inspiration / project become preset tags (D189)
spec: -
needs: -
gate+: yes
do: Build SPEC D189 exactly as `~/Hackerman/Tiurihartog.com/docs/SKRIFT-REQUEST.md` section 'DO THIS NOW' lists (read it first; the rest of that file is history): NoteDestination = .personal/.portfolio, .portfolio exports to `<root>/_inbox/`; old idea/inspiration/project values decode as .portfolio + that tag (do NOT read Tuur's real data to check; just make the decode safe); the chip row keeps the PRIVATE ¦ PORTFOLIO divider with two chips, and when Portfolio is picked shows idea / inspiration / project as one-tap tag presets beside `+ add tag`; NoteDestination.reserved stops routing; `needs: - credit` keyed on the inspiration tag (Compiler.swift ~127); drop `summary:` from the portfolio profile; everything else in that list unchanged. Q332/D188 video rule: every video keeps and syncs its movie; the portfolio export copies the movie for Portfolio notes. Phone, iPad and Mac, shared code first. Screen proof: sim screenshot of the chip row (Personal; Portfolio with presets) and a Mac -snapshot, both LOOKED at. Tests: `TwoDestinationsTests` (decode of old values, export path `_inbox/<slug>.md` with media beside it and preset tags in `tags:`, credit rule) on phone and Mac. Update FEATURES.md 'Four export destinations' row.
check: `./gate.sh`

### Q339 [auto] (done) Dynamic Island: the live recording waveform does not move (Lock Screen fine)
spec: -
needs: -
gate+: yes
do: Tuur 2026-10-11 on the iPhone 17 Pro, Dev 183 (after Q232 moved RecordingActivityAttributes into Services/Recording): the Live Activity shows on the Lock Screen and in the Dynamic Island, but the Dynamic Island waveform stays still. Find why (ContentState not updated for the island, an update throttle, or the island view not animating a timeline) in SkriftWidget/SkriftLiveActivity.swift and Services/Recording/RecordingActivityManager.swift; fix; keep the existing update throttle budget. Hardware-flavoured: add a DevLog line per activity update so the device trace proves it. Test: `RecordingActivityCaptionTests` still passes plus a unit test on whatever state the island reads.
check: `plan/mtest.sh RecordingActivityCaptionTests`

### Q340 [auto] (done) 'Fill with test notes' blocks while 'building the index' although it says it runs in the background
spec: -
needs: -
gate+: yes
do: Tuur 2026-10-11, iPhone 17 Pro, Dev 183: tapping Fill with test notes showed 'building the index' for a long time and the screen behaved as if blocked, though the copy says it runs in the background; it did finish (~1,700 notes). Find what runs on the main actor during Fill (seeding, the semantic index build, or the list rebuild per insert) — Shared/Corpus/TestLibraryRunner.swift, TestLibrarySync.swift; move it off main or batch the inserts so the UI stays responsive, and make the status line honest. Test: `TestLibrarySyncSeedTests` extended: seeding inserts in batches and does not run on the main actor.
check: `plan/mtest.sh TestLibrarySyncSeedTests`

### Q341 [auto] (done) FeedbackKit: tag every top-level phone/iPad screen and sheet with .feedbackScreen
spec: -
needs: -
gate+: yes
do: ~/Hackerman/netcup-server/ADOPTING.md step 5: put `.feedbackScreen("<Name>")` on each top-level screen and sheet so a feedback note says which screen it came from. Today only QuoteCaptureFlowView, AudiobookPlayerView and RecordView carry it. Add: Notes list, note screen, quick note, Books/Library, Review/Journal, Settings, Names, the share sheet's card, the Text sheet, the tag editor sheet, the person editor. Names are short and plain ('Notes', 'Note', 'Books', 'Review', 'Settings', …). Also confirm FeedbackKitWiring.swift passes nothing that disables the new previews/status features. Test: a UI test that opens the feedback sheet from the Notes list and asserts 'From the Notes screen' (phone sim, `-skipOnboarding`).
check: `./gate.sh`

### Q342 [auto] (done) Mac: FeedbackKit button in Skrift's Mac app (after FeedbackKit gets macOS support)
spec: -
needs: -
gate+: yes
do: Tuur 2026-10-11: 'make sure the mac app also has that feedback bubble'. BLOCKED until the netcup-server FeedbackKit session ships macOS support (requested 2026-10-11 from session 'Add under construction previews to FeedbackKit'); check `grep -L 'canImport(UIKit)' ~/Hackerman/netcup-server/Sources/FeedbackKit/*.swift` and ADOPTING.md's macOS steps before starting. Then: add the FeedbackKit package product to the SkriftDesktop target (project.yml), start it in the Mac App struct with Skrift's palette (reuse FeedbackPalette from the phone if it compiles on macOS), tag the Mac's top-level views with .feedbackScreen, Help > Send feedback… menu item. Proof: full Mac build + headless -snapshot of the panel you look at; never run a Mac UI test.
check: `./gate.sh`

### Q343 [auto] (done) a photo taken while capturing an audiobook quote is lost
spec: -
needs: -
gate+: yes
do: Feedback note 2b8bc952 (Tuur 2026-10-11, iPhone 17 Pro, Dev 184): while adding a note to a book quote (QuoteCaptureFlowView / the capture's ramble) he took a picture; the saved note says 'and then a picture of a trash can' but has no photo. Screenshot: ~/.feedback/skrift/2026-10/2b8bc952-b169-4ff9-b6a5-96b7e5587a52.png. Find where the capture flow drops the photo (camera result not attached to the quote memo, marker not inserted, or asset not saved), fix it so the photo lands in the ramble at the moment it was taken like a voice note's photo (C11/C13 timed placement), and make sure it syncs as a MemoAsset. This is data loss: also check every other capture path (share-text capture, quote capture without audio) for the same drop. Test: `QuoteCapturePhotoTests` (phone target). Reply to the sender when merged: `feedback.sh status skrift 2b8bc952-b169-4ff9-b6a5-96b7e5587a52 done '…build N'`.
check: `plan/mtest.sh QuoteCapturePhotoTests`

### Q344 [auto] (done) note header: the body text can overlap the Personal / Portfolio row
spec: -
needs: -
gate+: yes
do: Feedback note 719dfdbf (Tuur 2026-10-11, Dev 184, after Q338): 'before, the text was clipping over the personal versus portfolio buttons; now it works' — intermittent. His screenshot (~/.feedback/skrift/2026-10/719dfdbf-b11f-49ad-8c63-e997cf32dcbc.png) shows the expanded PRIVATE ¦ PORTFOLIO row with the body starting right under it, no gap. Find the layout race (header height measured before the destination row expands/collapses, or the editor's top inset not updating when the row changes) in MemoPageView / the hosted header, fix it, and give the body the same gap below the row as below the other header rows. Render and LOOK: sim screenshots with the row collapsed, expanded, and while toggling, light and dark. Reply to the sender when merged.
check: `./gate.sh`

### Q345 [auto] (done) a book-quote note's title shows the literal '> ' quote marker
spec: -
needs: -
gate+: yes
do: Seen in feedback note 2b8bc952's screenshot (Dev 184): the note title reads '> The first complete Odyssey in English w…' — the markdown quote marker leaks into the derived title. Fix the title ladder (Shared NoteTitle / ladderTitle) so a quote capture's title is the quote text without '> ' (or the book title, whichever the ladder rules say), on phone and Mac; keep one shared rule. Test in `NoteTitleQuoteTests` (phone) + a desktop case.
check: `plan/mtest.sh NoteTitleQuoteTests`

### Q346 [auto] (done) check: appending a recording to a typed note (no audio yet) may discard the new clip
spec: -
needs: Q343
gate+: yes
do: Found by the Q343 worker (2026-10-11): MemoSaver.appendRecordingAsync bails and discards the clip when memo.audioURL is nil, i.e. a typed note with an empty audioFilename (QuickNote, a typed note's ⋯ Add recording). Confirm with a failing test whether those paths can reach it; if yes, a typed note that gets its first recording must keep it (the clip becomes the note's audio, its text appended after the typed body, photos per Q343). Possible data loss: verify, don't assume. Test: `AppendToTypedNoteTests`.
check: `plan/mtest.sh AppendToTypedNoteTests`

### Q347 [auto] (done) book quote capture writes a second '> ' into the quote text
spec: -
needs: -
gate+: yes
do: Found by Q345 (2026-10-11) from feedback note 2b8bc952's screenshot (~/.feedback/skrift/2026-10/2b8bc952-b169-4ff9-b6a5-96b7e5587a52.png): the quote block shows a literal '> ' inside the italic quote text, i.e. the stored body is '> > The first…'. Q345 hid it in titles; find where the audiobook quote capture (QuoteCaptureFlowView / MergedCaptureView / the quote text source: book transcript sentences or read-along text) adds the second marker, fix it at the source, and make the display/export of an existing doubled quote show one marker. Test: `QuoteMarkerSourceTests` (phone).
check: `plan/mtest.sh QuoteMarkerSourceTests`

### Q348 [auto] (done) MacMainThreadCostTests: a wall-clock budget in the gate fails under machine load
spec: -
needs: -
gate+: no
do: 2026-10-11 the gate went red on SkriftDesktopTests/MacMainThreadCostTests.testBacklinkedIDsOneCallPerRenderStaysUnderBudget: 204.66 ms against a 200 ms budget, while other xcodebuild jobs ran (the change under test, Q344, was phone-only). A wall-clock assertion in the per-merge gate fails on load, not on code. Turn it into a work-counter assertion (scans per call, like the D186 counter tests), or move the timing check to gate-full with a margin. This file is protected: propose the change and list it for Tuur's approval rather than editing it.
check: `./gate.sh`

### Q349 [tuur] (done) mockup: the notes list next to Apple Notes, phone and Mac
spec: D190 D193 C113
needs: -
do: One clickable HTML page, `Skrift_Native/SkriftDesktop/mocks/Q349-notes-list-apple.html`: for each width (phone, Mac sidebar) an Apple Notes reference panel beside the Skrift list drawn to D190: groups Today / Previous 7 Days / Previous 30 Days / then months; calmer, slightly bigger rows of title line, date + first line, folder line (pick what Skrift's "folder" is: Personal/Portfolio destination, or nothing); no Continue-listening card; search stays on top. Draw Apple Notes from public reference images only, never from Tuur's own Notes; label it as a reference, no Apple names or icons as Skrift branding (D193). Current Skrift parts drawn from source (C117). Name each pick that departs from Apple Notes and why (audio, rating, photos).
check: Tuur clicked through it and said go.

### Q350 [tuur] (done) mockup: the open note and its editing toolbar next to Apple Notes, phone and Mac
spec: D193 D115 C113 C234
needs: -
do: One clickable HTML page, `Skrift_Native/SkriftDesktop/mocks/Q350-note-editor-apple.html`: the open note on phone and Mac beside an Apple Notes reference panel (public reference images only, never Tuur's Notes; no Apple names or icons as branding). Draw D115: selection bar (bold, italic, underline, strikethrough) and an "Aa" menu (Title, Heading, Body, lists, checklists) over Skrift's dim-visible markdown marks; keep what Apple Notes lacks: audio + karaoke player, inline photo blocks (long-press drag, D112), capture quotes, speaker turns, Personal/Portfolio, polish, rating pill. Every C234 must-keep visible in at least one frame. No new toolbar buttons beyond what Apple Notes has (D181). Current Skrift parts drawn from source (C117).
check: Tuur clicked through it and said go.

### Q351 [tuur] (done) mockup: the article reader in Library, highlight to Add note
spec: D90 D126 D138 C229
needs: -
do: One clickable HTML page, `Skrift_Native/SkriftDesktop/mocks/Q351-article-reader.html`, extending `Q6-library-tab.html` (the Q6 mock says the article reader is not drawn): a shared article link lands on the Library shelf as an article tile; the reader shows clean reader-mode text (title, site, byline); select text → "Add note" opens the capture (quote + his voice) and the new note links back with `— *Title*, site` + URL (D138); a non-article link (video, tweet, product page) stays a note (D138). Phone only. Current parts drawn from source (C117).
check: Tuur clicked through it and said go.

### Q352 [auto] (done) the Books tab becomes Library: shelf and empty tab per the Q6 mock
spec: C229 D90 D128 D134 D135
needs: -
gate+: yes
do: Build the phone tab to `Skrift_Native/SkriftDesktop/mocks/Q6-library-tab.html` (signed, D134/D135): tab label "Library" (`AppTabView.swift`), the shelf of tiles where a tap plays/opens and the '❝ N' pill opens that source's notes, the empty tab's four doors (audiobook, podcast, ePub or PDF, article). Add an optional `kind` (book, episode, pdf, article; nil = book) to `Audiobook` INSIDE the existing synced carrier blob, so no CloudKit schema change; old entries decode as books. Doors for kinds not built yet open their importer once Q353-Q355 land; until then a door shows nothing dead (hide it). iPad shelf grid stays (C229). Phone test `LibraryShelfTests` (kind round-trips, nil decodes as book, empty state lists four doors). Screenshots of shelf + empty tab against the mock, LOOK, into `plan/reads/library-tab/`. FEATURES.md row.
check: `test $(ls plan/reads/library-tab/*.png | wc -l) -ge 2 && perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh LibraryShelfTests`

### Q353 [auto] (done) Library: podcast episodes from a link or RSS feed, with the episode player
spec: D90 D144 C229
needs: Q352
gate+: yes
do: Per D90 and the Q6 mock "Episode player" screen: a pasted or shared Apple Podcasts link resolves to the show's RSS feed via the iTunes lookup API; a Spotify link resolves via its oEmbed show name + iTunes search; a raw RSS URL is used as is. Parse the feed, pick the episode, download its MP3 enclosure into Library as kind `episode` (title, show, date, artwork). A show with no public feed is refused with one plain sentence (D14), never scraped. Playback reuses the book player and capture ("Add note") unchanged. Fixtures: a saved copy of the NRC Het Uur feed (`https://rss.art19.com/het-uur`) under test-fixtures/, no network in tests. Phone test `PodcastFeedTests` (feed parse, enclosure pick, Apple-link → feed URL, Spotify-exclusive refusal). Try the D144 links by hand once and note the result in the commit. Screenshot the episode player, LOOK, `plan/reads/library-tab/`. FEATURES.md row.
check: `perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh PodcastFeedTests`

### Q354 [auto] (done) Library: PDFs from the share sheet, a PDF reader, select to Add note
spec: D126 D135 D138 C229
needs: Q352
gate+: yes
do: Per D126 and the Q6 mock screens "Share a PDF from Mail" and "PDF reader": a PDF shared from another app becomes a Library source (kind `pdf`) with the toast "Added to Library · add to a note instead" (the second half turns it into a note attachment as today); the "+" inside a note still attaches a PDF to that note. A PDFKit reader with text selection opens from the tile and keeps the page; selecting text → "Add note" opens the capture (quote + his voice); the note carries source + page for the jump-back and exports `— *Title*, p. N` (D138). Phone test `LibraryPDFTests` (share routing, page persisted, capture carries page). Screenshots of toast + reader, LOOK, `plan/reads/library-tab/`. FEATURES.md row.
check: `perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh LibraryPDFTests`

### Q355 [auto] (done) Library: articles from a shared link, reader mode, highlight to Add note
spec: D90 D138 C229
needs: Q351 Q352
gate+: yes
do: Build to `Skrift_Native/SkriftDesktop/mocks/Q351-article-reader.html` (signed D195: the share sheet asks Article or Note; picking Note keeps it a note): a shared article link is fetched once, reader-mode text extracted and stored locally (kind `article`, title, site, byline, URL); non-article links stay notes (D138, the mock's rule). Reader shows the stored text offline; select → "Add note" opens the capture; the note links back and exports `— *Title*, site` + URL. Fixtures: two saved article HTML pages + one video page under test-fixtures/, no network in tests. Phone test `LibraryArticleTests` (extraction, article vs non-article routing, capture link-back). Screenshot the reader against the mock, LOOK, `plan/reads/library-tab/`. FEATURES.md row.
check: `perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh LibraryArticleTests`

### Q356 [auto] (done) Library hatches: Send to a note, Move to Library, jump-back on PDF and podcast notes
spec: D90 D127 D138 D177 C229
needs: Q353 Q354
gate+: yes
do: Per the Q6 mock screens "A capture note" and "A note with a PDF" and D138: "Send to a note" (⋯ and long-press on a tile) keeps the source on the shelf and opens a new note holding a link card that jumps back to it; "Move to Library" on a note with a PDF moves the PDF to the shelf and keeps his words as a linked note. The audiobook jump-back (`AudiobookSession.beginJumpBack(to:)`, Q151/Q273) also works from PDF capture notes (to the page) and podcast capture notes (to the time), not moving the source's own place (D177, absorbs Q297). Keep the '❝ N' capsule. Also from Q354: a PDF capture note labels and exports as a PDF quote (SourceKind case + frontmatter `source:`), not 'Audiobook quote'; the 'N notes from this PDF' row under the reader. Also from Q353: a podcast link shared from another app goes to Library (not a note), and the Q6 player's 'notes from this episode' row. Also from Q352: the Q6 mock's type-filter chips on the shelf (one per kind present), and the cover drawn as the mock draws it (title + author on the cover). Phone tests `LibraryHatchTests` + `JumpBackNonBookTests`. FEATURES.md rows.
check: `perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh LibraryHatchTests && perl -e 'alarm 900; exec @ARGV' plan/mtest.sh JumpBackNonBookTests`

### Q357 [auto] (done) delete the Continue-listening card and its code
spec: D190
needs: -
gate+: no
do: D190: the Continue-listening book banner on top of the notes list goes, and goes means deleted. Remove `SkriftMobile/Features/Audiobooks/ContinueListeningCard.swift`, both uses in `MemosListView.swift`, and anything only it used (state, strings, tests, xcodegen entries). The mini player bar while a book plays stays. Grep both apps and Shared for leftovers. FEATURES.md row updated.
check: `! grep -rq 'ContinueListening' Skrift_Native --include='*.swift' && perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh ListDerivedCacheTests`

### Q358 [auto] (done) build the notes list per the Q349 mock on phone, iPad and Mac
spec: D190 D193 C113
needs: Q349 Q357 Q361
gate+: yes
do: Build to `Skrift_Native/SkriftDesktop/mocks/Q349-notes-list-apple.html` (the signed version is the spec, not any review page): the D190 groups (Today / Previous 7 Days / Previous 30 Days / months), the calmer row (title, date + first line, folder line as signed), the type size, and D194's picks (no importance on rows; folder line for Portfolio only; one card per group; 16 / 14; pills only while something is happening; an unrated note shows a small grey dot + "Unrated" where importance used to sit, rated notes show nothing there), on phone, iPad and Mac from the shared list core (Shared first). Keep filters, search, locked, fading, rating behaviour and the Q315/Q361 caches and counter tests unchanged. Phone test `ListGroupingTests` (group boundaries at day/7/30/month edges, Europe/Lisbon midnight). Screenshots phone + Mac (`-snapshot`) against the mock, LOOK, `plan/reads/list-apple/`. FEATURES.md row.
check: `test $(ls plan/reads/list-apple/*.png | wc -l) -ge 2 && perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh ListGroupingTests && perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh ListDerivedCacheTests`

### Q359 [auto] (done) build the phone and iPad note and toolbar per the Q350 mock
spec: D193 D115 D112 C113 C234
needs: Q350
gate+: yes
do: Signed with D196's picks on top of the mock: title ABOVE the grey meta line; 'New person…' at the right end of the selection bar after the formatting items, Paste in its normal place; Export soft tint; 'Include audio in export' is a choice in the Export confirmation (per-note `Memo.includeAudioInExport`), not a header switch; 'Split speakers' in the top ⋯ menu. Build to `Skrift_Native/SkriftDesktop/mocks/Q350-note-editor-apple.html` on phone and iPad: the open note's look, the selection bar and "Aa" menu as signed, photo blocks moved by long-press drag between paragraphs (D112). Every C234 must-keep survives (inline pictures, capture-quote protection, speaker turns, `transcriptUserEdited`, save-now, polished-body editing, swipe-between-notes OFF). Keep the NoteOpenWork/SaveNoop counter tests green, never loosened (D186). Phone test `EditorFormattingTests` (each toolbar action writes the right markdown, photo move keeps the marker order). Screenshots against the mock, LOOK, `plan/reads/editor-apple/`. FEATURES.md row.
check: `test $(ls plan/reads/editor-apple/*.png | wc -l) -ge 2 && perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh EditorFormattingTests && perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh NoteOpenWorkTests`

### Q360 [auto] (done) build the Mac note and toolbar per the Q350 mock
spec: D193 D115 D112 C113 C234
needs: Q350 Q363
gate+: yes
do: Signed with D196's picks on top of the mock: title ABOVE the grey meta line; 'New person…' at the right end of the selection bar after the formatting items, Paste in its normal place; Export soft tint; 'Include audio in export' is a choice in the Export confirmation (per-note `Memo.includeAudioInExport`), not a header switch; 'Split speakers' in the top ⋯ menu. Build to `Skrift_Native/SkriftDesktop/mocks/Q350-note-editor-apple.html` on the Mac: the open note's look, the formatting controls as signed (Format menu shortcuts stay), photo blocks dragged between paragraphs (D112). The Mac note view stays an editor, WYSIWYG to the exported markdown (C234); every C234 must-keep survives. Keep the Q363 typing counter tests green, never loosened. New Mac test `MacEditorFormattingTests` in SkriftDesktopTests. `-snapshot` PNGs against the mock, LOOK, `plan/reads/editor-apple/mac-*.png`. Never run SkriftDesktopUITests. FEATURES.md row.
check: `test $(ls plan/reads/editor-apple/mac-*.png | wc -l) -ge 1 && grep -q 'func test' Skrift_Native/SkriftDesktop/SkriftDesktopTests/MacEditorFormattingTests.swift`

### Q361 [auto] (done) Mac perf: the sidebar derives its list once per change, not on every redraw
spec: D191 D186 C279
needs: -
gate+: yes
do: From plan/perf2/f-mac-ui.md M1 M2 M3 M9 M11 and h-shared-data.md S1 L1; re-check each against today's code first (`chipCounts` already goes through `NotesListModel`) and skip what is fixed. Mirror the phone's Q315: the sidebar's rows, chip counts, backlinked set, sort and snippets come from one cache rebuilt when the memo-set version changes, never per body pass or per meter/run tick; `WayOutRules.quietRows` reuses the cached backlinked set; `refreshCloudMemos` does not refetch every Memo on a filter change; search uses the shared precomputed lowercase text with a ~150 ms debounce; snippets are built once per memo version. New counter test `MacListWorkTests` in SkriftDesktopTests: a body pass with an unchanged memo set does no corpus scan; a search keystroke does not re-lowercase unchanged memos; results equal the uncached path on the corpus. Never run SkriftDesktopUITests.
check: `grep -q 'func test' Skrift_Native/SkriftDesktop/SkriftDesktopTests/MacListWorkTests.swift`

### Q362 [auto] (done) Mac perf: opening and playing a note does no whole-library work
spec: D191 D186
needs: -
gate+: yes
do: From plan/perf2/f-mac-ui.md M5 M7 M8 M12 M15 and h-shared-data.md N1 P2; re-check each against today's code first. Mirror the phone's Q314: Connections refresh reuses the shared backlink index and runs only when the panel is open; the fading line for an unrated note reads cached backlinks; `NamesStore` memoises names.json until it changes (both apps, Shared); `[[` link candidates and `TagLibrary.counts` come from a cache keyed on the memo-set version; during playback the 20 Hz tick reads a karaoke word map built once per note version, not `bestBodyText.split` per tick. New counter test `MacNoteOpenWorkTests` in SkriftDesktopTests: opening a note in a 2,000-note in-memory store does no full-corpus fetch; ten playback ticks build the word map once; names.json is decoded once across two opens. Never run SkriftDesktopUITests.
check: `grep -q 'func test' Skrift_Native/SkriftDesktop/SkriftDesktopTests/MacNoteOpenWorkTests.swift`

### Q363 [auto] (done) Mac perf: typing never saves the store per key or restyles the whole note
spec: D191 D186 C277
needs: -
gate+: yes
do: From plan/perf2/f-mac-ui.md M4 M6 M6b M13 M14; re-check each against today's code first. Title keystrokes stay local and commit on the same debounce as the body (one CloudKit save + one sidebar notification per pause, not per key); `BodyTextView.updateNSView` restyles only when its real inputs changed (no full restyle on every SwiftUI update) and never puts back older model text inside the 1 s debounce (M6b, the Q63 data-loss risk); `MacCloudEditSync.flush` runs its Sanitiser passes off the main actor; speaker spines compute turn rects only when the text or turns change. New counter test `MacTypingWorkTests` in SkriftDesktopTests: 20 title keystrokes cause at most one store save; an unrelated SwiftUI update does not restyle; an update inside the debounce keeps the typed text. Never run SkriftDesktopUITests.
check: `grep -q 'func test' Skrift_Native/SkriftDesktop/SkriftDesktopTests/MacTypingWorkTests.swift`

### Q364 [auto] (done) Mac perf: the reconcile sweep skips monologue blobs, stops scanning by id, ingests off the main thread
spec: D191 D186 C278 C281
needs: -
gate+: yes
do: From plan/perf2/g-mac-pipeline.md G1-G7 G11 G12, f-mac-ui.md M10 and h-shared-data.md M1-M3 X1; re-check each first. `adoptLateDiarization` and `adoptLateWordTimings` short-circuit for a note with nothing to adopt and never fault asset blobs; `MacMemoAuthor.backfill/reflectTranscripts` use one id→Memo dictionary per sweep instead of a fetch per row; new memos ingest on a background context in batches with one save; `MemoCloudUpdate.apply` skips the JSON re-serialise when the metadata is unchanged; the lifecycle sweep and the Connections snapshot reuse the reconcile's memo snapshot; `NoteActions.workInputs` is computed once per body. Keep every sync rule identical (C-contract: raw transcript in, LWW by `enhancedAt`). New counter test `MacReconcileWorkTests` in SkriftDesktopTests: a sweep over 2,000 already-ingested monologues fetches no blob and does O(1) Memo fetches; a second sweep with no change writes nothing. Never run SkriftDesktopUITests.
check: `grep -q 'func test' Skrift_Native/SkriftDesktop/SkriftDesktopTests/MacReconcileWorkTests.swift`

### Q365 [auto] (done) Mac perf: Process and export read the vault tags and the ledger once per run and skip unchanged files
spec: D191 D186
needs: -
gate+: yes
do: From plan/perf2/g-mac-pipeline.md G8 G9 G10 G13; re-check each first. The vault tag scan is cached across runs and refreshed by file modification dates (and no longer drops tags past 5,000 files); the export ledger and names.json are decoded once per run and the ledger written once at the end (crash-safe: per-note entries still land if the run dies, e.g. append then compact); photo/audio copies are skipped when the markdown and the ledger say the note is unchanged, before any full byte compare; `runProcess` filters with a Set. Exported bytes must be identical to today's on the corpus. New counter test `MacExportWorkTests` in SkriftDesktopTests: exporting 50 unchanged notes decodes the ledger once, writes it once, and reads no image bytes. Never run SkriftDesktopUITests.
check: `grep -q 'func test' Skrift_Native/SkriftDesktop/SkriftDesktopTests/MacExportWorkTests.swift`

### Q366 [auto] (done) release prep: version bump, Release builds of both apps, the synced-field list for Q298
spec: D186
needs: Q352 Q353 Q354 Q355 Q356 Q357 Q358 Q359 Q360 Q361 Q362 Q363 Q364 Q365 Q380 Q386
gate+: no
do: Write `plan/release/RELEASE.md`. Bump CFBundleVersion in both project.yml files. Build the phone Release archive config and the Mac Release (`-configuration Release -skipMacroValidation ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -derivedDataPath build-release`), string-grep a literal from Q357/Q358 in each product, record the paths. List every synced field and asset kind added since the installed prod build (diff the SwiftData `Memo`/`MemoAsset`/carrier models against the prod tag or commit; at least `Memo.includeAudioInExport` and MemoAsset kind `video`/`thumbnail`) with the CloudKit console steps for Q298. List the open device checks (Q17 Q63 Q64 Q272 Q280 Q281 Q302 Q304 Q309 Q311) for Tuur to clear or wave. Install nothing; never touch /Applications/Skrift.app or real data.
check: `grep -q 'includeAudioInExport' plan/release/RELEASE.md && grep -q 'build-release' plan/release/RELEASE.md`

### Q367 [auto] (done) Mac store copy-test: open a COPY of the prod Mac store with the new build, print counts only
spec: -
needs: Q366
gate+: no
do: `plan/release/mac-store-copytest.sh` for Tuur to run (agents never read real Skrift data): copies the prod Mac SwiftData store files (both the local and the CloudKit store, with -wal/-shm) to a fresh temp dir, opens the copy with the new build's model container and migrations (a small CLI target or a guarded launch argument that takes an explicit store path and refuses the real path), and prints only counts before and after: notes, enhancements, people, name decisions (Q252: the `@Attribute(originalName:)` rename keeps them), unlinked names; then exits non-zero on any drop. Never prints titles or text. Self-test against a synthetic store built from test-fixtures/corpus.
check: `plan/release/mac-store-copytest.sh --self-test`

### Q368 [tuur] (tuur) run the Mac upgrade test on a copy of your real Mac data
spec: -
needs: Q367
do: -
check: Tuur ran `plan/release/mac-store-copytest.sh` and the counts matched before and after.
ask: Quit Skrift, run `plan/release/mac-store-copytest.sh` in Terminal, and paste me the counts it prints (no note text is shown).

### Q369 [tuur] (tuur) perf re-run on phone and Mac before promotion (D186)
spec: D186 C282
needs: Q366
do: -
check: Phone and Mac flows re-recorded with `plan/perf2/tools/`; no D186 budget missed, or Tuur waved the miss.
ask: On the Dev build with the perf library, record the 7-minute flow on the iPhone 17 Pro and a short Mac flow in Instruments; I read them with flow.py.

### Q370 [tuur] (todo) update the real Skrift on the phone (and Mac) once Dev checks pass — no public release (D201)
spec: -
needs: Q443 Q298 Q368 Q369 Q17 Q63 Q64 Q302 Q304 Q309 Q311 Q375 Q388 Q389 Q393 Q397 Q398 Q399 Q400 Q401 Q408 Q409 Q410 Q411 Q412 Q413 Q414 Q415 Q416 Q417 Q418 Q419 Q420 Q421 Q422
do: -
check: The production Skrift on Tuur's phone runs build 188+ (literal grep matches the installed build), the prod Mac app likewise if he chose it, and his notes/names are intact after the upgrade.
ask: Dev checks pass. Ready to put the updated production Skrift on your phone (I install the Release build to the prod app over USB, you switch on the new synced fields in the iCloud console first — RELEASE.md), and the Mac's /Applications/Skrift.app too, or phone only for now?

### Q371 [tuur] (done) approve: LibraryShelfTests door assertions follow the built doors (podcast now, PDF after Q354)
spec: -
needs: -
do: -
check: Tuur approved; the conductor flips `testOnlyBuiltDoorsAreShown` (XCTAssertFalse(.podcast) → True, same for .pdf once Q354 lands) via plan/hand-merge.sh and `plan/mtest.sh LibraryShelfTests` passes.
ask: Q352 added a protected test saying the podcast and PDF doors stay hidden; Q353/Q354 built them. OK to flip those assertions so the test matches?

### Q372 [auto] (done) a Library 'send to a note' note exports as a link to its source, not a quote; Move to Library drops the note's PDF asset
spec: D138 D90
needs: -
gate+: yes
do: From Q356's report: a "Send to a note" / "Move to Library" note is capture metadata (`bookID` + `bookPosition`, PDF page as "p. N" in `bookChapter`) with no quote; `LibraryHatch.isSourceLink` tells it apart on the phone, but `SourceKind.classify` (Shared/Pipeline/SourceTaxonomy.swift) cannot see that, so the Mac card and the export still say Audiobook/PDF quote (`source: Audiobook-quote`) with no quote. Make the shared classifier recognise the source-link shape (one rule in Shared, used by phone, Mac and both exporters) and export it as a link line to the source (`— *Title*, p. N` / `— *Show*, mm:ss` per D138) with `source:` naming the source kind, never an empty quote block. And D90: "Move to Library" moves the PDF, so the note's CloudKit `document` MemoAsset is removed once the Library copy exists (never before; no data loss if the move fails midway). New tests: Mac `SourceLinkExportTests` in SkriftDesktopTests (classify + exported markdown for book, PDF and episode link notes), phone `LibraryHatchMoveTests` (asset removed only after the Library copy is written). Never run SkriftDesktopUITests. FEATURES.md rows.
check: `grep -q 'func test' Skrift_Native/SkriftDesktop/SkriftDesktopTests/SourceLinkExportTests.swift && perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh LibraryHatchMoveTests`

### Q373 [tuur] (done) decide: exported source spelling for Library link notes (Q372 picked PDF-link / Episode-link / Audiobook-link / Article-link)
spec: D138
needs: -
do: -
check: Tuur kept the spelling or named another; follow-up item added if changed.
ask: A note made with Library's "Send to a note" now exports `source: PDF-link` (or Episode-link, Audiobook-link, Article-link) and one line like `— *Title*, p. 4` above your words. Keep that spelling?

### Q374 [auto] (done) install today's Dev build on the iPhone 17 Pro and the Mac for the sitting
spec: -
needs: -
gate+: no
do: Bump CFBundleVersion in both project.yml files (plists are generated). Phone: Debug build for the iPhone 17 Pro (devicectl UDID 00008150-001658662223C01C; find its xcodebuild id with `xcrun xctrace list devices` — the xcodebuild id and the devicectl id differ), `-allowProvisioningUpdates DEVELOPMENT_TEAM=9W82X49JZS CODE_SIGN_STYLE=Automatic -derivedDataPath build-device`, `xcrun devicectl device install app`, then string-grep a Q356 literal (e.g. `LibraryTypeChips` symbol or a new copy string) inside the installed product's .debug.dylib to prove it is today's binary. Mac: Debug SkriftDesktop build with `-derivedDataPath build-dev -skipMacroValidation`, quit only 'Skrift Dev' (never prod Skrift), ditto to '/Applications/Skrift Dev.app', open it, grep a Q365 literal (`ExportSession`) in the installed binary. Never touch /Applications/Skrift.app or prod data. Phone locked or not connected → report BLOCKED with the exact devicectl error; still do the Mac. Commit the version bump.
check: Tuur's phone and Mac run the new Dev build (worker reports both grep hits).

### Q375 [tuur] (done) look: the Library tab on Dev — shelf, podcast link, PDF share + reader, send to a note, jump back
spec: C229 D90
needs: Q374
do: -
check: Tuur looked; anything off became an item.
ask: On the phone (Dev): open Library. Add a podcast by pasting an Apple or Spotify episode link; share a PDF from Mail or Files into Skrift; open it, select a sentence, Add note; then from a tile choose Send to a note and tap its card to jump back. Does it all feel right, and does the shelf look good?

### Q376 [tuur] (done) feel: the Mac on Dev after the five speed fixes (Q361-Q365)
spec: D191 D186
needs: Q374
do: -
check: Tuur used the Mac on Dev; slow spots became items.
ask: On the Mac (Skrift Dev, with the test notes filled in Settings): click through the list, search, open and play notes, type in a title and a body, switch apps and come back, run Process once. Anything still slow or behaving oddly?

### Q377 [auto] (done) list groups: add Yesterday; group by the recorded date (the Recorded/Added picker switches it)
spec: D197 D190
needs: -
gate+: yes
do: D197 on top of Q358's list (Shared/Model/MemoDate.swift `MemoDate.bucket`, Shared/UI/NotesListModel.swift, phone ListDerivedCache, Mac MacListDerivedCache): (1) add a Yesterday bucket between Today and Previous 7 Days (Europe/Lisbon calendar day); (2) sections group by the note's recorded date by default, or by its added date when the Recorded/Added date picker (Q105, C70) is on Added; within a section, newest of that same date first — an old note imported today lands in its real month. Same rule phone, iPad and Mac from the one shared bucket function. Extend ListGroupingTests (phone) and MacListWorkTests stays green (port only if needed, D163). Never run SkriftDesktopUITests.
check: `perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh ListGroupingTests && perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh ListDerivedCacheTests`

### Q378 [tuur] (done) mockup: iPad list + open note next to Apple Notes on iPad
spec: D193 D194 D196 D197
needs: -
do: One clickable HTML page `Skrift_Native/SkriftDesktop/mocks/Q378-ipad-apple.html`: Skrift on iPad (landscape 1376 x 1032 pt for iPad Pro 13", plus portrait) beside an Apple Notes iPad reference redrawn from Tuur's screenshot(s) in '/Users/tiurihartog/Downloads/apple notes ui/ipad/' at the same scale (two columns: list with Pinned/Today groups + open note; one toolbar pill Aa · checklist · table · attach · writing tools, then markup, share, ⋯, Search field). The Skrift side applies the signed picks: list per D194/D197 (Q349 mock), note per D196 (Q350 mock), Mac-style full Aa list (D197) since iPad has a hardware keyboard; keep Skrift's verbs (Import · Record · New) and tabs. Frames must be laid against the screenshot at the same scale before publishing (one agent on the file). Current Skrift parts from source (C117).
check: Tuur clicked through it and said go.

### Q379 [auto] (done) build the iPad list + note layout per the iPad mock
spec: D193
needs: Q378 Q358 Q359
gate+: yes
do: Signed per D198: note text full pane width (48 pt margins beside the list, 89 pt full screen); Apple's in-note attach menu (Scan Document, Take Photo or Video, Choose Photo or Video, Attach File; no Record Audio) under 'Add to this note'; tabs = option A, a slim glass control at the top of the list column; no folders column. Build to `Skrift_Native/SkriftDesktop/mocks/Q378-ipad-apple.html` (the signed version) on the iPad width of the universal phone target: list column + open note side by side, the toolbar as signed, the full Aa list (D197). Reuse Q358's shared list row and Q359's editor; iPad-only layout code only. Screenshots on the iPad simulator next to the mock frames at the same scale into plan/reads/ipad-apple/. Phone test `IPadLayoutTests` for the size-class switch.
check: `test $(ls plan/reads/ipad-apple/*.png | wc -l) -ge 2 && perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh IPadLayoutTests`

### Q380 [auto] (done) dead-code sweep after the rebuild: delete what Q352-Q379 left unused, Periphery on both apps
spec: -
needs: Q355 Q358 Q359 Q360 Q377 Q379
gate+: yes
do: Remove means delete (no hidden or kept-just-in-case code). Known leftovers from the workers' findings in plan/RUN.md: ChipFlow.swift + ChipLineBreakerTests + Snapshot.renderCardChips (Q358, row draws no chips); NoteCardModel fields balls/chips/quiet/quietLine kept only for parity tests (Q358) — move the parity tests onto the drawn fields and delete the dead ones; the old phone Aa grid / header chip views and the Mac header audio + split-speakers switches replaced by Q359/Q360; `.feedbackScreen("Books")` → "Library" with FeedbackQ341ScreenTagUITests (Q352); the Mac always-on status pill code (Q358). Then run Periphery 2.21.2 (~/bin, flags in plan/periphery.md) on SkriftMobile and the full SkriftDesktop scheme, and delete every finding introduced since 4519b3ea that is truly unused (keep Codable/synced fields with a why-comment, never delete a synced field). Protected tests: only ported or deleted with the code they covered (D163; list them as needs hand-merge). Update FEATURES.md rows that name deleted files. Write the before/after counts into plan/periphery.md. Then the twin pass (Tuur 2026-10-13: "keep code shared as much as possible… I don't want drift"; C239, feedback_shared_code_first): run `./plan/twin-check.sh --report` and read today's new phone/Mac pairs by hand too, because the checker only matches names. Known candidates: phone `applyMarkdownStyling` (NoteBodyView) vs Mac BodyTextView restyle — move WHICH ranges get dimmed/styled into one Shared function both text views consume; phone NoteFormatPanel vs Mac MacFormatPopover — one Shared table of Aa items (phone shows the D115 subset, Mac/iPad the full D197 list); phone vs Mac list-row sizes and the Unrated marker — one source in NoteCardStyle; the article/PDF/podcast source labels and link lines — SourceKind only. Also from Q382: the phone header uses NoteRatingPill with the fading line on its own line, while the Mac and quick note keep NoteRatingRow with the line beside the pill — make it one shared header row. Single-source each in Skrift_Native/Shared/ in this item; anything left on purpose carries `twin-ok: <reason>`. Re-baseline plan/twins.baseline only if the count went DOWN.
check: `! grep -rq 'ChipFlow\|renderCardChips' Skrift_Native --include='*.swift' && grep -q 'Q380\|2026-10' plan/periphery.md`

### Q381 [auto] (done) article reader + article note match the signed Q351 mock (Q355's difference list)
spec: D195 D138
needs: Q355
gate+: no
do: Q355 built the article reader; its compare (plan/reads/library-tab/q355-pair-*.png, q355-diff.md) against Skrift_Native/SkriftDesktop/mocks/Q351-article-reader.html lists: (1) DEFECT: an article capture note shows an empty audio player although it has no audio — hide the player when a note has no audio; (2) cover lacks the ARTICLE badge; (3) reader selection is purple, mock uses system blue; (4) no reading-progress line at the top of the reader; (5) a 'No notes yet' card is pinned over the reader text — show the notes row only when there are notes, never over the text; (6) the capture screen lacks the mock's quote card and the boxed link-back line; (7) the highlight lacks its ❝ glyph. Fix all seven; re-take the q355 pairs at 402 x 874 next to the mock and LOOK. Launch with `-skipOnboarding` on a fresh sim; `-showArticleNote` is the DEBUG hook for the note shot. The share-sheet Article/Note frame cannot be driven on iOS 27 (Safari share button not found by XCUITest) — leave it to Tuur's device check.
check: `test $(ls plan/reads/library-tab/q355-pair-*.png | wc -l) -ge 5 && perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh LibraryArticleTests`

### Q382 [auto] (done) phone note editor matches the signed Q350 mock: Q359's visual gaps
spec: D196 D193
needs: Q359
gate+: no
do: Q359's compare (plan/reads/editor-apple/phone-*.png vs Skrift_Native/SkriftDesktop/mocks/Q350-note-editor-apple.html at 402 x 874) left: rating pill ~36 pt tall vs mock 26 (balls larger) and the Personal chip ~30 vs 26; on an unrated note the rating + amber fading line + Personal wrap onto two rows (mock: one row); the mock keeps '‹ Notes' in the top bar while typing (phone shows only undo, redo, ⋯, Done); the reading player is a full-width dark ~50 pt capsule (mock: a narrower glass pill, 24 pt radius); the keyboard bar is full-width and flush (mock: a short floating white pill inset ~10 pt with a shadow); phone-7-speakers shows the list, not the opened conversation note. Fix each to the mock (the book quote keeps the locked borderless accent-bar idiom — do NOT add a tinted block, feedback_no_bubbles_on_shared_input). Take shots in LIGHT mode too so colours can be compared. Launch flags: `-seedPhotoMoveMemo`, `-skipOnboarding`.
check: `test $(ls plan/reads/editor-apple/phone-*.png | wc -l) -ge 7 && perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh EditorFormattingTests`

### Q383 [auto] (done) install Dev 187 (list, editors, iPad, article reader) on the iPhone 17 Pro and the Mac
spec: -
needs: -
gate+: no
do: Same recipe as Q374 (finding: phone device builds need `-skipMacroValidation -skipPackagePluginValidation`; iPhone 17 Pro xcodebuild id == devicectl id; binary greps need `/usr/bin/grep -a`). Bump CFBundleVersion in both project.yml files (plists are generated). Phone: Debug build for the iPhone 17 Pro (devicectl UDID 00008150-001658662223C01C; find its xcodebuild id with `xcrun xctrace list devices` — the xcodebuild id and the devicectl id differ), `-allowProvisioningUpdates DEVELOPMENT_TEAM=9W82X49JZS CODE_SIGN_STYLE=Automatic -derivedDataPath build-device`, `xcrun devicectl device install app`, then string-grep a Q379 literal (`IPadTabControl`) inside the installed product's .debug.dylib to prove it is today's binary. Mac: Debug SkriftDesktop build with `-derivedDataPath build-dev -skipMacroValidation`, quit only 'Skrift Dev' (never prod Skrift), ditto to '/Applications/Skrift Dev.app', open it, grep a Q360 literal (`MacExportConfirm`) in the installed binary. Never touch /Applications/Skrift.app or prod data. Phone locked or not connected → report BLOCKED with the exact devicectl error; still do the Mac. Commit the version bump.
check: Tuur's phone and Mac run Dev 187 (worker reports both grep hits).

### Q384 [tuur] (done) mockup: a video and a file inside a note, next to Apple Notes (phone, iPad, Mac)
spec: D199 D198 D126
needs: -
do: One clickable page `Skrift_Native/SkriftDesktop/mocks/Q384-note-attachments.html`: inside an open Skrift note (Q350/Q378 frames as signed), an inline video block (poster frame, play, duration; tap plays inline, full screen on expand) and a file card (icon, name, size; tap opens Quick Look), plus the existing photo and PDF blocks, on phone, iPad and Mac; long-press moves any block like a photo (D112). Apple Notes reference panels from Tuur's screenshots in '/Users/tiurihartog/Downloads/apple notes ui/attatchments/' (iPhone and Mac), laid at the same scale; the iPad frame is drawn from those plus the signed Q378 iPad layout (D200). One agent on the file.
check: Tuur clicked through it and said go.

### Q385 [auto] (done) build video + file attachments in notes per the mock (sync, export, phone/iPad/Mac)
spec: D199 D126
needs: Q384 Q379
gate+: yes
do: Signed per D202: inline video play (⤢ full screen); tall video cut at 420 pt on the phone; each attachment has a small/large switch, SMALL by default (per-attachment size is synced note state), plus 'Set All to Small' / 'Set All to Large' in the note's ⋯ menu; mock picks 4–8 kept. Build every attachment rule (markers, sizes, labels, export) in Skrift_Native/Shared/ once; app targets only draw. Build to `Skrift_Native/SkriftDesktop/mocks/Q384-note-attachments.html` (signed). Body v2 gets block markers for a video and a file like `[[img_NNN]]` (Shared, one rule both apps); they sync as MemoAsset kinds (`video` exists since Q287; add `file` with original name + UTI) — no new CloudKit record type; list any new synced field for the release's schema step (Q366 RELEASE.md). Attach menu items (Take/Choose Photo or Video, Attach File) insert them on phone/iPad; Mac adds them by drop/paste/Insert like photos (Q325). Export copies the file beside the note and links it (`![[file]]`), same ledger/ExportSession path as photos (Q365). Tests: phone `NoteAttachmentTests`, Mac `NoteAttachmentExportTests`. Never run SkriftDesktopUITests.
check: `grep -q 'func test' Skrift_Native/SkriftDesktop/SkriftDesktopTests/NoteAttachmentExportTests.swift && perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh NoteAttachmentTests`

### Q386 [auto] (done) dead-code sweep part 2: triage the Periphery scans, one shared note header row, SourceKind label twins
spec: -
needs: Q380
gate+: yes
do: Finish what Q380 left (its finding in plan/RUN.md). (a) Re-run Periphery 2.21.2 (~/bin, flags in plan/periphery.md) on a `git archive` snapshot in your scratch dir — inside a worktree Periphery refuses a second -derivedDataPath — for SkriftMobile and the full SkriftDesktop scheme; delete every finding in files changed since 4519b3ea that is truly unused (keep Codable/synced fields with a why-comment; never delete a synced field); write before/after counts into plan/periphery.md. (b) One shared note header row: the phone uses NoteRatingPill with the fading line on its own line (Q382) while the Mac and quick note use NoteRatingRow with the line beside the pill — make one Shared row both apps draw (phone layout from the signed Q350 mock wins). (c) Read the article/PDF/podcast/book source labels and link lines on both apps; anything not coming from SourceKind moves there. After each deletion run the FULL SkriftDesktop build too — the UnitTests bundle does not compile every file (Q380 broke EditConflictViews.swift that way). Protected tests only ported or deleted with their code (needs hand-merge list). Never run SkriftDesktopUITests.
check: `grep -q 'Q386\|part 2' plan/periphery.md && ./plan/twin-check.sh`

### Q387 [auto] (done) phone: hide the tab bar while a note is open (D200)
spec: D200
needs: -
gate+: yes
do: On the phone (compact width) the open note hides the tab bar (`.toolbar(.hidden, for: .tabBar)` on the note destination — Q382 confirmed it works); it comes back on the list. The edge-swipe back and '‹ Notes' (Q382's NoteBackButton + SwipeBackRestorer) return to the list. iPad unchanged. Quick note, Library player and share sheet unchanged. Phone UI test `NoteHidesTabBarUITests`: open a note → no tab bar; back → tab bar. Screenshot before/after into plan/reads/editor-apple/tabbar-*.png.
check: `test $(ls plan/reads/editor-apple/tabbar-*.png | wc -l) -ge 2`

### Q388 [auto] (done) Mac Release signs for the CloudKit Production environment (icloud-container-environment)
spec: D201
needs: -
gate+: no
do: plan/research/cloudkit-env-mac-release.md: a development-signed local Mac Release with no `com.apple.developer.icloud-container-environment` uses the CloudKit DEVELOPMENT environment; the installed prod /Applications/Skrift.app (Aug build) is signed exactly that way (codesign shows aps-environment development, get-task-allow, no environment key), while the phone prod is Ad Hoc/TestFlight = Production. Fix: add `com.apple.developer.icloud-container-environment` = `Production` to the Release SkriftDesktop entitlements file ONLY (Debug/Dev keeps its own container); keep the value literal (no $(VAR) — CLAUDE.md signing lesson). Rebuild Release into build-release (`-configuration Release -skipMacroValidation ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -derivedDataPath build-release`) and show the signed entitlements with `codesign -d --entitlements :-` on the built product (key present, Production). Install nothing. Note in plan/release/RELEASE.md: deploy the prod schema BEFORE installing this build, or Production writes fail; push delivery with aps-environment development is unverified.
check: `grep -q 'icloud-container-environment' Skrift_Native/SkriftDesktop/SkriftDesktop.entitlements`

### Q389 [tuur] (done) check: does the real Skrift on the Mac show the notes you recorded on your phone lately?
spec: D201
needs: -
do: -
check: Tuur answered; if the Mac misses phone notes, an item to merge the two CloudKit environments safely is added before Q370.
ask: Open the real Skrift on the Mac (not Dev). Do your newest phone notes from this month show up there? The prod Mac build is set up in a way that may sync to a different iCloud environment than your phone, so they might not.

### Q390 [auto] (done) shared-code + cleanliness review of the attachments build (Q385)
spec: D202 C239
needs: Q385 Q391
gate+: yes
do: A fresh agent reviews everything Q385 changed (`git diff` of its merge) for drift and mess, then fixes it: phone/iPad/Mac twins of attachment logic, labels or sizes → one Shared home; dead code left by the old `captureFileCard` and photo-only attach paths deleted (remove means delete); no new main-thread work on note open or list render (keep NoteOpenWorkTests / MacNoteOpenWorkTests / ListDerivedCacheTests / MacListWorkTests counters green, never loosened); FEATURES.md rows accurate. Run Periphery (flags in plan/periphery.md, on a `git archive` snapshot) for files Q385 touched and delete true dead code. Write a short review note into plan/reads/q385-review.md: what was shared, what was deleted, what stays on purpose (with `twin-ok:` reasons). Full SkriftDesktop build after each deletion. Never run SkriftDesktopUITests.
check: `test -s plan/reads/q385-review.md && ./plan/twin-check.sh`

### Q391 [auto] (done) attachments match the Q384 mock: screenshots + the gaps Q385 left
spec: D202 D199
needs: Q385
gate+: yes
do: Finish Q385 to the signed mock Skrift_Native/SkriftDesktop/mocks/Q384-note-attachments.html. (1) Posters: AVAssetImageGenerator runs synchronously on the main thread when a note with a large video renders — generate off-main and cache per asset (NoteOpenWorkTests/MacNoteOpenWorkTests stay green, never loosened). (2) Starting an inline video pauses the note's own audio player (mock pick 1). (3) Mac: video/file blocks drag between paragraphs like photos (Shared BodyFormat.moveBlock exists). (4) Hold menu items as the mock: Copy, Share, Save, Delete plus View as Small/Large and move. (5) DEBUG `-seedAttachmentMemo` in DemoDataSeeder (text + [[vid_001]] large with a short AVAssetWriter .mov, [[img_001]], [[file_001]] a DXF, [[file_002]] a PDF), a phone screenshot UI test (`-skipOnboarding -routeViaList -appTheme light`) and a Mac `-snapshot-attachments` route; lay every shot next to the matching mock frame at the same scale into plan/reads/attachments/ and LOOK; fix differences. Never run SkriftDesktopUITests.
check: `test $(ls plan/reads/attachments/*.png | wc -l) -ge 4 && perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh NoteAttachmentTests`

### Q392 [auto] (done) attachments follow-ups from the Q390 review: Mac grey file card, one picker chain, Save on the captured PDF
spec: D202
needs: Q390
gate+: no
do: From plan/reads/q385-review.md: (1) the Mac capture card `CaptureViews.fileCard` still has its own purple Open button — replace it with the shared grey card from Shared/UI/NoteAttachmentArt.swift (whole card opens Quick Look), as the phone now does (D202 pick 4); (2) the phone page and the iPad toolbar each chain the same three pickers (camera, library, files) — one shared intake (NoteAttachIntake) both call; (3) the captured PDF's context menu lacks Save — add it from the shared hold-menu list. Mac `-snapshot` + phone shot of the file card next to the Q384 mock frame; LOOK. Never run SkriftDesktopUITests.
check: `! grep -q 'captureFileCard' -r Skrift_Native --include='*.swift' && perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh NoteAttachmentTests`

### Q393 [auto] (done) plan (no execution): bring the prod Mac's Development-iCloud data into Production safely
spec: D201
needs: -
gate+: no
do: Facts (Tuur 2026-10-13, Q389): the real Skrift on the Mac shows phone notes only up to 25/26 Sep 2026; the phone's newest is Sun 11 Oct; he switched to the iPhone 17 Pro around 1 Oct. The prod Mac app (Aug, e6245caa) is development-signed with no icloud-container-environment → CloudKit DEVELOPMENT of iCloud.com.skrift.mobile; the new phone's prod build is TestFlight/App-Store-signed → PRODUCTION. So since ~late Sep the phone writes Production and the Mac writes Development. Write plan/release/ICLOUD_MERGE.md: what lives where (phone local store + Production; Mac local store + Development: Mac-made notes, MemoEnhancement polish, names/vocab edits since 25 Sep), and the safest way to end with ONE Production copy and zero loss or duplicates — e.g. what NSPersistentCloudKitContainer/SwiftData does when the same local store is opened under a different environment (re-upload? metadata reset? — research with sources, plan/research/), how ids dedupe (Memo.id UUIDs, MemoDeduper, NamesMerge LWW union), MemoEnhancement LWW by enhancedAt, a dry run on a COPY first (extend plan/release/mac-store-copytest.sh if needed), and the exact steps Tuur does vs the agent. NEVER read his real data; no CloudKit writes; code reading + research only.
check: `test -s plan/release/ICLOUD_MERGE.md`

### Q394 [auto] (done) install Dev 189 (attachments, Q385-Q392) on the iPhone 17 Pro and the Mac
spec: -
needs: Q392
gate+: no
do: Same recipe as Q383 (findings Q374/Q383: phone builds need `-skipMacroValidation -skipPackagePluginValidation`; xcodebuild id == devicectl id 00008150-001658662223C01C; grep the .debug.dylib with `/usr/bin/grep -a` and a 16+ byte literal). Bump CFBundleVersion to 189 in both project.yml files (188 is the Release build). Phone Debug → devicectl install com.skrift.mobile.dev, grep `Add to this note` in SkriftMobile.debug.dylib; Mac Debug → quit 'Skrift Dev' by exact name, ditto to /Applications/Skrift Dev.app, open, grep `Set All to Large` in 'Skrift Dev.debug.dylib'. Never touch /Applications/Skrift.app or prod data. Commit the bump.
check: Tuur's phone and Mac run Dev 189 (worker reports both grep hits).

### Q395 [auto] (done) Personal/Portfolio pill: tap toggles in place like the rating pill, no menu (D204)
spec: D204 D189
needs: -
gate+: yes
do: The shared destination control (Shared/UI/DestinationRowView.swift + the Shared NoteRatingRow trailing slot, Q386) becomes a tap pill: one tap flips Personal ⇄ Portfolio in place, same look and hit area as NoteRatingPill (Q85), no Menu/dropdown/sheet, no list re-layout while choosing. Writes the same synced field as today (NoteDestination; Portfolio keeps its folder/_inbox rules, D189). One shared view for phone, iPad, Mac, quick note and share sheet; delete the menu code (remove means delete). Tests: Mac `DestinationPillTests` in SkriftDesktopTests (tap flips value; no menu path left). Phone + Mac shots of the header before/after into plan/reads/destination-pill/. Never run SkriftDesktopUITests.
check: `test $(ls plan/reads/destination-pill/*.png | wc -l) -ge 2 && grep -q 'func test' Skrift_Native/SkriftDesktop/SkriftDesktopTests/DestinationPillTests.swift`

### Q396 [auto] (done) file card kind label: one extension→label table in Shared (same words on phone and Mac)
spec: D202 C239
needs: Q392
gate+: yes
do: NoteAttachment.kindLabel (Shared/Pipeline/NoteAttachment.swift) uses the system UTType description, so one DXF reads 'DXF · 4 KB' on the Mac, 'DXF file · 4 KB' on the phone and 'DXF drawing' in the Q384 mock. Replace it with one fixed extension→label table in Shared (common office, image, audio, video, archive, CAD and 3D-print types; unknown → uppercase extension + ' file'), so every device says the same words. Mac test `NoteAttachmentKindLabelTests` in SkriftDesktopTests.
check: `grep -q 'func test' Skrift_Native/SkriftDesktop/SkriftDesktopTests/NoteAttachmentKindLabelTests.swift`

### Q397 [auto] (done) Mac backfill guard: author Memos only for local captures, only after the first full CloudKit import (ICLOUD_MERGE A1)
spec: D203
needs: Q393
gate+: yes
do: MacMemoAuthor.backfill (run on every reconcile from MemoCloudReconciler) authors a Memo for every PipelineFile with a UUID id and no Memo, never checking isLocalCapture — on a fresh Production store it would upload a twin of every phone note. Guard: only rows that are Mac local captures, and only after the first full CloudKit import has finished (persisted flag set from the mirroring delegate's import-complete event). Mac test `BackfillGuardTests` in SkriftDesktopTests (fresh store + phone-made rows → zero authored; local capture after import → authored once). See plan/release/ICLOUD_MERGE.md (Q393) for the full plan and section numbers; read it first. NEVER read the user's real data or touch CloudKit; tests and copies only. Never run SkriftDesktopUITests.
check: `grep -q 'func test' Skrift_Native/SkriftDesktop/SkriftDesktopTests/BackfillGuardTests.swift`

### Q398 [auto] (done) DevEraMerge engine: id-based merge of the Aug Mac store into Production, batches of 25 (ICLOUD_MERGE A2)
spec: D203
needs: Q397
gate+: yes
do: Build the engine ICLOUD_MERGE.md §A2 describes: reads a moved-out old memo_cloud.store (merge-from-dev/) read-only, merges into the live Production store by Memo.id in batches of 25 with the rules in §7 (shared notes keep Production; Mac field edits copied only when Production is unchanged since S=2026-09-25; insert Mac-made notes and phone notes recorded after S; never insert phone notes recorded before S, >20 such stops; MemoEnhancement newer enhancedAt wins in place), writes merge-report.txt (inserted ids) and supports unmerge. Confirm from e6245caa code that every Mac write bumps lastEditedAt. Mac tests `DevEraMergeTests` on synthetic stores. See plan/release/ICLOUD_MERGE.md (Q393) for the full plan and section numbers; read it first. NEVER read the user's real data or touch CloudKit; tests and copies only. Never run SkriftDesktopUITests.
check: `grep -q 'func test' Skrift_Native/SkriftDesktop/SkriftDesktopTests/DevEraMergeTests.swift`

### Q399 [auto] (done) merge dry run: StoreCopyTest --merge-dry-run + mac-store-copytest.sh --merge on copies (ICLOUD_MERGE A3)
spec: D203
needs: Q398
gate+: yes
do: Extend the Q367 tool: `StoreCopyTest --merge-dry-run` runs DevEraMerge on COPIES of the old store and a downloaded Production store and prints only counts (before/after, duplicate Memo.id groups, Mac-made notes present once with assets, enhancement LWW outcomes, conflicts, any drop → non-zero exit); `plan/release/mac-store-copytest.sh --merge` wires it for Tuur. Self-test on synthetic stores. See plan/release/ICLOUD_MERGE.md (Q393) for the full plan and section numbers; read it first. NEVER read the user's real data or touch CloudKit; tests and copies only. Never run SkriftDesktopUITests.
check: `plan/release/mac-store-copytest.sh --self-test`

### Q400 [auto] (done) one-shot merge alert in the Release Mac app, triggered by a merge-from-dev/ folder (ICLOUD_MERGE A4)
spec: D203
needs: Q398
gate+: yes
do: Per ICLOUD_MERGE.md §A4: when the Release Mac app finds ~/Library/Application Support/Skrift/merge-from-dev/ and the first Production import is done, it shows one alert with the dry-run numbers and Yes/Not now; Yes runs DevEraMerge, writes merge-report.txt, renames the folder to merged-<date>/. Never automatic. Mac test `MergeAlertTests` (folder present + import done → alert once; absent → never). Snapshot of the alert. See plan/release/ICLOUD_MERGE.md (Q393) for the full plan and section numbers; read it first. NEVER read the user's real data or touch CloudKit; tests and copies only. Never run SkriftDesktopUITests.
check: `grep -q 'func test' Skrift_Native/SkriftDesktop/SkriftDesktopTests/MergeAlertTests.swift`

### Q401 [tuur] (done) question: how did the iPhone 17 Pro get your notes — Quick Start/device transfer, an iCloud backup restore, or a fresh install that downloaded them?
spec: D203
needs: -
do: -
check: Tuur answered (ICLOUD_MERGE F2).
ask: When you moved to the iPhone 17 Pro around 1 October: did you use Quick Start / phone-to-phone transfer, restore from an iCloud backup, or install Skrift fresh and let it download? Did your old notes appear on the new phone right away?

### Q402 [auto] (done) Portfolio adds no tags by itself; idea/inspiration/project become suggestions to pick one (D205)
spec: D205 D189
needs: -
gate+: yes
do: Today choosing Portfolio (the Q395 tap pill) adds all three preset tags idea/inspiration/project to the note. Change: flipping to Portfolio adds NO tags; the tag row shows the three as quiet suggestion chips (the existing tag-suggestion look) only while the note is Portfolio and has none of them; tapping one adds just that tag; flipping back to Personal removes nothing the user added. One shared rule in Skrift_Native/Shared/ (phone, iPad, Mac, quick note). Mac test `PortfolioPresetTests` in SkriftDesktopTests (flip adds none; tap adds one; flip back keeps tags). Phone + Mac shots into plan/reads/destination-pill/portfolio-*.png. Never run SkriftDesktopUITests.
check: `grep -q 'func test' Skrift_Native/SkriftDesktop/SkriftDesktopTests/PortfolioPresetTests.swift`

### Q403 [auto] (done) Library shelf: Continue row, mini player, type badge on every cover (D207, Q6 mock)
spec: D207 C229
needs: -
gate+: yes
do: Build to the signed Skrift_Native/SkriftDesktop/mocks/Q6-library-tab.html 'Library' screen, using plan/reads/library-tab/compare-q6-lib.png (mock left, app right) as the gap list: (1) the 'Continue' row above the chips — the last few sources you played/opened (any kind), horizontally scrolling cards with cover, kind label, title, progress and time/pages left, tap resumes; (2) the mini player docked above the tab bar while a book/episode plays (cover, back 15, play/pause, forward 15, 'Add note') — reuse the existing AudiobookMiniPlayerBar if it exists, don't write a second player; (3) a type badge (AUDIOBOOK, EPISODE, ARTICLE, PDF) on every cover kind. Keep the author line under tile titles and the iOS 26 floating glass tab bar (D207). Shared code first (labels from SourceKind). Phone test `LibraryContinueRowTests` (order = most recently played/opened, kinds mixed, finished sources drop out). Shot next to the mock at 402 x 874 into plan/reads/library-tab/q403-*.png; LOOK.
check: `test $(ls plan/reads/library-tab/q403-*.png | wc -l) -ge 1 && perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh LibraryContinueRowTests`

### Q404 [auto] (done) PDF reader: reflowed reading view from the text layer, real page one tap away; Highlight in PDF + article selection menus (D207)
spec: D207 D126
needs: -
gate+: yes
do: Build to the signed Q6 mock 'PDF reader' screen (plan/reads/library-tab/compare-q6-reader.png shows the gap): when a PDF has a usable text layer (PDFKit page strings; the existing PDFTextExtract), the reader shows a reflowed reading view — the page's text in the reader font and size (same Aa settings as the article reader), headings and paragraphs kept, simple two-column tables as rows, page breaks marked 'Page N' — with an 'Original page' toggle back to the PDFKit page (remembered per PDF). No text layer or a poor extraction (heuristic: too few words/page, garbled ratio) → the real page only, no toggle. Selection in the reading view → the same Copy · Highlight · Add note menu; capture still carries source + page (Q354). Add Highlight to both menus (PDF + article): a highlight is a stored range on the source (no note) drawn as the mock's yellow, removable from its own menu, synced inside the Library item's blob. Shared text-shaping rules in Skrift_Native/Shared/. Phone tests `PDFReflowTests` (reflow keeps order and page markers; scanned PDF → no toggle) + `SourceHighlightTests`. Shots next to the mock into plan/reads/library-tab/q404-*.png.
check: `test $(ls plan/reads/library-tab/q404-*.png | wc -l) -ge 1 && perl -e 'alarm 1800; exec @ARGV' plan/mtest.sh PDFReflowTests`

### Q405 [auto] (done) capture screen: 'Record your thoughts' button in plain solid accent, no purple gradient (D207)
spec: D207
needs: -
gate+: no
do: Tuur 2026-10-14: the 'Record your thoughts' button (capture screen: book quote, PDF and article capture — MergedCaptureView and the text-capture sheet) is 'an ugly color'. Make it the app's plain solid accent fill like the other primary buttons (no gradient), same shape and size, white label + mic glyph; one shared style used by every capture screen. Only this button — the capture-screen design pause (CLAUDE.md) still holds for everything else. Before/after shots into plan/reads/library-tab/q405-*.png.
check: `test $(ls plan/reads/library-tab/q405-*.png | wc -l) -ge 2`

### Q406 [auto] (done) player: 15/15 skips, purple play button without glow; confirm the controls tuck away while playing (D208)
spec: D208
needs: -
gate+: no
do: In the one book/episode player (AudiobookPlayerView and the mini player): back skip 15 s and forward skip 15 s (was 15/30), icons to match; the play/pause button keeps the purple fill but drops its glow/shadow; keep the small header and the text space as they are. Check in code whether the reading-mode controls already hide while playing and come back on a tap/pull (the audiobook-player-reading-mode work, 2026-06-19); report yes/no with file:line — do not build it if missing, just report. Shot of the player before/after into plan/reads/library-tab/q406-*.png (`-openTab books -seedEpisode -showPlayer -appTheme light -skipOnboarding`).
check: `test $(ls plan/reads/library-tab/q406-*.png | wc -l) -ge 2`

### Q407 [auto] (done) install Dev 190 (Library shelf, PDF reading view, Highlight, tap pill, Portfolio fix, player) on the iPhone 17 Pro and the Mac
spec: -
needs: -
gate+: no
do: Same recipe as Q394 (findings Q374/Q383/Q394: phone builds need `-skipMacroValidation -skipPackagePluginValidation`; xcodebuild id == devicectl id 00008150-001658662223C01C; grep the .debug.dylib with `/usr/bin/grep -a` and a 16+ byte literal; quit 'Skrift Dev' via osascript in a script file). Bump to 190 in both project.yml files (SKRIFT_BUILD / CURRENT_PROJECT_VERSION). Phone: Debug → devicectl install com.skrift.mobile.dev; grep `Original page` or `Reading view` in SkriftMobile.debug.dylib; confirm with `xcrun devicectl device info apps --bundle-id com.skrift.mobile.dev` showing 190. Mac: Debug → quit Skrift Dev, ditto to /Applications/Skrift Dev.app, open; grep a Q402/Q395 literal (e.g. `PortfolioTagPresets`) in 'Skrift Dev.debug.dylib'. Never touch /Applications/Skrift.app or prod data. If the phone is unavailable, install the Mac anyway and report the exact devicectl error.
check: Tuur's phone and Mac run Dev 190 (worker reports both grep hits and the devicectl build number).

### Q408 [auto] (done) an edit that empties a note never lands silently
spec: C261 R70
needs: -
gate+: yes
do: Today (2026-10-14 read): no such guard exists; the only destructive confirm in Shared is `Shared/Naming/NameDeleteConfirm.swift` (reuse its style). When an editor commit would turn a non-empty raw transcript or the Mac's polished copy into empty text (phone, iPad and Mac editors), show a confirm in the existing destructive-confirm style (as C262/C266 shipped); Cancel keeps the prior text. The "nets to empty" decision is one function in `Skrift_Native/Shared/`. Test `EmptyCommitGuardTests` (desktop target) covers both fields (`editor-clear-raw`, `editor-clear-polished`).
check: `grep -rqE "class EmptyCommitGuardTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q409 [auto] (done) a .transcribing note orphaned on a gone device is adopted
spec: C264 C154 C97 C263 R75
needs: -
gate+: yes
do: Today: `MemoSaver.swift` `ownsForRecovery` re-runs only this device's memos; the C263 user-edited skip already exists there; the Mac has no `.transcribing` sweep. A memo left in `.transcribing` by another device is taken over after 30 minutes when its audio blob is present (C154), on the phone and by the Mac sweep as the backstop. Younger than 30 minutes stays untouched (C97); a `transcriptUserEdited` memo is never re-transcribed (C263). The age rule is one shared function in `Skrift_Native/Shared/`. Test `OrphanedTranscribingTests` (desktop target): a 31-minute orphan with audio is adopted, a 5-minute one and a user-edited one are not.
check: `grep -rqE "class OrphanedTranscribingTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q410 [auto] (done) a word-list edit merges with the latest synced list at write time
spec: C267 C103 R80
needs: -
gate+: yes
do: Today: `VocabularyCloudSync.swift` calls `VocabularySyncCore.reconcile` (whole-list LWW); the additive union runs only once as a migration. Custom vocabulary saves re-read the latest synced state immediately before writing and merge additively (phone and Mac, `VocabularyCloudSync` and the phone's twin), instead of saving the snapshot loaded when the screen opened. A removal on one device still removes. Test `VocabConcurrentAddTests` (desktop target): two devices each add a word offline, both words survive the sync.
check: `grep -rqE "class VocabConcurrentAddTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q411 [auto] (done) removing a book's download waits for its iCloud upload
spec: C268 R81
needs: -
gate+: yes
do: Today: `AudiobookCloudSync.removeDownload` deletes files once the book is synced, without checking the upload finished; the buttons in `SyncedAudiobooksView` and `AudiobookLibraryView` are never disabled. On the phone, Remove download is disabled with a "Still uploading to iCloud" line in the existing secondary-text style until `AudiobookCloudSync` reports the book's upload complete; no code path frees the local file before that. Test `RemoveDownloadUploadGateTests` (phone target).
check: `plan/mtest.sh RemoveDownloadUploadGateTests`

### Q412 [auto] (done) removing a bookmark removes the nearest one and says so
spec: C269 R82
needs: -
gate+: yes
do: Today: `AudiobookPlayerView` removes every bookmark in the tapped line's span and toasts "Unfolded"; the swipe delete in `ChaptersBookmarksSheet` shows nothing. Every bookmark removal path on the phone (player tap, swipe in the bookmarks sheet) removes exactly the one bookmark nearest the tap, breaks a tie by the earlier one, and shows a "Removed 1 bookmark at <time>" notice with Undo in the existing toast style. Test `BookmarkRemovalTests` (phone target): `bookmark-delete-near-tie` removes one, `bookmark-swipe-no-confirm` shows the notice.
check: `plan/mtest.sh BookmarkRemovalTests`

### Q413 [auto] (done) a shared-book import re-checks the library right before unpacking
spec: C270 R83
needs: -
gate+: yes
do: Today: `alreadyImported` is checked only at offer (`BookImportBridge.swift`); `BookImportSheet.unpack()` and `BookBundle.unpack` do not re-check. `BookImportBridge` checks `alreadyImported` again immediately before it unpacks a `.skriftbook`, not only when it offers the import; a book that arrived in between is never overwritten. Test `BookImportRecheckTests` (phone target): the same book imported between offer and unpack yields one library entry and its files unchanged.
check: `plan/mtest.sh BookImportRecheckTests`

### Q414 [auto] (done) a capture-inbox entry is deleted only after its note is saved
spec: C271 C147 R84
needs: -
gate+: yes
do: Today: notes and files already delete the entry after insert+save with an id dedup; the video, audio and podcast-URL branches of `CaptureInboxDrainer` still delete it before importing. Fix those three. `CaptureInboxDrainer` deletes an inbox entry only after the memo it produced is saved; a failed import leaves the entry for the next drain, and a re-drain is idempotent (memo id from the entry, so no duplicate note). Applies to every capture type. Test `CaptureInboxRetryTests` (phone target): an import that throws keeps the entry; the next drain makes exactly one note.
check: `plan/mtest.sh CaptureInboxRetryTests`

### Q415 [auto] (done) a failed reprint keeps the note's printedAt
spec: C272 R85
needs: -
gate+: yes
do: Today: `WallPrinter.printCard` calls `ledger.removeValue` before printing. `WallPrinter` writes the new `printedAt` only after the reprint succeeds; a failed or cancelled reprint leaves the previous stamp as it was. Test `WallReprintStampTests` (phone target).
check: `plan/mtest.sh WallReprintStampTests`

### Q416 [auto] (done) Markup keeps the original photo recoverable
spec: C273 R86
needs: -
gate+: yes
do: Today: `MarkupQuickLook` edits in place with `.updateContents`; no original is kept. Before `MarkupQuickLook` presents `.updateContents`, the untouched photo is kept as a second `MemoAsset` blob (additive, synced, C96); the photo's menu offers "Revert to original" as a plain menu item. Only the first markup saves the original; later markups keep it. Test `MarkupOriginalTests` (phone target): markup then revert gives back the original bytes.
check: `plan/mtest.sh MarkupOriginalTests`

### Q417 [auto] (done) a capture whose transcription is empty is kept and says so
spec: C274 R87
needs: -
gate+: yes
do: Today: `CaptureVoiceAnnotate.swift` deletes the audio and fires the success haptic when the transcript is empty. A voice annotation or capture whose transcription returns no text stays in the note with a "No words heard" line in the existing secondary-text style until he saves or discards it; the success haptic never deletes it. Test `EmptyTranscriptKeptTests` (phone target): `voice-annotation-empty-transcript-kept`.
check: `plan/mtest.sh EmptyTranscriptKeptTests`

### Q418 [auto] (done) same full name is the same person: merge and say so
spec: C254 R62
needs: -
gate+: yes
do: Today: only `NamesStore.upsert` merges by name (case-insensitive) and it replaces voiceprints instead of unioning; the sync merge `NamesData.mergeByCanonical` keys on the exact canonical, so case variants never merge. Adding a person whose full name matches an existing one, case-insensitively, merges into that row (aliases and voiceprints unioned) on every add path: Settings on both apps, the sync merge in `NamesData`, the speaker assign sheet. The UI shows "Merged into <name>" in the existing toast style. Add corpus fixture `roster-duplicate-canonical`. Test `RosterDuplicateMergeTests` (desktop target): one row, notice raised. `names.json` stays byte-compatible across apps.
check: `grep -rqE "class RosterDuplicateMergeTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q419 [auto] (done) name matching: Dutch bare possessive, diacritics, tags never split
spec: C255 C256 C260 R69 R68 R65
needs: -
gate+: yes
do: Today: `Sanitiser.swift` handles only `'s` / `’s`; no diacritic folding; the `\b` boundary does not protect `#tags`. In the shared matcher (`Skrift_Native/Shared/Naming/`): an alias plus a bare `s` (`Wims`, `Lottes`) links like `Wim's`, unless that word is itself a roster alias; matching folds diacritics both ways (Ines/Inés, Månsson/Mansson); a `#tag` is never split or linked even when it equals an alias. Add corpus fixtures `edge-name-dutch-possessive`, `edge-name-diacritics`, `edge-name-is-tag`. Test `NameMatcherEdgeTests` (desktop target).
check: `grep -rqE "class NameMatcherEdgeTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q420 [auto] (done) naming an unknown speaker seeds the alias
spec: C257 R66
needs: -
gate+: yes
do: Today: the phone uses `PersonEditCore.createIfNeeded` (`SpeakerAssignSheet`), the Mac its own inline upsert in `ProcessingCoordinator`; `NamesStore.addVoiceEmbedding` can also create a person with `aliases: []` (e.g. from `VoiceEnroller.enroll`) — close that path too. Naming a speaker with a name not on the roster creates the person with that typed name as an alias, or opens the person editor; an alias-less person is never created. Same rule on phone and Mac, in one shared function. Add corpus fixture `edge-speaker-assign-new-name`. Test `SpeakerAssignNewNameTests` (desktop target): the new person has at least one alias.
check: `grep -rqE "class SpeakerAssignNewNameTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q421 [auto] (done) a synced roster change re-derives the open note at once
spec: C258
needs: -
gate+: yes
do: Today: only the Settings/names screens observe `.namesDidChangeFromSync`; no open-note view does. When a roster change arrives by sync while a note is open (phone, iPad, Mac), that note's name spans are re-derived immediately, not on the next open. Test `OpenNoteRosterRefreshTests` (desktop target): an open note's model re-derives after a simulated synced rename.
check: `grep -rqE "class OpenNoteRosterRefreshTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q422 [auto] (done) a deleted person's voiceprints go with the tombstone
spec: C259 C208 R63
needs: -
gate+: yes
do: Today: a new tombstone already drops its voiceprints, but `NamesData.mergeByCanonical` unions voiceprints onto the winner even when it is a tombstone, and `NamesStore.addVoiceEmbedding` sets `deleted = nil` (revives a tombstone). Fix both. Deleting a person drops its voiceprints in the tombstone; the `NamesMerge` LWW merge never unions embeddings onto a tombstone. Add corpus fixture `roster-delete-with-voiceprint`. Test `RosterTombstoneVoiceprintTests` (desktop target).
check: `grep -rqE "class RosterTombstoneVoiceprintTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q423 [auto] (done) copy-edit harness: recorded model outputs, v1 goldens, tests for C30 C35 C40
spec: C253 C5 C7 C30 C35 C40 C286 C166
needs: -
gate+: yes
do: Record v1 copy-edit for every corpus note with the MLX build on a scratch store seeded by `-corpus` (never the live Dev store; quit Dev first, C166). Store each model call's output as `test-fixtures/corpus/goldens/model/<sha256(prompt+input)>.txt` (C7, C286) and v1's shipped body, title and summary as `test-fixtures/corpus/goldens/v1-copyedit/<slug>.txt`. `CopyEditDiffHarnessTests` (MLX-free, desktop target) replays the recorded outputs through each registered engine and classes identical / expected-different / unexplained (C5); a cache miss fails and prints its key. Pin C30 (`pic-wall`, `pic-three-spread`: each picture returns after the same-index paragraph; v1 registered expected-different, R3), C35 (every number, name and non-filler word of `voice-en-pricing-ramble` and `voice-mix-code-switch` survives), C40 (Process on an unrated note floors it to 0.1).
check: `test $(ls test-fixtures/corpus/goldens/v1-copyedit | wc -l) -ge 100 && grep -rqE "class CopyEditDiffHarnessTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q424 [auto] (done) copy-edit v2 beside v1
spec: C28 C29 C30 C31 C32 C33 C34 C36 C37 C38 C39 C177 C178 C285 C2 C3
needs: Q423
gate+: yes
do: Write copy-edit v2 in `Skrift_Native/Shared/CopyEditV2/`: escrow (C29), pictures back by paragraph index with the 6-word anchor code unused (C30), lost link or changed quote byte ships unedited (C31), token budget and truncation (C32), shrink guard (C33), paragraph ledger and the spoken-wall break (C34), title / summary / share / conversation rules (C36), one `MemoEnhancement` per pass (C37), post-conditions (C177), tail order tags → name-link → compile (C178), one prompt source (C39). Register it in the Q423 harness; the app keeps calling v1 (C2). At most 1,070 lines (40% of 2,674, C3). Write `plan/reads/copyedit-v2.md`: v1 and v2 side by side for every note whose output changed.
check: `test $(cat Skrift_Native/Shared/CopyEditV2/*.swift | wc -l) -le 1070 && test -s plan/reads/copyedit-v2.md`

### Q425 [tuur] (done) read the copy-edit v2 corpus output
spec: C8 C35
needs: Q449
do: -
check: Tuur read `plan/reads/copyedit-v2.md` (and the Dutch rambles run, if present) and said it reads right.

### Q426 [auto] (done) swap: Mac and iPad polish call copy-edit v2
spec: C2 C28 C38 C39
needs: Q425 Q478
gate+: yes
do: Point the Mac `EnhancementService` / batch path and the iPad polish path at copy-edit v2; a stale local prompt override is migrated away at first launch (C39). The v1 functions stay in place for Q427 to delete.
check: `! grep -rnE --exclude=CopyEditPipeline.swift "extractAnchors\(|PolishEscrow\." Skrift_Native/SkriftDesktop/Pipeline Skrift_Native/SkriftDesktop/Features Skrift_Native/SkriftMobile/Features`

### Q427 [tuur] (todo) delete v1 copy-edit after the tag
spec: C2 C252
needs: Q426
do: Tag the current commit `v1-copyedit`, then in ONE commit delete the v1 copy-edit code (`PolishEscrow`, the anchor code in `ImageMarkerReinsert`, v1's paths in `EnhancementService`) and the tests that pin it. This touches protected tests on purpose, so accept parks it stuck; Tuur approves the diff in the sitting.
check: `git rev-parse -q --verify refs/tags/v1-copyedit >/dev/null && ! grep -rqE "extractAnchors" Skrift_Native --include='*.swift'`

### Q428 [auto] (done) reconcile harness: v1 row goldens and the C52 test
spec: C253 C5 C44 C52 C41 C6 R40
needs: -
gate+: yes
do: Seed the corpus, run the v1 sweep, and record every Mac row field by field as `test-fixtures/corpus/goldens/v1-rows/<slug>.json` (C44). `ReconcileDiffHarnessTests` (desktop target) runs each registered sweep engine and classes rows identical / expected-different / unexplained (C5), and asserts a second sweep changes nothing (C41). Pin C52: launch, activation and CloudKit import each trigger one coalesced sweep through a fresh context, no timer, and a failed cloud fetch is logged and surfaced (R40).
check: `test $(ls test-fixtures/corpus/goldens/v1-rows | wc -l) -ge 100 && grep -rqE "class ReconcileDiffHarnessTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q429 [auto] (done) reconcile v2 beside v1
spec: C41 C42 C43 C44 C45 C46 C47 C48 C52 C185 C186 C187 C188 C189 C190 C191 C294 C2 C3
needs: Q428
gate+: yes
do: Write the reconcile sweep v2 in `Skrift_Native/Shared/ReconcileV2/`: memo → row mapping without fake multipart (C44), trust (C42), kinds from the caller (C43), late assets healed by content hash without faulting unchanged blobs (C45), stamp-to-stamp LWW with ±5 s skew (C46), per-field reflect (C47), duplicates (C48), names and vocab before memos (C185), store-resolved writers (C186-C188), re-export rules (C189), asset materialisation (C190), guarded await points (C294). Register it in the Q428 harness; the app keeps calling v1. At most 2,119 lines (40% of 5,297, C3). Write `plan/reads/reconcile-v2.md` listing every row that changed.
check: `test $(cat Skrift_Native/Shared/ReconcileV2/*.swift | wc -l) -le 2119 && test -s plan/reads/reconcile-v2.md`

### Q430 [tuur] (dead) read the reconcile v2 row diff
spec: C8
needs: Q429
do: -
check: Tuur read `plan/reads/reconcile-v2.md` and said go.

### Q431 [auto] (todo) swap: the Mac sweep calls reconcile v2
spec: C2 C52
needs: Q430 Q510
do: Point `MemoCloudReconciler`'s callers (launch, activation, CloudKit import, `CloudFirstImport`, `MacNoteOpenWork`) at reconcile v2. The v1 code stays in place for Q432 to delete.
check: `grep -rqE "ReconcileV2" Skrift_Native/SkriftDesktop/App Skrift_Native/SkriftDesktop/Pipeline`

### Q432 [tuur] (todo) delete v1 reconcile after the tag
spec: C2 C252
needs: Q431
do: Tag the current commit `v1-reconcile`, then in ONE commit delete v1's sweep code in `MemoCloudReconciler` and the tests that pin it. Touches protected tests, so accept parks it stuck; Tuur approves the diff in the sitting.
check: `git rev-parse -q --verify refs/tags/v1-reconcile >/dev/null`

### Q433 [auto] (done) export harness: v1 export goldens, tests for C57 C64 C65, dest fixtures on two destinations
spec: C253 C5 C57 C58 C64 C65 C129 C130 C133 C135 C137 D189
needs: -
gate+: yes
do: Re-baseline the `dest-*` corpus fixtures to D189: `dest-project`, `dest-idea`, `dest-inspiration-credit` become Portfolio plus that tag, exported to `<portfolio root>/_inbox/<slug>.md`. Record v1's export of every corpus note on both profiles as `test-fixtures/corpus/goldens/v1-export/<slug>.<vault|portfolio>.md`. `ExportDiffHarnessTests` (desktop target) classes each identical / expected-different / unexplained (C5) and checks portfolio frontmatter is flat YAML per C130 (one line per value, no `: ` in a plain value, block lists, none of the forbidden keys). Pin C57 (`typed-same-title-a/b` give distinct image files), C64 (a note recorded at 23:30 local gets the same `date:` from the phone and Mac paths), C65 (no snap call in any exporter).
check: `test $(ls test-fixtures/corpus/goldens/v1-export | wc -l) -ge 100 && grep -rqE "class ExportDiffHarnessTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q434 [auto] (done) export compiler v2 beside v1
spec: C53 C54 C55 C56 C57 C58 C59 C60 C61 C62 C63 C64 C129 C130 C131 C132 C133 C134 C135 C136 C137 C192 C193 C194 C195 C196 C2 C3
needs: Q433
gate+: yes
do: Write the export compiler v2 in `Skrift_Native/Shared/ExportV2/` per the export and portfolio clauses as re-baselined to two destinations (D189): a pure compiler (C56), `VaultLayout.home` (C53, C192), ownership and stamp rules (C54, C55, C193), images and attachments (C57, C58), memo-links (C59), quotes (C60), export gates (C61), Personal → vault and Portfolio → `_inbox/` (C62, C133), video and audio (C63, C136, C195), dates (C64). Register it in the Q433 harness; the app keeps calling `Shared/Export/Compiler.swift`. At most 1,094 lines (40% of 2,734, C3). Write `plan/reads/export-v2.md` with every export that changed.
check: `test $(cat Skrift_Native/Shared/ExportV2/*.swift | wc -l) -le 1094 && test -s plan/reads/export-v2.md`

### Q435 [tuur] (todo) read the export v2 output
spec: C8 C131
needs: Q434
do: -
check: Tuur read `plan/reads/export-v2.md` and said go.

### Q436 [auto] (todo) swap: iPad and Mac export call the v2 compiler
spec: C2 C61
needs: Q435 Q511
do: Point the shared export engine (iPad and Mac) at the v2 compiler. `Shared/Export/Compiler.swift` stays in place for Q437 to delete.
check: `grep -rqE "ExportV2" Skrift_Native/Shared/Export Skrift_Native/SkriftDesktop`

### Q437 [tuur] (todo) delete the v1 export compiler after the tag
spec: C2 C252
needs: Q436
do: Tag the current commit `v1-export`, then in ONE commit delete `Shared/Export/Compiler.swift`'s v1 paths and the tests that pin them. Touches protected tests, so accept parks it stuck; Tuur approves the diff in the sitting.
check: `git rev-parse -q --verify refs/tags/v1-export >/dev/null`

### Q438 [auto] (done) one shared share dispatcher with ingress fixtures
spec: C238 C198 C67 C69 C75 C125 C141 R4 R22
needs: -
gate+: yes
do: Today: only the accepted-type list is shared (`Shared/Pipeline/ImportKinds.swift`); `SharePayloadLoader.swift` and the Mac `IngestService.swift` each branch by type on their own. Write `Skrift_Native/Shared/Ingress/`: a pure dispatcher that takes every extension item and every provider (UTI plus file or text) and returns one import plan (kind, clips in order, pictures, texts in order, url, title) or an honest refusal. Order per C198 (audio → web URL → movie → images → text → document); audio outranks the URL and odd UTIs reroute by extension (C69); several texts keep their order (C125); a photo's caption is kept (C141); an empty payload refuses (C75). Fixtures in `test-fixtures/corpus/ingress/<door>/` (providers manifest + `expect.json`): WhatsApp 3 items, Signal 4 providers, 2 texts among clips and a picture, URL-as-text, photo with caption, empty payload. Test `IngressDispatchTests` (desktop target).
check: `test $(ls -d test-fixtures/corpus/ingress/*/ | wc -l) -ge 6 && grep -rqE "class IngressDispatchTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q439 [auto] (done) the phone share extension and the Mac importer use the shared dispatcher
spec: C238 C67 C77 C75
needs: Q438
do: `SharePayloadLoader` / `ShareViewController` on the phone and the Mac file importer call the Q438 dispatcher; their own per-type branching is deleted, not left beside it. Behaviour on today's working doors stays the same (`ShareSheetView` tests still pass).
check: `grep -rqE "IngressDispatch|ShareDispatch" Skrift_Native/SkriftMobile/SkriftShare && grep -rqE "IngressDispatch|ShareDispatch" Skrift_Native/SkriftDesktop`

### Q440 [auto] (done) a Voice Memo keeps its name, the same file twice is one note, a .skriftbook goes to Books
spec: C126 C127 C146
needs: Q439
gate+: yes
do: A Voice Memo shared under its own name keeps that name as the note title; a messenger filename never becomes one (C126). Sharing the same bytes twice yields the existing note and an "Already in Skrift" state in `ShareFeedbackView` beside its existing states (C127). A `.skriftbook` arriving through the share sheet goes to the book importer (C146). Fixtures `ingress/named-voice-memo`, `ingress/same-file-twice`, `ingress/skriftbook-via-share`; cases added to `IngressDispatchTests`.
check: `test -d test-fixtures/corpus/ingress/same-file-twice && test -d test-fixtures/corpus/ingress/skriftbook-via-share`

### Q441 [auto] (done) email, selected-text and Maps shares
spec: C142 C144 C123
needs: Q439
gate+: yes
do: An `.eml` / Mail share becomes a text capture: title = Subject, body = plain text, `recordedAt` = the Date header, sender per C123, attachments as files (C142). Selected text with its page URL is a text capture carrying the url and title, no fetch; a Maps link is a link capture with the place as location and title, no fetch (C144). Fixtures `ingress/email`, `ingress/selected-text`, `ingress/maps-link`; cases in `IngressDispatchTests`.
check: `test -d test-fixtures/corpus/ingress/email && test -d test-fixtures/corpus/ingress/maps-link`

### Q442 [tuur] (done) approve: flip NoteBodyTests.testClearingBodyCommitsNilTranscript to C261 (Q408)
spec: C261 D163
needs: Q408
do: The phone test `Skrift_Native/SkriftMobile/SkriftMobileTests/NoteBodyTests.swift` `testClearingBodyCommitsNilTranscript` asserts the old behaviour C261 forbids (clearing the body commits a nil transcript). Q408's worker proposes `XCTAssertEqual(coordinator.memo.transcript, "hello world")` instead. That changes an assertion on live behaviour, which D163 does not cover, so it needs his yes; then the conductor applies it with `plan/hand-merge.sh`. Until then `plan/mtest.sh NoteBodyTests` is red (exit 65). Same sitting, same kind: `AudioShareDrainTests.testTextFileBecomesNoteBody` (phone) still expects a shared `.md` to become a `.text` capture, but D171/Q286 made it a typed note; it has been red since Q286 (found by Q414). Flip it to the typed-note shape on the same yes.
check: Tuur said yes and `plan/mtest.sh NoteBodyTests` and `plan/mtest.sh AudioShareDrainTests` exit 0.

### Q443 [tuur] (tuur) deploy the CloudKit prod schema for VocabularyRecord.wordLedger (Q410) before Q370
spec: D201
needs: Q410
do: Q410 added the synced field `VocabularyRecord.wordLedger`. Before the production update, run a Dev build once so the field exists in CloudKit Development, then in the CloudKit Console deploy the Development schema to Production (same step as Q298; see plan/release/RELEASE.md). Without it the prod apps cannot save the carrier.
check: Tuur deployed the schema and the console's Production schema shows `VocabularyRecord.wordLedger` and `Memo.transcriptLanguageMode` (Q480) and `MemoEnhancement.pendingBlock` (Q481) and `Memo.transcriptEditedAt` (Q486), plus any field later items add (check plan/RUN.md for "NEW synced field").

### Q444 [auto] (done) install Dev 191 (Q408–Q422) on the iPhone 17 Pro and the Mac
spec: -
needs: Q417
do: Same recipe as Q407: bump SKRIFT_BUILD to 191 in both project.yml files, build the Dev (Debug) iOS app for the iPhone 17 Pro (devicectl UDID 00008150-001658662223C01C; resolve its xcodebuild UDID first, the old iPhone 13 UDID in CLAUDE.md is stale) with `-allowProvisioningUpdates DEVELOPMENT_TEAM=9W82X49JZS CODE_SIGN_STYLE=Automatic`, install with devicectl, string-grep a Q408 literal (`EmptyCommitGuard`) in the installed binary. Mac: Debug build, quit Skrift Dev, ditto to `/Applications/Skrift Dev.app`, never two Dev instances, never touch prod `/Applications/Skrift.app`, never `open -a`. If the phone is locked or unplugged, report blocked.
check: Report shows build 191 installed on the phone (devicectl app list) and the Mac Dev app's CFBundleVersion is 191.

### Q445 [auto] (done) v1 export: a note opening with a picture fuses the closing --- and loses the stamp (pic-at-start)
spec: C55 C56 C130 C193
needs: Q433
gate+: yes
do: Found by Q433: the corpus note `pic-at-start` (body opens with `[[img_001]]`) exports a broken frontmatter on BOTH profiles today: the closing `---` is fused onto the first sentence and `skriftID`/`skriftHash` are lost, so the vault file is no longer recognised as ours. Likely cause: `BodyV2Legacy.shown` runs over the whole compiled markdown in `VaultExporter.export` instead of the body only. Fix it in the v1 exporter (this is live until export v2 swaps in), keep the closing `---` on its own line and the stamp trio intact, and add `PicAtStartExportTests` (desktop target) asserting the frontmatter parses and carries skriftID/skriftHash for `pic-at-start` on both profiles. Then re-record the two `pic-at-start` goldens in `test-fixtures/corpus/goldens/v1-export/` and drop their C130 entry from `expected-differences-export.json` (report both as needs hand-merge).
check: `grep -rqE "class PicAtStartExportTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q446 [auto] (done) iPad export: the same pic-at-start frontmatter fusion in ObsidianPublisher (Q445 twin)
spec: C55 C56 C193 C239
needs: Q445
gate+: yes
do: Q445 fixed the Mac (`VaultExporter.shownBody` splits off the frontmatter and runs `BodyV2Legacy.shown` on the body only). The iPad/phone exporter has the same pattern: `Skrift_Native/SkriftMobile/Services/Export/ObsidianPublisher.swift` runs `BodyV2Legacy.shown(markdown).text` over the whole compiled markdown, so a note opening with a picture fuses the closing `---` onto the first sentence and loses the stamp. Move the body-only split into ONE shared function in `Skrift_Native/Shared/Export/` used by both exporters (C239, no twin), delete the Mac-only copy. Test `PicAtStartPublisherTests` (phone target) on corpus `pic-at-start`; keep `PicAtStartExportTests` green.
check: `plan/mtest.sh PicAtStartPublisherTests`

### Q447 [tuur] (done) decide: may a messenger filename ever be a title? C126 says never; D176 keeps it on the Files importer
spec: C126 D176
needs: -
do: -
check: Tuur picked one: (a) C126 everywhere — the Files importer also drops "WhatsApp Audio 2025-12-18 at 18.30.44" style names (then `ImportFileNameTitleTests` flips, an approved assertion change), or (b) keep D176 on Files/Open-in and C126 only on the share sheet (as Q440 built). His answer lands in SPEC Decisions.

### Q448 [auto] (done) an email share keeps its attachments as note attachments; Mac folder ingest takes .eml too
spec: C142 C77
needs: Q441
gate+: yes
do: Q441 parses `.eml` attachments (`EmailShare.Message.attachments` in `Skrift_Native/Shared/Ingress/EmailShare.swift`) but stores none, on phone or Mac. Store each attachment the way a note's file attachments are stored since Q385 (the same synced asset kind and `[[file_…]]`-style body marker the attachments lane uses; read FEATURES.md "attachments" and the Q385/Q392 findings in plan/RUN.md first), placed after the email body in attachment order. Also route `.eml` through `ingestEmailCapture` in the Mac folder-ingest path (`IngestService.swift`, the folder walk) like the direct drop. Test `EmailAttachmentsTests` (desktop target) on the `ingress/email` fixture with two attachments: the note carries both, in order.
check: `grep -rqE "class EmailAttachmentsTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q449 [auto] (done) copy-edit v2: accept small word drops; fall back to unedited only on a translation, a lost name or number, an invented name, or the shrink guard (D209)
spec: C35 C177 C33 D209
needs: Q424
gate+: yes
do: Tuur rejected Q424's all-or-nothing gate (D209): a model that drops a small word is the price of having a model. Loosen `CopyEditV2Gate` in `Skrift_Native/Shared/CopyEditV2/`: ship the model's edit even when it drops ordinary words; ship the original words unedited ONLY when the edit translates (language flip), loses a name or a number, invents a proper noun, re-paragraphs a typed note, or the C33 shrink guard fires. Keep fillers um/uh/eh removable. Re-run the harness, update `expected-differences-copyedit-v2.json` (still 0 unexplained; the code-switch translation must still be caught), and rewrite `plan/reads/copyedit-v2.md` so it lists which notes now ship the model's edit and which still fall back, with why.
check: `grep -q 'D209' plan/reads/copyedit-v2.md`

### Q450 [auto] (done) flip the two stale phone tests Tuur approved (Q442)
spec: C261 D171 D163
needs: -
do: Tuur said yes (Q442, 2026-10-15). In `Skrift_Native/SkriftMobile/SkriftMobileTests/NoteBodyTests.swift` change `testClearingBodyCommitsNilTranscript` to assert the C261 behaviour (clearing the body does NOT commit nil; the prior transcript stays, e.g. `XCTAssertEqual(coordinator.memo.transcript, "hello world")`), and in `AudioShareDrainTests.swift` change `testTextFileBecomesNoteBody` to expect the D171 typed-note shape for a shared .md. Touch nothing else. Report needs hand-merge: both files.
check: `plan/mtest.sh NoteBodyTests && plan/mtest.sh AudioShareDrainTests`

### Q451 [auto] (done) a new note and a reopened note render through one code path: one header row, no tab bar
spec: C113 C234 C239 D115
needs: -
gate+: yes
do: Tuur 2026-10-15 on Dev 191 (screenshots): a brand-new note shows tag, rating and Personal stacked on three rows, and tapping Done on the keyboard bar reveals the bottom tab bar (Notes/Library/Review/Settings) over the note; the same note reopened shows the signed layout (title, grey meta line, then `○○○ Not rated · Personal · + tag` on ONE row) with no tab bar. Two code paths draw the open note. Make the new-note path use the exact same view as the reopened note (the Q358 build of `Skrift_Native/SkriftDesktop/mocks/Q350-note-editor-apple.html`) and delete the duplicate; the tab bar is hidden in every open-note state. Then grep for any other place that draws a note differently for new vs existing (quick note, capture, share-opened, iPad) and fold those into the same view; list what you found. Phone test `NoteScreenParityTests`: the new-note and reopened-note screens build the same header view type and hide the tab bar. Screenshot both states on the iPhone 17 sim, LOOK, put them in `plan/reads/note-parity/`.
check: `plan/mtest.sh NoteScreenParityTests`

### Q452 [tuur] (done) mockup: more typing space when the keyboard is up
spec: C113 C234
needs: Q451
do: One clickable HTML page `Skrift_Native/SkriftDesktop/mocks/Q452-typing-space.html`, iPhone 17 Pro frames: today's open note with the keyboard up (drawn from source after Q451: title, meta line, the one rating/Personal/tag row, keyboard bar) leaves about a quarter of the screen for text (Tuur 2026-10-15). Show 2-3 options that give typing real estate while the keyboard is up: e.g. the header collapses to one slim line once he types, the rating/Personal/tag row scrolls away with the text, the keyboard bar slims. Compare with Apple Notes, which shows only text while typing. One agent writes this file.
check: Tuur clicked through it and picked one.

### Q453 [auto] (done) after Add recording the open note's player plays across the join without reopening the note
spec: C223 C26
needs: -
gate+: yes
do: Tuur 2026-10-15 on Dev 191 (Q311 failed): record a voice note, ⋯ › Add recording, say more, stop, play from before the join: playback STOPS at the old end; only after leaving and reopening the note does the player play the appended audio. The player keeps the old asset/duration after the append. Make the open note's player reload the merged audio (and the shifted word timings, C223) as soon as the append lands, on phone and iPad (and check the Mac Add recording path does the same). Phone test `AppendPlayerReloadTests`: after an append the open note's player item duration equals the merged file's.
check: `plan/mtest.sh AppendPlayerReloadTests`

### Q454 [auto] (done) a shared video lands as an inline video attachment like Apple Notes, not a 'Photo' file card (D210)
spec: C71 C63 D210 D202
needs: -
gate+: yes
do: Tuur 2026-10-15 on Dev 191: sharing a video into Skrift Dev makes a note that says Video but shows a `Photo · JPEG image · 117 KB` FILE CARD at the top (the frame), not the video. D210: a shared or imported video becomes the same inline video attachment a note gets from the Q385 attachments build (inline play, small by default, D202), with its transcript as the body; the frame is the attachment's poster, never a separate photo card. The synced `source.<ext>` movie (D188) is that attachment's file. Same on the Mac import path. Phone test `SharedVideoAttachmentTests`: a shared movie yields one video attachment marker and no photo card. Screenshot the note on the sim, LOOK.
check: `plan/mtest.sh SharedVideoAttachmentTests`

### Q455 [tuur] (done) mockup: the share sheet and its 'Saved' confirmation, redrawn
spec: C66 C75 C127
needs: -
do: One clickable HTML page `Skrift_Native/SkriftDesktop/mocks/Q455-share-sheet.html`, iPhone frames. Tuur 2026-10-15: the share sheet (`SkriftShare/ShareSheetView.swift`) and the confirmation after Save (`ShareFeedbackView.swift`) both look ugly. Draw today's two screens from source, then a calmer version in the app's Apple-style look (D190, the notes list and editor): for a voice memo, a video, a link, a photo, plus the 'Already in Skrift' and 'Skrift can't import this' states. Keep the rating and the sender name field position open as a question on the page. One agent writes this file.
check: Tuur clicked through it and said go.

### Q456 [auto] (done) capture camera: smooth pinch zoom, no fake drag handle, one recording status line
spec: C221 C100
needs: -
gate+: yes
do: Tuur 2026-10-15 on Dev 191 (Q221 confirmed): in the capture camera sheet pinch zoom is very jumpy (it compounds); the sheet shows a grab-handle pill at its top that drags nothing; and the recording status draws twice on top of itself (`Recording · 0:17 — still listening` over a second `Recording`). Fix: pinch sets zoom from the zoom factor at gesture start × scale, clamped to the device range (no compounding); remove the pill or make the sheet actually draggable (remove it); render one status line. Phone test `CaptureCameraZoomTests` for the zoom math. Camera hardware can't be proven on the sim; say so and leave the device feel to Tuur.
check: `plan/mtest.sh CaptureCameraZoomTests`

### Q457 [auto] (done) a messenger filename is never a title, on every door (D211)
spec: C126 D211
needs: -
gate+: yes
do: Tuur picked (a) on Q447 (2026-10-15, D211): a messenger or machine filename (WhatsApp/Signal/Telegram audio names, recorder patterns, UUIDs) is never a note title on ANY door — share sheet (already, Q440 `IngressDispatch.clipTitle`), Files importer, Open-in, AirDrop, Mac drop/folder ingest. Use the one shared rule (`IngressDispatch.clipTitle` or move it to `NoteTitle`) everywhere `NoteTitle.importName` titles from a filename; a real name like "kiln idea.m4a" still becomes the title. Flip `ImportFileNameTitleTests` to D211 (Tuur approved this assertion change in the same answer) and report it as needs hand-merge. Desktop test `MessengerNameNeverTitleTests` covering Files and Mac paths.
check: `grep -rqE "class MessengerNameNeverTitleTests\\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q458 [auto] (done) real-shaped PDF fixtures with expected reading text (synthetic, generated)
spec: D213 C4
needs: -
gate+: yes
do: Tuur 2026-10-15: the PDF reading view is not useful until it handles real layouts (D213), and today nothing proves its quality (only hand-made strings in `PDFReflowTests`). Generate synthetic PDFs (never his files; a script in `test-fixtures/pdf/generate.py` or Swift, committed) into `test-fixtures/pdf/`: two-column paper, report with running headers/footers and page numbers, page with a figure + caption, a 5-column table, a scanned page (text rendered to an image only), a single-column book page as control. Each gets `<name>.expect.md`: the reading text a careful human would want (order, headings, figure place marked `[figure: caption]`, table as rows, no headers/footers). `PDFReadingGoldenTests` (phone target) runs today's reflow on each and records per-fixture word-order similarity + header/footer leakage into `plan/reads/pdf-reading-baseline.md`; register today's failures as expected (C5 style) so later items flip them.
check: `test $(ls test-fixtures/pdf/*.pdf | wc -l) -ge 6 && plan/mtest.sh PDFReadingGoldenTests`

### Q459 [auto] (done) PDF reading view: right column order, no running headers/footers or page numbers, wide tables kept
spec: D213
needs: Q458
gate+: yes
do: First add a STRUCTURE metric to `PDFReadingGoldenTests` (Q458 finding: word order + leakage cannot see structure; figure-caption and table-5col pass today while wrong): per fixture, compare the headings, `[figure: …]` lines and table rows of the reading view against `expect.md`, and register today's structure failures in `expected-failures.json`. Then make the reading view match the goldens for layout: read text by line geometry (PDFKit selections / line bounds) instead of raw `page.string`, so a two-column page reads left column then right; drop lines that repeat at the same position on most pages (running headers/footers) and bare page numbers; keep tables of any width as rows (`Shared/Pipeline/PDFReflow.swift` holds the pure rules, `LibraryPDFReflow.swift` the PDFKit side). Flip the matching expected failures in `PDFReadingGoldenTests`; the control fixture must stay identical.
check: `plan/mtest.sh PDFReadingGoldenTests`

### Q460 [auto] (done) PDF reading view: figures shown inline where they sit on the page
spec: D213
needs: Q459
gate+: yes
do: Images and figures are dropped today. Also measure (Q459 doubt): each word now costs one PDFSelection; time the reading view of a generated 300-page text PDF and write the number into plan/reads/pdf-reading-structure.md; if it is over ~3 s on the iPhone 17 sim, batch the geometry per line. Crop each figure region from the page (PDFKit page image within the figure's bounds, or the embedded image) and show it inline in the reading view at its place, with its caption, using the same image block the article reader uses (Q351 build). Flip the figure fixture in `PDFReadingGoldenTests`. Screenshot the reading view of the figure fixture on the iPhone 17 sim, LOOK, `plan/reads/pdf-reading/`.
check: `plan/mtest.sh PDFReadingGoldenTests`

### Q461 [auto] (done) PDF reading view for scanned PDFs: on-device text recognition
spec: D213 C120
needs: Q459
gate+: yes
do: A scanned or image-only PDF gets no reading view today (`PDFReflow` usable-check fails). Run on-device Vision text recognition (VNRecognizeTextRequest, accurate, languages en + nl, never a network call, C120) per page when PDFKit text is missing or garbled, cache the result beside the library item, show a 'Reading the scan…' progress line while it runs, and feed the recognised lines through the same layout rules. Flip the scan fixture in `PDFReadingGoldenTests`.
check: `plan/mtest.sh PDFReadingGoldenTests`

### Q462 [tuur] (done) mockup: comment on a PDF highlight and share the PDF with your highlights and comments
spec: D212
needs: -
do: One clickable HTML page `Skrift_Native/SkriftDesktop/mocks/Q462-pdf-highlight-comments.html`, iPhone frames, drawn from source (`LibraryPDFReader.swift`, `SourceHighlight`, Highlight in the reading and page views). Tuur 2026-10-15 (D212): highlights should go INTO the PDF as real annotations with his comments, so he can share the PDF later with his thoughts. Show: adding a comment to a highlight (and editing/removing it), how commented highlights look in the reading view and the page view, and a 'Share PDF with highlights' action (does the library PDF itself carry the annotations, or only the shared copy? show both options and ask). One agent writes this file.
check: Tuur clicked through it and said go.

### Q463 [auto] (done) build PDF highlight comments and annotated PDF sharing per the mock
spec: D212
needs: Q462
gate+: yes
do: Build to `Skrift_Native/SkriftDesktop/mocks/Q462-pdf-highlight-comments.html` (signed 2026-10-16, Tuur: "the rest looks really good", D214) with two changes from his sign-off: (1) a comment can be typed OR voice-recorded: a mic button in the comment sheet records, transcribes on-device with the app's existing transcription engine, and stores the audio plus its transcript on the highlight; the PDF annotation contents carry the transcript; (2) the share action asks every time: share the PDF with my highlights and comments, or the clean PDF. The Library PDF itself carries the highlights and comments as real annotations, written when he leaves the reader (not per highlight); the untouched original is kept once as a hidden backup, which is what "clean PDF" shares. Original notes: a comment field on `SourceHighlight` (additive, synced), written into the PDF as real PDFKit highlight annotations with the comment as the annotation contents, so Preview/Files/other apps show them; the share action hands over that annotated PDF. Never lose the untouched original (C273 spirit). Phone test `PDFAnnotationExportTests`: a highlight with a comment round-trips through the written PDF (PDFKit reads back a .highlight annotation with that contents on that page).
check: `plan/mtest.sh PDFAnnotationExportTests`

### Q464 [auto] (done) build the calm share sheet per the Q455 mock, option A (rating + From rows), with the sender field
spec: C66 C75 C123 C127 D37
needs: Q455
gate+: yes
do: Build `Skrift_Native/SkriftDesktop/mocks/Q455-share-sheet.html` (signed 2026-10-15, Tuur: "beautiful! my pick is A, rows below"): the calm sheet filling the system sheet in the app's Apple-style look, light/dark; ✕ top left, Save as the nav-bar button top right; the item card, then option A: a Settings-style card BELOW it with a "Rating" row (pill on the right) and a "From" row; the in-place green "Saved" receipt that closes after 0.9 s (no separate green-circle card); "Already in Skrift" as a notes-list row; "Can't import" as the iOS empty state. The From row is C123: an optional sender name with roster autocomplete (D37), remembered per chat when the share carries a hint, stored as a new additive field on the capture inbox entry and written into the note as a person mention (links when on the roster, exports into people: when linked). Delete the old forced-dark sheet, the Sk monogram and the big glowing Save. Phone test `ShareSheetSenderTests` (sender reaches the note as a mention). Screenshots of every state on the iPhone 17 sim beside the mock, LOOK, list every colour/type/spacing difference in the report.
check: `plan/mtest.sh ShareSheetSenderTests`

### Q465 [auto] (done) capture camera: the .5x chip really zooms out (virtual back camera)
spec: C100 C221
needs: Q456
gate+: yes
do: Found by Q456: the capture camera uses builtInWideAngleCamera (min zoom 1.0), so the .5x chip Tuur sees on the iPhone 17 Pro never reaches the ultra-wide. Switch the back camera to the virtual device (builtInTripleCamera, else builtInDualWideCamera, else wide) so zoom factors map to the real lenses, keep the Q456 gesture-start pinch, and show only the chips the device can do (.5x only when the virtual device exposes the ultra-wide). Phone test `CameraLensChipsTests` for the chip list per device type. Device feel is Tuur's.
check: `plan/mtest.sh CameraLensChipsTests`

### Q466 [auto] (done) typing: the note follows the caret so the header scrolls away like Apple Notes (Q452 pick)
spec: C113 C234
needs: Q452
gate+: yes
do: Tuur on the Q452 mock (2026-10-15): keep today's header exactly as built (title, grey meta line, the one rating/Personal/tag row) and let it scroll away like Apple Notes, nothing folds or collapses. While he types with the keyboard up, the note scrolls so the caret stays just above the keyboard bar, which pushes the header off the top as soon as the text needs the room; dragging down brings it back. Read the Q452 finding (`grep -n 'finding: Q452' plan/RUN.md`): the header already scrolls with the note, so this is only the caret-follow while the note is short (MemoPageView / NoteBodyView). No sticky or collapsing header. Phone test `TypingScrollTests`: with the keyboard up, typing past the visible area scrolls the header out and keeps the caret visible. Screenshot on the iPhone 17 sim with the keyboard up after a few lines, LOOK.
check: `plan/mtest.sh TypingScrollTests`

### Q467 [auto] (done) iPad export converts [[vid_]] and [[file_]] markers instead of printing them
spec: C57 C58 C61 C239
needs: -
gate+: yes
do: Found by Q454: the iPad/phone `ObsidianPublisher` never converts `[[vid_NNN]]` / `[[file_NNN]]` attachment markers (a Q385 gap), so an iPad export prints them as raw text, while the Mac `MacNoteAttachments.convertMarkers` handles them. Move marker conversion for attachments into ONE shared function in `Skrift_Native/Shared/Export/` used by both exporters (C239), copying the attachment file beside the note under the same ownership rule (C58). Phone test `PublisherAttachmentMarkerTests`: an iPad export of a note with a file and a video attachment contains no `[[file_`/`[[vid_` text.
check: `plan/mtest.sh PublisherAttachmentMarkerTests`

### Q468 [auto] (done) a video note exports its poster frame to the vault again (C63) and the card is named sensibly
spec: C63 C71 D210
needs: Q454
gate+: yes
do: Found by Q454: with D210 the kept movie is a `[[vid_N]]` attachment whose marker is dropped on vault export (no movie in the vault, C63, right), but the vault now gets NO frame either; C63 says a video note exports markdown + audio + the frame. Write the poster frame as an image embed in its place on vault export (both exporters, shared code), never the movie. Also: a machine-named share shows the card title "Video" over "Video · 0:06"; title the card from the note title or the date instead. Desktop test `VideoNoteVaultFrameTests`.
check: `grep -rqE "class VideoNoteVaultFrameTests\\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q469 [auto] (done) polish protects [[vid_]] and [[file_]] markers like pictures
spec: C29 C30 C31
needs: Q454
gate+: yes
do: Found by Q454: copy-edit escrows picture paragraphs (`ImageMarkerReinsert`, and v2 by paragraph index) but not `[[vid_NNN]]` / `[[file_NNN]]` attachment markers, so a model pass can drop or move them. Treat attachment-marker paragraphs exactly like picture paragraphs in BOTH v1 (live) and copy-edit v2 (`Shared/CopyEditV2/`): stripped before the model, reinserted by paragraph index. Desktop test `AttachmentMarkerEscrowTests` over a note with a leading `[[vid_1]]` and a mid `[[file_1]]`; the copy-edit harnesses stay 0 unexplained.
check: `grep -rqE "class AttachmentMarkerEscrowTests\\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q470 [auto] (tuur) DevEraMergeTests.testOldStoreIsOpenedAsACopyOnly stops flaking on the SQLite -shm size
spec: D203
needs: -
gate+: yes
do: The gate went red once on `SkriftDesktopTests.DevEraMergeTests.testOldStoreIsOpenedAsACopyOnly` (DevEraMergeTests.swift:448: XCTAssertEqual on a file-size map containing `memo_cloud.store-shm: 32768 bytes`) during the full suite at machine load ~108, while the same class passed 3/3 alone on the same head (2026-10-15). The assertion compares SQLite side-file sizes, which change with checkpoint timing. Make it prove what C/D203 needs (the old store is opened as a COPY only, never written): compare the main store file bytes/hash and mtime, and assert -wal/-shm are untouched only if they existed before; or open the original read-only and check it. Do not weaken it to nothing. Report needs hand-merge: DevEraMergeTests.swift.
check: `cd Skrift_Native/SkriftDesktop && xcodebuild test -project SkriftDesktop.xcodeproj -scheme UnitTests -destination platform=macOS -skipPackagePluginValidation -skipMacroValidation -only-testing:SkriftDesktopTests/DevEraMergeTests -quiet`

### Q471 [auto] (done) a voice or video share's sender reaches people: like a capture's
spec: C123
needs: Q464
gate+: yes
do: Found by Q464: the share sheet's From name is stored as `CaptureInboxEntry.senderName` and the drain appends "From <name>". On a capture it lands in the body, so the Sanitiser links it and `people:` gets it; on an audio or video note it lands in `annotationText`, which `MemoExporter` never exports, so a voice-note sender never reaches `people:` (C123: "exports into people: when linked"). Make the sender a person mention that the name-linker sees and that exports, on both apps, in one shared place. Test `SenderPeopleExportTests` (desktop): a shared voice note with a roster sender exports that canonical in `people:`.
check: `grep -rqE "class SenderPeopleExportTests\\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q472 [auto] (done) install Dev 192 on the iPhone 17 Pro and the Mac
spec: -
needs: -
gate+: yes
do: Same recipe as Q444 (read `grep -n "finding: Q444" plan/RUN.md`): bump SKRIFT_BUILD to 192 in both project.yml files, Debug build for the iPhone 17 Pro (devicectl UDID 00008150-001658662223C01C, xcodebuild id is the same), install with devicectl, string-grep a Q464 literal (`ShareSender`) in the built binary; Mac Debug build, quit Skrift Dev via osascript (com.skrift.desktop.dev), ditto to /Applications/Skrift Dev.app, open once. Never touch /Applications/Skrift.app or any real data, never open -a the worktree app. If the phone is locked or unplugged, report blocked.
check: Report shows build 192 installed on the phone (devicectl app list) and the Mac Dev app CFBundleVersion is 192.

### Q473 [auto] (done) every device rebuilds its Library PDF from the synced highlights
spec: D212 D214
needs: Q463
gate+: yes
do: Tuur 2026-10-16 (go): the annotated Library PDF must be the same on phone, iPad and Mac. Today the book-file sync uploads a file once (AudiobookCloudSync upload-once, built for immutable audiobook audio), so only the device that highlighted has the annotated file (Q463 finding). Do NOT re-upload the PDF. Instead, on EVERY device, rebuild the local Library PDF from the hidden pristine original (`PDFAnnotationExport.pristine`) plus the synced `Audiobook.highlights` list whenever that list changes by sync (and on first download, creating the pristine backup there), using the same `LibraryHighlights.writeIntoPDF` atomic path. Two devices editing offline then converge because the file is regenerated from the merged list. Skip the rewrite when nothing changed. Spoken-comment audio still stays local (only its words sync); say so in FEATURES.md. Test `PDFAnnotationSyncRebuildTests` (phone target): a highlight list arriving by sync rewrites the local file so PDFKit reads back the annotation and comment; the pristine backup stays byte-identical; an unchanged list writes nothing.
check: `plan/mtest.sh PDFAnnotationSyncRebuildTests`

### Q474 [auto] (done) highlights from two devices merge per highlight, never last-writer-wins
spec: C267 D214
needs: Q473
gate+: yes
do: Found by Q473: `Audiobook.highlights` syncs as one blob, last-writer-wins by modifiedAt, so highlights or comments made on the phone and the iPad while offline lose one device's side (data loss, same shape as C267 for vocab). Merge per highlight id: union adds, a removal is a tombstone with a stamp (pruned after 90 days like names), a comment edit is LWW per highlight. Follow the Q410 vocab ledger pattern (`Shared/Pipeline/VocabularyLedger.swift`, `VocabularySyncCore.sync`); old blobs without stamps fall back to today's behaviour once. The Q473 rebuild then runs from the merged list. Test `HighlightMergeTests` (phone target): two offline adds both survive; a remove on one device beats an older add; comment edits LWW.
check: `plan/mtest.sh HighlightMergeTests`

### Q475 [auto] (dead) Add a podcast episode sheet: the feedback bubble covers the Paste button
spec: -
needs: -
gate+: yes
do: Tuur 2026-10-16 screenshot (Dev 192, iPhone 17 Pro, Library › + › Add a podcast episode): the FeedbackKit floating bubble sits on top of the button to the right of the link field, so only its first letter "P" (Paste) shows. Keep the bubble clear of controls in this sheet: inset the field row, or move/hide the bubble while a sheet with a trailing control is up (check how other sheets handle it; Q464 noted the bubble over the share-sheet demos too). Fix it where the bubble placement is decided so every sheet benefits. Screenshot the sheet on the iPhone 17 sim, LOOK, and confirm the whole Paste button shows. Phone test `PodcastAddSheetLayoutTests` (the trailing button frame does not intersect the bubble frame).
check: `plan/mtest.sh PodcastAddSheetLayoutTests`

### Q476 [auto] (done) a Spotify episode link finds the show's public feed instead of saying Spotify-only
spec: C72 D90
needs: -
gate+: yes
do: Tuur 2026-10-16 (Dev 192, Library › Add a podcast episode): pasting https://open.spotify.com/episode/2eDqhsYCs70lRUrjw2oYGn showed "This episode is only on Spotify and has no public feed". Wrong: Spotify oEmbed (https://open.spotify.com/oembed?url=…) names it "Andrew Ng on the delusion of AI doom", og:description "Economist Podcasts · Episode", released 2026-10-14; it is in the public Babbage feed (https://feeds.acast.com/public/shows/e421d786-ec36-4148-aa99-7a3b2928a779, slug andrew-ng-on-the-ai-doom-delusion) and the Economist Podcasts feed. Resolve a Spotify episode: read title + show from oEmbed / page meta, find the show via the iTunes Search API (entity=podcast, then its feedUrl; try the show name and "<show> from <publisher>" variants), then match the episode in the feed by normalised title (and date ±2 days). Only when that fails say it is Spotify-only. WIDENED 2026-10-16 (Tuur: "can't add shit, have u tested this properly?" — no: only PodcastFeedTests on hand-made data): one resolver chain for Spotify, Deezer (link.deezer.com short link → deezer.com/episode/<id> → api.deezer.com/episode/<id>), Acast pages, Overcast, Pocket Casts and any page with an RSS alternate link; an honest per-app message when all fail; a REAL-LINK fixture set under test-fixtures/podcast-links/ recorded once from real links (incl. Tuur's Spotify and Deezer links). Also accept an Acast episode page link (shows.acast.com/<show>/episodes/<slug>) by reading its feed. No Spotify scraping beyond the public oEmbed/meta (no login). Test `SpotifyFeedResolveTests` (phone target) on recorded oEmbed + iTunes + feed fixtures for this episode (no live network in tests).
check: `plan/mtest.sh SpotifyFeedResolveTests`

### Q477 [auto] (done) install Dev 193 on the iPhone 17 Pro and the Mac
spec: -
needs: -
gate+: yes
do: Same recipe as Q472 (`grep -n "finding: Q472" plan/RUN.md`): bump SKRIFT_BUILD (phone project.yml) AND CURRENT_PROJECT_VERSION (desktop project.yml) to 193; Debug build for the iPhone 17 Pro (00008150-001658662223C01C, same id for xcodebuild; phone needs -skipMacroValidation -skipPackagePluginValidation), install with devicectl, string-grep a Q476 literal (`lockedEpisodes`) in the built binary; Mac Debug build, quit Skrift Dev via osascript (com.skrift.desktop.dev), ditto to /Applications/Skrift Dev.app, open once. Never touch /Applications/Skrift.app or real data, never open -a the worktree app. If the phone is locked or unplugged, report blocked.
check: Report shows build 193 installed on the phone (devicectl app list) and the Mac Dev app CFBundleVersion is 193.

### Q478 [auto] (done) copy-edit v2 keeps checkboxes, short-note sentences, his spelling and lists (D215)
spec: C29 C33 C35 C177 D209 D215
needs: -
gate+: yes
do: Tuur on Q425 (2026-10-23, D215, "all four as recommended") on the read `plan/reads/copyedit-v2.md`: (1) checkbox lines (`- [ ]` / `- [x]`) never reach the model: hold them aside like pictures and put them back in place, so typed-tasks keeps every box and its state; (2) a note under 40 words that loses a full sentence (any whole input sentence absent from the output) falls back to his words, catching voice-en-paragraphed-by-pauses and voice-en-raw-title; (3) his spelling stays: tell the model in the ONE prompt source (`PolishPrompts`, C39) to keep the writer's spelling and dialect, and add a gate check that no input word was replaced by a spelling variant (colour→color, apologising→apologizing), falling back if so; (4) typed list lines (`- `, `* `, `1. `) stay list lines: hold list blocks aside when the note is typed, or fall back when the output loses list structure (typed-dutch-boodschappen). Fillers and "okay so" may still go. A changed prompt means new model outputs: record them with the Q424 recorder (`-recordcopyeditv2 <corpus> -isolatedRun`, raw Debug binary, never -corpus, never /Applications/*); never fabricate. Update `expected-differences-copyedit-v2.json` and rewrite `plan/reads/copyedit-v2.md` showing those four notes now. Test `CopyEditV2D215Tests` (desktop target).
check: `grep -rqE "class CopyEditV2D215Tests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q479 [auto] (done) A: an interruption pauses the recording clock, so photos land where they were taken
spec: C149
needs: -
gate+: yes
do: Today photo offsets are wall-clock (RecordView). Make the recording clock stop during an interruption (call, Siri, alarm) and have photo offsets read that clock, so a picture taken after a call lands at its spoken place. Add corpus fixture `pic-after-interruption`. Test `InterruptionClockTests` (phone target).
check: `plan/mtest.sh InterruptionClockTests`

### Q480 [auto] (done) A: a transcript records its language mode; ⋯ › Transcribe again in Dutch / English
spec: C151 D46
needs: -
gate+: yes
do: Store the ASR language mode each transcript was made with (additive synced field) and add a plain ⋯ menu item "Transcribe again in Dutch" / "in English" (the other language) on phone and Mac, re-running ASR on that note only; the global setting stays the default. Add corpus fixture `voice-nl-recorded-in-english-mode`. Test `TranscribeAgainLanguageTests` (phone target).
check: `plan/mtest.sh TranscribeAgainLanguageTests`

### Q481 [auto] (done) A: text appended to a polished note shows up and only the new block gets polished
spec: C152 C223
needs: -
gate+: yes
do: Today an append writes only the raw transcript (MemoSaver) while every screen shows the polished body, so new words are invisible. Make appended text (Add recording, capture ramble) appear in the body he sees, mark the note for a pass, and have that pass polish only the new block (the earlier polish stays). Add corpus fixture `voice-en-append-after-polish`. Tests `AppendAfterPolishTests` (desktop) for the pass and a phone test for the visible body.
check: `grep -rqE "class AppendAfterPolishTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q482 [auto] (done) A: a Mac recording's word timings and diarization reach the phone, so karaoke works everywhere
spec: C245 R34
needs: -
gate+: yes
do: A phone take's word timings ride to the Mac as assets; a Mac take's do not ride back (R34). Write the Mac take's word timings (and diarization, when any) as the same synced MemoAsset kinds the phone uses, so the phone's karaoke works on Mac recordings. Test `MacTimingsAssetTests` (desktop): a Mac recording yields a wordTimings asset in the same shape the phone writes.
check: `grep -rqE "class MacTimingsAssetTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q483 [auto] (done) A: a spoken hashtag becomes a real tag, by rule
spec: C275 C85
needs: -
gate+: yes
do: By rule, never the model: "hashtag motivation" / "hashtag motivatie" → `#motivation` / `#motivatie` in the shown body; a run of spoken hashtags at the end becomes one tag line and a trailing "Okay" after them is dropped; the raw transcript keeps the words; custom vocab applies ("C and C" → CNC when CNC is a vocab word). One shared function in Skrift_Native/Shared used on both apps. Add synthetic corpus fixture `voice-spoken-hashtags` (EN + NL, including "Hashtag production. C and C hashtag design hashtag GFR. Okay." → `#production #cnc #design #gfr`). Test `SpokenHashtagTests` (desktop).
check: `grep -rqE "class SpokenHashtagTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q484 [tuur] (todo) B: mockup: sync health on the list and the note
spec: C155 D48 R47
needs: -
do: One clickable HTML page `Skrift_Native/SkriftDesktop/mocks/Q484-sync-health.html`, phone + Mac frames drawn from source: a CloudKit quota or sign-in failure showing on the notes list within a minute, a note marked "not synced yet", and an iCloud account switch noticed (syncing stops, it says so). Reuse existing banner/pill styles. One agent writes this file.
check: Tuur clicked through it and said go.

### Q485 [auto] (todo) B: build sync health per the mock
spec: C155 D48 R47
needs: Q484
gate+: yes
do: Build to `Skrift_Native/SkriftDesktop/mocks/Q484-sync-health.html` with Tuur's sign-off notes, phone and Mac: surface CloudKit quota / sign-in errors on the list within a minute, mark unsynced notes, detect an iCloud account switch, stop syncing and say so. Tests `SyncHealthTests` (desktop: injected quota error → state; account change → stopped).
check: `grep -rqE "class SyncHealthTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q486 [auto] (done) B: a phone edit newer than the Mac's polish sends the note back to pending
spec: C153
needs: -
gate+: yes
do: A raw edit whose stamp is newer than the row's `enhancedAt` sets the Mac row back to pending; the phone shows the edit until the next pass lands. Test `RawEditPendingTests` (desktop) including the post-run race (edit lands while a pass runs → the pass result is discarded, C38).
check: `grep -rqE "class RawEditPendingTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q487 [auto] (done) B: a purge deletes the polish row and every asset; an orphan Mac row is trashed
spec: C157
needs: -
gate+: yes
do: Today `NotesRepository` purge keeps the MemoEnhancement. A purge deletes the note's polish row and every MemoAsset; on the next sweep a Mac row whose memo is gone is trashed (never its vault file). Tests `PurgeCascadeTests` (phone) and `OrphanRowSweepTests` (desktop).
check: `grep -rqE "class OrphanRowSweepTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q488 [auto] (done) B: a picture removed from a note leaves the vault on the next export
spec: C158 C14 C54
needs: -
gate+: yes
do: When a picture marker is removed from the body, the next export removes that image file from the vault if it is ours and untouched (C54 ownership); the manifest entry stays (C14). Shared export code, both exporters. Add corpus fixture `pic-deleted-after-export`. Test `RemovedPictureExportTests` (desktop).
check: `grep -rqE "class RemovedPictureExportTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q489 [auto] (done) B: a roster change re-links every processed note once and re-exports the stale vault files
spec: C159 C283 D32
needs: -
gate+: yes
do: Add, alias or rename re-derives links for every processed row on the Mac once, deterministically, and re-exports the untouched vault files we own whose links or `people:` went stale; a rename rewrites `[[Old]]` → `[[New]]` and `people:`; edited or foreign files are never touched. Add corpus fixtures `voice-en-bruno-before-roster` ×3 and a rename golden. Test `RosterReexportTests` (desktop).
check: `grep -rqE "class RosterReexportTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q490 [auto] (done) B: changing a note's destination moves its exported file; retitle and folder switch never move files
spec: C163 C164
needs: -
gate+: yes
do: Destination change: remove the old file when ours and untouched, write the new one; if the old file was edited or moved, refuse and name the file; a Personal note never stays in the portfolio. A retitle never renames the exported file; switching the vault folder never moves old exports (new notes go to the new folder; Settings says so). Tests `DestinationMoveTests` and `RetitleNoRenameTests` (desktop).
check: `grep -rqE "class DestinationMoveTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q491 [auto] (done) B: frontmatter carries editedAt
spec: C284 D12
needs: -
gate+: yes
do: Add `editedAt` to the vault frontmatter beside `created` and `duration` on both exporters (shared compiler), stable key order. Update export goldens only through the harness record flag and register the change. Test `EditedAtFrontmatterTests` (desktop).
check: `grep -rqE "class EditedAtFrontmatterTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q492 [auto] (done) B: a query mid-sweep never sees a half-swapped note
spec: C294
needs: -
gate+: yes
do: Guard the reconcile sweep's await points against actor reentrancy so a query during a sweep sees each memo either before or after its swap, never between. Test `SweepReentrancyTests` (desktop): concurrency stress with interleaved reads.
check: `grep -rqE "class SweepReentrancyTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q493 [auto] (done) C: an ePub import reads every part or says exactly what it skipped
spec: C289
needs: -
gate+: yes
do: A whole ePub import ingests every section or reports which parts it skipped and why; no silent partial ingest. Fixture: an ePub with a deliberately malformed mid-file section. Test `EpubSkipReportTests` (phone).
check: `plan/mtest.sh EpubSkipReportTests`

### Q494 [auto] (done) C: a long book import shows real progress and whether you can keep listening
spec: C290
needs: -
gate+: yes
do: A long ePub/book import shows real progress (parts done / total) in the existing import UI style and states whether listening can continue meanwhile. Test `BookImportProgressTests` (phone).
check: `plan/mtest.sh BookImportProgressTests`

### Q495 [auto] (done) C: ePub upload is blocked while the same book is still transcribing
spec: C291
needs: -
gate+: yes
do: Block adding an ePub to a book whose whole-book transcription is still running, with a clear message. Test `EpubUploadGuardTests` (phone).
check: `plan/mtest.sh EpubUploadGuardTests`

### Q496 [auto] (done) C: the model download checks the real file, not a size floor
spec: C292
needs: -
gate+: yes
do: The model-download completeness check verifies the downloaded files by expected byte count or hash, not a size floor; a truncated-but-over-floor download counts as incomplete and resumes. Test `ResumableModelDownloaderTests` gains the truncated case (new test file if the existing class is protected: `ModelDownloadCompletenessTests`).
check: `grep -rqE "class ModelDownloadCompletenessTests\b" Skrift_Native -r`

### Q497 [auto] (done) C: importing several books at once never merges them
spec: C293
needs: -
gate+: yes
do: Multi-select import of several distinct books yields one library entry per book. Fixture with 2+ distinct books. Test `MultiBookImportTests` (phone).
check: `plan/mtest.sh MultiBookImportTests`

### Q498 [auto] (done) C: a book title never repeats its author
spec: C297
needs: -
gate+: yes
do: An imported book named "Title — Author" (with an author byline) becomes title "Title" with the author in its own field. Test `BookTitleAuthorTests` (phone).
check: `plan/mtest.sh BookTitleAuthorTests`

### Q499 [auto] (done) C: unsharing an audiobook leaves no phantom library entry
spec: C298
needs: -
gate+: yes
do: An entry with no local audio and no cloud carrier is removed at the next library load, with a log line. Test `PhantomEntryTests` (phone): unshare then reload shows no empty row.
check: `plan/mtest.sh PhantomEntryTests`

### Q500 [auto] (done) C: directory accessors create their folder once per launch
spec: C280
needs: -
gate+: yes
do: `AppPaths`-style accessors call createDirectory at most once per process launch (cache the result), never on every access, on both apps. Test `DirectoryCreateOnceTests` (desktop) counting createDirectory calls across repeated access.
check: `grep -rqE "class DirectoryCreateOnceTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q501 [auto] (done) copy-edit v2 keeps headings and bold labels
spec: C34 C116 D215
needs: Q478
gate+: yes
do: Found by Q478: the polish model drops a leading `# heading` and bold labels like `**Pros:**` (corpus applenote-headings-checklist), which D215 (keep his structure: checkboxes, lists) did not name. Hold heading lines and the markup of bold/italic spans aside the way `CopyEditV2.HeldLines` holds checkboxes and lists, or fall back to his words when the output loses a heading or a bold span. Also close the 40-word gap: the sentence-lost rule (<40 words) and the shrink guard (>40) leave exactly 40 uncovered; make one of them inclusive. Model outputs only through the existing recorder; never fabricate. Test `CopyEditV2FormattingTests` (desktop).
check: `grep -rqE "class CopyEditV2FormattingTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q502 [auto] (done) C: every unzip checks the CRC (book bundles, ePubs, the Mac harness)
spec: C107 C289
needs: Q493
gate+: yes
do: Found by Q493: ZIPFoundation's closure-based extract RETURNS the CRC and never compares it, so a corrupt .skriftbook or ePub entry unpacks silently. Every unzip in the app (BookBundle.unpack, the ePub reader, the Mac -aligncheck harness, any other ZIPFoundation `Archive` use: grep for `Archive(`) checks `crc == entry.checksum` and treats a mismatch as a failed import with an honest message (C75 style), never a partial unpack. One shared helper. Test `ZipCRCTests` (phone target) with a generated archive whose entry bytes were flipped.
check: `plan/mtest.sh ZipCRCTests`

### Q503 [tuur] (tuur) decide: ePub add while the book transcribes — blocked (C291, built) or waits (signed A0 mock)?
spec: C291 D-A0
needs: Q495
do: -
check: Tuur picked: (a) keep Q495 as built: adding an ePub to a book that is still being transcribed is blocked with "Add it now, it matches up on its own once the book is transcribed" shown only before the job starts; or (b) restore the signed audiobook A0 promise (add any time, the text waits and matches up after transcription) and drop C291. His answer lands in SPEC Decisions.

### Q504 [auto] (done) A: an appended block also turns spoken hashtags into tags
spec: C275 C152
needs: Q483
gate+: yes
do: Q481 polishes only an appended block (BatchRunner.polishAppendedBlock) and Q483 turns spoken hashtags into tags through SpokenHashtags.shownBody, but the append path never calls shownBody, so "hashtag x" said in an added recording stays words. Call shownBody on the spliced body in polishAppendedBlock (and the phone path if it has one). Test `AppendSpokenHashtagTests` (desktop).
check: `grep -rqE "class AppendSpokenHashtagTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q505 [auto] (done) the desktop suite stops crashing in SwiftData dealloc
spec: C5
needs: -
gate+: yes
do: The suite crash (8 in an hour on 2026-10-23, SwiftData SIGSEGV in _swift_release_dealloc under PipelineFile.*Status setters) is a SwiftData thread-confinement violation, not container lifetime (lane A disproved that: retaining both containers still crashed 1 of 30). BatchRunner is a plain nonisolated struct and the project builds in Swift 5.9 mode, so its async run executes on the global executor (SE-0338) while every caller (CopyEditCorpusRun, CopyEditV2Mac.corpusStep, ProcessingCoordinator) hands it PipelineFile rows from a main-actor ModelContext. Production bug too: the Mac's Process / Re-transcribe path. Make BatchRunner @MainActor (pure statics nonisolated); engines stay awaited on their own actors. Test `BatchRunnerIsolationTests` (desktop): run executes on the main thread with a probe transcriber. Report the stress loop numbers before and after (baseline 5 of 100).
check: `grep -rqE "class BatchRunnerIsolationTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q506 [auto] (done) B: every reader skips a polish older than his last raw edit
spec: C152 C261
needs: Q486
gate+: yes
do: Q486 added MemoEnhancement.isStale(for:) (transcriptEditedAt > enhancedAt), but only the phone note page honours it: the phone/iPad vault exporter, WallPrinter and the list cache still read the newest copy-edit, so a note he re-edited after the Mac polished it exports and lists the old polish. Route every reader of the Mac polish through one shared accessor that returns nil when stale (fall back to his raw, as the note page does). Test `StalePolishReadersTests` (phone, plan/mtest.sh).
check: `grep -rqE "class StalePolishReadersTests\b" Skrift_Native/SkriftMobile/SkriftMobileTests && plan/mtest.sh StalePolishReadersTests`

### Q507 [auto] (done) A: import writes rows on the main actor, file work stays off main
spec: C5 C294
needs: Q505
gate+: yes
do: Same bug class as Q505: `struct IngestService: Sendable` has nonisolated async funcs (ingestReport/ingestFile/ingestAudio/ingestVideo/ingestNote/attachPictures/...) that insert PipelineFile rows into the CALLER'S context (the Sidebar passes mainContext), so drag-drop and import write the main context off the main thread. Split it: file work (copy, video export, hashing) stays off main so the old P1 freeze does not come back, inserts and row mutations run on the main actor. Test `IngestIsolationTests` (desktop): every insert happens on the main thread with a probe.
check: `grep -rqE "class IngestIsolationTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q508 [auto] (done) B: a Mac edit to a conversation note survives every re-derivation
spec: C261 C47
needs: Q489
gate+: yes
do: Q489 made a Mac body edit survive re-derivation (MacEditRoundTrip.adopt / settle into pf.enhancedCopyedit, de-linked) but skips conversation rows, so his Mac edit to a diarized note is still replaced by the old polish on a phone tag edit, a roster change, the open-note refresh or Redo. Extend the same rule to conversation bodies (speaker turns keep their headers; de-link per turn). Test `MacConversationEditKeptTests` (desktop): each of the four paths keeps his edit in sanitised, the compile and the cloud copy.
check: `grep -rqE "class MacConversationEditKeptTests\\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q509 [auto] (done) B: the phone shows a Mac edit to a conversation note
spec: C47 C152
needs: Q508
gate+: yes
do: The phone renders a conversation note from memo.transcript, not the Mac's copy-edit, so his edit to a diarized note on the Mac reaches the cloud MemoEnhancement but never his phone's view (pre-existing; found in Q508). Show the current (non-stale, MemoEnhancement.current) copy-edit for conversations the same way as for prose, keeping speaker turns and the turn gutter. Test `PhoneConversationPolishTests` (phone, plan/mtest.sh).
check: `grep -rqE "class PhoneConversationPolishTests\\b" Skrift_Native/SkriftMobile/SkriftMobileTests && plan/mtest.sh PhoneConversationPolishTests`

### Q510 [auto] (done) reconcile v2 covers the whole sweep before the swap
spec: C52 C157 C187 C190 C191 C3
needs: Q429
gate+: yes
do: Q429's reconcile v2 left these on v1: triggers/coalescer/fresh context wiring (C52), MacMemoAuthor backfill + reflectTranscripts, orphan-row trash (C157, Q487's rules incl. the quarter refusal), the background first-enable ingest, the unrated projection (C187), the phone materializer (C190), the cloudKitMacSync default (C191). Bring each into Skrift_Native/Shared/ReconcileV2 (or name why it stays outside the sweep) so Q431's swap replaces v1 whole. Keep the one synchronous main-actor sweep and the harness green (v2 unexplained 0). Also close R44's gap: a later-stamped phone polish with identical text must not be refused. Total stays within 2,119 lines; append the changes to plan/reads/reconcile-v2.md.
check: `test $(cat Skrift_Native/Shared/ReconcileV2/*.swift | wc -l) -le 2119 && grep -qi 'C157' plan/reads/reconcile-v2.md && grep -qi 'C190' plan/reads/reconcile-v2.md`

### Q511 [auto] (todo) C: export v2 swap prerequisites (Mac row mirrors createdAt and his-title; iPad publisher can call v2)
spec: C64 C25 D12 C2
needs: Q434
gate+: yes
do: Q434's export v2 reads memo.createdAt and "he typed the title" off the memo in the harness, but the Mac's PipelineFile mirrors neither, and the iPad publisher (ObsidianPublisher) is not wired to v2. Mirror both onto the Mac row (pull-only, like Q491's editedAt; new stored PipelineFile fields need the ReconcileDiffHarnessTests.fields line + all v1-rows goldens re-recorded by flag — hand-merge D163; include reconcile v2's Reflect field table). Give ObsidianPublisher and VaultExporter a v2 path behind one switch that stays OFF (the swap, Q436, flips it after Tuur reads Q435). Test `ExportV2InputsTests` (desktop): a synced memo's createdAt and title origin reach ExportV2.Note on the Mac exactly as the harness builds them.
check: `grep -rqE "class ExportV2InputsTests\\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

## Log
- 2026-09-24 10:59 plan: 21 items
- 2026-09-24 11:25 Q1 -> doing — mockup out
- 2026-09-24 11:25 Q2 -> doing — mockup out
- 2026-09-24 11:25 Q5 -> doing — mockup out
- 2026-09-24 11:25 Q9 -> doing — worker out
- 2026-09-24 11:33 Q2 -> tuur — built @86142b9a — awaiting sitting
- 2026-09-24 11:39 Q1 -> tuur — built @54d80333 — awaiting sitting
- 2026-09-24 11:40 Q5 -> tuur — built @23c7662b — awaiting sitting
- 2026-09-24 11:49 Q9 -> done — gate pass @0efe1220
- 2026-09-24 12:05 Q2 -> done — signed as drawn: one row, cumulative, word-only (D134)
- 2026-09-24 12:05 Q1 -> done — signed with ✎ in the header beside Select (D134)
- 2026-09-24 12:05 Q5 -> done — A Shelf, tab named Library; captures stay in Notes (D134)
- 2026-09-24 12:05 Q22 added
- 2026-09-24 12:12 Q22 -> doing — mockup out
- 2026-09-24 12:12 Q6 -> doing — mockup out
- 2026-09-24 12:12 Q8 -> doing — worker out
- 2026-09-24 12:12 Q10 -> doing — worker out
- 2026-09-24 12:12 Q16 -> doing — worker out
- 2026-09-24 12:21 Q22 -> tuur — built @9f61c346 — awaiting sitting
- 2026-09-24 12:30 Q10 -> done — gate pass @4d7cb60a
- 2026-09-24 12:30 Q23 added
- 2026-09-24 12:30 Q6 -> tuur — built @1aed4a5d — awaiting sitting
- 2026-09-24 13:07 Q24 added
- 2026-09-24 13:07 Q8 -> done — gate pass @0d081cca
- 2026-09-24 13:48 Q16 -> stuck — check failed — .queue/Q16.check.log
- 2026-09-24 13:49 Q25 added
- 2026-09-24 13:49 Q25 -> doing — worker out
- 2026-09-24 13:58 Q22 -> doing — second pass: phone gets iPad/Mac verbs, grey background (D135)
- 2026-09-24 13:58 Q6 -> done — signed: tap opens, 'Add note' capture, jump-back (D135)
- 2026-09-24 14:05 Q22 -> tuur — built @2d8c92a7 — awaiting sitting
- 2026-09-24 14:11 Q25 -> done — gate pass @ec9282f1
- 2026-09-24 14:11 Q16 -> doing — re-accept after Q25 pin
- 2026-09-24 14:12 Q16 -> done — gate pass @4ce87f55
- 2026-09-24 14:18 Q22 -> doing — third pass: filter into chip bar, triage line → chip counts (D136)
- 2026-09-24 14:24 Q22 -> tuur — built @2c719317 — awaiting sitting
- 2026-09-24 14:42 Q22 -> done — signed third pass; Mark all as Passing removed (D137)
- 2026-09-24 14:42 Q26 added
- 2026-09-24 14:47 Q17 -> doing — worker out
- 2026-09-24 14:47 Q24 -> doing — worker out
- 2026-09-24 14:47 Q23 -> doing — worker out
- 2026-09-24 14:47 Q3 -> doing — mockup out
- 2026-09-24 14:47 Q4 -> doing — mockup out
- 2026-09-24 14:53 Q17 -> tuur — built @798e826f — awaiting sitting
- 2026-09-24 14:53 Q21 -> doing — worker out
- 2026-09-24 14:55 Q4 -> tuur — built @5b77e43f — awaiting sitting
- 2026-09-24 15:02 Q3 -> tuur — built @840e77be — awaiting sitting
- 2026-09-24 15:09 Q21 -> done — gate pass @9d3d583b
- 2026-09-24 15:13 Q23 -> done — gate pass @12a1ca1a
- 2026-09-24 15:13 Q11 -> doing — worker out (opus)
- 2026-09-24 15:32 Q11 -> done — gate pass @665a2aa9
- 2026-09-24 15:33 Q12 -> tuur — awaiting sitting: read plan/reads/body-v2.md + 3 rulings
- 2026-09-24 15:39 Q27 added
- 2026-09-24 15:39 Q27 -> doing — worker out
- 2026-09-24 15:51 Q24 -> todo — paused at Mac shutdown; committed 576e6c09 on wt/Q24 in /Users/tiurihartog/Hackerman/Skrift/.claude/worktrees/agent-a5293a1fb407468ae — proof (gate + mobile build) not seen; resume there, then accept by hand (D138: only the 5 approved protected tests may change)
- 2026-09-24 15:51 Q27 -> todo — paused at Mac shutdown; 6fb419de on wt/Q27 in /Users/tiurihartog/Hackerman/Skrift/.claude/worktrees/agent-a65afc383d479ab53 — two holes still open: success path deletes unmerged unreadable take files, quarantine deletes an existing copy; resume there with that fix
- 2026-09-24 20:06 Q27 -> doing — resumed after restart
- 2026-09-24 20:06 Q24 -> doing — resumed after restart
- 2026-09-24 20:18 Q3 -> done — signed: inline field, tap-twice remove, own row; case fold across library (D139)
- 2026-09-24 20:18 Q4 -> done — signed with all picks; unkept → Recently Deleted (D139)
- 2026-09-24 20:18 Q28 added
- 2026-09-24 20:18 Q29 added
- 2026-09-24 20:21 Q27 -> done — gate pass @94cab5b1
- 2026-09-24 20:28 Q12 -> done — read signed with D140 + D141
- 2026-09-24 20:28 Q30 added
- 2026-09-24 20:28 Q30 -> doing — worker out
- 2026-09-24 20:49 Q30 -> done — hand-merged (D141/D142 protected edits only), gate green @4e02061b
- 2026-09-24 20:59 Q13 -> doing — worker out
- 2026-09-24 20:59 Q18 -> doing — worker out
- 2026-09-24 21:15 Q18 -> done — gate pass @3dc27cbc
- 2026-09-24 21:17 Q24 -> done — hand-merged (D138 tests only), gate+check+phone build green @132ea364
- 2026-09-24 21:17 Q19 -> doing — worker out
- 2026-09-24 21:17 Q26 -> doing — worker out
- 2026-09-24 21:27 Q13 -> done — gate pass @a42cd2cb
- 2026-09-24 21:28 Q31 added
- 2026-09-24 21:28 Q31 -> doing — worker out
- 2026-09-24 21:33 Q19 -> stuck — merge conflict onto claude/session-3-f90c83
- 2026-09-24 21:33 Q19 -> doing — redispatch 1 on fresh base (conflict)
- 2026-09-24 21:36 Q19 -> done — gate pass @c25e6221
- 2026-09-24 21:36 Q32 added
- 2026-09-24 21:36 Q32 -> doing — worker out
- 2026-09-24 21:41 Q26 -> done — gate pass @e1658dc1
- 2026-09-24 21:42 Q32 -> done — gate pass @aff15db7
- 2026-09-24 21:42 Q33 added
- 2026-09-24 21:42 Q34 added
- 2026-09-24 21:42 Q33 -> doing — worker out
- 2026-09-24 21:42 Q34 -> doing — worker out
- 2026-09-24 21:51 Q34 -> done — gate pass @87faab1c
- 2026-09-24 21:54 Q31 -> done — gate pass @3b66bc50
- 2026-09-24 21:54 Q28 -> doing — worker out
- 2026-09-24 22:04 Q33 -> stuck — gate failed — .queue/Q33.gate.log
- 2026-09-24 22:05 Q33 -> doing — re-accept: prior gate run was INTERRUPTED, not red
- 2026-09-24 22:05 Q33 -> done — gate pass @ff543191
- 2026-09-24 22:07 Q35 added
- 2026-09-24 22:07 Q35 -> doing — worker out
- 2026-09-24 22:13 Q28 -> done — gate pass @b22f6538
- 2026-09-24 22:14 Q36 added
- 2026-09-24 22:14 Q36 -> doing — worker out
- 2026-09-24 22:14 Q29 -> doing — worker out (opus)
- 2026-09-24 22:17 Q20 -> tuur — awaiting sitting: xctrace on iPhone 13 + Mac
- 2026-09-24 22:23 Q35 -> done — gate pass @67bd1faf
- 2026-09-24 22:23 Q37 added
- 2026-09-24 22:23 Q14 -> doing — worker out
- 2026-09-24 22:50 Q29 -> done — gate pass @438ba0f9
- 2026-09-24 22:50 Q38 added
- 2026-09-24 22:50 Q39 added
- 2026-09-24 22:50 Q7 -> doing — worker out
- 2026-09-24 22:54 Q14 -> done — gate pass @edfbd51e
- 2026-09-24 22:54 Q14 -> done — gate pass @a2ca16c5
- 2026-09-24 22:54 Q40 added
- 2026-09-24 22:54 Q15 -> tuur — awaiting sitting: tag v1-body + delete v1 (Q14 done)
- 2026-09-24 22:54 Q40 -> doing — worker out (opus)
- 2026-09-24 22:55 Q36 -> done — gate pass @f5b7a0b7
- 2026-09-24 22:56 Q41 added
- 2026-09-24 22:56 Q37 -> doing — worker out
- 2026-09-24 23:06 Q40 -> done — gate pass @049a2722
- 2026-09-24 23:06 Q38 -> doing — worker out (opus)
- 2026-09-24 23:16 Q38 -> done — gate pass @6b216dbb
- 2026-09-24 23:17 Q42 added
- 2026-09-24 23:17 Q42 -> doing — worker out
- 2026-09-24 23:21 Q7 -> done — gate pass @5458caba
- 2026-09-24 23:23 Q37 -> done — gate pass @54474703
- 2026-09-24 23:23 Q43 added
- 2026-09-24 23:23 Q41 -> doing — worker out
- 2026-09-24 23:37 Q41 -> done — gate pass @f33acceb
- 2026-09-24 23:38 Q42 -> done — gate pass @78045573
- 2026-09-24 23:38 Q44 added
- 2026-09-24 23:38 Q45 added
- 2026-09-24 23:39 Q39 -> doing — worker out
- 2026-09-24 23:39 Q45 -> doing — worker out
- 2026-09-24 23:52 Q45 -> done — gate pass @355a60aa
- 2026-09-24 23:52 Q45 -> done — accepted
- 2026-09-24 23:58 Q39 -> done — gate pass @26db0381
- 2026-09-24 23:58 Q43 -> doing — worker out
- 2026-09-25 00:14 Q46 added
- 2026-09-25 00:14 Q43 -> todo — blocked by the Q45 test-target regression; redispatch after Q46 from wt/Q43 (agent-aa06e0ed307fea7ce)
- 2026-09-25 00:14 Q46 -> doing — worker out
- 2026-09-25 00:27 Q46 -> done — gate pass @75ef8ac1
- 2026-09-25 00:27 Q43 -> doing — resumed after Q46
- 2026-09-25 00:36 Q43 -> done — gate pass @58aee0f3
- 2026-09-25 00:36 Q44 -> doing — worker out
- 2026-09-25 00:52 Q44 -> done — gate pass @34d24430
- 2026-09-25 15:15 Q47 added
- 2026-09-25 15:15 Q48 added
- 2026-09-25 15:15 Q49 added
- 2026-09-25 18:45 Q15 -> doing — approved D146; worker out
- 2026-09-25 18:56 Q50 added
- 2026-09-25 18:56 Q51 added
- 2026-09-25 19:05 Q15 -> done — hand-merged (D146); tag v1-body=8581f09d; 6 protected test files lose v1-only cases
- 2026-09-25 19:07 Q52 added
- 2026-09-25 19:13 Q20 -> done — baseline in plan/perf-measured.md; rest dropped by D147
- 2026-09-25 19:24 Q53 added
- 2026-09-25 19:24 Q54 added
- 2026-09-25 19:24 Q55 added
- 2026-09-25 19:24 Q56 added
- 2026-09-25 19:24 Q57 added
- 2026-09-25 19:24 Q58 added
- 2026-09-25 19:24 Q52 -> dead — merged into Q53
- 2026-09-25 19:24 Q59 added
- 2026-09-25 19:50 Q60 added
- 2026-09-25 19:50 Q60 -> doing — worker out
- 2026-09-25 20:10 Q60 -> done — gate pass @dc1e645d
- 2026-09-25 20:10 Q61 added
- 2026-09-25 20:10 Q62 added
- 2026-09-25 20:23 Q47 -> doing — worker out
- 2026-09-25 20:23 Q56 -> doing — worker out
- 2026-09-25 20:23 Q50 -> doing — worker out
- 2026-09-25 20:37 Q50 -> stuck — gate failed — .queue/Q50.gate.log
- 2026-09-25 20:39 Q50 -> doing — re-accept: gate died at Resolve Package Graph while a worker ran the same desktop scheme
- 2026-09-25 20:40 Q57 -> doing — worker out
- 2026-09-25 20:42 Q50 -> tuur — built @95b9d312 — awaiting sitting
- 2026-09-25 20:43 Q49 -> doing — worker out
- 2026-09-25 20:43 Q56 -> done — gate pass @e673611d
- 2026-09-25 20:44 Q63 added
- 2026-09-25 20:49 Q53 -> doing — worker out
- 2026-09-25 20:49 Q47 -> stuck — touched protected: Skrift_Native/SkriftMobile/SkriftMobileTests/QuickNoteRouteTests.swift 
- 2026-09-25 20:50 Q47 -> doing — re-accept: block lacked gate+ for its required new test file
- 2026-09-25 20:53 Q47 -> done — gate pass @07f78c62
- 2026-09-25 20:53 Q64 added
- 2026-09-25 20:55 Q51 -> doing — worker out
- 2026-09-25 20:57 Q57 -> stuck — check failed — .queue/Q57.check.log
- 2026-09-25 20:58 Q57 -> doing — resumed: accept check plan/mtest.sh AudiobookCostTests -> TEST FAILED
- 2026-09-25 20:58 Q63 -> tuur — awaiting sitting
- 2026-09-25 20:58 Q64 -> tuur — awaiting sitting
- 2026-09-25 20:58 Q49 -> tuur — built @5f2e5e79 — awaiting sitting
- 2026-09-25 21:02 Q58 -> doing — worker out
- 2026-09-25 21:03 Q57 -> done — gate pass @a05a6166
- 2026-09-25 21:04 Q55 -> doing — worker out
- 2026-09-25 21:06 Q51 -> tuur — built @1b7bbf64 — awaiting sitting
- 2026-09-25 21:13 Q54 -> doing — worker out
- 2026-09-25 21:15 Q53 -> done — gate pass @6adb30d6
- 2026-09-25 21:23 Q62 -> doing — worker out: prepare the sitting sheet
- 2026-09-25 22:14 Q54 -> done — gate pass @2d3ceaab
- 2026-09-25 22:16 Q55 -> stuck — check failed — .queue/Q55.check.log
- 2026-09-25 22:18 Q58 -> done — gate pass @2c4f232f
- 2026-09-25 22:19 Q62 -> tuur — built @2a70ae57 — awaiting sitting
- 2026-09-25 22:19 Q55 -> doing — resumed: accept check -> TEST FAILED (LaunchWorkTests or RecoverySweepTests)
- 2026-09-25 22:19 Q48 -> doing — worker out
- 2026-09-25 22:25 Q55 -> stuck — check failed — .queue/Q55.check.log
- 2026-09-25 22:27 Q55 -> doing — re-accept: both reds were sim-launch collisions with Q48's UI tests; mtest.sh now locks the sim
- 2026-09-25 22:32 Q55 -> done — gate pass @cbe5bfb8
- 2026-09-25 22:38 Q48 -> done — gate pass @290dbdf4
- 2026-09-25 22:39 Q59 -> doing — worker out
- 2026-09-25 22:59 Q59 -> done — gate pass @5e014195
- 2026-09-25 22:59 Q61 -> doing — worker out
- 2026-09-25 23:32 Q61 -> done — gate pass @a6da1959
- 2026-09-26 07:28 Q49 -> done — Tuur 2026-09-26: option A (chips carry everything)
- 2026-09-26 07:28 Q51 -> done — Tuur 2026-09-26: import in groups of 10; rate each as it comes in, or skip import / delete it (→ revised mock)
- 2026-09-26 07:28 Q50 -> doing — Tuur 2026-09-26: page unresponsive, A/B/C cannot be clicked — mock agent fixing
- 2026-09-26 07:28 Q65 added
- 2026-09-26 07:28 Q66 added
- 2026-09-26 07:28 Q67 added
- 2026-09-26 07:29 Q67 -> doing — worker out
- 2026-09-26 07:29 Q65 -> doing — worker out
- 2026-09-26 07:30 Q50 -> tuur — built @eb0ee20d — awaiting sitting
- 2026-09-26 07:45 Q68 added
- 2026-09-26 07:46 Q68 -> doing — worker out
- 2026-09-26 07:47 Q65 -> done — gate pass @034877fc
- 2026-09-26 07:47 Q66 -> doing — worker out
- 2026-09-26 08:05 Q68 -> stuck — touched protected: Skrift_Native/SkriftDesktop/SkriftDesktopTests/CardChipParityTests.swift 
- 2026-09-26 08:05 Q68 -> doing — re-accept: block lacked gate+ for its required new test file
- 2026-09-26 08:06 Q68 -> stuck — merge conflict onto claude/session-3-ab263e
- 2026-09-26 08:08 Q68 -> doing — re-accept after merge onto d329b83a
- 2026-09-26 08:09 Q68 -> done — gate pass @c80da099
- 2026-09-26 08:10 Q67 -> tuur — built @db5b01d1 — awaiting sitting
- 2026-09-26 08:37 Q66 -> stuck — stopped by Tuur 2026-09-26 mid-proof; code + 4 screenshots on wt/Q66 (worktree agent-aa85e961dd572047e), check never run — resume by running the check there, then accept
- 2026-09-27 09:37 Q69 added
- 2026-09-27 09:50 Q50 -> done — Tuur 2026-09-27: A no (unlabelled balls, nobody will know), C no (takes part of the title), B probably best; make two versions: B, and today's layout squeezed vertically → Q70
- 2026-09-27 09:50 Q67 -> done — Tuur 2026-09-27: A = Next locked until all ten decided; B = never offer again (but 'Delete' is the wrong name); C = one note at a time; + resumable, import-so-far, Apple tags → Skrift tags → Q71
- 2026-09-27 09:50 Q70 added
- 2026-09-27 09:50 Q71 added
- 2026-09-27 09:50 Q72 added
- 2026-09-27 09:59 Q73 added
- 2026-09-27 09:59 Q70 -> doing — worker out
- 2026-09-27 09:59 Q72 -> doing — worker out
- 2026-09-27 10:07 Q72 -> done — report plan/research/apple-notes-export.md
- 2026-09-27 10:07 Q71 -> doing — worker out
- 2026-09-27 10:23 Q70 -> tuur — built @03631705 — awaiting sitting
- 2026-09-27 10:23 Q71 -> tuur — built @94beefe4 — awaiting sitting
- 2026-09-30 08:28 Q74 added
- 2026-09-30 08:38 Q70 -> done — Tuur 2026-09-30: version 1, the pill; tapping cycles Not rated → Passing → Useful → Important → Not rated (maybe a left-right drag); mocks lack the destination row → Q75
- 2026-09-30 08:38 Q71 -> done — Tuur 2026-09-30: route 1 (Mac Notes database, Full Disk Access is fine); locked notes stay behind; asks whether imported notes can be moved into an Apple Notes folder → Q76; drawings parked as an idea
- 2026-09-30 08:38 Q75 added
- 2026-09-30 08:38 Q76 added
- 2026-09-30 08:46 Q77 added
- 2026-09-30 08:49 Q75 -> doing — worker out
- 2026-09-30 08:49 Q76 -> doing — worker out
- 2026-09-30 08:49 Q73 -> doing — worker out
- 2026-09-30 08:57 Q69 -> doing — worker out
- 2026-09-30 08:57 Q76 -> done — report plan/research/apple-notes-folders.md
- 2026-09-30 09:01 Q73 -> done — gate pass @28c698be
- 2026-09-30 09:01 Q75 -> tuur — built @d8ca5308 — awaiting sitting
- 2026-09-30 09:09 Q69 -> done — gate pass @f74a3381
- 2026-09-30 09:09 Q78 added
- 2026-09-30 09:09 Q74 -> doing — worker out
- 2026-09-30 09:11 Q79 added
- 2026-09-30 09:12 Q64 -> tuur — built @305d47df — awaiting sitting
- 2026-09-30 09:25 Q74 -> done — gate pass @c5512188
- 2026-09-30 09:39 Q62 -> done — Tuur 2026-09-30: agrees with every group's recommendation (1–14); group 15 sharing/batch export: delete, rebuild later if wanted; unify phone↔Mac for 6, 8, 9, 11, 12, 13; audiobook quotes can't be tapped to seek
- 2026-09-30 09:39 Q80 added
- 2026-09-30 09:39 Q81 added
- 2026-09-30 09:39 Q82 added
- 2026-09-30 09:39 Q83 added
- 2026-09-30 10:06 Q75 -> done — Tuur 2026-09-30: tap to step (not drag); destination row as drawn, but renamed/reordered → Q84, Q85
- 2026-09-30 10:06 Q84 added
- 2026-09-30 10:06 Q85 added
- 2026-09-30 10:06 Q86 added
- 2026-09-30 10:23 Q86 -> doing — worker out
- 2026-09-30 10:23 Q79 -> doing — worker out
- 2026-09-30 10:23 Q77 -> doing — worker out
- 2026-09-30 10:39 Q77 -> done — gate pass @e832dae4
- 2026-09-30 10:39 Q84 -> doing — worker out
- 2026-09-30 10:44 Q78 -> doing — worker out
- 2026-09-30 10:45 Q86 -> tuur — built @ea492c1e — awaiting sitting
- 2026-09-30 10:47 Q86 -> done — Tuur 2026-09-30: "looks great, on both phone and Mac, I like it all" — the switch in the header
- 2026-09-30 10:47 Q87 added
- 2026-09-30 10:51 Q83 -> doing — worker out
- 2026-09-30 11:03 Q78 -> done — gate pass @8a2be1e6
- 2026-09-30 11:27 Q83 -> done — gate pass @4e3e1acf
- 2026-09-30 11:32 Q84 -> done — hand-merged (D156 rename: approved test/corpus renames)
- 2026-09-30 11:32 Q85 -> doing — worker out
- 2026-09-30 11:32 Q81 -> doing — worker out
- 2026-09-30 12:01 Q79 -> done — gate pass @3f97467c
- 2026-09-30 12:30 Q88 added
- 2026-09-30 12:34 Q85 -> done — gate pass @f7d923be
- 2026-09-30 12:35 Q81 -> done — gate pass @5c895bd3
- 2026-09-30 12:35 Q80 -> doing — worker out
- 2026-09-30 12:35 Q87 -> doing — worker out
- 2026-09-30 13:10 Q87 -> done — gate pass @8a4b29d2
- 2026-09-30 13:11 Q88 -> doing — worker out
- 2026-09-30 13:40 Q80 -> done — hand-merged (D154 approved deletions incl. their own tests)
- 2026-09-30 13:41 Q82 -> doing — worker out
- 2026-09-30 13:42 Q88 -> done — gate pass @1b7bc368
- 2026-09-30 14:17 Q82 -> done — gate pass @b17fe1e0
- 2026-09-30 15:38 Q89 added
- 2026-09-30 15:38 Q66 -> doing — redispatch (D158): fresh worker from the current head, WIP on wt/Q66 f4981cf0 as reference
- 2026-09-30 15:38 Q89 -> doing — worker out
- 2026-09-30 15:52 Q90 added
- 2026-09-30 16:08 Q89 -> done — hand-merged (D158 approved deletions incl. their own tests)
- 2026-09-30 16:08 Q90 -> doing — worker done; hand-merge queued
- 2026-09-30 16:11 Q90 -> done — hand-merged (D159 approved: import-floor tests changed to the unrated rule)
- 2026-09-30 16:17 Q66 -> done — gate pass @c0e6c5b4
- 2026-09-30 16:18 Q91 added
- 2026-10-01 15:33 Q92 added
- 2026-10-01 15:33 Q92 -> doing — worker out
- 2026-10-01 15:33 Q91 -> doing — worker out
- 2026-10-01 15:43 Q91 -> done — hand-merged (D148: UI tests follow the new filter chips)
- 2026-10-01 15:44 Q93 added
- 2026-10-01 15:46 Q92 -> done — gate pass @1b58587d
- 2026-10-01 15:47 Q93 -> doing — worker out
- 2026-10-01 15:58 Q93 -> done — gate pass @752a8467
- 2026-10-01 15:58 Q94 added
- 2026-10-01 15:58 Q94 -> doing — worker out
- 2026-10-01 16:20 Q94 -> done — gate pass @8b712145
- 2026-10-02 08:12 Q95 added
- 2026-10-02 08:12 Q96 added
- 2026-10-02 08:12 Q95 -> doing — worker out
- 2026-10-02 08:12 Q96 -> doing — worker out
- 2026-10-02 08:15 Q97 added
- 2026-10-02 08:15 Q97 -> doing — worker out
- 2026-10-02 08:16 Q98 added
- 2026-10-02 08:26 Q98 -> doing — worker out
- 2026-10-02 08:28 Q95 -> done — gate pass @56a66399
- 2026-10-02 08:50 Q97 -> done — gate pass @a032d4c0
- 2026-10-02 08:52 Q98 -> done — gate pass @4fbaccb6
- 2026-10-02 08:54 Q96 -> done — gate pass @69cc1cf2
- 2026-10-02 08:54 Q99 added
- 2026-10-02 08:55 Q99 -> doing — worker out
- 2026-10-02 09:06 Q99 -> done — gate pass @29d1067a
- 2026-10-02 10:41 Q100 added
- 2026-10-02 10:41 Q101 added
- 2026-10-02 10:41 Q102 added
- 2026-10-02 10:41 Q103 added
- 2026-10-02 10:41 Q104 added
- 2026-10-02 10:41 Q105 added
- 2026-10-02 10:41 Q106 added
- 2026-10-02 10:41 Q107 added
- 2026-10-02 10:41 Q108 added
- 2026-10-02 10:41 Q109 added
- 2026-10-02 10:41 Q110 added
- 2026-10-02 10:41 Q111 added
- 2026-10-02 10:41 Q112 added
- 2026-10-02 10:41 Q113 added
- 2026-10-02 10:41 Q114 added
- 2026-10-02 10:41 Q115 added
- 2026-10-02 10:41 Q116 added
- 2026-10-02 10:41 Q117 added
- 2026-10-02 10:41 Q118 added
- 2026-10-02 10:41 Q119 added
- 2026-10-02 10:41 Q120 added
- 2026-10-02 10:41 Q121 added
- 2026-10-02 10:41 Q122 added
- 2026-10-02 10:41 Q123 added
- 2026-10-02 10:41 Q124 added
- 2026-10-02 10:41 Q125 added
- 2026-10-02 10:41 Q126 added
- 2026-10-02 10:41 Q127 added
- 2026-10-02 10:41 Q128 added
- 2026-10-02 10:41 Q129 added
- 2026-10-02 10:41 Q130 added
- 2026-10-02 10:41 Q131 added
- 2026-10-02 10:41 Q132 added
- 2026-10-02 10:41 Q133 added
- 2026-10-02 10:41 Q134 added
- 2026-10-02 10:41 Q135 added
- 2026-10-02 10:41 Q136 added
- 2026-10-02 10:41 Q137 added
- 2026-10-02 10:41 Q138 added
- 2026-10-02 10:41 Q139 added
- 2026-10-02 10:41 Q140 added
- 2026-10-02 10:41 Q141 added
- 2026-10-02 10:41 Q142 added
- 2026-10-02 10:41 Q143 added
- 2026-10-02 10:41 Q144 added
- 2026-10-02 10:41 Q145 added
- 2026-10-02 10:41 Q146 added
- 2026-10-02 10:41 Q147 added
- 2026-10-02 10:41 Q148 added
- 2026-10-02 10:41 Q149 added
- 2026-10-02 10:41 Q150 added
- 2026-10-02 10:41 Q151 added
- 2026-10-02 10:41 Q152 added
- 2026-10-02 10:41 Q153 added
- 2026-10-02 10:41 Q154 added
- 2026-10-02 10:41 Q155 added
- 2026-10-02 10:41 Q156 added
- 2026-10-02 10:41 Q157 added
- 2026-10-02 10:41 Q158 added
- 2026-10-02 10:41 Q159 added
- 2026-10-02 10:41 Q160 added
- 2026-10-02 10:41 Q161 added
- 2026-10-02 10:41 Q162 added
- 2026-10-02 10:41 Q163 added
- 2026-10-02 10:41 Q164 added
- 2026-10-02 10:41 Q165 added
- 2026-10-02 10:41 Q166 added
- 2026-10-02 10:41 Q167 added
- 2026-10-02 10:41 Q168 added
- 2026-10-02 10:41 Q169 added
- 2026-10-02 10:41 Q170 added
- 2026-10-02 10:41 Q171 added
- 2026-10-02 10:41 Q172 added
- 2026-10-02 10:41 Q173 added
- 2026-10-02 10:41 Q174 added
- 2026-10-02 10:41 Q175 added
- 2026-10-02 10:41 Q176 added
- 2026-10-02 10:41 Q177 added
- 2026-10-02 10:41 Q178 added
- 2026-10-02 10:41 Q179 added
- 2026-10-02 10:41 Q180 added
- 2026-10-02 10:41 Q181 added
- 2026-10-02 10:41 Q182 added
- 2026-10-02 10:41 Q183 added
- 2026-10-02 10:41 Q184 added
- 2026-10-02 10:41 Q185 added
- 2026-10-02 10:41 Q186 added
- 2026-10-02 10:41 Q187 added
- 2026-10-02 12:19 Q188 added
- 2026-10-02 12:19 Q189 added
- 2026-10-02 12:19 Q190 added
- 2026-10-02 12:19 Q191 added
- 2026-10-02 12:19 Q192 added
- 2026-10-02 12:19 Q193 added
- 2026-10-02 12:19 Q194 added
- 2026-10-02 12:19 Q195 added
- 2026-10-02 12:19 Q196 added
- 2026-10-02 12:19 Q197 added
- 2026-10-02 12:19 Q198 added
- 2026-10-02 12:19 Q199 added
- 2026-10-02 12:19 Q200 added
- 2026-10-02 12:19 Q201 added
- 2026-10-02 12:19 Q202 added
- 2026-10-02 12:19 Q203 added
- 2026-10-02 12:19 Q204 added
- 2026-10-02 12:19 Q205 added
- 2026-10-02 12:19 Q206 added
- 2026-10-02 12:19 Q207 added
- 2026-10-02 12:19 Q208 added
- 2026-10-02 12:19 Q209 added
- 2026-10-02 12:19 Q210 added
- 2026-10-02 12:19 Q211 added
- 2026-10-02 12:19 Q212 added
- 2026-10-02 12:19 Q213 added
- 2026-10-02 12:19 Q214 added
- 2026-10-02 12:19 Q215 added
- 2026-10-02 12:19 Q216 added
- 2026-10-02 12:19 Q217 added
- 2026-10-02 12:19 Q218 added
- 2026-10-02 12:19 Q219 added
- 2026-10-02 12:19 Q220 added
- 2026-10-02 12:19 Q221 added
- 2026-10-02 12:19 Q222 added
- 2026-10-02 12:19 Q223 added
- 2026-10-02 12:19 Q224 added
- 2026-10-02 12:19 Q225 added
- 2026-10-02 12:19 Q226 added
- 2026-10-02 12:19 Q227 added
- 2026-10-02 12:19 Q228 added
- 2026-10-02 12:19 Q229 added
- 2026-10-02 12:19 Q230 added
- 2026-10-02 12:19 Q231 added
- 2026-10-02 12:19 Q232 added
- 2026-10-02 12:19 Q233 added
- 2026-10-02 12:19 Q234 added
- 2026-10-02 12:19 Q235 added
- 2026-10-02 12:19 Q236 added
- 2026-10-02 12:19 Q237 added
- 2026-10-02 12:19 Q238 added
- 2026-10-02 12:19 Q239 added
- 2026-10-02 12:19 Q240 added
- 2026-10-02 12:19 Q241 added
- 2026-10-02 12:19 Q242 added
- 2026-10-02 12:19 Q243 added
- 2026-10-02 12:19 Q244 added
- 2026-10-02 12:19 Q245 added
- 2026-10-02 12:19 Q246 added
- 2026-10-02 12:19 Q247 added
- 2026-10-02 12:19 Q248 added
- 2026-10-02 12:19 Q249 added
- 2026-10-02 12:34 Q100 -> doing — worker out
- 2026-10-02 12:34 Q163 -> doing — worker out
- 2026-10-02 12:34 Q138 -> doing — worker out
- 2026-10-02 12:43 Q237 -> doing — worker out
- 2026-10-02 12:46 Q236 -> doing — worker out
- 2026-10-02 12:49 Q100 -> done — gate pass @c5c0dc6b
- 2026-10-02 12:49 Q101 -> doing — worker out
- 2026-10-02 12:49 Q101 -> todo — held: 3 workers out
- 2026-10-02 12:50 Q101 -> doing — worker out
- 2026-10-02 12:56 Q138 -> done — gate pass @0985a481
- 2026-10-02 12:57 Q237 -> done — gate pass @12953ca6
- 2026-10-02 12:58 Q250 added
- 2026-10-02 12:58 Q131 -> doing — worker out
- 2026-10-02 13:01 Q102 -> doing — worker out
- 2026-10-02 13:01 Q163 -> done — gate pass @12420ad6
- 2026-10-02 13:01 Q236 -> stuck — touched protected: Skrift_Native/SkriftMobile/SkriftMobileTests/Q236ModelLoadingTests.swift 
- 2026-10-02 13:06 Q241 -> doing — worker out
- 2026-10-02 13:07 Q102 -> tuur — hand-merge: worktree agent-acedeea7d0147ca0b @d2c3acf0 (desktop gate green); protected phone test ProcessPileTests.testLockedNoteIsNotWaiting (:41) must flip to 'a locked note IS waiting' in the same merge
- 2026-10-02 13:07 Q112 -> doing — worker out
- 2026-10-02 13:07 Q236 -> done — gate pass @8f3f5cb6
- 2026-10-02 13:10 Q101 -> done — gate pass @0b3ebcc9
- 2026-10-02 13:11 Q113 -> doing — worker out
- 2026-10-02 13:13 Q131 -> done — gate pass @217cd128
- 2026-10-02 13:13 Q115 -> doing — worker out
- 2026-10-02 13:16 Q112 -> stuck — check failed — .queue/Q112.check.log
- 2026-10-02 13:16 Q251 added
- 2026-10-02 13:16 Q112 -> doing — re-accept: first check run was SIGTERM'd mid-build at load ~109 (env, not code)
- 2026-10-02 13:19 Q112 -> done — gate pass @48b4e8ed
- 2026-10-02 13:19 Q103 -> doing — worker out
- 2026-10-02 13:21 Q115 -> done — gate pass @1967b830
- 2026-10-02 17:28 Q189 -> doing — batch worker out
- 2026-10-02 17:28 Q190 -> doing — batch worker out
- 2026-10-02 17:28 Q191 -> doing — batch worker out
- 2026-10-02 17:28 Q192 -> doing — batch worker out
- 2026-10-02 17:28 Q197 -> doing — batch worker out
- 2026-10-02 17:28 Q198 -> doing — batch worker out
- 2026-10-02 17:28 Q200 -> doing — batch worker out
- 2026-10-02 17:28 Q205 -> doing — batch worker out
- 2026-10-02 17:28 Q208 -> doing — batch worker out
- 2026-10-02 17:28 Q215 -> doing — batch worker out
- 2026-10-02 17:28 Q210 -> doing — batch worker out
- 2026-10-02 17:31 Q241 -> done — gate pass @fc56ae38
- 2026-10-02 17:41 Q113 -> done — gate pass @0b16cb62
- 2026-10-02 17:42 Q210 -> tuur — hand-merge: deleting the dead toggles needs edits to protected SkriftDesktopTests (MemoCloudReconcilerTests, MemoCloudIngestTests, DiarizationTests, DiarizationOptInTests, processEverything:false lines) — not started; do it with the approval
- 2026-10-02 17:42 Q211 -> doing — batch worker out
- 2026-10-02 17:42 Q225 -> doing — batch worker out
- 2026-10-02 17:42 Q227 -> doing — batch worker out
- 2026-10-02 17:42 Q223 -> doing — batch worker out
- 2026-10-02 17:42 Q197 -> tuur — hand-merge: moves/deletes existing protected tests (BodyNormaliseMigrationTests, ParagrapherTests, TranscriptionLogicTests) — not started
- 2026-10-02 17:42 Q198 -> tuur — hand-merge: edits many protected tests (ASRPostProcessTests:26, durationMs constructions, QuoteSeekTests:28, KaraokeTrackTests:63, EPubTOCEntry/splitFragment, BPEMerge/ASRLanguageStore/VocabularyTermParsing) — not started
- 2026-10-02 17:42 Q139 -> doing — worker out (opus)
- 2026-10-02 17:43 Q190 -> tuur — hand-merge: BookAlignmentTests.swift:502,520,541 + OdysseyRealDataDiagnostics.swift:112 pass epubSignature: — not started
- 2026-10-02 17:43 Q191 -> todo — back to todo: needs Q190 (hand-merge)
- 2026-10-02 17:43 Q192 -> todo — back to todo: needs Q190 (hand-merge)
- 2026-10-02 17:43 Q116 -> doing — worker out (opus)
- 2026-10-02 17:44 Q103 -> done — gate pass @b290fdfe
- 2026-10-02 17:46 Q208 -> done — gate pass @1e71fa7e
- 2026-10-02 17:46 Q205 -> done — gate pass (batched with Q208)
- 2026-10-02 17:46 Q215 -> done — gate pass (batched with Q208)
- 2026-10-02 17:48 Q200 -> done — gate pass @b8a0b887
- 2026-10-02 17:48 Q189 -> stuck — merge conflict onto claude/skrift-parity-audit-133898
- 2026-10-02 17:48 Q189 -> doing — redispatch 2/3: rebase after CONFLICT
- 2026-10-02 17:52 Q134 -> doing — worker out (opus)
- 2026-10-02 17:55 Q104 -> doing — worker out (opus)
- 2026-10-02 17:56 Q189 -> done — gate pass @54e170e3
- 2026-10-02 18:02 Q119 -> doing — worker out (opus)
- 2026-10-02 18:04 Q211 -> tuur — hand-merge: SplitSpeakersTests.swift:107 (isWaitingSplit), PipelineFileTests.swift:17-18 (steps setter) — not started
- 2026-10-02 18:04 Q225 -> tuur — hand-merge: PublishCoordinatorTests:24,33, MemoAssetTests, MemoModelTests:65, LiveCaptionCadenceTests:47-63, LiveCaptionSettleTests:54-56, testSetAPIKeyRoundTrip — not started; needs Q211
- 2026-10-02 18:07 Q116 -> done — gate pass @d93a540d
- 2026-10-02 18:10 Q202 -> doing — batch worker out
- 2026-10-02 18:10 Q235 -> doing — batch worker out
- 2026-10-02 18:11 Q173 -> doing — worker out
- 2026-10-02 18:13 Q139 -> done — gate pass @870808e1
- 2026-10-02 18:15 Q154 -> doing — worker out (opus)
- 2026-10-02 18:16 Q227 -> done — gate pass @bd9c7de2
- 2026-10-02 18:16 Q223 -> done — gate pass (batched with Q227)
- 2026-10-02 18:21 Q134 -> done — gate pass @3c1f35f8
- 2026-10-02 18:27 Q133 -> doing — worker out
- 2026-10-02 18:27 Q204 -> doing — worker out
- 2026-10-02 18:27 Q231 -> doing — worker out
- 2026-10-02 18:28 Q104 -> done — gate pass @b47406ff
- 2026-10-02 18:29 Q173 -> done — gate pass @8c5d69ed
- 2026-10-02 18:29 Q193 -> doing — batch worker out
- 2026-10-02 18:29 Q195 -> doing — batch worker out
- 2026-10-02 18:30 Q154 -> done — gate pass @aa1511df
- 2026-10-02 18:32 Q202 -> done — gate pass @26948504
- 2026-10-02 18:32 Q235 -> done — gate pass (batched with Q202)
- 2026-10-02 18:37 Q224 -> doing — batch worker out
- 2026-10-02 18:37 Q218 -> doing — batch worker out
- 2026-10-02 18:37 Q219 -> doing — batch worker out
- 2026-10-02 18:38 Q119 -> done — gate pass @0b4a717f
- 2026-10-02 18:40 Q204 -> done — gate pass @751eb401
- 2026-10-02 18:40 Q231 -> done — gate pass (batched with Q204)
- 2026-10-02 18:41 Q252 added
- 2026-10-02 18:41 Q253 added
- 2026-10-02 18:41 Q254 added
- 2026-10-02 18:42 Q108 -> doing — worker out
- 2026-10-02 18:45 Q133 -> done — gate pass @0f289a69
- 2026-10-02 18:46 Q255 added
- 2026-10-02 18:50 Q218 -> tuur — hand-merge: edits protected VideoImportTests x4, QuickNoteRouteTests:40, QuickNoteHeaderQ88Tests:14,25 (+5 QuickNoteDraft.edited sites), MemoSaverTests x7, QuoteCaptureSaveTests:94, AutoCopyAndCameraFlipTests:115, LiveCaptionCadenceTests x9 — not started
- 2026-10-02 18:50 Q219 -> todo — waits on Q218 hand-merge
- 2026-10-02 18:50 Q106 -> doing — worker out
- 2026-10-02 18:53 Q117 -> doing — worker out
- 2026-10-02 18:53 Q224 -> done — gate pass @d5830340
- 2026-10-02 18:55 Q108 -> done — gate pass @ad3bfb83
- 2026-10-02 18:55 Q256 added
- 2026-10-02 18:57 Q178 -> doing — worker out
- 2026-10-02 19:05 Q193 -> done — gate pass @7c88717f
- 2026-10-02 19:05 Q195 -> done — gate pass (batched with Q193)
- 2026-10-02 19:07 Q153 -> doing — worker out (opus)
- 2026-10-02 19:08 Q182 -> doing — worker out
- 2026-10-02 19:10 Q117 -> done — gate pass @b6b0648d
- 2026-10-02 19:11 Q178 -> done — gate pass @8d8207e6
- 2026-10-02 20:58 Q157 -> doing — worker out
- 2026-10-02 20:58 Q147 -> doing — worker out
- 2026-10-02 20:58 Q148 -> doing — worker out
- 2026-10-02 20:59 Q109 -> tuur — awaiting sitting
- 2026-10-02 20:59 Q110 -> tuur — awaiting sitting
- 2026-10-02 20:59 Q111 -> tuur — awaiting sitting
- 2026-10-02 20:59 Q130 -> tuur — awaiting sitting
- 2026-10-02 20:59 Q145 -> tuur — awaiting sitting
- 2026-10-02 20:59 Q146 -> tuur — awaiting sitting
- 2026-10-02 20:59 Q170 -> tuur — awaiting sitting
- 2026-10-02 20:59 Q175 -> tuur — awaiting sitting
- 2026-10-02 20:59 Q251 -> tuur — awaiting sitting
- 2026-10-02 20:59 Q252 -> tuur — awaiting sitting
- 2026-10-02 20:59 Q253 -> tuur — awaiting sitting
- 2026-10-02 20:59 Q254 -> tuur — awaiting sitting
- 2026-10-02 20:59 Q256 -> tuur — awaiting sitting
- 2026-10-02 20:59 Q194 -> tuur — awaiting sitting (judgement or protected-test approval)
- 2026-10-02 20:59 Q201 -> tuur — awaiting sitting (judgement or protected-test approval)
- 2026-10-02 20:59 Q203 -> tuur — awaiting sitting (judgement or protected-test approval)
- 2026-10-02 20:59 Q206 -> tuur — awaiting sitting (judgement or protected-test approval)
- 2026-10-02 20:59 Q213 -> tuur — awaiting sitting (judgement or protected-test approval)
- 2026-10-02 20:59 Q216 -> tuur — awaiting sitting (judgement or protected-test approval)
- 2026-10-02 20:59 Q220 -> tuur — awaiting sitting (judgement or protected-test approval)
- 2026-10-02 20:59 Q221 -> tuur — awaiting sitting (judgement or protected-test approval)
- 2026-10-02 20:59 Q226 -> tuur — awaiting sitting (judgement or protected-test approval)
- 2026-10-02 20:59 Q229 -> tuur — awaiting sitting (judgement or protected-test approval)
- 2026-10-02 20:59 Q232 -> tuur — awaiting sitting (judgement or protected-test approval)
- 2026-10-02 20:59 Q249 -> tuur — awaiting sitting (judgement or protected-test approval)
- 2026-10-02 20:59 Q250 -> tuur — awaiting sitting (judgement or protected-test approval)
- 2026-10-02 20:59 Q128 -> doing — mockup agent out
- 2026-10-02 20:59 Q129 -> doing — mockup agent out
- 2026-10-02 21:00 Q182 -> done — gate pass @51314e73
- 2026-10-02 21:01 Q166 -> doing — worker out (opus)
- 2026-10-02 21:17 Q129 -> tuur — mock https://claude.ai/artifact/9SVbKnUhn2Re1wyUWcjiD5 (mocks/Q129-mac-reminders.html). Question: closing the Mac banner with ✕ — does it also silence iPhone/iPad, or only clicking it open? (mock treats both as acknowledging)
- 2026-10-02 21:17 Q144 -> doing — mockup agent out
- 2026-10-02 21:17 Q106 -> done — gate pass @c00d0e3e
- 2026-10-02 21:19 Q153 -> stuck — gate failed — .queue/Q153.gate.log
- 2026-10-02 21:19 Q153 -> doing — redispatch 2/3 (opus): first try interrupted by shutdown; accept GATE FAIL CaptureCompilerTests.testUrlCaptureSharedBlockAboveBody
- 2026-10-02 21:25 Q157 -> done — gate pass @743bb9e4
- 2026-10-02 21:26 Q177 -> doing — worker out
- 2026-10-02 21:27 Q168 -> doing — worker out (opus)
- 2026-10-02 21:30 Q147 -> done — gate pass @a01d5eb9
- 2026-10-02 21:30 Q148 -> done — gate pass (batched with Q147)
- 2026-10-02 21:33 Q186 -> doing — worker out (opus)
- 2026-10-02 21:35 Q166 -> done — gate pass @ac2db3e9
- 2026-10-02 21:38 Q160 -> doing — worker out
- 2026-10-02 21:40 Q121 -> doing — worker out
- 2026-10-02 21:41 Q153 -> done — gate pass @7041ea92
- 2026-10-02 21:41 Q128 -> tuur — mock https://claude.ai/artifact/Li25ppmZmB5fVXHYCdHZxa (mocks/Q128-mac-note-photos.html). Question: on the Mac, one click on a photo selects it (double-click/Space opens, movable like an Apple Notes block) — or opens the viewer straight away like a phone tap?
- 2026-10-02 21:41 Q152 -> doing — mockup agent out
- 2026-10-02 21:41 Q144 -> tuur — mock https://claude.ai/artifact/43NTAjUbFrB6C8vHw1NL3m (mocks/Q144-mac-weather-daypart.html). Question: type the OpenWeatherMap key on the Mac separately, or should the Mac pick it up from the phone over iCloud? (D92 'same key' reads both ways)
- 2026-10-02 21:41 Q162 -> doing — mockup agent out
- 2026-10-02 21:41 Q177 -> done — gate pass @ae6d8b32
- 2026-10-02 21:43 Q168 -> done — gate pass @4f272318
- 2026-10-02 21:43 Q257 added
- 2026-10-02 21:43 Q257 -> tuur — awaiting sitting
- 2026-10-02 21:49 Q114 -> doing — worker out
- 2026-10-02 21:55 Q186 -> tuur — hand-merge: wt/Q186 @03747cdd (agent-a4b84bff486dfc6c2); protected MacMultiAudioImportTests.testMixedBundleMergesTheClipsAndKeepsTheRest (:155-171) must change to created.count == 1 + annotation 'Buy milk' (C68 reverses the old gap). NEW synced Memo.includeAudioInExport -> CloudKit prod schema deploy at promotion.
- 2026-10-02 21:56 Q155 -> doing — worker out (opus)
- 2026-10-02 21:56 Q160 -> done — gate pass @3780d440
- 2026-10-02 21:59 Q132 -> doing — worker out
- 2026-10-02 22:02 Q121 -> done — gate pass @9a5f0868
- 2026-10-02 22:14 Q135 -> doing — worker out
- 2026-10-02 22:15 Q161 -> doing — worker out
- 2026-10-02 22:26 Q258 added
- 2026-10-02 22:26 Q258 -> doing — worker out (opus)
- 2026-10-02 22:26 Q132 -> done — gate pass @2f9c8593
- 2026-10-02 22:38 Q162 -> tuur — mock https://claude.ai/artifact/7wi8J65uDFC1oCu3d6H8AL (mocks/Q162-mac-icloud-state.html, not render-checked by the agent). Question: when sync is broken or off, should the list carry a capsule until it's fixed, or only Settings say so?
- 2026-10-02 22:38 Q259 added
- 2026-10-02 22:39 Q152 -> tuur — mock https://claude.ai/artifact/Xoe9ccY5K7yHysRUMyBxrP (mocks/Q152-fix-quote.html, not render-checked by the agent). Question: is one word at a time + 'Include next word' enough for real mishearings, or free-type over the whole quote?
- 2026-10-02 22:41 Q259 -> doing — worker out
- 2026-10-02 22:42 Q114 -> stuck — check failed — .queue/Q114.check.log
- 2026-10-02 22:42 Q114 -> doing — re-accept: first check hit the 900 s mtest alarm (sim contention), not a code failure
- 2026-10-02 22:43 Q258 -> tuur — hand-merge: code is correct per C25/C132; update protected expectations — MemoExporterTests.swift:59 ('Untitled Memo' -> C25 'Note'/'Voice note'), :70 (frontmatter title = user title first, not the Mac suggestion), PortfolioExportTests lines 77/96/140/156/171 (file from the generated title: the-bench-outside-cafe-garrett.md). Broken by Q153 d4e0c0ff. PHONE SUITE RED on these 7 until merged.
- 2026-10-02 22:43 Q143 -> doing — worker out
- 2026-10-02 22:54 Q125 -> doing — batch worker out
- 2026-10-02 22:54 Q126 -> doing — batch worker out
- 2026-10-02 22:54 Q155 -> done — gate pass @ad5823fc
- 2026-10-02 22:56 Q161 -> done — gate pass @c67f2462
- 2026-10-02 22:58 Q260 added
- 2026-10-02 22:59 Q127 -> doing — batch worker out
- 2026-10-02 22:59 Q118 -> doing — batch worker out
- 2026-10-02 22:59 Q114 -> done — gate pass @2b5564a4
- 2026-10-02 23:02 Q259 -> done — gate pass @7256e7f1
- 2026-10-02 23:02 Q135 -> stuck — merge conflict onto claude/skrift-parity-audit-133898
- 2026-10-02 23:02 Q135 -> doing — redispatch 2/3: rebase after CONFLICT
- 2026-10-02 23:04 Q143 -> done — gate pass @1146a36a
- 2026-10-02 23:04 Q261 added
- 2026-10-02 23:04 Q261 -> tuur — awaiting sitting
- 2026-10-02 23:04 Q262 added
- 2026-10-02 23:04 Q262 -> tuur — awaiting sitting
- 2026-10-02 23:07 Q122 -> doing — batch worker out
- 2026-10-02 23:07 Q165 -> doing — batch worker out
- 2026-10-02 23:10 Q125 -> done — gate pass @bd0ce8e9
- 2026-10-02 23:10 Q126 -> done — gate pass (batched with Q125)
- 2026-10-02 23:10 Q137 -> doing — worker out
- 2026-10-02 23:18 Q105 -> doing — batch worker out
- 2026-10-02 23:18 Q107 -> doing — batch worker out
- 2026-10-02 23:21 Q135 -> done — gate pass @1f414d95
- 2026-10-02 23:26 Q127 -> done — gate pass @becf6adc
- 2026-10-02 23:26 Q118 -> done — gate pass (batched with Q127)
- 2026-10-02 23:26 Q263 added
- 2026-10-02 23:26 Q263 -> tuur — awaiting sitting
- 2026-10-02 23:27 Q136 -> doing — worker out
- 2026-10-02 23:31 Q169 -> doing — worker out
- 2026-10-02 23:33 Q137 -> done — gate pass @c9aa9161
- 2026-10-02 23:36 Q122 -> done — gate pass @d6777391
- 2026-10-02 23:36 Q165 -> done — gate pass (batched with Q122)
- 2026-10-02 23:36 Q264 added
- 2026-10-02 23:36 Q264 -> tuur — awaiting sitting
- 2026-10-02 23:43 Q265 added
- 2026-10-02 23:44 Q265 -> doing — worker out
- 2026-10-02 23:44 Q156 -> doing — worker out
- 2026-10-02 23:46 Q105 -> done — gate pass @31ddc957
- 2026-10-02 23:46 Q107 -> done — gate pass (batched with Q105)
- 2026-10-02 23:51 Q266 added
- 2026-10-02 23:51 Q176 -> doing — batch worker out
- 2026-10-02 23:51 Q159 -> doing — batch worker out
- 2026-10-02 23:52 Q169 -> done — gate pass @a7313798
- 2026-10-02 23:52 Q136 -> stuck — merge conflict onto claude/skrift-parity-audit-133898
- 2026-10-02 23:52 Q267 added
- 2026-10-02 23:52 Q267 -> tuur — awaiting sitting
- 2026-10-02 23:52 Q136 -> doing — redispatch 2/3: rebase after CONFLICT
- 2026-10-03 00:01 Q136 -> done — gate pass @a76b4a1c
- 2026-10-03 00:05 Q141 -> doing — worker out
- 2026-10-03 00:05 Q142 -> doing — batch worker out (opus)
- 2026-10-03 00:05 Q158 -> doing — batch worker out (opus)
- 2026-10-03 00:05 Q265 -> stuck — merge conflict onto claude/skrift-parity-audit-133898
- 2026-10-03 00:06 Q265 -> doing — redispatch 2/3: rebase after CONFLICT
- 2026-10-03 00:11 Q180 -> doing — worker out
- 2026-10-03 00:11 Q156 -> done — gate pass @b2b132c1
- 2026-10-03 00:13 Q176 -> done — gate pass @4c1f0e10
- 2026-10-03 00:13 Q159 -> done — gate pass (batched with Q176)
- 2026-10-03 00:16 Q265 -> done — gate pass @c4fdfd42
- 2026-10-03 00:16 Q268 added
- 2026-10-03 00:16 Q268 -> tuur — awaiting sitting
- 2026-10-03 00:19 Q141 -> doing — redispatch 2/3: 1970 'date unknown' sentinel would start the fading clock at 1970 — anchor must fall back to import time
- 2026-10-03 00:22 Q183 -> doing — worker out
- 2026-10-03 00:23 Q142 -> stuck — merge conflict onto claude/skrift-parity-audit-133898
- 2026-10-03 00:23 Q142 -> doing — redispatch 2/3: rebase after CONFLICT
- 2026-10-03 00:25 Q181 -> doing — worker out
- 2026-10-03 00:26 Q184 -> doing — worker out
- 2026-10-03 00:27 Q180 -> done — gate pass @081a6075
- 2026-10-03 00:29 Q141 -> done — gate pass @dcf11ade
- 2026-10-03 00:35 Q142 -> done — gate pass @10fa881e
- 2026-10-03 00:35 Q158 -> done — gate pass (batched with Q142)
- 2026-10-03 00:36 Q269 added
- 2026-10-03 00:36 Q269 -> tuur — awaiting sitting
- 2026-10-03 00:36 Q270 added
- 2026-10-03 00:36 Q270 -> tuur — awaiting sitting
- 2026-10-03 00:36 Q271 added
- 2026-10-03 00:36 Q271 -> tuur — awaiting sitting
- 2026-10-03 00:36 Q179 -> doing — batch worker out
- 2026-10-03 00:36 Q217 -> doing — batch worker out
- 2026-10-03 00:38 Q124 -> doing — batch worker out
- 2026-10-03 00:38 Q123 -> doing — batch worker out
- 2026-10-03 00:40 Q187 -> doing — batch worker out
- 2026-10-03 00:40 Q185 -> doing — batch worker out
- 2026-10-03 00:42 Q183 -> done — gate pass @7f249478
- 2026-10-03 00:44 Q184 -> done — gate pass @f2f2f520
- 2026-10-03 00:46 Q181 -> done — gate pass @d142fcc7
- 2026-10-03 00:50 Q149 -> doing — batch worker out
- 2026-10-03 00:50 Q151 -> doing — batch worker out
- 2026-10-03 00:53 Q179 -> done — gate pass @2d870ea8
- 2026-10-03 00:53 Q217 -> done — gate pass (batched with Q179)
- 2026-10-03 00:53 Q140 -> doing — batch worker out
- 2026-10-03 00:53 Q164 -> doing — batch worker out
- 2026-10-03 00:55 Q124 -> done — gate pass @8c7fe9fa
- 2026-10-03 00:55 Q123 -> done — gate pass (batched with Q124)
- 2026-10-03 01:01 Q167 -> doing — batch worker out
- 2026-10-03 01:01 Q120 -> doing — batch worker out
- 2026-10-03 01:03 Q187 -> done — gate pass @82e249c2
- 2026-10-03 01:03 Q185 -> done — gate pass (batched with Q187)
- 2026-10-03 01:04 Q272 added
- 2026-10-03 01:04 Q272 -> tuur — awaiting sitting
- 2026-10-03 01:10 Q255 -> doing — batch worker out
- 2026-10-03 01:10 Q150 -> doing — batch worker out
- 2026-10-03 01:11 Q273 added
- 2026-10-03 01:12 Q260 -> doing — batch worker out (opus)
- 2026-10-03 01:12 Q266 -> doing — batch worker out (opus)
- 2026-10-03 01:14 Q167 -> tuur — hand-merge: protected WallPrinterTests.testEnqueueGateIsOrangeTierOncePerNote line 38 asserts shouldEnqueue(significance: 0.7) is FALSE — C233/C210 retire that; flip to TRUE (+ a 0.6 false case), then WallPrinter.shouldEnqueue -> ThreeBallScale.isTopStop and ImportanceDots (JournalHomeView.swift:404) -> ThreeBallScale.step(for:). Not started.
- 2026-10-03 01:14 Q207 -> doing — worker out
- 2026-10-03 01:14 Q140 -> done — gate pass @91bfe7d4
- 2026-10-03 01:14 Q164 -> done — gate pass (batched with Q140)
- 2026-10-03 01:18 Q151 -> done — gate pass @06242d37
- 2026-10-03 01:18 Q149 -> done — gate pass (batched with Q151)
- 2026-10-03 01:20 Q273 -> doing — batch worker out
- 2026-10-03 01:20 Q239 -> doing — batch worker out
- 2026-10-03 01:23 Q120 -> done — gate pass @378ef99c
- 2026-10-03 01:23 Q207 -> stuck — merge conflict onto claude/skrift-parity-audit-133898
- 2026-10-03 01:24 Q274 added
- 2026-10-03 01:24 Q274 -> tuur — awaiting sitting
- 2026-10-03 01:24 Q275 added
- 2026-10-03 01:24 Q275 -> tuur — awaiting sitting
- 2026-10-03 01:24 Q276 added
- 2026-10-03 01:24 Q276 -> tuur — awaiting sitting
- 2026-10-03 01:24 Q207 -> doing — redispatch 2/3: rebase after CONFLICT with Q120
- 2026-10-03 01:25 Q247 -> doing — worker out
- 2026-10-03 01:31 Q239 -> tuur — hand-merge: protected WayOutViewTests.swift:27-100 call the forwarders Q239 deletes (WayOutView.total, orderedByImminence, oneLiner) — drop cases WayOutSharedTests covers, retarget the rest. Not started.
- 2026-10-03 01:31 Q240 -> doing — batch worker out
- 2026-10-03 01:31 Q243 -> doing — batch worker out
- 2026-10-03 01:35 Q174 -> doing — worker out
- 2026-10-03 01:38 Q255 -> done — gate pass @9e204637
- 2026-10-03 01:38 Q150 -> done — gate pass (batched with Q255)
- 2026-10-03 01:38 Q171 -> doing — worker out
- 2026-10-03 01:40 Q207 -> done — gate pass @02ec480c
- 2026-10-03 01:43 Q214 -> doing — worker out
- 2026-10-03 01:44 Q273 -> done — gate pass @f373cd0e
- 2026-10-03 01:45 Q247 -> done — gate pass @83c88db1
- 2026-10-03 01:48 Q260 -> done — gate pass @66f18d12
- 2026-10-03 01:48 Q266 -> done — gate pass (batched with Q260)
- 2026-10-03 01:48 Q174 -> stuck — merge conflict onto claude/skrift-parity-audit-133898
- 2026-10-03 01:48 Q277 added
- 2026-10-03 01:48 Q278 added
- 2026-10-03 01:48 Q279 added
- 2026-10-03 01:48 Q277 -> tuur — parked for the sitting
- 2026-10-03 01:48 Q278 -> tuur — parked for the sitting
- 2026-10-03 01:48 Q279 -> tuur — parked for the sitting
- 2026-10-03 01:49 Q172 -> doing — dispatched (opus)
- 2026-10-03 01:50 Q240 -> done — no changes; gate pass @4f911148
- 2026-10-03 01:50 Q243 -> done — gate pass (batched with Q240)
- 2026-10-03 01:51 Q240 -> doing — re-accept: the first accept got a bad worktree path and merged nothing
- 2026-10-03 01:51 Q243 -> doing — re-accept with Q240
- 2026-10-03 01:52 Q212 -> doing — dispatched (sonnet), hand-merge expected
- 2026-10-03 01:54 Q240 -> done — gate pass @5d57762b
- 2026-10-03 01:54 Q243 -> done — gate pass (batched with Q240)
- 2026-10-03 01:55 Q174 -> done — gate pass @44c7aa8f
- 2026-10-03 01:56 Q214 -> tuur — needs hand-merge: wt/Q214 @3dff5149 (agent-a9617e2e31fef03e6) rewrites protected UploadTests.swift + MemoCloudIngestTests.swift; gate green 1431; approve then plan/hand-merge.sh
- 2026-10-03 01:57 Q188 -> doing — dispatched (sonnet), hand-merge likely
- 2026-10-03 02:00 Q171 -> done — gate pass @0943590e
- 2026-10-03 02:01 Q248 -> doing — dispatched (sonnet), hand-merge expected
- 2026-10-03 02:01 Q212 -> tuur — needs hand-merge: wt/Q212 @3415bbc5 (agent-a468155f352ccf2c9) ports protected WayOutRulesTests (3 duplicate tests deleted, covered by WayOutSharedTests), DesktopTrashTests, VideoIngestTests, MergedNoteDateAndParagraphsTests, VaultExporterTests; gate green 1437; approve then plan/hand-merge.sh
- 2026-10-03 02:01 Q280 added
- 2026-10-03 02:01 Q280 -> tuur — parked for the sitting
- 2026-10-03 02:06 Q228 -> doing — dispatched (sonnet), hand-merge likely
- 2026-10-03 02:15 Q172 -> done — gate pass @584aa5fd
- 2026-10-03 02:15 Q188 -> tuur — needs hand-merge: wt/Q188 @b65cab6f (agent-ac17ad7e4e274ca9a) deletes trim tests in protected AudiobookCaptureMathTests + QuoteCaptureSaveTests, drops snapped args in AlignedSentenceSourceTests + TextCaptureTests; gate green 1440; approve then plan/hand-merge.sh
- 2026-10-03 02:19 Q228 -> done — gate pass @22e678ab
- 2026-10-03 02:19 Q248 -> tuur — needs hand-merge: wt/Q248 @b993383c (agent-a95f4d0123ea15b77) ports tempDir()/corpus climb in 21 desktop + 3 phone protected test files to makeTempDir()/CorpusSeed.fixtureRoot, assertions unchanged; gate green 1444; approve then plan/hand-merge.sh
- 2026-10-03 02:19 Q245 -> doing — dispatched (sonnet)
- 2026-10-03 02:29 Q245 -> done — gate pass @1f0d456b
- 2026-10-03 02:29 Q281 added
- 2026-10-03 02:29 Q281 -> tuur — parked for the sitting
- 2026-10-03 08:35 Q188 -> done — hand-merged (Tuur blanket approval 2026-10-03: ports + deletions of tests of deleted code)
- 2026-10-03 08:37 Q248 -> done — hand-merged (Tuur blanket approval 2026-10-03: ports + deletions of tests of deleted code)
- 2026-10-03 08:39 Q190 -> todo — sitting 2026-10-03: approved (SPEC D163-D166)
- 2026-10-03 08:39 Q197 -> todo — sitting 2026-10-03: approved (SPEC D163-D166)
- 2026-10-03 08:39 Q198 -> todo — sitting 2026-10-03: approved (SPEC D163-D166)
- 2026-10-03 08:39 Q210 -> todo — sitting 2026-10-03: approved (SPEC D163-D166)
- 2026-10-03 08:39 Q211 -> todo — sitting 2026-10-03: approved (SPEC D163-D166)
- 2026-10-03 08:39 Q218 -> todo — sitting 2026-10-03: approved (SPEC D163-D166)
- 2026-10-03 08:39 Q225 -> todo — sitting 2026-10-03: approved (SPEC D163-D166)
- 2026-10-03 08:39 Q239 -> todo — sitting 2026-10-03: approved (SPEC D163-D166)
- 2026-10-03 08:39 Q250 -> todo — sitting 2026-10-03: approved (SPEC D163-D166)
- 2026-10-03 08:39 Q254 -> todo — sitting 2026-10-03: approved (SPEC D163-D166)
- 2026-10-03 08:39 Q267 -> todo — sitting 2026-10-03: approved (SPEC D163-D166)
- 2026-10-03 08:39 Q277 -> todo — sitting 2026-10-03: approved (SPEC D163-D166)
- 2026-10-03 08:39 Q229 -> todo — sitting 2026-10-03: approved (SPEC D163-D166)
- 2026-10-03 08:39 Q226 -> todo — sitting 2026-10-03: approved (SPEC D163-D166)
- 2026-10-03 08:39 Q213 -> todo — sitting 2026-10-03: approved (SPEC D163-D166)
- 2026-10-03 08:39 Q232 -> todo — sitting 2026-10-03: approved (SPEC D163-D166)
- 2026-10-03 08:39 Q201 -> todo — sitting 2026-10-03: approved (SPEC D163-D166)
- 2026-10-03 08:39 Q216 -> todo — sitting 2026-10-03: approved (SPEC D163-D166)
- 2026-10-03 08:39 Q194 -> todo — sitting 2026-10-03: approved (SPEC D163-D166)
- 2026-10-03 08:39 Q220 -> todo — sitting 2026-10-03: approved (SPEC D163-D166)
- 2026-10-03 08:39 Q221 -> todo — sitting 2026-10-03: approved (SPEC D163-D166)
- 2026-10-03 08:39 Q206 -> todo — sitting 2026-10-03: approved (SPEC D163-D166)
- 2026-10-03 08:39 Q175 -> todo — sitting 2026-10-03: approved (SPEC D163-D166)
- 2026-10-03 08:39 Q249 -> todo — sitting 2026-10-03: approved (SPEC D163-D166)
- 2026-10-03 08:39 Q203 -> dead — sitting 2026-10-03: kept, the headless -snapshot path depends on the Text renderer (D166)
- 2026-10-03 08:39 Q102 -> doing — sitting 2026-10-03: approved, rebasing (D163/D164)
- 2026-10-03 08:39 Q212 -> doing — sitting 2026-10-03: approved, rebasing (D163/D164)
- 2026-10-03 08:39 Q214 -> doing — sitting 2026-10-03: approved, rebasing (D163/D164)
- 2026-10-03 08:39 Q216 -> doing — dispatched (sonnet)
- 2026-10-03 08:39 Q206 -> doing — dispatched (sonnet)
- 2026-10-03 08:48 Q214 -> done — hand-merged (Tuur blanket approval D163: ports + deletions of tests of deleted code)
- 2026-10-03 08:50 Q216 -> tuur — built @412c88ae — awaiting sitting
- 2026-10-03 08:52 Q212 -> done — hand-merged (Tuur blanket approval D163: ports + deletions of tests of deleted code)
- 2026-10-03 08:56 Q216 -> done — gate pass @412c88ae (merged; accept parked it only for its tuur lane)
- 2026-10-03 08:58 Q206 -> tuur — built @0458e662 — awaiting sitting
- 2026-10-03 08:58 Q206 -> done — gate pass (merged; tuur lane)
- 2026-10-03 09:03 Q102 -> done — hand-merged (D164: locked note in the Process pile, test flipped at 3bb0ea5b)
- 2026-10-03 09:05 Q282 added
- 2026-10-03 09:05 Q283 added
- 2026-10-03 09:05 Q284 added
- 2026-10-03 09:05 Q285 added
- 2026-10-03 09:05 Q286 added
- 2026-10-03 09:05 Q287 added
- 2026-10-03 09:05 Q288 added
- 2026-10-03 09:05 Q289 added
- 2026-10-03 09:05 Q290 added
- 2026-10-03 09:05 Q291 added
- 2026-10-03 09:05 Q292 added
- 2026-10-03 09:05 Q293 added
- 2026-10-03 09:05 Q294 added
- 2026-10-03 09:05 Q295 added
- 2026-10-03 09:05 Q296 added
- 2026-10-03 09:05 Q297 added
- 2026-10-03 09:05 Q109 -> done — Tuur decided 2026-10-03 (SPEC D167-D177); build items added
- 2026-10-03 09:05 Q110 -> done — Tuur decided 2026-10-03 (SPEC D167-D177); build items added
- 2026-10-03 09:05 Q111 -> done — Tuur decided 2026-10-03 (SPEC D167-D177); build items added
- 2026-10-03 09:05 Q130 -> done — Tuur decided 2026-10-03 (SPEC D167-D177); build items added
- 2026-10-03 09:05 Q145 -> done — Tuur decided 2026-10-03 (SPEC D167-D177); build items added
- 2026-10-03 09:05 Q146 -> done — Tuur decided 2026-10-03 (SPEC D167-D177); build items added
- 2026-10-03 09:05 Q170 -> done — Tuur decided 2026-10-03 (SPEC D167-D177); build items added
- 2026-10-03 09:05 Q251 -> done — Tuur decided 2026-10-03 (SPEC D167-D177); build items added
- 2026-10-03 09:05 Q253 -> done — Tuur decided 2026-10-03 (SPEC D167-D177); build items added
- 2026-10-03 09:05 Q261 -> done — Tuur decided 2026-10-03 (SPEC D167-D177); build items added
- 2026-10-03 09:05 Q264 -> done — Tuur decided 2026-10-03 (SPEC D167-D177); build items added
- 2026-10-03 09:05 Q269 -> done — Tuur decided 2026-10-03 (SPEC D167-D177); build items added
- 2026-10-03 09:05 Q270 -> done — Tuur decided 2026-10-03 (SPEC D167-D177); build items added
- 2026-10-03 09:05 Q276 -> done — Tuur decided 2026-10-03 (SPEC D167-D177); build items added
- 2026-10-03 09:05 Q256 -> done — Tuur decided 2026-10-03 (SPEC D167-D177); build items added
- 2026-10-03 09:05 Q257 -> done — Tuur decided 2026-10-03 (SPEC D167-D177); build items added
- 2026-10-03 09:05 Q262 -> done — Tuur decided 2026-10-03 (SPEC D167-D177); build items added
- 2026-10-03 09:05 Q268 -> done — Tuur decided 2026-10-03 (SPEC D167-D177); build items added
- 2026-10-03 09:05 Q263 -> done — Tuur decided 2026-10-03 (SPEC D167-D177); build items added
- 2026-10-03 09:05 Q275 -> done — Tuur decided 2026-10-03 (SPEC D167-D177); build items added
- 2026-10-03 09:05 Q167 -> todo — Tuur approved the protected-test flip 2026-10-03 (D174)
- 2026-10-03 09:05 Q258 -> todo — Tuur approved the protected-test flip 2026-10-03 (D174)
- 2026-10-03 09:05 Q186 -> todo — Tuur approved the protected-test flip 2026-10-03 (D174)
- 2026-10-03 09:05 Q258 -> doing — dispatched (opus)
- 2026-10-03 09:05 Q167 -> doing — dispatched (sonnet)
- 2026-10-03 09:05 Q186 -> doing — resumed worker: rebase + D174 test flip
- 2026-10-03 09:05 Q289 -> doing — mockup agent (opus)
- 2026-10-03 09:05 Q296 -> doing — mockup agent (opus)
- 2026-10-03 09:12 Q289 -> tuur — mock https://claude.ai/artifact/QztPhoVwuVYKVouVVHBeUW (mocks/Q289-mac-recorder-pause.html). Question: after × asks 'Discard this recording?', does the take keep recording until you answer, or pause?
- 2026-10-03 09:13 Q296 -> tuur — mock https://claude.ai/artifact/QyS5vmkXQKAhSdK1QU1Cv5 (mocks/Q296-mac-checklist-button.html). Question: button on the left beside the notes-list toggle (A) or right before Process (B)? Also: multi-line selection -> checklist is NEW on both apps (shared rule change)
- 2026-10-03 09:23 Q288 -> doing — dispatched (sonnet)
- 2026-10-03 09:27 Q186 -> done — hand-merged (D174: one bundle rule, MacMultiAudioImportTests flipped to one note)
- 2026-10-03 09:28 Q298 added
- 2026-10-03 09:28 Q298 -> tuur — parked: promotion
- 2026-10-03 09:33 Q291 -> doing — dispatched (sonnet)
- 2026-10-03 09:37 Q288 -> done — gate pass @66c96c62
- 2026-10-03 09:41 Q295 -> doing — dispatched (sonnet)
- 2026-10-03 09:41 Q292 -> doing — dispatched (sonnet)
- 2026-10-03 09:45 Q282 -> doing — dispatched (opus)
- 2026-10-03 09:46 Q167 -> done — hand-merged (D174: legacy 0.7 is the top stop, WallPrinterTests:38 flipped)
- 2026-10-03 10:02 Q258 -> done — hand-merged (D174: phone export test expectations follow C25)
- 2026-10-03 10:04 Q291 -> done — gate pass @458c2286
- 2026-10-03 10:05 Q295 -> done — gate pass @7114ba58
- 2026-10-04 09:28 Q299 added
- 2026-10-04 09:28 Q299 -> doing — dispatched (opus)
- 2026-10-04 09:28 Q175 -> done — gate.sh runs plan/twin-check.sh (baseline 22 twins); gate GREEN 1480
- 2026-10-04 09:32 Q282 -> done — hand-merged (D163 ports + D167 Done = processed)
- 2026-10-04 09:33 Q213 -> doing — dispatched (sonnet)
- 2026-10-04 09:33 Q210 -> doing — dispatched (sonnet)
- 2026-10-04 09:41 Q242 -> doing — dispatched (sonnet)
- 2026-10-04 09:43 Q213 -> done — hand-merged (D163: ports + deletions of tests of deleted code (D166))
- 2026-10-04 09:48 Q285 -> doing — dispatched (sonnet)
- 2026-10-04 09:48 Q290 -> doing — dispatched (sonnet)
- 2026-10-04 09:49 Q210 -> done — hand-merged (D163: ports + deletions of tests of deleted code (D166); retry after a load-timing flake)
- 2026-10-04 09:51 Q292 -> done — hand-merged (D178: one conversation rule, audio only; call-site ports + fixture audioFilename)
- 2026-10-04 09:54 Q299 -> done — gate pass @549011fc
- 2026-10-04 09:57 Q242 -> done — gate pass @1a538aa9
- 2026-10-04 09:57 Q300 added
- 2026-10-04 09:57 Q301 added
- 2026-10-04 09:57 Q302 added
- 2026-10-04 09:57 Q302 -> tuur — parked: Dev check
- 2026-10-04 10:04 Q285 -> done — gate pass @ddaa3224
- 2026-10-04 10:04 Q303 added
- 2026-10-04 10:04 Q300 -> doing — dispatched (sonnet)
- 2026-10-04 10:04 Q209 -> doing — dispatched (sonnet)
- 2026-10-04 10:08 Q218 -> doing — dispatched (opus; recording code)
- 2026-10-04 10:15 Q290 -> done — gate pass @4b74344c
- 2026-10-04 10:15 Q304 added
- 2026-10-04 10:15 Q304 -> tuur — parked: Dev check
- 2026-10-04 10:24 Q303 -> doing — dispatched (sonnet; privacy)
- 2026-10-04 10:27 Q300 -> done — gate pass @83ca3b43
- 2026-10-04 10:29 Q209 -> stuck — touched protected: Skrift_Native/SkriftDesktop/SkriftDesktopTests/LaunchArgsTests.swift 
- 2026-10-04 10:32 Q277 -> doing — dispatched (sonnet)
- 2026-10-04 10:32 Q267 -> doing — dispatched (sonnet)
- 2026-10-04 10:33 Q209 -> done — gate pass @bc9cd66a
- 2026-10-04 10:35 Q284 -> doing — dispatched (sonnet)
- 2026-10-04 10:35 Q301 -> doing — dispatched (sonnet)
- 2026-10-04 10:38 Q218 -> done — hand-merged (D163: call-site ports in 12 phone test files)
- 2026-10-04 10:47 Q301 -> done — hand-merged (D163: deleted FeedbackStoreTests (test of deleted code))
- 2026-10-04 10:49 Q286 -> doing — dispatched (sonnet)
- 2026-10-04 10:49 Q293 -> doing — dispatched (sonnet)
- 2026-10-04 10:51 Q284 -> done — gate pass @0d6b3c55
- 2026-10-04 11:04 Q277 -> done — hand-merged (D163: test ports, Q247 shim deleted)
- 2026-10-04 11:16 Q293 -> done — gate pass @e2de0aea
- 2026-10-04 11:18 Q303 -> done — gate pass @16c975cd
- 2026-10-04 11:20 Q267 -> done — hand-merged (D163: PDF expectation follows shipped Q136 behaviour)
- 2026-10-04 11:20 Q283 -> doing — dispatched
- 2026-10-04 11:20 Q219 -> doing — dispatched
- 2026-10-04 11:24 Q286 -> done — gate pass @a19ad28a
- 2026-10-04 11:25 Q305 added
- 2026-10-04 11:25 Q306 added
- 2026-10-04 11:25 Q307 added
- 2026-10-04 11:25 Q308 added
- 2026-10-04 11:25 Q309 added
- 2026-10-04 11:25 Q309 -> tuur — parked: Dev check
- 2026-10-04 11:25 Q308 -> doing — dispatched (sonnet)
- 2026-10-04 11:30 Q308 -> done — gate pass @36465845
- 2026-10-04 11:37 Q305 -> doing — dispatched (sonnet); kit a15b4bb on main
- 2026-10-04 11:45 Q307 -> doing — dispatched (sonnet)
- 2026-10-04 11:57 Q283 -> done — gate pass @ae298ab0
- 2026-10-04 12:00 Q307 -> done — hand-merged (Tuur 2026-10-04: every dropped PDF, loose or in a folder, is a file capture)
- 2026-10-04 12:04 Q219 -> stuck — check failed — .queue/Q219.check.log
- 2026-10-04 12:06 Q305 -> done — hand-merged (D163: FeedbackPaletteTests replaced tests of deleted workaround code)
- 2026-10-04 12:11 Q219 -> done — gate pass @843830f7
- 2026-10-04 12:11 Q310 added
- 2026-10-04 12:11 Q306 -> doing — dispatched (sonnet; one-at-a-time)
- 2026-10-04 12:22 Q306 -> done — gate pass @bfea17c9
- 2026-10-04 12:22 Q294 -> doing — dispatched (sonnet; one-at-a-time)
- 2026-10-04 12:37 Q294 -> done — hand-merged (D163: deleted the test of the deleted label)
- 2026-10-04 12:37 Q199 -> doing — dispatched (opus; lifecycle; one-at-a-time)
- 2026-10-04 12:57 Q199 -> done — hand-merged (D163: ports + deletions of tests of deleted lifecycle states)
- 2026-10-04 12:57 Q196 -> doing — dispatched (sonnet; one-at-a-time)
- 2026-10-04 13:12 Q196 -> done — hand-merged (D163: call-site ports (onCommit closure arity))
- 2026-10-04 13:26 Q254 -> done — hand-merged (D163: deleted tests of the deleted helpers)
- 2026-10-04 13:26 Q250 -> doing — dispatched (sonnet; one-at-a-time)
- 2026-10-04 13:33 Q250 -> done — hand-merged (Tuur-approved (D163 sitting): test seeds the shape the phone writes)
- 2026-10-04 13:33 Q229 -> doing — dispatched (sonnet; one-at-a-time)
- 2026-10-04 14:07 Q229 -> done — hand-merged (D163/D166: deleted tests of the deleted dictation drain)
- 2026-10-04 14:07 Q310 -> doing — dispatched (opus; flaky OCR test; one-at-a-time)
- 2026-10-04 18:29 Q310 -> done — hand-merged (Tuur 2026-10-04: fake OCR in MemoSaverTests, real Vision in PhotoTextIndexerTests)
- 2026-10-04 18:29 Q220 -> doing — dispatched (opus; audio append; one-at-a-time)
- 2026-10-04 18:44 Q220 -> done — gate pass @cd1676d3
- 2026-10-04 18:44 Q311 added
- 2026-10-04 18:44 Q311 -> tuur — parked: device check
- 2026-10-04 18:44 Q226 -> doing — dispatched (sonnet; one-at-a-time)
- 2026-10-04 19:00 Q226 -> done — hand-merged (D163/D166: ports + deletion of the paired-mode test; unrated assertion kept and strengthened)
- 2026-10-04 19:00 Q201 -> doing — dispatched (sonnet; one-at-a-time)
- 2026-10-04 19:13 Q201 -> done — hand-merged (Tuur confirmed all prod ran the migration (D166); deleted its test, ported setup helpers)
- 2026-10-04 19:13 Q239 -> doing — dispatched (sonnet; one-at-a-time)
- 2026-10-04 19:29 Q239 -> done — hand-merged (D163: ports + deletion of duplicate WayOut cases covered by WayOutSharedTests)
- 2026-10-04 19:29 Q222 -> doing — dispatched (sonnet; one-at-a-time)
- 2026-10-04 19:44 Q222 -> done — gate pass @7ca0ae08
- 2026-10-04 19:44 Q238 -> doing — dispatched (sonnet; one-at-a-time)
- 2026-10-04 19:56 Q238 -> done — gate pass @c18dcb69
- 2026-10-04 19:57 Q211 -> doing — dispatched (sonnet; one-at-a-time)
- 2026-10-04 20:10 Q211 -> done — hand-merged (D163: call-site ports to the column properties)
- 2026-10-04 20:10 Q225 -> doing — dispatched (sonnet; one-at-a-time)
- 2026-10-04 20:27 Q225 -> done — hand-merged (D163: ports + deletion of tests of deleted members)
- 2026-10-04 20:27 Q197 -> doing — dispatched (sonnet; one-at-a-time)
- 2026-10-04 20:40 Q197 -> done — hand-merged (D163: v1 fixtures moved into the tests; deleted tests of deleted ImageMarkers/paragraphed)
- 2026-10-04 20:40 Q233 -> doing — dispatched (sonnet; one-at-a-time)
- 2026-10-04 20:55 Q233 -> done — hand-merged (D163: ports + deletion of assertions on the deleted Fold)
- 2026-10-04 20:55 Q230 -> doing — dispatched (sonnet; one-at-a-time)
- 2026-10-04 21:19 Q230 -> done — hand-merged (D163: deleted tests of deleted members)
- 2026-10-04 21:19 Q312 added
- 2026-10-04 21:20 Q312 -> doing — dispatched (opus; bisect; one-at-a-time)
- 2026-10-04 21:59 Q312 -> stuck — check failed — .queue/Q312.check.log
- 2026-10-04 22:04 Q312 -> done — gate pass @8127ebcc
- 2026-10-05 10:06 Q313 added
- 2026-10-05 10:06 Q313 -> doing — worker out
- 2026-10-05 10:38 Q313 -> done — gate pass @713e5a74
- 2026-10-05 17:47 Q314 added
- 2026-10-05 17:47 Q315 added
- 2026-10-05 17:47 Q316 added
- 2026-10-05 17:47 Q317 added
- 2026-10-05 17:47 Q314 -> doing — worker out
- 2026-10-05 17:47 Q315 -> doing — worker out
- 2026-10-05 17:47 Q316 -> doing — worker out
- 2026-10-05 17:47 Q317 -> doing — worker out
- 2026-10-05 18:10 Q314 -> done — gate pass @be142476
- 2026-10-05 18:27 Q317 -> stuck — merge conflict onto claude/skrift-parity-audit-133898
- 2026-10-05 18:39 Q318 added
- 2026-10-05 18:48 Q317 -> done — hand-merged @9a381dee (memoSetVersion conflict, kept Q314); BookNotesCountCacheTests + NoteOpenWorkTests exit 0, gate green
- 2026-10-05 21:30 Q315 -> done — hand-merged @8c58dd07 (one sync bump kept); ListDerivedCache/LaunchWork/NoteOpenWork/BookNotesCountCache tests + MemosListUITests 6/6 exit 0, gate green
- 2026-10-05 21:35 Q316 -> done — gate pass @798b3a3c
- 2026-10-05 21:48 Q319 added
- 2026-10-05 21:48 Q319 -> tuur — waiting on Tuur
- 2026-10-05 21:49 Q320 added
- 2026-10-05 21:49 Q318 -> doing — worker out
- 2026-10-05 21:49 Q320 -> doing — worker out
- 2026-10-05 22:06 Q318 -> done — gate pass @820268c1
- 2026-10-05 22:14 Q321 added
- 2026-10-05 22:18 Q322 added
- 2026-10-05 22:18 Q323 added
- 2026-10-05 22:18 Q321 -> doing — worker out
- 2026-10-05 22:30 Q320 -> done — gate pass @7d7325ec
- 2026-10-05 22:38 Q322 -> doing — worker out
- 2026-10-05 23:21 Q321 -> done — gate pass @7cba30df
- 2026-10-06 08:22 Q319 -> done — Tuur ran it 2026-10-05 22:05; results in plan/perf2/MEASURED.md (b179 re-run)
- 2026-10-06 08:28 Q322 -> done — hand-merged (Tuur approved 2026-10-06: NoteOpenWorkTests saves now change a field first (no-op save no longer bumps); classifier test nonce)
- 2026-10-06 08:29 Q323 -> doing — worker out
- 2026-10-06 08:53 Q323 -> done — gate pass @c92c3bb4
- 2026-10-06 12:11 Q324 added
- 2026-10-06 12:11 Q324 -> doing — worker out
- 2026-10-06 12:46 Q324 -> done — gate pass @ab1e6888
- 2026-10-06 18:02 Q325 added
- 2026-10-06 18:02 Q326 added
- 2026-10-06 18:02 Q327 added
- 2026-10-06 18:02 Q328 added
- 2026-10-06 18:02 Q329 added
- 2026-10-06 18:02 Q330 added
- 2026-10-06 18:02 Q128 -> done — signed 2026-10-06 (SPEC D182) — build queued
- 2026-10-06 18:02 Q144 -> done — signed 2026-10-06 (SPEC D182) — build queued
- 2026-10-06 18:02 Q162 -> done — signed 2026-10-06 (SPEC D182) — build queued
- 2026-10-06 18:02 Q289 -> done — signed 2026-10-06 (SPEC D182) — build queued
- 2026-10-06 18:02 Q152 -> done — dropped 2026-10-06 (SPEC D183): no Fix-quote verb, quote edits as text
- 2026-10-06 18:02 Q296 -> done — dropped 2026-10-06 (SPEC D181): no checklist button
- 2026-10-06 18:02 Q325 -> doing — worker out
- 2026-10-06 18:02 Q326 -> doing — worker out
- 2026-10-06 18:02 Q327 -> doing — worker out
- 2026-10-06 18:02 Q328 -> doing — worker out
- 2026-10-06 18:06 Q331 added
- 2026-10-06 18:06 Q129 -> done — dropped 2026-10-06 (SPEC D185): reminders removed everywhere
- 2026-10-06 20:16 Q328 -> done — gate pass @944c30bd
- 2026-10-06 20:17 Q327 -> done — gate pass @8a544cf8
- 2026-10-06 20:19 Q325 -> done — gate pass @04ddd331
- 2026-10-06 20:20 Q326 -> stuck — merge conflict onto claude/skrift-parity-audit-133898
- 2026-10-06 20:24 Q326 -> done — hand-merged @bf857303 (Q327 SettingsView/Snapshot conflict, both kept); gate green 1574 tests; full Mac build ok
- 2026-10-06 20:24 Q330 -> doing — worker out
- 2026-10-06 20:24 Q331 -> doing — worker out
- 2026-10-06 20:46 Q330 -> done — gate 46s @2971e6bc
- 2026-10-06 20:50 Q331 -> done — hand-merged (Tuur approved 2026-10-06: protected tests that only pinned reminders go with D185)
- 2026-10-06 20:52 Q329 -> doing — worker out
- 2026-10-06 20:52 Q287 -> doing — worker out
- 2026-10-06 20:52 Q190 -> doing — worker out
- 2026-10-06 21:21 Q190 -> done — gate 136s @a1b33b3c
- 2026-10-06 21:21 Q191 -> doing — worker out
- 2026-10-06 21:26 Q287 -> done — gate 114s @212d1a78
- 2026-10-06 21:26 Q332 added
- 2026-10-06 21:27 Q332 -> doing — worker out
- 2026-10-06 21:30 Q329 -> done — gate 89s @36026484
- 2026-10-06 21:38 Q191 -> stuck — touched protected: Skrift_Native/SkriftMobile/SkriftMobileTests/AudiobookSyncSidecarKindTests.swift 
- 2026-10-06 21:38 Q191 -> doing — re-accept: gate+ yes for the new wire-name test (additive)
- 2026-10-06 21:42 Q191 -> done — gate 46s @098066e5
- 2026-10-06 21:42 Q192 -> doing — worker out
- 2026-10-06 21:42 Q244 -> doing — worker out
- 2026-10-06 21:56 Q192 -> done — gate 103s @b4b27a38
- 2026-10-06 21:56 Q194 -> doing — worker out
- 2026-10-06 21:56 Q297 -> doing — worker out
- 2026-10-06 22:07 Q244 -> done — gate 79s @799248ff
- 2026-10-06 22:07 Q297 -> stuck — parked 2026-10-06: nothing writes a PDF page or podcast position yet (podcasts unbuilt), and the branch adds an unmocked PDF reader view — fold into the Library tab plan; branch wt/Q297 @86e8a062 kept
- 2026-10-06 22:10 Q194 -> done — gate 40s @a51f183c
- 2026-10-06 22:11 Q249 -> dead — obsolete 2026-10-06: plan/accept.sh is now the claude-skills copy (201ad0ff); protected approvals stay with hand-merge.sh
- 2026-10-06 22:11 Q198 -> doing — worker out
- 2026-10-06 22:11 Q234 -> doing — worker out
- 2026-10-06 22:11 Q232 -> doing — worker out
- 2026-10-06 22:26 Q332 -> tuur — awaiting Tuur: approve 3 protected test edits (VideoAssetPhoneTests/VideoAssetSyncTests flip to 'Personal movie stays', D188); branch wt/Q332 pushed; then hand-merge.sh
- 2026-10-06 22:26 Q198 -> doing — Mac shut down 2026-10-06 mid-run; branch wt/Q198 pushed — accept it if its check passes, else redispatch
- 2026-10-06 22:26 Q232 -> doing — Mac shut down 2026-10-06 mid-run; branch wt/Q232 pushed — accept it if its check passes, else redispatch
- 2026-10-06 22:26 Q234 -> doing — accept was running at shutdown 2026-10-06; branch wt/Q234 pushed — re-run plan/accept-chain.sh Q234 agent-ab384018a72622595
- 2026-10-06 22:26 Q234 -> done — gate 117s @eb8f5bc0
- 2026-10-06 22:27 Q198 -> doing — done-candidate, wt/Q198 pushed — accept next session
- 2026-10-06 22:27 Q232 -> doing — done-candidate, wt/Q232 pushed — accept next session; Live Activity device check owed
- 2026-10-07 08:43 Q50 -> dead — replaced by the Q75 note-header mock, built by Q85
- 2026-10-07 08:43 Q70 -> dead — replaced by the Q75 note-header mock, built by Q85
- 2026-10-07 08:43 Q67 -> dead — replaced by the Q71 triage v3 mock
- 2026-10-07 08:43 Q129 -> dead — dropped by Tuur 2026-10-06 (SPEC D181/D183/D185)
- 2026-10-07 08:43 Q152 -> dead — dropped by Tuur 2026-10-06 (SPEC D181/D183/D185)
- 2026-10-07 08:43 Q296 -> dead — dropped by Tuur 2026-10-06 (SPEC D181/D183/D185)
- 2026-10-07 08:45 Q333 added
- 2026-10-07 08:46 Q333 -> doing — worker out
- 2026-10-07 08:46 Q246 -> doing — worker out
- 2026-10-07 08:48 Q198 -> done — gate 52s @b957c27b
- 2026-10-07 08:52 Q232 -> done — gate 39s @b6e76c5d
- 2026-10-07 08:54 Q332 -> done — hand-merged (Tuur approved 2026-10-07: Q287's protected video tests flip to D188 (a Personal movie stays synced))
- 2026-10-07 08:59 Q246 -> done — gate 40s @9722b809
- 2026-10-07 09:00 Q334 added
- 2026-10-07 09:00 Q334 -> tuur — awaiting sitting
- 2026-10-07 09:06 Q333 -> done — gate 44s @f960a37a
- 2026-10-07 09:07 Q335 added
- 2026-10-07 09:07 Q335 -> tuur — awaiting sitting
- 2026-10-10 20:37 Q336 added
- 2026-10-10 20:37 Q336 -> doing — worker out
- 2026-10-10 20:59 Q336 -> done — gate 53s @87fe9d71
- 2026-10-11 10:09 Q337 added
- 2026-10-11 10:09 Q337 -> doing — worker out
- 2026-10-11 10:31 Q338 added
- 2026-10-11 10:31 Q339 added
- 2026-10-11 10:31 Q340 added
- 2026-10-11 10:31 Q274 -> done — Tuur 2026-10-11: mic off → one 'microphone is off / Open Settings' alert, re-enabled, recorded fine (silent-take half not tried)
- 2026-10-11 10:31 Q334 -> done — Tuur 2026-10-11: Lock Screen + Dynamic Island show; island waveform does not move → new item
- 2026-10-11 10:33 Q341 added
- 2026-10-11 10:34 Q338 -> doing — worker out
- 2026-10-11 10:34 Q339 -> doing — worker out
- 2026-10-11 10:34 Q340 -> doing — worker out
- 2026-10-11 11:11 Q337 -> done — hand-merged (Tuur approved 2026-10-11: AppleNotesTriageTests' undated case gets a fresh note id (import now dedupes by Notes id))
- 2026-10-11 11:12 Q340 -> stuck — gate weakened: modified Skrift_Native/SkriftMobile/SkriftMobileTests/TestLibrarySyncSeedTests.swift 
- 2026-10-11 11:13 Q340 -> doing — re-accept: new tests move to an added extension file
- 2026-10-11 11:29 Q339 -> done — gate 111s @7737e43c
- 2026-10-11 11:31 Q340 -> done — gate 54s @ef0ce0a5
- 2026-10-11 11:32 Q341 -> doing — worker out
- 2026-10-11 12:10 Q341 -> done — gate 131s @d5a65a1e
- 2026-10-11 12:17 Q338 -> done — hand-merged (Tuur approved 2026-10-11: protected tests that pin four destinations rewritten to Personal/Portfolio (D189), incl. destination-only lines in 10 more test files after the aliases were removed)
- 2026-10-11 12:21 Q342 added
- 2026-10-11 12:48 Q342 -> doing — worker out (FeedbackKit macOS on netcup-server main 640f04c)
- 2026-10-11 12:59 Q342 -> stuck — gate failed — .queue/Q342.gate.log
- 2026-10-11 13:00 Q342 -> doing — fix: shared privacy line (twin-check)
- 2026-10-11 13:13 Q342 -> done — gate 93s @536ae9fb
- 2026-10-11 20:25 Q343 added
- 2026-10-11 20:25 Q344 added
- 2026-10-11 20:25 Q345 added
- 2026-10-11 20:26 Q343 -> doing — worker out
- 2026-10-11 20:26 Q344 -> doing — worker out
- 2026-10-11 20:26 Q345 -> doing — worker out
- 2026-10-11 20:43 Q346 added
- 2026-10-11 21:00 Q343 -> done — gate 287s @4f6fca2d
- 2026-10-11 21:01 Q346 -> doing — worker out
- 2026-10-11 21:03 Q347 added
- 2026-10-11 21:07 Q344 -> stuck — check failed — .queue/Q344.check.log
- 2026-10-11 21:07 Q344 -> doing — re-accept: gate failed on MacMainThreadCostTests timing (204 ms vs 200 ms budget) while 3 builds ran; Q344 is phone-only
- 2026-10-11 21:07 Q348 added
- 2026-10-11 21:12 Q345 -> stuck — gate failed — .queue/Q345.gate.log
- 2026-10-11 21:12 Q345 -> doing — re-accept after the MacMainThreadCostTests check (see Q348)
- 2026-10-11 21:23 Q344 -> done — gate 169s @ba56c139
- 2026-10-11 21:26 Q345 -> done — gate 78s @88eae032
- 2026-10-11 21:27 Q347 -> doing — worker dispatched
- 2026-10-11 21:37 Q346 -> stuck — gate weakened: modified QUEUE.md 
- 2026-10-11 21:41 Q346 -> done — gate 105s @5337ba75
- 2026-10-11 21:43 Q347 -> done — gate 75s @741d03a1
- 2026-10-13 09:12 Q252 -> done — folded into Q298: release phone and Mac together, Mac upgrade tested on a copy first
- 2026-10-13 09:12 Q271 -> done — folded into Q298: release phone and Mac together, Mac upgrade tested on a copy first
- 2026-10-13 09:12 Q278 -> done — folded into Q298: release phone and Mac together, Mac upgrade tested on a copy first
- 2026-10-13 09:12 Q279 -> stuck — not a question for Tuur: Claude fixes the SPEC wording at the next /2-plan
- 2026-10-13 09:12 Q335 -> stuck — waits for the release to the real Skrift; Tuur does it then
- 2026-10-13 09:18 Q348 -> done — hand-merged (Tuur 2026-10-13: approve Q348 (timing limit 200 → 1000 ms))
- 2026-10-13 09:38 Q297 -> dead — folded into Q356 (jump-back on PDF and podcast notes)
- 2026-10-13 09:38 Q279 -> done — SPEC wording fixed at the 2026-10-13 /2-plan: C220 20 s, C199 ImportKinds, C145 long-audio offer
- 2026-10-13 09:38 Q221 -> tuur — hardware: needs Tuur's repro on the device before a fix
- 2026-10-13 09:39 plan: resync +22 (Q349–Q370: Library tab, Apple-Notes list + editor, Mac speed D191, release); Q298 needs Q366, Q335 needs Q370; SPEC C220 C199 C145 C229 reworded
- 2026-10-13 10:02 Q349 -> doing — worker out
- 2026-10-13 10:02 Q350 -> doing — worker out
- 2026-10-13 10:02 Q351 -> doing — worker out
- 2026-10-13 10:02 Q352 -> doing — worker out
- 2026-10-13 10:02 Q357 -> doing — worker out
- 2026-10-13 10:02 Q361 -> doing — worker out
- 2026-10-13 10:02 Q363 -> doing — worker out
- 2026-10-13 10:18 Q362 -> doing — worker out
- 2026-10-13 10:19 Q364 -> doing — worker out
- 2026-10-13 10:19 Q349 -> tuur — built @6d563ec6, gate 156s — awaiting sitting
- 2026-10-13 10:20 Q361 -> done — gate 62s @7cd49253
- 2026-10-13 10:20 Q365 -> doing — worker out
- 2026-10-13 10:21 Q365 -> todo — waits for a free worker slot (3 out)
- 2026-10-13 10:21 Q351 -> tuur — built @3924ad30, gate 34s — awaiting sitting
- 2026-10-13 10:21 Q363 -> done — gate 34s @c82c4c49
- 2026-10-13 10:22 Q350 -> tuur — built @03123eb9, gate 32s — awaiting sitting
- 2026-10-13 10:27 Q365 -> doing — worker out
- 2026-10-13 10:33 Q352 -> done — gate 78s @1f68eade
- 2026-10-13 10:33 Q357 -> done — gate pass (batched with Q352); ContinueListening grep clean
- 2026-10-13 10:37 Q353 -> doing — worker out
- 2026-10-13 10:37 Q354 -> doing — worker out
- 2026-10-13 10:38 Q364 -> done — gate 42s @ee44b630
- 2026-10-13 10:38 Q362 -> stuck — merge conflict onto claude/skrift-parity-audit-e9fa0c
- 2026-10-13 10:43 Q362 -> done — gate 73s @5201903e
- 2026-10-13 10:46 Q365 -> done — gate 71s @7cd7a694
- 2026-10-13 10:57 Q353 -> done — gate 65s @53c3e7a2
- 2026-10-13 10:57 Q371 added
- 2026-10-13 10:58 Q371 -> tuur — awaiting sitting
- 2026-10-13 11:02 Q354 -> stuck — merge conflict onto claude/skrift-parity-audit-e9fa0c
- 2026-10-13 11:09 Q354 -> done — gate 37s @14474740
- 2026-10-13 11:09 Q356 -> doing — worker out
- 2026-10-13 11:40 Q356 -> done — gate 43s @7e4d12e1
- 2026-10-13 11:41 Q372 added
- 2026-10-13 11:41 Q372 -> doing — worker out
- 2026-10-13 12:00 Q372 -> done — gate 53s @9e0f5cc0
- 2026-10-13 12:00 Q373 added
- 2026-10-13 12:00 Q373 -> tuur — awaiting sitting
- 2026-10-13 12:01 Q374 added
- 2026-10-13 12:01 Q375 added
- 2026-10-13 12:01 Q376 added
- 2026-10-13 12:02 Q374 -> doing — worker out
- 2026-10-13 12:06 Q349 -> tuur — built @70e9bd61, gate 114s — awaiting sitting
- 2026-10-13 12:08 Q374 -> done — gate 37s @d7c7e7c8
- 2026-10-13 13:22 Q349 -> tuur — built @7de0e5e5, gate 36s — awaiting sitting
- 2026-10-13 13:53 Q375 -> tuur — awaiting sitting (Dev 186 installed)
- 2026-10-13 13:53 Q376 -> tuur — awaiting sitting (Dev 186 installed)
- 2026-10-13 13:55 Q349 -> done — signed: 'this looks actually really fucking good' + D194 picks; unrated = grey dot + word in the importance spot
- 2026-10-13 13:55 Q358 -> doing — worker out
- 2026-10-13 14:04 Q351 -> done — signed D195: 'Yo, fucking cool, this is really sick. Nicely done' — share sheet asks Article or Note
- 2026-10-13 14:04 Q376 -> done — Tuur: the Mac never felt slow on his M4; optimise for slower Macs anyway (D195)
- 2026-10-13 14:04 Q350 -> todo — revise per D195: Personal pill beside the rating pill (phone + Mac), calmer header, smaller Aa buttons, add-person in the selection menu
- 2026-10-13 14:04 Q355 -> doing — worker out
- 2026-10-13 14:04 Q350 -> doing — mockup revision out
- 2026-10-13 14:08 Q373 -> done — Tuur: keep PDF-link / Episode-link / Audiobook-link / Article-link
- 2026-10-13 14:08 Q298 -> done — Tuur: yes — same-day release, Mac copy-test first, ~10 min in the CloudKit console at Q370
- 2026-10-13 14:15 Q272 -> done — Tuur: yes, keep all three
- 2026-10-13 14:15 Q350 -> tuur — built @5012ab7c, gate 50s — awaiting sitting
- 2026-10-13 14:17 Q371 -> done — hand-merged (Tuur 2026-10-13: approve Q371 (door assertions follow the built doors))
- 2026-10-13 14:18 Q350 -> done — signed D196: title above the meta line, New person further right, Export soft tint, audio choice in the Export confirmation, Split speakers in ⋯; 'mac frame looks a lot better'
- 2026-10-13 14:18 Q359 -> doing — worker out
- 2026-10-13 14:18 Q360 -> doing — worker out
- 2026-10-13 14:22 Q358 -> done — hand-merged (D163 blanket: protected tests only ported or deleted with the code they covered)
- 2026-10-13 14:23 Q377 added
- 2026-10-13 14:25 Q378 added
- 2026-10-13 14:25 Q379 added
- 2026-10-13 14:26 Q378 -> doing — mockup out
- 2026-10-13 14:40 Q380 added
- 2026-10-13 14:44 Q360 -> done — gate 43s @0303864c
- 2026-10-13 14:44 Q377 -> doing — worker out
- 2026-10-13 14:55 Q378 -> tuur — built @74e2fe13, gate 41s — awaiting sitting
- 2026-10-13 15:03 Q378 -> todo — revise per D198: tab placement options, Apple attach menu minus Record Audio, full-width text
- 2026-10-13 15:03 Q378 -> doing — mockup revision out
- 2026-10-13 15:03 Q377 -> done — hand-merged (Tuur D197 2026-10-13: Yesterday group — ListGroupingTests assertions follow the decided behaviour)
- 2026-10-13 15:10 Q381 added
- 2026-10-13 15:15 Q355 -> done — hand-merged (D163/Q371 pattern: LibraryShelfTests asserts the built article door; conductor resolved the Q371 conflict)
- 2026-10-13 15:17 Q378 -> tuur — built @07672798, gate 59s — awaiting sitting
- 2026-10-13 15:17 Q378 -> done — signed D198: full width, Apple attach menu minus Record Audio, tabs option A ('A')
- 2026-10-13 15:17 Q381 -> doing — worker out
- 2026-10-13 15:19 Q382 added
- 2026-10-13 15:24 Q359 -> done — gate 37s @bc9277f0
- 2026-10-13 15:25 Q379 -> doing — worker out
- 2026-10-13 15:25 Q382 -> doing — worker out
- 2026-10-13 15:37 Q381 -> stuck — merge conflict onto claude/skrift-parity-audit-e9fa0c
- 2026-10-13 15:51 Q381 -> done — gate 60s @346beda6
- 2026-10-13 15:55 Q382 -> done — gate 38s @9b6aa679
- 2026-10-13 16:07 Q379 -> done — gate 41s @d88dfa92
- 2026-10-13 16:08 Q380 -> doing — worker out
- 2026-10-13 16:08 Q383 added
- 2026-10-13 16:09 Q383 -> doing — worker out
- 2026-10-13 16:10 Q384 added
- 2026-10-13 16:10 Q385 added
- 2026-10-13 16:17 Q383 -> done — gate 38s @3c3cc8f2
- 2026-10-13 16:34 Q386 added
- 2026-10-13 16:37 Q380 -> done — hand-merged (D163 blanket: protected tests only deleted with the chip/quiet code or call sites ported)
- 2026-10-13 16:38 Q386 -> doing — worker out
- 2026-10-13 17:10 Q386 -> done — gate 58s @87984fff
- 2026-10-13 17:11 Q366 -> doing — worker out
- 2026-10-13 17:24 Q387 added
- 2026-10-13 17:26 Q387 -> doing — worker out
- 2026-10-13 17:26 Q384 -> doing — mockup out
- 2026-10-13 17:31 Q366 -> done — gate 132s @12486193
- 2026-10-13 17:36 Q388 added
- 2026-10-13 17:36 Q389 added
- 2026-10-13 17:36 Q389 -> tuur — awaiting sitting
- 2026-10-13 17:36 Q388 -> doing — worker out
- 2026-10-13 17:44 Q388 -> done — gate 73s @5efc20c4
- 2026-10-13 17:48 Q384 -> tuur — built @0480185c, gate 55s — awaiting sitting
- 2026-10-13 17:52 Q387 -> done — gate 37s @fa4ddbe0
- 2026-10-13 17:54 Q367 -> doing — worker out
- 2026-10-13 17:54 Q369 -> tuur — awaiting sitting (after Dev checks)
- 2026-10-13 18:05 Q367 -> done — gate 43s @73c96f38
- 2026-10-13 18:05 Q368 -> tuur — awaiting sitting: run plan/release/mac-store-copytest.sh after the Dev checks
- 2026-10-13 19:39 Q390 added
- 2026-10-13 19:39 Q384 -> done — signed D202: inline play, 420 pt cut, small by default + Set All Small/Large in ⋯; 'very good… nicely done'
- 2026-10-13 19:39 Q385 -> doing — worker out
- 2026-10-13 20:20 Q391 added
- 2026-10-13 20:24 Q385 -> done — gate 50s @b5d3cbac
- 2026-10-13 20:24 Q391 -> doing — worker out
- 2026-10-13 20:54 Q391 -> done — gate 42s @c82b12b7
- 2026-10-13 20:54 Q390 -> doing — worker out
- 2026-10-13 21:11 Q392 added
- 2026-10-13 21:14 Q390 -> done — gate 45s @281eb28b
- 2026-10-13 21:14 Q392 -> doing — worker out
- 2026-10-13 21:18 Q392 -> todo — paused by Tuur (gaming); wip on wt/Q392 in agent-a5b75aec6775df775 — redispatch from it
- 2026-10-13 22:19 Q392 -> doing — resumed: worker out from wt/Q392
- 2026-10-13 22:25 Q393 added
- 2026-10-13 22:25 Q394 added
- 2026-10-13 22:25 Q389 -> done — Tuur: Mac's newest phone note 25/26 Sep, phone newest 11 Oct; split ~when he moved to the iPhone 17 Pro → Q393 plans the merge
- 2026-10-13 22:27 Q393 -> doing — worker out
- 2026-10-13 22:27 Q395 added
- 2026-10-13 22:29 Q395 -> doing — worker out
- 2026-10-13 22:31 Q396 added
- 2026-10-13 22:35 Q392 -> done — gate 51s @048e2d66
- 2026-10-13 22:36 Q394 -> doing — worker out
- 2026-10-13 22:39 Q397 added
- 2026-10-13 22:39 Q398 added
- 2026-10-13 22:39 Q399 added
- 2026-10-13 22:39 Q400 added
- 2026-10-13 22:39 Q401 added
- 2026-10-13 22:40 Q401 -> tuur — awaiting Tuur
- 2026-10-13 22:42 Q397 -> doing — worker out
- 2026-10-13 22:43 Q393 -> done — gate skipped, no code: path touched @fdd6ec41
- 2026-10-13 22:50 Q395 -> done — gate 52s @e5e0d1ca
- 2026-10-13 22:51 Q396 -> doing — worker out
- 2026-10-13 22:54 Q397 -> done — gate 72s @92c75dd8
- 2026-10-13 22:55 Q398 -> doing — worker out
- 2026-10-13 23:00 Q396 -> done — gate 48s @0d72e984
- 2026-10-13 23:11 Q398 -> done — gate 53s @f4aa6b04
- 2026-10-13 23:11 Q399 -> doing — worker out
- 2026-10-13 23:11 Q400 -> doing — worker out
- 2026-10-13 23:22 Q399 -> done — gate 41s @31a892aa
- 2026-10-13 23:24 Q400 -> done — gate 46s @66274e7d
- 2026-10-14 09:28 Q402 added
- 2026-10-14 09:28 Q401 -> done — Tuur: not a fresh install — Quick Start or iCloud backup, doesn't remember which (D206)
- 2026-10-14 09:28 Q394 -> done — Dev 189 on Mac (grep 'Set All to Large') and iPhone 17 Pro (devicectl: com.skrift.mobile.dev 0.2.0 189; grep 'Add to this note')
- 2026-10-14 09:29 Q402 -> doing — worker out
- 2026-10-14 09:31 Q394 -> done — gate 50s @7766c1fe
- 2026-10-14 09:43 Q402 -> done — gate 46s @5d500b5e
- 2026-10-14 09:59 Q403 added
- 2026-10-14 09:59 Q404 added
- 2026-10-14 10:00 Q403 -> doing — worker out
- 2026-10-14 10:00 Q404 -> doing — worker out
- 2026-10-14 10:14 Q405 added
- 2026-10-14 10:16 Q405 -> doing — worker out
- 2026-10-14 10:23 Q403 -> done — gate 109s @536dc0c8
- 2026-10-14 10:30 Q405 -> done — gate 38s @3a3cbbb9
- 2026-10-14 10:33 Q404 -> done — gate 42s @0325fa15
- 2026-10-14 11:14 Q406 added
- 2026-10-14 11:15 Q406 -> doing — worker out
- 2026-10-14 11:25 Q406 -> done — gate 38s @3a783b7f
- 2026-10-14 12:05 Q407 added
- 2026-10-14 12:06 Q407 -> doing — worker out
- 2026-10-14 12:13 Q407 -> done — gate 39s @9458721b
- 2026-10-14 13:25 plan: resync from plan/reads/spec-coverage-2026-10-14.md — Q408–Q441 added (data-loss C261–C274, names C254–C260, targets 2–4, import layer); Q370 needs Q408–Q422; Q280 Q281 Q302 Q304 Q309 Q311 filled; Q17 Q64 on the iPhone 17 Pro
- 2026-10-14 14:19 Q408 -> doing — worker out
- 2026-10-14 14:19 Q418 -> doing — worker out
- 2026-10-14 14:19 Q411 -> doing — worker out
- 2026-10-14 14:31 Q409 -> doing — worker out
- 2026-10-14 14:36 Q410 -> doing — worker out
- 2026-10-14 14:36 Q411 -> done — gate 118s @cd682edc
- 2026-10-14 14:36 Q418 -> stuck — merge conflict onto claude/skrift-parity-audit-91f702
- 2026-10-14 14:37 Q408 -> stuck — merge conflict onto claude/skrift-parity-audit-91f702
- 2026-10-14 14:37 Q442 added
- 2026-10-14 14:41 Q418 -> done — gate 135s @33256737
- 2026-10-14 14:44 Q419 -> doing — worker out
- 2026-10-14 14:44 Q412 -> doing — worker out
- 2026-10-14 14:45 Q408 -> done — gate 57s @4f93d12d
- 2026-10-14 14:45 Q442 -> tuur — awaiting sitting
- 2026-10-14 14:47 Q409 -> done — gate 110s @e8fe0df6
- 2026-10-14 14:52 Q413 -> doing — worker out
- 2026-10-14 14:52 Q414 -> doing — worker out
- 2026-10-14 14:52 Q443 added
- 2026-10-14 14:54 Q412 -> done — gate 77s @4f9fbf99
- 2026-10-14 14:55 Q420 -> doing — worker out
- 2026-10-14 14:56 Q410 -> done — gate 55s @87312352
- 2026-10-14 14:56 Q443 -> tuur — awaiting sitting
- 2026-10-14 14:58 Q419 -> done — gate 104s @32f35397
- 2026-10-14 14:58 Q421 -> doing — worker out
- 2026-10-14 15:00 Q415 -> doing — worker out
- 2026-10-14 15:07 Q413 -> done — gate 114s @95280a27
- 2026-10-14 15:08 Q416 -> doing — worker out
- 2026-10-14 15:12 Q422 -> doing — worker out
- 2026-10-14 15:13 Q414 -> done — gate 174s @67c0b41a
- 2026-10-14 15:13 Q417 -> doing — worker out
- 2026-10-14 15:14 Q420 -> done — gate 69s @4eedce8a
- 2026-10-14 15:15 Q421 -> done — gate 74s @71a62049
- 2026-10-14 15:22 Q415 -> done — gate 120s @0f1a9b79
- 2026-10-14 15:23 Q438 -> doing — worker out
- 2026-10-14 15:24 Q428 -> doing — worker out
- 2026-10-14 15:25 Q416 -> done — gate 65s @f4510f09
- 2026-10-14 15:26 Q422 -> done — gate 46s @082e4d42
- 2026-10-14 15:29 Q433 -> doing — worker out
- 2026-10-14 15:30 Q438 -> done — gate 43s @206f215b
- 2026-10-14 15:32 Q439 -> doing — worker out
- 2026-10-14 15:33 Q417 -> done — gate 41s @51628e50
- 2026-10-14 15:34 Q444 added
- 2026-10-14 15:39 Q444 -> doing — worker out
- 2026-10-14 15:41 Q428 -> done — gate 114s @3c6001f4
- 2026-10-14 15:44 Q423 -> doing — worker out
- 2026-10-14 15:45 Q439 -> done — gate 55s @f3af339d
- 2026-10-14 15:46 Q445 added
- 2026-10-14 15:47 Q433 -> done — hand-merged (dest-* fixtures re-based to D189 as Q433's do: asked; Tuur confirmed the resync 2026-10-14)
- 2026-10-14 15:49 Q440 -> doing — worker out
- 2026-10-14 15:49 Q445 -> doing — worker out
- 2026-10-14 15:49 Q444 -> done — gate 43s @641560e0
- 2026-10-14 15:53 Q446 added
- 2026-10-14 15:55 Q445 -> done — hand-merged (two pic-at-start goldens re-recorded as Q445's do: asked)
- 2026-10-14 15:56 Q446 -> doing — worker out
- 2026-10-14 16:17 Q447 added
- 2026-10-14 16:17 Q447 -> tuur — awaiting sitting
- 2026-10-14 16:18 Q440 -> done — gate 59s @9a52fa53
- 2026-10-14 16:18 Q441 -> doing — worker out
- 2026-10-14 16:20 Q446 -> done — gate 49s @913d4c8c
- 2026-10-14 16:29 Q448 added
- 2026-10-14 16:30 Q441 -> done — gate 57s @c3d4c3fb
- 2026-10-14 16:30 Q448 -> doing — worker out
- 2026-10-14 16:40 Q448 -> done — gate 53s @a68e370b
- 2026-10-14 16:41 Q423 -> done — gate 50s @e2ce3b28
- 2026-10-14 16:41 Q424 -> doing — worker out
- 2026-10-14 17:07 Q424 -> done — gate 53s @2a4feffb
- 2026-10-14 17:08 Q425 -> tuur — awaiting sitting
- 2026-10-15 08:39 Q449 added
- 2026-10-15 08:39 Q450 added
- 2026-10-15 08:39 Q451 added
- 2026-10-15 08:39 Q452 added
- 2026-10-15 08:39 Q453 added
- 2026-10-15 08:39 Q454 added
- 2026-10-15 08:39 Q455 added
- 2026-10-15 08:39 Q456 added
- 2026-10-15 08:40 Q442 -> done — Tuur 2026-10-15: flip both tests, yes — applied by Q450
- 2026-10-15 08:40 Q425 -> todo — Tuur 2026-10-15: no — don't fall back on any dropped word; re-read after Q449 (D209)
- 2026-10-15 08:40 Q311 -> todo — Tuur 2026-10-15: fails — playback stops at the join until the note is reopened → Q453, recheck after
- 2026-10-15 08:40 Q64 -> done — Tuur 2026-10-15: pencil opens a fresh note, keyboard bar stays (layout issues → Q451/Q452)
- 2026-10-15 08:40 Q280 -> done — Tuur 2026-10-15: they look good
- 2026-10-15 08:40 Q281 -> done — Tuur 2026-10-15: voice memo fine; video lands as a Photo card → Q454; share sheet + confirmation ugly → Q455
- 2026-10-15 08:40 Q221 -> done — Tuur 2026-10-15: zoom very jumpy, fake drag pill, doubled status → Q456; BT mic via in-app feedback
- 2026-10-15 08:40 Q375 -> done — Tuur 2026-10-15: the library looks really good (PDF highlight question answered in chat)
- 2026-10-15 08:42 Q455 -> doing — worker out
- 2026-10-15 08:42 Q449 -> doing — worker out
- 2026-10-15 08:42 Q451 -> doing — worker out
- 2026-10-15 08:50 Q457 added
- 2026-10-15 08:50 Q458 added
- 2026-10-15 08:50 Q459 added
- 2026-10-15 08:50 Q460 added
- 2026-10-15 08:50 Q461 added
- 2026-10-15 08:50 Q462 added
- 2026-10-15 08:50 Q463 added
- 2026-10-15 08:50 Q447 -> done — Tuur 2026-10-15: (a) never a title, every door → D211
- 2026-10-15 08:57 Q449 -> done — hand-merged (Tuur D209 2026-10-15: C35 harness test now checks names+numbers only; copy-edit-v2 registry updated)
- 2026-10-15 08:58 Q450 -> doing — worker out
- 2026-10-15 08:58 Q453 -> doing — worker out
- 2026-10-15 09:03 Q451 -> done — hand-merged (D163: deleted QuickNoteBodyTextViewTests with the deleted view; PortfolioPresetTests source-scan path ported)
- 2026-10-15 09:05 Q425 -> tuur — awaiting sitting (re-read after D209)
- 2026-10-15 09:08 Q455 -> tuur — mock https://claude.ai/artifact/KTg3QUv6mJqCZPd8NnEuoc — question: rating + sender placement A or B
- 2026-10-15 09:08 Q452 -> doing — worker out
- 2026-10-15 09:08 Q454 -> doing — worker out
- 2026-10-15 09:10 Q455 -> done — Tuur 2026-10-15: beautiful — pick A, rows below
- 2026-10-15 09:10 Q464 added
- 2026-10-15 09:26 Q450 -> done — hand-merged (Tuur approved both flips on Q442 (2026-10-15))
- 2026-10-15 09:29 Q452 -> tuur — mock https://claude.ai/artifact/PHfGiLSgsDnECruxvpfFCD — pick A, B or C
- 2026-10-15 09:29 Q464 -> doing — worker out
- 2026-10-15 09:29 Q456 -> doing — worker out
- 2026-10-15 11:03 Q453 -> done — gate green (1905 tests) + AppendPlayerReloadTests rc=0 on merged head 166e88fa, re-run after the session restart killed the first accept
- 2026-10-15 11:03 Q311 -> tuur — recheck after Q453 (needs Dev 192)
- 2026-10-15 11:04 Q465 added
- 2026-10-15 11:07 Q452 -> done — Tuur 2026-10-15: keep today's header, let it scroll away like Apple Notes
- 2026-10-15 11:07 Q466 added
- 2026-10-15 11:07 Q466 -> doing — worker out
- 2026-10-15 11:08 Q456 -> done — gate 86s @7365e533
- 2026-10-15 11:09 Q467 added
- 2026-10-15 11:09 Q468 added
- 2026-10-15 11:09 Q469 added
- 2026-10-15 11:20 Q467 -> doing — worker out
- 2026-10-15 11:30 Q454 -> done — hand-merged (Tuur D210 2026-10-15 supersedes C71 frame-as-photo: four assertions moved to the D210 shape (gate green in the worker tree))
- 2026-10-15 11:32 Q467 -> stuck — merge conflict onto claude/skrift-parity-audit-91f702
- 2026-10-15 11:38 Q467 -> stuck — gate failed — .queue/Q467.gate.log
- 2026-10-15 11:38 Q468 -> doing — worker out
- 2026-10-15 11:38 Q469 -> doing — worker out
- 2026-10-15 11:40 Q470 added
- 2026-10-15 11:40 Q467 -> doing — re-accept after unrelated flake (DevEraMergeTests 3/3 green alone)
- 2026-10-15 11:43 Q467 -> done — gate 62s @5ecf3a79
- 2026-10-15 11:50 Q468 -> done — gate 59s @fdbc9ce2
- 2026-10-15 11:54 Q471 added
- 2026-10-15 11:59 Q464 -> done — gate 102s @1960c00a
- 2026-10-15 11:59 Q457 -> doing — worker out
- 2026-10-15 11:59 Q470 -> doing — worker out
- 2026-10-15 12:01 Q466 -> done — gate 59s @440764fe
- 2026-10-15 12:03 Q469 -> done — gate 60s @54b121f7
- 2026-10-15 12:03 Q458 -> doing — worker out
- 2026-10-15 12:03 Q465 -> doing — worker out
- 2026-10-15 12:06 Q470 -> tuur — approve: -shm checked by presence only (store + -wal still byte+mtime exact); wt/Q470 a4ab03cc, hand-merge on yes
- 2026-10-15 12:06 Q471 -> doing — worker out
- 2026-10-15 12:10 Q462 -> doing — mockup agent out
- 2026-10-15 12:32 Q465 -> done — gate 278s @facc651b
- 2026-10-15 12:35 Q457 -> done — hand-merged (Tuur Q447 (a) 2026-10-15 → D211: ImportFileNameTitleTests WhatsApp-name assertion flipped)
- 2026-10-15 12:39 Q458 -> done — gate 53s @7b990562
- 2026-10-15 12:40 Q471 -> done — gate 59s @e1959e07
- 2026-10-15 12:40 Q459 -> doing — worker out
- 2026-10-15 12:40 Q472 added
- 2026-10-15 12:40 Q472 -> doing — worker out
- 2026-10-15 12:48 Q472 -> done — gate 64s @48504f6b
- 2026-10-15 12:56 Q459 -> stuck — gate weakened: modified QUEUE.md 
- 2026-10-15 12:56 Q460 -> doing — worker out
- 2026-10-15 12:56 Q461 -> doing — worker out
- 2026-10-15 12:59 Q459 -> done — gate 61s @5a70b0ea
- 2026-10-15 12:59 Q462 -> tuur — mock https://claude.ai/artifact/CefrZozLqfihZdJdZv4scv — A (Library PDF carries highlights) or B (only the shared copy)
- 2026-10-15 13:20 Q460 -> done — gate 110s @32f54cf3
- 2026-10-15 13:25 Q461 -> stuck — merge conflict onto claude/skrift-parity-audit-91f702
- 2026-10-16 11:05 Q461 -> done — gate 64s @545a0b39
- 2026-10-16 11:50 Q462 -> done — Tuur 2026-10-16: rest looks really good; voice comments too; share asks with or without edits (D214)
- 2026-10-16 11:50 Q463 -> doing — worker out
- 2026-10-16 12:22 Q463 -> done — gate 98s @bc2dee38
- 2026-10-16 14:38 Q473 added
- 2026-10-16 14:38 Q473 -> doing — worker out
- 2026-10-16 14:53 Q474 added
- 2026-10-16 14:56 Q473 -> done — gate 68s @d8142be0
- 2026-10-16 14:56 Q474 -> doing — worker out
- 2026-10-16 15:02 Q475 added
- 2026-10-16 15:03 Q475 -> dead — Tuur 2026-10-16: not a bug, the bubble can be moved
- 2026-10-16 15:04 Q476 added
- 2026-10-16 15:04 Q476 -> doing — worker out
- 2026-10-16 15:12 Q474 -> done — gate 77s @cbda3eef
- 2026-10-16 15:28 Q476 -> done — gate 54s @e469a592
- 2026-10-16 15:29 Q477 added
- 2026-10-16 15:29 Q477 -> doing — worker out
- 2026-10-16 15:35 Q477 -> done — gate 55s @4f9cece8
- 2026-10-23 15:29 Q478 added
- 2026-10-23 15:29 Q425 -> done — Tuur 2026-10-23: all four as recommended → D215, applied by Q478
- 2026-10-23 15:29 Q478 -> doing — worker out
- 2026-10-23 15:34 Q479 added
- 2026-10-23 15:34 Q480 added
- 2026-10-23 15:34 Q481 added
- 2026-10-23 15:34 Q482 added
- 2026-10-23 15:34 Q483 added
- 2026-10-23 15:34 Q484 added
- 2026-10-23 15:34 Q485 added
- 2026-10-23 15:34 Q486 added
- 2026-10-23 15:34 Q487 added
- 2026-10-23 15:34 Q488 added
- 2026-10-23 15:34 Q489 added
- 2026-10-23 15:34 Q490 added
- 2026-10-23 15:34 Q491 added
- 2026-10-23 15:34 Q492 added
- 2026-10-23 15:34 Q493 added
- 2026-10-23 15:34 Q494 added
- 2026-10-23 15:34 Q495 added
- 2026-10-23 15:34 Q496 added
- 2026-10-23 15:34 Q497 added
- 2026-10-23 15:34 Q498 added
- 2026-10-23 15:34 Q499 added
- 2026-10-23 15:34 Q500 added
- 2026-10-23 15:36 plan: resync — 22 items for the 23 unqueued clauses (C149 C151 C152 C153 C155 C157 C158 C159 C163 C164 C245 C275 C280 C283 C284 C289–C294 C297 C298) in lanes A (recording/capture) B (sync/export) C (library/books); C160/C162 dropped (D183/D185); C296 covered by the perf lane
- 2026-10-23 17:24 Q479 -> done — gate 265s @b91dad8c
- 2026-10-23 17:24 Q501 added
- 2026-10-23 17:24 Q502 added
- 2026-10-23 17:28 Q478 -> done — hand-merged (D215 2026-10-23: expected-differences-copyedit-v2.json additive registrations as the item asked)
- 2026-10-23 17:35 Q493 -> done — gate 126s @33a80cb9
- 2026-10-23 17:38 Q480 -> stuck — gate failed — .queue/Q480.gate.log
- 2026-10-23 17:42 Q494 -> done — gate 125s @584c72ce
- 2026-10-23 17:45 Q496 -> done — gate 114s @12d664de
- 2026-10-23 17:48 Q481 -> done — hand-merged (D163 port: a new stored PipelineFile field added to ReconcileDiffHarnessTests.fields and the 101 v1-rows goldens (null), mechanical)
- 2026-10-23 17:51 Q503 added
- 2026-10-23 17:51 Q503 -> tuur — awaiting sitting
- 2026-10-23 17:56 Q495 -> done — gate 60s @886afdac
- 2026-10-23 18:30 Q504 added
- 2026-10-23 18:35 Q483 -> done — gate 144s @a9691c2a
- 2026-10-23 18:40 Q504 -> done — gate 84s @c67910ce
- 2026-10-23 18:42 Q482 -> done — hand-merged (R34 fixed by this item: RoundTripParityTests pre-registered XCTExpectFailure flips to a plain assertion (C5))
- 2026-10-23 18:46 Q501 -> done — hand-merged (D215 extension asked by Q501: expected-differences-copyedit-v2.json registrations moved/added for headings + bold)
- 2026-10-23 18:52 Q497 -> done — gate 74s @4fd69d33
- 2026-10-23 18:55 Q498 -> done — gate 65s @7533abc9
- 2026-10-23 18:57 Q500 -> stuck — gate failed — .queue/Q500.gate.log
- 2026-10-23 19:00 Q491 -> done — hand-merged (Q491 asked for goldens re-recorded by the harness flag: 99 vault export + 101 row goldens gain editedAt/memoEditedAt; 3 test lines ported (D163))
- 2026-10-23 19:05 Q499 -> stuck — gate failed — .queue/Q499.gate.log
- 2026-10-23 19:09 Q480 -> done — hand-merged (D163 port: new stored PipelineFile fields transcriptLanguageMode + pendingPolishBlock in ReconcileDiffHarnessTests.fields and the 101 v1-rows goldens (null))
- 2026-10-23 19:12 Q505 added
- 2026-10-23 19:12 Q502 -> stuck — gate failed — .queue/Q502.gate.log
- 2026-10-23 19:14 Q492 -> done — gate 105s @d050c3ec
- 2026-10-23 19:16 Q500 -> stuck — gate failed — .queue/Q500.gate.log
- 2026-10-23 19:16 Q506 added
- 2026-10-23 19:23 Q499 -> done — gate 219s @b7f70ca0
- 2026-10-23 19:23 Q426 -> stuck — touched protected: Skrift_Native/SkriftDesktop/SkriftDesktopTests/CopyEditV2SwapTests.swift Skrift_Native/SkriftMobile/SkriftMobileTests/PolishV2Tests.swift 
- 2026-10-23 19:27 Q502 -> done — gate 93s @f7529efa
- 2026-10-23 19:27 Q486 -> stuck — merge conflict onto claude/skrift-parity-audit-91f702
- 2026-10-23 19:27 Q426 -> todo
- 2026-10-23 19:27 Q500 -> todo
- 2026-10-23 19:27 Q507 added
- 2026-10-23 19:30 Q487 -> done — gate 187s @df83c527
- 2026-10-23 19:33 Q426 -> done — gate 187s @37df776f
- 2026-10-23 19:36 Q500 -> done — gate 155s @2746cf4f
- 2026-10-23 19:39 Q488 -> done — gate 166s @2b57c83e
- 2026-10-23 19:39 Q486 -> todo
- 2026-10-23 19:42 Q486 -> done — gate 193s @3f18139a
- 2026-10-23 19:45 Q505 -> stuck — check failed — .queue/Q505.check.log
- 2026-10-23 19:45 Q505 -> todo
- 2026-10-23 19:48 Q505 -> done — gate 164s @c3a965b9
- 2026-10-23 19:50 Q490 -> stuck — gate failed — .queue/Q490.gate.log
- 2026-10-23 19:53 Q506 -> done — gate 64s @7800be13
- 2026-10-23 19:57 Q508 added
- 2026-10-23 19:59 Q489 -> done — gate 117s @1d30a93d
- 2026-10-23 20:00 Q507 -> done — gate 87s @29ecb51d
- 2026-10-23 20:00 Q490 -> todo
- 2026-10-23 20:02 Q490 -> done — gate 87s @937e8190
- 2026-10-23 20:03 Q509 added
- 2026-10-23 20:04 Q508 -> done — gate 76s @50d9771c
- 2026-10-23 20:09 Q509 -> done — gate 49s @e43ef3fa
- 2026-10-23 20:15 Q510 added
- 2026-10-23 20:17 Q429 -> done — hand-merged (Q429's own harness registration: V2SweepEngine added to ReconcileDiffHarnessTests (v1 assertions unchanged, secondSweepConflicts per engine) and expected-differences-rows.json gains pic-missing-file C41 for v2; Tuur reads the diff in Q430)
- 2026-10-23 20:22 Q434 -> done — hand-merged (Q434's own harness registration: engines = [V1Engine(), V2Engine()] in ExportDiffHarnessTests and v2 ids added to expected-differences-export.json (no id removed); Tuur reads the diff in Q435)
- 2026-10-23 20:23 Q511 added
- 2026-10-23 20:28 Q510 -> done — gate 69s @0a277300
- 2026-10-23 21:52 Q430 -> dead — Tuur 2026-10-23: dropped the read (no context); conductor accepts on the harness (v2 108 identical, 1 expected, 0 unexplained)
