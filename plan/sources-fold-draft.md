# Fold draft — paste-ready rows from `plan/sources.md`

Built 2026-09-23 under SPEC.md C276. Every clause/decision/bug row below maps to one or more
numbered rows in `plan/sources.md`'s de-duplicated OPEN table. Checked before drafting:
SPEC.md's last clause is C282, last R is R94, last D is D100 (so C283/D101 are free); BUGS.md
§1's last data-loss item is D19 (so a new §1 item would be D20 — none needed here, every BUG
row below is a §2 "wrong behaviour" item, not new data loss).

---

## Clauses (paste into SPEC.md, numbered from C283)

- C283 [auto] `SourceTaxonomy` glyph/label maps are consolidated into one `Shared/` module used
  by both apps for every source kind (voice/URL/PDF/video/audiobook quote/Apple Note); no
  per-app duplicate map remains. || check: a golden test asserting one map instance is used by
  both `SkriftMobile` and `SkriftDesktop` targets. — sources.md #1
- C284 [tuur] Mac filter/sort gets a mock-first pass toward the phone's 5 sort modes +
  multi-axis filters, replacing the 3-way `QueueFilter`. || check: mock sign-off, then
  `QueueFilterTests` extended to the new axes. — sources.md #2
- C285 [tuur] Idea i10 (Obsidian-grade markdown body: bold/italic/highlight/strike, phone
  #tag/heading popup) graduates from idea to a queue item with a mock. || check: mock
  sign-off. — sources.md #3
- C286 [auto] Every `DriftedPair` in `Shared/UI/Palette.swift` and `SignificanceCirclesView.swift`
  is collapsed to one shared value or explicitly justified as a deliberate platform
  difference; none remain unresolved. || check: `grep -c DriftedPair` returns 0 or each hit
  carries a comment citing the platform-difference reason. — sources.md #4
- C287 [auto] `SignificanceCircles`/`Theme` hand-rolled per-app copies are folded to one
  shared implementation under the C239 twin-audit. || check: single shared type used by both
  targets. — sources.md #5
- C288 [tuur] The Mac gets a Models/Storage Settings screen mirroring the phone's (or this is
  explicitly marked not-doing). || check: `MacModelsStorageView` exists and is snapshot-tested,
  or a Decisions-log line records not-doing. — sources.md #6
- C289 [auto] "Record a voice" enrollment (Settings → Names & voices, and the standalone
  `PersonDetailView` affordance) is built on the desktop to phone parity, distinct from
  conversation-mode enrollment. || check: `PersonDetailView` unit test exercising a Mac-side
  enroll. — sources.md #7, #12
- C290 [tuur] Desktop gets a "Send feedback" capture (record+type+screenshot → Mail) mirroring
  the phone's Shhhcribble-ported flow, or this is explicitly dropped. || check: built feature or
  a Decisions-log not-doing line. — sources.md #8
- C291 [auto] The phone gets the desktop's word-select → "add as name" gesture on the
  transcript body. || check: `PhoneNameLinkingTests` covers a text-selection-to-name flow. —
  sources.md #9
- C292 [tuur] Confirm whether inline photo embeds close the "photo filmstrip + full-screen
  viewer" wish, or scope and build the dedicated viewer. || check: Decisions-log line either
  way. — sources.md #10
- C293 [tuur] Settings gets storage stats + "Clear synced memos" + a persisted last-sync
  timestamp, on whichever app(s) still lack them, or this is dropped. || check: built rows or a
  not-doing line. — sources.md #11
- C294 [tuur] Q7 per-Person "treat as distinctive" stoplist override is built, or formally
  parked under a named roadmap idea. || check: built override or an idea id. — sources.md #13
- C295 [auto] Roster-change propagation: `rescanRoster` triggers re-export of already-exported
  vault `.md` files whose `people:` frontmatter is now stale. || check: a `RosterAudit` test
  asserting a re-export queue entry on roster change. — sources.md #15
- C296 [tuur] The app surfaces vault completeness — a coarse "is my vault a full mirror of my
  rated notes" indicator, or this is explicitly parked as an idea. || check: built indicator or
  a parked-ideas line. — sources.md #16
- C297 [auto] YAML frontmatter carries `editedAt` alongside the `createdAt`/`duration` fields
  D12 already decided to add. || check: `VaultExporterTests` asserts `editedAt` in frontmatter. —
  sources.md #18
- C298 [auto] Reminders (`remindAt`) get a Mac-side alarm reconciler using the same
  `UserNotifications` API the phone uses; `remindAt` already syncs. || check:
  `MacReminderReconcilerTests`. — sources.md #19
