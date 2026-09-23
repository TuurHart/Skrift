# Source ledger — archive/handoffs/ + memory owed items

Date: 2026-09-23. Built per SPEC.md C276 ("a cited document is not a folded document"; every
open item in every old plan gets a verdict). This is the other half of `plan/sources.md`
(which covers `plan/extraction/*.md`): it covers the twelve docs in `archive/handoffs/` and
the owed/parked/deferred lines pulled from every file under
`/Users/tiurihartog/.claude/projects/-Users-tiurihartog-Hackerman-Skrift/memory/`.

Doc list: CONVERSATION_MODE_HANDOFF.md, DESKTOP_NATIVE_HANDOFF.md, DESKTOP_NATIVE_REWRITE_PLAN.md,
HANDOFF-2026-07-25-audio-session.md, LIVE_SYNC_HANDOFF.md, MAC_CLOUDKIT_PLAN.md,
MOBILE_NATIVE_HANDOFF.md, MOBILE_NATIVE_REWRITE_PLAN.md, NEXT_CHAT_HANDOFF.md,
OBSIDIAN_EXPORT_ALTERNATIVES.md, TEXT_CAPTURE_WAVE2_HANDOFF.md, WALKTHROUGH_BUGS.md.

Verdicts checked against SPEC.md (clauses C1–C276, required differences R1–R89, decisions
D1–D100), BUGS.md, `roadmap/roadmap.yaml`, and `git log` where a DONE-SINCE claim needed a
commit. A doc's Bonjour/local-HTTP sync content is marked SUPERSEDED once, citing SPEC.md's
"No Python, Electron, React Native, Bonjour; CloudKit is the only transport" (Not doing, near
line 1543) and `CLAUDE.md`'s "Bonjour/HTTP LAN sync is fully retired" — that line is not
repeated per sub-item inside those docs.

---

## archive/handoffs/CONVERSATION_MODE_HANDOFF.md

