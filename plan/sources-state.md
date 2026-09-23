# Source ledger — half A

Date: 2026-09-23. Rule: SPEC.md C276 — a cited document is not a folded document; every open
item in every old plan gets a verdict.

Docs covered here (per assignment; `archive/state-2026-09/backlog.md` excluded from this half —
tracked separately):
`archive/state-2026-09/AUDIT_FIX_TESTLIST.md`, `AUDIT_PLAN.md`, `JOURNAL_RETRIEVAL_PLAN.md`,
`NAMING_MODEL.md`, `SHARE_INGEST_SURVEY.md`, `SKRIFT_SOURCE_OF_TRUTH.md`, `STANDALONE_PLAN.md`,
`TESTFLIGHT_INSTALL_HANDOFF.md`; `Skrift_Native/IPAD_PLAN.md`; `Skrift_Native/CAPTURE_CONTRACT.md`;
`FEATURES.md` (planned/partial/owed rows only); `CHANGELOG.md` (unreleased/owed lines only).

Cross-referenced against: SPEC.md clauses C1–C276, required differences R1–R89, decisions
D1–D100; BUGS.md sections 1–5; `roadmap/roadmap.yaml` nodes. Where the live ledger didn't
settle it, current source was grepped (cited by path).

---

## `archive/state-2026-09/AUDIT_FIX_TESTLIST.md`

Dated 2026-07-19, merged branch `audit-fixes`. Nearly everything in it is a manual smoke-test
checklist for code already merged; the "Deliberately NOT changed" and "Known-issue" sections are
the doc's own verdicts.

| item (short) | doc line | verdict | id / why |
|---|---|---|---|
| Phone checks: record→pocket, list scroll, read-along catch-up, whole-book %, merged capture view, audiobook sync failure surface, initial-sync burst | 15–32 | FOLDED | roadmap node `AuditFix` win: "phone/Mac smoke of the top-4 testlist items owed" — the same unchecked device round, still open |
| Mac checks: video-drop UI stays responsive, edit-while-processing, second-launch no-op, reconcile sweep memory, reconcile summary log, Connections gate error surface, vault-export failed-attachment logging | 36–53 | FOLDED | roadmap node `AuditFix` (same smoke-round owed); reconcile blob-fault behavior also covered by SPEC C45/R29 |
| Cross-app: Connections still work, empty-snapshot guard, model-bump drop-out behavior | 57–61 | FOLDED | roadmap node `AuditFix`; drop-out-not-garbage rule = `feedback_no_bad_information` (locked 2026-07-12), matches SPEC C230 "a stale-model vector is never scored" |
| "Deliberately NOT changed": trash purge sync in App.init, BookCoverCache sync-on-main, per-buffer Task ordering (needs-device), quote-capture AVAssetExportSession drift experiment, ExportStateStore O(k·n) unwired | 65–76 | DROPPED | doc's own verdict — explicitly decided not to change; per-buffer Task ordering item reopened later as AUDIT_PLAN §4 (see below) |
| mlx-swift-lm pinned to `branch: main` (floating), broke fresh worktree checkouts | 80–85 | DONE-SINCE | commit `f0d44953` "fix(mac): pin mlx-swift-lm to the proven revision"; current `project.yml:24-26` carries an exact revision, not `branch:` — matches SPEC C167 |
| 6 failing UI tests (Smoke launch, Settings inventory, Share probes, VoiceEnroll) predate this branch | 89–91 | FOLDED | SPEC D85 "Retire the XCUITest suite. DECIDED: retire; the unit suite is the gate" — supersedes the whole XCUITest-failure question |

## `archive/state-2026-09/AUDIT_PLAN.md`

Dated 2026-09-01, read-only 6-agent audit, "nothing built, nothing tested." Every fix in it was
unbuilt at write time.