- C299 [tuur] Audiobook bookmarking on an un-transcribed book gets an explicit fallback
  behaviour (decided, not just flagged). || check: `BookmarkTests` covers the untranscribed
  case. — sources.md #21
- C300 [tuur] Confirm a Tuur-pressed manual pause/resume button during recording is wanted
  beyond the existing auto-pause-on-interruption (C149), or drop the wish. || check:
  Decisions-log line. — sources.md #22
- C301 [tuur] Confirm Cmd+F find-in-page is wanted on the desktop app, or drop the wish. ||
  check: Decisions-log line. — sources.md #23
- C302 [auto] The enhancement summary prompt is checked against the "implied first person /
  present participle, never third person" rule and corrected if it drifted. || check: a golden
  prompt-output fixture asserting no "the speaker" framing. — sources.md #24
- C303 [tuur] Confirm the "image-drag ask" (repositioning a photo within a note) is the same
  item as C119's "picture drag-reposition" and fold it there, or scope separately. || check:
  Decisions-log line. — sources.md #25
- C304 [auto] A golden model-output baseline is recorded once over the synthetic corpus, so
  every later run can diff against it instead of judging against v1. || check: the baseline
  file exists under `test-fixtures/corpus/` and a diff-gate test reads it. — sources.md #26
- C305 [auto] Every recording-lifecycle transition (start/segment/interrupt/finalize) logs a
  Release-safe `os_log` line, not just DEBUG `DevLog`. || check: a log-line assertion test run
  in a Release-configured harness. — sources.md #27
- C306 [auto] Unrecoverable `rec_tmp_*` orphans are cleaned up after a failed recovery sweep,
  once the D26/C99 recovery path lands. || check: `RecoverySweepTests` covers the
  cleanup-after-failure branch. — sources.md #28
- C307 [auto] Conversation playback and audiobook read-along redraw only the changed region,
  not the whole screen, on their 20 Hz/2 Hz timers. || check: a render-count assertion in
  `ConversationTurnsSection`/`AudiobookPlayerView` tests. — sources.md #29
- C308 [auto] `SourceTaxonomy` parses its metadata blob once per row (not twice),
  `SpeakerTranscript.parse` caches its regex across note pages, and `names.json` is
  memoized instead of re-decoded on every access. || check: `plan/perf-sweep.md` P5-P7
  re-measured post-fix. — sources.md #30
- C309 [auto] `GemmaEmbedder.downloadProgress` loses its `nonisolated(unsafe)` race — proper
  actor isolation or a `Sendable`-safe publisher. || check: TSan-clean under the concurrency
  test target. — sources.md #31
- C310 [auto] The Mac ASR pre-warms on Record press instead of on first speech, closing the
  "waveform moves, no words for a while" gap on take 1. || check: a timing assertion in
  `MacRecordingTests`. — sources.md #37
- C311 [auto] The karaoke read-along perf cache (`315206b`, reverted) is re-landed against the
  current read-along code path. || check: perf-sweep re-measurement post-fix. —
  sources.md #38
- C312 [auto] A whole ePub import either ingests every part of the source file or reports
  exactly what was skipped and why — no silent partial ingest. || check: an ePub fixture with
  a deliberately malformed mid-file section, asserting a skip report. — sources.md #40
- C313 [auto] A long ePub/book import shows real progress and states whether listening can
  continue during the import. || check: `BookImportProgressTests`. — sources.md #41
- C314 [auto] ePub upload is blocked (with a clear message) while the same book's
  transcription is still in flight. || check: a guard test asserting the upload path checks
  the transcription job state. — sources.md #42
- C315 [auto] The iPad Polish model-download completeness check verifies the actual download
  (byte count or hash), not just a 500 MB floor. || check: `ResumableModelDownloaderTests`
  covers a truncated-but-over-floor download as incomplete. — sources.md #43
- C316 [tuur] Board A #3b follow-ups (mock's first-page inline PDF render on Mac,
  `PDFTextExtract` Mac-wire fallback, vault copy of the capture document on export) each get a
  DParityB backlog line and a device round. || check: backlog line added, then a device round
  confirms each. — sources.md #49
- C317 [auto] The audiobook player's perf debt is closed as one pass: `ReadAlongModel`
  decodes its sidecar once and diffs, not 2×/s; `BookTranscriptionJob`'s `@MainActor` work
  (`extractPCM`, `store.save`, `publishValue`) moves off-main or becomes O(n);
  `AudiobookCloudSync.localTranscriptSignature` stops full-decoding per reconcile; the Books
  list stops re-rendering at 2 Hz off `currentTime`; `setCurrent`'s 10×/s linear scan is
  indexed; per-body `Timer.publish` and per-`loadCoverTint` `CIContext` allocation are
  eliminated. || check: `plan/perf-sweep.md` gets a §3 covering these named sites, re-measured
  post-fix. — sources.md #52
