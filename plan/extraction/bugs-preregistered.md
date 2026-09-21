# Known bugs — pre-registered as REQUIRED differences for the v2 diff gate (2026-09-21)

Each bullet: **what v1 does today** → **the correct output** · src · status. `verified-open` = re-opened against source in `BUGS.md` §1–3 (2026-09-14). `lead` = from the ledger, not re-verified. A v2 that matches v1 on a `verified-open` item FAILS the gate.

## Body / image model

- **Shared picture lands after the first word.** v1: a picture with no timestamp gets `offsetSeconds: 0` (`CaptureInboxDrainer.swift:261/450`, `MemoSaver.swift:373`) → `[[img_NNN]]` after the FIRST WORD, splitting the opening sentence. Correct: the picture is its own paragraph, placed where the spec says (TOP of the note per the 2026-09-18 note — needs Tuur's confirmation, see ledgers C1); the first sentence stays whole · src: backlog.md:681–683 · verified-open (code-read 2026-09-18)
- **Timed picture splits its sentence in the raw body.** v1: capture drops `\n\n[[img_NNN]]\n\n` at the end of the word nearest the photo's time, mid-sentence; display/export snap it at render time via three stacked offset remaps. Correct: the stored body already has the picture as its own paragraph after the sentence that was being spoken; every renderer and the exporter show the same thing without a snap layer · src: backlog.md:679, 686–702 · verified-open
- **Mixed WhatsApp share (8 voice notes + 1 picture): the picture marker lands in the wrong spot.** v1: the drain's marker placement puts `[[img_NNN]]` somewhere inside the merged transcript. Correct: the picture ends up as its own paragraph at the position the spec assigns a timeless shared picture (see C1), never inside a clip's sentence · src: backlog.md:897, 637 · lead (Tuur report 2026-08-18)
- **Pictures "wrap" badly / collapse paragraphs after polish.** v1 (partly fixed 2026-08-20): `extractAnchors` used to flatten all whitespace before feeding the model; the horizontal-only fix shipped, but Tuur says "wrapping pics is hard apparently" is still an issue. Correct: paragraph count never drops across copy-edit unless the shrink guard fired; a picture never changes the author's paragraphing · src: backlog.md:674–676, 719–729 · lead
- **Same-titled notes overwrite each other's images on export.** v1: `convertImageMarkers` names images `<safe-title>_NNN.ext`. Correct: images are named by the note STEM (already uniquified for the `.md`), so two "Untitled" notes keep separate files · src: BUGS.md:74, backlog.md:5576 · verified-open
- **Stale `ambiguousNames` offsets after any body migration.** v1: offsets are stored against the raw (unsnapped) body. Correct: after normalising old notes to picture-paragraphs, re-sanitise once so suggested-name spans land on the right characters · src: backlog.md:701 · lead
- **A conversation turn split by an inline photo leaks out of the gutter column.** v1: the Mac turn renderer treats the photo paragraph as a turn break. Correct: the turn continues after the photo block, same speaker column · src: backlog.md:2076 · lead (found + fixed for one case 2026-07-27; re-check under v2)

## Copy-edit (Mac polish)

- **Near-echo on real Dutch/mixed text.** v1: Gemma at temp 0 returns 7790→7780 chars, 7→4 newlines on Tuur's real note — nothing edited, no paragraphs. Correct (mechanical half): the deterministic paragrapher guarantees paragraphs when the model returns <2 breaks; (verdict half): whether v2 must edit Dutch prose at all · src: backlog.md:1048–1055, 918–928 · lead (needs-verdict on the model half)
- **Unbounded shrink.** v1 (guarded since 2026-08-19): a circling ramble could come back at 7% of its words. Correct: output <~55% of input words → keep raw + log; a stored copy-edit is never a silent half note · src: backlog.md:911, 1041 · lead (guard shipped, threshold untuned)
- **`ensureParagraphs` only fires below 2 newlines.** v1: a 7k-char output with 2–3 stray breaks passes as "paragraphed". Correct: paragraphing is judged per block, not by a global newline count (or the rule is stated and accepted) · src: backlog.md:730 · lead
- **Prod prompt override shadows the shipped default.** v1: `user_settings.json` carries a 764-char old copy-edit prompt that wins over `PolishPrompts`. Correct: v2 reads ONE prompt source; a stale override is migrated or surfaced · src: backlog.md:941 · lead
- **Slab-note redo outcome unreported.** v1: Tuur's important note was re-polished after the wave; nobody read the paragraph ledger. Correct: the corpus replay of that note shows `in N → model N → shipped N` with N ≥ the author's paragraph count · src: backlog.md:754–765 · lead
- **Re-transcribe destroys a transcript when the audio has moved (D2).** v1: `retranscribe` nils transcript + derivatives BEFORE `process()` learns the audio is gone; `BatchRunner` marks the row done-and-empty with no error. Correct: nothing is cleared until ASR returns; a missing file is an error on the row, the old transcript survives · src: BUGS.md:33, AUDIT_PLAN.md:79 · verified-open
- **Edits during a polish run.** v1 (fixed 2026-07-19, unverified on device): a body edit during the LLM window was overwritten. Correct: the stale run is discarded, status returns to pending, the edit survives · src: AUDIT_FIX_TESTLIST.md:38, backlog.md:4828 · lead

## Reconcile sweep (Mac ingest + write-back)

- **`names.json` can be lost across every device (D1).** v1: non-atomic write, `load()` returns an empty roster on decode failure, unguarded read-modify-write off-main; LWW then propagates the loss. Correct: atomic writes behind an actor; a torn read never produces an empty roster; a merge never shrinks the roster · src: BUGS.md:27, AUDIT_PLAN.md:55 · verified-open
- **`NamesMerge` millisecond tie always favours remote; `MacCloudWriteBack` LWW has no skew tolerance.** Correct: a tie keeps local (or is deterministic by device id); write-back LWW tolerates clock skew · src: BUGS.md:117 · lead
- **Bonjour-shaped ingest.** v1: `MemoCloudIngest` re-encodes the typed `Memo` into fake multipart parts and `UploadService` string-parses `[String: Any]`. Correct: Memo + assets → PipelineFile typed; byte-equal PipelineFile on the golden corpus · src: backlog.md:6138 · lead
- **Mac twin of the blob-faulting sweep.** v1: `adoptLateDiarization`'s guard never turns false for a monologue, so `fetchAssets()` faults every blob per memo per sweep on every window activation. Correct: the already-ingested branch reads metadata only; unchanged rows are skipped · src: AUDIT_PLAN.md:243 · lead
- **Mac sync only lands on app restart / window click.** v1: the live CloudKit-import trigger appears not to fire on the Mac. Correct: a phone edit reflects on the Mac within the CloudKit latency without a relaunch · src: backlog.md:2172, 3267 · lead
- **Diarization late-asset heal never exercised.** v1: the heal exists but the only conversation memos are unrated. Correct: rating a conversation whose `diar` asset trailed its record yields turns + enrolment on the next sweep · src: backlog.md:2127 · lead
- **Vault scan with no cap in the sweep.** v1: `VaultStamp` enumerates every `.md` and opens each, uncapped, on main, once per updated row. Correct: capped/indexed lookup off main · src: AUDIT_PLAN.md:247 · lead
- **A memo trashed on the phone was never trashed on the Mac (pre-2026-07-15).** Fixed by delete sync; regression guard: trash on phone → row trashed on Mac; restore either way mirrors · src: backlog.md:5588 · lead (round-trip owed)
- **Reminder alarm on the Mac missing.** v1: `remindAt` mirrors + shows 🔔 but no Mac reconciler schedules it. Correct: the Mac schedules the same `UserNotifications` request from the synced field · src: backlog.md:6120, 5617 · lead

## Export compiler

- **Vault export deletes a file it doesn't own (D3).** v1: `VaultExporter.swift:269-270` and `:293-294` `removeItem` then copy under the ORIGINAL filename (`IMG_0001.jpg` clobbers the vault's). Correct: attachment lanes go through the stamp/ownership rule; a destination the ledger doesn't claim is never overwritten · src: BUGS.md:40, AUDIT_PLAN.md:97 · verified-open
- **Frontmatter migration is per-note.** v1: old exports keep the old key order until re-exported by hand. Correct (or accepted): a stated rule — v2 never silently rewrites, but a bulk verb exists or the gap is documented · src: backlog.md:1102 · lead
- **`includeAudioInExport` not synced.** v1: Mac-only field; the iPad can't honour or show it. Correct: the field syncs, both exporters read it · src: backlog.md:3462 · lead
- **Duration chip missing on synced notes (pre-2026-07-26).** v1 wrote `duration` as a Double while `PipelineFile.durationSeconds` parsed HMS. Regression guard: a synced note shows its duration and docks a player on the Mac · src: backlog.md:2613, 2987 · lead (fixed; keep as invariant)
- **Mac Dev vault path moved on its own.** v1: Dev's vault setting pointed at the REAL iCloud vault at 16:09, the test vault later — one observation. Correct: the Dev build can never resolve to the real vault; the setting is stable · src: backlog.md:1106 · lead (data-safety)
- **Archive-side unknowns.** Does the site render person pages (else `[[Jack]]` dangles); does it accept video; is `_inspiration` still right · src: backlog.md:2875 · lead (questions, not bugs)

