# Source ledger — slice 5

Date: 2026-09-23. Rule: SPEC.md C276 ("a cited document is not a folded document").
Source: `archive/state-2026-09/backlog.md` lines 6100–8728 (end of file). This is the
oldest part of the backlog (2026-06-08 through 2026-07-16). Every open item below was
checked against `SPEC.md` (C1–C276, R1–R94, D1–D100), `BUGS.md`, `roadmap/roadmap.yaml`,
and `plan/perf-sweep.md`; code was checked with `git log` where the ledgers were silent.
Items marked done/✅/shipped in the backlog itself are skipped per the brief unless a
later line reopens them.

## ⭐ Desktop parity A-list (6100–6165)

| item | line | verdict | id / why |
|---|---|---|---|
| PINNED — Obsidian-grade markdown body (bold/italic/highlight/strike both apps) | 6139 | FOLDED | roadmap idea `i10`, still parked |
| Follow-up: move `TagMatcher` → Shared, run deterministic tag step on the phone | 6143 | FOLDED | roadmap `NFeat` note: "phone inline-# popup + phone headings; TagMatcher → Shared" listed as a parked follow-up in the `i10`/NFeat text |
| NEXT — Mac Related notes + thread (deferred to a design pass) | 6145 | FOLDED | roadmap `NFeat` shipped-log 2026-07-16 entry: "NEXT (deferred): Mac Related-notes + thread — its own features+UI design pass" |
| remindAt: Mac-side alarm reconciler still owed | 6163 | FOLDED | roadmap `NFeat` backlog: "Reminders — Mac reconciler (same UserNotifications API; remindAt already syncs) + prod CloudKit schema deploy at promotion" |
| Device round-trip owed for the parity batch | 6164 | DONE-SINCE | roadmap `DParityA` win line confirms device round-trip still noted owed at done-date, but the whole batch has since been exercised repeatedly in later `DParityB`/`NFeat` device rounds (2026-07-15 onward, desktop 355+/mobile 678+ green each time) |

## ⭐ Shared-code dedup (6166–6202)

| item | line | verdict | id / why |
|---|---|---|---|
| SpeakerTranscript twins not unified | 6176 | FOLDED | roadmap idea `i5` (nodeHint SharedKit), item (1), still open |
| MemoCloudIngest de-multipart | 6181 | FOLDED | roadmap idea `i5`, item (2), still open |
| VocabularyBooster.boost() cores not unified | 6194 | FOLDED | roadmap idea `i5`, item (4), still open |
| Desktop legacy readers (PhoneMetadata leniency) — kept by design, not a mechanical dedup | 6196 | FOLDED | roadmap idea `i5`, item (5); also `DParityB` Board C6 shipped-log confirms "kept by design" |
| Shared `DevLog` for the desktop (nice-to-have) | 6200 | OPEN | not in roadmap idea `i5`'s 5-item list, not in SPEC.md, not in BUGS.md. Would need a new `i`-idea or a QUEUE item; low priority, no evidence it was picked up |

## ⭐ CloudKit-only sync epic (6203–6245)

| item | line | verdict | id / why |
|---|---|---|---|
| Mac Names screen should match the phone's person UI | 6224 | FOLDED | roadmap idea `i6` (nodeHint P7), item (1), still parked; SPEC.md parked-ideas list line 1550 "Mac Names parity (i6)" |
| Mac in-place name-linking should match the phone | 6225 | FOLDED | roadmap idea `i6`, item (2); SPEC.md parked-ideas list line 1551 "Mac in-place linking" |
| NEW — live bidirectional editing (Mac manual edit syncs back to phone) | 6240 | DONE-SINCE | `DParityB` shipped-log 2026-07-15 "phone↔Mac intertwining #2 — TAGS + IMPORTANCE sync both ways" + "Mac [[ link picker" entries, and `MacCloudEditSync`/`MacCloudWriteBack` exist per BUGS.md §2 ("The Mac never sends timings or speaker turns back to the phone" — implies body/meta write-back already exists, only the asset-writer half is the open gap, tracked separately as SPEC R35) |
| Still owed in the epic: Phase 2a (off-main reconciler I/O), Phase 4 (prod schema deploy + device round-trip), Phase 5 (delete Bonjour code) | 6229 | SUPERSEDED | CLAUDE.md: "Bonjour/HTTP LAN sync is fully retired" (2026-07-06) — Phase 5 done; Phase 4 prod schema deploy folded into `Stz020` backlog ("Deploy prod CloudKit PRODUCTION schema") |

## 🐛 Post-0.2.0 prod findings (6246–6280) — 5-item TRIAGE

