# Source ledger — archive/state-2026-09/backlog.md lines 4421–6099

Date: 2026-09-23. Built per SPEC.md C276 ("a cited document is not a folded document").
Verdicts cross-checked against SPEC.md (clauses C1–C280, required differences R1–R94,
decisions D1–D100), BUGS.md, roadmap/roadmap.yaml, plan/perf-sweep.md, and current source
where a ledger hit was inconclusive. Sections below match the `##`/`###` headings inside
this line range, in order. Fully-done sections with no reopened line are noted but not
tabled.

## 📖 ePub ↔ audiobook alignment (lines 4421–4810)

Feature is `roadmap/roadmap.yaml` node **EPubAlign**, `status: done` (2026-07-22), rounds
5–8 landed 2026-07-23. Table covers only lines still open after that close.

| item (short) | line | verdict | id / why |
|---|---|---|---|
| "1–2 more pairs still wanted" (matching-edition + messy ePub) | 4501 | SUPERSEDED | EPubAlign shipped GO off the one real pair (150:1 wrong-book separation); node note treats book-2/3 pairs as "when found," not blocking. |
| Starvation mitigation (re-align freeze fix) "not a proven root cause — needs the device to confirm" | 4639 | OPEN | Not in BUGS/SPEC/roadmap. Needs a BUGS §3 device-round row. |
| b113 built + suite-green, **not installed**; device round to confirm the re-align freeze fix | 4647 | OPEN | EPubAlign is `status: done` but its note doesn't cite this verify step; no BUGS row either. |
| Per-file resume for an app-killed-mid-align restart ("worth it if multi-file books grow") | 4649 | OPEN | Not tracked under EPubAlign or P9b (Audiobook player polish, `status: planned`). |
| BGProcessingTask ride-along for align-on-lock ("parked, standalone-phase candidate") | 4652 | OPEN | No idea/backlog entry names it. |
| AlignmentCore progress callback (real % inside one file's match) ("parked as a candidate") | 4670 | OPEN | Not tracked under P9b. |
| Unify Transcribe+Book-text menus (round 7 item 4) — text says "Not built" | 4684 | DONE-SINCE | roadmap idea **i12**: "SIGNED OFF AND BUILT 2026-07-23, same session." i12's own text still owes a phone b110 device eyeball — that sub-part stays open inside i12. |
| "images in the reader = PARKED for later" | 4740, 4807 | FOLDED | SPEC.md "Parked ideas… ePub images in the reader" + EPubAlign node note repeats it verbatim. |
| CORE2 tabled: 30s gap-bridge untuned; epubChapters detected-merge suppression stays whole-file | 4781 | OPEN | Neither knob has a clause or backlog row. |
| Persist per-file coverage % in the sidecar "at the next schema touch" | 4792 | OPEN | Not tracked. |

## 🐛 List thumbnail stale after deleting photos (lines 4812–4822)

| item | line | verdict | id / why |
|---|---|---|---|
| "OWED: device eyeball (build 86)" | 4821 | DONE-SINCE | BUGS.md §5 "Already fixed — do not re-open: List thumbnail stale after deleting photos — fixed 2026-07-18." |

## ⚡ Perf + reliability audit — 2026-07-16 (lines 4824–4892)

Section header itself says "FIX WAVE MERGED 2026-07-19"; only the unticked `[ ]` lines are
items here. `plan/perf-sweep.md` (2026-09-23, same effort as this ledger) re-audited much
of this surface fresh and is cited where it re-confirms a mechanism.

| item | line | verdict | id / why |
|---|---|---|---|
| P2 per-buffer `Task` no ordering guarantee into caption accumulator (`LiveRecordingService.swift:479-499`) | 4838 | OPEN | `feedStream` symbol not found in current `LiveRecordingService.swift` — likely refactored since. Not in perf-sweep.md's scope; needs re-verification before it can get an R-row. |
| P2 live-caption rebuilds full `AttributedString` per poll (`RecordView.swift:644-676`) | 4839 | OPEN | Code still assembles the caption as one `AttributedString` per poll (`RecordView.swift` ~L706-713). Not in perf-sweep.md (didn't scope RecordView) or BUGS.md. |
| P3 `purgeExpiredTrash()` runs sync in `SkriftApp.init()` | 4849 | OPEN | Still called synchronously at `SkriftApp.swift:64`, outside the `.task` sweep chain perf-sweep.md audited (lines 108-203, R94/C280). Not one of the nine sweeps that row covers. |
| P3 detail pager `@Query` = whole non-trashed corpus (`MemoDetailView.swift:20-21`) | 4851 | OPEN | `@Query` there is still unwindowed. perf-sweep.md's MemoDetailView findings (candidate #5) are a different cost (names/backlinks in `.task(id:)`), not this one. |
| P2 `QuoteCaptureProcessor.exportSpan` drift — needs a chunksim third lane before any code change | 4856 | OPEN | Not referenced in SPEC/BUGS/roadmap/perf-sweep. |
| P3 `BookCoverCache.image(for:)` on-main file read in body | 4858 | OPEN | Confirmed still synchronous `UIImage(contentsOfFile:)` inside `@MainActor BookCoverCache.image(for:)` (`BookCoverView.swift:66-73`). Not tracked anywhere. |
| P3 read-along `setCurrent` linear-scan + `AudiobookCloudSync.localTranscriptSignature` full decode on main | 4860 | OPEN | Repeats verbatim in the "Audiobook deep-review findings" section (line 5030); no ledger row either place. |
| P3 `ExportStateStore.persist()` whole-ledger rewrite, `publishAll()` unwired | 4865 | DONE-SINCE | `ExportStateStore.swift` no longer exists in source (only stale build artifacts remain). The phone export path was rebuilt on the shared export engine, commit `cb096394` ("the iPhone/iPad export, rebuilt on the shared engine + its missing front door"). |
| P3 `NamesMerge` millisecond-tie always favors remote; `MacCloudWriteBack` wall-clock LWW has no skew tolerance; `MemoCloudIngest` Bonjour double-ingest comment likely dead | 4866 | FOLDED | BUGS.md §4 lists "`NamesMerge` millisecond-tie always favours remote… `MacCloudWriteBack` wall-clock LWW has no skew tolerance" verbatim as an unverified lead. |
| P2 LINKED-FROM backlinks full-corpus body scan per note switch (`NoteDisplayView.swift:501-511`) | 4874 | OPEN | Cost relocated, not fixed: `ConnectionsPanel.swift:119` `backlinkScan(for:in:)`, comment reads "the old MemoBacklinks strip's scan, unchanged." No ledger row. |
| "PHONE PARITY still owed" for Connections query-failure empty state | 4884 | OPEN | Sub-note of a ticked item; the Mac half shipped, nothing tracks the phone half. |
| P2 actor-reentrancy window: a query during a sweep's await can see a mid-swap memo | 4888 | OPEN | "Structural M," no clause anywhere. |
| P3 `ConnectionsModel` backlink full-corpus scan per note switch (mobile) | 4889 | OPEN | Same underlying cost as the `NoteDisplayView`/`ConnectionsPanel` item above, different app; no ledger row. |
| P3 ANE-compile hang has no timeout/retry affordance | 4890 | FOLDED | BUGS.md §4 "ANE-compile hang has no timeout or retry affordance (speculative, needs UX)" verbatim. |

## 🎛 Transcription-engine wave (lines 4894–4952)

Header is `✅ BUILT`; roadmap node **TrEngine** confirms "Device rounds DONE 2026-07-12
(builds 71–75)."

| item | line | verdict | id / why |
|---|---|---|---|
| "Device-owed: chapter detection on the real library, capture-cancel latency, 180s-chunk memory on the iPhone 13, RTF re-measure, filler toggle on a real ramble" | 4966 | DONE-SINCE | TrEngine node: "Device rounds DONE 2026-07-12 (builds 71–75)." |
| Parked: per-book language override for the book job | 4969 | FOLDED | SPEC.md "Parked ideas… per-book language" verbatim. |
| Parked: Paragrapher grouping for reading-mode when that builds | 4969 | OPEN | `Paragrapher` itself shipped (SPEC clause, roadmap 2026-07-28) but its reading-mode tie-in is unconfirmed; no clause ties the two. |
| Parked: FluidAudio streaming managers for live caption at the next engine upgrade | 4969 | FOLDED | roadmap node **RecHard** backlog: "Spike — FluidAudio SlidingWindowAsrManager for captions (takes the already-loaded AsrModels)." |

## 🎙 Recording robustness + heat diet (lines 4973–5005)

| item | line | verdict | id / why |
|---|---|---|---|
| Device round (13 + AirPods): freeze gone, snapshot-ms trace, mid-record call/alarm, camera-sheet latency, auto-off, Live Activity tail | 4993 | FOLDED | roadmap node **RecHard** backlog: "Device round on the 13 — devlog snapshot-ms trace; call/alarm mid-record survives; camera-sheet latency; freeze gone?" |
| Phase 3: move session activate/deactivate + engine start/stop off the main thread | 4995 | SUPERSEDED | RecHard shipped log, 2026-07-26: "engine stays on-main so the round-2 P0 window never opens — Phase 3 superseded" (by the prestart fix). |
| Spike: FluidAudio true streaming ASR (`SlidingWindowAsrManager`/`StreamingEouAsrManager`) | 4997 | FOLDED | RecHard node backlog, same line as above. |
| Extraction pass: TapWriter / RouteRecovery / CaptionFeed out of `LiveRecordingService` | 5001 | FOLDED | RecHard node backlog: "Extraction pass — TapWriter / RouteRecovery / CaptionFeed once device rounds lock behavior." |
| Deferred judgment calls: captions keep running while backgrounded; memory-warning `unload()` still no-ops mid-recording | 5003 | OPEN | Neither call is revisited in any ledger. |

## ⭐ CONTINUE HERE — sweet-goldstine wrap (lines 5006–5015)

| item | line | verdict | id / why |
|---|---|---|---|
| Branch pushed, not yet PR'd; user eyeball of build 51; open PR → merge → close PR #8 | 5012 | DONE-SINCE | roadmap.yaml:2012 — "PR #6 (sweet-goldstine) MERGED to main 2026-07-07." |

## 🔬 Audiobook deep-review findings (lines 5016–5049, "UNBUILT unless ticked")

| item | line | verdict | id / why |
|---|---|---|---|
| P1 `ReadAlongModel.reloadIfNeeded` full-sidecar decode ~2×/s on main past the frontier | 5019 | OPEN | Duplicate of the section-3 item above; not tracked anywhere. |
| P1 `BookTranscriptionJob` `@MainActor` costs: sync `extractPCM`, O(n²) `store.save`, `publishValue` re-decode | 5022 | OPEN | Not addressed by the later chunk-buffer work (which fixed a different cost — the temp-WAV round trip). No ledger row. |
| P2 `AudiobookCloudSync.localTranscriptSignature` full-decode per reconcile | 5025 | OPEN | Duplicate of the section-3 item; not tracked. |
| P2 over-observation: 2Hz `currentTime` re-renders Books list + per-row SwiftData fetch + N× `fileExists` | 5027 | OPEN | Not tracked. |
| P3 `setCurrent` linear-scan 10×/s; per-body `Timer.publish` churn; `CIContext` per `loadCoverTint` | 5030 | OPEN | Not tracked. |
| P1 "Edit book details" never syncs (`modifiedAt` never bumped) | 5033 | FOLDED | BUGS.md §2 "'Edit book details' never syncs" verbatim, `Audiobook.swift:562-566`. |
| P2 `TranscribeBookView` shows the active book's progress on any sheet; Start silently cancels the other job | 5035 | split | Display half **FOLDED** → BUGS.md §5 "already fixed" (`isThisBook` gate). Silent-cancel half **FOLDED** → BUGS.md §4, still an unverified lead. |
| P2 seek-while-paused never persists | 5037 | FOLDED | BUGS.md §2 "Seek while paused is never persisted" verbatim. |
| P3 `BookCoverView` placeholder uses `uuidString.hashValue`, not stable across launches | 5038 | FOLDED | BUGS.md §2 "Book cover placeholders change colour every launch" verbatim. |
| VERIFY quote audio extraction `exportSpan` vs `extractPCM` gotcha | 5040 | OPEN | The same 2026-07-16 audit corrected this in place (line 4856): production is self-consistent, only `buildOutputFromSidecar` is exposed, and "STEP 0" (a chunksim third lane) was never run. Still open. |
| Dead code ~800 lines (CaptureMath, CaptureScrub, `QuoteCaptureProcessor.process()`, TrimResult, SentenceSnap, `CaptureSpan.proposal`/`replayWindow`, `AudiobookSession.sleepLabel`) | 5042 | SUPERSEDED | `CaptureMath.swift`, `SentenceSnap`, `TrimResult`, `sleepLabel` all still exist and are now referenced by `BookAlignment.swift`/`ChunkFusion.swift`/`QuoteCaptureProcessor.swift` — reused by the later ePub-alignment and chunk-fusion work, not dead. The 2026-07-07 claim is stale. |
| UX: per-book "N notes" surface + note→book jump-back | 5046 | OPEN | Not in P9b (Audiobook player polish, `status: planned`) or elsewhere. |
| UX: multi-select import of N distinct books silently merges into one | 5046 | OPEN | Not tracked. |
| UX: Books empty-state deserves a real CTA button | 5046 | OPEN | Not tracked. |

## 🎧 Books tab + one-tap resume (lines 5050–5079)

Header is `✅ BUILT`; no reopened lines in range. Fully folded into the sweet-goldstine /
PR #6 merge above — no separate table.

## 🔭 Next unclaimed lane + quick hits (lines 5080–5308)

| item | line | verdict | id / why |
|---|---|---|---|
| Quick hit 1 — Stz020 #3: phone-added person unlinkable (`aliases: []`) | 5098 | FOLDED | BUGS.md §2 + roadmap node **Stz020** backlog: "Name added on phone not recognised… seed alias from name on add." |
| Quick hit 2 — i4: WhatsApp voice message imports as a link | 5102 | DONE-SINCE | Section's own text ends "i4 = FIXED IN CODE," device rounds 1–4 passed; BUGS.md §5 confirms "Fixed after that entry was written." |
| Quick hit 3 — Stz020 #5 remainder: stale `**Name:**` turn markers, no bulk un-diarize/re-transcribe path | 5290 | FOLDED | Stz020 backlog: "Desktop tags every note a 'conversation' (≥2 '**Name:**' headers) + no re-transcribe button." |
| Quick hit 4 — Prod gate runbook (CloudKit dashboard deploy, Mac Settings toggle, Release App Groups capability, one prod round-trip) | 5294 | FOLDED | Stz020 backlog: "Deploy prod CloudKit PRODUCTION schema (incl. MemoEnhancement + NamesRecord + VocabularyRecord) — phone→Mac sync hangs in prod." |
| Quick hit 5 — Sequencing: do Mac name-linking parity AFTER live-sync, then `/code-review` the CloudKit sync spine | 5299 | DONE-SINCE | Overtaken by build: CloudKit-only sync is now the shipped architecture (CLAUDE.md "CloudKit sync contract is the spine"; Bonjour retired 2026-07-06 per MEMORY.md). The ordering concern this note guards against no longer applies. |
| Wave-2 kickoff item: multi-ITEM WhatsApp bundles — `SharePayloadLoader` reads only the first `NSExtensionItem` | 5258 | FOLDED | roadmap node **ShareW2** (`status: done`) still carries this in its own `backlog:` list: "Multi-ITEM WhatsApp bundles — SharePayloadLoader reads only the FIRST attachment of a multi-item share… next-session kickoff = 9f31c26." Design side is decided (SPEC D69, "video+link in a multi-item bundle = ONE note"), implementation still open. |
| Voice-annotate: v1 = dictation model (audio consumed); Mac ingest counterpart owed before attaching playable audio | 5262 | FOLDED | Same ShareW2 node backlog: "Voice-annotate playable-audio attach needs the Mac ingest counterpart." |
| "Still pending user calls: C1 YouTube rich-card-only?, C2 Insta/TikTok, B4 chat-export" | 5178 | DONE-SINCE | All three decided in SPEC: D14 (YouTube = card only), D15 (Instagram/TikTok = card + caption), C128 (chat-export zip parked, not a v2 ingress path). |

## ⭐ CONTINUE HERE — stabilization DONE, next board (lines 5309–5332)

| item | line | verdict | id / why |
|---|---|---|---|
| 1. Soak-watch builds ≥59 (passive: pull devlog + crashes after a day) | 5316 | OPEN | No ledger closes this out; the build range itself is long superseded by now, but nothing formally retired the check. |
| 2. Design question: "warming up…" row in Related section (~40s cold load) | 5318 | DONE-SINCE | Superseded by the shared `RetrievalGate` work — roadmap node **NFeat**: "shared RetrievalGate upgrades the PHONE gate too (%, preparing, N-of-M)." |
| 3. Prod CloudKit schema deploy | 5321 | FOLDED | Stz020 backlog, same as above. |
| 4. Desktop Review mock sign-off + desktop-parity device round-trips owed | 5323 | split | Mock sign-off **DONE-SINCE** (`mocks/journal-desktop.html` v2 signed off 2026-07-11, per section 13 below). Device round-trips **OPEN**, tracked piecemeal inside roadmap node **DParityB** (`status: inprogress`) shipped-log "owed" notes, not closed out. |
| 5. Vault lens (waits on Tuur's iCloud vault move) | 5325 | FOLDED | SPEC.md "Parked ideas that are NOT decisions today… vault-read direction." |
| 6. Parked kickoff: capture-as-note + note-editing follow-ups | 5327 | FOLDED | roadmap node **CapNote** ("Capture reads as a note"), `status: inprogress`, note cites this exact memory brief. |
| Wall printer reminder: re-pick the home printer after the office test print | 5329 | OPEN | Physical/personal action, not a code item; no clause applies. |

## ✅ Post-convergence stabilization (lines 5333–5438)

Items 1–3 in the triage are `✅` closed 2026-07-10 in the text itself — skipped. Tail:

| item | line | verdict | id / why |
|---|---|---|---|
| 4. Wall: office print test → re-pick home printer after | 5401 | OPEN | Same physical reminder as above; not a code item. |
| 5. Then: vault lens, desktop Review mock sign-off, prod CloudKit schema deploy | 5403 | duplicate | Already verdicted above (vault lens FOLDED parked-ideas; mock sign-off DONE-SINCE; CloudKit deploy FOLDED Stz020). |
| Noticed in passing: list-row previews still render raw `memo.transcript` while detail shows the polish; "fold into a display-consistency pass if it bothers in use" | 5413 | OPEN | Explicitly deferred by its own text; not tracked. |
| Bug report: semantic search intermittently finds nothing (build 53) | 5419 | FOLDED | BUGS.md §3 "Semantic search intermittently finds nothing" verbatim, still reported-not-diagnosed. |
| Bug report: Skrift Dev crashed a few times at random spots (build 53) | 5423 | FOLDED | BUGS.md §3, same text, still undiagnosed. |
| Design add: vault lens gains title-linking (Backlink-Weaver) | 5428 | FOLDED | SPEC.md parked ideas: "Backlink Weaver." |
| Design add: Then-vs-Now pair-picking mechanics | 5432 | FOLDED | SPEC.md:1170 area cites `ThenVsNow`/`LookingBack` tests — mechanic is specified, not an open item. |
| Design add: office-printer guard (behavioral rule) | 5436 | OPEN | Personal workflow rule, not code; no clause applies. |

## 🖨️ Print-to-wall + significance in the Journal (lines 5439–5461)

Header is `✅ BOTH BUILT`. Whole section **FOLDED** → SPEC.md **C233** ("Print-to-wall fires
once per note on crossing INTO the TOP ball (1.0, D30)… `WallPrinter` tests"). Note: v2
respec moved the threshold from 0.8 to 1.0 (D30) — the original 0.8-threshold device-verify
notes in this section are superseded by that respec, not separately open. The reprint
stamp-clearing defect this section's code shipped with is separately tracked as **R85/C272**.

## ⭐ CONTINUE HERE — desktop-parity board (lines 5462–5623)

| item | line | verdict | id / why |
|---|---|---|---|
| Board A #1: "`[[` creation picker still owed" | 5481 | DONE-SINCE | roadmap node **DParityB** shipped log, 2026-07-15: "Mac `[[` link picker (phone parity)." |
| Board A #3b follow-ups: (a) mock's true first-page inline PDF render on the Mac, (b) `PDFTextExtract` Mac-wire fallback, (c) vault copy of the capture document on export; live device round-trip owed | 5500–5502 | OPEN | roadmap DParityB shipped log names these as "follow-ups" in prose but carries no backlog row tracking them; still untracked. |
| Board A #4: verify UnitTests + full `-skipMacroValidation` build + `-snapshot` PNGs | 5503 | OPEN | Routine verify instruction, not itemized as a discrete deliverable anywhere. |
| Board B: device/live eyeball owed (annotation count-bubbles want a live-deploy look) | 5506 | OPEN | Not tracked specifically. |
| Board C #6: `PhoneMetadata` leniency vs shared `MemoMetadata` strictness — "left as-is for now" | 5562–5574 | FOLDED | DParityB shipped log: "Board C6 (legacy PhoneMetadata) kept by design… a collapse needs a lenient shared `init(from:)` + golden tests first — its own chunk." Tracked as a deliberate deferral, not a bug. |
| Minor follow-up: export image collision when two notes share the exact same title | 5619 | FOLDED | BUGS.md §2 "Same-titled notes overwrite each other's images on export" verbatim. |

## ⭐ Phone↔Mac intertwining (lines 5624–5975)

| item | line | verdict | id / why |
|---|---|---|---|
| Later gaps from the audit: reminder alarm on the Mac | 5659 | OPEN | No hit anywhere in SPEC/BUGS/roadmap. |
| Open Q: should trashing also delete the note's Obsidian `.md`? | 5661 | OPEN | Explicit open design question; no decision recorded. Needs a D-row. |
| (c) transient "lost the link" on the Mac once, unreproduced, not fixed | 5708 | FOLDED | BUGS.md §3 "Transient 'lost the link' on the Mac, once, not reproducible (second try kept it). Watch for it rather than hunt it." |
| Filter/sort parity gap (Mac review-workflow filters vs phone content filters) — scoped, mock-first before building | 5727 | OPEN | Not tracked in SPEC/BUGS/roadmap. |
| PDFs (3b) not synced to the Mac — "RE-TEST with a FRESH PDF share before treating it as a bug" | 5723, 5736 | FOLDED | roadmap DParityB shipped log, "3b — .file capture documents SYNC," itself still says "live round-trip owed" — same open re-test, same node. |
| Image-at-sentence-end reflow: "DEVICE ROUND OWED (both apps, build-number bump per push)" | ~5760 | FOLDED | roadmap node **NFeat** shipped log, 2026-07-16 entry, verbatim: "…Mac hostPNG eyeballed; device round owed." |
| Device-verify checklist: Mac-added vocab word → phone (and deletion → Mac) | 5788 | DONE-SINCE | Same line cites the fix commit directly: "[LWW fix 6f78ac1]." |
| Device-verify checklist: lock on phone → Mac export refusal/gate, unlock → re-export; OCR search on the Mac; memo-link export opens the target in Obsidian; 🔔 reminder row shows | 5788 | OPEN | Remaining checklist items, not individually tracked. |
| Review-note-detail mock PARKED (revive trigger: alert annoys again in practice) | 5800 | OPEN | Self-contained parked item; no live ledger names it, revive condition is in the backlog text itself only. |
| "TUUR'S EYES (casual, no chat needed)": fading round eyeball, b81-era carried items, map dive re-wiggle | 5815 | OPEN | Casual/no-ledger checklist; nothing tracks it as closed. |
| Fading lifecycle: "re-eyeball: dot lights fresh → opens shelf → goes dark; Keep; sweep-all; cross-device convergence" | 5855 | DONE-SINCE | roadmap node **LifeClock**: "FIVE same-day eyeball fix waves off Tuur's live rounds (Mac Dev + phone b88–92)" — the IA/fading overhaul shipped fully on both devices per that node. |
| Parked direction: read the Obsidian vault into the app | 5878–5886 | FOLDED | SPEC.md parked ideas: "vault-read direction." |
| Map: "⬜ re-wiggle owed" (pin-tap dive camera) | 5895 | OPEN | Not tracked. |
| Connections panel: "rest of the eyeball… then the phone round… FEATURES.md row + roadmap tick owed" | 5951 | DONE-SINCE | Superseded by the later 2026-07-20 panel-polish pass in the same doc (hairline-border fix, top-K cap) — eyeballing against real notes necessarily happened to surface those. |
| NEXT CHUNK: shared `RetrievalGate` core (phone Journal gate adopts %, preparing, N-of-M) | 5957 | DONE-SINCE | roadmap **NFeat**: "shared RetrievalGate upgrades the PHONE gate too (%, preparing, N-of-M)." |
| NEXT CHUNK: Mac search-jump parity (scroll-to-match + flash) | 5963 | FOLDED | BUGS.md §4 "Mac search-jump parity gap — Mac search filters the sidebar but doesn't jump to the hit," still open, not re-verified. |
| NEXT CHUNK: photo-OCR search edges on the Mac — Mac-local ingests never OCR'd; an OCR-only match can't flash in the body | 5971 | OPEN | Not tracked in SPEC/BUGS/roadmap. |

## 🧭 SharedKit wave 2 — twin-scan triage (lines 5976–6099)

| item | line | verdict | id / why |
|---|---|---|---|
| 6 Palette `DriftedPair`s — "RECONCILE after an eyeball round (each collapse = a one-line change now)" | 5998 | OPEN | Confirmed still present in code: `Shared/UI/Palette.swift`, `Shared/UI/SignificanceCirclesView.swift` both still reference `DriftedPair`. Not tracked as a backlog/idea item anywhere. |
| `NoteBodyView ↔ BodyTextView` (clone-scan #14) — "fold into i10 rather than a separate job" | 6045 | FOLDED | roadmap idea **i10** ("Obsidian-grade markdown body"), still an idea (`source: voice`, `nodeHint: NFeat`), not yet graduated to a node — open, tracked there. |
| `MemoSaver ↔ IngestService` (clone-scan #10) — shared ingest logic | 6052 | OPEN | No hit anywhere in SPEC/BUGS/roadmap. |
| Main-column polish proposal (mock #m6): tags move up, importance control one size down, icons on context chips | 6058 | OPEN | Explicitly "not this feature's scope… a boxed proposal"; no clause or backlog row picks it up. |

## OPEN items in this slice

**Count: 49** (48 rows verdicted plainly OPEN, plus the device-round-trips half of the
split "Desktop Review mock sign-off" row).

Most important five, judged by user-facing/data-risk weight:

1. **Reminder alarm never reaches the Mac, and no decision exists on whether trashing a note should delete its Obsidian `.md`** (lines 5659, 5661) — the second is a live data-safety question with zero record of Tuur ever being asked.
2. **6 Palette `DriftedPair`s are still literally in the code** (line 5998) — `Shared/UI/Palette.swift`/`SignificanceCirclesView.swift` confirmed today; the one-eyeball-round reconcile promised in July never happened.
3. **The Mac backlink scan is still an unindexed full-corpus scan per note switch** — moved into `ConnectionsPanel.swift:119` with a comment admitting "unchanged," never fixed, never ticketed (lines 4874, 4889).
4. **Filter/sort parity between phone and Mac was scoped but never mocked or built** (line 5727) — an explicit "mock-first before building" that nobody picked back up.
5. **`MemoSaver ↔ IngestService` duplicate ingest logic was flagged by the twin-scan tool and never actioned** (line 6052) — the last unclosed item from the SharedKit wave-2 triage list.