## Ingress — per-source share jank

- **Multi-ITEM WhatsApp bundle drops everything but the first item.** v1: `SharePayloadLoader.load` reads `inputItems.first`; a voice-notes + photo + link + video selection yields only a video note. Correct: attachments are flattened across ALL extension items; one note carries every clip in chat order, the photo(s), the link; the sheet SAYS what it keeps · src: backlog.md:5215–5226 · lead (devlog-proven 2026-07-12)
- **Mixed-share picture placement** — see Body section; the WhatsApp picture is the reported instance · src: backlog.md:897 · lead
- **JS-rendered pages get a bare-domain title / no article text.** v1: enrichment is one GET + `HTMLMeta`; YouTube/Instagram/SPA pages return no og/title. Correct: the note SHOULD be per Tuur's per-source verdict (YouTube = link card w/ real title vs fetch+transcribe; Instagram = caption as body) — pre-register once decided · src: backlog.md:626–636, SHARE_INGEST_SURVEY.md:47, 77–78 · lead (needs-verdict)
- **Google-Maps `goo.gl` short links stay plain link cards.** v1: opaque without a fetch, BY DESIGN. Correct (as designed): still a link card — pre-register as identical, not a difference · src: backlog.md:5172, 4317 · lead
- **GIF flattened, PNG lossy re-encoded on image share.** v1: re-encode to JPEG 0.85 after downsample. Correct: PNG stays PNG; GIF keeps first frame honestly or stays animated · src: SHARE_INGEST_SURVEY.md:50 · lead
- **Video/file share: `.file` capture has no pinned block on the Mac; Mac never shows the PDF first page.** Correct: the Mac card renders the first page from the synced `.document` asset · src: backlog.md:5457, 8244 · lead
- **Old PDF captures (pre-build-76) never sync their document to the Mac.** Correct: re-test with a fresh share; legacy captures stay text-only by design · src: backlog.md:5680 · lead
- **Mac-local ingests never get OCR'd; an OCR-only search hit can't flash in the body.** Correct: the Mac runs the same `PhotoTextIndexer` on local imports; an OCR hit scrolls to the `[[img_N]]` attachment · src: backlog.md:5927 · lead
- **Shared audio ≥1 h → Books chooser UI unverified** (routing device-proven, chooser never seen) · src: backlog.md:5176, 5211 · lead
- **Apple Notes export (`.md` + `Attachments/`) has no corpus fixture yet** — the Mac folder-drop path handles it; behaviour per attachment kind unrecorded · src: backlog.md:629 · lead
- **Silent video (no audio track) → a `.failed` memo titled "Video had no audio track".** v1 = correct-by-design; pre-register as identical · src: backlog.md:8629 · lead
- **Duplicated author in an imported book's title** ("In Praise of Shadows - Junichiro Tanizaki" + author line). Correct: the importer splits `Title - Author` filenames, or the title never carries the author · src: backlog.md:462 · lead
- **Rejected/empty alignment sidecar packed into a shared `.skriftbook`.** Correct: `derivedSidecars` skips a sidecar with verdict `rejected`/empty sources · src: backlog.md:454 · lead