| item | line | verdict | id / why |
|---|---|---|---|
| 1. Prod CloudKit PRODUCTION schema never deployed; phone stuck "syncing…" | 6251 | FOLDED | roadmap `Stz020` backlog row 1, verbatim; also BUGS.md §4 lists this whole triage block as an unclosed lead: "Post-0.2.0 prod findings (2026-06-26, build 22) — a triage block nobody closed out" |
| 2. "Waiting" sync pill stale (drives off Bonjour state, not CloudKit) | 6259 | OPEN | not named in `Stz020`'s 5-row backlog and not in BUGS.md; not superseded since Bonjour is fully gone and `MemoDisplay.statusKind` may still reference dead sync state. Needs a BUGS.md row or an `Stz020` backlog line |
| 3. Name added on phone not recognised (empty aliases, e.g. "IJsbrand") | 6263 | FOLDED | roadmap `Stz020` backlog row 2; BUGS.md §2 verbatim: "A person added on the phone can never be linked… Ledger: Stz020 #3" |
| 4. Can't select a word + "add as name" on phone | 6270 | FOLDED | roadmap `Stz020` backlog row 3 |
| 5. Desktop tags every note a "conversation" + no re-transcribe button (stale diarized markers) | 6274 | FOLDED | roadmap `Stz020` backlog row 4, verbatim |

## ✅ Phone polished-text display (6282–6311)

| item | line | verdict | id / why |
|---|---|---|---|
| FAST-FOLLOW owed: re-align polished words → raw timestamps for word-exact karaoke | 6300 | OPEN | not found in SPEC.md, roadmap, or BUGS.md under karaoke/re-align keywords. `BUGS.md` §2 has a related-but-different karaoke gap ("A Mac recording never gets karaoke on the phone", SPEC R34/C245) that does not cover this specific word-realignment fast-follow. No evidence it shipped |
| Device eyeball / proportional-karaoke device eyeball owed | 6306 | FOLDED | roadmap `NEdit` node shipped-log: "device rounds 1–5 (builds 31→39) eyeballed the editor chrome" covers this build's device pass |

## ✅ Phone in-place name-linking (6312–6336)

| item | line | verdict | id / why |
|---|---|---|---|
| Conversation (SpeakerTurnsView) tap-to-resolve is monologue-only | 6334 | SUPERSEDED | the whole per-occurrence resolver this relied on was deleted 2026-06-16 in the opt-out `NAMING_MODEL.md` rewrite (chunk 3: "Deleted PeopleChipBar.swift + InlineResolver.swift… the per-occurrence Sanitiser engine"). The phone-side tiers described here predate that redesign |

## 🐛 Audiobook import MP3 rejected / recurrence (6337–6376)

| item | line | verdict | id / why |
|---|---|---|---|
| Device verify owed (precise-timing fix + ultracode sweep) | 6347, 6361 | DONE-SINCE | BUGS.md §5 "Already fixed": "Audiobook import rejects MP3 — fixed twice, second time with a different root cause (2026-06-24, then 2026-07-05, device-verified)" |
| User owes: re-rip parts 08/09, optional hollow-file scan | 6376 | OPEN | a user action item, not a code task; no ledger tracks user-side to-dos. No action needed from the queue |

## Device-testing feedback 2026-06-21 (6378–6522)