| item (short, the doc's words) | doc line | verdict | id / why |
|---|---|---|---|
| Device-test the phone auto-match (name in recording A, auto-label in B); tune the 0.5 threshold on real audio | 54–58 | DONE-SINCE | D88 (SPEC.md) decides the voice-enrollment floor at 2s and the design shipped; `roadmap.yaml` `H_conv` (done) logs "2026-06-09 Voice identity — embedding-cosine, measured threshold 0.5 [8ccc3d2, 245db92]" as shipped, and FEATURES.md "Persist diarization segments" row is ✅/✅ on both apps. |
| Bidirectional voice-sync verify (phone enroll → Mac recognizes; Mac enroll → phone recognizes) | 59–61 | SUPERSEDED | Bonjour transport this doc assumes is retired; voice sync now rides the same CloudKit `NamesRecord` union as every other Names field (CLAUDE.md "Names sync over CloudKit... via NamesMerge LWW (union voiceEmbeddings)"). No open clause names a remaining voice-sync gap. |
| Mac-originated enrollment ("6b-full") — persist diarization segments per memo + a name-a-speaker review-UI affordance in `NoteDisplayView` | 62–68 | FOLDED | SPEC.md Parked ideas (line ~1535): "the Mac name-a-speaker review UI (owed after v2)". Segment persistence itself shipped (FEATURES.md "Persist diarization segments (for later enrollment)" row, desktop `DiarizationSidecar.swift`, "unblocks Mac 'name a speaker'"); only the review-UI affordance is still parked, explicitly past v2. |
| (F) Live diarization while recording (phone) | 69 | OPEN | Not in SPEC.md, BUGS.md or roadmap.yaml. Would need a v2 spec clause if picked up — it is not one of the 276 clauses today. |
| Fallback: sync a compressed audio sample per person + `enrollSpeaker` (only if embedding-cosine proves weak) | 231–235 | DROPPED | Conditional fallback, never triggered — the embedding-cosine design shipped and is the one SPEC.md/FEATURES.md describe; no clause proposes the audio-sample fallback. |

## archive/handoffs/DESKTOP_NATIVE_HANDOFF.md

| item (short, the doc's words) | doc line | verdict | id / why |
|---|---|---|---|
| Whole Bonjour/local-HTTP sync server + phone↔Mac round-trip (§4 contract, D "mobile track waits on this app") | 22, 183 | SUPERSEDED | Doc header note. |
| Parity golden tests — extend beyond Sanitiser to TagMatcher/Compiler | 36, 162 | OPEN | Not in SPEC.md/BUGS.md/roadmap; no golden-parity node exists post-Python (the Python backend it compares against is archived, so a byte-parity oracle no longer applies the same way — SPEC.md v2 rewrite instead judges by "output diffs" against v1, `V2Core` node). |
| Extend the live-app pilot/XCUITest walkthrough to Process→Ready + resolver + body editing | 173 | SUPERSEDED | D85 (SPEC.md): "Retire the XCUITest suite... the unit suite is the gate." The UI-test coverage this item asks for is deliberately not being extended. |
| North star: local-embedding vault semantic search + related-notes timeline ("see how my thinking evolved over time") | 61, 169–170, 175–180 | DONE-SINCE | `roadmap.yaml` node `P8` ("Journal / On-This-Day / search"), status done 2026-07-07, win: "On This Day + timeline + semantic 'related notes' work on-device — a years-old thought resurfaces next to today's." Device-verified by Tuur (builds 40–53). |
| Owed chore: re-ingest the old Electron app's ~35 audio files, then clear the old store | 61 | FOLDED | SPEC.md Parked ideas: "re-ingest of the Electron-era notes" — named explicitly, not scheduled. |
| Product idea — Backlink Weaver (auto-link vault note titles, not just people) | 176 | FOLDED | SPEC.md Parked ideas: "Backlink Weaver" — named, not scheduled. |
| Product idea — Context-aware enhancement (feed phone's place/weather/people/time into the Gemma prompt) | 177 | DROPPED | D82 (SPEC.md, builder default 2026-09-22): "Summary prompt quality / context hints... prompts frozen in v2, no sensor context." Direct contradiction of the idea; decided against. |
| Product idea — People Timeline (per-person note view) | 178 | FOLDED | SPEC.md Parked ideas: "people pages (P7)" — same shape, named, not scheduled. |
| Product idea — Smart Suggest New People (NLTagger pass → "Add [[Sam]]?") | 179 | DROPPED | SPEC.md Not doing: "no LLM in naming, tagging or importance... no auto 'new person?'" — explicitly ruled out. |
| Product idea — Ask-Your-Memos (local RAG chat over notes) | 180 | DROPPED | SPEC.md Not doing: "no vision pipeline; no chat/ask" — explicitly ruled out. |
| Product idea — Weekly Digest | 180 | FOLDED | SPEC.md Parked ideas: "monthly digest" — same shape (periodic summary), named, not scheduled. |
| Data-quality: clean up the user's real `names.json` (`short:"None"` literal, `jank`/`timmons` shorts) | 273 | OPEN | Not in SPEC.md/BUGS.md/roadmap. The names data model has changed substantially since (CloudKit `NamesRecord`), so this specific June-2026 dataset issue is not tracked as a distinct item. |

## archive/handoffs/DESKTOP_NATIVE_REWRITE_PLAN.md

| item (short, the doc's words) | doc line | verdict | id / why |
|---|---|---|---|
| Whole plan — thin Swift server + Bonjour as the phone's sync target (§4), Phase 9 "retire Electron/Python" | throughout | SUPERSEDED | Doc header note. Phase 9's retirement half is DONE-SINCE regardless: CLAUDE.md confirms the old apps are archived intact under `archive/`. |
| Phase 7/8/9 checklist tail — review UI / ingest+settings / parity+retire (marked `[ ]` at file end) | 229–231 | DONE-SINCE | All built per DESKTOP_NATIVE_HANDOFF.md's own STATUS line ("Phases 0–8 GREEN... feature-complete for the core loop") and the current app existing at `Skrift_Native/SkriftDesktop/` per CLAUDE.md. |

## archive/handoffs/HANDOFF-2026-07-25-audio-session.md

| item (short, the doc's words) | doc line | verdict | id / why |
|---|---|---|---|
| Whole doc — record-start latency (pre-warm, don't rebuild per retry, `.allowBluetoothA2DP`, move off main actor) | 72–88 | DONE-SINCE | `roadmap.yaml` node `RecHard` (inprogress) shipped log 2026-07-26: "Record-start pre-warm... 'Starting…' folded into the recording layout [26899d3]" and "PRESTART — capture starts AT the record button... 8s unclaimed expiry... Phase 3 superseded [164cf53, b115]" and "b115 trace verdict (the cold-AirPods second = the A2DP→HFP flip inside engine.start, 969ms)... prestart race FIXED [2188e59, b116]" — all one day after this handoff was written. |
| Audiobook route handling — interruption `.ended` resume, quote-capture handback, silent-stop recovery, false end-of-book guard, Now Playing ownership | 90–106 | DONE-SINCE | Same `RecHard` shipped log 2026-07-26: "Two-phase Bluetooth handoff built (b117) → REJECTED on its own device round... → fallback enacted b119 — with Bluetooth around the whole memo records on the built-in mic, output stays A2DP." The specific two-phase design this doc proposed was tried and rejected on-device; a different fallback shipped instead — not a straight yes, but the underlying problem (route loss around a recording) was closed, not left open. |
| Close-out: tick backlog.md items, update FEATURES.md, update roadmap.yaml, archive this file | 110–115 | DONE-SINCE | The file IS archived (this doc lives in `archive/handoffs/`), confirming the close-out ran. |
| Remaining live backlog item under the same investigation | — | OPEN | `RecHard`'s own current `backlog:` still lists "Device round on the 13 — devlog snapshot-ms trace; call/alarm mid-record survives; camera-sheet latency; freeze gone?" — carried forward in the live roadmap, not this doc. |

## archive/handoffs/LIVE_SYNC_HANDOFF.md

| item (short, the doc's words) | doc line | verdict | id / why |
|---|---|---|---|
| Part A — delete the mobile Bonjour code (file list, project.yml edits) | 35–80 | DONE-SINCE | The doc's own "✅ STATUS" section says Part A shipped + pushed (`0dab500`); CLAUDE.md confirms "Bonjour/HTTP LAN sync is fully retired 2026-07-06." |
| Part B — live bidirectional editing, Mac→phone write-back + phone→Mac reconcile; device round-trip OWED at write time | 12, 84–119 | DONE-SINCE | CLAUDE.md's CloudKit sync contract line describes exactly this as shipped, steady-state behavior: "the Mac ingests a synced memo (MemoCloudIngest)... writes its polish back as MemoEnhancement (LWW by enhancedAt)." `roadmap.yaml` `NFeat`/`DParityB` shipped logs (2026-07-15 on) build on top of this working two-way sync (tags/importance sync, delete sync, etc.), which would be impossible if Part B were still broken. |
| Push the 14 commits | 124 | DONE-SINCE | Superseded by every later commit on `main`; moot. |
| Prod gate: deploy CloudKit Production schema + one prod round-trip before promoting Release | 125–126 | DONE-SINCE | MAC_CLOUDKIT_PLAN.md's own later entry: "Release-config capabilities VERIFIED DONE 2026-06-26" and prod app `/Applications/Skrift.app` exists and runs per CLAUDE.md. |
| Backlog parity item: Mac in-place name-linking (dotted/tappable in the review body, immediate not post-enhance) | 127–128 | FOLDED | SPEC.md Parked ideas: "Mac in-place linking" — named, not scheduled. (Note: a different feature, the Mac `[[` link-PICKER for memo-links, did ship per `DParityB` 2026-07-15 — that is not this item.) |

## archive/handoffs/MAC_CLOUDKIT_PLAN.md

| item (short, the doc's words) | doc line | verdict | id / why |
|---|---|---|---|
| Finish one round-trip: Process on Mac → enhance → write-back syncs → phone's Obsidian export uses polished text | 62–63 | DONE-SINCE | `MemoExporter` "prefers" `MemoEnhancement" per FEATURES.md and CLAUDE.md's sync-contract line; years of later work (NFeat, DParityB, W9, ExportDestinations) build on this path functioning. |
| Prod promotion: confirm `MemoEnhancement` record type exists in CloudKit Production | 64–69 | DONE-SINCE | Same VERIFIED-DONE 2026-06-26 note referenced above; prod app is live. |
| Known limitation: capture items dedup only on CloudKit re-ingest, not cross-transport (Bonjour + CloudKit double-create) | 71–76 | SUPERSEDED | Bonjour retired 2026-07-06 — the cross-transport case this describes cannot occur anymore (there is only one transport). |
| Open decision 1 — model sharing (`Memo`/`MemoAsset` truly shared) vs a Mac-local mirror | 250–254 | DONE-SINCE | `Shared/Model/Memo.swift` described as built in the doc's own RESUME block ("8a-ii — true-share Memo/MemoAsset/DeviceID → Shared/Model"); this is the decided-and-built path, not an open question anymore. |
| Open decision 2 — W1 vs W2 write-back shape | 255 | DONE-SINCE | Doc's own RESUME block: "8c — write-back (MacCloudWriteBack)... upsert a MemoEnhancement" — W2 was built. |
| Open decision 3 — desktop signing change to team signing | 256–257 | DONE-SINCE | Doc's own hard-steps checklist: "✅ DONE. The main app target now signs with CODE_SIGN_STYLE: Automatic + DEVELOPMENT_TEAM: 9W82X49JZS." |
| Open decision 4 — process-everything vs significance>0 default | 258 | DONE-SINCE | FEATURES.md "Capture sync" row: "Same significance>0 gate" — confirms >0 stayed the default, consistent with `AppSettings.cloudKitMacSync`/`processAllSyncedMemos` opt-in described in the doc's own RESUME block. |
| Open decision 5 — retire Bonjour eventually | 259 | DONE-SINCE | Retired 2026-07-06 per CLAUDE.md. |

## archive/handoffs/MOBILE_NATIVE_HANDOFF.md

| item (short, the doc's words) | doc line | verdict | id / why |
|---|---|---|---|
| Karaoke tap-to-seek (Settings toggle, per-word hit-testing) | 333–338 | DONE-SINCE | `roadmap.yaml` `NFeat`/other shipped logs describe a working karaoke renderer (`Shared/Pipeline/Karaoke.swift`, `DParityB` "Board C7... Karaoke twins → ONE Shared/Pipeline/Karaoke.swift"); FEATURES.md documents karaoke as shipped on both apps. |
| Restore the ~35 old Electron-era notes (re-ingest into the prod desktop) | 339–344 | FOLDED | SPEC.md Parked ideas: "re-ingest of the Electron-era notes" — same item as the DESKTOP_NATIVE_HANDOFF.md row above. |
| Liquid Glass polish / significance slider / karaoke-tap-to-seek device confirmation (TabView(.page) fix) | 300–354 | DONE-SINCE | Doc's own later section says this was fixed and deployed (`d96dafb`); superseded within the doc itself, then carried further by the whole 2026-06 device-hardening pass ("LIVE ROUND-TRIP VERIFIED"). |
| Share Extension + capture items (Task-items gap #1, "entirely missing") | 473–479, 513–523 | DONE-SINCE | CLAUDE.md "Capture items — ✅ BUILT 2026-06-12"; roadmap `H_capture` node status done. |
| Lock/Home Screen widgets + app-icon Quick Record | 480–484 | DONE-SINCE | CLAUDE.md feature list: "Control Center + Lock/Home widgets"; MOBILE_NATIVE_REWRITE_PLAN.md Phase 8 status `[x]` with Live Activity/Control Center/App Intents/Share Extension shipped. |
| Memory-aid prompts (record-screen prompt list + Settings editor, dropped from RN) | 485 | OPEN | Not in SPEC.md/BUGS.md/roadmap — never picked back up. |
| Full capture-context surfaced in Memo detail (daylight/steps/pressure/full weather rows) | 486–488 | DONE-SINCE | `roadmap.yaml` `NFeat` 2026-07-16 shipped entry: "the Mac now SHOWS the place · weather · daypart CONTEXT CHIPS under the title" — mirrors the phone side; D92 (SPEC.md) locks the Mac getting the same context as the phone. |
| Photo filmstrip with offset labels + full-screen viewer | 489–490 | OPEN | Not found in SPEC.md/BUGS.md/roadmap under this description; inline embeds shipped instead (per FEATURES.md), but a dedicated filmstrip + full-screen viewer is not confirmed built. |
| Settings extras: storage stats + "Clear synced memos" + persisted last-sync time | 494–495 | OPEN | Not in SPEC.md/BUGS.md/roadmap. |
| Pull-to-refresh / on-focus auto-sync / row-swipe-delete | 496–497 | DONE-SINCE | LIVE_SYNC_HANDOFF.md Part A: "Pull-to-refresh can trigger a CloudKit reconcile (NamesCloudSync/VocabularyCloudSync/AssetMaterializer — the `.refreshable` already calls these)." Swipe/multiselect delete shipped per `project_unification_backlog` memory ("native-List swipe/multiselect"). |
| Auto-enqueue trusted mobile uploads on the Mac (hands-free processing) — open decision | 809–810, 896 | OPEN | Not decided in SPEC.md/BUGS.md/roadmap; the Mac still requires a rating/pickup gate by design (NoteConsent, `W9`), which reads as the opposite default, but no clause explicitly closes this exact question. |
| Substitutions feature (synced deterministic word-substitution list) | 898–902 | FOLDED | SPEC.md Parked ideas: "substitutions list" — named, not scheduled. |
| App Intents Start/Stop — user hesitant, prototype carefully | 903–906 | DONE-SINCE | MOBILE_NATIVE_REWRITE_PLAN.md Phase 8 `[x]`: "App Intents + Control Center + Live Activity Stop... SIGTRAP-avoided: plain AppIntent+openAppWhenRun." |
| Dictate-anywhere keyboard — deferred big bet, not chosen | 907 | FOLDED | SPEC.md Parked ideas: "dictate-anywhere" — named, not scheduled. |
| Retire `Mobile/` (RN) only at native parity | 524–527, 908 | DONE-SINCE | CLAUDE.md: "The previous apps are preserved intact under `archive/`... `archive/Mobile/` = old React Native iOS" — relocated (not gutted), matching the user's own stated requirement in this doc. |
| Marker insertion UTF-16 vs Python `str` — spot-check `[[img_NNN]]` parity on multibyte/emoji transcripts | 889–890 | OPEN | Not in SPEC.md/BUGS.md/roadmap; the Python backend it compared against is archived, so a like-for-like parity check no longer applies, but no note confirms the multibyte case was separately checked against the Swift implementation. |
| Bonjour pairing hardening: no "allow this iPhone?" confirm on the Mac side | 403–405 | SUPERSEDED | Bonjour retired. |
| Desktop `title`-read from upload metadata | 407–409 | DONE-SINCE | DESKTOP_NATIVE_HANDOFF.md STATUS line: "F1 phone-title extraction (unblocks mobile title)" listed as done. |

## archive/handoffs/MOBILE_NATIVE_REWRITE_PLAN.md

| item (short, the doc's words) | doc line | verdict | id / why |
|---|---|---|---|
| Phase 9 — parity sweep + retire `Mobile/` (checklist `[ ]`) | 348 | DONE-SINCE | Same as MOBILE_NATIVE_HANDOFF.md row above — `Mobile/` relocated intact under `archive/`. |
| Live names round-trip vs a running Mac (flagged "still pending" in Phase 1 status) | 279 | DONE-SINCE | CloudKit names sync has run continuously since 2026-06 per CLAUDE.md's sync contract and dozens of later roadmap entries touching `NamesCloudSync`/`NamesMerge`. |
| Live POST against the running desktop app (Phase 6 status) | 312 | SUPERSEDED | The upload target was Bonjour/HTTP; superseded by CloudKit ingest (`MemoCloudIngest`). |

## archive/handoffs/NEXT_CHAT_HANDOFF.md

| item (short, the doc's words) | doc line | verdict | id / why |
|---|---|---|---|
| Device eyeball owed: ❝ glyph (CC + widget), full-screen player + read-along sync (`ReadAlongView.lead` dial), merged capture E2E, bidirectional/bounded selection, share-video open-on-import, date sorts + filter | 49–51 | DONE-SINCE | D89 (SPEC.md) locks the read-along `lead` at 0.1s (settled, no longer an open dial); `roadmap.yaml` `EPubAlign` (done 2026-07-22) and `H_sprint` describe this whole capture/player generation as shipped and superseded by the 2026-06-13 audiobook-player-redesign and later rounds. |
| TestFlight build-1 export-compliance prompt handling | 71–72 | DONE-SINCE | `project_testflight` memory documents many later builds (through at least 168) with export-compliance already a settled non-issue; TestFlight distribution is now routine per CLAUDE.md's "TestFlight distribution" section. |
| Pre-existing backlog: prod promotion (push `native`→`main`) | 78 | DONE-SINCE | CLAUDE.md Branch section: "main IS the trunk" since 2026-06-14 — done. |
| Pre-existing backlog: Mac "name a speaker" UI (backend ready) | 78 | FOLDED | Same SPEC.md Parked-ideas line as the CONVERSATION_MODE_HANDOFF.md item: "the Mac name-a-speaker review UI (owed after v2)." |
| Pre-existing backlog: record-a-voice enroll (placeholder both apps) | 78 | OPEN | Not found as a distinct item in SPEC.md/BUGS.md/roadmap; the enrollment mechanism exists (conversation naming enrolls a voice) but a standalone "record a voice" affordance in `PersonDetailView` is not confirmed built. |
| Pre-existing backlog: drag-multi-select (Photos-style lasso, wants a mock) | 79 | FOLDED | SPEC.md Parked ideas: "lasso multi-select" — named, not scheduled. |
| Pre-existing backlog: desktop Models/Storage view | 79 | OPEN | Not in SPEC.md/BUGS.md/roadmap. |
| Pre-existing backlog: in-app feedback→inbox | 79 | OPEN | Not in SPEC.md/BUGS.md/roadmap. |
| Pre-existing backlog: source-taxonomy unification | 79 | OPEN | Still listed as open cross-app work in CLAUDE.md itself ("Unified source taxonomy... folds into capture items"), but no SPEC.md clause or roadmap node tracks it as a scheduled item today — the spec/queue would need a clause naming the remaining glyph/label inconsistencies across source kinds (voice/URL/PDF/video/quote/note) to close it. |
| Pre-existing backlog: re-ingest old notes | 80 | FOLDED | Same "re-ingest of the Electron-era notes" Parked-ideas line as above. |
| Pre-existing backlog: "transcription a bit weird" on cold auto-start | 80 | OPEN | Also named PARKED in `project_unification_backlog` memory ("user is unsure it's a real bug"). Not in SPEC.md/BUGS.md/roadmap — would need a repro before it could become a clause. |

## archive/handoffs/OBSIDIAN_EXPORT_ALTERNATIVES.md

| item (short, the doc's words) | doc line | verdict | id / why |
|---|---|---|---|
| Decision doc itself — ship #1 (one-way overwrite) now; evolve to the split-note+guard hybrid (user-owned region + round-trip guard + `skrift-id`) later; #6 per-book commonplace book later; Phase-8 PULL (vault-read for search) later | throughout | FOLDED/DONE-MIXED | #1 (built) is superseded by `SharedExport`'s VaultWriter engine (roadmap, done-ish/inprogress: "never write over foreign/legacy/edited files (edit guard live on the Mac)" — this already IS the round-trip guard from option #4, done, not just planned). The user-owned-region split-note hybrid and the `skrift-id` framing itself are not named as such in SPEC.md; `SharedExport`'s "the folder is an INBOX — identity lives in the file's stamp (skriftID/skriftHash/real lastTouched...)" is the shipped equivalent of the `skrift-id` idea. Per-book commonplace book → SPEC.md Parked ideas: "commonplace book." Phase-8 PULL (vault-read for search) → DONE-SINCE via `roadmap.yaml` `P8` (done 2026-07-07) — though P8 indexes Skrift's own notes, not the Obsidian vault contents; a true Obsidian-vault read is still what SPEC.md Parked ideas calls "vault-read direction" (parked, not decided). |

## archive/handoffs/TEXT_CAPTURE_WAVE2_HANDOFF.md

| item (short, the doc's words) | doc line | verdict | id / why |
|---|---|---|---|
| Task 1 — whole-book pre-transcribe (`BookTranscript` sidecar, chunker, resumable job, "Transcribe book" menu item, instant capture from the sidecar, real per-hour estimate) | 28–39 | DONE-SINCE | CLAUDE.md "Open cross-app work → Audiobooks" section: "Text-capture WAVE 2 (mobile) — whole-book pre-transcribe: BookTranscript sidecar + ChunkFusion + resumable BookTranscriptionJob + Transcribe-book button + instant sidecar capture" — listed as shipped in the same 2026-06-13 batch. `roadmap.yaml` `TrEngine` (done 2026-07-11) further replaced the temp-WAV chunker with in-memory chunking, superseding the exact mechanism this doc proposed while keeping the feature. |
| Task 2 — fix custom vocabulary ("Script"→"Skrift" mis-transcription; alias mechanism; non-blocking booster) | 43–59 | DONE-SINCE | CLAUDE.md pinned memory line: "Custom vocab fixed both apps — pre-warm booster + aliases + trust guard; device-confirmed working" ([[project_vocab_booster]]), listed as the resolution of this exact task. |

## archive/handoffs/WALKTHROUGH_BUGS.md

| item (short, the doc's words) | doc line | verdict | id / why |
|---|---|---|---|
| C1 — three green health dots unclear (deferred to a ui-audit visual pass) | 13 | OPEN | Left `☐` in the doc itself and not named in SPEC.md/BUGS.md/roadmap; the desktop UI has been rebuilt several times since (v5 shell, `NoteCardM2`), so the specific health-dot affordance this refers to may no longer exist as described — unverified either way. |
| ST7 — verify Settings confirm-prompts match Electron (Wave D) | 23 | OPEN | Never actioned in the doc; Electron app is archived, so a like-for-like prompt-text comparison no longer has a live target — would need a fresh clause if still wanted. |
| E4 — verify YAML frontmatter structure (Wave D) | 51 | DONE-SINCE | `roadmap.yaml` `ExportDestinations` 2026-08-28 shipped entry: "Frontmatter UNIFIED against the real archive... two bugs his own rounds found... both apps' tests had made that same conflation" — frontmatter has since been reviewed against real data repeatedly, well past a wave-D checklist verify. |
| N2 — significance editable pre-process (left as-is, "not a clear bug") | 28 | DONE-SINCE | Superseded: `IPadWave1` 2026-07-23 shipped entry: "'Process N' wore the verb but not the meaning — it counted the UNRATED pile" fix, and the broader `NoteConsent`/rating-as-consent model (`W9`, done) makes significance gating pre-process a deliberately answered design question, not an open bug. |

---

## Memory notes (owed / parked / deferred lines), grouped by note

Only notes that matched OWED/owed/"device round owed"/"not yet built"/PARKED/deferred are
listed. Notes with no such line (most of the ~90 under `memory/`) are omitted per the brief.

### project_audiobook_player.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Read-along sync layers — device round owed on all of it (drift fix + opt-in memo territory) | 32, 58 | DONE-SINCE | D89 (SPEC.md) settles the read-along `lead` at 0.1s; `roadmap.yaml` `EPubAlign` (done 2026-07-22, rounds 5–8 landed 2026-07-23) is "DEVICE-CONFIRMED across four live rounds... 'way more fucking aligned'." |

### project_audit_fix_wave.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| OWED: Tuur's smoke of `AUDIT_FIX_TESTLIST.md` top-4 | 16 | DONE-SINCE | `roadmap.yaml` `AuditFix` node status `done`, `done: 2026-07-19` — the node cannot be marked done under the roadmap-authoring rule without its win condition (which names this smoke) being met. |

### project_book_sharing.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Entire device round owed — nothing run end to end, neither sheet looked at | 3, 47 | DONE-SINCE | `roadmap.yaml` `BookShare` status `done`, `done: 2026-08-12`, shipped log: "round trip PROVEN on a real 42 MB bundle off Tuur's phone — arrival sheet, import, plays with read-along... Only AirDrop/Messages between two physical devices is left." Note: CLAUDE.md's own "Open cross-app work" section still calls book-sharing "NOT signed off yet" — that line is stale against the roadmap, which is the authoritative live state per CLAUDE.md's own rule. |

### project_capture_as_note_kickoff.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Parked kickoff (deferred 2026-07-07): capture-as-note design chunk + note-editing follow-ups | 3, 10 | FOLDED | `roadmap.yaml` node `CapNote` ("Capture reads as a note"), status `inprogress`, note: "Lane P of the 2026-07-12 parallel board — capture-as-note + note-editing follow-ups (verbatim brief = memory project_capture_as_note_kickoff, deferred 2026-07-07)" — this memory note is the CapNote brief by direct citation. |
| Device eyeball owed: photo camera dialog, checklist flow, bar v2.1 | 61 | FOLDED | Same `CapNote` node — still `inprogress`, win not yet met ("a capture opens as one normal editable note... on phone, export, and Mac"). |

### project_conversation_namelinking.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Slot-aware rename, reads fresh from sidecar — device-eyeball owed | 38 | DONE-SINCE | `roadmap.yaml` `H_conv` (done) + FEATURES.md diarization rows both ✅/✅; conversation-mode naming has been live and device-confirmed since CONVERSATION_MODE_HANDOFF.md's own "DEVICE-VERIFIED by the user" note. |
| #4 mid-sentence mis-attribution bounded by Sortformer quality — owed/watch | 43 | OPEN | Not tracked as a distinct clause in SPEC.md/BUGS.md; a quality ceiling, not a scheduled fix. |
| Fully hiding (vs dimming) the header `**` marks — owed (mock-first) | 45–46 | OPEN | Not in SPEC.md/BUGS.md/roadmap. |

### project_conversation_voice_identity.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Bidirectional sync LIVE round-trip; Mac-originated enroll UI (backend done) — owed | 53 | FOLDED | Same SPEC.md Parked-ideas line: "the Mac name-a-speaker review UI (owed after v2)" — matches this exactly, including the "owed after v2" framing. |

### project_desktop_parity_plan.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Desktop parity: DEVICE ROUND-TRIP STILL OWED | 16 | FOLDED | `roadmap.yaml` `DParityB` ("Desktop B-list + Journal on Mac"), status `inprogress` — its own 2026-07-15 shipped log repeatedly ends entries with "live round-trip owed" for the specific sync legs (delete sync, tags/importance sync, `[[` link picker). Still tracked live, not lost. |
| Journal map pins+interactions, chip clicks, checkbox eyeball still owed (Dev deploy only) | 48 | FOLDED | Same `DParityB` node — Board B (Journal mode) is part of the node's still-open scope. |

### project_epub_unified_text_sheet.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Mitigation not a proven root cause — device confirmation still owed | 38 | DONE-SINCE | CLAUDE.md ledger: "book-text-unified... signed off AND built 2026-07-23 same session, b110" — listed as fully closed, not just mitigated. |
| b113 built + suite-green but never installed — OWED install + activity-line eyeball | 45 | DONE-SINCE | Superseded by the same CLAUDE.md line above and by `roadmap.yaml` `EPubAlign`'s 2026-07-23 rounds 5–8, which build directly on the Book-text sheet and are themselves device-confirmed. |

### project_epub_alignment.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Owed: b94 device round (phone went offline mid-install) | 34 | DONE-SINCE | `roadmap.yaml` `EPubAlign` status `done`, `done: 2026-07-22`; rounds 5–8 (2026-07-23) explicitly device-verified past this point. |
| Eyes owed on b97 (sheet + re-align after schema gate) | 72 | DONE-SINCE | Same `EPubAlign` node, same shipped log. |
| Pictures-in-reader — PARKED for after spike 6 | 114 | FOLDED | SPEC.md Parked ideas: "ePub images in the reader" — named, not scheduled. |

### project_export_destinations.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Not merged to main; phone/iPad round owed | 3 | OPEN | `roadmap.yaml` `ExportDestinations` status `inprogress` (not `done`); most recent shipped line (2026-08-28) still ends "OWED: phone/iPad round, and merge to main" — genuinely still open in the live ledger. |
| Phone/iPad round owed (branch `claude/skrift-export-destinations-4fbea7`) | 44 | OPEN | Same as above — same node, same still-open item. |
| OWED: Tuur's device round, throwaway folder first (CloudKit-storage decision) | 51 | OPEN | Same `ExportDestinations` node — its 2026-08-27 shipped entry ends with the identical line. |
| OWED: a device round (share a photo with no words → rate → process → export) | 84 | OPEN | Same `ExportDestinations` node, 2026-08-26 shipped entry ("the processed-vs-polished gate split... OWED: a device round"). |

### project_intertwining_device_bugs.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Image-at-sentence-end reflow — DEVICE ROUND OWED (no iPhone attached) | 3 | DONE-SINCE | `roadmap.yaml` `NFeat` 2026-07-16 shipped entry documents the reflow fix landing with Mac hostPNG verification, and the memory note's own description header already says "ALL headline bugs FIXED + deployed (Mac latest, phone build 79)" — the device round completed within the same note's later text. |
| Parked: significance-0 auto-prune-after-30-days idea | 60 | FOLDED | Superseded by the fading-lifecycle model instead (`roadmap.yaml` `LifeClock`, done): fading/purge now runs off `keptAt`/`trashSeenAt`, not a significance-0 rule — a different, shipped mechanism answers the same underlying want. |

### project_ipad_wave1.md

This note is a long multi-round session log (2026-07-23 → 2026-07-26+); nearly every "owed" line
inside it is superseded by a *later* line in the same note (each round fixes the prior round's
device findings). The items below are the ones still genuinely open against the live roadmap.

| item | doc line | verdict | id / why |
|---|---|---|---|
| Tuur's Mac eyeball (incl. the snapshot-blind ⋯ chip), polish+prompt-sync live test, the undiagnosed "could not process", the "Mark all as Passing" wording question, then promote to main | 31, 38 | FOLDED | `roadmap.yaml` `IPadWave1` status `inprogress` — its own `note:` field carries this exact line verbatim as the current "Owed:" ("Owed: Tuur's Mac eyeball (incl. the snapshot-blind ⋯ chip), polish + prompt-sync live test... then promote to main"). Not lost — it is the live ledger's own wording. |
| Header polish round — TUUR's landscape confirm of the reclaim (121), TUUR'S OWN eyeball of 120, phone install of 120, "could not process" undiagnosed | 105, 111 | FOLDED | Superseded within the note by later rounds (127→132), then folded into the same `IPadWave1` current-owed line above. |
| Bookmark + ePub sync — owed round-trip witness | 119 | DONE-SINCE | Same note, four lines later: "✅ bookmark + ePub sync CONFIRMED WORKING on device 2026-07-24... the owed round-trip witness is done." |
| Note-view redesign / Connections-as-inspector — device eyeball owed (132) | 175, 182 | DONE-SINCE | Note's own later text: "BUILT + installed (132, 3c871ed...) and Tuur-CONFIRMED on device 2026-07-24 ('this looks soo good')." |
| Tuur's Mac eyeball owed (chrome mirrored to Mac note view) | 196 | FOLDED | Same current `IPadWave1` owed line as above (Mac eyeball is still the node's open item as of the roadmap's latest entry, 2026-07-26). |
| Owed: Tuur's live eyeball — the spring, whether the re-wrap looks janky | 220 | FOLDED | Superseded by later rounds in the same note culminating in the same still-open `IPadWave1` Mac-eyeball line. |
| Owed: Tuur's live eyeball (unrated note → rate it → watch the hand-over) | 287 | DONE-SINCE | Note's own 2026-07-26 round-6 entry (roadmap `IPadWave1` shipped log): "Tuur's eyeball on round 5 — anatomy confirmed live, two fixes out of it." |
| SharedExport real-vault round owed | 318 | OPEN | `roadmap.yaml` `SharedExport` status `inprogress`, its own note: "INPROGRESS not done: Tuur's first real-device run owed (throwaway folder first)" — still open in the live ledger. |
| Tuur's first real-device run (THROWAWAY folder first); `includeAudioInExport` sync parked | 333–334 | OPEN / FOLDED | Same `SharedExport` node for the device-run half (still open); `includeAudioInExport` sync itself is not named in SPEC.md/roadmap as scheduled — OPEN, no tracked clause. |
| OWED: two-device round-trip (his gate — sync contract) | 408 | DONE-SINCE | Two-device sync round-trips are load-bearing for every later shipped roadmap entry (NFeat, DParityB, W9, ExportDestinations) — could not be broken and have those land. |
| Tightness lens — DEFERRED by Tuur to "once we connect my Obsidian vault" | 428 | FOLDED | SPEC.md Parked ideas: "tightness lens" — named, not scheduled. |

### project_lifecycle_one_clock.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Phone-open eyeball owed + schema-downgrade gotcha | 3 | DONE-SINCE | Note's own later text: "Phone-open eyeball DONE on device 2026-07-23: first open under build 106 fired `FadingSweep: purge clock started for 53 synced-in trashed note(s)`" — resolved within the same note. |
| Owed: Dev-deploy + eyeball both apps (rides the walkthrough tail) | 21 | DONE-SINCE | Same note, "Eyeball waves 2026-07-22 (live round): Mac confirmed on sight" and the v3 section's "Verified: mobile 868/0 + desktop 490/0... Mac Dev live." |
| Only the LifeIA walkthrough tail now remains | 25 | FOLDED | `roadmap.yaml` `LifeIA` ("Lifecycle IA — one spine"), status `inprogress` — the remaining tail is that node's live scope, not lost. |

### project_audio_session_round.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Audiobook half — device round DEFERRED by Tuur 2026-07-26 ("only encountered it once"); NOT owed, don't re-chase | 23, 28 | DROPPED | Explicitly not owed per the note's own words, matching `roadmap.yaml` `RecHard`'s backlog line verbatim: "Audiobook round (b121) — device test DEFERRED by Tuur 2026-07-26 (seen once; trusting the fix, will report a recurrence). Not owed." |
| Merge: `claude/ipad-app-version-3f9a3a` still on old main, needs rebase before landing | 30 | DONE-SINCE | Superseded — that branch's work is the `IPadWave1` node, which has landed dozens of commits on `main` since (per its shipped log), so any stale-base issue is long resolved. |

### project_mac_recording.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Owed: one live BUTTON run (record → talk → stop → words arrive, note lands quiet) → W7 done | 60 | DONE-SINCE | `roadmap.yaml` `W7` ("The Mac records too"), status `done` — the node cannot be `done` without its own stated win condition (this button run) being met. |

### project_model_upgrade.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Still TODO: Inspector error messages for model failures ("check Settings → Enhancement" instead of generic "Connection failed") | 25 | OPEN | Not in SPEC.md/BUGS.md/roadmap.yaml under this description. |

### project_native_convergence.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Deferred until the desktop app stabilizes | 3 | DONE-SINCE | Convergence happened (`H_conv`, done, 2026-06-07→2026-06-09). |
| NOT pushed — origin/main ~203 behind; push is owed | 65 | DONE-SINCE | `main` has been the trunk with continuous pushes since 2026-06-14 per CLAUDE.md's Branch section. |

### project_connections_panel.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Dropped voice enrollment; Mac allowed never-linking no-alias people — noted as a gap | 37 | OPEN | Not a tracked clause in SPEC.md/BUGS.md/roadmap under this description. |
| Owed: phone device round (upgraded gate % / PREPARING / N-of-M), Tuur's Dev eyeball round | 42 | DONE-SINCE | `roadmap.yaml` `NFeat` 2026-07-16 shipped entry: "shared RetrievalGate upgrades the PHONE gate too (%, preparing, N-of-M)... Live Dev round running; phone device round owed" — superseded by the extensive later Connections work across `IPadWave1`/`NFeat`/`SharedExport`, all of which build on a working gate. |

### project_note_consent.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Tuur's live re-run owed | 3 | DONE-SINCE | `roadmap.yaml` `W9` ("ONE rated/unrated rule — NoteConsent"), status `done`, done 2026-07-28, shipped log: "Tuur's live re-run same evening ('very sexy, very hot')." |
| OWED: phone build ride-along (canSummon not yet on his device) | 48 | FOLDED | Same `W9` node's own `note:` field carries this exact line verbatim: "OWED: phone build ride-along (canSummon not on device yet)" — still the live ledger's own open item, word for word. |
| Dictate-at-caret (i17 near half) PARKED by Tuur ("similar to Scribble… maybe we don't [need it]") | 49 | FOLDED | Consistent with SPEC.md Parked ideas' "dictate-anywhere" line — same shape of idea, parked. |
| OWED: Tuur's typed-note + paragraph [feel round] | 64 | FOLDED | `roadmap.yaml` `W8` ("The Mac writes with you — live transcription"), status `inprogress`, backlog: "resting-note paragraph eyeball" still listed as owed before done — same item, live. |

### project_note_lifecycle.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Band-Process writes 0.1 through CloudKit — zombie = "Parked" | 29 | DONE-SINCE | Superseded by the one-clock lifecycle model (`LifeClock`, done) which retired the "Parked" state entirely (project_lifecycle_one_clock.md: "'Parked — edited' ceases to exist"). |
| OWED: Dev band eyeball | 38 | FOLDED | `roadmap.yaml` `LifeIA` status `inprogress` — this eyeball is part of that node's still-open scope. |
| PARKED: `mocks/review-note-detail.html` (read-only detail + Process-on-this-Mac) | 56 | OPEN | Not picked up by any later node; the note-detail view has since been rebuilt multiple times (`NoteCardM2`, `IPadWave1` chrome), so this specific mock is stale — would need re-mocking, not a resume point. |
| Also parked: the tightness lens | 58 | FOLDED | Same SPEC.md Parked-ideas "tightness lens" line as above. |

### project_overhaul.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| North star (deferred): "see how a thought evolved over time" — semantic search across the vault + timeline | 16 | DONE-SINCE | Same `roadmap.yaml` `P8` (done, 2026-07-07) as the DESKTOP_NATIVE_HANDOFF.md north-star row above. |
| Watched-folder ingest deferred | 28, 33 | FOLDED | SPEC.md Parked ideas: "watched-folder ingest" — named, not scheduled. |
| Deferred: evolve-over-time timeline; summary-prompt quality pass; LLM narration of evolution | 33 | DONE-MIXED | Timeline → DONE-SINCE (`P8`). Summary-prompt quality → DROPPED, D82: "prompts frozen in v2, no sensor context." LLM narration of evolution → DROPPED, SPEC.md Not doing: "no LLM narration of 'how my thinking evolved' yet." |

### project_port_electron_notes.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Data-migration chore, deferred until feature-complete enough to trust | 28 | FOLDED | SPEC.md Parked ideas: "re-ingest of the Electron-era notes" — same item cited three times now across handoffs and memory. |

### project_v2_core_rewrite.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| OWED: iPad [full suite pass mentioned near the commit line] | 37 | OPEN | `roadmap.yaml` `V2Core` status `now` (the current focus) — the rewrite is mid-flight; this specific iPad pass is not yet a closed item in the live ledger, consistent with OPEN. |
| Owed by him: five Dutch [decisions / D90 Books tab "feels bolted on"] | 76 | OPEN | D90 (SPEC.md) is explicitly marked "Open" — matches directly: "The Books tab... Mock first. Open." |

### project_live_transcription.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Description: edit live-check owed | 3 | FOLDED | `roadmap.yaml` `W8`, status `inprogress`, note ends "OWED: the live eyeball (blocked on the wedged host CoreAudio — BT toggle) + the clean phone-suite re-run (same blocker)." |
| `XCTSkipIf` guard PARKED for Tuur's call | 57 | OPEN | Not decided in SPEC.md; D85 retires the XCUITest suite generally, but this is a unit-test skip guard, a different question, still unresolved. |
| OPEN: edited takes need a timings-only file pass first — parked | 86 | FOLDED | `roadmap.yaml` `W8` backlog: "karaoke-after-edit decision (parked)" — same item. |
| OWED (next session): mid-take edit check, resting-note paragraph eyeball, after-edit parked decision, i17 cursor-follow (DESIGN) | 130, 133 | FOLDED | Same `W8` node backlog verbatim: "Still owed before done: the mid-take edit LIVE check (chip + survival), resting-note paragraph eyeball, karaoke-after-edit decision (parked), clean phone re-run before prod." |

### project_unification_backlog.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Capture items: device verify owed | 32 | DONE-SINCE | CLAUDE.md: "Capture items — ✅ BUILT 2026-06-12 (...awaiting device verify)" superseded by the feature being in continuous use across every later capture-related roadmap node (`ShareW1`, `ShareW2`, `CapNote`, all done/inprogress on top of it). |
| Significance-wall design session DEFERRED | 38 | DONE-SINCE | Superseded by the shipped `NoteConsent`/rating model (`W9`, done) which answers the same underlying question (what a significance value gates) definitively. |
| Owed: user device-confirms the 3 Liquid-Glass/slider/karaoke behaviours | 88 | DONE-SINCE | Superseded within MOBILE_NATIVE_HANDOFF.md itself and by years of later device-verified UI work on the same views. |
| Remaining/deferred: capture items, conversation mode, re-ingest 30 old notes (all user-driven) | 94 | DONE-MIXED | Capture items → DONE-SINCE (above). Conversation mode → DONE-SINCE (`H_conv`). Re-ingest old notes → FOLDED (SPEC.md Parked ideas). |
| "Transcription weird on cold auto-start" — PARKED, user unsure it's a real bug | 115 | OPEN | Same item as the NEXT_CHAT_HANDOFF.md row above; not in SPEC.md/BUGS.md/roadmap. |

### project_standalone_app_store.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Watch support deferred/fast-follow (user has no Watch) | 49 | FOLDED | `roadmap.yaml` node `P10` ("Apple Watch capture"), status `deferred`, note: "Fast-follow — own target + review. (User has no Watch.)" — direct match. |
| Still open: folders model | 49 | FOLDED | SPEC.md Parked ideas: "folders model" — named, not scheduled. |
| Shared code unification (Compiler/TagMatcher/contract DTOs into Shared/) deferred from Phase 0 | 60 | DONE-SINCE | `roadmap.yaml` `SharedKit` node status `done`; `DParityB`'s Board C0b–C7 entries (2026-07-15) show exactly this kind of Compiler/TagMatcher/contract-DTO consolidation landing. |
| Deferred: #8 rate-only changes don't sync (LWW on `lastPlayedAt`; position DOES sync) | 124 | OPEN | Not found as a distinct tracked item in SPEC.md/BUGS.md/roadmap; would need re-verification against the current audiobook sync model before it could be scheduled. |
| DEVICE-VERIFY OWED: real iCloud opt-in on iPhone → watch % → downloads on iPad with % | 132 | DONE-SINCE | Superseded by the extensive, later device-verified iPad/audiobook work (`IPadWave1`, `EPubAlign`, `BookShare`, all with live device rounds on exactly this path). |
| Device-verify owed (cover + reordering "recently played") | 158 | DONE-SINCE | Same reasoning — superseded by later audiobook-library device rounds. |
| 3–7 owe a device eyeball (real book + transcript); owed fast-follows: light/sepia reading themes | 187 | DONE-MIXED | The device-eyeball half → DONE-SINCE (superseded by `EPubAlign`'s later device-confirmed rounds on real books). Light/sepia reading themes → OPEN, not found in SPEC.md/BUGS.md/roadmap. |
| (d) 10 pre-existing iOS-26 UI-test fixes; (e) DEFERRED cellular "Ready to sync" tap-to-pull | 222 | DONE-MIXED | The UI-test fixes → SUPERSEDED, D85: "Retire the XCUITest suite... the unit suite is the gate" — the tests this item wanted fixed are being retired, not fixed. Cellular tap-to-pull → OPEN, not tracked. |
| Also still owed independently: the Phase-4a model spike on the real iPhone 13 | 241 | OPEN | Not found as a distinct tracked item; on-device Polish is `roadmap.yaml` node `P4`, status `planned`, whose own backlog already restates the same spike as its first step ("Spike on the iPhone 13 FIRST — hard memory gate") — so the spike itself has not yet run per the live ledger. |
| Mac + CloudKit deferred decision (Mac uses PipelineFile ≠ phone's Memo) | 247 | DONE-SINCE | Resolved by MAC_CLOUDKIT_PLAN.md's shipped Fork-A bridge (`MemoCloudIngest`/`MacCloudWriteBack`), which is exactly the decision this line deferred. |

### project_mobile_overhaul.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Pivot note itself (2026-06-05, RN → native rewrite) — historical framing, not an action item | 10 | DONE-SINCE | The native rewrite is the current app; superseded by everything since. |

### project_note_editing_sprint.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Follow-up work DEFERRED by the user 2026-07-07 → parked brief | 13 | FOLDED | Same `roadmap.yaml` `CapNote` node as project_capture_as_note_kickoff.md above (the parked brief IS that kickoff note). |

### project_p0_enhancement_clobber.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Real bugs found: search-flow opens render raw + embedder ~2-min cold-start stall | 32 | DONE-SINCE | `roadmap.yaml` `P8` 2026-07-10 shipped entry: "'Single-word search finds nothing' CLOSED — devlog proved a cold-load stall... DEVICE-VERIFIED build 59." Same stall, closed. |

### project_vocab_booster.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Device re-test owed (no phone "Skrift" audio this session) | 41 | DONE-SINCE | CLAUDE.md pinned line: "Custom vocab fixed both apps — pre-warm booster + aliases + trust guard, device-confirmed 2026-06-13" ([[project_vocab_booster]]) — the same note's own topic, confirmed. |

### project_testflight.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| `state=INVITED`, no email arrived, app never showed in TestFlight — re-inviting via [workaround] | 33 | DONE-SINCE | Note's own later ⭐⭐⭐ finding: "ROOT CAUSE: 29 builds across 5 apps force-expired in a 3-SECOND WINDOW on 2026-08-26 — account-wide" — this specific invite failure is folded into that broader, since-diagnosed Apple-side incident, not an unresolved local bug. |
| Read-only GETs allowed by the [ASC API scope]; GET_RELATED not allowed | 98, 112 | OPEN | A documented API-scope limitation, not a task; still true of the credentials in use, no clause proposes changing it. |

### project_xcuitest_ios26_failures.md

| item | doc line | verdict | id / why |
|---|---|---|---|
| Fix 10 pre-existing SkriftMobileUITests iOS-26 failures — deferred, pin it | 3, 11 | DROPPED | D85 (SPEC.md), decided 2026-09-22: "Retire the XCUITest suite. ✅ DECIDED: retire; the unit suite is the gate." The suite this item wants fixed is being removed, not fixed. |

---

## OPEN items across all docs

Counts (items with verdict OPEN, or the OPEN half of a DONE-MIXED row):

- CONVERSATION_MODE_HANDOFF.md — 1
- DESKTOP_NATIVE_HANDOFF.md — 2
- DESKTOP_NATIVE_REWRITE_PLAN.md — 0
- HANDOFF-2026-07-25-audio-session.md — 1
- LIVE_SYNC_HANDOFF.md — 0
- MAC_CLOUDKIT_PLAN.md — 0
- MOBILE_NATIVE_HANDOFF.md — 5
- MOBILE_NATIVE_REWRITE_PLAN.md — 0
- NEXT_CHAT_HANDOFF.md — 5
- OBSIDIAN_EXPORT_ALTERNATIVES.md — 1 (vault-read direction, parked not decided)
- TEXT_CAPTURE_WAVE2_HANDOFF.md — 0
- WALKTHROUGH_BUGS.md — 2
- memory notes (all files combined) — 20

Total OPEN across every doc: 37.

The five I judge most important:

1. **Auto-enqueue trusted mobile uploads on the Mac** (MOBILE_NATIVE_HANDOFF.md) — still undecided
   whether a rated-and-synced memo should process itself; affects every "why hasn't this note
   processed" report.
2. **Source-taxonomy unification** (NEXT_CHAT_HANDOFF.md, restated live in CLAUDE.md) — glyphs/labels
   for voice/URL/PDF/video/quote/note still drift; no clause closes it even though CLAUDE.md still
   flags it open.
3. **Real recording data loss / cold-start / append-silently-adds-no-text class of bugs** (several
   memory OPEN rows point at the same family BUGS.md §4 already tracks unverified, e.g. append
   silently adding no text) — worth a source-ledger-style sweep of its own before v2 ships transcription.
4. **The Phase-4a on-device Polish memory spike on a real iPhone 13** (project_standalone_app_store.md)
   — `roadmap.yaml` P4 still lists this exact spike as its unstarted first step; it gates whether
   on-device Polish ships at all.
5. **Desktop Models/Storage view + in-app feedback→inbox** (NEXT_CHAT_HANDOFF.md) — two small, long-
   dormant Settings-surface gaps nobody has picked up or explicitly killed.
