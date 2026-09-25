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

### Q15 [tuur] (tuur) delete v1 body after the tag
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

### Q20 [tuur] (tuur) perf baseline before any perf fix
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

### Q47 [auto] (todo) quick note opens the full note screen; ✎ never opens an old note; toolbar stays
spec: C112 C114 C43
needs: -
do: D145 + BUGS §3 (build 172): the quick note must be the FULL note screen (MemoDetailView in a draft state: date, tags, importance visible, cursor in body, keyboard up) — retire the separate `QuickNoteView`; keep first-keystroke creation + empty discard. Fix: the first ✎ tap opened an OLD note (the recovered recording) — find why the route resolved to an existing memo (stale deep link / draft id / selection state) and add a test; the keyboard accessory bar must never disappear while typing. QuickNoteTests stay green; add `QuickNoteRouteTests` (phone target). Sim screenshot, synthetic corpus, isolated store; LOOK; commit under `plan/reads/quicknote-q47/`.
check: `plan/mtest.sh QuickNoteRouteTests && plan/mtest.sh QuickNoteTests && test $(ls plan/reads/quicknote-q47/*.png | wc -l) -ge 1 && ./gate.sh`

### Q48 [auto] (todo) filter chips switch with one consistent animation; verb row a little bigger
spec: C117 C240
needs: -
do: D145 + BUGS §3 (build 172): switching chips (All / Needs Work / Done / Unrated) animates differently per chip (Needs Work flies up from the bottom, Done's date headers fly in last). Make a chip switch one consistent, quick transition on all three devices (no per-section insertion animations; list identity stable). Make the Import · Record · ✎ row a little taller (Tuur: "a bit small") on phone and iPad. Sim screenshots before/after; LOOK; commit under `plan/reads/list-q48/`.
check: `test $(ls plan/reads/list-q48/*.png | wc -l) -ge 1 && ./gate.sh`

### Q49 [tuur] (todo) mockup: one filter mechanism instead of chips + Filter icon
spec: C117
needs: -
do: D145: "two types of filters… difficult or tricky". One page showing today's chip bar + Filter icon (drawn from source) and 2–3 ways to make it ONE mechanism (e.g. chips carry everything, or one Filter menu with the chips inside), phone + Mac.
check: Tuur clicked through it and said go.

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