- C318 [auto] A per-book "N notes" surface with a note→book jump-back is built. || check:
  `AudiobookLibraryTests`. — sources.md #54
- C319 [auto] Multi-select import of N distinct books never silently merges them into one. ||
  check: an import-fixture test with 2+ distinct books asserting 2+ resulting entries. —
  sources.md #55
- C320 [auto] The Books empty state gets a real call-to-action button. || check: snapshot
  test. — sources.md #56
- C321 [auto] `RecordView`'s live caption stops rebuilding a full `AttributedString` per poll;
  it diffs and appends. || check: perf-sweep re-measurement. — sources.md #58
- C322 [auto] `purgeExpiredTrash()` moves off `SkriftApp.init()`'s synchronous path into the
  audited async sweep chain (or gets its own watermark like the nine sweeps C281 already
  covers). || check: launch-time trace shows no synchronous purge call. — sources.md #59
- C323 [auto] `MemoDetailView`'s detail-pager `@Query` is windowed, not the whole non-trashed
  corpus. || check: perf-sweep re-measurement, distinct from the names/backlinks cost C278
  already covers. — sources.md #60
- C324 [auto] `BookCoverCache.image(for:)` reads off-main. || check: perf-sweep
  re-measurement. — sources.md #61
- C325 [auto] Backlinks (`LINKED-FROM`) are indexed on both apps, not a full-corpus body scan
  per note switch (`ConnectionsPanel.swift:119`, `ConnectionsModel`). || check: perf-sweep
  re-measurement, one clause for both apps. — sources.md #62
- C326 [auto] The phone gets the Mac's Connections query-failure empty state. || check:
  snapshot test on both platforms. — sources.md #63