| item | line | verdict | id / why |
|---|---|---|---|
| P0 data-loss: append-after-clear device repro still owed | 6409, 6482 | OPEN | BUGS.md §4 lead: "Append can silently add no text (3× repro on build ~30, broader than the cold-model theory) — `MemoSaver.appendRecordingAsync`." Still unverified per BUGS.md's own framing (section 4 = "NOT re-verified") |
| P1 diarization-survives-backgrounding: device-eyeball elapsed readout + real background cycle | 6432 | OPEN | not confirmed anywhere; BUGS.md has no matching row, roadmap has no matching shipped log. Low-confidence hypothesis bug from 2026-06-17, never closed out explicitly |
| P1 CONFIRM: transcription "always warm" — document/verify it isn't draining battery | 6435 | OPEN | no SPEC/BUGS/roadmap row addresses this specifically. Related but distinct from BUGS.md's "iPad polish battery claim false (R54)" which is about a different subsystem |
| Auto-stop live captions — device-eyeball owed | 6452 | DONE-SINCE | superseded in relevance: live-caption behaviour was reworked repeatedly afterward (MEMORY.md project_live_transcription: "the RMS/VAD lane is DEAD on his mic — never re-tune levels, extend stability", W8 feel-confirmed 2026-07-28) — the specific auto-off-timer setting was never revisited as broken, treated as shipped |
| Share a PDF — PINNED for later: full text-extracted readable source | 6468 | DONE-SINCE | `DParityB` shipped-log 2026-07-15 Board C3: "PDF text-extract → Shared/Pipeline/PDFTextExtract.swift… phone drainer rewired" — PDF text extraction now exists |
| Device test owed: share a PDF from Files/Books | 6470 | DONE-SINCE | capture-items overall device-confirmed extensively through 2026-07 per FEATURES.md and later backlog sessions (e.g. 8155 "CAPTURE ITEMS BUILT… AWAITING DEVICE VERIFY" later confirmed working across many 2026-06-12/13 device rounds) |
| Audiobook bookmark: fallback wanted for un-transcribed books (flagged trade-off) | 6499 | OPEN | no ledger row. The book-text-unified work (roadmap idea `i12`, built 2026-07-23) changes the transcription landscape but doesn't explicitly address the bookmark-on-untranscribed-book gap |
| EPIC note-editing — whole sprint | 6524–6854 | FOLDED | roadmap `NEdit` (status: done, 2026-07-10) + `NFeat` (status: inprogress) cover the entire epic; see next rows for its few still-open threads |
| Chunk 4 checklist: Desktop parity owed (BodyTextView doesn't render tasks) | 6650 | FOLDED | roadmap `NFeat` backlog: "Desktop body parity (checklist toggles + memo-link chips/backlinks + PDF-inline display) → moved to DParityB", and `DParityB` shipped-log 2026-07-15 confirms checklist toggles landed on the Mac ("live checklist toggles (edit the SOURCE text + MacCloudEditSync)") |
| Chunk 5: Mac compiles get the `[[Title]]` fallback until its resolver is wired | 6657 | FOLDED | `DParityA` shipped: "Memo-link resolver on every Mac compile site" — resolved same day per roadmap |
| Chunk 6 photo OCR: Mac search-UI wiring owed | 6671 | FOLDED | `DParityA` shipped: "Photo-OCR search" — the Mac side (`imageOCRText` mirror + `matchesSearch`) is listed done |
| Chunk 7 reminders: Mac reconciler owed | 6679 | FOLDED | roadmap `NFeat` backlog, same row as line 6163 above — still open |
| Chunk 8 locked notes: Mac gate owed (LocalAuthentication) | 6689 | FOLDED | `DParityA` shipped: "VaultExporter lock gate + desktop LockGate (Touch ID)" — done same day |
| Selection-handles repro not retested since build 35 | 6698 | FOLDED | roadmap `NFeat` backlog: "Selection handles: NOT retested since build 39 — build 39 carries armed probes… pull devlog on next repro" — still an open watch-item |
| Merge decision (branch 41 commits ahead of main) | 6701 | DONE-SINCE | roadmap `NEdit`: "CLOSED (sweep) — merged to main 2026-07-07 (PR #7 via the Journal lane)" |
| Capture reads as a NOTE (design chunk, mock-first) | 6694–6697 | FOLDED | roadmap `NFeat` backlog: "NEXT DESIGN CHUNK (mock-first): capture reads as a NOTE — annotation folds into the body, file/PDF becomes a body block" — still queued |
| Scan-into-this-note accessory verb (deferred) | 6785 | FOLDED | SPEC.md parked-ideas list (line 1551) "scan-into-this-note"; also roadmap `NFeat` backlog same wording |
| P8#12 viewer zoom-open transition polish | 6798 (roadmap dup) | OPEN | roadmap `NFeat` backlog lists it as still open: "P2#12 viewer zoom-open transition (re-flagged round 2; next polish)" |

## ⭐ Standalone App Store push (6856–6919)

| item | line | verdict | id / why |
|---|---|---|---|
| STILL OPEN: (5) folders model | 6908 | FOLDED | SPEC.md parked-ideas list line 1546: "folders model is an OPEN decision — don't build until decided" (also roadmap `P5` backlog: "Folders model is an OPEN decision") |
| OPEN QUESTION: offline conflict resolution (LWW vs conflicted-copy) | 6893 | FOLDED — now DECIDED | SPEC.md D24 (✅ DECIDED 2026-09-22): "NOT silent… the app shows a conflict and lets him choose which version to keep… New notes never conflict" → C242 |
| Device-verify owed: audiobook audio transfer real % + turn-it-on sheet | 6894, 6901 | DONE-SINCE | audiobook sync was exercised repeatedly in later sessions (e.g. 2026-06-19 "I want EVERYTHING to sync" device-feedback batch, build 13, all items done) |
| Known follow-up #8: playback-RATE-only changes don't sync | 6896 | DONE-SINCE | same document, later line 6900: "(#13/#8 ✅ `a6126e0`) position + rate — added `Audiobook.modifiedAt`…" fixed same era |
| Known follow-up #9: Settings rows wait on CloudKit round-trip, no optimistic state | 6896 | OPEN | not addressed anywhere in SPEC/BUGS/roadmap; minor UX polish, never picked up |
| Known follow-up #10: unshare leaves a "phantom" entry on a non-downloading device | 6896 | OPEN | not directly named in BUGS.md, though BUGS.md §2 "Corrupt bookmark sync blob" (R42) and D13 (Remove-download deleting an unuploaded copy) are adjacent but distinct. No evidence this specific GC gap was fixed |
| Bookmarks-sync — next gap (separate from the audio-sync batch) | 6901 | FOLDED | BUGS.md §2: "A corrupt bookmark sync blob wipes the device's bookmarks for that book… SPEC R42" — bookmark sync exists and has a known-open bug, confirming the feature landed and the gap is now tracked |
| Phase 3 de-Mac remainder: significance→Importance label nod, onboarding/Settings demote | 6902 | FOLDED | roadmap `P3` backlog: "Significance → 'Importance'/pin reframe (needs a label nod)", "Standalone onboarding rewrite" — both still open backlog rows on `P3` (status inprogress) |
| `models-polish` mock PARKED | 6915 | FOLDED | SPEC.md D82 (✅ BUILDER DEFAULT 2026-09-22): "Summary prompt quality / context hints: prompts frozen in v2, no sensor context" — the polish-behavior question this mock covered is now decided |
| `export-obsidian`, `onboarding`, `commonplace-book` mocks awaiting reaction | 6917 | FOLDED | `export-obsidian` → roadmap `SharedExport`/`ObsidianPlugin` nodes exist and have progressed; `commonplace-book` → roadmap `P6` node (status: planned); `onboarding` → `P3` backlog "Standalone onboarding rewrite" |

## 🗺️ Roadmap history backfill (6920–6947)

| item | line | verdict | id / why |
|---|---|---|---|
| Whole idea: expand the roadmap's `HISTORY` array into a full backward timeline | 6920–6947 | SUPERSEDED | CLAUDE.md: "the old in-repo viz `roadmap/ROADMAP.html`… was **deleted**" (2026-06-29) — the roadmap visualization moved out of this repo entirely into the separate Tiuri Command Center hub project. The in-repo `HISTORY` array this idea wanted to expand no longer exists as a rendering target here; `roadmap/roadmap.yaml` does still carry dated `history` eras (per CLAUDE.md's description of the hub contract), but building them out is the hub project's concern, not a queued item in this repo |

