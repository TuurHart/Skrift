# Source ledger — archive/state-2026-09/backlog.md, lines 1-1162

Date: 2026-09-23. Rule: SPEC.md C276, "a cited document is not a folded document." Every open
item below got a verdict from SPEC.md (clauses C1-C281, required differences R1-R94, decisions
D1-D100), BUGS.md, roadmap/roadmap.yaml, plan/perf-sweep.md, and git log where needed. Range
read: lines 1-1162 only, per the split.

## ⭐ RESUME HERE — 2026-09-14 (lines 5-33)

| item | line | verdict | id / why |
|---|---|---|---|
| Pull Tuur's lost recording off the phone (the orphan `rec_tmp_*.m4a`) | 23-24 | OPEN | A physical device action, not a code change. No commit or ledger confirms it happened. Needs a queue item: "pull recordings dir via devicectl, run tools/rescue-lost-recordings.py, report result." |
| The D4 fix itself (segment rolling + launch sweep + force-quit finalize) | 25-26 | FOLDED | SPEC C99 ("a recording is NEVER lost... segments... marker plus a launch sweep... force-quit finalises"), decision D26 ("all three, fixed in v1 now"), BUGS.md §1 D4, issue #14. Not yet built. |
| Owed device round — "mid-record call/alarm survives" | 26-27 | FOLDED | Same as above: C99's own check clause names "a simulated call and a process kill mid-take on the sim... the iPhone 13 call test" as still owed. |

## 🔍 CONTINUE HERE — audit fix wave 2 (lines 34-91)

| item | line | verdict | id / why |
|---|---|---|---|
| D1 `names.json` non-atomic write + unguarded read-modify-write, can lose the roster | 54-57 | FOLDED | roadmap node `AuditFix2` (status: planned) backlog list; BUGS.md §1 D1, re-confirmed 2026-09-22 against the native port. |
| D2 Re-transcribe with missing audio destroys the transcript, marks done+empty | 58-60 | FOLDED | roadmap `AuditFix2`; BUGS.md §1 D2, same file:line. |
| D3 Vault export deletes-then-copies under the original filename, three lanes | 61-63 | FOLDED | roadmap `AuditFix2`; BUGS.md §1 D3, re-confirmed 2026-09-22 (a third lane found, `convertImageMarkers`). |
| D4 Whole recording lost if the app dies mid-recording | 64-70 | FOLDED | roadmap `AuditFix2`; BUGS.md §1 D4; SPEC C99/D26; issue #14. |
| P1 `MemosListView` per-row full-corpus scans | 73-75 | FOLDED | SPEC R92/C279 ("hoist every per-row derived lookup"); plan/perf-sweep.md §1 confirms still open at the same lines. |
| P2 `AppPaths.recordingsDirectory` mkdirs on every access | 76 | FOLDED | SPEC R93/C280; plan/perf-sweep.md §1 confirms still open. |
| P3 `MemosListView` DEBUG-only per-keystroke corpus scan | 77-78 | FOLDED | roadmap `AuditFix2` backlog line; plan/perf-sweep.md §1 confirms "still open, confirmed DEBUG-only" — no C-clause needed since it never ran on prod. |
| P4 `NotesRepository.allAssets()` unscoped, faults every blob | 79-81 | FOLDED | SPEC R91/C278; plan/perf-sweep.md §1, narrowed to `captureMissing` (the sibling `materializeMissing` was already fixed). |
| P5-P7 SourceTaxonomy double parse · SpeakerTranscript uncached regex · NamesStore re-decode | 82-83 | OPEN | Not in `AuditFix2`'s backlog list (only P1-P4 are) and no C/R number exists. Tracked as "still open" in BUGS.md §2 "Small repeated costs" and plan/perf-sweep.md §1, but nothing folds them into a clause yet. Needs a C-clause in the pattern of C277-C281, or adding to `AuditFix2`'s backlog. |
| "Then" — launch/foreground sweep chain, 9 unwatermarked `@MainActor` sweeps | 86-87 | FOLDED | SPEC R94/C281; roadmap `AuditFix2` backlog ("Sweep chain watermarks + off-main"). |
| "Then" — 20 Hz / 2 Hz whole-screen invalidation, conversation playback + audiobook read-along | 88 | OPEN | Not in any ledger. (A different, already-fixed 20 Hz issue exists — the note-editor karaoke re-render, roadmap node `NEdit`, done 2026-07-10 — but it is not this one.) Needs a perf-sweep §2 candidate row or a roadmap `AuditFix2` backlog line. |
| "Then" — concurrency: `isTranscribing` counter, `MacRecorder.stop` queue-drain, live-caption Task ordering | 89-90 | FOLDED | roadmap `AuditFix2` backlog ("Concurrency - isTranscribing counter, MacRecorder drain, caption ordering"); plan/perf-sweep.md §1 confirms the first two still open (flagged correctness, not speed). |
| "Then" — tooling: SwiftLint baseline, duplication report, signposts, `-warn-long-function-bodies` | 91 | FOLDED | roadmap `AuditFix2` backlog, verbatim ("SwiftLint baseline ratchet + duplication report + pipeline signposts"). |