- C327 [auto] A SwiftData query issued mid-sweep never observes a partially-swapped memo
  (actor-reentrancy guard around the sweep's `await` points). || check: a concurrency stress
  test. — sources.md #64
- C328 [auto] Paragrapher's grouping is confirmed wired into (or explicitly excluded from) the
  audiobook reading-mode display. || check: Decisions-log line, then a test if wired. —
  sources.md #65
- C329 [tuur] Decide: do captions keep running while backgrounded, and does memory-warning
  `unload()` interrupt mid-recording — record both as explicit rules. || check: Decisions-log
  lines, then guard tests. — sources.md #66
- C330 [auto] Whole recordings never lose route on a call/alarm mid-take (superset of the
  `os_log` diagnosability item) — the recovery path from D26/C99 is the fix; this clause only
  requires the orphan-cleanup half. || check: covered by C306.
- C331 [tuur] Office-printer guard: print-to-wall never fires to a random/office-network
  printer, only the saved one. || check: `WallPrinterTests` asserts the printer identity
  check. — sources.md #118

## Decisions (paste into SPEC.md Decisions log, numbered from D101)

101. **D101 Nickname preservation.** Preserve genuine alternate nicknames as distinct aliases,
     or keep normalising everything to one canonical name? Default: preserve as aliases
     (matches the existing alias model). — sources.md #14
102. **D102 Portfolio-repo archive questions.** Four questions for the portfolio-repo chat:
     is `_inspiration` still the right bucket name; do `[[Jack]]`-style links dangle on the
     site or resolve to person pages; does the site have a "type" concept matching the four
     destinations; does the archive accept video files. Default: ask before the next archive
     export round ships. — sources.md #17
103. **D103 Trash and the vault file.** Does trashing a note also delete its exported Obsidian
     `.md`? Default: no — trash is local lifecycle, the vault file stays until an explicit
     vault-side delete (matches the "never write over what isn't provably ours" doctrine). —
     sources.md #20
104. **D104 Digest-menu idea "Daily, spoken."** Fold into `i15` (monthly digest) as a cadence
     option, or drop. Default: fold in as the "weekly too?" question below (D106). —
     sources.md #46
105. **D105 Timeline-in-Review.** Give the "how did my thinking evolve" view its own idea id
     and a design-chat kickoff, distinct from the generic roadmap idea P8c it currently loose-
     matches. Default: yes, new idea id, cite this Decision as its origin. — sources.md #47
106. **D106 Monthly-digest cadence + landing + silence.** Three sub-questions on idea `i15`:
     (a) monthly only, or weekly too — default monthly only; (b) lands in Review as a pinned
     card, or vault-only at first — default vault-only at first; (c) an all-quiet month
     produces a digest or silence — default silence (matches the no-bad-information doctrine).
     — sources.md #48
107. **D107 Main-column polish proposal (mock #m6).** Approve or reject: tags move up,
     importance control one size down, icons on context chips. Default: needs Tuur's look at
     the mock before a verdict. — sources.md #68
108. **D108 `names-mac.html` sign-off.** Approve, reject, or defer the Mac Names screen
     redesign (avatars, voice status, side-by-side editor, in-place linking before enhance).
     Default: needs Tuur's look before scheduling. — sources.md #120
109. **D109 `resolver-inline.html` status.** Confirm whether variant A (click-to-resolve
     popover) is the same interaction that shipped in `naming-review.html`'s in-prose popover,
     or is still a distinct, unbuilt proposal. Default: needs a side-by-side comparison before
     closing. — sources.md #121
110. **D110 Desktop Models/Storage view.** Build a Mac mirror of the phone's model-inventory
     screen, or mark not-doing. Default: build (parity expectation set by every other Settings
     screen). — sources.md #6
111. **D111 Desktop "Send feedback" capture.** Build the Mac equivalent of the phone's
     record+type+screenshot→Mail flow, or drop now that `pull-phone-feedback` covers the
     voice-memo half of feedback. Default: drop — the skill already covers the workflow this
     served. — sources.md #8
112. **D112 Image-drag reposition.** Confirm this is the same item as C119's "picture
     drag-reposition (no mock yet, after C10)" and fold there. Default: yes, same item, no
     separate track needed. — sources.md #25

## BUGS.md §2 bullets ("Wrong behaviour — verified open today")

- [ ] **`SkriftMobile.diskwrites_resource` warning never root-caused.** Flagged twice
      (2026-06-14, 2026-07-xx) as "model downloads + whole-book transcribe = suspects," never
      profiled to a cause. Needs one Instruments pass. SPEC C-clause TBD (perf).
- [ ] **Text capture sometimes breaks a sentence up strangely.** Parakeet punctuation on
      abbreviations in text-first quote capture; never root-caused or reproduced deliberately.
      `Features/Audiobooks/TextCaptureView.swift`.
- [ ] **"Waiting" sync pill still reads off dead Bonjour sync state, not CloudKit.** Bonjour
      was retired 2026-07-06; `MemoDisplay.statusKind` (or its successor) may still branch on
      the old signal, producing a misleading pill. Needs a source check + fix.
- [ ] **Mac rating line is not state-aware.** Says "ready to process" even on an
      already-processed note; the wording fix landed (`e36bf150`, 2026-08-14) but the
      state-aware version was explicitly deferred in the same commit and never revisited.
      `RatingLineView` (or successor).
- [ ] **Connections panel card-chrome drift confirmed live: Mac draws cards, iPad draws bare
      rows.** C232 specs the chrome difference generally but this residual visual gap
      (`71f9ef71`, 2026-08-14) was never itself closed or explicitly ratified as intentional.
- [ ] **Karaoke realignment after a hand-edited live take never landed.** "Parked with its one
      open decision (edited takes need a timings-only pass)" — only ever a parenthetical in a
      roadmap shipped-log line (`roadmap.yaml:2114`), never promoted to a clause or its own
      BUGS row until now.

## Ledger corrections

- **CLAUDE.md**, mocks list: "`audiobook-player-reading-mode` (e-reader 'reading mode' +
  tab-bar IA redesign, signed off 2026-06-19 — not yet built)" →
  "`audiobook-player-reading-mode` (e-reader 'reading mode' + tab-bar IA redesign, signed off
  and built 2026-06-19, build 14)".
- **CLAUDE.md**, mocks list: "`book-sharing` (... cut twice 2026-07-30 ... **NOT signed off
  yet**; board = backlog '📦 CONTINUE HERE')" → "`book-sharing` (... signed off + built
  2026-08-01/08-11, round-trip proven on device, roadmap node `BookShare` done 2026-08-12)".
- **`Skrift_Native/SkriftDesktop/mocks/book-text-unified.html`**: `<title>` currently reads
  "... (PROPOSAL)" and an internal HTML comment reads "NOT BUILT — awaiting sign-off" → both
  should read "SIGNED OFF AND BUILT 2026-07-23 (b110)", matching FEATURES.md:190 and roadmap
  idea `i12`.