| item (short) | doc line | verdict | id / why |
|---|---|---|---|
| D1 names.json non-atomic write + unguarded read-modify-write | 55–77 | FOLDED | BUGS §1 D1; SPEC C50, R8. Verified still open: `NamesStore.swift:50` is still `try? encoded.write(to: fileURL)` |
| D2 re-transcribe destroys transcript when audio has moved | 79–95 | FOLDED | BUGS §1 D2; SPEC C51, R9 |
| D3 vault export deletes a file it doesn't own (attachment lanes) | 97–109 | FOLDED | BUGS §1 D3; SPEC C58, R7 |
| D4 a whole recording is lost if the app dies mid-recording | 111–123 | FOLDED | BUGS §1 D4; SPEC C99, D26 (decided 2026-09-22, "never ever ever") |
| P1 two full-corpus scans per rendered row (`MemosListView.swift:462-463`) | 131–153 | FOLDED, still open | roadmap `AuditFix2` backlog "P1 MemosListView 462-463…"; verified current code unchanged at the same lines |
| P2 `mkdir` on every path access, 44 call sites (`AppPaths.swift`) | 155–163 | FOLDED, still open | roadmap `AuditFix2` backlog "P2"; verified `recordingsDirectory` is still `static var`, not `static let` |
| P3 DEBUG-only per-keystroke double corpus scan | 165–178 | FOLDED, still open | roadmap `AuditFix2` backlog "P3"; current `MemosListView.swift:305-317` still runs a `#if DEBUG` per-keystroke memo filter (rewritten shape, same class of issue) |
| P4 asset sweep faults every blob into memory (`NotesRepository.allAssets`) | 180–192 | FOLDED, still open | roadmap `AuditFix2` backlog "P4"; verified `NotesRepository.swift:131` still `context.fetch(FetchDescriptor<MemoAsset>())` with no `propertiesToFetch` |
| P5 source-type lookup parses metadata blob twice per row (🔶) | 197–204 | OPEN | not named in roadmap `AuditFix2` backlog or any SPEC clause; would need a queue item citing `SourceTaxonomy.swift:54-71` |
| P6 `SpeakerTranscript.parse` compiles a fresh regex per note page (🔶) | 206–212 | OPEN | not tracked; would need a queue item citing `SpeakerTranscript.swift:39-40` |
| P7 `names.json` re-read/re-decoded on every access, no memoization (🔶) | 214–220 | OPEN | roadmap `AuditFix2`'s D1 bullet doesn't name P7 even though the audit says "do D1 and P7 as one change"; would need that line added, or a new R/queue item |
| Tier 3: launch/foreground sweep chain, no checkpointing, `DemoDataSeeder` fetch-before-flag-check (🔶) | 228–233 | FOLDED | roadmap `AuditFix2` backlog "Sweep chain watermarks + off-main" |
| Tier 3: note opening does the corpus twice per pager page (🔶) | 234–237 | OPEN | not tracked; would need a queue item citing `MemoDetailView.swift:882-901` |
| Tier 3: read-along/conversation playback redraws whole screens on a 20 Hz/2 Hz timer (🔶) | 238–242 | OPEN | not tracked; would need a queue item citing `ConversationTurnsSection`, `AudiobookPlayerView` |
| Tier 3: Mac twin of P4 — `adoptLateDiarization` guard can't go false, faults every blob per sweep (🔶) | 243–246 | FOLDED | roadmap `AuditFix2` backlog "Mac twin MemoCloudReconciler 117-122"; also SPEC C45/R29 ("unchanged rows are skipped without faulting blobs") |
| Tier 3: Mac vault scan uncapped, opens every `.md` on the main thread (🔶) | 247–249 | OPEN | not tracked; would need a queue item citing `VaultStamp.swift:140-154` |
| Tier 3: no `#Index` anywhere despite deployment target support (🔶) | 250–253 | OPEN | not tracked; would need a queue item for `Memo.deletedAt`+`recordedAt`, `MemoAsset.memoID`, `MemoEnhancement.memoID` |
| Tier 4: `isTranscribing` is a `Bool` on a re-entrant actor, two overlapping transcribes race (🔶) | 263–267 | FOLDED | roadmap `AuditFix2` backlog "Concurrency - isTranscribing counter" |
| Tier 4: `MacRecorder.stop` finalizes by dropping a reference, no explicit queue drain (🔶) | 268–271 | FOLDED, still open | roadmap `AuditFix2` backlog "MacRecorder drain"; current `MacRecorder.swift:298-317` still relies on `teardownSession()` dropping the sink rather than an explicit `writerQueue.sync{}` like the phone has |
| Tier 4: live-caption buffers through unstructured per-buffer `Task`, order-critical on the Mac (🔶) | 272–275 | FOLDED | roadmap `AuditFix2` backlog "caption ordering" |
| Tier 4: `GemmaEmbedder.downloadProgress` nonisolated(unsafe) race (🔶) | 276–277 | OPEN | not tracked; would need a queue item citing `GemmaEmbedder.swift:27,96` |
| "Turning on SWIFT_STRICT_CONCURRENCY" — targeted ~3d, complete 10-15d, check dependency Swift 6 modes first | 279–282 | OPEN | no clause or roadmap item addresses a concurrency-checking adoption plan |
| SwiftLint baseline ratchet | 290–294 | FOLDED | roadmap `AuditFix2` backlog "SwiftLint baseline ratchet" |
| Duplication report (jscpd/lizard) | 295–296 | FOLDED | roadmap `AuditFix2` backlog "duplication report" |
| Long-compile hunt (`-warn-long-function-bodies`/`-warn-long-expression-type-checking`) | 297–299 | OPEN | not named in roadmap `AuditFix2` backlog |
| `OSSignposter` around the pipeline stages | 300–302 | FOLDED | roadmap `AuditFix2` backlog "pipeline signposts" |
| Dead code — Periphery (archived, now commercial) or `swiftlint analyze` substitute | 303–307 | OPEN | not tracked |
| Mutation testing / manual break-ten-functions test of the suite | 308–311 | OPEN | not tracked |
| `XcodeBuildMCP` for agent build/install/drive loop | 312–313 | OPEN | not tracked; tooling adoption question, not a code item |
| §0 measurement: Xcode Organizer field metrics unavailable, blocked by TestFlight account lockout | 43–47 | FOLDED | see `TESTFLIGHT_INSTALL_HANDOFF.md` section below — same root cause, still open there |
| §7 "where the agents were wrong" (calibration notes) | 345–358 | DROPPED | retrospective, not an actionable item |

## `archive/state-2026-09/JOURNAL_RETRIEVAL_PLAN.md`

Dated 2026-07-06/07 (P8 plan). The whole engine + all mock surfaces were built and
device-verified the same week; roadmap node `P8` ("Journal / On-This-Day / search") is `done`
(2026-07-07, with device-verify shipped-log entries through 2026-07-10).