## Names & sanitise

- **A person added on the phone can never be linked.** v1: `NamesListView.swift:202` saves `aliases: []`; the Sanitiser matches only by aliases. Correct: `aliases = [canonical]` seeded on add (as `PersonEditorView` does) + a one-time backfill for alias-less people ("IJsbrand") · src: BUGS.md:50, backlog.md:6220 · verified-open
- **Adding a person doesn't relink existing notes.** v1: only the OPEN note is re-scanned (`resanitiseForNames`). Correct: per Tuur's verdict — either the documented open-note-only rule, or a global re-derive on add · src: backlog.md:7261, 7283 · lead (needs-verdict)
- **Roster collision re-scan doesn't touch exported `.md`.** v1: `rescanRoster` re-derives in-app only. Correct: affected exported notes re-export (or the gap is stated) · src: backlog.md:7395 · lead
- **Mid-body `> ` blockquote gets name-linked.** v1: only a LEADING quote span is non-prose. Correct: names inside any quoted passage are never "about" the person · src: backlog.md:7392 · lead
- **"Every note is a conversation" — stale `**Name:**` turn markers baked into stored transcripts** (Stz020 #5). Correct: a monologue never carries turn markers; a bulk un-diarize path exists · src: backlog.md:5247, 6231 · lead
- **Phone `SpeakerTranscript.parse` not pipe-aware** (a Mac `[[Canonical|spoken]]` header doesn't round-trip); speaker name containing `*` breaks the Mac header regex · src: backlog.md:7214 · lead
- **Can't select a word in the phone transcript and "add as name".** Correct: selection → "Add as new person / alias of…" (Mac has it) · src: backlog.md:6227 · lead
- **`Sanitiser.wordRegex` recompiled per alias per call; O(people × aliases) whole-word regex + `nonProseRanges` per person.** Correct: one alternation pass, `nonProseRanges` computed once · src: backlog.md:7409, 4833 · lead

## Consent / rating / lifecycle

- **The rating line is stateless** ("Rated — ready to process" on a processed note). Correct: the line reflects `NoteWorkState` · src: backlog.md:1100 · lead
- **`purgeExpiredTrash` runs synchronously in `App.init` before the first frame.** v1 = deliberate (trash-only fetch); pre-register as identical unless v2 changes ordering · src: AUDIT_FIX_TESTLIST.md:64 · lead
- **Conversation-turn edits + C3 annotation edits don't bump `editedAt`.** Correct: every content edit bumps it (or the exception is stated) · src: backlog.md:8656 · lead
- **Two rows still carry a literal `"[]"` tag** (input now guarded). Correct: cleanup pass or accepted · src: backlog.md:2121 · lead
- **`Memo.significance` 10 stops are fake precision** (only `0`, `≥0.8`, and sort read it). Not a bug; pre-register that a 3/4-button control writes 0.3/0.6/1.0 (or 0.7) into the SAME Double contract once decided · src: backlog.md:98–119 · lead (needs-verdict)

## Sync contract

- **Offline conflict = per-record LWW; a same-note edit on two devices silently loses one side.** Correct: accepted and stated, or a conflicted-copy/field-merge rule · src: backlog.md:6850 · lead (needs-verdict)
- **Unshare leaves a phantom audiobook entry on a device that never downloaded the audio.** Correct: an entry with no carrier AND no local audio is removed · src: backlog.md:6853 · lead
- **Rate-only audiobook changes** (fixed via `modifiedAt` 2026-06-19) — regression guard: a speed-only change syncs without reordering "recently played" · src: backlog.md:6857 · lead
- **iPad polish + Release entitlements.** `com.skrift.mobile` (Release) still owes the one-time Xcode capability visits (`increased-memory-limit`, App Groups) · src: backlog.md:3171, 8172 · lead (promotion checklist, not v2)

## Recording & audio

- **A whole recording is lost if the app dies mid-recording (D4).** v1: audio goes to one `AVAudioFile` at `rec_tmp_<uuid>.m4a`, becomes a memo only in `stop()`; `rec_tmp` appears once in the repo; a killed take leaves an unfinalised MP4 (no `moov`) that nothing sweeps; the user is never told. Correct: segments roll on interruption/background and every 60 s; a sidecar marker + launch sweep rebuild the memo from segments and SAY so; a swipe-kill finalises via `willTerminate` · src: BUGS.md:18, backlog.md:476–590 · verified-open (Tuur, prod, 2026-08-22; issue #14)
- **Append can silently add no text** (3× repro on build ~30; broader than cold-model). Correct: an append never lands empty — `.transcribing` shown, retry, terminal failure = Error pill · src: BUGS.md:108, backlog.md:7665, 6429 · lead
- **Tail of a recording cut off after Stop** (both dev + prod, intermittent). v1: one path fixed (`audioFile.close()` before the read). Correct: file duration ≈ wall-clock capture on every stop path · src: BUGS.md:110, backlog.md:7672 · lead
- **`MacRecorder.stop` finalises by dropping a reference with no queue drain** (the phone's cut-off-tail bug, never ported). Correct: `writerQueue.sync {}` + explicit `close()` · src: AUDIT_PLAN.md:268 · lead
- **`isTranscribing` is a Bool on a re-entrant actor** — two overlapping transcribes (book chunk + memo) can `cleanup()` the manager the other is decoding on. Correct: a depth counter · src: AUDIT_PLAN.md:263 · lead
- **Live-caption buffers go through one unstructured `Task` per buffer** into an order-critical consumer; on the Mac settled text becomes the saved transcript. Correct: one ordered `AsyncStream` consumer · src: AUDIT_PLAN.md:272, backlog.md:4795 · lead
- **`GemmaEmbedder.downloadProgress` nil'd from main while callbacks land off-thread** · src: AUDIT_PLAN.md:276 · lead
- **Cold-start: waveform moves but no words for a while** (ASR model loads on first use; live caption catches up). Correct: pre-warm on Record press, or an honest "warming up" state · src: backlog.md:1698, 7560 · lead
- **Mid-record call/alarm survival never device-tested** (the round that would have caught D4) · src: backlog.md:4950 · lead
- **Mid-take edit on the Mac live draft never human-verified** (edit a settled word → survives + "✎ edited while recording" chip) · src: backlog.md:1756, 1868 · lead
- **AirPods-mic recording for the pocket case** (b119 policy records on the built-in mic when BT is around). Not a bug; a stated limitation with a revisit item · src: backlog.md:2314 · lead

## Audiobooks

- **"Edit book details" never syncs.** v1: `Audiobook.swift:562-566` `update(_:)` never sets `modifiedAt`; a replaced cover never re-uploads (`audioUploadedAt` once-gate). Correct: any edit bumps `modifiedAt`; a new cover re-uploads · src: BUGS.md:57 · verified-open
- **Seek while paused is never persisted.** v1: `AudiobookSession.seek(to:)` never calls `persistProgress`; force-quit after a paused scrub loses the position. Correct: every seek persists · src: BUGS.md:64 · verified-open
- **Book cover placeholder colour changes every launch.** v1: palette picked by `uuidString.hashValue` (per-process seed). Correct: derived from the UUID bytes, stable across launches · src: BUGS.md:69 · verified-open
- **Starting a transcribe on book B while A's job runs may cancel A silently.** v1: the display half is fixed (`isThisBook`), the cancel half unchecked. Correct: A keeps running or the user is told · src: BUGS.md:119, backlog.md:4992 · lead
- **Quote-audio `exportSpan` drift on deep-chapter captures.** v1: production passes the precise-timing key; the measured-bad harness lane didn't. Correct: STEP 0 = a chunksim third lane WITH the flag; captured audio ↔ sidecar karaoke stay aligned · src: backlog.md:4813, 4997 · lead
- **Read-along + conversation playback redraw whole screens on a 20 Hz / 2 Hz clock.** Correct: a small position observable read only by the leaves · src: AUDIT_PLAN.md:238 · lead
- **App-killed-mid-align restarts the whole file; align dies with the app on lock when nothing plays.** Correct: per-file resume; a `BGProcessingTask` ride-along for the heal · src: backlog.md:4606 · lead
- **Sync note:** a receiver holding v1 sidecars whose source signature didn't change won't re-pull until the next signature change · src: backlog.md:4544 · lead (accepted at iPad scale)
- **A/B integrity for text-vs-audio capture testers, cross-chapter quotes, auto-transcribe-ahead** — deferred wave-2 items · src: backlog.md:8546 · lead

## Search / retrieval

- **Semantic search intermittently finds nothing** ("I'm trying" stopped surfacing the testing notes; worked earlier). v1: `SemanticSearch …` devlog lines exist; suspects = a swallowed engine-load error or short queries under `searchFloor` 0.25. Correct: a query either returns hits above floor or the UI says the engine isn't ready · src: BUGS.md:84, backlog.md:5376 · verified-open (undiagnosed)
- **First search of a session shows an empty Related for ~42 s** (ANE cold load). Correct: an honest "warming up…" row · src: backlog.md:5330 · lead
- **Mac search-jump parity gap** — search filters the sidebar but opening a result lands at the top; no scroll-to-match + flash · src: BUGS.md:113, backlog.md:5919 · lead
- **Actor-reentrancy: a query during a sweep's await can see a mid-swap memo** (self-corrects) · src: backlog.md:4845 · lead
- **`ConnectionsModel` / LINKED-FROM full-corpus body scan per note switch.** Correct: a backlink index maintained on save · src: AUDIT_PLAN.md:234, backlog.md:4831 · lead
- **ANE-compile hang has no timeout/retry affordance** · src: BUGS.md:116 · lead
- **Phone parity owed: query failure rendered as "no matches"** (Mac shows "Connections unavailable") · src: backlog.md:4841 · lead
- **Transient "lost the link" on the Mac** (once, not reproducible) · src: BUGS.md:99 · verified-open (watch)

## Editor & note UI

- **The app feels slow next to other apps at <200 notes, on PROD.** v1: `enhancedTitleByMemoID` + `searchFadingIDs` computed PER ROW (two full corpus scans, P1); `mkdir` on every path access (P2); `allAssets()` faults every audio/photo blob on every sweep (P4); nine `@MainActor` sweeps on launch/foreground/import with no watermarks; note open does the corpus twice per pager page. Correct: Time Profiler first; no per-row corpus work; metadata-only asset reads; checkpointed sweeps off main · src: BUGS.md:94, AUDIT_PLAN.md:131–192, 228–237, backlog.md:1120 · verified-open (undiagnosed; leads located)
- **Skrift Dev crashed a few times at random spots** (build 53 era; mixed usage). Never diagnosed; pull crash logs · src: BUGS.md:90 · verified-open
- **The caret/insertion point lands ~6 lines below the click** (Mac, unexplained, self-resolved once; ships with the iPad branch's `NoteDisplayView` rework) · src: backlog.md:2118 · lead
- **iOS-26 selection handles misbehave during scroll** (probes armed since build 39; never retested) · src: backlog.md:6655, 6665 · lead
- **The two `ConnectionsPanel` views are twinned and drifted** (Mac cards vs iPad bare rows) — the amber signal was fixed; chrome still wants one shared view · src: backlog.md:1197–1239 · lead
- **`0.8`-vs-`0.2` Connections counts (13 vs 4) were two different notes** — NOT a bug; re-check on one note before treating as one · src: backlog.md:1104 · lead (dismissed)
- **Phone has no create-note button** (iPad + Mac have ✎/⌘N) · src: backlog.md:1152 · lead
- **List-row previews render raw `memo.transcript` while the detail shows the polish** (pre-existing display choice) · src: backlog.md:5370 · lead (cosmetic; decide)
- **Editing feel vs Apple Notes** — open; profile the editor before a rewrite · src: backlog.md:1153 · lead
- **6 `DriftedPair` colour tokens + `SignificanceStyle` sub-2 pt drifts** — one eyeball round each · src: backlog.md:5952, 2679 · lead
- **`BodyTextView.restyle` full-doc regex per keystroke; tag typeahead re-tallies per keystroke** — fine now, scope-limit for long pastes · src: backlog.md:4830, 4832 · lead
- **10 pre-existing `SkriftMobileUITests` iOS-26 failures** (TextEditor `.value` cluster, Share probes, VoiceEnroll) — unit suite is the gate · src: AUDIT_FIX_TESTLIST.md:89, backlog.md:377 · lead
- **`AudioPlayerModelTests.testPlayClaimsTheSession…` is host-audio dependent** — wants an `XCTSkipIf(no usable output)` guard · src: backlog.md:1935 · lead

## Already fixed — do NOT re-open (pre-register as IDENTICAL, not different)

- WhatsApp voice message imports as a link — fixed (`SharePayloadLoader.swift:85-94`) · src: BUGS.md:126
- Transcribe-book sheet shows another book's progress — display half fixed (`isThisBook`) · src: BUGS.md:130
- iPad "Process" on an already-processed note — closed 2026-08-18 · src: BUGS.md:135
- List thumbnail stale after deleting photos — fixed 2026-07-18 · src: BUGS.md:136
- Audiobook MP3 import rejected — fixed twice (precise duration key; hollow parts skipped) · src: BUGS.md:137
- Rate→row hole (typed notes never got a Mac row) — fixed + promoted 2026-08-20 · src: backlog.md:948
- Picture whitespace flattening before copy-edit — fixed 2026-08-20 (horizontal runs only) · src: backlog.md:719
- Copy-edit `maxTokens: 1024` wall → dynamic budget + truncation guard · src: backlog.md:829
- Video "vanishes" after share — it relocates to its filming date; open-on-import + Recently-added sort · src: backlog.md:8614
- Word-timings CloudKit race (karaoke dead after a late asset) — healed · src: backlog.md:2151
- 2026-06-17 data-integrity finding (live store in the App Group container) — resolved 2026-06-21 · src: backlog.md:7156
- Post-0.2.0 prod findings #1 (prod schema) / #2 (Bonjour "Waiting" pill) — superseded by CloudKit-only sync + the retired pill · src: backlog.md:6208, 6216
