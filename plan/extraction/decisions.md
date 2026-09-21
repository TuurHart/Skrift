# Skrift v2 spec extraction — decisions, contracts, open verdicts

- Extracted 2026-09-21 from: `SKRIFT_SOURCE_OF_TRUTH.md` (SSOT), `STANDALONE_PLAN.md`, `CLAUDE.md`, `Skrift_Native/CAPTURE_CONTRACT.md`, `LANE_PLAYBOOK.md`, `NAMING_MODEL.md`, `README.md`, `CHANGELOG.md`, all 14 `archive/handoffs/*.md`, the 2026-09-18 backlog block (`backlog.md:599-700`, `roadmap/roadmap.yaml:695-720`), and the memory dir.
- `memory/<file>` below = `/Users/tiurihartog/.claude/projects/-Users-tiurihartog-Hackerman-Skrift/memory/<file>`.
- Later doc beats earlier doc. "reversed <date>" marks a decision a later source overturned; the bullet records the FINAL state.
- Tagging: section A = `locked` (dated, Tuur decided, he confirms it stays), B = `[mechanical]` (wire/format fact, no verdict), C = needs-verdict (open, contradicted, or "still mulling").
- Counts: A = 259 locked bullets (11 carry a "reversed <date>" note) · B = 110 mechanical · C = 71 needs-verdict.

---

## A. LOCKED DECISIONS

### Body/image model
- 2026-09-18 Rewrite the CORE of Skrift as a v2, one subsystem at a time; views, the CloudKit schema and the audio/hardware paths STAY — "months of AI patches have accreted weird bugs" — src: `backlog.md:599-605`, `roadmap/roadmap.yaml:695-720`
- 2026-09-18 Subsystem order = body/image model → copy-edit pipeline → reconcile sweep → export compiler — src: `backlog.md:658-659`
- 2026-09-18 v2 lives beside v1 in `Shared/`, never replaces until judged; size budget "v2 ≤ 40% of v1's lines or say why" — the lever against AI accretion — src: `backlog.md:644-645`
- 2026-09-18 The gate is the corpus diff but v1 is NOT the judge ("will you copy over the bugs?"): every output = identical / expected-different / unexplained; known bugs pre-registered as REQUIRED differences (matching v1 there fails); v1-independent invariants (markers in = markers out, paragraph count never drops unless the shrink guard fired, editor round-trip returns the same string, every transform idempotent, no rated memo without a row); plus Tuur reads the corpus output — src: `backlog.md:646-657`
- 2026-09-18 A shared picture (no capture time) goes to the TOP of the note — "his verdict" — src: `backlog.md:694-697`
- 2026-07-16 ONE shared idempotent rule (`BodyTransform.snapImages`) moves a picture to its sentence end for BOTH renderers and the Obsidian export; device-confirmed — src: `memory/project_intertwining_device_bugs.md:20-23`
- 2026-07-07 Photos are display BLOCKS in the editor; the raw `[[img_NNN]]` marker may stay mid-sentence in storage — src: `memory/project_note_editing_sprint.md:41-44`
- 2026-08-20 A picture must never cost the note its paragraphs: the copy-edit anchor strip collapses only horizontal whitespace runs; a paragraph ledger (`in N → model N → shipped N`) logs every copy-edit — src: `memory/project_rate_to_row.md:42-56`
- 2026-04-13 (Era 2, still the export shape) `[[img_NNN]]` in the transcript becomes `![[<file>]]` on Obsidian export; image names title-prefixed to avoid vault collisions — src: `memory/project_photo_capture.md:13-16`
- 2026-04-27 The vision pipeline (photo-caption VLM) was REMOVED; single text model — "deliberately dropped" — src: `SKRIFT_SOURCE_OF_TRUTH.md:76-77`, `archive/handoffs/DESKTOP_NATIVE_HANDOFF.md:180`