## 🎚️ OPEN IDEA — importance: 3 buttons instead of 10 circles (lines 93-130)

| item | line | verdict | id / why |
|---|---|---|---|
| Collapse the 10-step significance scale to 3 (or 4) buttons | 93-130 | FOLDED | roadmap idea `i23`, verbatim restatement including the open sub-decision (3 vs 4 buttons). Still just an idea, not decided or built. |

## 📱 BLOCKED ON APPLE — TestFlight installs 404 (lines 132-159)

| item | line | verdict | id / why |
|---|---|---|---|
| TestFlight builds 166/167/168 404 on install; root cause = Apple-side force-expiry / App Availability; remedy = Feedback Assistant + sysdiagnose + support callback; Ad Hoc unblocks testers meanwhile | 132-159 | OPEN | The branch that researched this (`claude/testflight-install-failure-c89268`) merged to main (commit `f150455a`, confirmed on `origin/main`), so the docs are current, but the underlying Apple-side block is not tracked as resolved anywhere and has no SPEC/BUGS/roadmap entry. The full current text lives at `archive/state-2026-09/TESTFLIGHT_INSTALL_HANDOFF.md` (frozen doc, not superseded by a decision). Needs a BUGS.md or roadmap line: "blocked on Apple support ticket; Ad Hoc distribution is the fallback." |

## 🧠 IDEA MENU — getting more out of the notes you already have (lines 161-333)

Doctrine + 21 lettered/numbered ideas. Cross-checked against SPEC.md's "Parked ideas" list
(around line 1546) and roadmap.yaml ideas i18-i22 plus the pre-existing import-sourced ideas
(P4c, P6d, P7b, P8a).