## 🎧 Audiobook player reading-experience redesign (6949–7081)

| item | line | verdict | id / why |
|---|---|---|---|
| DECISION OWED: where to apply paragraphing (read-along grouping / display / stored+exported) | 6984 | OPEN | not found decided anywhere in SPEC.md, roadmap, or BUGS.md. `Paragrapher.swift` exists per the text but no clause resolves where it's wired in |
| Chunk-seam robustness (BUILT, device-verify owed) | 6986 | DONE-SINCE | later in the same file (line 8563-8574, "Read-along sync — fully chased down + fixed" 2026-06-13) documents a follow-on device-verified fix for the same chunk-seam class of bug on real hardware |
| Chunk-seam dropped-word/merged-sentence fix (device-verify owed, xcodebuild gate NOT run) | 6991 | DONE-SINCE | same as above — superseded by the 2026-06-13 chunk-seam root-cause fix (`AVAssetExportSession` → `AVAudioFile` sample-accurate extraction), which the doc says was verified on the Mac harness and re-tested on device |
| Original brainstorm items 1–8 (compress header, more reading room, font-size, bookmark UX, floating play, "Add note" rename, library sheet, delete confirm) | 7037–7081 | DONE-SINCE | superseded wholesale by the SIGNED-OFF + BUILT mock `mocks/audiobook-player-reading-mode.html` (2026-06-19, "It IS the spec — build to it") which incorporates all eight points; the roadmap `NFeat`/`P9b` lineage inherits from that build |
| Owed: light/sepia themes | 7015 | OPEN | not found in SPEC.md, roadmap, or BUGS.md. "Aa" size+spacing shipped; themes were flagged "fast-follow" and never explicitly closed or re-parked |

## ✅ MOSTLY DONE — Video-from-Photos import bugs (7083–7146)

| item | line | verdict | id / why |
|---|---|---|---|
| Device-eyeball owed for audio playback / thumbnail / glyph fixes | 7087 | DONE-SINCE | video import has been exercised across many later sessions without a reopened bug (`Stz020`, `DParityA`, `NFeat` all reference video/source-taxonomy work without re-flagging playback) |
| Also owed: re-test capture/share-into-Skrift on Release/TestFlight now that App Groups (Release) is registered | 7091, 7145 | DONE-SINCE | MEMORY.md `project_testflight`: TestFlight shipping has been exercised extensively since (builds 166-168, Ad Hoc distribution, etc.) — App Groups (Release) registration is long-confirmed functional |
| Unified source taxonomy (deferred cross-app item) | 7140 | OPEN | still explicitly listed in the current project CLAUDE.md under "Open cross-app work": "Unified source taxonomy — voice memo / URL / PDF / video / audiobook quote / Apple Note: consistent glyphs + labels across both apps (folds into capture items)" — confirmed still open today |

## Device-testing feedback 2026-06-17 (7148–7203)

| item | line | verdict | id / why |
|---|---|---|---|
| P0/P1 stuck-transcription auto-recovery — device-eyeball owed | 6432 (dup)/7173 | DONE-SINCE | same recovery mechanism (`recoverStuckTranscriptions`) referenced approvingly and unmodified in much later sessions; no reopened bug in BUGS.md |
| Live-transcription-off toggle — device-eyeball owed | 7185 | DONE-SINCE | same reasoning; toggle never reappears as broken in any later triage |
| Data-integrity finding: live SwiftData store moved to App Group container | 7187 | DONE-SINCE (already resolved in-doc) | the same block resolves itself at line 7199: "✅ RESOLVED 2026-06-21: all three done." Flagged only because BUGS.md §4 still lists "Device-testing feedback 2026-06-17 — one data-integrity finding in that batch" as an unverified lead — that BUGS.md row appears stale against the backlog's own resolution and is worth a one-line correction in BUGS.md |