### Copy-edit (Mac polish)
- 2026-06-04 All LLM steps run on the RAW transcript; no `[[ ]]` reaches the model; name-linking is the LAST deterministic step — src: `memory/project_overhaul.md:21`, `SKRIFT_SOURCE_OF_TRUTH.md:486`
- 2026-06-04 Flow = ingest → auto-run unattended (transcribe → copy-edit → title → summary → deterministic tags) → "Ready for Review" → mandatory fast per-note review → export; NO mid-flight gates — src: `memory/project_overhaul.md:20`
- 2026-06-04 No re-enhance on edit; karaoke is a corrector aligning body words to word timings — src: `memory/project_overhaul.md:23`
- 2026-06-06 The enhancement LLM is mlx-swift Gemma IN-PROCESS on the Mac ("GO native", no Python sidecar); ship the 8-bit quant (4-bit under-removed fillers) — src: `archive/handoffs/DESKTOP_NATIVE_HANDOFF.md:232`, `memory/project_desktop_native_arch.md:12-14`
- 2026-06-06 Models download from HuggingFace on first run (no shipped deps zip) — src: `archive/handoffs/DESKTOP_NATIVE_HANDOFF.md:233`
- 2026-06-09 Copy-edit is SKIPPED for speaker-attributed (conversation) transcripts — Gemma stripped the `**Name:**` turn prefixes; title/summary/name-link still run — src: `archive/handoffs/CONVERSATION_MODE_HANDOFF.md:48-51`
- 2026-06-12 Capture items get enhance-LITE: title + tags + summary on the annotation, NO body copy-edit ("the annotation is written text, not speech") — src: `Skrift_Native/CAPTURE_CONTRACT.md:106-110`
- 2026-06-15 Polish behaviour = title + summary + copy-edit (the Mac's three ops, same prompts); NO invented "modes", NO raw/polished toggle, best-body precedence — src: `STANDALONE_PLAN.md:333-334,419-420`
- 2026-06-15 On-device polish is a GATED SPIKE: "better no model than an unreliable one"; Tier D no-polish is a fully acceptable ship state; RAW stays source of truth regardless — src: `STANDALONE_PLAN.md:36-38,133-138`
- 2026-06-15 Tier-C bundled phone model = OPT-IN, user explicitly downloads it (no auto-download) — src: `STANDALONE_PLAN.md:569-570`
- 2026-06-07 Do NOT feed sensor context (place/weather) into the LLM copy-edit — "small local model hallucinates"; keep context deterministic (frontmatter / a Context line), at most a tightly-constrained title hint — src: `archive/handoffs/DESKTOP_NATIVE_HANDOFF.md:170`
- 2026-06-26 The Mac's polish is SHOWN on the phone: the note opens to the polished version as one editable body (no toggle); ✦ title chooser (Suggested / first line / your own); summary card; "✦ Polished on your Mac" provenance — src: `CHANGELOG.md:13-23`, `SKRIFT_SOURCE_OF_TRUTH.md:197`
- 2026-07-06 A phone edit to an already-processed note → the Mac re-links + recompiles, NO LLM re-enhance ("user call") — src: `archive/handoffs/LIVE_SYNC_HANDOFF.md:17-18`
- 2026-07-07 Polisher rule: Mac = automatic batch polisher; iPad = on-demand ("Process now" / polish-on-open); no election protocol — src: `memory/project_ipad_direction.md:24-27` (executed 2026-07-22, `memory/project_ipad_wave1.md:64-65`)
- 2026-07-22 Shared verb: it is "Process" on every device ("I don't know why it's called polish, if it's called Process on the Mac") — `SharedCopy.processVerb` — src: `memory/project_ipad_wave1.md:52-53`
- 2026-07-28 Paragraphs single-sourced (`Shared/Pipeline/Paragrapher`): Mac file pass paragraphs at store time like the phone; already-structured text (any newline / speaker turns) passes through untouched; `longFormGap` 2.0 s shared, phone live 0.65 s untouched — src: `memory/project_live_transcription.md:119-124`, `memory/project_note_consent.md:60-63`
- 2026-08-12 ONE model on every device (8-bit Gemma-4-E4B, revision-pinned) — Tuur's own objection to a 4-bit iPad model: identical polish everywhere; the 12B OptiQ bake-off was "a trade, not a win", stayed on 8-bit — src: `memory/project_ipad_polish_fix.md:14-22,33-34,46-49`
- 2026-08-26 "Has a pass RUN?" must never be answered by "is there polish worth showing?": a pass records itself even when the model has nothing to say (`MemoEnhancement.processedAt`); a manual-edit re-sync does not; pre-`processedAt` rows use the ALL-THREE-PARTS rule, never any-part — src: `memory/project_export_destinations.md:71-86`
- 2026-06-14 Quote protection: an audiobook quote passes through enhancement byte-identically; `[[Author]]` is added at export only — src: `SKRIFT_SOURCE_OF_TRUTH.md:289,490`

### Reconcile sweep
- 2026-06-22 Mac = a 2nd `NSPersistentCloudKitContainer` client of the SAME `Memo` schema (Fork A; hand-rolled CKRecord bridge rejected) — src: `archive/handoffs/MAC_CLOUDKIT_PLAN.md:117-137`
- 2026-06-22 Write-back = W2 sidecar `MemoEnhancement` (not fields on `Memo`) so `Memo.transcript` stays RAW and sacrosanct; `MemoExporter` prefers the sidecar — src: `archive/handoffs/MAC_CLOUDKIT_PLAN.md:172-189`
- 2026-06-22 Read bridge reuses the exact upload-ingest mapping (parity by construction) with the same trust gate — src: `archive/handoffs/MAC_CLOUDKIT_PLAN.md:26-31,164-170`
- 2026-06-22 Mac processes only `significance > 0` by default; "process everything synced" was an opt-in — reversed 2026-07-21: that toggle RETIRES (rating is the only gate) — src: `archive/handoffs/MAC_CLOUDKIT_PLAN.md:199-201`; `memory/project_note_lifecycle.md:30-32`
- 2026-07-06 Bonjour/HTTP retired on BOTH apps; CloudKit is the only transport — src: `archive/handoffs/LIVE_SYNC_HANDOFF.md:9-11,23-25`, `CLAUDE.md:11`
- 2026-07-06 Live bidirectional edit sync: Mac edits → debounced `MemoEnhancement` re-upsert; phone edits → Mac refreshes its row (re-link + recompile); provenance stamp so a device never echoes an edit that came from the other side — src: `archive/handoffs/LIVE_SYNC_HANDOFF.md:12-20,93-113`
- 2026-07-13 The Mac sweep is duplicate-tolerant: same-id clone Memos resolve to ONE keeper (most content), clones detached + trashed, differing content left alone — src: `memory/project_desktop_parity_plan.md:50-54`
- 2026-07-16 Each sweep reads a FRESH `ModelContext` (a CloudKit import updates the store, not a cached context) — src: `memory/project_intertwining_device_bugs.md:11-13`
- 2026-07-21 Mac-only files DISSOLVE: Mac imports author synced `Memo`s (`MacMemoAuthor`); both devices are collectors — src: `memory/project_note_lifecycle.md:30-32`
- 2026-07-23 Final lifecycle doors move ONLY at an app-open: sweeps at phone launch + foreground / Mac launch + activation; the Mac 24 h heartbeat + day-change sweeps RETIRED — src: `memory/project_lifecycle_one_clock.md:25`
- 2026-07-28 `reflectTranscripts` publishes only `.done` rows (the live seed must never clobber the final pass) — src: `memory/project_live_transcription.md:113-117`
- 2026-07-28 A local recording is the ROW's own fact (`PipelineFile.isLocalRecording`), stamped at construction, because the sweep races ingest; `MacCloudWriteBack` resolves the memo id by asking the store, never by filename alone — src: `memory/project_mac_recording.md:69-80`
- 2026-08-20 An echo guard asks whether the local copy EXISTS: a fresh row adopts the cloud enhancement even when `enhancedByDeviceID` is this Mac — src: `memory/project_rate_to_row.md:26-29`
- 2026-08-20 Never turn a waiting thing into a different thing: a memo whose audio blob has not synced is NOT a text note; text-only is the caller's decision (`MemoCloudIngest.isTextOnly`), never sniffed from the parts — src: `memory/project_rate_to_row.md:31-35`
- 2026-08-20 A rated memo with no pipeline row must still render (`WayOutRules.stranded`); a branch returning `[]` is a silent nil factory — src: `memory/project_rate_to_row.md:15-24`
- 2026-08-20 The sweep takes an injectable `UploadService`; a default that resolves to real user data is a test hazard (1987 folders written into live Dev data) — src: `memory/project_rate_to_row.md:37-40`

### Export compiler
- 2026-06-22 Obsidian export = overwrite + edit-guard back-off: Skrift updates its file until it detects a vault edit, then adopts the user's version and backs off forever ("your edit wins"); Tuur confirmed he WILL edit exported notes; deleting the vault file lets the next export recreate it — src: `archive/handoffs/OBSIDIAN_EXPORT_ALTERNATIVES.md:8-17`
- 2026-06-22 PUSH mode: deleting the Skrift memo after export is fine and desirable ("capture tool; Obsidian is home") — src: `memory/project_obsidian_relationship.md:21-24`
- 2026-06-16 Skrift writes real `[[ ]]` + frontmatter to disk; the person timeline never depends on a live Obsidian plugin — src: `NAMING_MODEL.md:205-207`
- 2026-06-16 Keep `people:` frontmatter alongside the body link — durable (survives edits), queryable (Dataview/Bases); body link = browse, `people:` = query — src: `NAMING_MODEL.md:38-41`
- 2026-06-14 Audiobook quote export shape `> — [[Author]], *Book*, ch. N`; the author is never in the names DB — src: `SKRIFT_SOURCE_OF_TRUTH.md:289,519`
- 2026-06-07 Per-note "Include audio in export" toggle; exported audio named by title `<title>.<ext>` — src: `archive/handoffs/WALKTHROUGH_BUGS.md:24,76`
- 2026-07-07 Locked notes are EXCLUDED from Obsidian publish (sync continues); lock-after-export → honest vault notice, never deletes vault files; Mac `VaultExporter` refuses — src: `FEATURES.md:41`, `memory/project_note_editing_sprint.md:43`
- 2026-07-26 ONE vault-write engine, doctrine locked with Tuur: the picked folder IS the destination (no `Skrift/` prefix — "his vault already has `0 Inbox/Skrift`"); the folder is an INBOX, identity lives in the FILE stamp; moved notes report `movedAway` and are NEVER respawned; never write over anything not provably ours + untouched (the hash spans frontmatter — an Obsidian tag edit counts; "edit tags in the app" rejected as unintuitive); atomic + `NSFileCoordinator`; unchanged notes write NOTHING (iCloud churn); ledger per folder = convenience, stamp = safety — reversed the 2026-06-21 `<vault>/Skrift/{Voice Memos,…}` subfolders and the 2026-06-22 "WRITE-ONLY" publisher — src: `memory/project_ipad_wave1.md:317-334`, `FEATURES.md:70`; older: `STANDALONE_PLAN.md:262-263`, `memory/project_standalone_app_store.md:214`
- 2026-07-26 Export is rated-only everywhere; the phone's "All notes" publish option REMOVED; unrated never exports — src: `memory/project_ipad_wave1.md:355-356,368-369`
- 2026-08-11 THE PHONE DOESN'T EXPORT: "Only the iPad and the Mac can do that AFTER they processed the note"; the folder picker stays everywhere (prerequisite for the phone READING the vault later); `shouldPublish` requires a PROCESSED note, not merely rated — src: `memory/project_ipad_wave1.md:14-22`
- 2026-08-11 Nothing auto-publishes on iOS; Settings → "Export now" is the only trigger, kept manual deliberately while the engine is unproven against a real vault — src: `memory/project_ipad_wave1.md:23-25`
- 2026-08-26 Four destinations, ONE-OF-FOUR: Personal → his Obsidian vault; Made → `portfolio/_inbox/`; Idea → `portfolio/_ideas/`; Inspiration → `portfolio/_inspiration/` — src: `memory/project_export_destinations.md:55-59`, `FEATURES.md:68`
- 2026-08-26 THE DESTINATION IS A PRIVACY BOUNDARY, NOT A FILING SHELF: his own thoughts must never be read by AI; ideas and inspirations are what he WANTS Claude to work on — hence never two destinations at once, a stored field not a real tag (a typo would re-route a note), reserved words refused in the tag field — src: `memory/project_export_destinations.md:60-64`
- 2026-08-26 NO suggestion engine for the destination: "I know what I'm recording, I just click a button… it's gonna be so wonky" — src: `memory/project_export_destinations.md:29-30`
- 2026-08-26 `idea` + `inspiration` together is meaningless (the line is AUTHORSHIP); a photograph that gave him an idea is ONE note filed Idea ("that's actually how it always happens") — src: `memory/project_export_destinations.md:66-69`
- 2026-08-27 Archive names are NAMED, not dated, and FLAT — `_ideas/<full-name>.md`, media beside them, cap 120 chars (the vault's own rule); the timestamp survives only as the fallback for a title-less capture — src: `memory/project_export_destinations.md:32-35`
- 2026-08-27 Archive frontmatter unified against his real portfolio repo: `capture:` not `source:`, `author:` dropped, `voice:` (raw|cleaned|written) + `needs: - credit` added; Skrift and the archive share ZERO keys — src: `memory/project_export_destinations.md:11-17`
- 2026-08-27 `voice:` is set by EACH APP, never derived in the Compiler (Mac body lives in `enhancedCopyedit`, phone in `sanitised` — a Compiler guess read different values for the same note) — src: `memory/project_export_destinations.md:19-21`
- 2026-08-27 He REVERSED the privacy call on names: the archive KEEPS `people:` and the body's `[[names]]` (public website, "credit where credit is due"); places still drop — "Don't fix this back" — src: `memory/project_export_destinations.md:87-91`
- 2026-08-26 DELETED is not FILED: a moved file = inbox doctrine, never respawn; a deleted file must be re-exportable (he deleted test exports and got "left where you put it" forever) — `VaultStamp.locate` tells them apart — src: `memory/project_export_destinations.md:23-27`
- 2026-08-14 Video has no exportable asset kind — Skrift never keeps the movie (audio extracted, temp copy discarded); shared video is transcribed, never exported; closed by Tuur as "skip them" — src: `memory/project_export_destinations.md:49-51,111-113`, `FEATURES.md:68`
- 2026-07-26 Digest/related mentions of an UNRATED note are plain text, never `[[links]]` (they would dangle) — src: `memory/project_ipad_wave1.md:373-374`
- 2026-07-26 The Obsidian plugin is the TOP RUNG of standalone (phone alone → +Mac/iPad → +plugin), not a rival; Connections = Mac-live ONLY, a static sidecar tier REJECTED ("don't like stale data") — src: `memory/project_ipad_wave1.md:374-375,419-426`

### Ingress (share/import)
- 2026-06-12 A capture item = a URL / text / image / file shared in + optional annotation + rating; NO audio, NO transcription, NO diarization; the annotation is the note body; a bare capture (no annotation) is legal — src: `Skrift_Native/CAPTURE_CONTRACT.md:13-19,51-52`
- 2026-06-07 Share-to-import audio arrives via document types (`public.audio` → `MemoSaver.importAudio`); m4a/wav/mp3 transcribe on-device; other formats fall back to the Mac — src: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:438-441`
- 2026-06-14 Share a video → voice memo: audio stripped + one frame thumbnail; `recordedAt` = the video's filming date (never rewritten); `createdAt` added so it still sorts to the top under "Recently added" — src: `archive/handoffs/NEXT_CHAT_HANDOFF.md:36-44`, `SKRIFT_SOURCE_OF_TRUTH.md:147`
- 2026-06-14 List sorts: Recently added (DEFAULT) / Recently edited / Recently recorded / Oldest / Longest; date-range filter (Recorded or Added) — src: `archive/handoffs/NEXT_CHAT_HANDOFF.md:40-44`
- 2026-06-07 Memo date = the RECORDING date, not the import date: embedded m4a `creation_time` → date in the filename (WhatsApp/Signal/recorder names) → file creation date → now — src: `archive/handoffs/DESKTOP_NATIVE_HANDOFF.md:54`, `archive/handoffs/WALKTHROUGH_BUGS.md:80`
- 2026-06-07 Folder ingest accepts audio (drag a folder of recordings); in-app Delete moves the on-disk working folder to Trash (recoverable) — src: `archive/handoffs/DESKTOP_NATIVE_HANDOFF.md:53,55`
- 2026-06-07 Apple-Notes attachments: copy siblings into the note folder renamed `<safe title> - <n>.<ext>`, HEIC→JPG, rewrite refs; copies, never mutates the source — src: `archive/handoffs/DESKTOP_NATIVE_HANDOFF.md:67`
- 2026-06-08 Native-parts rule: the ONE non-native runtime bit (`sips` shell-out for HEIC) goes native via ImageIO — src: `memory/project_unification_backlog.md:100-106`
- 2026-06-11 Capture URL title comes from the share payload, no network fetch — src: `Skrift_Native/CAPTURE_CONTRACT.md:39` (see needs-verdict: the 2026-09-18 note says a title/page-text fetch exists and is "the jank")
- 2026-07-12 Shared inputs NEVER get bubble/box chrome ("again — I keep telling you"); pinned shared text uses the audiobook-quote idiom (accent bar, italic, borderless); notes must read as NOTES, WYSIWYG to the Obsidian output — src: `memory/feedback_no_bubbles_on_shared_input.md:10-14`
- 2026-07-28 A Mac recording is not a new kind of thing: it is a file arriving by a different door — Stop calls the same `ArrivalPath` Import does — src: `memory/project_mac_recording.md:99-101`
- 2026-07-28 Transcription is CAPTURE (words on stop, note unrated); polish, name-linking and export are PROCESSING and only those are gated by the rating; when unsure how the Mac should behave, copy the phone — src: `memory/feedback_copy_the_phone.md:11-28`, `memory/project_mac_recording.md:82-84`
- 2026-09-18 Ingress corpus: ONE real source file per media type with the platform's exact filename + container quirks, pushed through the REAL share/import code in Dev, the resulting memo recorded as the golden; network fetches recorded once and replayed — the diff harness never touches the network — src: `backlog.md:618-633`
- 2026-06-07 Memory-aid record prompts, photo filmstrip, Settings storage stats: "user doesn't care, won't port" — src: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:485-495,522-523`

### Names & sanitise
- 2026-06-16 The job: every person = ONE note; memos ABOUT a person collect on it as dated backlinks so "decades later you open their note … and watch the relationship evolve" — src: `NAMING_MODEL.md:13-16`
- 2026-06-16 Two separable jobs: normalisation (names spelled right everywhere, even unlinked) and linking (only genuine subjects become graph edges; side-characters do not) — src: `NAMING_MODEL.md:18-22`
- 2026-06-16 Aggregate via Obsidian backlinks; the canonical lives in Skrift's portable names DB and must match the `People/` note title exactly — src: `NAMING_MODEL.md:28-32`
- 2026-06-16 ONE inline body link per subject, the FIRST mention (backlink pane shows the sentence; prose stays clean) — src: `NAMING_MODEL.md:33-37`
- 2026-06-16 DEFAULT = OPT-OUT with risk-tiered auto-write — "for a 50-year capture archive, a missed link is unrecoverable, a stray link is a two-second prune"; auto-commit full/distinctive names, dotted-suggest common-word or shared names, leave stoplisted words plain; reversed the 2026-06-15 opt-in model (chunks 1–5 built then deleted) — src: `NAMING_MODEL.md:42-60`; `SKRIFT_SOURCE_OF_TRUTH.md:534`
- 2026-06-16 Recognition = KNOWN-ROSTER ONLY; no NER, no LLM; the roster grows for life by manual right-click add; REJECTED: any auto "new person?" hint, even the deterministic capitalised-token one ("ASR casing on speech is shaky"); the system "never misses KNOWN people", never claims to catch unknown ones — src: `NAMING_MODEL.md:61-75,203-204,217-218`
- 2026-06-16 NO LLM anywhere in the naming path — it must be portable to the phone — src: `NAMING_MODEL.md:76-81`
- 2026-06-16 Mistranscribed known names are normalised everywhere; unlinked ones show DOTTED so the fix is visible and one-click revertible, never a silent rewrite — src: `NAMING_MODEL.md:82-86`
- 2026-06-16 Interaction = click a name in the prose → popover (keep / side-mention unlink / wrong person / new / leave as spoken); demoted names stay dotted + re-promotable; this REPLACES the chip bar — src: `NAMING_MODEL.md:87-90`
- 2026-06-16 Ambiguity (two known people, one name) = note-level pick + per-mention override; NO per-occurrence resolver ("never happened") — src: `NAMING_MODEL.md:91-97`
- 2026-06-16 "Change person" lists ONLY people who share the name and is HIDDEN for a distinctive name; rejected: filled-highlight link style ("sea of links"), the pending-count bar, saturated amber — src: `NAMING_MODEL.md:134-141`
- 2026-06-16 Matcher stays STRICT: whole-word + capitalisation, no edit-distance ("fuzzy-vs-FP is the LLM trap we exclude"); knobs = `NameStoplist` + min length — src: `NAMING_MODEL.md:284-286`
- 2026-06-16 Roster seeding reads `<vault>/People/*.md` FILENAMES only (top-level, no contents, no AI); canonical = title so links resolve; aliases = full title + first-name token — src: `NAMING_MODEL.md:245-252`
- 2026-06-16 Skip non-prose spans when scanning (YAML, code, verbatim audiobook quote — "a name inside a quoted book passage is NOT about that roster person"); retroactive re-scan when a second same-name person is added — src: `NAMING_MODEL.md:181-187,280-288`
- 2026-06-16 The date-sorted person view is the user's Dataview/Bases query; Skrift writes `date:` + backlinks; Skrift does NOT create or enrich person notes (a separate "people CRM" track) — src: `NAMING_MODEL.md:212-215,294-295`
- 2026-06-14 Conversation linking: inline mentions render `[[Canonical|spoken]]` on EVERY mention (the spoken word preserved — replace-all "fucks it up"); a speaker's FIRST turn header = `[[Canonical]]`, later turns = plain short `**Tuur:**`; merge consecutive same-speaker turns; Re-transcribe DISABLED for diarized memos — src: `memory/project_conversation_namelinking.md:13-17`
- 2026-06-15 On-device name-linking = YES for display + export; the phone STILL sends RAW; the Mac re-links identically via shared code + the synced names DB (no double-link, no skip flag); reversed the 2026-06-05/06 "NO on-device name-linking, phone NEVER links" rule — src: `STANDALONE_PLAN.md:273-280,563-567`; older: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:82-88`, `memory/project_mobile_overhaul.md:15`
- 2026-06-15 Alias management UI on the phone mirrors the Mac (reversed the 2026-06-06 "no alias editing on the phone"); 2026-07-16 one shared `NamesStore`, the phone editor saves like the Mac — src: `STANDALONE_PLAN.md:277-278`, `memory/project_connections_panel.md:38-39`; older: `memory/feedback_native_ui_process.md:33-38`
- 2026-06-07 Mac right-click "Add '…' as ▸" = a new name OR an alias of an existing person; cross-person duplicate aliases allowed on purpose (that IS the two-Jacks ambiguity) — src: `archive/handoffs/DESKTOP_NATIVE_HANDOFF.md:52`
- 2026-06-13 Custom vocabulary: pre-warm the booster at launch when words exist; aliases `"Canonical: alias1, alias2"`; trust guard drops a boost when every replacement is sim < 0.55; cbw tuning is a dead end (do not lower) — src: `memory/project_vocab_booster.md:13-38`
- 2026-07-27 A speaker's hue slot = first-appearance order of the RESOLVED identity (never header text), shared by linker and both renderers — src: `memory/project_conversation_turn_gutter.md:47-52`

### Consent / rating / lifecycle
- 2026-06-04 Significance is a user-set value, not LLM-scored; one field (confidence/importance/significance consolidated) — src: `SKRIFT_SOURCE_OF_TRUTH.md:79`, `memory/project_overhaul.md:24`
- 2026-06-08 "Only if they have more than 0 significance are they suitable for transfer — I don't need to send stupid messages to the Mac" — reversed 2026-07-20 in MEANING only: CloudKit syncs every memo; significance is flag-to-PROCESS (the Mac's pickup), not flag-to-send; phone microcopy fixed to "Not flagged — the Mac will leave it alone" / "Flagged — the Mac will polish this" / 0.8+ = refine pass — src: `memory/project_unification_backlog.md:11-19,42-51`
- 2026-06-11 Slider → 10 tappable circles, 0–1 in 0.1 steps (tiers Passing/Useful/Important, 0.8 refine wall) — src: `SKRIFT_SOURCE_OF_TRUTH.md:150`, `memory/feedback_mock_as_is_from_source.md:10-13`
- 2026-06-19 "significance" → "Importance" in visible copy only; `Memo.significance`, test IDs and the contract key untouched — src: `STANDALONE_PLAN.md:446-447`
- 2026-06-11 Trash / Recently Deleted = 14-day retention; the phone owns permanent deletion — src: `SKRIFT_SOURCE_OF_TRUTH.md:149,268`, `memory/project_note_lifecycle.md:14-16`
- 2026-07-18 Fading lifecycle: an untouched note fades at 30 d into count-badged shelves and auto-trashes at 60 d via the existing 14-day trash; fading is DERIVED (no stored state); `Memo.keptAt` is the one synced addition; timers FULLY automatic ("why is it not automatic?" — reversible trash + counts are the safety) — src: `memory/project_note_lifecycle.md:11-20`
- 2026-07-18 What counts as a touch: dots / edit / title / tags / lock / reminder / annotation / backlink / keptAt; photos and bare captures deliberately NOT touches — src: `memory/project_note_lifecycle.md:13-14`, `backlog.md:5780`
- 2026-07-21 Lifecycle IA = Two Rooms, One Spine + an exit conveyor; ONE trash over both stores; conveyor verb "Bring back"; `processAllSyncedMemos` toggle retires — src: `memory/project_note_lifecycle.md:22-32`
- 2026-07-21 Trash is NOT searchable; fading IS — src: `memory/MEMORY.md` (index line "IA overhaul … LOCKED: trash not searchable, fading IS")
- 2026-07-22 ONE CLOCK: touching a note restarts its 30-day clock (fade anchor = max(recordedAt, keptAt)); "Parked / kept — edited" ceases to exist; exemptions that never fade = locked, pending reminder, backlinked; "On its way out" renamed "Fading" (Tuur's word); replaces the 2026-07-17 rule "anything you touched stays until you say otherwise" — src: `memory/project_lifecycle_one_clock.md:13,17`
- 2026-07-22 The importance circles ARE the flag: no "Flag for processing" button, no silent 0.1 auto-write; the Flag verb retired on both apps ("Rating IS the flag") — src: `memory/project_lifecycle_one_clock.md:15`, `memory/project_ipad_wave1.md:60`
- 2026-07-22 Lock is background-only (Tuur: locked one note ever): no peek button; quiet-row right-click + the phone's existing toggle — src: `memory/project_lifecycle_one_clock.md:15`
- 2026-07-22 ASYMMETRY DOCTRINE: Mac list = deciding room (always-on per-row state); phone list = notebook (unrated is the default, not an alarm; clock line only when fading ≤ 7 d); the lists are deliberately not twins — src: `memory/project_lifecycle_one_clock.md:23`
- 2026-07-23 v3 "no note dies unseen": purge countdown = synced `Memo.trashSeenAt` (first open with the note in trash); a stamp older than `deletedAt` is stale; delete gestures stamp their own — src: `memory/project_lifecycle_one_clock.md:25`
- 2026-07-26 THE UNRATED MODEL: "the rating is CONSENT — until judged, Skrift spends nothing on a note and shows it nowhere but back to you": fades · grey · no Process · no export · no Connections in EITHER direction; unrated notes DO play, show photos, karaoke, a slim ⋯ (copy verbs) — src: `memory/project_ipad_wave1.md:365-374`, `memory/project_note_consent.md:13-14`
- 2026-07-26 An unrated note IS a normal note — no second renderer ("make an unrated note identical to other notes… nothing special"); `MemoNoteProjection` feeds the ordinary note view — src: `memory/project_ipad_wave1.md:253-266`
- 2026-07-26 Pressing Polish IS a judgment: `polishNow` floors the rating to 0.1; the 0.1 floors (`MacMemoAuthor` imports, `polishNow`) are DOORS out of unrated, not leaks — src: `memory/project_ipad_wave1.md:367`, `memory/project_note_consent.md:41-42`
- 2026-07-26 Rating is a ONE-WAY door on a synced pipelined note (un-rating leaves the row lit and processing) — DECIDED AS-IS, he was offered the symmetric fix and chose to leave it; 2026-07-28: local Mac takes are two-way — asymmetric on purpose — src: `memory/project_ipad_wave1.md:309-314`, `memory/project_note_consent.md:39-41`
- 2026-07-26 "Don't take my thing as doctrine": per-difference decisions on unrated behaviour, not blanket rules — src: `memory/project_ipad_wave1.md:336-340`
- 2026-07-28 ONE rated/unrated predicate (`Shared/Pipeline/NoteConsent.isRated`) routes every gate; `PipelineFile.significance` nil has three meanings resolved only in `NoteConsent+PipelineFile` (projection = unrated; local recording = unrated; local import/legacy = RATED) — src: `memory/project_note_consent.md:11-25`
- 2026-07-26 A rating user action is an EVENT (`MacCloudMetaSync.setRating`), never disambiguated in a passive mirror pass — src: `memory/project_ipad_wave1.md:301-308`
- 2026-07-28 Unrated Mac takes are quiet dim rows, out of "Process N"; errors stay loud — src: `memory/project_mac_recording.md:49-52`
- 2026-07-16 Connections: importance decimals are user-set (warm ≥ 0.8); unrated = nothing shown — src: `memory/project_connections_panel.md:12-15`

### Sync contract
- 2026-06-15 Internal sync = CloudKit (SwiftData CloudKit mode), NOT iCloud-Drive file sync — no `filename 2.md` conflict copies — src: `STANDALONE_PLAN.md:34-35`
- 2026-06-15 Three coexisting modes over ONE source of truth (standalone / +Obsidian / +Mac); the Mac and Obsidian are optional output sinks ("we can't bet wrong") — src: `STANDALONE_PLAN.md:20-22,39-40`
- 2026-06-15 Cross-app consistency = shared CODE, not parallel copies, and deterministic RE-DERIVATION (never a one-sided "done" bit) — src: `STANDALONE_PLAN.md:71-88`
- 2026-06-17 The shared mechanism is a source FOLDER (`Skrift_Native/Shared/`) compiled into both apps, NOT an SPM package (~50 consumers; zero import churn) — src: `STANDALONE_PLAN.md:164-166`
- 2026-06-18 Fold ALL device↔device sync into Phase 1: media, word-timings + diarization sidecars, names + voices, custom vocab, audiobook state — src: `memory/project_standalone_app_store.md:52-54`
- 2026-06-18 Audiobook AUDIO sync = PER-BOOK opt-in (books local by default, `library.json` untouched; resume-anywhere needs a shared book id); position/bookmarks/rate always sync for opted-in books — src: `STANDALONE_PLAN.md:546-551`, `memory/project_standalone_app_store.md:54-55`
- 2026-06-22 The phone carries the RAW transcript, never `sanitised`; the Mac links names; trust = `transcriptUserEdited || transcriptConfidence ≥ 0.7`; `names.json` byte-compatible across both apps — src: `CLAUDE.md:34-42`
- 2026-06-14 A phone-diarized conversation sets `transcriptUserEdited = true` so the Mac trusts its turns regardless of confidence — src: `memory/project_conversation_namelinking.md:25`, `SKRIFT_SOURCE_OF_TRUTH.md:509`
- 2026-06-18 Custom vocab syncs LWW-by-`modifiedAt` on the WHOLE list (a delete must propagate; a union would resurrect words); a fresh never-edited device never pushes an empty list — src: `STANDALONE_PLAN.md:522,538`
- 2026-07-26 ASR language setting syncs on the existing `VocabularyRecord` carrier with its OWN stamp; `LanguageSyncCore` refuses to push a default nobody chose; the Mac gets the same setting — src: `memory/project_ipad_wave1.md:393-401`
- 2026-07-22 LOCAL-ONLY sync doctrine: fields describing local files/derivations (`epub*`, `detectedChapters`) are STRIPPED from every sent blob and preserved at every adopt site — an older writer's whole-blob LWW erases additive fields — src: `memory/project_epub_alignment.md:57-61`
- 2026-07-23 Once-only UI flags live in UserDefaults, never in the synced record — src: `memory/project_epub_unified_text_sheet.md:39-41`
- 2026-07-16 Embeddings never sync; each device sweeps its own index; the consent key string is shared but per-device — src: `memory/project_connections_panel.md:29-30`
- 2026-07-22 A sync applied-marker records what the apply PRODUCED, never just that it ran — src: `memory/project_ipad_wave1.md:57-59`
- 2026-06-15 Minimum iOS = 26 (FM / glass / SwiftData-CloudKit clean; accept dropping pre-26 devices) — src: `STANDALONE_PLAN.md:571-572`
- 2026-06-18 Deliberately NOT a merged single app: separate UIs, shared model + pure code only — src: `memory/project_standalone_app_store.md:56-59`

### Recording & audio
- 2026-06-06 Live transcription DURING recording = YES, the signature ("starts the moment you speak") — src: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:688-692`, `memory/feedback_native_ui_process.md:29-32`
- 2026-06-06 Record = caption-first, camera ON-DEMAND (viewfinder slides up as a sheet, recording keeps going), never persistent — src: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:693-699`
- 2026-06-06 Post-record flow = save-now → Memo detail; NO Review screen (Stop persists immediately; the live caption pre-fills until the file pass refines it) — src: `memory/feedback_native_ui_process.md:64-67`, `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:362`
- 2026-06-07 The transcript is ALWAYS editable (no Edit button); Re-transcribe REMOVED on the phone (failed = informational, recovers via edit) — src: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:189-192,507-510`
- 2026-06-06 One-shot transcribe-on-stop stays the file/import path; streaming only for the live record screen — src: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:48-49,690-692`
- 2026-06-07 App Intents = plain `AppIntent` + `openAppWhenRun`, never `AudioRecordingIntent` (SIGTRAP in Shhhcribble); no haptic in the auto-start path (haptics share the audio session Siri still owns) — src: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:432-437,595-598`
- 2026-06-06 Pair-a-Mac by Bonjour, QR dropped ("noone cares, remove it") — reversed 2026-07-06: Bonjour itself retired — src: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:707-712`; `archive/handoffs/LIVE_SYNC_HANDOFF.md:9-11`
- 2026-06-09 Diarization = NVIDIA Sortformer on both apps (legacy `DiarizerManager` merges similar voices); identification = a SEPARATE wespeaker-embedding cosine match, threshold 0.5 (different ≤ 0.22, same ≥ 0.62), true cosine (not unit-norm), ≥ 2 s of speech; the embedding is what syncs — src: `archive/handoffs/CONVERSATION_MODE_HANDOFF.md:27-30,131-137`
- 2026-06-09 Tag-as-you-go: name a speaker → voiceprint saved → auto-matched next time — src: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:211-212,247-249`
- 2026-06-09 Conversation markdown = bold-name turns `**Speaker 1:** …` → `**[[Name]]:** …` once tagged; per-speaker colour is app-only chrome (markdown carries no colour) — src: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:243-246`
- 2026-06-06 Conversation mode = manual toggle on the record screen, not automatic — reversed 2026-06-09: POST-TRANSCRIPT "Split speakers" button (person.2.fill next to ⋯), no pre-record toggle ("the user kept forgetting to toggle"); "How many speakers? Auto/2/3/4/5", forcing N merges the most similar slots, merge is PER-LINE, the model loads only on tap; 2026-06-15 adds "Flatten to monologue" — src: `memory/project_conversation_voice_identity.md:41-50`, `SKRIFT_SOURCE_OF_TRUTH.md:167`; older: `memory/feedback_native_ui_process.md:39-41`
- 2026-06-14 SpeakerFusion: `minTurnWords` 3; gap words go to the nearest BOUNDARY (byte-identical on both apps) — src: `memory/project_conversation_namelinking.md:26`
- 2026-06-08 Recording gain uses `.default` (`.measurement` was soft with a tiny waveform); a < 0.4 s recording is discarded with "Nothing recorded" — src: `memory/project_mobile_native_rewrite.md:28`, `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:282-283`
- 2026-06-12 AirPods P0: validate/install the tap with `inputFormat`, not `outputFormat` — src: `SKRIFT_SOURCE_OF_TRUTH.md:152`
- 2026-06-22 Live captions auto-stop after a default 1 min (battery) — src: `SKRIFT_SOURCE_OF_TRUTH.md:192`
- 2026-06-15 ASR mel-chunk-context: English default mel-ON, Dutch A/B showed mel-OFF wins → a Language setting, not a revert — src: `SKRIFT_SOURCE_OF_TRUTH.md:550`
- 2026-07-26 With Bluetooth present the WHOLE memo records on the built-in mic (`avoidsBluetoothMic`; A2DP output stays on the AirPods); a mid-recording flip to the headset mic was built (b117) and REJECTED on device the same day — the transition eats speech — src: `memory/project_audio_session_round.md:15-17`
- 2026-07-26 Capture starts AT the record button (`prestart()` parks a starting service synchronously in the button action) — src: `memory/project_audio_session_round.md:19`
- 2026-07-26 Audiobook keeps the route: latch `pausedByInterruption`, resume only latch + `.shouldResume` + no live recording; the quote-capture ramble's stop skips `notifyOthersOnDeactivation` while a book session is active; Tuur DEFERRED the device test ("only encountered it once — I'll trust you") — not owed — src: `memory/project_audio_session_round.md:24-28`
- 2026-07-28 Mac live transcription (m2, "for sure"): the note pane IS the recording surface; settled text is the USER's (editable mid-take), the wet tail is the ENGINE's; stop just stops (m4 trimmed); an edited take finalises only the wet region and is marked trusted — src: `memory/project_live_transcription.md:11-29`
- 2026-07-28 The settle mechanism is TEXT STABILITY (identical non-empty tail decode on two consecutive polls = the pause); the RMS/VAD lane is DEAD on his mic — "never re-tune levels, extend stability"; Mac rotates at 7 s, poll floor 0.4 s, ceiling 20 s; phone keeps its thermally-tuned 25 s — src: `memory/project_live_transcription.md:66-68,99-109,125`
- 2026-07-28 Mac recorder = `AVCaptureSession` (device-targeted `AVAudioEngine` on macOS yields stale/0 Hz formats); records on the wired mic while Bluetooth is around; a dead take verdicts at stop naming the device — src: `memory/project_mac_recording.md:21-28,33-47`
- 2026-07-28 Mac Record button = mock B: Import and Record pair on one row, Process full-width below — src: `memory/project_mac_recording.md:11-12`
- 2026-07-28 Record's append-only model CONFIRMED; dictate-at-caret PARKED ("similar to Scribble… maybe we don't need the Apple version — keep what we have"); if ever built, dictated audio is NOT kept — src: `memory/project_note_consent.md:48-51`
- 2026-07-07 Audio-trim DROPPED; transcription QUALITY is the moat (Parakeet ≫ Apple) — src: `memory/project_note_editing_sprint.md:44-45`
- 2026-07-11 Book chunks skip the custom-vocab CTC pass ("book prose never wants vocab swaps") — src: `memory/project_audiobook_player.md:52-53`

### Audiobooks
- 2026-06-11 Skrift IS the audiobook player (modelled on Bound); one memo per capture; quote audio = the captured span — src: `SKRIFT_SOURCE_OF_TRUTH.md:490`
- 2026-06-13 Text-first quote capture is the ONLY flow; the audio mark-in/out arm RETIRED (built, then cut) — src: `SKRIFT_SOURCE_OF_TRUTH.md:286,535`, `archive/handoffs/NEXT_CHAT_HANDOFF.md:30-32`
- 2026-06-13 Build-your-quote is bidirectional and bounded: the tapped line is the centred anchor, ~90 s before + up to 8 lines after (4 un-chunked) — src: `archive/handoffs/NEXT_CHAT_HANDOFF.md:33-35`
- 2026-06-13 Bookmarks BUILT (reversed the 2026-06-12 "decided against"); whole-book pre-transcribe BUILT (reversed the earlier "explicitly rejected") — src: `SKRIFT_SOURCE_OF_TRUTH.md:536-537`
- 2026-06-19 Reading-mode redesign LOCKED and built to the mock: tab-bar IA (Notes · Library · Highlights · Settings — Library stops being a sheet), reading mode = auto-recede (~3–4 s idle, never while paused), now-line pinned upper-third, margin bookmark glyph, add = action / sheet = browse-only, "Aa" size + spacing, floating play, cover-tint ambiance; delete offers "all devices" + "this iPhone only" for synced books; build the WHOLE redesign, then export — src: `memory/project_standalone_app_store.md:190-199`, `STANDALONE_PLAN.md:443-456`
- 2026-07-11 Transcript chapter detection is THE chapter standard ("even file-per-chapter splits aren't reliably chapters"); `detectedChapters` is local-only; detected > embedded/file-synth for ALL chapter UI — src: `memory/project_audiobook_player.md:40-51`
- 2026-07-12 "Better no information than bad information": incomplete derived data degrades the DISPLAY to the coarser complete level (book-level jump points, not a gappy chapter list); never renumber to fake completeness — src: `memory/feedback_no_bad_information.md:10-21`
- 2026-07-21 ePub decisions LOCKED: ePub TOC wins chapters · aligner-internal normalisation · FluidAudio pin bump · ZIPFoundation yes · `.epub` primary, `.txt` freebie, `.mobi` skip; pictures-in-reader PARKED — src: `memory/project_epub_alignment.md:112-114`
- 2026-07-22 "ePub TOC wins" is scoped to the files it aligned to; detected chapters/separators outside those spans survive — src: `memory/project_epub_alignment.md:74-80`
- 2026-07-23 ONE "Text…" verb/sheet (library long-press + player ⋯): Level 1 Transcript over Level 2 Book text; A0 once-per-book post-import "do both" prompt; an affordance must acknowledge existing state ("Add book text…" → "Add another text…") — src: `memory/project_epub_unified_text_sheet.md:11-18,42-43`
- 2026-07-23 Union display: ASR fills uncovered runs ≥ 3; collisions contest BETWEEN texts only, never within one text's own batch — src: `memory/project_epub_alignment.md:16-23`
- 2026-06-13 Chunk extraction for transcription uses sample-accurate `AVAudioFile` frame reads, never `AVAssetExportSession` (drifts word-times on compressed audio) — src: `memory/project_audiobook_player.md:21-30`
- 2026-07-30 Book sharing = ONE `.skriftbook`, ONE option, "no fluff": "send the BOOK, never your relationship to it" — audio (unconditional) + cover + ePub(s) + transcript/alignment sidecars; NEVER position ("don't share my location — it's a new book for them"), bookmarks, rate, or his notes; own devices are covered by cloud sync (cut twice); Dev uses a different file EXTENSION (`.skriftbookdev`), Tuur approved — src: `memory/project_book_sharing.md:15-20,30-35`, `SKRIFT_SOURCE_OF_TRUTH.md:440`
- 2026-08-11 Low Power Mode no longer stops a book transcribe; the pause policy is charge-only (pause below 20% on battery) — device-confirmed — src: `memory/project_book_sharing.md:54-58`
- 2026-08-11 "Remove transcript" lives in the Text sheet's ⋯, like removing an ePub ("in line with what is already there") — src: `memory/project_book_sharing.md:59-62`
- 2026-06-14 Capture-screen redesign (audiobooks) is DESIGN PAUSED: no code iterations on `CaptureMomentView` until a design session — src: `CLAUDE.md:198-199`

### Search / retrieval
- 2026-06-04 North star: "see how my thinking evolved over time" — semantic search across the whole archive + related notes + a timeline; LLM NARRATION of the evolution deferred until local models are good enough; Skrift feeds Obsidian, it does not replace it — src: `SKRIFT_SOURCE_OF_TRUTH.md:482`, `memory/project_overhaul.md:16`
- 2026-07-07 Embedder = EmbeddingGemma-300M via CoreML-LLM (bake-off 10/10 vs Apple NL 5/10), NOT `NLContextualEmbedding`; same model on Mac and phone — src: `SKRIFT_SOURCE_OF_TRUTH.md:438`, `memory/project_connections_panel.md:17-19`
- 2026-07-16 Connections panel: ONE list + Date⇄Closest pill; closeness = ordering + flag + hover "N% match" (never ambient); hover-✕ hide per-device — src: `memory/project_connections_panel.md:12-15`
- 2026-07-24/25 Connections is an INSPECTOR, not a matched column pair: iPad = per-note visitor sheet over the note; Mac = floating inspector that STAYS open across notes (the platforms deliberately diverge); summoned by a word-only capsule — no glyph, no count ("capped at 7 ⇒ always 7 ⇒ zero signal") — src: `memory/project_ipad_wave1.md:159-162,205-211`
- 2026-07-25 Floating panel may never hide text: `NoteMeasure` narrows the column only when the window can't afford both — Tuur chose ADAPTIVE — src: `memory/project_ipad_wave1.md:213-221`
- 2026-07-25 "View Thread" retired — Date mode IS the thread; the compact Related-card sheet KEPT on the phone (its only arc view); one arc surface per platform — src: `memory/project_ipad_wave1.md:247-251`
- 2026-07-26 Semantic linking is deliberately NOT while typing; `[[` = a searchable note picker; a future post-save Related strip promotes to a real link on tap — src: `memory/project_desktop_parity_plan.md:63-66`
- 2026-07-26 Tightness lens DESIGN AGREED (build deferred to "once we connect my Obsidian vault"): never a numeric slider; a NAMED 3-step lens beside the Date⇄Closest pill (Related .45 / Close ~.60 / Tight ~.80) with live counts, its own empty state, no looser step than .45; floors re-derived from the real corpus percentiles — src: `memory/project_ipad_wave1.md:428-440`
- 2026-07-26 Monthly digest: code selects/scaffolds with real links + verbatim quotes, Gemma writes only slot prose, invented mentions rejected; "the model never chooses" — src: `memory/project_ipad_wave1.md:377-380`
- 2026-06-06 Phone search = full-text over transcript + tags + place name; photo OCR matches in LIST search only (find-in-note is a separate 🔍) — src: `memory/feedback_native_ui_process.md:54-55`, `memory/project_note_editing_sprint.md:33-34`
- 2026-07-13 The Mac Journal reads the CLOUD Memo store (full corpus), read-only — src: `memory/project_desktop_parity_plan.md:61-62`

### Editor & note UI
- 2026-06-04 The desktop note view is an EDITOR, not a reader; WYSIWYG to the exported Obsidian markdown (brackets visible) — "what you see = what ships" — src: `memory/project_overhaul.md:16`, `memory/feedback_visual_ui_iteration.md:12`
- 2026-06-06 Memo detail is the "note" screen: optional editable title, transcript with inline image markers, playback, tags, swipe between notes — src: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:719-723`
- 2026-06-06 Memos list = ONE funnel icon for Sort & Filter (less vertical space); day-group headers; multi-select — src: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:713-718`
- 2026-06-06 Tags model: the Mac owns the vocabulary (vault tag NAMES from frontmatter only, no body scan); phone pulls the whitelist read-only; deterministic lemma match ≥ 2× + spoken `#hashtags`; suggestions only, user selects; people NOT auto-excluded — src: `memory/project_overhaul.md:25`, `memory/feedback_native_ui_process.md:59-61`
- 2026-06-07 Liquid Glass uses `.glassEffect(.clear)` (`.regular` frosts) — judge on device only — src: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:185-186`, `SKRIFT_SOURCE_OF_TRUTH.md:500`
- 2026-06-07 Karaoke renders IN the same NSTextView (no renderer swap → no reflow; click a word seeks) — src: `archive/handoffs/WALKTHROUGH_BUGS.md:32`
- 2026-06-07 Mac inline disambiguation: the banner asks "Who is X?", pick one → applied to every mention, no separate Apply; "Different people" escalates per mention — user: "perfect, it works" (later subsumed by the 2026-06-16 popover model) — src: `archive/handoffs/WALKTHROUGH_BUGS.md:43-45,55`
- 2026-07-07 Note-editing LOCKED: B2 pinned title; accessory bar = undo · redo | ☑ · 📷 · → · 🔍 · Done (⋯ removed while verbs fit); Return-continuation Notes flow; every feature ships BOTH apps with logic in `Shared/` — src: `memory/project_note_editing_sprint.md:41-45`
- 2026-07-07 Memo↔memo links: type `[[` → searchable picker → atomic chip; tap jumps the pager; "LINKED FROM" backlinks under the body; chips show the target's LIVE title — src: `FEATURES.md:44`
- 2026-07-16 Markdown headings render with dim-visible marks (LOCKED); vanish-off-caret-line REJECTED (the offset-math trap); the full bold/italic/highlight suite = roadmap i10 — src: `memory/project_intertwining_device_bugs.md:28-31`
- 2026-07-16 Inline `#` completion = a PASSIVE non-activating panel, never NSTextView's built-in completion session — src: `memory/project_intertwining_device_bugs.md:26-28`
- 2026-07-22 iPad doctrine: phone bones everywhere, Mac dress for Mac jobs, system chrome where iPadOS owns it; the Mac is the design reference when it's better; one spec, two platforms, differing by one button each way — src: `memory/project_ipad_wave1.md:50-56`
- 2026-07-24 iPad signed spec ("perfect"): two materials (sidebars `skSurface`, note `skBg`, hairline toolbar); ONE screen-pinned ◧; glass containment on bar controls; the player DOCKS at regular width (phone keeps glass) — src: `memory/project_ipad_wave1.md:152-163`
- 2026-07-25 The ⋯ menu is single-sourced (`NoteMenuItem` owns wording, glyph, ORDER; actions stay per-app; omitting is normal, renaming/reordering is drift) — src: `memory/project_ipad_wave1.md:234-242`
- 2026-07-26 Derived titles clip at a word boundary + "…" everywhere; the export FILENAME keeps the hard slice (an ellipsis would rename notes on disk) — src: `memory/project_ipad_wave1.md:296-301`
- 2026-07-27 Conversation turn gutter (E1, "way better looking"): headers move into a right-aligned gutter with per-speaker hue + spine; playback washes the live turn accent@7%; a long name TRUNCATES; the phone KEEPS its cards (no phone gutter planned); turn spacing left looser than the mock on purpose — src: `memory/project_conversation_turn_gutter.md:11-21,55-58`
- 2026-07-28 Mac ✎/⌘N typed note = a fresh unrated Memo rendered by the ordinary unrated pane (no new renderer) — src: `memory/project_note_consent.md:51-56`
- 2026-08-26 The destination row lives ON THE NOTE beside the importance circles, resting as ONE chip that expands to four; Personal = quiet chip; an archive destination names its folder and says AI READS THIS ("an always-on warning is no warning"); rejected: chip inline with the tag row, a fuzzy list mixing tags and destinations — src: `memory/project_export_destinations.md:98-105`
- 2026-06-12 Karaoke tap-to-seek default ON; capture karaoke via the 3-mode `TranscriptBodyView` — src: `memory/project_unification_backlog.md:38-40`
- 2026-07-22 iPad header = the Mac sidebar; Import IS the picker menu (Files/Photos/Scan); ⋯ = a single filter/sort icon; identity row keeps Notes + Select — src: `memory/project_ipad_wave1.md:87-103`

### Privacy
- 2026-06-04 Never point AI/agents at the user's Obsidian vault contents; only the app's own local code scans it; test with a small sample he provides — src: `memory/feedback_vault_privacy.md:10-14`, `CLAUDE.md:32-33`
- 2026-06-22 Privacy REFRAME: the rule targets cloud LLMs / big-company AI, NOT Skrift's own code — Skrift reading its own exported files or the whole vault is an engineering decision, not a privacy blocker; the dev-time rule (agents don't read his real vault) still binds — src: `archive/handoffs/OBSIDIAN_EXPORT_ALTERNATIVES.md:19-29`, `memory/project_obsidian_relationship.md:13-19`
- 2026-06-15 $0.69 one-time, NO IAP → no per-use cloud LLM is affordable → all intelligence on-device / free-Apple, "which IS the privacy story" — src: `STANDALONE_PLAN.md:28-31`
- 2026-08-26 The destination is a privacy boundary (see Export compiler): Personal notes are never read by AI; the portfolio repo `~/Hackerman/Tiurihartog.com/` is the space he lets AI read — src: `memory/project_export_destinations.md:11-13,60-64`
- 2026-08-27 The archive KEEPS `[[names]]` (public site, credit his friends) — his deliberate reversal of my privacy call — src: `memory/project_export_destinations.md:87-91`
- 2026-06-16 Roster seeding reads `People/` FILENAMES only; the tag whitelist reads frontmatter only; the tightness-lens calibration lets only percentiles leave the device — src: `NAMING_MODEL.md:64-66,246`, `memory/project_overhaul.md:25`, `memory/project_ipad_wave1.md:438-440`
- 2026-07-07 Locked notes v1 = an auth gate (Face ID / Touch ID per session), not encryption, stated in-app — src: `FEATURES.md:41`
- 2026-09-18 The test corpus is SYNTHETIC, never his notes ("the app is filled with my thoughts already… make a testing vault"); the Dev vault is `~/Hackerman/Obsidian_LLM_Test_Vault` — src: `backlog.md:606-617`
- 2026-06-07 Never screenshot the live app at a real note; `names.json` is app config (ok to read for debugging) — src: `archive/handoffs/DESKTOP_NATIVE_HANDOFF.md:284`
- 2026-06-14 `ITSAppUsesNonExemptEncryption = false` — offline + standard crypto, export-compliance exempt — src: `archive/handoffs/NEXT_CHAT_HANDOFF.md:70-71`

### Process & shipping
- 2026-06-05 Both apps rewritten as native SwiftUI; NO Python, NO Electron, NO React Native; the old apps preserved INTACT and operational under `archive/`, never gutted — src: `archive/handoffs/MOBILE_NATIVE_REWRITE_PLAN.md:3-12`, `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:524-527`, `CLAUDE.md:23`
- 2026-06-06 Desktop UI = FULL SwiftUI rebuild (Option A), a faithful port of the overhauled Electron look; WKWebView reuse rejected — src: `archive/handoffs/DESKTOP_NATIVE_HANDOFF.md:236`, `memory/project_desktop_native_arch.md:16`
- 2026-06-06 Mock-first is LOCKED process for new UI: spec all functionality → agents audit UI coverage → build → XCUITest; a signed-off mock IS the spec — src: `memory/feedback_native_ui_process.md:10-15`, `CLAUDE.md:46-48`
- 2026-06-06 Operate autonomously ("go automatic"), BUT (2026-07-22 boundary) design-shaped observations get discussed first; only explicit breakage reports get fix-waved directly — src: `memory/feedback_autonomous_execution.md:13-17`
- 2026-06-08 Dev/prod split by per-config bundle IDs: Debug = "Skrift Dev" (`com.skrift.*.dev`, inverted icon, own data, TEST vault); Release = "Skrift" (real data, real vault); never rebuild prod while in use; promote deliberately when idle — src: `CLAUDE.md:86-100`
- 2026-06-14 `main` is the trunk — src: `CLAUDE.md:169`
- 2026-06-14 TestFlight ships via the Xcode Organizer GUI; the ASC API-key CLI export fails ("Cloud signing permission error") — src: `archive/handoffs/NEXT_CHAT_HANDOFF.md:59-67`, `memory/project_testflight.md:18-26`
- 2026-06-15 $0.69 one-time, NO IAP, no free trial; full-vision v1; Apple Watch deferred (he has no Watch) — src: `STANDALONE_PLAN.md:26-33,573`
- 2026-06-17 Build/deploy: dev = CLI `xcodebuild` / Xcode Cmd-R; PROD = Xcode Organizer for BOTH apps; capabilities ALWAYS via Xcode (`-allowProvisioningUpdates` cannot add one) — src: `STANDALONE_PLAN.md:556`, `CLAUDE.md:191-197`
- 2026-06-21 Bump `CFBundleVersion` before every device/TestFlight build; take max(phone, origin/main) + 1 (two chats collided on "40") — src: `memory/feedback_device_build_version_bump.md:10-16`
- 2026-06-25 UI review uses VISION — render it and look; never review UI from source alone — src: `memory/feedback_ui_review_vision.md:10-17`
- 2026-06-12 Signing lesson: entitlement values LITERAL per-config files (a `$(VAR)` breaks CLI profile matching); App Groups + increased-memory-limit need a one-time Xcode capability visit per App ID (Release IDs still owe theirs) — src: `CLAUDE.md:191-197`, `memory/project_ipad_polish_fix.md:30-34`, `memory/project_testflight.md:49-61`
- 2026-07-16 SHARED CODE FIRST: anything living on both apps (logic, labels, constants, glyphs) is single-sourced in `Shared/` in the same change — "if I change that thing in one place, we change it in another place"; un-twin views as one shared view + per-app style struct, prove zero pixels by render-diff — src: `memory/feedback_shared_code_first.md:11-39`, `LANE_PLAYBOOK.md:29-30`
- 2026-07-16 A mock's "as-is" elements are drawn from the SOURCE, never from older mocks/memory; "your mock differs from the app" = blocking defect — src: `memory/feedback_mock_as_is_from_source.md:18-24`
- 2026-07-21 Lane batches run under `LANE_PLAYBOOK.md`: Sonnet executes, Fable conducts + judges; lanes never edit existing `Shared/`, never build, never touch hardware; new UI needs a signed mock; LESSONS append-only with Tuur's approval; reversed the 2026-06-13 "don't use the parallel-lanes skill (the user dislikes it)" — src: `LANE_PLAYBOOK.md:3-5,13-37,59-60`; older: `archive/handoffs/TEXT_CAPTURE_WAVE2_HANDOFF.md:68`
- 2026-07-21 Hardware-flavoured bugs (audio routes / BT / sensors) are diagnosed from the DEV `devlog.txt` trace first and fixed by the orchestrator, never lanes — src: `CLAUDE.md:101-109`
- 2026-06-29 `roadmap/roadmap.yaml` is the single plan source (exactly one `now`); update it in the same change as the work — src: `CLAUDE.md:143-152`, `.claude/rules/roadmap-authoring.md`
- 2026-07-27 Write for skimming: lead with the answer, tables over prose, questions last; 2026-09-21: "please don't write it super technical" — src: `memory/feedback_skimmable_output.md:11-29`
- 2026-07-28 Announce before deploy on feel loops: evidence → posted diagnosis + change + predicted feel → THEN build — src: `memory/feedback_announce_before_deploy.md:11-23`
- 2026-06-13 Don't fabricate perf numbers — measure or state unknown — src: `archive/handoffs/TEXT_CAPTURE_WAVE2_HANDOFF.md:69`
- 2026-06-18 The UNIT suite is the gate; the XCUITest suite's iOS-26 failures are deferred rot (17 failing as of 2026-08-11) — src: `STANDALONE_PLAN.md:526`, `memory/project_xcuitest_ios26_failures.md:22`
- 2026-08-11 `xcodegen generate` after EVERY new file before believing a build or test result (a file created after the last generate is not in the target; 1017 tests passed with a broken file) — src: `memory/project_book_sharing.md:22-27`
- 2026-08-12 Fresh checkouts/CI need `-skipPackagePluginValidation` + `-skipMacroValidation` — src: `memory/feedback_parallel_orchestration.md:30`
- 2026-08-30 TestFlight install 404s are Apple-side (29 builds across 5 apps force-expired in a 3-second window on 2026-08-26); do NOT burn builds, do NOT change the bundle id, do NOT set a price to "fix" it; re-distribute 167 (universal) when Apple repairs; Ad Hoc is the workaround — src: `memory/project_testflight.md:146-217`
- 2026-09-18 Spec written from INTENT, not from the code; the WHOLE project in one flow ("I don't like the start stop start stop"); any rule he doesn't confirm does NOT go into v2 — src: `backlog.md:638-643`
- 2026-09-18 Unfinished-work policy: built-on-main-owed-eyeball → NOT rebuilt, clauses marked unverified, eyeballs in the `[tuur]` lane; approved-mock-nothing-built (audiobook reading mode, rest of journal-desktop, picture drag-reposition, Mac thumbnails, place/tags chips) → spec done-states with the mock as the clause, built later, anything on a rewrite target waits for that subsystem's v2; land `claude/testflight-install-failure-c89268`, ignore the six June/July leftovers — src: `backlog.md:661-675`
- 2026-06-09 Effort calibration: no research harnesses for casual questions ("this is too crazy. not necessary") — src: `memory/feedback_effort_calibration.md:10-14`
- 2026-06-15 Never run two "Skrift Dev" instances (they race the shared store); deploy desktop as build → pkill → ditto → open `/Applications/Skrift Dev.app` — src: `memory/feedback_desktop_dev_deploy.md:10-30`

### Other
- 2026-06-05 Metadata captured per recording: location (reverse-geocoded place), weather, pressure, daylight/day period, steps; the Mac consumes them into frontmatter; 2026-08-26 the Mac writes `location:` for recordings only, never imports — src: `SKRIFT_SOURCE_OF_TRUTH.md:322`, `memory/project_export_destinations.md:37-40`
- 2026-06-05 Names DB = `names.json` with LWW + tombstones + `voiceEmbeddings` union carried straight from the Python era; `names.json` byte-compatible forever — src: `SKRIFT_SOURCE_OF_TRUTH.md:90-91,513`
- 2026-06-08 "See how my thinking evolved" (north star) is DEFERRED by the user — "needs a lot of thinking first"; don't start without a design pass — src: `archive/handoffs/DESKTOP_NATIVE_HANDOFF.md:61`
- 2026-06-07 Substitutions (deterministic synced find/replace for misheard jargon) PARKED, needs his go-ahead; dictate-anywhere keyboard = deferred big bet, not chosen — src: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:899-907`
- 2026-06-05 The user speaks an English/Dutch mix; models must handle both; "no NL→EN translation / no meaning change" is a polish gate — src: `memory/user_language.md`, `STANDALONE_PLAN.md:315`
- 2026-06-04 Cut for good: the ask-a-question chat, export preview, LLM tagging, LLM significance, the `[[Name]]` bracket-preservation hack — src: `memory/project_overhaul.md:26`, `SKRIFT_SOURCE_OF_TRUTH.md:78-80`

---

## B. MECHANICAL CONTRACTS

### Body/image model
- [mechanical] Image marker literal is `[[img_NNN]]` (3-digit), inserted at the word whose start time is closest to the photo's `offsetSeconds` (ascending); `transcriptMarkersInjected = true` stops the Mac re-injecting — src: `archive/handoffs/MOBILE_NATIVE_REWRITE_PLAN.md:207-210`
- [mechanical] Capture today drops `\n\n[[img_NNN]]\n\n` at the END of the nearest word (mid-sentence); a shared picture has no time → offset 0 → lands after the first word (the known bug) — src: `backlog.md:678-684`
- [mechanical] Photo files `photo_{memoId}_NNN.jpg`; `imageManifest = [{filename, offsetSeconds}]`; offsets exclude paused time — src: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:50-55`
- [mechanical] Copy-edit strips markers keeping 6 words either side as anchors, re-finds them in the model output, degrades to 1-word then proportional (`ImageMarkerReinsert`) — src: `backlog.md:685-687`
- [mechanical] Display snap (`BodyTransform.snapImages`) moves each marker to its sentence end at render time with a `SnapResult` segment map; both renderers collapse the 11-char marker to a 1-char glyph with a second remap; export runs the snap again — src: `backlog.md:688-693`
- [mechanical] Export rewrites `[[img_NNN]]` → `![[<Title>_NNN.<ext>]]` and copies the image (title-derived unique names) — src: `archive/handoffs/DESKTOP_NATIVE_HANDOFF.md:28`, `archive/handoffs/WALKTHROUGH_BUGS.md:48`
- [mechanical] A viewfinder exists only inside a recording (`CameraSheet` from `RecordView`); every in-app photo rides a voice note; the only wordless path is sharing an image in — src: `memory/project_export_destinations.md:93-96`
- [mechanical] SwiftData traps on a Codable-struct `@Model` attribute → complex values persist as JSON `Data?` blobs (`Memo.metadata`, `sharedContent`, `PipelineFile.audioMetadataJSON`) — src: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:56-61`
- [mechanical] `MemoNoteProjection` maps through `MemoCloudIngest.metadataJSON` (the exact blob a real ingest writes) — faithful, bugs included; known: `durationSeconds` parses an HMS string while the blob writes a Double, so synced notes show no duration chip on the Mac — src: `memory/project_ipad_wave1.md:271-277`

### Copy-edit (Mac polish)
- [mechanical] Prompts = `AppSettings.Prompts.defaultCopyEdit/Title/Summary` (verbatim from the Python `settings.py`); summary is skipped for short notes (summary gate) — src: `archive/handoffs/DESKTOP_NATIVE_HANDOFF.md:145`, `SKRIFT_SOURCE_OF_TRUTH.md:167,315`
- [mechanical] Model = `mlx-community/gemma-4-e4b-it-8bit`, revision-pinned via `PolishPrompts.defaultModelRevision` (HF `main` drifted); mlx-swift-lm ≥ `e6e3de75`, mlx-swift 0.31.6; `MLX.withErrorHandler` scoped so faults throw instead of `fatalError` — src: `memory/project_ipad_polish_fix.md:14-28`
- [mechanical] 8.88 GB on iPad needs `com.apple.developer.kernel.increased-memory-limit` — src: `memory/project_ipad_polish_fix.md:30-32`
- [mechanical] `MemoEnhancement { memoID, copyedit, title, summary, compiledMarkdown, enhancedByDeviceID, enhancedAt, processedAt }`; loose `memoID` FK; LWW by `enhancedAt`; `isProcessed` in Shared — src: `archive/handoffs/MAC_CLOUDKIT_PLAN.md:177-179`, `memory/project_export_destinations.md:80-81`
- [mechanical] Body precedence on the Mac: sanitised → copyedit → transcript; the phone keeps RAW in `Memo.transcript` and re-derives links on demand — src: `archive/handoffs/DESKTOP_NATIVE_REWRITE_PLAN.md:88-90`, `CHANGELOG.md:36-37`
- [mechanical] Desktop copy-edit output is wrapped in `QuoteProtection` + `ImageMarkerReinsert`; the Sanitiser call is source-agnostic (trusted phone transcript or Mac ASR) — src: `STANDALONE_PLAN.md:102`, `archive/handoffs/DESKTOP_NATIVE_HANDOFF.md:39`
- [mechanical] Paragraph ledger log line: `category == "paragraphs"`, `in N → model N → shipped N` — the promotion marker for non-greppable fixes (Swift inlines ≤ 15-byte literals) — src: `memory/project_rate_to_row.md:51-56`
- [mechanical] Filler strip is opt-in and memos-only (never book prose) — src: `memory/project_audiobook_player.md:57`

### Reconcile sweep
- [mechanical] `PipelineFile.id == Memo.id.uuidString` for synced memos; audio filename `memo_<uuid>.m4a` embeds the UUID; dedup by UUID OR filename collapses one memo to one row — src: `archive/handoffs/MAC_CLOUDKIT_PLAN.md:26-30,111-113`
- [mechanical] A Mac take's `memo_<uuid>.m4a` names the AUDIO file, not the Memo (authored under the row `id`) — `resolve(for:in:)` asks the store which candidate exists — src: `memory/project_mac_recording.md:76-80`
- [mechanical] Mac reconciles only at launch + `NSApplication.didBecomeActive` (click the window before diagnosing "isn't syncing"); DEBUG hook `-poke-sweep <sec>` — src: `memory/project_ipad_wave1.md:32-35`, `memory/project_lifecycle_one_clock.md:25`
- [mechanical] Phone→Mac update path: `MemoCloudUpdate` + `MemoCloudReconciler.sweep` (`SweepOutcome`) + `PipelineFile.syncedSourceEditedAt` watermark — src: `archive/handoffs/LIVE_SYNC_HANDOFF.md:15-17`
- [mechanical] Mac→phone edit path: `MacCloudEditSync` debounced write-back via `MacCloudWriteBack.upsert(bodyOverride:)` + `Sanitiser.unlinkToSpoken`; projections (nil `modelContext`) are skipped — src: `archive/handoffs/LIVE_SYNC_HANDOFF.md:13-15`, `memory/project_ipad_wave1.md:265-267`
- [mechanical] `MacMemoAuthor.author()` infers user-edited from "transcript already present on a fresh local recording"; the seed ORDERING (edited path seeds in `onCreated`, unedited inside the transcribe hook) is a contract — src: `memory/project_live_transcription.md:23-27`
- [mechanical] Headless verbs (quit the GUI first): `-runfile <audio> [-transcript] [-vault]`, `-recordingest`, `-ratetorow`, `-trashfile`, `-ratefile`, `-vaultexport`, `-turncheck`, `-voiceloop`, `-snapshot*` — src: `memory/project_mac_recording.md:88-89`, `CLAUDE.md:76-78`

### Export compiler
- [mechanical] Vault stamp = frontmatter `skriftID` · `skriftHash` · real `lastTouched` — a PUBLIC contract for the plugin; Obsidian Bases can table Skrift notes today (`skriftID exists`) — src: `FEATURES.md:70`, `memory/project_ipad_wave1.md:322-325`
- [mechanical] `people:` frontmatter = the DISTINCT canonical wiki-links in the rendered body, reading order, image markers excluded, `[[A|x]]` resolved to `[[A]]`, known persons only, conversations include matched speakers; empty when nobody is linked — src: `FEATURES.md:347`
- [mechanical] Memo link raw syntax `[[memo:UUID|Title]]` (`Shared/Model/MemoLinkSyntax.swift`); export rewrites to a precise `[[<stem>|Title]]` via the frozen export path, else `[[Title]]`; the raw keeps the title snapshot as fallback, display shows the LIVE title — src: `FEATURES.md:44`
- [mechanical] Foreign-file collision → deterministic `<stem> <id8>.md`; pre-stamp legacy file → blocked with NO twin; vault-edited → backed off, their version wins — src: `FEATURES.md:70`
- [mechanical] Significance in YAML rounded to 0.1 (`%.1f`) — src: `archive/handoffs/WALKTHROUGH_BUGS.md:50`
- [mechanical] Capture export: url → link block (title + URL) above the body + `url:` frontmatter; text → blockquote above; image → `![[filename]]` above; `source: capture-url|capture-text|capture-image` (Obsidian profile; the ARCHIVE profile writes `capture:` instead) — src: `Skrift_Native/CAPTURE_CONTRACT.md:111-118`, `memory/project_export_destinations.md:14-15`
- [mechanical] Obsidian profile layout: title-derived stems, `Images/` + `Recordings/` subfolders, `![[wiki embeds]]`; archive = a SECOND output profile (`ExportProfile`), flat + named, `![](file)` links; a destination is a per-device folder bookmark (no Mac dependency) — src: `memory/project_export_destinations.md:106-111`, `FEATURES.md:68`
- [mechanical] Export ledger is per picked folder (`ExportLedger.default(for:)` keys on the destination folder); a fresh ledger ADOPTS its own stamped file (how two devices share one vault) — src: `memory/project_ipad_wave1.md:327-328`
- [mechanical] `MemoExporter.exportTitle` keeps the hard `prefix(80)` slice (filename stability); `author:` is a parameter (the phone had no "your name" setting) — src: `memory/project_ipad_wave1.md:298-299`, `memory/project_standalone_app_store.md:213`
- [mechanical] Quote export string `> — [[Author]], *Book*, ch. N`; C2 book metadata `bookTitle` / `bookAuthor` / `bookChapter` ride the memo metadata; absent = old behaviour — src: `SKRIFT_SOURCE_OF_TRUTH.md:519`

### Ingress (share/import)
- [mechanical] C3 discriminator: zero audio parts + `metadata.sharedContent` present; phone-side a `Memo` with `audioFilename == ""`; Mac-side `sourceType == .capture`; `sharedContent` keys `type ("url"|"text"|"image"|"file")`, `url`, `urlTitle`, `urlDescription`, `urlThumbnailUrl`, `text`, `fileName`, `mimeType` (`Shared/Model/SharedContent.swift`, goldens in both suites; unknown `type` decodes to nil) — src: `Skrift_Native/CAPTURE_CONTRACT.md:27-50`
- [mechanical] Capture metadata: `annotationText` optional; `source: "mobile"`; `duration: 0`; `tags: []` v1; `title` absent v1; context fields absent v1; trust flags irrelevant (the desktop capture branch must not consult them) — src: `Skrift_Native/CAPTURE_CONTRACT.md:51-63`
- [mechanical] Mac capture ingest: `transcript = annotationText ?? ""`, `transcribeStatus = .done` (never run ASR); empty annotation → title falls back to `urlTitle` / snippet head / image filename — src: `Skrift_Native/CAPTURE_CONTRACT.md:101-110`
- [mechanical] Share extension `SkriftShare` writes an inbox entry (JSON + optional file) into the App Group (`group.com.skrift.mobile` / `.dev`); the main app drains on launch/foreground → `Memo`; a devicectl-created inbox file is immutable to the app (never `copy to` into app-group paths) — src: `Skrift_Native/CAPTURE_CONTRACT.md:126-131`, `memory/reference_xcodebuild_silent_auth_stall.md:12`
- [mechanical] `SkriftShare` lists its `Shared/` sources per FILE in `project.yml` — a new Shared file the extension needs is added by hand — src: `memory/feedback_shared_code_first.md:41-44`
- [mechanical] Video import: `NSExtensionActivationSupportsMovieWithMaxCount` + a `"video"` inbox entry → `CaptureInboxDrainer` → `MemoSaver.importVideo` (audio stripped, temp movie discarded) — src: `archive/handoffs/NEXT_CHAT_HANDOFF.md:36-38`, `memory/project_export_destinations.md:49-51`
- [mechanical] PDF share → `.file` capture; `MemoAsset.Kind.document` is additive (the doc blob did not sync before 3b) — src: `SKRIFT_SOURCE_OF_TRUTH.md:186`, `memory/project_desktop_parity_plan.md:30-31`
- [mechanical] Mixed share (8 audios + 1 picture) → ONE note; a multi-audio WhatsApp thread imports chronologically — src: `backlog.md:622-626`
- [mechanical] Recording file `memo_{uuid}.m4a`; `Memo.audioURL` resolved at runtime (no absolute paths); ISO8601 timestamps match JS `toISOString()` — src: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:636-641`
- [mechanical] Apple-Notes import: `#` heading → title; inline hashtags → YAML frontmatter (Era-1 behaviour carried forward) — src: `archive/handoffs/DESKTOP_NATIVE_HANDOFF.md:28`, `SKRIFT_SOURCE_OF_TRUTH.md:73`

### Names & sanitise
- [mechanical] `names.json` per-entry `{canonical: "[[Name]]", aliases: [], short, voiceEmbeddings?: [], lastModifiedAt, deleted?}`; per-canonical LWW; `voiceEmbeddings` UNION; tombstones pruned after 90 days; CloudKit `NamesRecord` carrier merged via the same `NamesMerge.mergeByCanonical`; duplicate carriers collapse — src: `archive/handoffs/MOBILE_NATIVE_REWRITE_PLAN.md:197-202`, `STANDALONE_PLAN.md:521`
- [mechanical] `VoiceEmbedding { vector: [Double], condition: String?, addedAt: String? }` (map FluidAudio `[Float]`); never average embeddings — max-cosine over the stored list — src: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:639-640`, `memory/project_mobile_overhaul.md:21`
- [mechanical] Match threshold override `UserDefaults("voiceMatchThreshold")`; embedder window `minSamples` 32k (2 s), `maxSamples` 160k (10 s) — src: `archive/handoffs/CONVERSATION_MODE_HANDOFF.md:30,85`
- [mechanical] Legacy `names.json` shapes: `short: "None"` literal, no-timestamp entries (the store once read 0 people) — decode leniently — src: `archive/handoffs/DESKTOP_NATIVE_HANDOFF.md:273`, `memory/project_desktop_native_rewrite.md:25-26`
- [mechanical] On add, a person's alias list must seed from the name (the shared `Sanitiser` matches only by `p.aliases`; empty aliases = never recognised) — src: `SKRIFT_SOURCE_OF_TRUTH.md:338`
- [mechanical] Link identity is pipe-aware: `Sanitiser.linkTarget` / `hasCanonicalLink` / `linkDisplay`; unlink/relink restore the spoken word — src: `memory/project_conversation_namelinking.md:21`
- [mechanical] Sanitiser tiers: full name OR distinctive first name auto-commits; `NameStoplist` common-word / ≤ 2-char single name / alias shared by 2+ people → `AmbiguousOccurrence` suggestion (`candidates.count == 1` common-word, `≥ 2` ambiguous); capitalisation FP-guard ("I will call" plain, "Will came over" suggests); `nonProseRanges` skips YAML / code / audiobook-quote — src: `NAMING_MODEL.md:232-244`
- [mechanical] Per-note `namePicks` (alias → canonical FORCE-LINK; `""` = silence) + `unlinkedNames` (prune → suggest); overrides pre-computed in one `Overrides` struct; `RosterAudit.newlyAmbiguous` re-derives affected memos when a twin is added — src: `NAMING_MODEL.md:267-288`
- [mechanical] `SpeakerTranscript.parse` / `parseWithPreamble` / `mergeAdjacentTurns` line-anchored; `isAttributed` requires ≥ 2 DISTINCT speakers (kills `**Pros:**`/`**Cons:**`) — src: `memory/project_conversation_namelinking.md:22`
- [mechanical] Custom vocab: terms parsed `"Canonical: alias1, alias2"` (entries split on `;` in `-runfile -vocab`); `VocabularyTrust` floor 0.55; env knobs `SKRIFT_VOCAB_CBW` / `MINSIM` (DEBUG) — src: `memory/project_vocab_booster.md:32-38`
- [mechanical] ASR post-process ORDER is load-bearing (`Shared/Pipeline/ASRPostProcess.finish`): phantom guard first; vocab rescore BEFORE markers; re-align AFTER the rescore; `mergeBPETokens` starts a word on a leading SPACE — src: `memory/project_ipad_wave1.md:385-392`

### Consent / rating / lifecycle
- [mechanical] `Memo.significance` = non-optional Double, 0 = unrated, snap 0.1; `PipelineFile.significance` nil = three meanings resolved only in `NoteConsent+PipelineFile`; reading nil as 0 anywhere else silently un-rates every Mac import — src: `memory/project_note_consent.md:20-25`
- [mechanical] Conveyor: 30 d quiet → 30 d fading → 14 d Recently Deleted → gone; fade anchor `max(recordedAt, keptAt)`; `MemoLifecycle.trashClockStart(deletedAt:seenAt:)` is the one purge validity rule; migration runs BEFORE `FadingSweep` in the same launch — src: `memory/project_lifecycle_one_clock.md:13,25,27`
- [mechanical] `markEdited()` is THE phone touch tracepoint (bumps `keptAt`); `MemoNoteProjection.writeBack` calls it for content edits, rating-only changes don't — src: `memory/project_lifecycle_one_clock.md:27`, `memory/project_note_consent.md:56-59`
- [mechanical] `WayOutRules.unpipelined` = "has no PipelineFile row"; `ProcessPile` (waiting = rated + not-yet-enhanced; unrated = waits on Tuur; provably disjoint); `NoteConsent.joinsConnectionsIndex` (live + rated); `ConnectionsPanelLogic.canSummon` (rated && !locked) — src: `memory/project_ipad_wave1.md:76-80,268-270`, `memory/project_note_consent.md:27-37`
- [mechanical] Fading shelf badge = unread semantics (lit only for fade entries newer than the last shelf visit, per-device stamp) — src: `memory/project_note_lifecycle.md:46-48`
- [mechanical] Lock: `Memo.locked` synced; `Shared/Session/LockGate` keyed by memo UUID string; backgrounding re-locks; the Mac's Lock/Unlock exists only on Review-side unrated `Memo` rows, an open `PipelineFile` has no lock affordance — src: `FEATURES.md:41`, `memory/project_ipad_wave1.md:243-246`

### Sync contract
- [mechanical] CloudKit containers `iCloud.com.skrift.mobile` (Release) / `.mobile.dev` (Debug), private database; phone schema `[Memo, MemoAsset, MemoEnhancement, NamesRecord, VocabularyRecord, AudiobookSyncRecord, AudiobookAsset(dead)]`; Mac 2nd client over `[Memo, MemoAsset, MemoEnhancement]`, its local `PipelineFile` store pinned `cloudKitDatabase: .none` — src: `SKRIFT_SOURCE_OF_TRUTH.md:522`, `archive/handoffs/MAC_CLOUDKIT_PLAN.md:21-25,46-52`
- [mechanical] CloudKit forbids `@Attribute(.unique)` (dropped on `Memo.id`, uniqueness enforced in-app) and `.externalStorage` on synced attrs; `MemoAsset { memoID, kind, filename, byteCount, blob: Data }` plain Data (>~1 MB auto-promotes to CKAsset), loose FK, blob in its own row; kinds include audio, photo, `wordTimings`, `diarization`, `document` — src: `STANDALONE_PLAN.md:516-520`, `memory/project_desktop_parity_plan.md:30-31`
- [mechanical] `AssetMaterializer` (idempotent, both directions, launch + foreground + CloudKit import-complete): synced blob → `recordings/<filename>` never clobbering; disk → asset incl. refresh-on-append by `byteCount` — src: `STANDALONE_PLAN.md:519,537`
- [mechanical] Sidecar filenames `wt_<id>.json` (word timings), `diar_<id>.json` (diarization incl. per-turn `turnSlots`); stores expose one `filename(for:)` — src: `STANDALONE_PLAN.md:520`, `memory/project_conversation_namelinking.md:37-38`
- [mechanical] Schema is additive-only; renaming a `@Model` type renames the CloudKit record type (orphaned rows); dropping a synced `@Model` risks a load `fatalError` (`AudiobookAsset` kept dead until a prod dev-env reset); prod needs "Deploy Schema Changes" in the CloudKit Dashboard — src: `STANDALONE_PLAN.md:250,490`, `memory/project_ipad_wave1.md:397-398`
- [mechanical] Raw-CloudKit audiobook transfer: `AudiobookAudio` CKRecord + `CKAsset(fileURL:)` in the private-DB DEFAULT zone; recordNames `ab_<bookID>_<index>` / `_cover` / `_t<i>` (transcript) / `_al<n>` (alignment); fetch by id only (no queryable index, no `CKQuerySubscription`); the carrier's `audioUploadedAt` stamp is the push trigger; byte-weighted determinate %; Wi-Fi only (`allowsCellularAccess = false`) — src: `STANDALONE_PLAN.md:477-492`, `memory/project_epub_alignment.md:40-42`
- [mechanical] Audiobook position/rate LWW by `Audiobook.modifiedAt`; receiver re-stamps the transcript signature (`<size>:<mtime>`) to its own audio (`BookTranscriptStore.restampTranscripts`, the ONE re-stamper); `Remove download` is a per-device UserDefaults marker — src: `memory/project_standalone_app_store.md:112-115,152-158`, `memory/project_book_sharing.md:42-46`
- [mechanical] Silent push: iOS `remote-notification` background mode; macOS `aps-environment` + `registerForRemoteNotifications` (32-byte token verified) — src: `archive/handoffs/MAC_CLOUDKIT_PLAN.md:219-222`, `memory/project_standalone_app_store.md:101-103`
- [mechanical] `Memo.recordingDeviceID` + `DeviceID`: a receiver never re-transcribes another device's `.transcribing` memo — src: `memory/project_standalone_app_store.md:105-106`
- [mechanical] Carrier pattern for JSON/file-backed stores (names, vocab, language): a CloudKit `@Model` carrier + a main-actor reconciler that merges both ways on launch/foreground, gated on change — src: `memory/project_standalone_app_store.md:95-98`
- [mechanical] `Memo` core (`SyncStatus`/`TranscriptStatus`/`TrashPolicy`, `addedAt`, `lastEditedAt`, `markEdited`, `parseTagInput`) lives in `Shared/Model/Memo.swift` with a blob-based init; iOS coupling in `Memo+Mobile.swift`; typed call sites use `Memo.make(…)` — src: `archive/handoffs/MAC_CLOUDKIT_PLAN.md:13-20`
- [mechanical] `PipelineFile ⇄ Memo` mirror is declared once (`MirroredNoteFields`); `Memo.title` optional phone-set title, preferred over the LLM title in the chooser — src: `memory/project_export_destinations.md:52-54`, `archive/handoffs/MOBILE_NATIVE_REWRITE_PLAN.md:188-189`
- [mechanical] `NSPersistentCloudKitContainer.eventChangedNotification` is start/done only (no %) — src: `STANDALONE_PLAN.md:478-479`

### Recording & audio
- [mechanical] Engines: Parakeet TDT v3 (FluidAudio, pinned `7f963cdc` → later v0.15.5 both apps), Sortformer v2.1 (diarization), wespeaker (embeddings), CTC 110M (vocab spotter); the sim has no ANE — seed transcripts (`-seedTranscript`, `SeededDiarizer`, `SeededEmbedder`) — src: `SKRIFT_SOURCE_OF_TRUTH.md:276,359`, `memory/project_epub_alignment.md:102-105`, `archive/handoffs/CONVERSATION_MODE_HANDOFF.md:222`
- [mechanical] Parakeet v3 emits full punctuation on both apps (FluidAudio's "no punctuation" claim is wrong); seam damage ~1 per 4.5 h — src: `memory/project_epub_alignment.md:102-105`
- [mechanical] `ASRLanguageMode` owns the setting key + `melChunkContext` derivation (English = mel on, Multilingual = mel off); adopting a remote value drops the loaded ASR manager — src: `memory/project_ipad_wave1.md:393-402`
- [mechanical] Live caption engine is ONE shared `Shared/Recording/LiveCaptionEngine.swift` (phone's rotation/pacing verbatim, per-owner `rotationInterval`, `pollDelay` floor param) — src: `memory/project_live_transcription.md:31-36,66-68,107-109`
- [mechanical] `Shared/Recording/RecordingCore.swift` = encoder settings, `memo_<uuid>.m4a`, ×12 level scale, rolling `Meter`, `m:ss` label; `Engines/MacRecorder.swift` = the platform half (no `AVAudioSession` on macOS) — src: `memory/project_mac_recording.md:93-97`
- [mechanical] iOS stops the mic at the START of a route transition and posts the notification at its END — the honest capture-hole metric is file duration vs wall-clock, with word-timings as proof — src: `memory/project_audio_session_round.md:13`
- [mechanical] Cold-AirPods latency = the A2DP→HFP flip INSIDE `engine.start()` (~969 ms), recurring per recording because stop deactivates the session — src: `memory/project_audio_session_round.md:15`
- [mechanical] DEV builds write `Documents/devlog.txt` (`DevLog.log`, ring-buffered, DEBUG-only; no such file in a Release/TestFlight container) — src: `CLAUDE.md:101-105`, `memory/project_testflight.md:63-70`
- [mechanical] Diarization `SpeakerFusion`: word → speaker by segment cover, turn grouping, ≤ 1-word island smoothing; per-turn `turnSlots` in the sidecar make rename/enroll slot-aware — src: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:266-268`, `memory/project_conversation_namelinking.md:37-38`
- [mechanical] Live-caption metadata: `[photo N]` inline in the caption; 40-bar waveform; 0.6 s caption polling; live-transcription toggle — src: `SKRIFT_SOURCE_OF_TRUTH.md:244-246`

### Audiobooks
- [mechanical] `BookTranscript` sidecar per book (`Documents/audiobooks/<id>/`), time basis = (fileIndex, file-local time); a quote span never crosses a file boundary; `FileTranscript.currentSchema` 2 (invalidated drifted sidecars); alignment sidecars `alignment_f<n>.json`, schema 5 — src: `archive/handoffs/TEXT_CAPTURE_WAVE2_HANDOFF.md:32`, `memory/project_audiobook_player.md:30`, `memory/project_epub_alignment.md:22-23`
- [mechanical] `BookTranscriptionJob` is a SINGLETON (read `savedProgress(for: book)` per book); 180 s in-memory PCM chunks; capture/pause/battery cancel the in-flight chunk; resumable from the last saved boundary — src: `memory/project_epub_unified_text_sheet.md:26-30`, `memory/project_audiobook_player.md:52-55`
- [mechanical] `Audiobook.detectedChapters` `[]` = ran-found-nothing, nil = not yet (reset to nil, never `[]`, to re-try); `effectiveChapters` = detected > embedded/file-synth — src: `memory/project_audiobook_player.md:49-51`, `memory/project_book_sharing.md:61-62`
- [mechanical] Alignment core: anchors → LIS → banded DP; exact per-word times carried (never re-spread linearly); the MONOTONIC fraction, not coverage, discriminates a wrong book; adjacent same-file EPubBlocks merged before aligning; verdict-gate every chapter derivation — src: `memory/project_epub_alignment.md:44-47,83-92,98-101`
- [mechanical] `.skriftbook` = ZIP (ZIPFoundation, audio stored `.none`, JSON deflated); `BookBundleManifest` + `BookBundleRules` hold every decision; the book `id` survives so a re-import says "already in your books"; duration text = `BookTextDisplay.durationText` ("28 h 04") — src: `memory/project_book_sharing.md:36-41,35-36`
- [mechanical] Removing a transcript posts `BookTranscriptStore.transcriptRemovedNotification` so readers drop their decoded copy — src: `memory/project_book_sharing.md:63-69`
- [mechanical] Read-along: interpolate the playhead between 0.5 s AVPlayer ticks; advance at the line's END; `ReadAlongView.lead` (0.3 s) is the one tuning dial; sentence split via `NLTokenizer(.sentence)` — src: `memory/project_audiobook_player.md:32-36`, `memory/project_conversation_namelinking.md:40-41`

### Search / retrieval
- [mechanical] Embedding index floors calibrated 2026-07-07 from random-pair percentiles p50 .31 / p90 .49 / p99 .81 (`EmbeddingIndex.swift:19`); related floor 0.45; `JournalIndexService` excludes `significance == 0` at index time — src: `memory/project_ipad_wave1.md:439-440,357-358`
- [mechanical] `RetrievalGate` names the model phases ("Preparing model…" for the ~2 min ANE compile on A15; "Finding…" for a cold first query, never a false "No connections yet"); embedder yields while `TranscriptionActivity` is set — src: `memory/project_connections_panel.md:23-26`, `memory/project_intertwining_device_bugs.md:18-19`
- [mechanical] Thread/Date mode = same query, same 0.45 floor, oldest-first, first mention; the rail caps at 7 until "Show all" — src: `memory/project_ipad_wave1.md:247-249`
- [mechanical] `ConnectionsPanel.width` is one constant; `NoteMeasure` (pure) — column identical-to-closed when note area ≥ 1380, 320 pt floor yields — src: `memory/project_ipad_wave1.md:215-219`

### Editor & note UI
- [mechanical] Mobile design tokens: bg `#0f1117`, surface `#181a23`, elev `#1e2130`, text `#e4e4e7`/`#8b8b97`/`#55556a`, accent `#7c6bf5`, green `#34d399`, amber `#f59e0b`, red `#ef4444`; continuous corners (cards 16, sheets 24); one spring `.spring(response:0.35,dampingFraction:0.85)`; Dynamic Type, only the timer custom — src: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:673-685`
- [mechanical] Naming tier colours: linked `#9d8ff7` solid (`Theme.nameLink`), suggested tan `#bda481` + dotted `#ab9676` (`Theme.nameSuggest`), plain default; first mention only — src: `NAMING_MODEL.md:125-130`
- [mechanical] Speaker turn hues from `Shared/Pipeline/SpeakerTurnStyle.swift`; a gutter attachment stands for MODEL words (`**[[Tiuri Hartog]]:**` = two) — `BodyTextView.Coordinator.modelWordIndex` translates click → seek — src: `memory/project_conversation_turn_gutter.md:25-31,47-48`
- [mechanical] Rules shared in `Shared/Pipeline/BodyMarkdown.swift` + `TagComplete.swift`; `BodyTransform.snapImages`; `NoteTitle.clip` (word boundary + "…"); `SharedCopy` (processVerb, importVerb, searchPlaceholder, emptyTitleFallback); `SkMotion`; `Palette` with explicit `DriftedPair`s — src: `memory/project_intertwining_device_bugs.md:29`, `memory/project_ipad_wave1.md:192-195,211-212,296-300`
- [mechanical] Phone conversations render in `SpeakerTurnsView` (cards), NOT `NoteBodyView` — src: `memory/project_conversation_turn_gutter.md:39-40`
- [mechanical] `TranscriptEditor` / `NoteBodyView` = self-sizing UITextView with inline image attachments, writes back reconstructing markers, flags `transcriptUserEdited`; commit target pinned at first dirty edit (`markDraftDirty`) — src: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:189-192`, `memory/project_p0_enhancement_clobber.md:13-21`
- [mechanical] Live SwiftData store on the phone is the APP-GROUP container (`group.com.skrift.mobile.dev/Library/Application Support/default.store`) — src: `memory/project_p0_enhancement_clobber.md:29-32`

### Privacy
- [mechanical] Metadata weather comes from an OpenWeatherMap REST call with the user's own API key (pressure from the same response) — src: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:62-64`
- [mechanical] Locked notes: sync continues, Obsidian publish refused, Copy gated behind auth — src: `FEATURES.md:41`

### Process & shipping
- [mechanical] Builds: mobile `xcodebuild test -scheme SkriftMobile -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build` (unit gate `-only-testing:SkriftMobileTests`); desktop `UnitTests` scheme (host-less, MLX-free) + full `-skipMacroValidation`; Release desktop needs `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` — src: `CLAUDE.md:52-70`
- [mechanical] Device: build with UDID `00008110-001208C902EA201E` (`devicectl` wants `A9195A77-…`); verify freshness via `.debug.dylib` date + `nm`/literal grep; desktop promotion needs `-derivedDataPath build` and a string-grep of the deployed binary — src: `memory/feedback_device_build_udid.md:10-39`, `CLAUDE.md:71-75`
- [mechanical] Bundle IDs `com.skrift.mobile{,.share,.widget}` / `.dev` variants; App Groups `group.com.skrift.mobile{,.dev}`; team `9W82X49JZS`; ASC app id `6780161319` — src: `Skrift_Native/CAPTURE_CONTRACT.md:126-127`, `memory/project_testflight.md:13-16,41`
- [mechanical] `CFBundleVersion` lives in `project.yml` only (plists generated); latest known builds: phone 164 (export destinations), TestFlight 166–169 — src: `memory/project_testflight.md:88-92`, `memory/project_export_destinations.md:42-45`
- [mechanical] Ledgers: `backlog.md` (working ledger), `FEATURES.md` (feature matrix), `CHANGELOG.md`, `BUGS.md` (open bugs, worst first), `roadmap/roadmap.yaml`, SSOT (citation index over `archive/handoffs/`) — src: `README.md:19-31`
- [mechanical] Mock vision-check on this Mac: no Chrome — WKWebView Swift snapshot script hosted in an `NSWindow`; hosted `-snapshot-*` (NSHostingView) for anything with system controls, since plain `ImageRenderer` is blind to `glassEffect`, `Menu`, Pickers, ScrollViews — src: `memory/reference_mock_vision_check.md`, `memory/project_ipad_wave1.md:222-232`

---

## C. NEEDS-VERDICT

### Body/image model
- The v2 invariant "a picture is always its own paragraph" is a PROPOSAL (capture snaps to the sentence end at birth; old notes normalised once at write; snap layer + `SnapResult` deleted; anchors → strip image paragraphs / copy-edit / reinsert by paragraph index; export stops transforming) — only the shared-picture-to-TOP half carries his verdict — src: `backlog.md:694-700`
- Where a timed photo lands when its word is mid-sentence: the 2026-04-13 rule said "nearest sentence boundary", the shipped capture code drops it after the nearest WORD — confirm sentence end (the proposal) — src: `memory/project_photo_capture.md:15`, `backlog.md:678-681`
- Migration of old notes (stale `ambiguousNames` offsets → re-sanitise once) and whether the one-time normalise runs at read or at sync arrival — src: `backlog.md:697-700`
- Picture drag-to-reposition (approved mock, nothing built) = "move a block" AFTER body v2 — confirm it stays in scope — src: `backlog.md:667-670,700`

### Copy-edit (Mac polish)
- 4c "Clean up my ramble" output presets (note / bullets / email / to-do) is still a planned phase, but the 2026-06-15 lock says "NO invented modes" — which one holds? — src: `STANDALONE_PLAN.md:323-325` vs `:419-420`
- Summary quality ("reads stale / not in my voice") — a prompt-tuning pass was deferred, gated on local-model quality; does v2 copy-edit own it? — src: `SKRIFT_SOURCE_OF_TRUTH.md:368`
- Context-aware enhancement (one-line place/weather/people context into title/summary prompts) is listed as a product idea, against his own caution not to feed sensor context to the small model — src: `archive/handoffs/DESKTOP_NATIVE_HANDOFF.md:170,177`
- On-device polish spike (P4a) on the real iPhone 13 never ran; the iPhone 13 RAM variant (4 vs 6 GB) is unconfirmed; is phone polish still wanted at all now the iPad polishes? — src: `SKRIFT_SOURCE_OF_TRUTH.md:425-431,598`
- Karaoke-after-edit on the Mac (an edited take needs a timings-only file pass first) — parked — src: `memory/project_live_transcription.md:132-133`
- Polished-body karaoke on the phone is proportional (timings pinned to raw words); fast-follow to re-align polished words to raw timestamps — still wanted? — src: `SKRIFT_SOURCE_OF_TRUTH.md:363`

### Reconcile sweep
- Offline conflict: the same note body edited on two devices = per-record LWW (one edit silently lost); decide LWW vs "conflicted copy" vs field-level — src: `SKRIFT_SOURCE_OF_TRUTH.md:350`
- `cloudKitMacSync` was specified opt-in OFF by default when Bonjour was the fallback; with Bonjour gone, should Mac sync simply be on? — src: `archive/handoffs/MAC_CLOUDKIT_PLAN.md:37`, `archive/handoffs/LIVE_SYNC_HANDOFF.md:23-25`
- Prod CloudKit: schema deploy (`MemoEnhancement`, `NamesRecord`, `VocabularyRecord`, later types) + one real prod round-trip are still listed as owed — has prod ever done a round-trip? — src: `SKRIFT_SOURCE_OF_TRUTH.md:421-422`, `archive/handoffs/LIVE_SYNC_HANDOFF.md:125-126`
- Cross-subsystem end-to-end scenarios per swap ("a handful of `-ratetorow`-style") — which ones — src: `backlog.md:654-657`

### Export compiler
- The export model is "STILL being mulled by the user — not locked": ship the built one-way engine as v1; the split-note hybrid (Skrift region + user-owned region below a fence) and per-book quote aggregation (#6) are sequenced later — confirm v2 compiler scope excludes both — src: `memory/project_obsidian_relationship.md:29-32`, `archive/handoffs/OBSIDIAN_EXPORT_ALTERNATIVES.md:96-113`
- Folders model (app-native folders vs Obsidian subfolders) — "user wants to think more"; possibly superseded by "the picked folder IS the destination" + four destinations — src: `STANDALONE_PLAN.md:576-577`
- Auto-publish on iPad/Mac after Process (today: manual "Export now" on iOS; the Mac has an auto re-export sweep) — src: `memory/project_ipad_wave1.md:23-25`, `FEATURES.md:41`
- "Delete after export" as a feature (called desirable, never built) — src: `memory/project_obsidian_relationship.md:22-24`
- Should trashing a memo delete its Obsidian `.md`? — parked question — src: `memory/project_intertwining_device_bugs.md:61`
- `includeAudioInExport` sync parked; the return path (plugin → Skrift) deliberately small — src: `memory/project_ipad_wave1.md:335`
- Obsidian plugin menu (10 wireframes) is a PROPOSAL, not signed off; recommended v1 bundle = inbox + sync doctor + listen — src: `memory/project_ipad_wave1.md:419-426`
- Capture `source:` on the OBSIDIAN profile still reads `capture-url|text|image` while the archive uses `capture:` — unify or leave? — src: `Skrift_Native/CAPTURE_CONTRACT.md:117-118`, `memory/project_export_destinations.md:14-15`
- Legacy vault files without a stamp are blocked with no twin — is a one-time adopt-by-content wanted for his pre-2026-07-26 exports? — src: `FEATURES.md:70`, `backlog.md:1115`

### Ingress (share/import)
- What the note SHOULD be per media type: a YouTube link = a link card with the title, or fetch the audio and transcribe? Instagram = the caption as body? (he is the only one who can answer) — src: `backlog.md:634-637`
- URL title/page-text fetch: the C3 contract says "no network fetch" (title from the share payload), the 2026-09-18 note says the fetch on JS-rendered pages is "the jank" — which is the rule? — src: `Skrift_Native/CAPTURE_CONTRACT.md:39`, `backlog.md:628-630`
- Capture-as-note ("text, PDF, text — like Apple Notes", no boxed annotation field; fold `annotationText` into the body; a file/PDF becomes a body block) — user-asked, deferred 2026-07-07, touches C3 + exporter + Mac — src: `memory/project_capture_as_note_kickoff.md:42-46`
- Unified source taxonomy (voice memo / URL / PDF / video / audiobook quote / Apple Note) — glyph/label maps are duplicated; PDF and video are not first-class source TYPES — src: `CLAUDE.md:200-201`, `SKRIFT_SOURCE_OF_TRUTH.md:373`
- Watched-folder ingest (Mac Voice Memos export) — deferred — src: `SKRIFT_SOURCE_OF_TRUTH.md:367`
- Re-ingest the ~30 old Electron-era notes (needs prod idle + the real vault) — still wanted? — src: `memory/project_port_electron_notes.md:3-7`
- Substitutions list (deterministic synced find/replace) — parked, needs his go-ahead — src: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:899-902`
- Synthetic corpus gap: English fixtures edited fine before while his real Dutch came back near-echo — the optional "5 throwaway rambles in Skrift Dev" — src: `backlog.md:614-617`

### Names & sanitise
- The phone's name-linking shipped WITH a "People in this note" chip bar (2026-06-25/26) while the Mac model KILLED the chip bar (2026-06-16) — keep the phone's, or one model? — src: `CHANGELOG.md:33`, `SKRIFT_SOURCE_OF_TRUTH.md:196` vs `NAMING_MODEL.md:97`
- Mac "name a speaker" review UI (backend done; turn-renderer → click-to-name → relabel → enroll) — still owed, mock signed — src: `SKRIFT_SOURCE_OF_TRUTH.md:357`
- Backlink Weaver (auto-`[[link]]` any vault note title, gated by length/distinctiveness) — idea with his over-linking caution — src: `SKRIFT_SOURCE_OF_TRUTH.md:374`, `archive/handoffs/DESKTOP_NATIVE_HANDOFF.md:170,176`
- Tag normalisation ("filosofaties") is explicitly "a parallel issue, not this" — in v2 scope or not? — src: `NAMING_MODEL.md:219`
- Ambiguous-name resolution on the phone: v1 "may leave ambiguous mentions unlinked"; CHANGELOG says purple-dotted tap-to-pick shipped — confirm the phone does the note-level pick — src: `STANDALONE_PLAN.md:279-280`, `CHANGELOG.md:30`

### Consent / rating / lifecycle
- Timeline-in-Review = open question — src: `memory/project_ipad_wave1.md:376`
- Significance-0 auto-prune-after-30-days (roadmap i2) — likely absorbed by the fading lifecycle; confirm it is dead — src: `memory/project_intertwining_device_bugs.md:60`
- Fading exemption "backlinked": does a memo-link from an UNRATED note count as the backlink that holds a note? — src: `memory/project_lifecycle_one_clock.md:13`, `backlog.md:5780`

### Sync contract
- Cellular "Ready to sync · N MB" tap-to-pull for audiobook audio (today Wi-Fi only) — deferred — src: `STANDALONE_PLAN.md:507-509`
- Un-sharing a book leaves a phantom entry on a device that never downloaded the audio — GC deferred — src: `SKRIFT_SOURCE_OF_TRUTH.md:360`
- `SkriftDesignKit` (a real SPM package for tokens) was user-confirmed for Phase 2 — never mentioned again; still wanted, or has `Shared/UI` + `Palette` replaced it? — src: `STANDALONE_PLAN.md:213-226`

### Recording & audio
- Mid-take edit on the Mac (fix a settled word while talking → survives + '✎' chip) — never human-verified — src: `memory/project_live_transcription.md:130-131`
- i17 in-Skrift cursor-follow (movable append anchor) = DESIGN, mock first — src: `memory/project_live_transcription.md:133-134`
- "Transcription a bit weird" after a cold-launch auto-record — parked, "user is unsure it's a real bug" — src: `memory/project_unification_backlog.md:115-116`
- Always-warm ASR engine: confirm intentional + measure for silent battery drain — src: `SKRIFT_SOURCE_OF_TRUTH.md:356`
- Pocket dictation through AirPods now records from the phone mic (b119 policy) — revisit item (roadmap RecHard) — src: `memory/project_audio_session_round.md:17`
- Pause button placement ("on top") accepted for now, low priority — src: `memory/feedback_pause_button_placement.md`
- WeatherKit vs OpenWeatherMap (lean: keep OWM + his key) — never decided — src: `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:811-812`
- Live diarization while recording (F) — deferred lowest — src: `archive/handoffs/CONVERSATION_MODE_HANDOFF.md:69`

### Audiobooks
- Reading-mode status contradiction: `STANDALONE_PLAN.md:443` says the reading-mode redesign is BUILT (build 14, 8 chunks), `CLAUDE.md:125` and the 2026-09-18 note list "audiobook reading mode" as signed-off-not-built — which mock is unbuilt? — src: `STANDALONE_PLAN.md:443-456`, `CLAUDE.md:123-126`, `backlog.md:665-668`
- Capture-screen redesign — DESIGN PAUSED, needs the interaction session — src: `CLAUDE.md:198-199`
- P9b player polish list (sleep timer incl. end-of-chapter, per-book speed memory, skip-silence, annotatable bookmarks, skip-back-on-resume, Clips) — planned, unranked — src: `STANDALONE_PLAN.md:383-387`
- Light/sepia reading themes + a global cross-tab mini-player — owed fast-follows — src: `STANDALONE_PLAN.md:456-457`
- Pictures-in-reader — parked; book pages in-app (i16) — mock-first later — src: `memory/project_epub_alignment.md:114`, `memory/project_ipad_wave1.md:380`
- Book sharing is built on an unmerged branch (`claude/book-sharing-devices-rygara`) with zero device run — merge, or leave until judged? — src: `memory/project_book_sharing.md:11-13,47-51`

### Search / retrieval
- Vault-read (PULL) direction — Skrift reads the whole vault for search/connections — parked ("Huginn-shaped"); the phone folder picker exists for it — src: `memory/project_note_lifecycle.md:58-59`, `memory/project_ipad_wave1.md:18-19`
- Tightness-lens floors re-derived from his real corpus percentiles (resume order: vault → histogram → mock → build) — src: `memory/project_ipad_wave1.md:436-440`
- Monthly digest spike (`-digest <YYYY-MM>` on his real July) — planned in full, not built — src: `memory/project_ipad_wave1.md:377-380`
- Ask-Your-Memos RAG / Weekly digest / People Timeline / Smart-Suggest-People — old idea list, never picked — src: `archive/handoffs/DESKTOP_NATIVE_HANDOFF.md:175-180`

### Editor & note UI
- `mocks/review-note-detail.html` (read-only detail + Process-on-this-Mac for the "Not in the queue" dead-end) — PARKED; revive if the purple alert annoys again — src: `memory/project_note_lifecycle.md:56-58`
- Approved mocks with nothing built: rest of journal-desktop, Mac thumbnails, place/tags chips — spec done-states with the mock as the clause — src: `backlog.md:665-668`
- Drag-to-multi-select lasso (wants a mock) — src: `SKRIFT_SOURCE_OF_TRUTH.md:371`
- Selection-handle wobble on iOS 26 — NOT confirmed fixed since build 35; next step = host header/footer outside the text view — src: `memory/project_note_editing_sprint.md:28-31`
- Accessory bar: revisit scroll-vs-overflow when scan/markup verbs arrive — src: `memory/project_note_editing_sprint.md:41-42`
- Phone Models/Storage management view + the desktop Models-tab mirror — deferred — src: `SKRIFT_SOURCE_OF_TRUTH.md:372`

### Privacy
- "Fully offline" vs the two live network calls: OpenWeatherMap weather at capture and any URL page-title fetch — state them in the spec or cut them — src: `README.md:3-4`, `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:62-64`, `backlog.md:628-630`
- Whether "AI reads this" applies to a future in-app Claude/agent reading `_ideas/` — the boundary is stated for the portfolio repo only — src: `memory/project_export_destinations.md:11-13,60-64`

### Process & shipping
- Keep or retire the XCUITest suite (17 iOS-26 failures, deferred since 2026-06-18) — src: `memory/project_xcuitest_ios26_failures.md:11-22`
- Prod promotion prerequisites still open: Release App IDs owe App Groups + increased-memory-limit capability visits; prod CloudKit schema; TestFlight blocked Apple-side — src: `memory/project_testflight.md:49-61`, `memory/project_ipad_polish_fix.md:32-33`
- Project age is `[unverified]` (git floors at 2025-10-18; he recalls "2 years+") — src: `SKRIFT_SOURCE_OF_TRUTH.md:53-59,555`

---

## D. DRAFT MATERIAL FOR THE SPEC HEAD

### Point (one paragraph)
- Skrift is Tuur's own capture tool for his second brain: he records a voice note (or types, or shares a link, picture, PDF, video, or an audiobook quote) on his iPhone, it is transcribed on the device with nothing sent to any cloud, and — only once he rates it — his Mac or iPad cleans it up with a local model, spells and links the people it is about, and writes one Markdown file into the folder he chose (his private Obsidian vault, or the public portfolio archive that AI is allowed to read). Obsidian is home; Skrift is the front door ("capture tool; Obsidian is home"). The long game is "see how my thinking evolved over time": decades of notes, people pages that show a relationship unfolding, related notes surfacing across years. It is fully offline, one user (him), sold flat at $0.69 with no subscription and no cloud AI — "which IS the privacy story" — src: `README.md:3-4`, `STANDALONE_PLAN.md:12-22,28-31`, `memory/project_obsidian_relationship.md:22-24`, `SKRIFT_SOURCE_OF_TRUTH.md:482`, `NAMING_MODEL.md:13-16`

### Done-means (things he holds or sees)
- On the iPhone 13: he taps record, words appear as he speaks, he stops, and the note is in the list within a second — playable, photos as their own blocks in the right place, unrated and grey, and nothing has been processed or exported — src: `memory/feedback_native_ui_process.md:29-32,64-67`, `memory/project_ipad_wave1.md:365-374`
- On the Mac: the same note is there after he clicks the window; he rates it and presses Process; the polished body, title and summary appear on the phone and iPad within seconds; the raw transcript is still underneath — src: `CHANGELOG.md:13-23,39-45`, `memory/project_ipad_wave1.md:32-35`
- In Obsidian: exactly one file for that note in the folder he picked, with the people it is about as `[[links]]` and in `people:`, the pictures embedded, the stamp in frontmatter; when he edits that file, Skrift never touches it again; a note filed Idea lands in `_ideas/<name>.md` with his friends credited — src: `memory/project_ipad_wave1.md:317-334`, `memory/project_export_destinations.md:55-64,87-91`
- On the iPad: the same note, the same Process button, an identical polish from the identical model — src: `memory/project_ipad_wave1.md:64-65`, `memory/project_ipad_polish_fix.md:33-34`
- On the synthetic corpus: every v2 output is identical to v1 or is a pre-registered expected difference, the invariants hold (markers in = markers out, paragraphs never drop, editor round-trip exact, transforms idempotent, no rated memo without a row), each v2 subsystem is ≤ 40% of v1's lines, and he has read the corpus output and it reads right — src: `backlog.md:644-657`
- In the audiobook player: he opens a book, the read-along text is aligned with the narrator, a captured quote becomes a note with his ramble, and nothing is re-transcribed — src: `memory/project_epub_alignment.md:74`, `SKRIFT_SOURCE_OF_TRUTH.md:490`

### Not doing (explicit exclusions)
- No Python, no Electron, no React Native, no Bonjour/HTTP server; both apps native SwiftUI, CloudKit the only transport — src: `CLAUDE.md:11,23`, `archive/handoffs/LIVE_SYNC_HANDOFF.md:9-11`
- No cloud AI, ever; no AI/agent reads his vault; no third-party analytics ("all on-device, no tracking") — src: `memory/feedback_vault_privacy.md`, `STANDALONE_PLAN.md:396-397`
- No subscription, no IAP, no free trial ($0.69 flat) — src: `STANDALONE_PLAN.md:28-31`
- No third app: the iPad is the universal iPhone target; the Mac stays a separate UI over shared code, never a merged single app — src: `memory/project_ipad_direction.md:15-18`, `memory/project_standalone_app_store.md:58-59`
- No LLM in naming, tagging or significance; no NER; no auto "new person?" hint; no per-occurrence resolver; no chip bar on the Mac — src: `NAMING_MODEL.md:61-81,97,217-218`, `memory/project_overhaul.md:24-25`
- No destination suggestion engine; never two destinations on one note — src: `memory/project_export_destinations.md:29-30,60-64`
- No numeric similarity slider; no static (stale) Connections sidecar; no semantic linking while typing — src: `memory/project_ipad_wave1.md:374-375,430-432`, `memory/project_desktop_parity_plan.md:64-65`
- No vision pipeline, no chat/ask feature, no export preview, no LLM narration of "how my thinking evolved" (yet) — src: `SKRIFT_SOURCE_OF_TRUTH.md:76-80,482`
- No audio mark-in/out quote capture; no QR pairing; no Review screen after recording; no Re-transcribe on the phone; no memory-aid prompts; no audio trim — src: `SKRIFT_SOURCE_OF_TRUTH.md:535`, `archive/handoffs/MOBILE_NATIVE_HANDOFF.md:507-510,711-712`, `memory/project_note_editing_sprint.md:44`
- No Apple Watch in v1; no dictate-at-caret (parked; if ever built, the audio is not kept); no phone-side Obsidian export; nothing auto-publishes on iOS — src: `STANDALONE_PLAN.md:573`, `memory/project_note_consent.md:48-51`, `memory/project_ipad_wave1.md:14-25`
- No video export; no bubble/box chrome on shared input; no 4-bit iPad model; no iCloud-Drive sync; no `Skrift/` prefix in the vault; no Flag verb — src: `memory/project_export_destinations.md:111-113`, `memory/feedback_no_bubbles_on_shared_input.md`, `memory/project_ipad_polish_fix.md:33-34`, `STANDALONE_PLAN.md:34`, `memory/project_ipad_wave1.md:60,321-322`
- In v2: no rewrite of views, the CloudKit schema or the audio/hardware paths; no real notes in the corpus; v1 is never the judge — src: `backlog.md:599-605,606-608,646-647`
- No whole-library audiobook sync (per-book opt-in only); a shared `.skriftbook` never carries position, bookmarks, rate or his notes — src: `STANDALONE_PLAN.md:546-551`, `memory/project_book_sharing.md:15-20`

### Device reality (what is verified where)
- iPhone 13 (the only real phone; UDID `00008110-001208C902EA201E`): live round-trip 2026-06-07; intents/widgets/Live Activity 2026-06-08; conversation split + tap-to-name + auto-match; CloudKit iPhone→iPad 2026-06-17/18; custom vocab fix 2026-06-13; image reflow build 80; one-clock phone-open build 106; record-start numbers build 119/121; LPM transcribe build 136 + remove-transcript build 137; language sync both ways builds 133/134; turn gutter build 134; export destinations build 164 (screenshots) — src: `SKRIFT_SOURCE_OF_TRUTH.md:132,141`, `memory/project_conversation_voice_identity.md:50`, `memory/project_audio_session_round.md:21`, `memory/project_book_sharing.md:53-62`, `memory/project_ipad_wave1.md:12-14`, `memory/project_export_destinations.md:42-45`
- iPad Pro: chrome build 132 Tuur-confirmed; bookmark + ePub sync confirmed 2026-07-24 (29 real TOC chapters); the iPad polishes since 2026-08-12; export destinations 164 screenshots — src: `memory/project_ipad_wave1.md:83-85,110-111,168-175`, `memory/project_ipad_polish_fix.md:11-12`
- Dev Mac (`/Applications/Skrift Dev.app`): 73 memos synced 2026-06-22; Connections live 2026-07-16; live transcription "way better" 2026-07-28; unrated model "very sexy" 2026-07-28; turn gutter "way better looking" 2026-07-27; recorder hardware-verified headlessly (`-recordcheck`); export destinations live-verified builds 156–164 — src: `archive/handoffs/MAC_CLOUDKIT_PLAN.md:54-59`, `memory/project_live_transcription.md:98`, `memory/project_note_consent.md:46-47`, `memory/project_conversation_turn_gutter.md:11-15`, `memory/project_mac_recording.md:54-58`, `FEATURES.md:68`
- iPhone 17 sim: the unit gate (mobile 1065/0 latest, desktop 762/0, MLX build green); no ANE/mic/camera, so ASR, diarization, glass, audio routes and share sheets can never be proven there; UI suite 17 failing (iOS-26 rot) — src: `memory/project_export_destinations.md:43-44`, `memory/project_xcuitest_ios26_failures.md:22`, `CLAUDE.md:52-55`
- Prod: "Skrift" Release on the iPhone 13 and `/Applications/Skrift.app` last promoted around 0.2.0 (build 22, 2026-06-26); prod CloudKit schema deploy + a prod round-trip never recorded as done — src: `SKRIFT_SOURCE_OF_TRUTH.md:198,336,421-422`
- TestFlight: builds 166/167/168/169 all 404 on install — Apple-side per-app beta contract defect since 2026-08-26; testers cannot install anything — src: `memory/project_testflight.md:146-217`
- OWED / UNVERIFIED (no hardware evidence): book sharing end-to-end (branch unmerged, neither sheet ever opened); export destinations phone + iPad round; the shared export engine's first real-vault run (throwaway folder first); mid-take edit on the Mac; one live Mac Record button press; read-along `lead` tune; Mac name-a-speaker UI; selection-handle wobble; audiobook interruption fixes B1–B5 (deferred by Tuur, not owed); Mac Dev eyeballs of the inspector spring and the ⋯ chip; `includeAudioInExport`; the P4a on-device polish spike; weather (needs his key) — src: `memory/project_book_sharing.md:47-51`, `memory/project_export_destinations.md:45`, `memory/project_ipad_wave1.md:333-334`, `memory/project_live_transcription.md:130-134`, `memory/project_mac_recording.md:60`, `SKRIFT_SOURCE_OF_TRUTH.md:357,599`, `memory/project_audio_session_round.md:28`