| item | line | verdict | id / why |
|---|---|---|---|
| Doctrine for a dumb local model (escrow→generate→verify→bail, 7 rules) | 166-193 | FOLDED | roadmap idea `i19`, verbatim restatement of the doctrine. |
| A1 Cluster the embedding index into themes | 197-206 | FOLDED | roadmap idea `i18`, point (1). |
| A2 Prosody heat from word timings | 207-218 | FOLDED | roadmap idea `i18`, point (2). |
| A3 Speaker-scoped retrieval | 219-225 | FOLDED | roadmap idea `i18`, point (3). |
| A4 Open loops (rule-matched, no model) | 226-231 | FOLDED | roadmap idea `i18`, point (4). |
| B1 `.nameType` → unlinked-mention mining | 236-240 | FOLDED | roadmap idea `i21`; also pre-existing roadmap node `P7b`. |
| B2 `.sentimentScore` as a retrieval facet | 241-243 | OPEN | Not named in SPEC's parked-ideas list or in i18-i22. Needs its own idea entry. |
| B3 `SoundAnalysis` ambient labels | 244-248 | FOLDED | roadmap idea `i22`, point (2). |
| B4 `EventKit` calendar join | 249-253 | FOLDED | roadmap idea `i22`, point (1). |
| C1 Cluster labels (naming for A1) | 259-261 | OPEN | i18 covers the clustering itself but not the labeling sub-step. Not named elsewhere. |
| C2 Decision extraction → running decision log | 262-268 | OPEN | Not in SPEC's parked list or any roadmap idea. |
| C3 Action/todo extraction | 269-270 | OPEN | Same — not tracked anywhere. |
| C4 Open-loop resolution (LLM confirm step over A4) | 271-274 | OPEN | i18 point (4) covers the rule-matched open loops only, not this LLM verb. |
| C5 Tag suggestion from a closed set | 275-277 | OPEN | Not tracked. |
| C6 Contradiction / evolution detector | 278-281 | OPEN | Not tracked. |
| C7 Ramble modes (Note/Bullets/Email/To-do) | 282-285 | FOLDED | Pre-existing roadmap node `P4c` ("'Clean up my ramble' modes"); SPEC's parked-ideas list names "ramble modes" explicitly. |
| C8 Query expansion for search | 286-289 | FOLDED | SPEC's parked-ideas list: "query expansion / themes (i18)". |
| C9 Per-turn conversation summary | 290-291 | OPEN | Not tracked. |
| C10 Auto-title on capture | 292-293 | FOLDED | Pre-existing roadmap node `P6d` ("Instant auto-transcribe + auto-title a capture"). |
| C11 Person digest ("what Jack and I keep circling") | 294 | OPEN | Not tracked. |
| C12 On-this-day card | 295-296 | FOLDED | Pre-existing roadmap node `P8a` ("On This Day (memos from this date, prior years)"). |
| D Monthly digest, full execution plan | 298-322 | FOLDED | roadmap idea `i20`; SPEC's parked-ideas list: "monthly digest". |
| Build order (5-step prioritization of the above) | 324-330 | — | Not a separate item — a sequencing note over the ideas above, all already verdicted. |

## ⭐ RESUME HERE (branch `claude/book-sharing-devices-rygara`) (lines 336-367)

