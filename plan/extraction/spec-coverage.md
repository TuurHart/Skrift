# SPEC.md coverage audit — against `plan/extraction/` (2026-09-21)

Read in full: `SPEC.md` (C1–C122, R1–R15, D1–D34) and all six reports (ledgers 458 lines, bugs 155, code-core 568, ingress 461, mocks-roadmap 567, decisions 585). Two code checks only: `Shared/Naming/Sanitiser.swift:1-30,140-210` (link literal) and `Shared/Model/Memo.swift:254-300` (destination words as tags). Nothing else modified.

Legend: `L:` ledgers.md · `B:` bugs-preregistered.md · `K:` code-core.md · `I:` ingress.md · `M:` mocks-roadmap.md · `D:` decisions.md (line numbers are the report's own). "→ Cnew" = proposed clause in the spec's style. "trivia" = lives in tests, not the spec, with the reason.

| Section | Count |
|---|---|
| A · uncovered rules (locked or load-bearing mechanical) | 134 → a proposed clause or fold (A1–A134); 47 more judged trivia (listed per section) |
| B · needs-verdict items not in D1–D34 or parked | 47 (+ 14 parked-in-reports items missing from the spec's parked list) |
| C1 · contradictions inside SPEC.md | 14 |
| C2 · SPEC clauses vs a [locked] report decision | 12 |
| C3 · ledger (20) + mocks (30) contradictions — resolution stated? | 50 rows: 25 stated · 4 partly · 16 not · 5 n/a |
| D · unsourced clauses | 12 (incl. R10, which may be mis-registered) |
| E · invariants (54) | 36 covered · 9 weaker in the clause · 3 obsolete under C17 · 6 missing |
| F · required differences missing from R1–R15 | 17 inside targets (+ 6 ingress-adjacent, 4 unstated identicals) |

---

## A · UNCOVERED RULES

### The v2 method / Gate

- **A1** The corpus golden generator on the Mac is `-ingestfile` + `-processfile [-exportafter]` (quit the GUI first); the sim runs seeded engines (no ANE) — I:365-373, D:397 → `- Cnew [auto] Mac goldens come from -ingestfile → -processfile -exportafter on the Dev store; sim runs use -seedTranscript/SeededDiarizer/SeededEmbedder || check: harness script names those verbs — I:365-373, D:397`
- **A2** Every dependency and the model are pinned by exact revision (FluidAudio v0.15.5, mlx-swift-lm, swift-transformers 1.3.0, Jinja 2.3.6, ZIPFoundation 0.9.20); upgrades are deliberate with a device round — L:425 [locked] → `- Cnew [auto] All engines + the model are revision-pinned; a pin bump is its own commit and owes a device round || check: no branch:/main refs in project.yml or Package.resolved — L:425, D:319`
- **A3** Failures must be visible: no `try?` on the write surface; `lastError` rendered; export/ingest/attachment failures logged — L:427 → `- Cnew [auto] No swallowed error on any write surface (vault, store, sync); every refusal reaches the UI as text || check: grep try? in Shared/Export, Shared/Naming, Pipeline/Ingest = 0 — L:427`
- **A4** Tests never touch live Dev data; the sweep takes an injectable `UploadService` — L:115, D:62 [locked] → fold into C122: `…; tests run on temp dirs, never the Dev container (injectable UploadService) — L:115`
- **A5** MLX faults throw (`PolishEngineError.mlx`), never `fatalError` — L:77, D:319 → `- Cnew [auto] An engine fault throws and lands on the row as an error; the app never dies on a bad model load || check: MLX.withErrorHandler wraps every generate — L:77`

### Body/image model

- **A6** `offsetSeconds` = recording time with paused time excluded; manifest order = capture order; markers numbered by manifest index — K:15,18 → `- Cnew [auto] offsetSeconds excludes paused time; imageManifest order = capture order; [[img_NNN]] N = manifest index || check: MemoSaver persist tests — K:18`
- **A7** Diarization rebuilds the body from words (markers dropped) then re-inserts markers by timestamp — K:23 → under C10 it must re-place picture paragraphs after the turn: `- Cnew [auto] Splitting speakers keeps every picture as its own paragraph after the turn sentence it was spoken in (D3) || check: corpus conv-with-picture — K:23`
- **A8** Phantom guard threshold: drop when empty, or RMS < 0.0075 AND ≤ 3 words — K:25 → fold into C101: `…phantom guard (RMS < 0.0075 ∧ ≤ 3 words)…`
- **A9** `transcriptMarkersInjected` is a synced flag whose only live reader is the phone thumbnail rule; the Mac never reads it — K:26-27 [locked doc, dead] → `- Cnew [auto] transcriptMarkersInjected stays on the wire (additive) and is read only by the thumbnail rule; no Mac path re-injects || check: grep readers — K:26-27` (see B5)
- **A10** List thumbnail = first marker in BODY order that resolves; all markers deleted → none; marker-less share capture → manifest[0]; typed body → none — L:19, K:86 → `- Cnew [auto] Thumbnail rule as L:19 || check: MemoDisplay tests, corpus pic-missing-file`
- **A11** Karaoke on a capture = quote words + ramble words as one text; ramble timings start at the quote's spoken-word count — L:45, K:78 → fold into C26.
- **A12** Filler-word filter: opt-in, default OFF, EN/NL stoplist, voice memos only (never quotes/live caption), text + timings drop in lockstep — L:331 [locked], K:61 → `- Cnew [auto] Filler strip is opt-in (default off), memos only, drops token + timing together, all-filler input unchanged || check: FillerFilterTests — L:331`
- **A13** Quote splitter drift: `QuoteProtection.splitLeadingQuote` demands column 0, `CaptureQuote.split` tolerates indent, the Mac counts an indented `> ` as a quote line (2026-07-27) — L:31, K:65-66 → `- Cnew [auto] ONE quote splitter for display, copy-edit and export (indent tolerance decided once) || check: no second splitter — L:31, K:65`
- **A14** A quote-capture memo is born `transcriptUserEdited = true` so the Mac never re-ASRs it; no location captured — K:69 → fold into C104.
- **A15** The quote text of a capture is NOT free-text editable (would diverge from the audio) — M:278 [locked] → fold into C22: `…the quote block is read-only in the editor; only the ramble edits`.
- **A16** "Backlinked" = distinct memo ids in `[[memo:…]]` across live memos' transcript (+ copyedit on the phone) — K:74 → `- Cnew [auto] Backlink set = memo-link targets across live bodies (raw + polished); it holds a note off the fade clock (C89) || check: MemoLifecycle backlink tests — K:74` (see B33)
- **A17** Phone commit target (raw vs polished binding) is pinned at the FIRST dirty edit of a burst (P0 2026-07-10) — K:41 → `- Cnew [auto] The edit target is pinned at the first keystroke; an arriving polish never receives a raw-born draft || check: NoteBodyTests markDraftDirty — K:41`
- **A18** Conversation detection is gated on `sourceType == .audio`; an Apple Note with ≥ 2 bold headings is prose — L:209 → fold into C23.
- **A19** Mac conversations render as a right gutter + spine; a long name truncates; the phone KEEPS its cards; turn spacing stays looser than the mock — L:36-37 [locked] → `- Cnew [tuur] Mac turns = gutter + spine (E1), phone = cards with shared hues; no phone gutter planned — L:36, M:359`
- **A20** Capture-image markers in an annotation convert like memos; the pinned `![[embed]]` is skipped when the body carries markers; legacy marker-less captures keep the old path — M:28, K:215 → fold into C57.
- Trivia (tests, not spec): tasks Return-continuation (L:28); live link title never "Untitled" (L:30); Mac hides `> ` glyphs (L:32); tokenizer regex details (K:32); typing-attribute stripping (K:40); re-render guards (K:44-45, die with C17); video frame at `min(1, dur/2)` s (K:22); photo tap hit-test/markup chain (M:23-24); tall-portrait shrink (M:25).

### Copy-edit

- **A21** Local-model doctrine post-conditions: no proper noun in the output absent from the input; language never flips; length bound; on gate failure degrade to deterministic, never ship suspect output; never hand the model corpus-wide synthesis / numbers / dates / translation / sentiment — L:65-66, M:62 [locked i19] → `- Cnew [auto] Post-conditions on every model output: no new proper noun, same language, bounded length; a failed gate ships the unedited text || check: PolishGate tests on the corpus — L:65, M:62`
- **A22** No sensor context (place/weather/people) is fed to the LLM; context stays deterministic in frontmatter — D:36 [locked] → `- Cnew [auto] Prompts carry the text only; never metadata || check: prompt builder has one text input — D:36`
- **A23** Prompt rewording is NOT the cure for Dutch near-echo / missing paragraphs; the paragrapher is (A/B refuted) — L:56 [locked] → fold into C34/D8 as a stated doctrine.
- **A24** Deterministic tail order after the model: tags (`TagMatcher`) → name-link LAST → compile; no `[[ ]]` reaches the model — K:127, D:26 [locked] → `- Cnew [auto] After generation: tags → name-link (last) → compile, in that order || check: BatchRunner step order test — K:127`
- **A25** Deterministic tags: vault-whitelist lemma match ≥ 2 occurrences, max 10, + ≤ 5 spoken `#hashtags`; suggestions only, user selects; the Mac owns the vocabulary from frontmatter names only; people not auto-excluded; no LLM — K:128, D:234 [locked], M:178 → `- Cnew [auto] Tag suggestions are deterministic (lemma ≥ 2×, max 10 + 5 spoken); the user accepts; the vault is read for tag NAMES only || check: TagMatcher tests — K:128, D:234`
- **A26** Refine pass (`refineStep`) runs before export for significance ≥ 0.8 — L:75, M:61 → `- Cnew [tuur] What the refine pass does in v2 (keep / drop) — decides D30's 4th button` (see B9)
- **A27** Redo title / copy-edit / summary share ONE generate path; a redo rewrites only that part into the EXISTING enhancement with an LWW stamp; offered only where polished + engine + unlocked; conversations keep verbatim — L:71, K:131,140 → `- Cnew [auto] Redo rewrites one part in place through the same escrow; never a second enhancement row || check: PolishCenter redo tests — L:71`
- **A28** The iPad polishes ONLY on the visible verb (no auto-polish on open, Tuur 2026-07-23); the Mac polishes unattended; ONE note at a time device-wide; iPad-only, ≥ 6 GB, never sim — K:136-141 [locked], M:53 → `- Cnew [auto] Mac = automatic batch polisher; iPad = on-demand only, one note at a time; the iPhone never polishes || check: PolishCenter gate tests — K:136-141, M:53`
- **A29** Phone: the polished body is ONE editable body (no raw/polished toggle); an edit writes `enhancement.copyedit` re-stamped (this device, now); title chooser Suggested / recording / own; "Polished on your Mac" provenance — M:51, D:37 [locked 2026-06-26], K:144-145 → `- Cnew [tuur] The phone shows the polish as the one editable body; edits land in the enhancement, stamped — M:51`
- **A30** Interrupted runs (`.processing` at launch) reset to pending; queue = live ∧ not done ∧ not unrated-local-recording, oldest first, one at a time — K:129-130 → fold into C38.
- **A31** Capture title fallback when the annotation is empty: `urlTitle` → first 8 words → image filename → "Capture"; a preset title wins; captures never transcribe/diarize — K:117 → fold into C25/C36.
- **A32** A quote-only capture never calls the model — K:101, inv 15 → fold into C29.
- **A33** Verb is "Process" on every device (`SharedCopy.processVerb`); "memo" → "note" in every user string — D:40, M:297 [locked] → fold into C115.
- **A34** Re-transcribe must also clear diarization segments + sidecar; keeps the chosen title — L:108, K:132 → fold into C51.
- **A35** Flatten to monologue: drops headers, clears diarization, re-polishes as monologue, no re-ASR; conversation mode default OFF — M:59 [locked], D:182 → fold into C102.
- **A36** Gemma output sanitised for the vault: forbidden filename chars stripped from the stem; YAML `title:`/`summary:` quoted — L:78, K:210,233 → see A53.
- Trivia: exact model hash `4255b21b` (L:51, lives in PolishPrompts); one instruct turn `prompt + "\n\n" + text` (K:93); models unload after 60 s (K:129); Redo menu visibility (L:62).

### Reconcile sweep

- **A37** Reconcile order: names sync → vocab → prompts → memo sweep → notify → save + re-export → `MacMemoAuthor.backfill` → `reflectTranscripts` → connections index — K:153 → `- Cnew [auto] Names and vocab reconcile BEFORE the memo sweep so linking sees the fresh roster || check: wiring order test — K:153`
- **A38** `reflectTranscripts` fills an EMPTY memo transcript only for this device's own memos and only from `.done` rows (the live seed never clobbers the final pass) — L:96, D:57 [locked], inv 37 → `- Cnew [auto] Mac words reach a memo only when the memo is empty, Mac-recorded, and the row is done || check: MacMemoAuthorTests:188-264`
- **A39** Row match = memo id, else `audioFilename` — but the filename arm may not claim a row owned by another memo (quote captures inherit the source's filename) — L:94, K:157, inv 26 → fold into C41.
- **A40** `MacCloudWriteBack.resolve` asks the STORE which candidate UUID exists (row id vs filename UUID); every writer uses it; a Mac recording's file UUID ≠ memo UUID — L:99, K:187 [locked], D:58 → `- Cnew [auto] Every Mac→phone writer resolves the memo through the store, never by filename alone || check: MacCloudWriteBackTests resolve — K:187` (see B7)
- **A41** A Mac recording rides the Import door (`ArrivalPath`), no second path — L:98, D:100 [locked] → fold into C49.
- **A42** Unrated notes never become `PipelineFile`s; the Mac renders them through a transient projection and writes edits straight onto the `Memo` (never via `MacCloudEditSync` — that would claim "the Mac polished this"); Journal reads the cloud store read-only — L:106-107, K:196, M:209 [locked 2026-07-26] → `- Cnew [auto] An unrated note has no row; the Mac edits it on the Memo itself, never as an enhancement || check: MemoNoteProjection.writeBack tests — L:106`
- **A43** Three meanings of `PipelineFile.significance == nil` resolved ONCE (projection = unrated · local recording = unrated · import/legacy = rated) — L:100, M:70 [locked] → fold into C87 (see B10).
- **A44** `cloudKitMacSyncEnabled` defaults ON; an explicit false is honoured — L:109, M:81 [locked] → fold into C52.
- **A45** Sidecars honoured only when the transcript is trusted — K:164 → fold into C42.
- **A46** The row's content date (`pf.uploadedAt`) = the phone's `recordedAt`, never ingest time — K:167 → fold into C70 (see B8).
- **A47** Recompile only when a `recompiles` field or content changed; lock / reminder / OCR never recompile; a nil/blank `Memo.title` never clears `enhancedTitle` — K:178, inv 30 → fold into C47.
- **A48** Mac→phone meta writes never bump `lastEditedAt` (never a touch); a Mac-initiated trash stamps `trashSeenAt` — K:191-192 → fold into C89/C90.
- **A49** The Mac auto re-exports a changed row only if already exported ∧ unlocked ∧ live; refusals logged not raised; unlock ⇒ re-export — K:182, L:140-141 → `- Cnew [auto] Re-export after a sweep is automatic only for notes already in the vault; the first export is always the verb || check: Wiring re-export test — K:182`
- **A50** `AssetMaterializer`: idempotent both ways; synced blob → file never overwriting; disk → asset refreshed on byte-size change; runs launch/foreground/import — K:201, M:227 → `- Cnew [auto] Asset materialisation never overwrites a file and refreshes on byteCount only || check: AssetMaterializerTests — K:201`
- **A51** Stuck `.transcribing`/diarizing memos recovered once per launch, by the recording device only — K:202, L:324 → fold into C97/C100.
- **A52** Permanent delete stays device-local; the phone owns the purge; Mac soft-delete keeps the working folder — L:104, D:133 → fold into C90.
- Trivia: reconcile summary log line (L:110); notification posting (L:95); `-poke-sweep` (D:330); working-folder layout (K:168).

### Export compiler

- **A53** Vault stem rule: title else filename stem; `/ \` → `-`; strip `* " < > : | ? # ^ [ ]`; collapse spaces; cap 120; `MemoExporter.exportTitle` keeps the hard `prefix(80)` slice (filename stability) — K:233,254, L:41 [locked] → `- Cnew [auto] The vault stem derives from the title by ONE rule (K:233); derived-title clipping (C25) never touches the filename || check: VaultName tests — K:233, L:41`
- **A54** `VaultLayout.home`: folder names not configurable (`Skrift/`, `Recordings/`, `Images/`, `Documents/`); pick named Skrift → as-is; pick holds a stamped `.md` → as-is; pick contains `Skrift/` → that; else `<pick>/Skrift` created on first write; archive returns the pick unchanged — K:232 [locked 2026-08-14], L:132 → `- Cnew [auto] Home resolution + media subfolders exactly as K:232 || check: VaultLayoutTests` (contradicts C53 wording — see C2-4)
- **A55** Stamp: hash = SHA-256 over every line except the `skriftHash` line and SPANS the frontmatter (an Obsidian tag edit = a user edit); only text starting `---` is stamped; keys are a PUBLIC contract for the plugin, never renamed — K:234, L:121, M:97 [locked] → fold into C54.
- **A56** Ledger = convenience, stamp = safety: per-picked-folder, local-only, per-device; a wiped or foreign ledger ADOPTS its own file by stamp; a retitle keeps the path — L:124,127, K:240, inv 44 → `- Cnew [auto] Losing the ledger costs nothing: the next export re-adopts by stamp; a retitle never moves the file || check: VaultWriteTests:73-78,215-237`
- **A57** Skrift never deletes a vault file; lock-after-export → "already in your vault" notice — L:140 [locked] → fold into C54/C91.
- **A58** `ExportOutcomeCopy` is ONE outcome table: a refusal STAYS until dismissed; `unchanged` never says "Exported"; `exportRefusal` names the first failing gate — L:126, K:241 [locked 2026-08-28], K:259 → `- Cnew [auto] Outcome copy is shared; refusals sticky; unchanged ≠ exported || check: ExportOutcomeCopy tests`
- **A59** Include audio in export: per-note toggle, default on, copies the audio as `<stem>.<ext>` into `Recordings/`; Mac-only, unsynced — D:70 [locked], M:115, K:246 → `- Cnew [auto] Audio export = per-note switch (default on), file named by the stem; the flag does not sync (D-new) || check: VaultExporterTests audio — D:70`
- **A60** Destinations sit behind ONE Settings switch, off by default; off = today's behaviour byte for byte; a destination is a per-device folder bookmark (no Mac dependency); ONE archive root — L:147-148 [locked] → fold into C62.
- **A61** Archive frontmatter also WRITES `capture:` (not `source:`), `voice: raw|cleaned|written` set by EACH APP never derived in the Compiler, `location:` kept; archive slug cap 120, collision suffix `-<id8>`; vault suffix ` <ID8>` — L:150, K:225-228, D:81-82 [locked] → fold into C62 (currently lists only the drops).
- **A62** The Mac keeps a video's source movie beside `original.m4a` (local, never synced) and the ARCHIVE export copies it — K:248 [locked 2026-08-28] → conflicts with C63; see C2-3.
- **A63** Body precedence on export: `sanitised` → `enhancedCopyedit` → `transcript`; dangling markers dropped, never printed; assets after the write, failures counted never fatal — K:209,239,255 → fold into C56/C57/C58.
- **A64** Frontmatter is GROUPED (what-you-read / what-it's-about / where-you-were / bookkeeping last) with `pressureTrend`; title always double-quoted — K:210-211 [locked 2026-08-14] → amend C56's key list to the code order.
- **A65** The note's primary verb is ONE three-state rule Process → Export → Re-export (`NoteWorkState`); the rating line reflects work state — M:101 [locked 2026-08-14], L:267, L:287 → `- Cnew [auto] One three-state primary verb on every device || check: NoteWorkStateTests`
- **A66** Full-exportability doctrine (2026-07-18): the vault is a complete mirror of rated notes; internal by nature = timings, embeddings, sync state — L:157 [locked] → state as superseded-in-part by C61 (processed-only, verb-driven).
- Trivia: Mac export order (K:246); `exported` flag bookkeeping (K:249); `fmtNum` (K:214); Mac place reaches its export (L:155).

### Ingress

- **A67** Share dispatch order: audio → web URL → movie → image(s) → plain text → document; first match wins; only the audio branch (collects images + text) and the URL branch (text beats URL, URL rides along) keep siblings — I:27-30, L:175 [locked] → `- Cnew [auto] Dispatch order and which branches keep siblings, as I:27 || check: SharePayloadLoader fixtures` (C69 has only the audio-first half)
- **A68** Maps share → `metadata.location` + place chip, no fetch; `maps.app.goo.gl` short links stay plain cards BY DESIGN (pre-register identical) — L:190 [locked], I:122 → fold into C72.
- **A69** A share carries rating + annotation only: no title, tags `[]`, destination Personal — I:36-38 → fold into C66.
- **A70** Open-in / AirDrop (`CFBundleDocumentTypes`) dispatches by extension; `.ogg/.oga/.m4b/.pdf` silently ignored; audio-only `.mp4` fails "no audio track"; in-app Import = Files (N files → N notes, no chooser) · Video from Photos · Scan — I:222-257, L:191 [locked] → `- Cnew [auto] Open-in accepts what the share sheet accepts; in-app Import has three doors || check: AppURLHandler tests — I:227-235`
- **A71** Whether FluidAudio decodes ogg-opus on device is UNVERIFIED; the doc promises "falls back to the Mac", the code marks `.failed` — I:67-70, D:91 → fold into C69 with ⚠ unverified.
- **A72** Inbox entries that cannot be deleted are tombstoned (cap 200) so nothing re-imports on every open; drain is off-main with a re-entrancy guard — L:201,200 → fold into C75.
- **A73** Silent video → `.failed` memo "Video had no audio track" (identical); `.avi/.mpg` accepted, fail honestly — L:204, I:176 → fold into C71.
- **A74** Captures get no location/weather; the Mac stamps `location:` for RECORDINGS only, never imports — L:198, L:333, D:295 [locked] → fold into C78/C100.
- **A75** SKIP vCard → Names, `.ics`; PARKED Apple Books / Kindle quote shares — L:192 [locked] → add to Not doing.
- **A76** Old test image-captures stay broken, no migration; pre-build-76 PDF captures stay text-only — L:213 [locked], B:54 → state which legacy shapes C10/D4 normalise and which stay (see C2-9).
- **A77** Feedback states copy: "Saved ✓ … Skrift opens on it next time" / error + Try again / "Skrift can't import this" with no Save — M:130 [locked] → fold into C75 (one line).
- Trivia: ≤ 10 attachments cap (L:182); clip-order tie window 2 s (I:49); enrichment timeouts/2 MB/640 px (I:125-131); `.txt` ≤ 512 000 bytes (I:210); audiobook multi-file import rules (L:211 — Books, out of rewrite).

### Names & sanitise

- **A78** Every person = ONE note; the canonical must match the `People/` note title exactly; Skrift never creates or enriches person notes — L:219, D:106-108,120 [locked] → `- Cnew [auto] Canonical = the People/ note title; Skrift writes links + people:, never the person page || check: roster seed test — L:219`
- **A79** Roster seeding reads `<vault>/People/*.md` TITLES only (no contents, no AI); canonical = title, aliases = full title + first token; idempotent — L:233, D:118 [locked] → `- Cnew [auto] Seeding = filenames only || check: PeopleFolderScanner reads no body — L:233`
- **A80** Two jobs: normalise known names everywhere (a mistranscribed KNOWN name is fixed via a registered alias, shown dotted when unlinked, one-click revertible) vs link only subjects — L:220,227,228 [locked] → `- Cnew [auto] Normalisation ≠ linking: aliases fix spelling everywhere; only the first mention links || check: SanitiserTests normalise — L:227`
- **A81** The link literal: first mention of a safe alias → bare `[[Canonical]]` (possessive outside), later → short; conversation inline first mention `[[Canonical|short]]` (bare when equal); an existing link counts as the first mention — K:268-269,272; Sanitiser.swift:1-30 → C80's `[[Canonical|spoken]]` is wrong vs code; see C2-6.
- **A82** Unlink scopes: this mention (alias as spoken) or all mentions in this note (`unlinkedNames`, survives reprocess); never touches the Names DB; NO "never link anywhere"; a silenced pick `""`; `neverLink` prunes but still suggests — M:163 [locked], K:271 → `- Cnew [auto] Two unlink scopes, note-local, persisted in nameResolutions; the roster is never edited from a note || check: NameUnlink tests — M:163`
- **A83** Adding a same-name person re-derives every memo that auto-linked it → dotted suggestion + count flash; exported `.md` untouched; cross-person duplicate aliases allowed on purpose — L:236, D:124 [locked] → `- Cnew [auto] Roster collision re-scan is in-app only; duplicate aliases across people are legal (that IS ambiguity) || check: RosterAudit tests`
- **A84** Accepted limitations: a stoplisted frequent person (Mark/Rose/Max) is dotted in every memo, no per-person override NOT NOW; sentence-initial "Will you…" noise accepted — L:238-239 [locked] → fold into C80.
- **A85** `names.json` merge: LWW string compare, ties → remote, tombstones win when newer, pruned > 90 days; `PersonEditCore`: alias defaults to the name, case-insensitive de-dupe, rename carries voiceprints, delete tombstones WITHOUT voiceprints — K:266, L:241 → fold into C85 (tie rule → B12).
- **A86** Voice identity: true cosine (not unit-norm), ≥ 2 s of speech, max-cosine over the stored list (never averaged), audio discarded after embedding; naming a speaker enrols the voice and auto-matches next time; attribution gated on trust, unnamed stays unnamed ("a wrong attribution is worse than none") — D:179,180,362 [locked], L:251,343, M:173 → fold into C102.
- **A87** Re-transcribe is hidden for diarized memos; "Split speakers" is POST-transcript (no pre-record toggle), "How many speakers? Auto/2-5", forcing N merges the most similar; `SpeakerFusion` byte-identical on both apps (`minTurnWords` 3) — D:121,182,183 [locked], L:245 → fold into C102.
- **A88** TagComplete grammar (no spaces, `_-/`, nested `/`); inline `#` = passive panel, bare `#` browses — L:402, M:179 [locked] → fold into C93/C24 (one line).
- Trivia: iOS uses `confirmationDialog` not a caret popover (M:166 — view); right-click "Add as…" (L:250); names push debounce (L:247); name tier colours (D:425).

### Consent, rating, lifecycle

- **A89** Significance grid: 10 stops 0.1…1.0; tiers Passing 0.1–0.3 / Useful 0.4–0.6 / Important 0.7–1.0; refine wall ≥ 0.8; tap the Nth → 0.N, re-tap → Not rated; user-facing word "Importance" (symbols unchanged); rating ties broken by date — L:260, M:191-192 [locked 2026-06-11/19], K:281 → `- Cnew [auto] The rating grid + tier names + refine wall as L:260; "Importance" in copy || check: SignificanceScaleTests`
- **A90** What counts as a TOUCH: dots / edit / title / tags / lock / reminder / annotation / backlink / keep; photos and bare captures deliberately NOT; typing restarts the clock, a rating-only change does not; `markEdited` is THE tracepoint — D:135 [locked], K:289, M:210 → fold into C89 (currently "touch" is undefined).
- **A91** Fading is DERIVED (no stored state); sweeps automatic from install (no arming gate); `keptAt`/`fadeEntersAt` the only additive fields; the ⋯ dot = unread semantics — L:273,283 [locked] → fold into C89.
- **A92** Copy trio verbatim on every surface: "starts fading <date>" · "moves to Recently Deleted in Nd" · "gone for good in ~Nd" — L:271, M:196 [locked], inv 53 → `- Cnew [auto] The three lifecycle strings are byte-pinned in MemoSpine || check: MemoSpineTests`
- **A93** ONE conveyor named "Fading" (fading + deleted, soonest first), ONE verb "Bring back" (= keep + undelete); phone placement B = a quiet row at the bottom of the Review feed; ONE Recently Deleted in Review backed by `Memo`; delete is soft everywhere, no confirm dialog on the Mac; lock is a background verb — L:275, M:198,202-205 [locked] → `- Cnew [tuur] Lifecycle IA as signed (lifecycle-ia-explorations + triage-peek m6): one conveyor, one trash, Bring back, phone row B — M:194-205`
- **A94** Asymmetry doctrine: Mac list = deciding room (always-on state); phone list = notebook (amber only ≤ 7 d); unrated rows quiet and dim on both, interleaved by date; status pills Mac always / iPad in-flight+error only — L:276-278, M:208,215 [locked 2026-07-22] → `- Cnew [tuur] The two lists are deliberately not twins (L:277); pills policy per app — L:278`
- **A95** One-home law: every station has exactly ONE counting surface; editorial views may show any live note; a countdown appears only where computed true — M:197 [locked 2026-07-21] → `- Cnew [tuur] One counting surface per station — M:197`
- **A96** Lock = hidden, not encrypted, stated in-app; the player never loads a locked memo; Copy gated behind auth; locked notes KEEP PROCESSING in v1 — L:280, D:259, K:292, D:434 → fold into C91 (and D10 must reckon with "keep processing" — see B).
- **A97** Retention doctrine: the permanent corpus = rated memos; unrated are provisional; auto-prune only via a user-approved review; prune audio before text — M:218 [locked JRP] → `- Cnew [tuur] Nothing is pruned without a review he approves; audio before text — M:218` (see B34)
- **A98** `ProcessPile.waiting` = rated ∧ live ∧ unlocked ∧ real transcript ∧ not processed; unrated Mac takes are out of "Process N"; `canSummon` = rated ∧ !locked — L:265-266, K:286, D:150 → fold into C38/C109.
- **A99** Sync is unconditional: CloudKit syncs EVERY memo regardless of rating (flag-to-PROCESS) — M:189, D:130 [locked 2026-07-20] → fold into C87 (not stated anywhere in the spec).
- Trivia: unrated audio materialised to `UnratedAudio/` (L:279); deduper clones stamp at trash (L:284); capture sheet significance on top (L:285 — view order); `QueueFilter` names (L:266).

### Sync contract

- **A100** `Memo.id` is the spine: never regenerated; the audio filename embeds it; the Mac row id equals it; no `@Attribute(.unique)` — K:297 → fold into C96.
- **A101** `MemoAsset.kind` ∈ audio | photo | wordTimings | diarization | document; sidecar filenames `wt_<UUID>.json`, `diar_<UUID>.json`, photos `photo_<UUID>_NNN.jpg`, audio `memo_<UUID>.<ext>`, docs `file_<UUID>.<ext>`; one enhancement row per memo, newest wins on read — K:203,298-299, M:228 → fold into C96/C46.
- **A102** ASR language setting (English = mel on / Multilingual = mel off) syncs on the `VocabularyRecord` carrier with its own stamp; `LanguageSyncCore` never pushes an unchosen default; adopting a remote value drops the loaded ASR manager — L:294-295, D:163,187 [locked], D:399 → `- Cnew [auto] Language mode syncs both ways with its own LWW stamp; a default nobody chose never pushes || check: LanguageSyncCoreTests`
- **A103** Audiobook sync: per-book opt-in (local by default); raw `CKRecord` + `CKAsset` `ab_<bookID>_<i>` / `_cover` / `_t<i>` / `_al<n>`, fetch by id, Wi-Fi only; position + rate LWW by `modifiedAt`; bookmarks whole-list LWW; transcript sidecars sync and are RE-STAMPED to the receiver's audio; alignment applies only once the transcript matches; applied-marker records what it PRODUCED; unshare keeps local audio; Apple Books delete model — L:298-301, M:234-235,299-300, D:159,167 [locked] → `- Cnew [auto] Audiobook sync contract as L:298 (out of the rewrite, listed so nothing is lost) || check: AudiobookSync tests`
- **A104** Once-only UI flags live in UserDefaults, never in the synced record — D:165 [locked] → fold into C96.
- **A105** Silent push registered on both apps (sync in seconds even backgrounded) — M:237 → fold into C52 (Done-means depends on it).
- **A106** Schema is additive-only; renaming a `@Model` orphans rows; dropping a synced `@Model` risks a load `fatalError`; prod needs "Deploy Schema Changes" at promotion; `AudiobookAsset` kept dead — D:386, M:241 → fold into C96 + a promotion note (see B22).
- **A107** Minimum iOS 26; `Shared/` is a source folder compiled into both apps, not an SPM package — D:168,157 [locked] → fold into Not doing / C115.
- **A108** `PipelineFile.durationSeconds` reads numeric seconds AND legacy HMS; v2 writes one representation — K:311, L C20 → fold into C44.
- Trivia: containers/bundle ids (D:382,439); `eventChangedNotification` has no % (D:394).

### Recording & audio

- **A109** Mac live transcription doctrine: the note pane IS the draft; settled text is the user's (editable mid-take, engine only appends), the wet tail is the engine's; settle = TEXT STABILITY (two identical tail decodes); the RMS/VAD lane is DEAD on his mic — never re-tune levels, extend stability; Mac rotates 7 s, phone keeps its thermally-tuned 25 s; an edited take lands `transcriptUserEdited`, an unedited take waits for the file pass; seed ordering is a contract — L:339, M:256-257, D:191-192 [locked ⭐⭐], K:314, D:333 → `- Cnew [auto] Mac live draft rules as L:339; settle = stability, never levels || check: LiveRecordingDraft/Finalize tests`
- **A110** Route change: the tap is torn down + reinstalled in the current hardware `inputFormat` (validate with inputFormat, not outputFormat); never a permanent give-up; interruption `.ended` + foreground re-arm; capture watchdog rebuilds when the engine is dead > 2 s — L:317-318, M:251-252, D:185 [device-verified] → `- Cnew [auto] Recorder survives every route/interruption event as L:317; a 2 s watchdog || check: RecordingCore route tests; device round`
- **A111** Live captions auto-stop after 60 s (Never/30 s/1/2 min), transient; the live-transcription toggle is sticky and works mid-recording; one-shot transcribe for file/import, streaming only for the live screen — L:321-322 [locked], D:176 → fold into C101.
- **A112** Append: record more → transcribe → text appended with `\n\n`, audio merged sample-accurate, timings shifted by the precise base duration, `transcriptUserEdited = true`; must never silently add no text (`.transcribing` shown, retry, Error pill); pause hides the paused interval — L:326, K:313, B:91 → `- Cnew [auto] Append never lands empty; audio + text + timings merge atomically || check: MemoSaver append tests — L:326`
- **A113** Gain `.default`; a < 0.4 s take is discarded with "Nothing recorded"; camera on-demand as a sheet, never persistent — D:184,173 [locked] → fold into C100.
- **A114** App Intents are plain `AppIntent` + `openAppWhenRun`, never `AudioRecordingIntent` (SIGTRAP); no haptic in the auto-start path — D:177 [locked, device] → `- Cnew [auto] Intents stay plain AppIntent; no haptic before the session is ours || check: grep AudioRecordingIntent = 0 — D:177`
- **A115** Mac recorder = `AVCaptureSession` → `AVAudioFile`; input picked to avoid Bluetooth; no buffer in 1.5 s → named-device alert; TCC denial → typed refusal + Open Settings; needs the writer-queue drain on stop — L:338, D:193 [locked], B:93 → `- Cnew [auto] Mac recorder rules as L:338 || check: -recordcheck`
- **A116** Memo playback and the book session are mutually exclusive; ducks only on Play; `.notifyOthersOnDeactivation` skipped while a book session is active; book resumes only its own interruption pause and never over a live recording — L:335-336, D:190 [locked] → fold into C104.
- **A117** Book chunks skip the custom-vocab pass — D:197 [locked] → fold into C106.
- Trivia: caption polling pacing numbers (M:255), Live Activity (L:337), encoder settings (L:313), `[photo N]` ±12 anchoring (M:253).

### Audiobooks

- **A118** Capture ALWAYS records voice (no quote-only save; a bail discards); build-your-quote bounded ~90 s before + 8 lines after (4 un-chunked), no infinite scroll; pre-select the last sentence ended before the playhead — L:350-351, M:277,279 [locked] → fold into C104.
- **A119** ePub alignment: unique n-gram anchors → LIS → banded DP; exact per-word times; verdict aligned/partial/rejected with the MONOTONIC gate; `.epub` primary, `.txt` freebie, `.mobi` skipped; "ePub TOC wins" scoped to aligned files; attach during transcribe deferred; read-along display is a UNION (book text > bridged > ASR splice > gap fill ≥ 3), nothing deleted; collisions contested between texts only — L:359-362, D:207-210 [locked 2026-07-21/23] → `- Cnew [auto] Alignment + union-display rules as L:359-360 || check: EPubAlign tests, -readalongcheck`
- **A120** `detectedChapters`: `[]` = ran-found-nothing, nil = not yet (reset to nil to retry); sidecar time basis (fileIndex, file-local); a quote span never crosses a file boundary; `ChunkFusion` cuts at the last complete sentence, a cancelled chunk redoes the same frontier; speed estimate only from measured RTF — D:409,411, L:355, M:283 [locked] → fold into C105/C106.
- **A121** Tab IA = Notes · Books · Review · Settings (Highlights cut, Library → Books, "Journal" → "Review"); Notes-tab book presence = card-at-rest / pill-when-live; iPad shelf grid stays, ONE player at every width — M:294-296,301 [locked] → fold into C108 / a UI clause.
- **A122** Bookmarks never export to the vault — L:367 [locked] → fold into C61.
- Trivia: `ChapterDetector` heuristics (L:358), sidecar schema numbers (D:409), session auto-end 2 h (L:369).

### Search & Connections

- **A123** Grain = ONE gist vector (title + summary + place + people + tags) + body chunks every ~150-200 words at sentence boundaries; `**Name:**` headers stripped; relevance = max over vectors; trashed excluded, captures included, book sidecars out; stale `modelRev` vectors excluded — M:313 [locked], L:379 → `- Cnew [auto] Index grain as M:313; a stale-model vector is never scored || check: EmbeddingIndex tests`
- **A124** The vault is NEVER indexed in v1; corpus = Skrift memos only; "juxtapose, don't judge" — no sentiment/stance/mood inference — M:318-319 [locked] → fold into C109 + Not doing.
- **A125** Search "Related" appears only when the query has ≥ 2 words or exact hits < 3; top 8 above floor; Then-vs-Now (last ~2 weeks vs ≥ 6 months older); "Important lately" = ≥ 0.8 in ~30 days; Looking back = 1 w / 1 / 3 / 6 / 12 months, highest importance per window, "On this day" — M:316,320, L:388-389 [locked] → `- Cnew [auto] Review surfaces' selection rules as M:316-320 || check: ThenVsNow / LookingBack tests`
- **A126** Connections chrome: summoned by the WORD (no glyph, no count); Mac = floating inspector that stays open; iPad = per-note visitor sheet; thread retired on iPad/Mac, kept on the phone card; embedder yields the ANE while transcribing, held 10 min — L:380-383,390, M:322-324 [locked] → `- Cnew [tuur] Connections matches related-panel v3 + chrome-belongs v2 — M:322-324`
- **A127** Print-to-wall: crossing INTO ≥ 0.8 auto-prints ONE card to the saved AirPrint printer (offline queue), `printedAt` idempotent — L:418, M:333 [locked 2026-07-07/10] → `- Cnew [auto] Wall print fires once per note on crossing 0.8 || check: WallPrinter tests`
- **A128** Map contract on all devices: owned camera, dive-down only, pin tap never zooms out; the map is a MODE of the column — L:412, M:327-328 [locked] → fold into a UI clause.

### Editor, note UI

- **A129** Editor "must not break" list for C113's rebuild: inline `[[img]]`, capture-quote protection, speaker-turn view, `transcriptUserEdited`, save-now, polished-body editing, paging; swipe-between-notes is OFF on the phone — M:347, L:400 [locked] → fold into C113.
- **A130** Locked built-UI rules the spec references only via C117/C118: phone editor = ONE UITextView with B2 pinned title; accessory bar undo · redo | ☑ · 📷 · → · 🔍 · Done; compact player pill; tag chips with explicit ✕; photo tap → QuickLook markup saved INTO the file + OCR rescan; share-out = markdown + audio; ONE funnel filter; iPad header = Mac sidebar; Mac note header; regular-width iPad chrome; ⋯ menu single-sourced (`NoteMenuItem`) — L:397-411, M:343-365, D:244 → `- Cnew [tuur] Built UI matches the S+B rows of mocks-roadmap §B; any deviation is a defect — M:412-486`
- **A131** Desktop note view is an EDITOR, WYSIWYG to the exported markdown ("what you see = what ships") — D:231 [locked] → fold into C116.
- **A132** Phone search = full-text over transcript + tags + place name; OCR hits in LIST search only — D:227 → fold into C111.
- Trivia: design tokens (D:424); glass `.clear` (D:235); karaoke in the same NSTextView (D:236); `DriftedPair` eyeballs (L:416).

### Privacy

- **A133** Privacy reframe: the rule targets cloud LLMs / big-company AI; Skrift's OWN code may read its exports or the vault (titles for the roster, tag names, a later opt-in lens); the dev-time rule (agents never read his real vault; never screenshot the live app at a real note) still binds — D:254,261 [locked] → fold into C120/C122.
- **A134** Weather = OpenWeatherMap with his own API key — D:433 → fold into C120/D29.

---

## B · NEEDS-VERDICT ITEMS NOT IN D1–D34 (nor parked)

| # | Question (one line) | Proposed default | Blocks |
|---|---|---|---|
| B1 | On truncation/shrink the iPad returns the marker-stripped `input` into the escrow, the Mac returns the pre-escrow `text` — which path? — K:103 | Pre-escrow original body on both (C31 doctrine) | target 2 |
| B2 | Reinsert pictures by PARAGRAPH index (C30, D:449) or by SENTENCE index (K:110)? | Paragraph (C30) | target 2 |
| B3 | Mac export resolves images via the `images/` DIRECTORY, the phone/review via the manifest — K:247 | Manifest only, both apps | target 4 |
| B4 | Make `PipelineFile.significance` non-optional (0 = unrated) once the floor is written back? — K:283 | Yes, in target 3 | target 3 |
| B5 | `transcriptMarkersInjected` is dead on the Mac — keep on the wire, drop the reader? — K:27 | Keep additive, delete the Mac forward, document the thumbnail reader | target 1 (small) |
| B6 | Delete `processEverything` (documented dead 2026-07-21, still threaded + tested)? — K:306 | Delete | target 3 |
| B7 | Mint the memo id first for Mac recordings so filename UUID == memo id and `resolve` collapses? — K:188 | Yes | target 3 |
| B8 | Rename `PipelineFile.uploadedAt` (it is the content date)? — K:195 | No rename; add a computed `contentDate` | none |
| B9 | What does the refine pass (≥ 0.8) do in v2 — keep or drop? — L:75 | Drop unless Tuur names its output | target 2, D30 |
| B10 | Collapse the lenient desktop decoders (`PhoneMetadata`, `SharedContent`) into one shared `init(from:)` with goldens? — L:112, M:243 | Yes, target 3, goldens first | target 3 |
| B11 | Delete the dead publish-gate legs (`isMacPaired`, `publishWhenPaired`, `.all`)? — K:260 | Delete | none |
| B12 | `NamesMerge` millisecond tie → remote; write-back LWW has no skew tolerance — rule? — L:253, B:28 | Tie = deterministic by device-id order; ±5 s skew tolerance on write-back | target 3 |
| B13 | Should trashing a note delete its Obsidian `.md`? — L:113, D:473 | No (Skrift never deletes vault files, A57) | none |
| B14 | Is Mac→phone body-edit sync (`MacCloudEditSync`) complete/in v2 scope? two-device round owed — L:114, M:244 | Keep as-is, device round owed | none |
| B15 | `includeAudioInExport` — sync as a `Memo` field or stay Mac-only? — L:160, M:240, B:41 | Mac-only in v2; iPad switch hidden | none (C-A59) |
| B16 | Wave-2: does a PDF's extracted text go into the exported body? — M:118 | No — embed + ramble only; text is search-only | target 4 |
| B17 | Keep the `MemoExporter` share verbs (markdown/PDF/plain/quote card) + batch export? unverified in FEATURES — M:119-120 | Keep outside the compiler rewrite; batch export owes a device look | none |
| B18 | Split-note hybrid / per-book quote aggregation excluded from the v2 compiler? — D:469, L:159, M:121 | Excluded | target 4 (scope) |
| B19 | Auto-publish after Process on iPad/Mac? — D:471 | No first-export automation; Mac re-export sweep stays (A49) | none |
| B20 | Obsidian profile keeps `source: capture-url` while the archive uses `capture:` — unify? — D:476 | Leave | none |
| B21 | One-time adopt-by-content for his pre-stamp legacy exports? — D:477 | No; delete-and-re-export by hand | none |
| B22 | Prod CloudKit schema deploy + Release App-ID capabilities — when? — M:238, D:465,544 | At prod promotion after v2; Dev only until then | none (promotion) |
| B23 | Drop `Memo.syncStatus` (dead under CloudKit) and the Unsynced filter? — K:305 | Keep the field, remove the filter | none |
| B24 | Video + link inside a multi-item WhatsApp bundle: own memo, ride along, everything-in-one? — L:173, I:22-26 | Video = own memo; link rides the note as a card | C67/C68 (ingress) |
| B25 | WhatsApp photo shared WITH a caption: caption → annotation or dropped? — I:161,456 | Caption → annotation (like B3 text) | C68 (ingress) |
| B26 | Audio-only `.mp4` opened on the phone: probe for a video track (Mac parity)? — I:229,457 | Yes | C69 |
| B27 | Voice-annotate a capture in-app (dictation model v1, unverified): does the Mac ingest the dictation asset? mic pill on captures only? — M:150,152 | Captures only; Mac maps the asset in target 3 | target 3 (small) |
| B28 | Video share keeps the typed thought (built) or audio's no-ramble rule? — M:151 | Keep the thought | none |
| B29 | Messenger chat-export `.zip` — L:195 | No | none |
| B30 | Capture-as-note (annotation folded into the body, file/PDF as a body block; roadmap CapNote `inprogress`) — in the body v2 scope? — M:371, D:482 | After body v2, mock first; body v2 must leave room for a file block | target 1 (shape) |
| B31 | i10 full markdown body (bold/italic/highlight/strike) — after v2? — M:370 | After v2 | none |
| B32 | On-device iPhone polish (P4) still wanted now the iPad polishes? — M:394, D:458 | No for v2; spike stays parked | none |
| B33 | Does a memo-link FROM an unrated note count as the backlink that holds a note off the clock? — D:499 | Yes (any live memo) | none (state in C89) |
| B34 | i2 auto-prune of significance-0 — dead (absorbed by fading)? — M:219, D:498 | Dead | none |
| B35 | Phone keeps its "People in this note" chip bar while the Mac killed it — keep the asymmetry? — D:490, M:565 | Keep (phone), Mac prose-only, stated | none |
| B36 | Mac name-a-speaker review UI (mock signed, backend done) — owed? — D:491, M:447 | Owed, after v2 | none |
| B37 | Genuine alternate nicknames vs normalise everything — L:229 | Normalise (registered aliases only) | none |
| B38 | Auto re-export exported notes after a roster collision? — L:237, B:66 | No; next content change re-exports; log the count | none |
| B39 | Tag normalisation ("filosofaties") in scope? — D:493 | Out | none |
| B40 | Dutch corpus gap: add 5 throwaway Dutch rambles recorded in Dev? — D:487 | Yes (Dev-recorded, still not his real notes) | C4 wording |
| B41 | Summary prompt quality / context-aware title hints — does v2 own it? — D:456-457 | No; prompts frozen; no context (A22) | none |
| B42 | Reading-mode redesign built or not (STANDALONE_PLAN built vs CLAUDE.md not built)? — L:372, D:517 | Built (F:196-210, R D3 done); only themes remain — C108 stands | none |
| B43 | `BookBundle.derivedSidecars` packs a rejected/empty alignment sidecar — fix in v1? — L:365, B:60 | Fix in v1 now | none |
| B44 | Always-warm ASR engine intentional? measure battery — D:510 | Intentional; measure once | none |
| B45 | WeatherKit vs OpenWeatherMap — D:513 | Keep OWM + his key; D29 states it | none |
| B46 | Keep or retire the XCUITest suite (17 iOS-26 failures)? — D:543 | Retire; unit suite is the gate | gate |
| B47 | Does "AI READS THIS" also license a future in-app agent over `_ideas/`? — D:540 | Yes — that is the point of the archive | none (state in C121) |

Parked in the reports but missing from the spec's parked list (add so the sitting can skip them): per-book quotes page / i16 (L:159,374); ePub images in the reader, per-book language, cross-chapter quotes (L:373); P9b player polish (M:305); i21 unlinked-mention mining (M:184); names → vocab auto-boost (L:252); place-triggered resurfacing (L:433); query expansion / themes / i18 (L:393, M:336); P7 people pages (M:398); i6 Mac Names parity (M:183); scan-into-this-note (M:374); lasso multi-select (M:376); wall-card design round (M:338); Mac in-place linking (M:378); `SkriftDesignKit` package (D:504).

---

## C · CONTRADICTIONS

### C1 · Inside SPEC.md

| # | Clauses | Disagreement | Fix |
|---|---|---|---|
| 1 | C91 ↔ D22 | C91 cites D22 for "does a locked note get polished"; D22 is the text-file share. The lock question is D10 | Repoint C91 → D10 |
| 2 | C94 ↔ D24 | C94 cites D24 for the importance control; D24 is offline conflict; the control is D30 | Repoint C94 → D30 |
| 3 | C98 ↔ D25 | C98 cites D25 for offline conflict; D25 is "shares default to 0"; offline conflict is D24 | Repoint C98 → D24 |
| 4 | C73 ↔ D22 | C73 asserts `.txt/.md` share → note body; D22 leaves body-vs-card open | Mark C73 ⚠ needs-verdict D22 or close D22 |
| 5 | C1 ↔ C113 | C1: views not rewritten, no v2 file under `Features/`; C113: the editor is rebuilt on body v2 | C1 gains "except the editor rebuild of C113, after target 1" |
| 6 | C61 ↔ C57/C64/C81 | C61 "the phone does not export"; C57/C64/C81 diff "phone" exports. The iPad is the SkriftMobile target | Say "iPhone does not export; iPad + Mac do" and write "iPad" in the checks |
| 7 | C63 ↔ C71 | C63 "video is never exported … markdown + audio + frame"; C71 keeps `source.<ext>` on the Mac — and K:248 says the archive export copies it | See C2-3; C63 must carve out the archive |
| 8 | C36 ↔ C29 | C36 "a capture gets … no copy-edit"; C29/C31 copy-edit a quote-capture's ramble. "Capture" is ambiguous (share capture vs quote capture) | C36: "a SHARE capture"; C29: "a QUOTE capture's ramble" |
| 9 | Gate ↔ clauses | Gate refers to "C-V2 below"; no such clause exists | Name the clause (C5/C6) |
| 10 | C56 ↔ C55 | C56 lists keys in an order that is not the code's grouped order and omits `pressureTrend`; C55 promises stable order | Copy K:210's order into C56 |
| 11 | C10/C12/C20/C25 ↔ D1/D2/D5/D6 | Clauses state as rule what the decision leaves open (marked ⚠, acceptable) — but C20 "ONE gap constant" and C25 "ONE ladder" read as decided | Keep the ⚠ marks; move the "ONE" wording into the D default |
| 12 | C42 ↔ C97 | C42 re-transcribes an untrusted transcript; C97 never re-transcribes another device's in-flight memo — true together only because in-flight = `.transcribing` and untrusted = `.done` low-confidence | Add the status distinction to C42 |
| 13 | Decisions "2026-08-11 … the picked folder is the consent" | That decision is dated 2026-08-18 (L:130, b151) | Fix the date |
| 14 | C61 check `applenote-dutch` never appears in the vault | No clause explains why an Apple Note never exports | State the reason (unrated in the corpus?) or drop the check |

### C2 · SPEC clauses vs a [locked] report decision

| # | Clause | Locked decision | Resolution to state |
|---|---|---|---|
| 1 | C10, C17 | L:22-23, K:34,51, D:19-20 (2026-07-16): stored RAW keeps the marker at its recorded moment; renderers + export SNAP | v2 supersedes this via D1 — say "supersedes 2026-07-16" in C10 |
| 2 | C25 "derived titles clip at 80 on a word boundary" | L:41, K:254, D:245: `exportTitle` KEEPS the hard `prefix(80)` slice for the filename | C25 gains "never the filename (A53)" |
| 3 | C63 "video is never exported" | K:248 (Tuur 2026-08-28 "that is gold"): the Mac keeps the source movie and the ARCHIVE export copies it | C63: "no video to the vault; the archive export copies the Mac-kept movie" |
| 4 | C53 "no forced subfolders … the picked folder IS the destination" | K:232 (2026-08-14, vault-folder-model): media go to fixed `Recordings/ Images/ Documents/`; a pick that is neither named Skrift nor contains one gets `<pick>/Skrift` created; Not doing says "no `Skrift/` prefix forced" | State `VaultLayout.home` verbatim (A54) and let D11 decide the `<pick>/Skrift` creation case |
| 5 | C93 "destination words are accepted as tags" | L:146 (2026-08-26/28): four words RESERVED, only `#inspiration` re-allowed | Code (`Memo.swift:270-289`, 2026-08-27) accepts all four; L:146 is stale — say so in C93 |
| 6 | C80 link literal `[[Canonical\|spoken]]` | K:268 + `Sanitiser.swift:1-5`: first mention = bare `[[Canonical]]` (+possessive outside), later = short; conversation inline = `[[Canonical\|short]]`; L C7 final = short; M:160 (phone mock) = `\|spoken` | Pin the literal per case from the code; the phone mock's "spoken" is display, not storage |
| 7 | C20 "ONE gap constant" | D:41, K:59 (Tuur ROUND 10/11 2026-07-28): `longFormGap` 2.0 s shared, phone live 0.65 s "untouched" | C20 reverses a Tuur round — D5 must say it is a reversal |
| 8 | C62 "drops places" | K:225: archive KEEPS `location:` in frontmatter; only body place LINKS plainify (L:149 "places do NOT" = links) | C62: "place links plainified; `location:` kept" |
| 9 | C10 "old notes normalised once on read" (D4) | L:213 (2026-07-10): old test image-captures stay broken, no migration; B:54: legacy PDF captures stay text-only by design | D4 must list which legacy shapes normalise |
| 10 | C40 "the Mac never auto-re-polishes" only | K:141 (Tuur 2026-07-23), M:53: the iPAD never auto-polishes on open either | Add A28 |
| 11 | D10 default "a locked note is never processed" | K:292: locked notes keep processing in v1 (only export refused); L:140 "excluded from publish only" | State D10 as a change from v1 |
| 12 | C89 "touch restarts 30 days" | D:135 (2026-07-18): photos and bare captures are NOT touches; K:289: rating changes never call `markEdited` | Define touch (A90) |

### C3 · Ledger §C (20) and mocks §D (30): does the spec state the resolution?

| Src | # | Topic | Stated? | Where / what to state |
|---|---|---|---|---|
| L | C1 | shared picture TOP | yes | D2 (open) |
| L | C2 | export root | partly | C53; state `VaultLayout.home` (A54) |
| L | C3 | share-sheet dictation | yes | Decisions 2026-07-10 |
| L | C4 | whole-book transcribe | yes | C106 |
| L | C5 | Low Power Mode | yes | C106 |
| L | C6 | fading touch list | partly | C89; define touch (A90) |
| L | C7 | conversation inline links | no | C80 says spoken; ledger final = short; code = bare first mention — pin per C2-6 |
| L | C8 | `#inspiration` tag | yes | C93 |
| L | C9 | Flag verb | yes | Not doing |
| L | C10 | WhatsApp audio-as-link fixed | yes | "Already fixed" by reference |
| L | C11 | wrong file cite | n/a | — |
| L | C12 | SpeakerTranscript dedup done | n/a | — (twin risk M:185 → note in C115) |
| L | C13 | phone publishes photos | no | C61: "the iPad exports photos + audio through the shared engine" |
| L | C14 | vocab synced | yes | C103 |
| L | C15 | plugin live only | yes | Not doing |
| L | C16 | already-fixed list | yes | R section |
| L | C17 | audit corrections | partly | C96 (plain Data); `callStackSymbols`-not-in-Release is process |
| L | C18 | handoff over-fit | n/a | — |
| L | C19 | video "vanish" | yes | C66 + C70 |
| L | C20 | durationSeconds HMS vs Double | no | C44: v2 writes numeric seconds; the Mac reads both (A108) |
| M | 1 | reading mode built | yes | C108 (⚠) |
| M | 2 | book sharing signed | yes | D27 |
| M | 3 | journal-desktop built | yes | C119 |
| M | 4 | photo block export changed | yes | C17/C65 |
| M | 5 | flag-to-send vs process | partly | C87; add "sync is unconditional" (A99) |
| M | 6 | Waiting sync pill | no | state: no per-memo sync pill; `syncStatus` dead (B23) |
| M | 7 | fading doctrine | yes | C89 |
| M | 8 | diarization heal | yes | C45 lists diarization (= shipped) |
| M | 9 | FluidAudio pin | no | A2 names v0.15.5 |
| M | 10 | thread view | no | A126 |
| M | 11 | chapter precedence | yes | C105 |
| M | 12 | standalone-export vs SharedExport | yes | C53/C61 (batch export → B17) |
| M | 13 | per-occurrence vs whole-note | yes | Not doing |
| M | 14 | include-audio on the phone | no | A59 |
| M | 15 | BookTranscript local-only | no | A103 (sidecars sync, re-stamped) |
| M | 16 | silent 0.1 | yes | C40/C49 doors; no button floor |
| M | 17 | CloudKit schema freeze | no | C96: additive fields allowed in Dev, prod deploy at promotion (A106, B22) |
| M | 18 | Journal vs Review | no | A121: the tab is "Review" |
| M | 19 | Podcasts node | yes | D33 |
| M | 20 | onboarding two nodes | n/a | roadmap hygiene |
| M | 21 | NFeat win vs reminders | yes | C92 ⚠ |
| M | 22 | book-text-unified header | yes | C108 |
| M | 23 | fading-shelf placement | no | A93 (placement B) |
| M | 24 | CLAUDE.md `CaptureMomentView` stale | no | D34 repoints CLAUDE.md — add the line |
| M | 25 | related-panel chrome superseded | no | A126 |
| M | 26 | IPAD_PLAN polish-on-open | no | A28 |
| M | 27 | Highlights tab | no | A121 |
| M | 28 | vocab per-device stale | yes | C103 |
| M | 29 | chip-bar asymmetry | no | B35 |
| M | 30 | mock count | n/a | — |

Report-vs-report disagreements the spec should settle explicitly: voice-enrolment floor (L:248 "≥ 3 s / 32 000 samples" vs D:363 "32k = 2 s" vs M:172 "≥ 2 s"); read-along `lead` (L:366 0.1 s vs D:415 0.3 s); Queue band (M:200 "Not in the pipeline · N" Q1) vs "the band is dead" (L:276) — both 2026-07-21, the 2026-07-26 projection model wins; `MemoNoteProjection` "inherits the duration bug" comment is stale (K:197).

---

## D · UNSOURCED CLAUSES (content not found in any report or cited code)

| Clause | Unsourced part | Note |
|---|---|---|
| C7 | Recorded model outputs keyed by sha256(prompt+input); a miss runs live | Drafter's harness design; no report mentions a recording cache |
| C9 | "one `-corpus`-driven scenario per swap" | D:466 only asks "which ones" (backlog 654-657) |
| C13 | "two pictures in the same second … manifest order" | Derivable (K:18 manifest order, M:16 "both blocks in order") but the same-second case is invented |
| C19 | "ONE rule applied at WRITE" | v1's `tidyWhitespace` lives in the copy-edit path (K:108); moving it to write is the drafter's |
| C27 | "no mock needed for the body v2" | Not in any report |
| C72 | "no title → the host as title, never the raw URL" | I:116 says the card already shows the domain; no report says v1 shows the raw URL |
| R10 | "v1: raw URL as title → v2: host as title" | B:50 registers the JS-rendered-page item as needs-verdict D14/D15, not as "host as title"; as written R10 may pre-register an IDENTICAL output as a required difference, which C5 would then FAIL |
| C112 | Lock-screen / Control Center / Siri "New Note" in under a second | Tuur's 2026-09-21 words are quoted in Decisions but appear in no report; L:414 has only "phone new-note button + Apple Notes bar" |
| C113 | "a picture is a block he can move" as part of the editor bar | Same sitting; drag-reposition is B:900 (mock-first) |
| C114 / D28 | What the app opens into | Not in any report |
| C122 | "`-corpus` refuses a path under his real vault" | Not in any report or code (no such guard found); fine as a new rule, but it is new |
| Decisions | "2026-09-21 Dev only during the rewrite; v2 beside v1; tag before each swap" | Beside-v1 is D:16; the tag-per-swap and Dev-only are the sitting's, not a report's |

---

## E · INVARIANTS (code-core §B, 54)

| Status | Invariants |
|---|---|
| In C6 | 3 (round-trip), 5 (markers in = out), 24 (stranded = 0), 38 (names.json bytes); "paragraph count never drops" is in C6 but NOT in §B as a whole-body invariant (16/17 are narrower) |
| In another clause | 2 (C18), 8 (C20), 9 (C18), 10 (C14), 11 (C21), 14 (C31), 17 (C34), 18 (C32/C33), 20 (C36), 21 (C36), 22 (C28), 23 (C37), 25 (C41), 27 (C48), 28 (C41), 29 (C46), 31 (C47), 33 (C42), 34 (C44), 35 (C45), 36 (C49), 39 (C56), 41 (C55), 42 (C54), 43 (C54), 46 (C57/C59), 47 (C62), 48 (C56), 49 (C61), 50 (C61), 51 (C55), 52 (C87) |
| Partial | 12 (C26 lacks "monotonic, one per word"), 16 (C34 states shipped ≥ input, not input ≥ raw), 19 (C32 lacks "monotonic in length"), 26 (C41 lacks the legacy-filename claim), 30 (C47 lacks "nil title never clears"), 32 (C46 lacks "row count stays 1" and skew), 40 (C54 lacks "single char → userEdited; no frontmatter → foreign"), 45 (C57 lacks "same relative path from both apps"), 54 (C89/C90 lack "purge false when trashSeenAt < deletedAt"), 4/6/7 (snap invariants — obsolete under C17; say so) |
| Missing | 1 (pieces cover raw exactly), 13 (identity-generator escrow round trip), 15 (quote-only never calls the generator), 37 (reflectTranscripts only .done into empty own memos), 44 (retitle keeps path; fresh ledger adopts), 53 (MemoSpine one station + pinned copy trio) — plus the three obsolete snap invariants (4, 6, 7) need a replacement invariant: "no `[[img_` inside a sentence in any stored body" |

C6's "54 listed" claim is therefore true only by reference; 6 invariants have no clause, 9 are weaker in the clause than in the test, and 3 (snap) die with C17 and need a replacement.

---

## F · REQUIRED DIFFERENCES missing from R1–R15

Inside the four targets (verified-open or lead in `bugs-preregistered.md`):

| # | Bug (v1 → v2) | Src | Status | Suggested row |
|---|---|---|---|---|
| F1 | Mixed WhatsApp bundle (8 clips + 1 picture) marker mid-transcript → own paragraph at the C12 spot | B:9 | lead | R1 covers the timeless case only; add the P3 fixture explicitly |
| F2 | Stale `ambiguousNames` offsets after body migration → re-sanitise once | B:12 | lead | new R (D4 mentions it, no R) |
| F3 | Conversation turn split by a photo leaks out of the gutter → turn continues | B:13 | lead | corpus `conv-with-picture` (D3) — renderer, mark as identical-or-diff explicitly |
| F4 | Prod prompt override shadows the default → one prompt source | B:20 | lead | new R tied to C39/D9 |
| F5 | Slab-note redo ledger unread → corpus replay shows `in N → model N → shipped N`, N ≥ author's | B:21 | lead | new R (typed-wall corpus note) |
| F6 | `NamesMerge` ms tie favours remote; write-back LWW no skew tolerance | B:28 | lead | new R (B12) |
| F7 | Mac blob-faulting sweep (`adoptLateDiarization` guard never false) → metadata-only steady sweep | B:30 | lead | C45 states it; add as R (measurable: 0 blob fetches on an unchanged corpus) |
| F8 | Diarization late-asset heal never exercised → rating a conversation whose `diar` trailed yields turns | B:32 | lead | corpus scenario (C9) |
| F9 | Vault scan uncapped on main per updated row → capped/indexed off main | B:33 | lead | perf; state as invariant not R |
| F10 | Frontmatter migration per-note (old key order stays until re-export) → rule stated or bulk verb | B:40 | lead | needs verdict (not in D) — add D |
| F11 | `includeAudioInExport` not synced → syncs or stated | B:41 | lead | B15 |
| F12 | Roster-collision re-scan doesn't touch exported `.md` | B:66 | lead | B38 |
| F13 | Mid-body `> ` blockquote gets name-linked → never | B:67 | lead | C82/D21 — add as R once D21 closes |
| F14 | Stale `**Name:**` turn markers baked into monologues → never; bulk un-diarize path | B:68 | lead | new R (`SpeakerTranscript` is in target 1's inventory) |
| F15 | Phone `SpeakerTranscript.parse` not pipe-aware; `*` in a speaker name breaks the Mac regex | B:69 | lead | new R (target 1 file) |
| F16 | Conversation-turn edits + C3 annotation edits don't bump `editedAt` | B:77 | lead | new R or stated exception (touch rule A90) |
| F17 | Two rows carry a literal `"[]"` tag → cleanup or accepted | B:78 | lead | corpus `typed-bracket-tag-bug` is in C93's check; say cleanup-or-accepted |

Ingress-adjacent (feed target 1; not in R): GIF flattened / PNG lossy (B:52 → C74/D17); Mac-local ingests never OCR'd + OCR hit can't flash (B:55); Mac `.file` capture has no pinned block / PDF first page (B:53 — view, C119); old PDF captures never sync their document (B:54 — identical by design, pre-register); Signal multi-select via `loadFile .first` (I:80 — fold into R4); open-in ignores `.ogg/.oga/.m4b/.pdf` (I:230 — not in bugs report at all).

Pre-register as IDENTICAL but currently unstated: `goo.gl` plain card (B:51), silent video `.failed` (B:58), `purgeExpiredTrash` before first frame (B:76), duration chip regression guard (B:42).

R-table defects: R10 (see D) may fail C5 by construction; R11's fix key (`sourceType` vs `mediaSource`) is a reader change, not an output diff — state which side moves; R13 (Mac honest refusal) has no corpus note.