| item (short) | doc line | verdict | id / why |
|---|---|---|---|
| Chunk 0 bake-off gate (EmbeddingGemma-300M d512 vs Apple NLContextualEmbedding) | 145–151 | FOLDED, done | roadmap `P8` shipped log "Bake-off run on the M4 — EmbeddingGemma d512 wins 10/10" |
| Chunk 1–2: engine + local-only index, hash-diff sweep, inert-by-default | 152–162 | FOLDED, done | roadmap `P8` shipped log entries `4767d09` |
| Chunk 3: calibration harness owed, replace provisional 0.55 floor | 163–166 | DONE-SINCE | roadmap `P8` shipped log: "floors CALIBRATED from the on-device histogram (random-pair p50 .31/p90 .49 → related floor 0.45)"; final numbers in SPEC C109 (related 0.45, search 0.25) |
| Chunk 4: mock gate | 167–171 | FOLDED, done | doc's own ✅ SIGNED OFF |
| Chunk 5–7: Journal tab, search Related + Thread view, Related card on note detail | 172–191 | FOLDED, done | roadmap `P8` shipped log entries `d05ddd8`/`0c9babd`/`c6acc39` |
| Chunk 8: Settings consent flow, sweep logging, calibration harness, then "flip P8 done" | 192–204 | DONE-SINCE | roadmap `P8` status `done`, `done: 2026-07-07` |
| Device findings: devlog pull for real floors, jetsam/memory check, Settings/Calendar/Map eyeball | 206–216 | DONE-SINCE | roadmap `P8` shipped log: "DEVICE-VERIFIED live by Tuur (builds 40–53, 4 rounds)"; cold-load stall separately closed 2026-07-10 (shipped log, commit `0778575`/`70c3714`) |
| Also owed: iPad layout pass for Journal | 203–204 | OPEN | no shipped-log line or SPEC clause names an iPad Journal layout pass specifically; would need a queue item |
| Also owed: person/kind filter chip additions to search | 183–185, 203–204 | OPEN | doc's own "Deviations (deliberate): filter CHIPS not built" — not picked up in any later ledger; would need a queue item against the existing `SortFilterSheet` |
| Fast-follow: "Then vs Now" card | 220–222 | FOLDED, built | SPEC C231 "Then-vs-Now (last ~2 weeks vs ≥6 months older)"; FEATURES.md line 117 confirms shipped v2 2026-07-23 |
| Fast-follow: Voice search on the search field | 223–224 | FOLDED | SPEC "Parked ideas" list names "voice search" explicitly — not a decision, tracked as parked |
| Phase 2: Mac + vault lens (index `<vault>/**/*.md`, `source: vault` tag) | 226–242 | FOLDED | SPEC "Parked ideas" list names "vault-read direction" explicitly |
| Phase 2: vault relocation to iCloud Drive (replacing lapsed Obsidian Sync) | 243–251 | OPEN | this is an operational/personal-vault-management task, not a Skrift code item; no clause or decision covers it — would need a Decision entry if still wanted |
| Later, same substrate: book influence pages, ask-your-memos RAG, weekly digest, P6 Daily Review by embedding diversity | 253–258 | FOLDED | SPEC "Not doing": "no chat/ask… no LLM narration of 'how my thinking evolved' yet"; per-book quotes page listed in Parked ideas (i16) |
| Collision map items (Bonjour removal, Highlights-tab removal, note-editing, SharedKit dedup) | 260–274 | DROPPED | all historical, resolved same week per the doc's own "ALL CLEAR" |

## `archive/state-2026-09/NAMING_MODEL.md`

Dated 2026-06-16, "LOCKED design." Chunks 1–5 were built the same day; the remaining content is
deferred/out-of-scope markers.

| item (short) | doc line | verdict | id / why |
|---|---|---|---|
| Chunks 1–5 (opt-out flip, roster seeding, delete legacy machinery, in-prose UX, robustness/re-scan) | 232–288 | FOLDED, done | doc's own ✅ DONE 2026-06-16 marks; superseded in detail by SPEC's Names & sanitise section (C80–C86) and the later names-probe fixes R62–R69/C254–C260 |
| Phone-side picking UI (click-a-name popover), deferred "build Mac-first" | 216 | FOLDED, built | SPEC C80/D77: "The phone's 'People in this note' CHIP BAR is removed: names are clickable in the text as on the Mac, one model on both apps" — the same in-prose interaction, now built on both devices |
| Skrift creating/enriching person notes (profiles, `firstMentioned`, confidence) — "people CRM" | 212–215 | FOLDED | SPEC "Parked ideas" list names "people pages (P7)" |
| Any auto "new person?" hint for unknown people — rejected | 217–218 | FOLDED | SPEC "Not doing": "no auto 'new person?' hint" |
| Tag normalisation ("filosofaties") — parallel issue, not this | 219 | FOLDED | SPEC D80: "Tag normalisation ('filosofaties') out of scope. Default: out" |
| Date-sorted person-note *view* — explicitly "the user's Dataview/Bases query, not Skrift's job" | 294–295 | DROPPED | doc's own words — deliberately outside Skrift's scope |
| Live in-NSTextView body eyeball owed after deploy (chunk 4) | 279 | OPEN | no later ledger names this specific device-verify; would need a queue item or fold under SPEC C118's "his eyeball owed" list |

## `archive/state-2026-09/SHARE_INGEST_SURVEY.md`

Dated 2026-07-07, verdict pass 2026-07-10. Waves 1–3 (2026-07-10 to 07-12) built nearly every
row with commit hashes in the doc itself — those are skipped per the doc's own ✅ marks except
where a residue is explicitly unverified/owed.