| item | line | verdict | id / why |
|---|---|---|---|
| Book sharing — 5 chunks built, UNTESTED, device round owed | 343-353 | DONE-SINCE | Branch merged to main, commit `db9b6ff6`; round-trip proven on a real device 2026-08-12 (backlog's own later section, lines 432-472); roadmap node `BookShare` status `done` (2026-08-12); SPEC D27 "merge to main now" (decided 2026-09-22). |
| Recording data-loss P0 (duplicate of D4 above) | 355-360 | FOLDED | Same as D4 above — SPEC C99/D26, BUGS.md §1 D4, issue #14. |

## 🔋 Low Power Mode / 📖 removed-transcript entries (lines 370-472)

Both fixed and device-confirmed within the doc itself (lines 385-398); no open item. Two
sub-items from the device round-trip proof are still open:

| item | line | verdict | id / why |
|---|---|---|---|
| `BookBundle.derivedSidecars` packs a rejected/empty alignment sidecar | 454-461, 471-472 | FOLDED | SPEC D83 ("BookBundle packs a rejected alignment sidecar: fix in v1 now. Default: yes"), decided 2026-09-22. Code still unfixed as of this read (`BookBundle.swift:258-269` packs any file that exists, no verdict check) — decision made, implementation pending. |
| Duplicated author in book title ("X - Author" title + separate author line) | 462-464, 472 | OPEN | Not mentioned anywhere in SPEC, BUGS, or roadmap. Needs a BUGS.md row or a spec clause: book title import should not duplicate the author already on the byline field. |

## 🚨 OPEN P0 — a phone call ate a whole recording (lines 476-596)

Full triage of D4; the fix list is the operative content.

| item | line | verdict | id / why |
|---|---|---|---|
| Fix 1 — roll the file into segments (interruption / background / 60s triggers) | 571-576 | FOLDED | SPEC C99 ("Audio is persisted in segments during the take (on every interruption and every 60s)"), D26. |
| Fix 2 — sidecar marker + launch/foreground sweep, visible recovery message | 577-581 | FOLDED | SPEC C99 ("a marker plus a launch sweep rebuilds the note and says so"), D26. |
| Fix 3 — `BackgroundTask` assertion while backgrounding + finalize on `willTerminate` | 582-584 | FOLDED | SPEC C99 ("a force-quit finalises"); D26 covers "all three." |
| Fix 3b — make prod diagnosable: recording lifecycle to `os_log` in Release, not just DEBUG `DevLog` | 585-588 | OPEN | Not named in C99 or anywhere else. A real, separate ask (Release-build diagnosability) that the fold doesn't mention. Needs its own clause or a BUGS.md note. |
| Fix 4 — orphan hygiene: clean up unrecoverable `rec_tmp_*` files | 589-590 | OPEN | Not named in C99. Needs its own line once the recovery path (fixes 1-3) exists. |
| Owed device round, "mid-record call/alarm survives" (duplicate) | 594-595 | FOLDED | Same as the RESUME-HERE entry above — C99's own check clause. |

## ⭐ CONTINUE HERE — 2026-09-21 (lines 599-638)

| item | line | verdict | id / why |
|---|---|---|---|
| OWED: iPad Polish load re-check (Gemma code moved after the mlx-swift-lm pin bump) | 630-631 | OPEN | No commit or test file found for this re-check. Not in any ledger. |
| OWED: full phone unit suite before a device push | 631 | OPEN | Not tracked; standard pre-push gate that hasn't been logged as run since the pin bump. |
| OWED: golden recording of model outputs over the corpus | 631 | OPEN | No golden-output file exists under `test-fixtures/corpus/` and no "golden" reference to model-output recording appears in SPEC/plan docs. Needed for the "v1 is not the judge" diff gate (SPEC "Not doing" section references this pattern generally, but the golden recording itself is unbuilt). |

## ⭐ CONTINUE HERE — 2026-09-18 → v2 core rewrite (lines 642-750)

| item | line | verdict | id / why |
|---|---|---|---|
| Land `claude/testflight-install-failure-c89268` (12 commits, docs + build bump) | 712-715 | DONE-SINCE | Merged into `claude/skrift-v2-core-rewrite-564928` (commit `f150455a`), confirmed present on `origin/main`. |
| Six June/July leftover branches (1-2 commits each) | 715 | — | The doc itself says "ignore" — not an item needing a verdict. |
| Body/image model audit — "a picture is always its own paragraph" proposal, ~50-file rewrite | 717-745 | FOLDED | SPEC C10, C11, C12, C13, C17, C30, D1 ("Picture = its own paragraph, enforced at write" — DECIDED 2026-09-22: yes), plus R2/R3/R33 in the required-differences table. Decided, not yet built (v2 body/image model is the first rewrite target per C1's subsystem order). |
| Re-sanitise migrated notes once for stale `ambiguousNames` offsets | 745 | FOLDED | Same fold as above — part of the C10 "enforced at write, normalised once on read" invariant. |

## Historical wraps, lines 753-1161 (2026-08-11 through 2026-08-20 sessions)

Mostly already-marked-done narrative. Open threads found inside it:

| item | line | verdict | id / why |
|---|---|---|---|
| "Share-import placed the picture wrong" (offset 0 lands after first word) | 940-942 | FOLDED | SPEC C12 (mixed-bundle picture placement) and R33 in the required-differences table — same root cause as the body/image audit above. |
| "Can't drag a picture to reposition it" | 943-944 | FOLDED | SPEC C119 ("Approved mocks, nothing built... picture drag-reposition (no mock yet; after C10)"). |
| Copy-edit test sweep #2 — 24k-char ceiling test, UNTESTED (fixture deduped instead of hitting the cap) | 949-950 | FOLDED | SPEC C32 (token-budget formula) and plan/scenarios-adverse.md scenario S4, which reproduces the same case (9k-word wall) and flags the exact gap: "amend C150 to state whether it applies to typed walls." Not closed — the amendment is still owed. |
| Copy-edit test sweep #5 — unbounded shrink is real (7% of input survives on repetitive Dutch text) | 954-958 | DONE-SINCE | Shrink guard shipped, commit `f67b135d` ("copy-edit fix wave" 2026-08-19), per the backlog's own later entry at line 1084. |
| Copy-edit fix-wave board item 1 — prompt reword for EN/NL paragraphing | 974-985 | DROPPED | The doc says so directly (line 974): "REFUTED BY THE A/B... the model won't paragraph long Dutch/mixed at temp 0 under any wording." |
| Copy-edit fix-wave board item 2 — deterministic paragraph fallback (`ensureParagraphs`) | 986-987 | DONE-SINCE | Shipped commit `f67b135d`, confirmed by the doc's own line 1084 ("+ ensureParagraphs (the wall cure)"). |
| Copy-edit fix-wave board item 3 — shrink guard | 988 | DONE-SINCE | Commit `10705445` (second pass corrected the hash; `f67b135d` is a sibling fix three minutes later). |
| Copy-edit fix-wave board item 4 — surface `coordinator.lastError` on the Mac | 989-990 | DONE-SINCE | Same commit `f67b135d` (doc line 1084: "+ lastError strip on the Mac"). |
| ConnectionsPanel is twinned (683 + 593 lines) and drifted, Mac cards vs iPad bare rows | 1140-1142 | FOLDED | SPEC C232 ("Connections chrome matches related-panel v3 + chrome-belongs v2"), tagged `[tuur]` — eyeball-only check, spec exists, build status per A126 tests. |
| The rating line is stateless ("Rated — ready to process" on an already-processed note) | 1143-1144 | DONE-SINCE | Fixed by the shared `NoteWorkState` three-state control, commit `5de2b71c` ("the iPad's verbs move to the Mac's places"), shipped 2026-08-18 per roadmap. |
| Frontmatter migration is per-note, no bulk re-export | 1145-1146 | FOLDED | SPEC D87 ("Frontmatter migration is per-note... Default: stated, no bulk verb"), decided 2026-09-22 — accepted as-is, not a bug. |
| 0.8-vs-0.2 Connections counts (13 vs 4) — two different notes, not confirmed a bug | 1147-1148 | OPEN | The doc itself only says "re-check... before treating it as a bug"; no later ledger records that recheck. Needs a one-note verification or a formal drop. |
| Mac Dev's vault setting pointed at the real vault once, then the test vault, unexplained | 1149-1151 | OPEN | Single observation, not reproduced since (2026-08-18). Not tracked in BUGS.md or SPEC. Needs a "watch for recurrence" line if it happens again — not enough evidence for a bug row yet. |

## OPEN items in this slice

**Count: 21**

Five most important, by risk:

1. **TestFlight installs still 404** (lines 132-159) — testers cannot install any build; the diagnosis is complete and archived, but no ledger tracks the outstanding Feedback-Assistant support ticket as a live to-do, so it can silently stay stuck.
2. **P0 recording-loss prod diagnosability** (lines 585-588) — even once the D4/C99 fix lands, prod has no `os_log` trail for the recording lifecycle, so the next "it vanished" report costs another multi-day forensic hunt like this one did.
3. **Golden model-output recording for the v2 corpus** (line 631) — blocks the stated v2 gate ("v1 is not the judge," every corpus output compared against a recorded baseline); nothing has recorded that baseline yet.
4. **Pull Tuur's lost recording off the phone** (lines 23-24) — the one irreplaceable, time-sensitive action in the whole slice; unconfirmed anywhere that it happened.
5. **20 Hz/2 Hz whole-screen invalidation in conversation playback + audiobook read-along** (line 88) — a real, named perf complaint with a file-level lead that never made it into `AuditFix2`'s backlog or any perf-sweep row, so it is currently invisible to whoever picks that node up next.