- **`Skrift_Native/SkriftDesktop/mocks/index.html`**: delete — byte-identical duplicate of
  the superseded `v2.html`; both are superseded by `v5.html` (the file CLAUDE.md already
  correctly cites as the locked shell).
- **SPEC.md C181**: "The phone shows the polish as the ONE editable body (no raw/polished
  toggle); an edit lands in the enhancement, stamped; title chooser Suggested / recording /
  own; 'Polished on your Mac' provenance." → drop the trailing "'Polished on your Mac'
  provenance" clause — Tuur killed this caption 2026-07-07 (`d66a1ee7`) and it has stayed dead
  since (current code + its own test comment confirm removal).
- **SPEC.md C197**: "... is superseded in part by C61 (processed-only, verb-driven). Confirm
  the narrowing." → "... is superseded in part by C61 (processed-only, verb-driven). ⚠
  Confirm the narrowing — see D-row [assign next free D after this fold]." (turns the dangling
  imperative into a tracked Decision instead of a clause that can never resolve itself).
- **BUGS.md §4**: delete the row "Device-testing feedback 2026-06-17 — one data-integrity
  finding in that batch." → resolved in-source, `archive/state-2026-09/backlog.md:7199`,
  "✅ RESOLVED 2026-06-21: all three done."
- **BUGS.md §4**: the "Mac search-jump parity gap" row needs a re-verify pass before its next
  edit — commit `785a8156` (2026-07-16) claims it fixed; no evidence either way was checked
  before the row was filed. Not a delete yet, a flagged re-verify.

## Queue verify items

- Real-device export round: `SharedExport` — throwaway folder first, then the real vault.
- Real-device export round: `ExportDestinations` — throwaway folder first, then the portfolio
  repo; also verify the gate fix `00e67299` on-device.
- Device round: iPad Polish load re-check after the mlx-swift-lm pin bump.
- Full phone unit suite run before the next device push (post pin-bump).
- iPad audiobook player "owed by contract": wide-player live eyeball, landscape pass, Stage
  Manager/Split View compact fallback, ⌘-shortcut feel, onboarding on pad — one device round
  covering all five.
- Board A #4 (DParityB): full UnitTests + `-skipMacroValidation` build + `-snapshot` PNG pass.
- Board B (DParityB): annotation count-bubbles live-deploy look.
- Diarization-survives-backgrounding: elapsed readout + a real background cycle on device.
- "Always warm" ASR engine: one battery measurement (distinct from the iPad-polish battery
  claim already closed).
- `SkriftDesignKit` token package: status check against `Shared/UI/` — built or not.
- Append-can-silently-add-no-text: re-verify against current `MemoSaver.appendRecordingAsync`
  (BUGS §4 still calls this NOT re-verified).
- Mac Dev redeploy: eyeball the Date/Filter popovers; phone install of build 126 (or current
  equivalent) device round.
- ePub round-trip: phone uploads on next foreground reconcile → iPad shows the attached ePub
  without re-aligning.
- Starvation-mitigation (re-align freeze fix): one device round to confirm the root cause.
- Books tab bookmark-toggle chip beyond the signed mock: confirm intentional or revert.
- Wave-3 share-ingest user retest list (real apps, choosers, import menu) — low priority.
- Chunksim third lane (STEP 0) for `exportSpan` vs `extractPCM` — never run.
- Project age: ask Tuur directly (git floors 2025-10-18, he recalls "2 years+").
- iPad's old Skrift Dev build: confirm updated (local-only doctrine risk).
- Cross-check the karaoke-after-edit decision once D-row above (D-TBD) is answered.

## Tooling

- `SWIFT_STRICT_CONCURRENCY` adoption plan — scope a spike if still wanted (targeted ~3d, full
  10-15d per the original audit estimate).
- Long-compile hunt (`-warn-long-function-bodies`/`-warn-long-expression-type-checking`).
- Dead-code tool: pick a `swiftlint analyze`-based substitute (Periphery is now commercial).
- Mutation testing / manual break-ten-functions suite-quality check.
- `XcodeBuildMCP` for the agent build/install/drive loop — evaluate adoption.
- `CaptureInboxDrainer.process` — split the 410-line function into its own refactor chunk.
- `MemoSaver`↔`IngestService` duplicate ingest logic — its own dedup chunk (twin-scan flagged,
  never actioned).
- `Audio Output Dev` sweep-test leak on the Dev store (~1,969 stray folders) — one-time cleanup
  script, needs Tuur's go-ahead before running.
- Release App-Group one-time Xcode Signing & Capabilities visit for the prod bundle ID
  (capture-items precedent) — a [tuur] manual step, not code.