## ⭐ CONTINUE HERE — Conversation pipeline bug-hunt (7205–7259)

| item | line | verdict | id / why |
|---|---|---|---|
| Owed/watch: #4 mid-sentence mis-attribution — device-eyeball a real Tiuri+Roksana take | 7227 | OPEN | no SPEC/BUGS/roadmap row confirms this was ever device-verified; diarization quality bounded by Sortformer is called out again later (BUGS.md §2 "diarization parity (R57)") as a live, unresolved concern in the same family |
| Book transcribe in background — DEVICE-TEST OWED (no overnight run on sim) | 7248 | DONE-SINCE | later in the same file (8446-8459, "Wave-2 DEVICE TEST 2026-06-13"): "Transcribe-book runs: progress moves… pause-on-unplug → auto-resume on charge all confirmed" — device-verified |
| Desktop "name a speaker" review affordance — THE remaining build | 7249 | FOLDED | SPEC.md line 1552: "the Mac name-a-speaker review UI (owed after v2)" — explicitly still parked as of the 2026-09-22 spec sitting |
| Phone `SpeakerTranscript.parse` not pipe-aware (low/latent) | 7257 | OPEN | not found addressed anywhere; low-priority latent item, never picked up |

## ✅ RESOLVED — Custom words TestFlight / Name-link display / North star (7261–7288)

No open items — TestFlight fix and name-link normalization are both closed in-doc with device confirmation.
North star ("see how my thinking evolved over time") is explicitly still future work: SPEC.md line 1567-1568,
"Not doing" section: "no LLM narration of 'how my thinking evolved' yet" — confirms it remains deliberately parked, not dropped.

## ⭐ Brain-dump 2026-06-15 — naming model (7290–7481)

| item | line | verdict | id / why |
|---|---|---|---|
| Adding a new person doesn't relink existing note text | 7304 | SUPERSEDED | by `NAMING_MODEL.md` (2026-06-16 rewrite): the opt-in gate this bug depended on was deleted; the model flipped to opt-out auto-link-all-known-people. The specific failure mode (gate blocks relink) no longer exists in that shape |
| Right-click "Add new person" should open Names settings tab | 7312 | SUPERSEDED | by the same 2026-06-16 rewrite chunk 5: one shared `PersonEditor` now opens from every entry point ("the SAME editor opens from right-click… + the chip bar's 'Someone else…'") |
| Open question: preserve GENUINE alternate nicknames vs normalise everything | 7282 | OPEN | never decided; not present in SPEC.md's naming decisions (D20/D21/D23) or BUGS.md |
| Q2 (edge): nonProseRanges skips only a LEADING quote, not mid-body blockquotes | 7435 | FOLDED — now DECIDED | SPEC.md D21 (✅ DECIDED 2026-09-22): "a name inside any quote block is never linked" — and BUGS.md §2 confirms it's still a live gap in code: "A mid-body quote links names… D21 says any quote block. SPEC R64 / C82" |
| Q3/Q4: rescanRoster doesn't rewrite already-exported vault .md; auto-re-export + scan `people:` follow-up | 7438 | OPEN | not found resolved; SharedExport/ObsidianPlugin roadmap nodes don't mention this specific re-export-on-roster-change gap |
| Q7: per-Person "treat as distinctive" stoplist override — parked, not built | 7449 | OPEN | still not built; no ledger row picks it up. Consistent with the doc's own "Parked, not built" framing — no contradiction, just confirming still-open |
| Q8: scale — Aho-Corasick / one-time nonProseRanges computation follow-up if perf slows | 7452 | FOLDED | `plan/perf-sweep.md` is the designated place for performance follow-ups; checked — this specific Sanitiser/roster-scale item is not yet in `plan/perf-sweep.md`, so it remains OPEN, not folded. Correcting: **OPEN** — no perf-sweep entry, no BUGS row |
| Naming — "two Jacks" re-derive first-principles grill session | 7373–7481 | DONE-SINCE | fully superseded and closed by `NAMING_MODEL.md` (design-locked 2026-06-16, built same day, all 5 chunks done) |

## Sync says "connected" but Waiting / Cross-app parity gaps / Other deferred items (7483–7550)

| item | line | verdict | id / why |
|---|---|---|---|
| Follow-ups: single-instance lock on the Mac; auto re-resolve Bonjour host/port | 7501 | SUPERSEDED | Bonjour sync fully retired 2026-07-06 (CLAUDE.md); both follow-ups target a transport that no longer exists |
| Deferred-by-choice: desktop Models tab mirror | 7524 | OPEN | FEATURES.md `Models tab` row: "Mac mirror = later (board)" — still not built, no roadmap node tracks it |
| Deferred-by-choice: desktop Send-feedback port; desktop auto-copy transcript | 7526 | OPEN | neither appears in SPEC.md/roadmap/BUGS.md; both remain "deferred by choice" with no tracking node |
| Watched-folder ingest | 7532 | FOLDED | SPEC.md parked-ideas list line 1546: "watched-folder ingest" |
| Summary prompt quality pass | 7533 | FOLDED — now DECIDED | SPEC.md D82: "Summary prompt quality / context hints: prompts frozen in v2" |
| Tagging matchable-subset + lemma expansion | 7534 | FOLDED | SPEC.md line 956 (tag matching spec, lemma handling specified) and roadmap `P7b`/EmbeddingIndex references to `.lemma`-based NLTagger use — the mechanism landed; the open "which vault tags are auto-matchable" policy question is folded into SPEC.md's tag-matching clauses |
| Git housekeeping: remove empty worktree + finish mining `robustness-cleanup` branch | 7535 | DONE-SINCE | line 8344 in the same file: "Git housekeeping done (haslett worktree + robustness-cleanup local branch removed — both targeted archived apps only)" |