| item (short) | doc line | verdict | id / why |
|---|---|---|---|
| A6 PDF/doc share: no text extraction, device-eyeball owed | 52 | FOLDED | SPEC C73: "PDF/doc share → file capture, the document syncs as an asset, its text is searchable" |
| A5 original video discarded "by design — revisit?" | 51 | FOLDED | SPEC C63/D44: kept as synced asset for Made/Idea/Inspiration, discarded for Personal — decided, not revisited as a blanket keep |
| A5 small crash window: inbox entry deleted before import, can lose the video | 51 | FOLDED | SPEC R23/C147, and BUGS §1 D14/R84 (capture-inbox entry deleted before import confirmed) |
| Wave 3 voice-annotate: built but UNVERIFIED (build-stack wedge) | 27–29 | FOLDED | SPEC D71 (in-app voice-annotate on captures, default yes) and BUGS §1 D16/R87 (voice-annotation audio deleted even on empty transcript) — same feature, now tracked with an open bug |
| C1 YouTube: captions rejected, overall UNDECIDED (rich card vs desktop local-transcribe) | 77 | FOLDED | SPEC C72/D14: "A YouTube link is a CARD ONLY — the audio is never scraped… the reliable route stays: download the audio yourself, drop the file on Skrift" — decided card-only, no distinct desktop path |
| C2 Instagram/TikTok: UNDECIDED | 78 | FOLDED | SPEC C72/D15: "a card plus the page's caption as body when it gives one, never a login-walled fetch" |
| B4 messenger chat-export `.zip`: MAYBE, parking lot | 71 | FOLDED, still open | SPEC C128/D37: "NOT an ingress path in v2 (parked)… ⚠ needs-verdict D37" — tracked as an explicitly open SPEC decision |
| D1 Book quotes (Apple Books/Kindle share): PARKED, decide with Books/Journal design chat | 87 | FOLDED | SPEC "Not doing": "Apple Books / Kindle quote shares parked" |
| D2 Contact (vCard) → Names DB: SKIP | 88 | FOLDED | SPEC "Not doing": "No vCard → Names" |
| D5 Calendar (.ics) → meeting scaffold: SKIP for now | 91 | FOLDED | SPEC "Not doing": "no `.ics` meeting scaffold" |
| C3 Podcasts → Books tab: STRONG GO | 79 | FOLDED | roadmap node `Podcasts` ("Podcasts → Books", status inprogress); SPEC D33 |
| C4 Web article → readable text | 80 | FOLDED | SPEC C72 (title/description/thumbnail on drain, article text search-only) |
| C5 URL that points at a PDF | 81 | FOLDED | SPEC C73 |
| D4 `.md`/`.txt` share → note body | 90 | FOLDED | SPEC C73/D22 |
| D6 Location (Maps) share → place-tagged note | 92 | FOLDED | SPEC C144 |
| D7 Telegram/Signal voice notes | 93 | FOLDED | SPEC C69 |
| D8 In-app Files importer for audio+video | 94 | FOLDED | SPEC C145; confirmed built — `MemosListView.swift` has a `.fileImporter` on `[.audio, .movie]` |
| E1 One unified share sheet | 100 | FOLDED, doc marks ✅ built (wave 3) | SPEC C66 |
| E2 Audio length routing, 1h threshold | 101 | FOLDED | SPEC C79: "Audio ≥ 1 h offers Books" |
| E3 Feedback & failure UX ("Saved to Skrift ✓", honest errors) | 102 | FOLDED | SPEC C75 |
| E4 Enrichment-on-drain policy (extension stays dumb, main app fetches) | 103 | FOLDED | SPEC C120: "the only network calls are weather at capture and the one URL fetch on drain" |
| E5 IngestKit shared engine + Mac surfaces (share-menu ext, drag-drop, Finder Open-with, watch folder) | 104 | FOLDED, partial | SPEC C238/D19 (ONE shared import layer, decided/built); "watched-folder ingest" separately listed in SPEC's Parked ideas — the Mac-specific surfaces beyond the shared layer aren't individually tracked |

## `archive/state-2026-09/SKRIFT_SOURCE_OF_TRUTH.md`

Dated up to 2026-07-12 (Era 6). Sections 1, 2, 5, 6 are historical/architecture narrative that
now lives in CLAUDE.md and SPEC.md verbatim — no open items there. Sections 3, 4 (phase ledger)
and 7 (contradictions) carry the open content.

