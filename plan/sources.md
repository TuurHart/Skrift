# Source ledger — merged

Date: 2026-09-23. Rule in force: SPEC.md C276 — a cited document is not a folded document;
every OPEN row in every slice gets a verdict here before `/2-plan` can run.

19 slices, 3,171 lines, read in full:

| slice | OPEN |
|---|---|
| sources-state.md | 30 |
| sources-handoffs.md | 37 |
| sources-backlog-1.md | 21 |
| sources-backlog-2.md | 10 |
| sources-backlog-3.md | 37 |
| sources-backlog-4.md | 49 |
| sources-backlog-5.md | 32 |
| sources-commits-1.md | 4 |
| sources-commits-2.md | 4 |
| sources-commits-3.md | 2 |
| sources-commits-4.md | 1 |
| sources-commits-5.md | 4 |
| sources-commits-6.md | 8 |
| sources-commits-7.md | 2 |
| sources-commits-8.md | 5 |
| sources-commits.md (name-filtered cross-check) | 3 |
| sources-mocks-1.md | 0 (1 stale-file note) |
| sources-mocks-2.md | 0 (2 needs-Tuur, 2 signed-not-built) |
| sources-mocks-3.md | 0 (2 needs-Tuur, 3 signed-not-built) |

**Total before de-duplication: 249** rows marked OPEN (plus 9 mock-slice "needs Tuur" /
"signed-off-not-built" rows folded in below, since they are real gaps even though those
three slices don't use the literal OPEN tag). **After merging duplicates and near-duplicates
(same underlying gap named in two or more slices, or several perf/polish sub-items on one
subsystem folded into one row): 121** distinct rows below.

---

## OPEN, de-duplicated

| # | item (plain words) | sources (slice:line or commit) | kind | what it needs |
|---|---|---|---|---|
| 1 | Source-taxonomy glyph/label maps still duplicated across phone and Mac, no shared module | handoffs:132; backlog-5:130,227 | RULE | consolidate into `Shared/SourceTaxonomy.swift`, close the CLAUDE.md open-work bullet |
| 2 | Mac filter/sort parity — phone has 5 sort modes + multi-axis filters, Mac has a 3-way `QueueFilter` | backlog-4:175; commits-6:22,120 | RULE | mock-first pass, then a clause |
| 3 | Obsidian-grade markdown body parity (i10) — bold/italic/highlight/strike, phone #tag/heading popup, still an unbuilt idea | backlog-5:15; commits-6:27,121 | RULE | graduate roadmap idea i10 to a queue item |
| 4 | 6 Palette `DriftedPair` colours, 9 call sites, never reconciled despite a promised "one eyeball round" | backlog-2:69; backlog-4:194 | RULE | the C239 twin-audit round, one collapse per pair |
| 5 | `SignificanceCircles`/`Theme` hand-rolled duplicates (separate from #4) never folded | backlog-2:70 | RULE | same C239 umbrella |
| 6 | Desktop Models/Storage view (mirror of the phone's model-inventory Settings screen) still not built | handoffs:130; backlog-5:173,192,270; sources-state:177 | RULE | build the Mac screen or an explicit not-doing line |
| 7 | Desktop "record a voice" enroll still a placeholder — mobile shipped 2026-06-15, desktop unconfirmed | backlog-5:188,228,272 | RULE | build or formally defer |
| 8 | Desktop "Send feedback" capture (Shhhcribble-style record+type+screenshot→Mail) never built, mobile has it | commits-2:20,84 | RULE | build or drop with a decision |
| 9 | Word-select "add as name" on the phone (desktop has it) — no clause names this parity gap | sources-state:154 | RULE | an R-row for the phone-side gesture |
| 10 | Photo filmstrip with offset labels + full-screen viewer — not confirmed built distinct from inline embeds | handoffs:100 | RULE | confirm inline embeds close it, else build |
| 11 | Settings extras: storage stats + "Clear synced memos" + persisted last-sync time, either app | handoffs:101 | RULE | small Settings feature, needs a queue item or drop |
| 12 | Standalone "record a voice" affordance in PersonDetailView (distinct from conversation enrollment) unconfirmed | handoffs:128 | RULE | check current `PersonDetailView`, clause or drop |
| 13 | Q7 per-Person "treat as distinctive" stoplist override — parked, never built | backlog-5:164 | RULE | build or park with a roadmap idea id |
| 14 | Genuine alternate-nickname preservation vs. normalise-everything, never decided | backlog-5:161 | DECISION | a D-row on nickname handling |
| 15 | `rescanRoster` doesn't rewrite already-exported vault `.md`; no auto-re-export on roster change | backlog-5:163 | RULE | a clause on roster-change export propagation |
| 16 | No vault-completeness surface — nothing answers "is my vault a full mirror of my rated notes?" | backlog-3:319 | RULE | a roadmap idea or SPEC parked-ideas addition |
| 17 | Four unanswered questions to the portfolio-repo chat (`_inspiration` naming, dangling `[[Jack]]` links, site "type" concept, does the archive accept video) | backlog-3:55-58 | DECISION | one message, four short answers |
| 18 | YAML frontmatter `editedAt` never ruled on (D12 settled `duration`/`createdAt` in, lat/lon/reminder out) | backlog-3:317 | DECISION | one-line addendum to D12 |
| 19 | Reminder alarm never reaches the Mac (no Mac-side alarm reconciler) | backlog-4:172 | RULE | promote the existing NFeat backlog line to a queue item |
| 20 | Should trashing a note also delete its Obsidian `.md`? — explicit open design question, never asked | backlog-4:173 | DECISION | a D-row, data-safety weight |
| 21 | Audiobook bookmark fallback for an un-transcribed book — flagged trade-off, never answered | backlog-5:80 | RULE | a clause once decided |
| 22 | Manual pause/resume recording button (user-pressed) — only auto-pause-on-interruption (C149) is confirmed | commits-1:42,75 | RULE | confirm against current `RecordView`, clause if missing |
| 23 | Cmd+F find-in-page on the desktop app — no in-app find/search clause anywhere | commits-1:26,72 | RULE | confirm still wanted, clause or explicit not-doing |
| 24 | Summary-prompt voice (implied first person/present participle, never "the speaker") — no clause pins it | commits-1:27,73 | RULE | check the current prompt text, codify or drop |
| 25 | Image-drag ask (repositioning a photo within a note), triaged, never built or ledgered separately | commits-8:59,131 | RULE | confirm same item as C119's "picture drag-reposition," track there |
| 26 | Golden model-output recording for the v2 corpus not yet built — blocks the "v1 is not the judge" gate | backlog-1:114,153 | RULE | build the baseline tool, run it once over the corpus |
| 27 | Recording-loss prod diagnosability — no `os_log` trail for the recording lifecycle in Release (DevLog is DEBUG-only) | backlog-1:104,152 | RULE | a clause requiring a Release-safe log line per transition |
| 28 | Orphan hygiene — nothing cleans up unrecoverable `rec_tmp_*` files after a failed recovery | backlog-1:105 | RULE | a clause once the D26/C99 recovery path exists |
| 29 | 20 Hz/2 Hz whole-screen invalidation in conversation playback + audiobook read-along, never entered AuditFix2 or perf-sweep | backlog-1:30,155; backlog-4:89,90,93 | RULE | a perf-sweep candidate row (C277-C281 pattern) |
| 30 | P5-P7: `SourceTaxonomy` double metadata-blob parse, `SpeakerTranscript.parse` fresh-regex-per-page, `names.json` re-decode with no memoization — never folded into AuditFix2 | sources-state:49-51; backlog-1:28 | RULE | add P5-P7 to AuditFix2's backlog, or their own C-clauses |
| 31 | `GemmaEmbedder.downloadProgress` `nonisolated(unsafe)` race | sources-state:61 | RULE | a concurrency clause or AuditFix2 backlog line |
| 32 | `SWIFT_STRICT_CONCURRENCY` adoption plan (targeted ~3d, full 10-15d) — no plan tracked | sources-state:62 | TOOLING | a scoped spike if still wanted |
| 33 | Long-compile hunt (`-warn-long-function-bodies`/`-warn-long-expression-type-checking`) never run | sources-state:65 | TOOLING | one-off diagnostic pass |
| 34 | Dead-code tooling (Periphery now commercial; `swiftlint analyze` substitute never picked) | sources-state:67 | TOOLING | pick a tool or drop |
| 35 | Mutation testing / manual break-ten-functions suite check, never run | sources-state:68 | TOOLING | a one-off suite-quality audit |
| 36 | `XcodeBuildMCP` for the agent build/install/drive loop — tooling adoption question, unresolved | sources-state:69 | TOOLING | evaluate, not a code item |
| 37 | Mac ASR cold-start pre-warm on Record press ("waveform moves, no words for a while" on take 1) | backlog-2:53,102 | RULE | a pre-warm-on-press clause under W8/RecHard |
| 38 | Re-land the karaoke read-along perf cache (`315206b`, reverted by `d898771e`, never redone) | backlog-2:67,105 | RULE | a perf-sweep row if it still matters |
| 39 | `CaptureInboxDrainer.process` — still a 410-line unsplit function, device-critical share-ingest | backlog-2:71,108 | TOOLING | its own refactor chunk |
| 40 | Partial-ePub ingest bug — "not all parts of the ePub were displayed/ingested," distinct from alignment verdicts (C227) | backlog-2:85,109 | RULE | an R-row or BUGS entry on the ingest path |
| 41 | Big-ePub import UX — 13-hour book, long load, no progress bar, unclear if listening can continue | backlog-2:86,110 | RULE | a progress-bar clause |
| 42 | Block ePub upload while the book is still transcribing — undefined today | backlog-2:87,111 | RULE | a guard clause |
| 43 | iPad Polish model-download completeness check still just a 500 MB floor, own code comment says "advisory only" | backlog-3:87,330-333 | RULE | exact byte/hash verification, not a floor |
| 44 | iPad audiobook player "owed by contract": wide-player live eyeball, landscape pass, Stage Manager/Split View fallback, ⌘-shortcut feel, onboarding on pad | backlog-3:17-21 | VERIFY | a P9b backlog line per item, or one device round |
| 45 | Release App-Group one-time Xcode Signing & Capabilities visit for the prod bundle ID (capture-items precedent) | backlog-3:22 | TOOLING | a [tuur] queue item, not code |
| 46 | "9 Daily, spoken" digest-menu idea never reviewed or verdicted | backlog-3:115 | DECISION | fold into i15 or explicitly drop |
| 47 | Timeline / "how did my thinking evolve" view in Review — reacted well to twice, no design chat, no mock, no roadmap idea | backlog-3:98,116; sources-commits:149,187-190 | DECISION | a design-chat kickoff or a roadmap idea id |
| 48 | Monthly digest open questions: cadence (monthly-only or weekly too?), lands in Review as a pinned card or vault-only, all-quiet month = digest or silence | backlog-3:131-133 | DECISION | three short D-rows under i15 |
| 49 | Filter/sort parity — Board A #3b follow-ups (mock's true first-page inline PDF on Mac, `PDFTextExtract` fallback, vault copy of the capture doc on export) never got a backlog row | backlog-4:162 | RULE | a DParityB backlog line per follow-up |
| 50 | Board A #4 — full verify pass (UnitTests + `-skipMacroValidation` build + `-snapshot` PNGs) never itemized as a deliverable | backlog-4:163 | VERIFY | routine, just needs a checklist line |
| 51 | Board B — annotation count-bubbles want a live-deploy look, never confirmed | backlog-4:164 | VERIFY | one device round |
| 52 | Audiobook perf debt: `ReadAlongModel.reloadIfNeeded` 2×/s full-sidecar decode, `BookTranscriptionJob` @MainActor sync `extractPCM`/O(n²) `store.save`, `AudiobookCloudSync.localTranscriptSignature` full-decode per reconcile, 2 Hz `currentTime` over-observation, `setCurrent` linear-scan 10×/s, per-body `Timer.publish` churn, `CIContext` per `loadCoverTint` | backlog-4:89-93 | RULE | a P9b/perf-sweep pass over the audiobook player, one clause covering the class |
| 53 | Quote audio extraction `exportSpan` vs `extractPCM` — the chunksim third lane (STEP 0) was never run | backlog-4:98 | VERIFY | run the chunksim lane once |
| 54 | Per-book "N notes" surface + note→book jump-back never built | backlog-4:100 | RULE | a P9b idea |
| 55 | Multi-select import of N distinct books silently merges into one — never fixed | backlog-4:101 | RULE | a guard clause |
| 56 | Books empty-state has no real CTA button | backlog-4:102 | RULE | small UI fix |
| 57 | `LiveRecordingService` per-buffer `Task` ordering (P2, symbol renamed/moved) needs re-verification before it can get an R-row | backlog-4:42 | VERIFY | re-locate the current code path, then clause or drop |
| 58 | Live-caption rebuilds a full `AttributedString` per poll (`RecordView.swift` ~L706-713) — still unfixed | backlog-4:43 | RULE | perf-sweep candidate |
| 59 | `purgeExpiredTrash()` runs synchronously in `SkriftApp.init()`, outside the audited sweep chain (R94/C280 didn't cover it) | backlog-4:44 | RULE | fold into the sweep-chain clause or give it its own |
| 60 | `MemoDetailView`'s detail-pager `@Query` is still the whole non-trashed corpus, unwindowed | backlog-4:45 | RULE | perf-sweep candidate, different cost than the one C-clause already covers |
| 61 | `BookCoverCache.image(for:)` still an on-main synchronous file read | backlog-4:47 | RULE | perf-sweep candidate |
| 62 | Mac + mobile: `LINKED-FROM`/backlinks still a full-corpus body scan per note switch (`ConnectionsPanel.swift:119`, `ConnectionsModel`) | backlog-4:51,54 | RULE | index it, one clause for both apps |
| 63 | Phone parity for the Connections query-failure empty state — Mac half shipped, phone untracked | backlog-4:52 | RULE | port the Mac's empty state |
| 64 | Actor-reentrancy window — a query during a sweep's `await` can see a mid-swap memo (structural, no clause) | backlog-4:53 | RULE | needs its own concurrency clause |
| 65 | Paragrapher's reading-mode grouping tie-in unconfirmed (Paragrapher shipped, reading-mode use is not tied to it by any clause) | backlog-4:66 | RULE | confirm the wiring, one line |
| 66 | Deferred judgment calls: captions keep running while backgrounded; memory-warning `unload()` still no-ops mid-recording | backlog-4:77 | RULE | two small clauses or an explicit accept |
| 67 | MemoSaver↔IngestService duplicate ingest logic, flagged by the twin-scan tool, never actioned | backlog-4:196 | TOOLING | its own dedup chunk |
| 68 | Main-column polish proposal (mock #m6: tags move up, importance control one size down, icons on context chips) — a boxed proposal, never picked up | backlog-4:197 | DECISION | Tuur picks yes/no on the mock |
| 69 | Starvation-mitigation (re-align freeze fix) — "not a proven root cause," device round never run | backlog-4:18,19 | VERIFY | one device round |
| 70 | Per-file resume for an app-killed-mid-align restart — "worth it if multi-file books grow," never scoped | backlog-4:20 | RULE | park explicitly or scope |
| 71 | `BGProcessingTask` ride-along for align-on-lock — "parked, standalone-phase candidate," no idea id | backlog-4:21 | RULE | give it an idea id if still wanted |
| 72 | `AlignmentCore` progress callback (real % inside one file's match) — parked candidate, no idea id | backlog-4:22 | RULE | give it an idea id |
| 73 | CORE2: 30s gap-bridge untuned; `epubChapters` detected-merge suppression stays whole-file | backlog-4:25 | RULE | a tuning pass, needs a clause |
| 74 | Persist per-file coverage % in the ePub sidecar "at the next schema touch" — schema touch never happened | backlog-4:26 | RULE | fold into the next sidecar schema bump |
| 75 | Memory-aid prompts (record-screen prompt list + Settings editor) — dropped from the RN era, never picked back up | handoffs:98 | RULE | decide keep-dropped or rebuild |
| 76 | "Transcription a bit weird" on cold auto-start — user unsure if real, never resolved either way | handoffs:134; backlog-5:187 | RULE | needs a repro before it can become a clause |
| 77 | Diarization-survives-backgrounding — device-eyeball elapsed readout + a real background cycle, never confirmed | sources-state:158; backlog-5:75 | VERIFY | one device round |
| 78 | Audiobook unshare leaves a phantom library entry (no GC for a carrier-less, audio-less entry) | sources-state:168; backlog-5:102 | RULE | a GC clause |
| 79 | Whole-book transcribe memory-pressure lead — "not a clear fix," profiling only | sources-state:169 | RULE | loosely related to AuditFix2's Time Profiler step, not named |
| 80 | Capture sentence-split on abbreviations ("Dr.") — not a corpus fixture in the Paragrapher rewrite | sources-state:170 | RULE | a corpus fixture + C20 amendment |
| 81 | Desktop walkthrough tracker items (C1 health-dot design, ST7/E4 prompt-vs-YAML verify, AUD-P* polish, W2 cursor) — `WALKTHROUGH_BUGS.md` items never folded | sources-state:180; handoffs:153-156 | RULE | fold the surviving items or confirm the UI moved past them |
| 82 | Project age unverified (git floors 2025-10-18, Tuur recalls "2 years+") | sources-state:184 | VERIFY | Tuur's own recollection, not a code clause |
| 83 | `SkriftDesignKit` token package — never confirmed built or not | sources-state:209 | VERIFY | a status check against `Shared/UI/` |
| 84 | Cellular "ready to sync · N MB" tap-to-pull affordance (`NWPathMonitor`) never built | sources-state:213; backlog-1:44(dup, distribution) | RULE | a clause once scoped |
| 85 | `B2.sentimentScore` as a retrieval facet — idea never named anywhere | backlog-1:60 | RULE | give it an idea id or drop |
| 86 | Cluster labels (naming step for A1's clustering, i18) — clustering itself is tracked, the label sub-step isn't | backlog-1:63 | RULE | fold into i18 |
| 87 | Decision-extraction → running decision log — not tracked anywhere | backlog-1:64 | RULE | give it an idea id |
| 88 | Action/todo extraction — not tracked anywhere | backlog-1:65 | RULE | give it an idea id |
| 89 | Open-loop resolution (LLM confirm step over the rule-matched A4) — i18 covers the rule-matched half only | backlog-1:66 | RULE | fold into i18 or a new idea |
| 90 | Tag suggestion from a closed set — not tracked | backlog-1:67 | RULE | give it an idea id |
| 91 | Contradiction/evolution detector — not tracked | backlog-1:68 | RULE | give it an idea id |
| 92 | Per-turn conversation summary — not tracked | backlog-1:71 | RULE | give it an idea id |
| 93 | Person digest ("what Jack and I keep circling") — not tracked | backlog-1:73 | RULE | give it an idea id |
| 94 | Duplicated author in an imported book's title ("X — Author" title plus a separate author byline) | backlog-1:93 | RULE | a clause: strip author from the title on import |
| 95 | `Audio Output Dev` sweep-test leak — ~1,969 stray folders on the Dev store, left for Tuur to decide | commits-8:98,132 | TOOLING | a one-time cleanup script, needs Tuur's go-ahead |
| 96 | `SkriftMobile.diskwrites_resource` warning — never root-caused (model downloads / whole-book transcribe are suspects) | backlog-5:206 | BUG | a profiling pass |
| 97 | Two import affordances in the Library (toolbar + and a second) — "keep only the toolbar +," never confirmed done | backlog-5:231 | RULE | a UI cleanup pass |
| 98 | "Sentence breaks up strangely" in text capture (Parakeet punctuation/abbreviations) — never root-caused | backlog-5:235 | BUG | a repro + fix |
| 99 | Wave-2 desktop mirror of whole-book text-capture transcription — mobile-only today, no Mac build | backlog-5:242 | RULE | scope a Mac equivalent or drop |
| 100 | Bookmarks-viewing list hidden inside Chapters sheet → Bookmarks tab — a more direct path never built | backlog-5:243 | RULE | a small IA fix |
| 101 | Desktop Send/receive `DevLog` shared equivalent (nice-to-have) — never actioned | backlog-5:29 | TOOLING | low priority, needs a queue item if wanted |
| 102 | "Waiting" sync pill still drives off dead Bonjour sync state, not CloudKit — a real user-visible correctness bug | backlog-5:45,263-265 | BUG | a BUGS.md row, check `MemoDisplay.statusKind` |
| 103 | Mac rating line stays stateless ("ready to process" on an already-processed note) — explicitly deferred, never revisited | commits-8:40; sources-commits:56,180-182 | BUG | a BUGS.md row or its own clause |
| 104 | Connections panel card-chrome drift confirmed live (Mac draws cards, iPad draws bare rows) | commits-8:30,129 | BUG | a BUGS.md row, C232's chrome spec doesn't cover this residual |
| 105 | Karaoke realignment after a hand-edited live take (mid-take edit) — parked with one open decision (edited takes need a timings-only pass), never promoted past a roadmap parenthetical | commits-7:101(? see W8 backlog); sources-commits:101,183-186 | BUG | an idea id or a D-row so it can't be silently dropped |
| 106 | Append can silently add no text — 3× repro, broader than the cold-model theory; BUGS §4 still calls it NOT re-verified | backlog-5:74 | VERIFY | re-verify against current `MemoSaver.appendRecordingAsync` |
| 107 | P0/P1 diarization-survives-backgrounding low-confidence hypothesis, never closed | backlog-5:75 (dup of #77, listed once) | VERIFY | one device round |
| 108 | "Always warm" ASR/transcription engine — confirm/document it isn't draining battery, distinct from the (different) iPad-polish battery claim | backlog-5:76 | VERIFY | one battery measurement |
| 109 | Desktop "record a voice" enroll again flagged in the 2026-06-14 audit's own ⏳ OPEN list — same as #7, cross-confirmed a second time | backlog-5:228 | RULE | (same fix as #7) |
| 110 | "Two Rooms" desktop mirror of the same Mac/iPad sync-status pill wording gap | backlog-5:102 (see #78) | — | duplicate, folded into #78 |
| 111 | Small Content-icon two-import-affordances/library nit (#3937 area — Filter sheet bigger + trimmed, big sheet only sim-verified) | backlog-3:214 | VERIFY | Mac Dev redeploy to eyeball on device |
| 112 | Mac Dev redeploy to eyeball the Date/Filter popover, phone install of build 126 device round — never confirmed | backlog-3:213,215 | VERIFY | one Dev redeploy + phone install |
| 113 | Device round owed: phone uploads on next foreground reconcile → iPad should show attached ePub without re-aligning | backlog-3:244 | VERIFY | one round-trip |
| 114 | Shell: last-note-delete leaves a stale pane until a tap | backlog-3:260 | BUG | a small UI fix |
| 115 | Detail: related-derivation double-computes at regular width (distinct from the C278/perf-sweep sites already tracked) | backlog-3:261 | RULE | perf-sweep candidate |
| 116 | Books tab added a bookmark-toggle chip beyond the signed mock — never resolved as a deliberate difference or a drift bug | backlog-3:262 | RULE | confirm intentional or revert |
| 117 | Update the iPad's old Skrift Dev build (local-only doctrine risk) — device hygiene, never confirmed done | backlog-3:274 | TOOLING | a housekeeping check |
| 118 | Print-to-wall office-printer guard rule (don't silently print to a random/office network printer) — named once, never a clause | commits-5:103,111 | RULE | a guard clause under C233 |
| 119 | Wave-3 share-ingest user retest list — parked "with zero urgency," never became a BUGS row or queue item | commits-5:56,110 | VERIFY | a retest pass, low priority |
| 120 | `names-mac.html` mock (Mac Names screen redesign matching the phone) — no sign-off date recorded anywhere | mocks-2:29,45-50,65 | DECISION | Tuur confirms approve/reject before it's scheduled |
| 121 | `resolver-inline.html` mock (R3 inline name-disambiguation, 3 variants) — no citation anywhere ties it to a build | mocks-3:15,65 | DECISION | Tuur confirms whether variant A shipped as the naming-review popover or is still open |

**Kind counts:** RULE 76 · DECISION 10 · BUG 7 · VERIFY 16 · TOOLING 11 (120 verdicted rows;
row #110 is a pure duplicate marker folded into #78, not separately counted). STALE items are
covered in the Contradictions section below, not duplicated here.

---

## Contradictions the slices found

Each checked against the current file, not taken on the slice's word.

1. **C181 still requires the "Polished on your Mac" provenance caption.** SPEC.md:965-966 lists
   it as required phone UI. Tuur killed it explicitly 2026-07-07 (commit `d66a1ee7`,
   "Polished on your Mac" isn't useful — drop it") and current code has it removed
   (`PolishedDisplayUITests.swift:27` comment records the removal). Confirmed stale — C181
   needs its phrase deleted, not silently carried forward. — commits-5:33,109

2. **C197 flags itself as needing confirmation.** SPEC.md:1029-1031: "superseded in part by
   C61 (processed-only, verb-driven). Confirm the narrowing." No later commit or Decision
   resolves it — it is not wrong, it is an admitted-open ⚠ that nothing has closed. Confirmed
   still open, five weeks after the C61 rewrite that triggered it. — commits-6:84,125

3. **Mac search-jump: commit vs. BUGS.md disagree.** Commit `785a8156` (2026-07-16) title
   says "Mac search should jump to + flash the hit like the phone... fixed." BUGS.md:281
   ("§4 From the ledger, NOT re-verified") still lists "Mac search-jump parity gap" as open.
   Checked: BUGS §4 is explicitly the not-re-verified section, so this isn't a hard
   contradiction — it's an unresolved re-verify, and the commit's own claim was never checked
   against source before being filed there. Needs one re-verification, then either BUGS.md
   drops the row or it moves to §2. — commits-6:28,122-123,127

4. **BUGS.md §4's 2026-06-17 data-integrity finding is stale.** BUGS.md:277 lists "Device-
   testing feedback 2026-06-17 — one data-integrity finding in that batch" as an unverified
   lead. The source backlog (`archive/state-2026-09/backlog.md:7199`) resolves it in the same
   document: "✅ RESOLVED 2026-06-21: all three done." Confirmed stale — this BUGS.md row
   should be deleted, not carried as a lead. — backlog-5:138

5. **roadmap `ExportDestinations` is `inprogress` — checked, this is correct, not stale.**
   `roadmap.yaml:759` shows `status: inprogress` despite the core build merging
   (`8d6b6519`). Its own `note:` field lists real remaining scope ("LEFT: the field +
   reserved-word guard... the tag-sheet rework + vault tags on the phone, and video as an
   exportable asset kind"). Verdict: accurate, not a contradiction.

6. **roadmap `IPadWave1` is `inprogress` — checked, also correct.** `roadmap.yaml:872` shows
   `status: inprogress` with an explicit unresolved owed list in its own `note:` field (Mac
   eyeball incl. the snapshot-blind ⋯ chip, polish + prompt-sync live test, undiagnosed
   "could not process," the Mac's "Mark all as Passing" wording). Verdict: accurate, matches
   every slice that touched this node (commits-7:41,146; backlog-1 and -3's iPad rows).

7. **CLAUDE.md's mock bullet for `audiobook-player-reading-mode` is stale.** CLAUDE.md reads
   "signed off 2026-06-19 — not yet built." FEATURES.md:196 and commits-4:46 both confirm it
   shipped 2026-06-19 (build 14), same day as sign-off. Needs correcting. — mocks-1:19

8. **CLAUDE.md's mock bullet for `book-sharing` is stale.** CLAUDE.md reads "NOT signed off
   yet." Sign-off is `427dd0f1`/`6a462229` (2026-08-01/08-11), build merged (`db9b6ff6`),
   round-trip proven on device, roadmap node `BookShare` status `done` (2026-08-12). Needs
   correcting. — mocks-1:21; handoffs:181

9. **`book-text-unified.html`'s own `<title>` says "(PROPOSAL)"** and an internal HTML
   comment says "NOT BUILT — awaiting sign-off," contradicting FEATURES.md:190 and roadmap
   idea i12 ("SIGNED OFF AND BUILT 2026-07-23, same session") and CLAUDE.md's own correct
   ledger line for this same mock. The stale text lives inside the mock file, not in
   CLAUDE.md. — mocks-1:23; sources-state:23(cf. book-text-unified row)

10. **`index.html` mock is a byte-identical copy of `v2.html`.** `md5` confirmed identical;
    both are superseded by `v5.html` (commit `eba5576d`, "v5 = locked design," which CLAUDE.md
    correctly cites). `index.html` is dead weight, not a design decision. — mocks-1:32,51-53

11. **Backlink Weaver / context-aware enhancement / People Timeline flagged OPEN in one
    slice, FOLDED in two others.** `sources-commits-2.md:35,81` lists all three as OPEN
    ("none appear in SPEC.md, FEATURES.md, or roadmap.yaml"). `sources-handoffs.md:42,44` and
    `sources-state.md:106,178-179` correctly find them in SPEC.md's Parked-ideas list
    ("Backlink Weaver," "people pages (P7)") and D82 (context-aware enhancement, dropped).
    The commits-2 slice's grep missed the parked-ideas list — its OPEN verdict for these
    three is itself stale; they are FOLDED, not open. Not re-listed in the OPEN table above.

12. **"In-app feedback → backlog/inbox routing" gets both OPEN and SUPERSEDED verdicts.**
    `sources-handoffs.md:131` (citing NEXT_CHAT_HANDOFF.md) marks it OPEN. `sources-backlog-5.md:190,226`
    marks the same idea SUPERSEDED — the `.claude/skills/pull-phone-feedback/` skill is the
    actual shipped mechanism for this need. The backlog-5 verdict is the one consistent with
    the live repo (the skill exists and is in active use per CLAUDE.md's ledger section); the
    handoffs OPEN verdict is stale. Not listed in the OPEN table above.

---

## Not a gap, checked

- TestFlight distribution: the account-wide Apple force-expiry root cause IS documented
  (memory `project_testflight`), just not promoted into BUGS.md/roadmap — see OPEN table.
- CloudKit prod schema, App Groups (Release) capability, and the Bonjour retirement are all
  confirmed shipped and current across every slice that touched them.
- The v2 rewrite's own spec machinery (SPEC.md, BUGS.md §1-3, `roadmap/roadmap.yaml`,
  `plan/perf-sweep.md`) is itself current and was the primary cross-check for every verdict
  above — none of the 19 slices found it wrong except the two BUGS.md rows in Contradictions.
- Naming model (opt-out, in-prose, 3-tier) is fully built and consistently cited across every
  slice that touched it — no drift found.
- CloudKit sync spine (Memo/MemoAsset/MemoEnhancement, NamesRecord LWW union) is confirmed
  live and load-bearing for dozens of later shipped features across every slice.
- Audiobook chunk-extraction gotcha (sample-accurate `AVAudioFile` frames, never
  `AVAssetExportSession`) is the one piece of tribal knowledge every audiobook-adjacent slice
  independently confirmed still holds.
- The lifecycle "one clock" / rating-is-consent model (C87-C91) is consistently cited as the
  current, shipped design across every slice that touched lifecycle or rating.
- Export destination as a privacy boundary (one-of-four, never two) is consistently confirmed
  built and current, including the 2026-08-27/28 frontmatter-key-collision fixes.
- The RN/Electron/Python archival (June 2026) is confirmed complete and intact under
  `archive/` in every slice that checked it — nothing was lost in the convergence.
- Device-build/signing doctrine (Team ID, `-allowProvisioningUpdates`, dev/prod bundle-ID
  split) is confirmed current and unchanged across every slice.

---

## Queue verify items (device rounds owed, from this fold)

- Real-device export round: `SharedExport` — throwaway folder first, then the real vault.
- Real-device export round: `ExportDestinations` — throwaway folder first, then the portfolio
  repo; also verify the gate fix `00e67299` on-device.
- Device round: iPad Polish load re-check after the mlx-swift-lm pin bump.
- Full phone unit suite run before the next device push (post pin-bump).
- #44 iPad audiobook player "owed by contract": wide-player live eyeball, landscape pass, Stage
  Manager/Split View compact fallback, ⌘-shortcut feel, onboarding on pad — one device round
  covering all five.
- #50 Board A #4 (DParityB): full UnitTests + `-skipMacroValidation` build + `-snapshot` PNG pass.
- #51 Board B (DParityB): annotation count-bubbles live-deploy look.
- #77, #107 Diarization-survives-backgrounding: elapsed readout + a real background cycle on device.
- #108 "Always warm" ASR engine: one battery measurement (distinct from the iPad-polish battery
  claim already closed).
- #83 `SkriftDesignKit` token package: status check against `Shared/UI/` — built or not.
- #106 Append-can-silently-add-no-text: re-verify against current `MemoSaver.appendRecordingAsync`
  (BUGS §4 still calls this NOT re-verified).
- #111, #112 Mac Dev redeploy: eyeball the Date/Filter popovers; phone install of build 126 (or
  current equivalent) device round.
- #113 ePub round-trip: phone uploads on next foreground reconcile → iPad shows the attached ePub
  without re-aligning.
- #69 Starvation-mitigation (re-align freeze fix): one device round to confirm the root cause.
- #116 Books tab bookmark-toggle chip beyond the signed mock: confirm intentional or revert.
- #119 Wave-3 share-ingest user retest list (real apps, choosers, import menu) — low priority.
- #53 Chunksim third lane (STEP 0) for `exportSpan` vs `extractPCM` — never run.
- #82 Project age: ask Tuur directly (git floors 2025-10-18, he recalls "2 years+").
- #117 iPad's old Skrift Dev build: confirm updated (local-only doctrine risk).
- #105 Cross-check the karaoke-after-edit decision once D131 is answered.

## Tooling (from this fold)

- #32 `SWIFT_STRICT_CONCURRENCY` adoption plan — scope a spike if still wanted (targeted ~3d, full
  10-15d per the original audit estimate).
- #33 Long-compile hunt (`-warn-long-function-bodies`/`-warn-long-expression-type-checking`).
- #34 Dead-code tool: pick a `swiftlint analyze`-based substitute (Periphery is now commercial).
- #35 Mutation testing / manual break-ten-functions suite-quality check.
- #36 `XcodeBuildMCP` for the agent build/install/drive loop — evaluate adoption.
- #39 `CaptureInboxDrainer.process` — split the 410-line function into its own refactor chunk.
- #67 `MemoSaver`↔`IngestService` duplicate ingest logic — its own dedup chunk (twin-scan flagged,
  never actioned).
- #95 `Audio Output Dev` sweep-test leak on the Dev store (~1,969 stray folders) — one-time cleanup
  script, needs Tuur's go-ahead before running.
- #45 Release App-Group one-time Xcode Signing & Capabilities visit for the prod bundle ID
  (capture-items precedent) — a [tuur] manual step, not code.

## Where each OPEN item went

Every row of the de-duplicated OPEN table above, with its landing. `NOT FOLDED` rows have no
clause, decision, BUGS row, VERIFY item or TOOLING item drafted for them in this pass — most are
"give it an idea id or drop" rows (roadmap idea additions) that this fold did not reach; they need
a pass of their own.

| # | landing |
|---|---|
| 1 | D113 |
| 2 | D114 |
| 3 | D115 |
| 4 | D116 |
| 5 | D116 |
| 6 | D110 |
| 7 | D117 |
| 8 | D111 |
| 9 | D118 |
| 10 | D133 |
| 11 | D119 |
| 12 | D117 |
| 13 | D120 |
| 14 | D101 |
| 15 | C283 |
| 16 | D121 |
| 17 | D102 |
| 18 | C284 |
| 19 | D122 |
| 20 | D103 |
| 21 | D123 |
| 22 | D124 |
| 23 | D125 |
| 24 | C285 |
| 25 | D112 |
| 26 | C286 |
| 27 | C287 |
| 28 | C288 |
| 29 | C296 |
| 30 | C296 |
| 31 | BUGS §2 GemmaEmbedder race |
| 32 | TOOLING (SWIFT_STRICT_CONCURRENCY spike) |
| 33 | TOOLING (long-compile hunt) |
| 34 | TOOLING (dead-code tool substitute) |
| 35 | TOOLING (mutation testing check) |
| 36 | TOOLING (XcodeBuildMCP evaluation) |
| 37 | C296 |
| 38 | C296 |
| 39 | TOOLING (CaptureInboxDrainer.process split) |
| 40 | C289 |
| 41 | C290 |
| 42 | C291 |
| 43 | C292 |
| 44 | VERIFY (iPad audiobook player device round) |
| 45 | TOOLING (App-Group Signing & Capabilities visit) |
| 46 | D104 |
| 47 | D105 |
| 48 | D106 |
| 49 | D126 |
| 50 | VERIFY (Board A #4 full verify pass) |
| 51 | VERIFY (Board B annotation count-bubbles) |
| 52 | C296 |
| 53 | VERIFY (chunksim third lane) |
| 54 | D127 |
| 55 | C293 |
| 56 | D128 |
| 57 | VERIFY (re-locate the per-buffer Task ordering) |
| 58 | C296 |
| 59 | C296 |
| 60 | C296 |
| 61 | C296 |
| 62 | C296 |
| 63 | D129 |
| 64 | C294 |
| 65 | D130 |
| 66 | D131 |
| 67 | TOOLING (MemoSaver/IngestService dedup) |
| 68 | D107 |
| 69 | VERIFY (starvation-mitigation device round) |
| 70 | Parked ideas |
| 71 | Parked ideas |
| 72 | Parked ideas |
| 73 | Parked ideas |
| 74 | Parked ideas |
| 75 | Parked ideas |
| 76 | VERIFY (repro owed) |
| 77 | VERIFY (diarization-survives-backgrounding) |
| 78 | C298 |
| 79 | VERIFY (profile whole-book transcribe memory) |
| 80 | VERIFY (corpus fixture: "Dr." abbreviation split, C20) |
| 81 | VERIFY (WALKTHROUGH_BUGS items re-check) |
| 82 | VERIFY (project age) |
| 83 | VERIFY (SkriftDesignKit status check) |
| 84 | Parked ideas |
| 85 | Parked ideas |
| 86 | Parked ideas |
| 87 | Parked ideas |
| 88 | Parked ideas |
| 89 | Parked ideas |
| 90 | Parked ideas |
| 91 | Parked ideas |
| 92 | Parked ideas |
| 93 | Parked ideas |
| 94 | C297 |
| 95 | TOOLING (Audio Output Dev cleanup script) |
| 96 | BUGS §2 (diskwrites_resource) |
| 97 | Parked ideas |
| 98 | BUGS §2 (text-capture sentence break) |
| 99 | Parked ideas |
| 100 | Parked ideas |
| 101 | TOOLING |
| 102 | BUGS §2 (waiting sync pill) |
| 103 | BUGS §2 (Mac rating line) |
| 104 | BUGS §2 (Connections chrome drift) |
| 105 | BUGS §2 (karaoke realignment) |
| 106 | VERIFY (append-can-silently-add-no-text re-verify) |
| 107 | VERIFY (dup of #77) |
| 108 | VERIFY (always-warm ASR battery measurement) |
| 109 | D117 (dup of #7) |
| 110 | DUP (folded into #78 per sources.md) |
| 111 | VERIFY (Mac Dev redeploy eyeball) |
| 112 | VERIFY (Mac Dev redeploy + phone build 126) |
| 113 | VERIFY (ePub round-trip device check) |
| 114 | BUGS §2 stale pane |
| 115 | C296 perf lane |
| 116 | VERIFY (Books tab bookmark chip vs signed mock) |
| 117 | VERIFY (iPad old Dev build confirm-updated, per draft) |
| 118 | C295 |
| 119 | VERIFY (wave-3 share-ingest retest) |
| 120 | D108 |
| 121 | D109 |


## Verify + tooling additions (2026-09-23, from the unplaced rows)
- VERIFY: re-locate `LiveRecordingService` per-buffer `Task` ordering (#57); repro "transcription a bit weird on cold auto-start" (#76); profile whole-book transcribe memory pressure (#79); corpus fixture for "Dr." abbreviation splits (#80); re-check the `WALKTHROUGH_BUGS.md` tracker items (#81).
- TOOLING: a shared desktop `DevLog` equivalent (#101).

## Second pass (plan/sources-verify.md, 2026-09-23) — the rows the first pass missed
Sampled 125 backlog lines, 25 state-doc lines, 25 handoff/memory lines, 40 commits, 15 mocks: miss rate 3.2% / 4% / 0 / unbounded (commits, see below) / 0. Two wrong hashes out of 621, both corrected in the slices. Commit family: the eight full-read slices and the name-filtered cross-check overlap, so no miss rate could be bounded; all 621 cited hashes were checked to exist (`git cat-file`), 2 bad, 2 package revisions.
| item | source | landing |
|---|---|---|
| Device eyeball owed: m2 photo-thumb rows + book-quote rows (iPad b155 / Dev Mac) | backlog:809 | VERIFY |
| Re-export flip owed a vaulted device tap (substance tracked: roadmap.yaml:681, SPEC A58/A65); the slice had no row | backlog:1205–1236 | FOLDED (citation added here) |
| Device eyeball owed: build 87, the 3-photo thumbnail repro | backlog:4332–4338 | VERIFY |
| Device re-verify tags on three FIXED memo-link bugs (SignificanceCircles gating, backlinks-missing, Mac chip `memo_<UUID>`) | backlog:5699,5707,5713 | VERIFY (one device round) |
| Instant-record flashes the old ready screen | backlog:7978–8003 (2026-06-11 device feedback) | BUGS §4 |
| AirPods re-insertion after removal does not resume input | same | BUGS §4 |
| Live Activity shows stale on the lock screen after a fresh install | same | BUGS §4 |
| `roadmap/HISTORY_BACKFILL.md` eras 1–5 "not yet built into the viz" (the in-repo viz was deleted 2026-06-29; the Command Center renders now) | SKRIFT_SOURCE_OF_TRUTH.md:456 | TOOLING (fresh look at /2-plan, may be moot) |