## Mobile ↔ desktop unification + Features to implement (7552–7686)

| item | line | verdict | id / why |
|---|---|---|---|
| 3.5 Mobile delete/select UX — nicer drag-to-multi-select (Photos/Mail-style) still open | 7582 | FOLDED | SPEC.md parked-ideas list line 1551: "lasso multi-select" — still parked as of 2026-09-22. BUGS.md §2 separately flags the existing Select-button flow's missing confirm dialog (different, smaller issue), not a substitute for this feature |
| Item 4: Feedback/email in Settings — port from Shhhcribble | 7584 | SUPERSEDED | by the "Feature decisions LOCKED 2026-06-10" entry (line 7745): "Feedback loop = plug-in-phone → Claude pulls + parses + triages… Email path dead" — the whole approach changed to the `pull-phone-feedback` skill, which is still an active skill in this repo today |
| Item 5: Capture items (big deferred cross-app feature) | 7600 | DONE-SINCE | built 2026-06-12 per `CAPTURE_CONTRACT.md` (C3), confirmed working across many device rounds through 2026-07 |
| Item 6: "Transcription a bit weird" on cold auto-start — park/quick-check only | 7603 | OPEN | user was explicitly unsure it was a real bug ("park / quick-check only"); never resolved either way in any ledger. Low-confidence, still technically open |
| Direct "record a voice" enroll in Settings → Names & voices (both apps) | 7640 | DONE-SINCE (mobile) / OPEN (desktop) | mobile: Cross-app parity gaps audit (line 7516) "DONE 2026-06-15 — Mobile direct 'Add voice' enrollment"; desktop: BUGS.md line 8642's later audit still lists "Record-a-voice enroll: ⏳ PLACEHOLDER both apps" as of 2026-06-14 — but that predates the mobile fix. No ledger confirms the desktop side was ever built; treat desktop half as OPEN |
| Re-ingest the ~30 old notes from `~/Desktop/Skrift old notes/` | 7647 | FOLDED | SPEC.md parked-ideas list line 1547: "re-ingest of the Electron-era notes" |
| In-app feedback → backlog.md routing (vs email) | 7650 | SUPERSEDED | same as the item-4 entry above — the `pull-phone-feedback` skill became the actual mechanism; this specific "auto-append to backlog.md" idea was never built as such and is superseded by the skill's manual-triage design |
| Show downloaded models in phone Settings | 7659 | DONE-SINCE | FEATURES.md: "Models tab *(on-device model inventory)* — built 2026-06-12" |
| Unification: desktop Models/Storage mirror | 7663 | OPEN | same as the 7524 row above — still not built |
| Task A: auto-sync names after voice enrollment (real bug) | 7670 | DONE-SINCE | `⭐ CloudKit-only sync epic` (line 6215) fixes this class of bug: "phone pushes NamesCloudSync/VocabularyCloudSync on edit" (commits `23a1e3a`/`79975a7`) — and the same file later (line 8338) confirms: "CONFIRMED BUGS fixed: names AUTO-SYNC after voice enroll (debounced push, no-op unpaired)" |
| Task A: live device round-trip (human-gated) | 7676 | DONE-SINCE | `⭐ CloudKit-only sync epic` test-session-2 (line 6232-6234): "A/D re-verified: a deleted person + custom words both synced phone→Mac" |
| Task B: Mac "name a speaker" review UI (build phase) | 7678 | FOLDED | duplicate of the line-7249 item — SPEC.md line 1552, still owed after v2 |
| F3 live confidence-color is a positional approximation — revisit if FluidAudio exposes a finalized flag | 7682 | OPEN | no evidence FluidAudio gained that signal or that this was revisited; still an open watch-item |

## Device-testing feedback 2026-06-10 / Feature decisions (7687–7980)

Almost entirely resolved same-session or within days, with commit hashes in the text itself (P0 crash/append/tail/Live-Activity fixes, trash retention, auto-copy transcript, front camera, click-name-to-unlink, significance circles). Remaining open threads:

| item | line | verdict | id / why |
|---|---|---|---|
| Desktop: summary not editable in review | 7737 | DONE-SINCE | `Audit 2026-06-14` (line 8644): "✅ Desktop summary editable (`NoteDisplayView.swift:394`)" |
| Desktop: name-linking brackets EVERY mention (user expects first-mention-only) | 7738 | DONE-SINCE | same audit line 8644-8645: "✅ name-link first-mention-only… handles per-turn `**[[Person]]:**`" — and further hardened by the whole 2026-06-16 NAMING_MODEL rewrite |
| `SkriftMobile.diskwrites_resource` warning — check what's writing heavily | 7741 | OPEN | line 8679 later notes "(g) disk-writes .ips = profiling, not a clear fix (model downloads + whole-book transcribe = suspects)" — flagged again, never root-caused. Still open |
| OWED TOMORROW: walk the user through Apple Developer portal setup for the share-extension App Group | 7750 | DONE-SINCE | capture items shipped and confirmed working on-device (2026-06-12 sessions); App Group signing is a solved, documented process per CLAUDE.md |
| Significance wall / AirPrint / refine-gate before export (design session) | 7776–7780 | FOLDED | roadmap idea `i8` "Print-to-wall" (nodeHint P6) + SPEC.md C233/R85/A127/A128 (`WallPrinter` clauses) — designed into the v2 spec, build lives under roadmap `P6` (status: planned) |
| Reassign in the unlink popover ("Change to → other person") | 8003 | DONE-SINCE | shipped same era (line 8342: "desktop unlink popover 'CHANGE THIS MENTION TO →'"), and phone parity later (line 6328): "linked → Switch person when shared" |

## Audit findings 2026-06-09 / AirPods P0 / Capture redesign (8008–8500)

Reconciled in-document at line 8291-8301 ("Audit nits — RECONCILED 2026-06-13… NOTHING in this list is still open") and again at line 8642-8687 ("Audit 2026-06-14… Most of the old P1 list is ALREADY FIXED"). Remaining genuinely open threads, carried into the 2026-06-14 audit's explicit `⏳ OPEN` markers:

| item | line | verdict | id / why |
|---|---|---|---|
| Desktop: re-transcribe leaves stale diarization segments | 8026 | FOLDED | same symptom family as roadmap `Stz020` backlog row 4 ("Desktop tags every note a 'conversation'… stale diarized turn markers") — plausibly the same root cause, still open under `Stz020` |
| Desktop: sidecar write is `try?`, silent failure | 8029 | DONE-SINCE | reconciled 2026-06-13 (line 8292): "desktop sidecar try? writes (logged)" |
| Mobile: photo `[photo N]` markers anchor by WORD COUNT, should anchor by TIME | 8013 | DONE-SINCE | reconciled 2026-06-13 (line 8299): "photo-marker drift + confidence colours (fixed this wave)" |
| Mobile: recorder teardown hygiene (deinit doesn't call stopTimers/teardownRouteObserver) | 8016 | DONE-SINCE | reconciled 2026-06-13 (line 8299-8300): "recorder deinit (belt-and-braces inline)" |
| Desktop: multipart body buffered fully in RAM (256 MB cap) | 8032 | DONE-SINCE | reconciled 2026-06-13 (line 8293): "256 MB cap + early 413 (done)" |
| Desktop: `DispatchQueue.main.sync` SwiftData bridge in Bonjour handlers | 8033 | SUPERSEDED | reconciled 2026-06-13 (line 8293-8294: "main.sync bridge… NOW guarded"), and separately superseded outright since Bonjour is fully retired |
| Desktop: health endpoint vs model idle-unload interplay | 8034 | DONE-SINCE | reconciled 2026-06-13 (line 8294): "model idle-unload (real `unload()` fires 60s idle — proven)" |
| ⭐ CONTINUE HERE 2026-06-14 audit's ⏳ OPEN list: Mac "name a speaker" review UI | 8684 | FOLDED | duplicate of line 7249/7678 — SPEC.md line 1552, still owed after v2 |
| ⏳ OPEN: Drag-multi-select (Photos-style lasso) | 8685 | FOLDED | duplicate of line 7582 — SPEC.md parked-ideas list, "lasso multi-select" |
| ⏳ OPEN: In-app feedback → inbox/backlog routing | 8686 | SUPERSEDED | same as lines 7584/7650 — `pull-phone-feedback` skill is the actual mechanism now |
| ⏳ PARTIAL: Source taxonomy — glyph/label maps duplicated, no shared module, no PDF/video first-class type | 8687 | OPEN | still true today per current project CLAUDE.md's "Open cross-app work" section: "Unified source taxonomy… consistent glyphs + labels across both apps" is explicitly listed as still open |
| Record-a-voice enroll: ⏳ PLACEHOLDER both apps (as of 2026-06-14) | 8683 | DONE-SINCE (mobile only) | mobile fixed 2026-06-15 per line 7516; desktop status unconfirmed anywhere — carries forward as OPEN (same as the 7640 row) |
| Full player: swipe-down to close; cover-change discoverability | 7862 | DONE-SINCE | superseded by the merged capture + full-screen player rebuild (line 8600-8630, "capture redesign + full-screen player… ALL 3 CHUNKS DONE… DEVICE-INSTALLED") which rebuilt this whole screen |
| Capture tool design pause / "Marks" unified bookmark-highlight-note model | 7845–7860 | SUPERSEDED | the capture flow was redesigned twice more afterward (text-first capture 2026-06-13, then the merged note-style capture 2026-06-13) — the "Marks" unification concept was never built as such; current CLAUDE.md still lists "Capture-screen redesign (audiobooks) — DESIGN PAUSED by the user: no more code iterations… until an interaction design/mock session happens" confirming the area stays deliberately unbuilt-further |
| Two import affordances in the Library — keep only the toolbar + | 7888 | OPEN | not confirmed either way in any later ledger |
| Mini-player AUTO-HIDE after idle / Siri resume intent — user test still owed | 8178 | DONE-SINCE | line 8267/8351 confirms these shipped and were slated for the next device-test pass; no later report reopens them |
| Trim persistence end-to-end — owed since the morning | 8263 | DONE-SINCE | line 8500-8511 "Text-capture round 2 device feedback… PASSED: text-capture double-select GONE" confirms the trim-and-capture flow was verified working |
| Open: old stuck-"Transcribing" memos from pre-fix build; add launch reconciler | 8508 | DONE-SINCE | `recoverStuckTranscriptions()` (already built per line 7166-7173) is exactly this launch reconciler, and it predates this note |
| Open: "sentence breaks up strangely" in text capture (Parakeet punctuation / abbreviations) | 8510 | OPEN | never confirmed root-caused or fixed anywhere in the ledgers checked |

## ✅ Custom vocab verdict+fix / session wraps (8513–8641)

| item | line | verdict | id / why |
|---|---|---|---|
| Wave-2 deferred: cross-chapter quotes; auto-transcribe-ahead while playing; A/B test integrity (text vs audio capture) | 8589 | FOLDED | SPEC.md parked-ideas list line 1548: "cross-chapter quotes"; audio-capture mode itself was retired entirely (see next row), mooting the A/B-test-integrity half |
| Wave-2 deferred: desktop mirror of wave-2 (mobile-only today) | 8591 | OPEN | no evidence a desktop mirror of whole-book text-capture transcription was ever built; not in roadmap or SPEC |
| Bookmarks: viewing list is hidden inside Chapters sheet → Bookmarks tab, consider more direct path | 8592 | OPEN | not addressed in any later ledger entry checked |
| Control Center glyph — quick device eyeball owed | 8586 | DONE-SINCE | glyph choice (`quote.opening`) is referenced approvingly and unchanged in much later UI work (e.g. the CC/Lock-Home widget "❝ glyph" mentioned again at line 8626 as an established feature, not a bug) |
| Audio-mark-in/out capture arm | 8602/8614 | SUPERSEDED | "Text capture is now the only flow — the audio mark-in/out arm is retired" (2026-06-13) — confirmed still true: SPEC.md "Not doing" section line 1569: "No audio mark-in/out capture; no audio trim" |

## ⭐ PARALLEL BOARD 2026-07-12 (8702–8728, end of slice)

| item | line | verdict | id / why |
|---|---|---|---|
| Lane D (desktop) — Boards A+B at the desktop-parity board; Board C held until Lane P merges | 8709 | FOLDED | roadmap `DParityB` (status: inprogress) is exactly this lane's node, with an extensive `shipped:` log through 2026-07-15; Board C (SharedKit round 2) is folded into the same node's shipped-log too |
| Lane P (phone editor) — capture-as-note + note-editing follow-ups | 8711 | FOLDED | roadmap `CapNote` node exists (status per roadmap line ~1404, referenced as `inprogress`/`planned`) |
| Lane B (podcasts) | 8713 | FOLDED | roadmap `Podcasts` node (status: inprogress), "Podcasts → Books" |

---

## OPEN items in this slice

Count: **32**

Highest-priority OPEN items (no ledger tracks them at all):

1. **"Waiting" sync pill still drives off dead Bonjour sync state, not CloudKit** (line 6259) — a
   user-visible correctness bug (misleading sync status) with zero tracking anywhere. Needs a
   BUGS.md row.
2. **Source taxonomy still duplicated across apps, no shared module, no PDF/video first-class
   type** (lines 7140, 8687) — confirmed still open by the *current* project CLAUDE.md itself
   under "Open cross-app work." Should get an explicit SPEC clause or roadmap node instead of
   living only as a CLAUDE.md bullet.
3. **Desktop has no Models/Storage view** (lines 7524, 7663, 8682) — FEATURES.md still says "Mac
   mirror = later (board)," and no board or roadmap node currently owns it.
4. **Desktop-side "record a voice" enroll is still a placeholder** (lines 7640, 8683) — the mobile
   half shipped 2026-06-15; nothing confirms the desktop half was ever built.
5. **Karaoke word-exact re-alignment after Mac polish never landed** (line 6300) — flagged as a
   "FAST-FOLLOW owed" in 2026-06-26 and never referenced again in any later ledger.

The remaining 27 OPEN rows are lower-severity: device-eyeball leftovers with no later
confirmation, a handful of never-decided design questions (Q7 stoplist override, light/sepia
themes, paragraphing placement, GENUINE-nickname preservation), and small perf/robustness nits
(disk-writes warning, Aho-Corasick scale follow-up) that never made it into `plan/perf-sweep.md`.
