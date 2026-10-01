# QUEUE — Skrift
gate: ./gate.sh
protected: SPEC.md QUEUE.md gate.sh plan/mtest.sh test-fixtures/corpus Skrift_Native/SkriftDesktop/SkriftDesktopTests Skrift_Native/SkriftMobile/SkriftMobileTests

Wave 1 of the v2 rewrite (2026-09-24): the mocks, rewrite target 1 (body/image) end to end,
the lost-recording fix, three data-loss/privacy fixes, the perf baseline. Phone-side checks
use `plan/mtest.sh <TestClass>` (the default gate runs the Mac suite only). Mocks go in
`Skrift_Native/SkriftDesktop/mocks/`, current-app parts drawn from source (C117).

## Later

Staged, not dropped. Each comes back as items at the next resync (`/2-plan`), in this order:
- Builds of the Q3 tag UI (C241), Q4 conflict prompt (C98, C242) and Q6 sources tab (D90, D126, D128) mocks, once signed.
- Target 2 copy-edit v2 (C28–C40, C150, C177–C182), first its untested clauses C30 C35 C40 as tests (C253).
- Target 3 reconcile v2 (C41–C52, C185–C191), first C52 as a test (C253); twin audit `plan/twins.md` before it (C239).
- Target 4 export v2 (C53–C65, C129–C137, C192–C196), first C57 C64 C65 as tests (C253).
- The perf lane: one item per site in `plan/perf-sweep.md` §2 and `plan/sources.md` rows 29 30 37 38 52 58 59 60 61 62 115 (C277–C281, C296), after the Q20 baseline.
- The editor rebuild on body v2 with Apple Notes formatting (C113, C234, D112, D115), mock first.
- The one shared import layer (C238, C66–C79, C123–C128, C140–C147) with the ingress fixtures.
- Mock refreshes: Mac Names screen (D108); `resolver-inline` A vs the shipped popover (D109).
- Remaining data-loss rows C261–C274 not covered by Q16/Q18/Q19; names fixes C254–C260; Mac feedback transport (D111, host owed).

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

### Q17 [tuur] (tuur) iPhone 13: call and force-quit mid-take
spec: C99
needs: Q16
node: AuditFix2
do: Install the Dev build on the iPhone 13. Take 1: record, take a phone call mid-take, hang up. Take 2: record, force-quit mid-take. Relaunch after each; pull `Documents/devlog.txt`.
check: Both notes are present after relaunch with all audio up to the event, and Tuur says so.

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
needs: Q26
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

### Q50 [tuur] (done) mockup: one compact note header (date + place, tags, importance)
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
do: Q56 made BodyTextView restyle only the edited paragraph and debounce the full pass 1 s, so typing inside a heading or link shows plain styling for up to 1 s (never rendered on screen). Install Skrift Dev on the Mac from the session branch (build → pkill → ditto to /Applications/Skrift Dev.app → open), type in a long note inside a heading and a link. If the flash bothers him: keep the edited paragraph's heading/link styling live.
Also, in the same Dev window: does the sidebar's left edge cut the first letter of every row and day header ("ODAY", "AT 19 SEP")? The headless snapshot always shows it (Q35, Q37, Q65); a real window has never been checked.
check: Tuur typed on the Mac and said the flash is fine, or it became an item.

### Q64 [tuur] (tuur) iPhone 13: quick note full screen, ✎ opens a new note, toolbar stays
spec: C112 C114
needs: Q47
do: Q47's two device fixes are unverified (NoteRoute replaces the desyncable draft-id pair; NoteAccessoryBar intrinsicContentSize for the vanishing toolbar). Install the Dev build from the session branch on the iPhone 13 (bump SKRIFT_BUILD); tap ✎ right after launch and after a recovered recording exists; type a paragraph; check date, tags and importance show and the toolbar never leaves.
check: Tuur tapped ✎ on the iPhone 13 and said it opened a new note with the toolbar up, or it became an item.

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

### Q67 [tuur] (done) mockup: Apple Notes import as a triage, 10 notes at a time (rate / skip / delete)
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

### Q70 [tuur] (done) mockup: compact note header, two versions — B refined, and today's layout squeezed
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

### Q94 [auto] (doing) the phone reads dates from filenames like the Mac (C70 required difference): one shared filename-date ladder, the share extension carries each file's name
spec: C70 C124 C12 C238
needs: Q93
gate+: yes
do: C70 is a required difference: recordedAt = embedded date → date in the filename (WhatsApp / Signal / Telegram / recorder patterns, Mac parity) → file date → now; the phone never parses the filename today. Q92 extended the Mac's `IngestService.dateFromFilename` (incl. compact HHMMSS like `signal-2026-10-01-080349`); Q93 found the share extension hands the drain no filenames — clips carry file mod dates, pictures only EXIF (empty for Signal JPEGs) — so a real Signal share of clips + a picture falls back to pictures-first. Move the filename-date ladder into `Shared/` (one copy, the Mac calls it too), make the share extension carry each item's original filename / suggestedName and its selection position, and let the drain date clips and pictures from it so MixedBundle places a Signal picture between the clips at its time and the note is dated to the first message (C124). Tests: the ladder's patterns (shared, desktop + phone), a Signal-named share bundle → picture between clip 3 and 4. Never run SkriftDesktopUITests.
check: `perl -e 'alarm 900; exec @ARGV' plan/mtest.sh QuickNoteRouteTests && ./gate.sh && (cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null && xcodebuild build -scheme SkriftDesktop -destination 'platform=macOS' -skipMacroValidation -quiet)`

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
