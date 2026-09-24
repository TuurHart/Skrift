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

### Q3 [tuur] (tuur) mockup: tag UI revamp
spec: C241 C93
needs: -
do: A redesigned tag editor for phone and Mac that keeps the C93 rules (comma/newline split, `#` stripped, case kept, case-variants fold to the first spelling, destination words allowed). Start from today's tag chips drawn from source, show add / remove / suggest / typeahead.
check: Tuur clicked through it and said go.

### Q4 [tuur] (tuur) mockup: edit-conflict prompt
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

### Q7 [auto] (todo) build quick note
spec: C112 C114 C43
needs: Q1 Q22 Q26
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

### Q12 [tuur] (tuur) read the body v2 corpus output
spec: C8 C27
needs: Q11
node: V2Core
do: Three rulings owed with the read (Q11 finding): (a) four fixtures put a picture mid-sentence against C11 (pic-at-start, pic-ocr-text, pic-three-spread #3, ingress-p3) — fix the fixtures' offsets, or allow a boundary tolerance; (b) pic-in-task-list cannot satisfy R95 under C20+D3 — drop its R95 entry; (c) the 13 extra differences in `expected-differences-q11.json` are accepted. -
check: Tuur read `plan/reads/body-v2.md` and said it reads right.

### Q13 [auto] (todo) swap: every body write site calls v2
spec: C10 C17 C65 C2
needs: Q12
node: V2Core
do: (Q11 finding: call `BodyV2.committed(BodyV2.Input(text:words:manifest:source:userEdited:))` at every write site, `.speech` only with real word times; `BodyTransform.snappedImageBody` and v1's `ImageMarkers.insert → Paragrapher` leave in the same swap; thumbnail = `BodyV2Thumbnail.pick`.) Point every place a body is WRITTEN at body v2: phone capture (`MemoSaver`), share drain, editor commit, imports, the Mac author path and Mac recordings. Renderers and both exporters stop calling the render-time snap (`snapImages`, `SnapResult`), the display-only `imageBreaks` and the export-time `snappedImageBody` (the v1 functions stay in place for Q15 to delete). The three offset remaps collapse to one (marker → one glyph).
check: `! grep -rnE "snapImages\(|snappedImageBody\(|imageBreaks" Skrift_Native/SkriftDesktop/Pipeline Skrift_Native/SkriftDesktop/Features Skrift_Native/SkriftMobile/Features Skrift_Native/SkriftMobile/Services`

### Q14 [auto] (todo) old notes normalised once
spec: C10 C203
needs: Q13
gate+: yes
node: V2Core
do: (Q23 finding: the corpus has no name-offset field — `CorpusSeed.Note`/`makeMemo` hardcode `nameResolutionsData = nil`; add one so `migrated-stale-name-offsets` proves R25.) At first open on any device, a note whose stored body breaks C10 is rewritten once to the v2 layout and its name offsets re-derived (D4, R25); a local per-note flag makes it one-time and a second run a no-op; the C203 legacy shapes (old test image-captures, pre-build-76 PDF captures) are left alone. Test in `BodyNormaliseMigrationTests` (desktop target) using the v1 goldens as the legacy bodies.
check: `grep -rqE "class BodyNormaliseMigrationTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q15 [tuur] (todo) delete v1 body after the tag
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

### Q18 [auto] (todo) a corrupt local file is never loaded as empty
spec: C50 C265 C218
needs: -
gate+: yes
node: AuditFix2
do: One shared doctrine for every locally cached JSON file: `names.json` (atomic write, actor-guarded, merge never shrinks — R8), phone `library.json` and `bookmarks.json`, the Mac's `settings.json`, the audiobook-bookmark sync blob (R42, R59, R78). A file present but undecodable is kept aside as `<name>.corrupt-<date>`, recovery is surfaced, and nothing is written over it. One helper in `Skrift_Native/Shared/`. Tests: `CorruptStoreTests` in BOTH test targets (Mac: names + settings; phone: library + bookmarks).
check: `grep -rqE "class CorruptStoreTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && plan/mtest.sh CorruptStoreTests`

### Q19 [auto] (todo) re-transcribe keeps the text; attachments obey ownership
spec: C51 C58 C54
needs: -
gate+: yes
node: AuditFix2
do: Re-transcribe clears nothing until the new transcript exists; a missing audio file is an error on the row (R9). Every attachment lane — the Mac `VaultExporter` attachment copy and the shared `VaultWrite.writeAsset` `.file` branch — goes through the same stamp/ownership check as the markdown lane and never removes a file it doesn't own (R7, R77). Tests `RetranscribeKeepsTextTests` and `AttachmentOwnershipTests` (desktop target).
check: `grep -rqE "class RetranscribeKeepsTextTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && grep -rqE "class AttachmentOwnershipTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests`

### Q20 [tuur] (todo) perf baseline before any perf fix
spec: C282
needs: -
node: AuditFix2
do: Claude prepares the `xctrace` commands; Tuur runs Time Profiler on the iPhone 13 PROD build during a list scroll and a note open, and a typing session in a 5,000-word note on the Mac (Dev, the corpus `typed-wall-7k` note). Claude writes the top frames of both traces into `plan/perf-measured.md`.
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

### Q24 [auto] (doing) the old 10-stop scale and refine pass leave the code (litCount)
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

### Q26 [auto] (todo) build the one notes list on phone, iPad and Mac
spec: C117 C114 C240
needs: Q22 Q8
gate+: yes
do: Build the signed `Skrift_Native/SkriftDesktop/mocks/one-notes-list.html` ("One list" tab; D134–D137) on all three devices through the shared `Shared/UI/NoteCardView.swift` + per-app style: the phone gets the iPad/Mac Import · Record · ✎ verb row and loses the red mic corner button; all three on the phone's grey `Palette.bg.phone`; status pill only while working/broken; display-only three balls on rows; day groups everywhere; chip bar All · Needs Work N · Done N · Unrated N + icon-only Filter; the "ready to review · to process" line and "Mark all as Passing" are REMOVED (Process button unaffected). Fix the two BUGS §4 leads on the way: unrated rows double-dimmed (MemoCard 0.55 × NoteCardView 0.62) and the Mac untitled-row first-line repeat (QueueRowView). Test the chip counts and row inputs in a new `NotesListModelTests` (desktop target).
check: `grep -rqE "class NotesListModelTests\b" Skrift_Native/SkriftDesktop/SkriftDesktopTests && ! grep -rqE "Mark all as Passing|ready to review" Skrift_Native --include='*.swift'`

### Q27 [auto] (doing) recovery sweep quarantines unreadable orphans, never deletes them
spec: C99 C288
needs: Q16
gate+: yes
node: AuditFix2
do: Device evidence 2026-09-24 (iPhone 13, Dev build 171, devlog 15:34:49): the Q16 launch sweep logged `rec recover-failed — no readable audio — cleaned 1 file(s)` for 5 legacy pre-segment `rec_tmp_*` orphans and DELETED them. An m4a with no moov atom is unreadable to AVFoundation but often rescuable (`tools/rescue-lost-recordings.py`), so on prod's first launch this would destroy his real orphaned recordings. Change the failed-recovery branch: MOVE every unreadable orphan (rec_tmp_*, rec_seg_*, rec_ckpt_*) into `Documents/QuarantinedRecordings/` with a sidecar JSON (take id, sizes, first-seen date), never delete it; log `rec quarantined`; a later explicit user action or the rescue tool is the only way out. C288's cleanup now means "out of the recording dir", not "deleted". Test in a NEW `RecoveryQuarantineTests` (phone target): a truncated m4a is quarantined byte-identical, nothing is removed.
check: `plan/mtest.sh RecoveryQuarantineTests && ! grep -rnE "removeItem" Skrift_Native/SkriftMobile/Features/Recording/RecordingRecovery.swift`

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