| item (short) | doc line | verdict | id / why |
|---|---|---|---|
| P0/P1 #1: phone won't sync to Mac — prod CloudKit schema never deployed | 336 | FOLDED, still open | SPEC D67: "Prod CloudKit schema deploy + Release App-ID capabilities: at prod promotion after v2… Default: yes" |
| P0/P1 #2: stale "Waiting" sync pill keyed off Bonjour/HTTP state | 337 | DONE-SINCE | Bonjour/HTTP LAN sync fully retired 2026-07-06 (CLAUDE.md); the code path this bug lived in no longer exists |
| P0/P1 #3: name added on phone never recognised (empty aliases, e.g. "IJsbrand") | 338 | FOLDED | BUGS §2 "A person added on the phone can never be linked"; SPEC C83/R12 |
| P0/P1 #4: can't select a word + "add as name" on phone (desktop has it) | 339 | OPEN | no SPEC clause or BUGS row names this specific parity gap |
| P0/P1 #5: desktop shows every note as a conversation, no re-transcribe button, stale turn markers | 340 | FOLDED | SPEC R30/C23/C174: "a monologue never carries turn markers; one parser on both apps" |
| Device-verify-owed: P0 append-transcription "text didn't land" | 343 | FOLDED | same subsystem as SPEC R72/C223 (append races the original transcription pass) — carried forward as a live, still-broken required difference |
| Device-verify-owed: MP3 audiobook quote-span/append-splice/chunksim drift, fixed on Linux only | 344 | FOLDED, built | SPEC C106: "Whole-book transcription: 180 s chunks via sample-accurate frame reads (never AVAssetExportSession)" — the durable fix this item was chasing |
| Device-verify-owed: diarization survives backgrounding | 345 | OPEN | not specifically named in any later ledger; general recording-interruption durability is covered by SPEC C99, but backgrounding-during-diarization isn't singled out |
| Device-verify-owed: PDF share persist, auto-stop captions, bookmark affordances | 346 | FOLDED, built | auto-stop captions = SPEC C222 ("Live captions auto-stop after 60 s… sticky, works mid-recording"); PDF share = SPEC C73 |
| Open design Q: note-editing text-selection auto-scroll (option B/B2) | 349 | FOLDED | SPEC C113: "The editor feels like Apple Notes… Rebuilt on the body v2 (C10)… Mock first" — the rebuild this question was blocking |
| Open design Q: offline conflict resolution (same-note-body LWW risk) | 350 | FOLDED | SPEC D24/C98/C242: conflict is shown and chosen, never silent |
| Open design Q: folders model (app-native vs Obsidian-subfolder) | 351 | FOLDED | SPEC "Parked ideas" list names "folders model" |
| Open design Q: significance → "Importance"/pin label | 352 | FOLDED | SPEC C210/D30/D100: "Importance" is the locked user-facing word, three-ball scale |
| Owed engineering: confirm always-warm ASR engine isn't draining battery | 356 | FOLDED | SPEC D84: "Always-warm ASR engine: intentional; measure battery once. Default: keep, measure" |
| Owed engineering: Mac "name a speaker" review UI — backend done, desktop turn-renderer owed | 357 | FOLDED | SPEC "Parked ideas" list names "the Mac name-a-speaker review UI (owed after v2)" |
| Owed engineering: Paragrapher built but not wired into the UI | 358 | FOLDED | SPEC C20/D5 — paragraphing rules now fully specified for the v2 rewrite target 1 |
| Owed engineering: FluidAudio pinned to moving `main` | 359 | DONE-SINCE | doc's own strikethrough: "✅ RESOLVED 2026-07-11, pinned to revision `7f963cdc`" |
| Owed engineering: audiobook unshare leaves a phantom library entry | 360 | OPEN | no clause covers GC of a carrier-less, audio-less library entry specifically |
| Owed engineering: whole-book transcribe memory-pressure lead (profiling, "not a clear fix") | 361 | OPEN | not individually tracked; loosely related to roadmap `AuditFix2`'s general Time-Profiler step but not named |
| Owed engineering: capture sentence-split on abbreviations ("Dr.") | 362 | OPEN | not named as a corpus edge case in SPEC C20's paragrapher rewrite; would need a new corpus fixture |
| Owed engineering: polished-body karaoke is proportional, not word-exact | 363 | FOLDED | SPEC C26: "Karaoke: raw body word N = timing N; polished body aligned via AlignmentCore; a body that doesn't match its audio degrades to a proportional sweep" |
| Deferred: watched-folder ingest | 367 | FOLDED | SPEC "Parked ideas" list |
| Deferred: summary-prompt quality pass | 368 | FOLDED | SPEC D82: "Summary prompt quality/context hints: prompts frozen in v2. Default: frozen" |
| Deferred: re-ingest ~30 old notes from the Electron era | 369 | FOLDED | CLAUDE.md "Open cross-app work": "TODO: port old Electron notes — deferred" (memory `project_port_electron_notes`) |
| Deferred: in-app feedback routed into `backlog.md` | 370 | DONE-SINCE | superseded by the `.claude/skills/pull-phone-feedback/` skill (CLAUDE.md ledgers section) — a different, now-built mechanism for the same need |
| Deferred: drag-to-multi-select memos (lasso) | 371 | FOLDED | SPEC "Parked ideas" list names "lasso multi-select" |
| Deferred: phone Models/Storage management view + desktop mirror | 372 | OPEN | no clause or roadmap node names this |
| Deferred: unified source taxonomy (duplicated glyph/label maps) | 373 | FOLDED | SPEC C78: "`SourceTaxonomy` is the one glyph+label map"; CLAUDE.md "Open cross-app work" still separately lists "Unified source taxonomy" as unbuilt-in-full |
| Deferred: Backlink Weaver (auto-link vault note titles beyond people) | 374 | FOLDED | SPEC "Parked ideas" list |
| Desktop walkthrough tracker open items (C1 health-dot design, ST7/E4 prompt-vs-YAML verify, AUD-P* polish, W2 cursor) | 377 | OPEN | `WALKTHROUGH_BUGS.md` is not in this agent's doc list and none of these granular items are named in SPEC/BUGS/roadmap |
| Phase ledger: Phases 0–11 (`STANDALONE_PLAN.md` source) | 402–456 | FOLDED | see `STANDALONE_PLAN.md` section below — same phase list, same roadmap node mapping |
| Contradiction #4: P0 append-transcription bug, 3 reframings, still open | 533 | FOLDED | same as the device-verify-owed row above — SPEC R72/C223 |
| Contradiction #25: no `P9a` roadmap node, D1–D3 stand in for it | 554 | DONE-SINCE | resolved in the current `roadmap.yaml`, which has `D1`/`D2`/`D3` nodes and no `P9a` |
| Contradiction #26: project age unverified (git floors at 2025-10-18, user recalls "2 years+") | 555 | OPEN | genuinely unresolved, but not spec-actionable; would need Tuur's own recollection, not a code clause |

## `archive/state-2026-09/STANDALONE_PLAN.md`

Dated 2026-06-15 onward. Its Phase 0–11 skeleton is the literal ancestor of the current
`roadmap.yaml` node set (same ids/titles). Each phase folds to its roadmap node; only
phase-internal items not already covered above get their own row.

| item (short) | doc line | verdict | id / why |
|---|---|---|---|
| Phase 0 — shared naming engine | 161 | FOLDED, done | roadmap node `P0`, status done |
| Phase 1 — CloudKit internal sync | 228 | FOLDED, done | roadmap node `P1`, status done |
| Phase 2 — Export & Obsidian publish | 256 | FOLDED | roadmap node `P2`, status inprogress |
| Phase 3 — De-Mac the UX | 287 | FOLDED | roadmap node `P3`, status inprogress |
| Phase 3: navigation/IA decision — tab bar Notes·Library·Highlights·Settings | 298–305 | DONE-SINCE | built as the 4-tab IA (FEATURES.md line 217: "4-tab IA: Notes · Books · Journal · Settings") |
| Phase 4 — On-device Polish (iPhone-side, gated spike, Tier A-D adaptive engine) | 307–347 | SUPERSEDED | SPEC D74: "On-device iPhone polish: parked for v2 now the iPad polishes. Default: parked" — the iPad polishes instead (SPEC C180, built per memory `project_ipad_polish_fix.md`); roadmap node `P4` itself is still `planned` and may need its scope re-synced to this decision |
| Phase 4: PARKED title-presentation UI on mobile (Suggested/From-recording chooser doesn't fit a phone) | 344–347 | DROPPED | moot — the phone never polishes under D74, so no phone-side title-presentation chooser is needed |
| Phase 5 — Organization (pins, folders, nested tags, smart folders) | 349 | FOLDED | roadmap node `P5`, status planned; folders sub-item blocked on the same parked "folders model" decision as above |
| Phase 6 — Commonplace Book / Highlights (feed, Daily Review, quote cards) | 355 | FOLDED | roadmap node `P6`, status planned |
| Phase 7 — People & backlinks | 365 | FOLDED | roadmap node `P7`, status planned |
| Phase 8 — Journal & retrieval | 370 | FOLDED, done | roadmap node `P8`, status done — see `JOURNAL_RETRIEVAL_PLAN.md` section above |
| Phase 9a — Reading-experience redesign (mock-first) | 376–382 | FOLDED, partial | SPEC C108: text-forward hybrid player built; "remainder = reading themes (light/sepia/dark)" still ⚠ unverified — matches this item's leftover scope exactly |
| Phase 9b — Player polish (sleep timer, per-book speed, skip-silence, annotatable bookmarks, clips, cross-device handoff) | 383–387 | FOLDED | roadmap node `P9b` ("Audiobook player polish"), status planned |
| Phase 10 — Capture reach (Apple Watch) | 389 | FOLDED | roadmap node `P10` ("Apple Watch capture"), status deferred |
| Phase 11 — App Store readiness | 394 | FOLDED | roadmap node `P11`, status planned |
| Design system `SkriftDesignKit` (tokens package) | 213–226 | OPEN | no roadmap node or SPEC clause tracks whether this token package was ever built; would need a queue item or a status check against `Shared/UI/` |
| Significance reframed as a per-sink publish filter (Obsidian "publish all" vs "important only") | 581–593 | SUPERSEDED | the whole framing is replaced by SPEC C87/C210/C62 — rating is consent (three-ball importance), export gate is C61 (processed/rated/unlocked/live), destination is one of four (C62), not a per-sink significance filter |
| Migration checklist items 1–10 (drop `@Attribute(.unique)`, `cloudKitDatabase` config, entitlements, `MemoAsset`→CKAsset, audiobook state models, export identity fields, `MemoExporter`/`ObsidianPublisher`, de-Mac gating, significance reframe, `-inMemoryStore` offline tests) | 598–608 | SUPERSEDED | this is the pre-native-rewrite migration plan for the (then still React-Native-derived) phone app; the current architecture (CLAUDE.md: "Two native SwiftUI apps that sync over CloudKit") was built as a fresh rewrite, not a migration along this checklist — items 1–4, 6, 10 are the CURRENT shipped architecture, not open work |
| Decision "still open" #5: Folders model | 576–577 | FOLDED | SPEC "Parked ideas" list (same as SOURCE_OF_TRUTH row above) |
| CONTINUE HERE: cellular "ready to sync · N MB" tap-to-pull affordance (NWPathMonitor) | 508 | OPEN | not named in any later ledger |
| CONTINUE HERE: owed fast-follows — light/sepia reading themes, global cross-tab mini-player | 456 | FOLDED, split | light/sepia themes = SPEC C108 (still owed); global mini-player = DROPPED — FEATURES.md line 218 ("Audiobook chrome") records the deliberate call: "Journal/Settings carry nothing (user call)" |
| CONTINUE HERE: Phase 1h-ii per-book audiobook sync UI (toggle, row states, Settings section, Wi-Fi policy) | 540–552 | DONE-SINCE | roadmap nodes `D1`/`D2` ("Per-book audiobook sync + real %", "Everything syncs"), both status done (Jun 19) |
| CONTINUE HERE: 10 pre-existing iOS-26 SkriftMobileUITests failures | 507, 526 | FOLDED | SPEC D85 (retire the XCUITest suite) — same verdict as AUDIT_FIX_TESTLIST.md's identical item |
| Device-verify owed for Phase 1c/1d/1e/1f (asset/sidecar/names/vocab CloudKit sync) | 524, 528–534 | DONE-SINCE | CLAUDE.md's current architecture description confirms CloudKit sync is the shipped spine; roadmap "Mac rejoins via CloudKit" node, status done |

## `archive/state-2026-09/TESTFLIGHT_INSTALL_HANDOFF.md`

Dated 2026-08-29/30. Root cause found and documented; the fix itself was never confirmed
executed in this repo.

| item (short) | doc line | verdict | id / why |
|---|---|---|---|
| File Feedback Assistant report with a sysdiagnose, cross-post to forums thread 813703 | 24–26, 250–271 | OPEN | no SPEC clause, BUGS row, or roadmap node tracks TestFlight account-level remediation; would need a roadmap `P11` (App Store readiness) backlog line or a standalone tracked task |
| Route B: developer.apple.com/contact, Developer Program Support callback, ask for "senior-advisor reversal" by name | 273–286 | OPEN | same as above — no live ledger entry |
| Ad Hoc distribution unblocks the 5 testers meanwhile | 321–338 | OPEN | not recorded anywhere as done/attempted in SPEC, BUGS, or roadmap |
| Housekeeping: `SkriftShared` framework target hardcoded `CURRENT_PROJECT_VERSION: "28"`, drifted from the app's 167 | 372–375 | DONE-SINCE | commit `08bcdf57` "fix(📱): one place to bump the version, and the widget's App Group answered" — `project.yml` now derives every target's version from `$(SKRIFT_BUILD)` |
| 167 is the build to re-distribute once Apple restores the contract; 168 (iPhone-only experiment) should not ship | 361–365 | OPEN | contingent on the account-block resolution above, itself unresolved |

## `Skrift_Native/IPAD_PLAN.md`

Dated 2026-07-22, "wave 1." Directly cited and superseded in detail by the live roadmap node.

| item (short) | doc line | verdict | id / why |
|---|---|---|---|
| Wave-1 scope: Foundation, Shell+Notes, Note detail, Review, Books, Polish on iPad | 33–52 | FOLDED, built | roadmap node `iPad` ("iPad — the reading room", status inprogress) shipped log: chrome + eyeball waves BUILT and installed (120); note-view stacking REBUILT (130); "chrome that belongs" v2 signed + BUILT + installed (132, Tuur-confirmed 2026-07-24) |
| Polish on iPad: feature-flagged, live generation device-owed (sim can't Metal-JIT) | 47–51 | FOLDED, still open | roadmap node `iPad`'s own "Owed:" line: "polish + prompt-sync live test (sim can't Metal-JIT)" |
| Out of scope: reading-mode redesign (its own wave) | 55 | FOLDED | SPEC C108 — same item as tracked above |
| Out of scope: iPad batch/background polishing, polish elections | 56 | DROPPED | deliberate design constraint, restated as locked in SPEC C180 ("no polish-on-open") |
| Out of scope: Mac-style Queue/pipeline surfaces on iPad | 57 | DROPPED | deliberate — "the Mac remains the factory" |
| Out of scope: App Store iPad screenshots | 58 | FOLDED | SPEC roadmap node `P11` (App Store readiness) covers screenshots generally |
| Owed: Tuur's Mac eyeball (incl. snapshot-blind ⋯ chip), the undiagnosed "could not process" error, "Mark all as Passing" wording, promote to main | (roadmap node text, not in this file) | FOLDED, still open | roadmap node `iPad`'s own "Owed:" line names these exactly |

## `Skrift_Native/CAPTURE_CONTRACT.md`

The C3 wire contract. No unchecked items in the doc itself (it is written as a MUST-shape
contract, fully built); several "v1 only, additive later" hedges are now resolved by SPEC.

| item (short) | doc line | verdict | id / why |
|---|---|---|---|
| `urlThumbnailUrl` — "optional, unused v1" | 41 | FOLDED | SPEC C72: "title/description/thumbnail fetched on drain (one GET, no JS, local thumbnail…)" |
| `title` absent v1, Mac derives/suggests | 57–58 | FOLDED | SPEC C25 (title ladder) |
| Context fields (location/weather/capturedAt) absent v1, "additive later" | 59–60 | SUPERSEDED | SPEC C202: "Captures get no location or weather" — now a permanent rule, not a v1 stopgap |
| "NO mic v1" on the capture sheet | 133 | FOLDED, built with an open bug | SPEC D71 (in-app voice-annotate, default yes), matches SHARE_INGEST_SURVEY's "voice-annotate ✅ built UNVERIFIED" row and BUGS §1 D16/R87 |
| `tags: []` v1, "the sheet has no tags row by design; Mac suggests" | 56 | FOLDED | SPEC C36: "a SHARE capture… gets title + summary + tags on its annotation" |

## `FEATURES.md` (planned/partial/owed rows only)

| item (short) | doc line | verdict | id / why |
|---|---|---|---|
| Speaker turns + name-a-speaker — desktop 🟡, resolver deleted, in-prose popover took over | 74 | FOLDED | SPEC C80/D77 (in-prose naming UI, one model both apps) |
| Conversation turn gutter — mobile 🟡 "hues only" | 255 | FOLDED, mostly built | row's own note: built to the signed mock 2026-07-27, Tuur-confirmed on the Mac; phone got the same hue table onto its existing cards — the 🟡 marks a cosmetic parity gap (phone keeps cards, Mac has gutter+spine) that SPEC C175 states as the locked difference: "the phone KEEPS its turn cards with the shared hues" |
| Journal: Foreground sweep wiring 🟡 — floor calibration owed | 383 | DONE-SINCE | see `JOURNAL_RETRIEVAL_PLAN.md` row above — floors calibrated, roadmap `P8` done |
| Journal: index consent flow 🟡 — device enable + eyeball owed | 384 | DONE-SINCE | roadmap `P8` shipped log: device-verified builds 40–53 |
| Journal tab: Looking back + calendar + map 🟡/🟡 — pushed screens + device eyeball owed | 385 | DONE-SINCE | roadmap `P8` shipped log: device-verified, floors calibrated; Mac side also shipped 2026-07-13 |
| Search "Related" + Thread view / Mac Connections panel 🟡/✅ — phone device round owed | 386 | FOLDED, still open | row's own note: "phone device round owed" as of its last edit; not superseded by a later confirmation in SPEC or roadmap — genuinely still a loose end, though the desktop half is extensively verified |
| Related card on note detail 🟡 — conversation/capture pages don't get it until they migrate to the editor layout | 387 | FOLDED | SPEC C113 (editor rebuild on body v2) is the blocking rewrite this is waiting on |
| Print-to-wall + Important lately 🟡 — physical print + card-design round owed on device | 388 | FOLDED | SPEC C233 (print-to-wall fires once per note on crossing into the top ball) restates the rule for v2; the physical device round isn't separately tracked — would need a queue item |
| "Known targets (open work as of 2026-06-09)" — B: model-loading placeholder, live auto-scroll, color-by-confidence, inline [photo N], AirPods robustness, append-flow verify, keyboard-dismiss | 394 | DONE-SINCE | live-caption coloring + [photo N] anchoring shipped 2026-06-12 (FEATURES.md line 22); AirPods robustness = memory `project_audio_session_round` (multi-round fix, HFP-flip verdict landed) |
| "Known targets": A — surface user `title` on rows; suppress "Waiting" on significance-0 memos | 395 | DONE-SINCE | title ladder now SPEC C25 / built via the m2 note card (FEATURES.md line 62); the whole significance/rating model was rebuilt under SPEC C87 (rating is consent), which removes the "Waiting" framing this item was chasing |
| "Known targets": C — video import → audio extraction (mobile + desktop) | 396 | DONE-SINCE | SPEC C71 (video ingress, built) |
| "Known targets": D — Liquid Glass pass (player bar/sidebar) | 397 | DONE-SINCE | SOURCE_OF_TRUTH §5 gotcha confirms Liquid Glass rules were learned and applied (`.glassEffect(.clear)`, Reduce Motion, simulator caveat) — the pass happened |

## `CHANGELOG.md` (unreleased/owed lines)

No "Unreleased" heading exists in the file (`grep -n "^##"` shows only `## 0.2.0` and
`## 0.1.0`), and no line in it is marked owed or TODO. Zero rows.

---

## OPEN items across all docs

Counts (this half only; `backlog.md` excluded):

- `AUDIT_PLAN.md` — 12 OPEN (P5, P6, P7, note-opening-twice, read-along redraw, Mac vault-scan cap, no `#Index`, GemmaEmbedder race, strict-concurrency adoption plan, long-compile hunt, dead-code tooling, mutation testing, XcodeBuildMCP)
- `JOURNAL_RETRIEVAL_PLAN.md` — 3 OPEN (iPad layout pass, person/kind filter chips, vault-to-iCloud-Drive relocation)
- `NAMING_MODEL.md` — 1 OPEN (in-NSTextView body eyeball)
- `SHARE_INGEST_SURVEY.md` — 0 OPEN (everything folded)
- `SKRIFT_SOURCE_OF_TRUTH.md` — 8 OPEN (word-select-to-name parity, diarization-survives-backgrounding, audiobook unshare phantom entry, whole-book memory-pressure lead, capture sentence-split on abbreviations, phone Models/Storage view, desktop walkthrough-tracker items, project-age unverified)
- `STANDALONE_PLAN.md` — 2 OPEN (SkriftDesignKit token package status, cellular tap-to-pull affordance)
- `TESTFLIGHT_INSTALL_HANDOFF.md` — 4 OPEN (Feedback Assistant filing, Developer Support callback, Ad Hoc distribution status, which build ships once unblocked) — all one underlying unresolved account issue
- `AUDIT_FIX_TESTLIST.md` — 0 OPEN
- `IPAD_PLAN.md` — 0 OPEN
- `CAPTURE_CONTRACT.md` — 0 OPEN
- `FEATURES.md` — 0 OPEN (one FOLDED-but-still-open row: phone Connections device round)
- `CHANGELOG.md` — 0 OPEN

**Total: 30 OPEN rows across 6 docs.**
