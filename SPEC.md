# SPEC — Skrift

DRAFT 2026-09-21, written from the extraction in `plan/extraction/` (five reports: ledgers,
bugs, code, ingress, mocks/roadmap, decisions — every clause below cites one of them or a
file). Status of this file: **not yet confirmed by Tuur.** The sitting goes through
"Open decisions" first, then strikes anything outdated in the clauses. A clause he does
not confirm does not go into v2.

Marks: `[auto]` = a machine can check it (the check follows `||`); `[tuur]` = only his eyes
or hands can judge. `⚠ unverified` = built on main, never seen on a device by him.
Sources: `X:` = `plan/extraction/X.md`; `F:` = `FEATURES.md`; `B:` = `backlog.md`.

## Point

Skrift is Tuur's capture tool for his second brain. He records a voice note on his iPhone
(or types one, or shares a link, picture, PDF, video, or an audiobook quote), it is
transcribed on the device with nothing sent anywhere, and once he rates it his Mac or iPad
cleans it up with a local model, links the people it is about, and writes one Markdown file
into the folder he chose: his private Obsidian vault, or the public archive that AI may
read. Obsidian is home; Skrift is the front door. One user, fully offline, sold flat, no
cloud AI. The long game is decades of notes he can look back through.

## Done means

- On the iPhone 13: tap record, words appear while he talks, stop, and the note is in the
  list within a second, playable, its pictures as their own blocks in the right place,
  unrated and grey, nothing processed or exported.
- On the Mac: the same note is there when he clicks the window; he rates it and presses
  Process; the polished body, title and summary show up on the phone and iPad within
  seconds; the raw transcript is still underneath.
- In Obsidian: exactly one file for that note in the folder he picked, people as
  `[[links]]` and in `people:`, pictures embedded, the stamp in the frontmatter; once he
  edits that file Skrift never touches it again; a note filed Idea lands in
  `_ideas/<name>.md` with his friends credited.
- Quick note: from pocket to typing in one second, from the lock screen or the app; the
  editor feels like Apple Notes.
- On the corpus: every v2 output is identical to v1 or a pre-registered expected
  difference; the invariants hold; each v2 subsystem is at most 40% of v1's lines or says
  why; he has read the corpus output and it reads right.

## Gate

`./gate.sh` — the Mac unit suite (MLX-free, seeds the whole corpus and proves the
rate→row invariant over all 106 notes). Measured 2026-09-21: see the end of this file.
The v2 diff harness joins the gate when the first subsystem lands (C-V2 below).

---

## Clauses

### The v2 method (Tuur 2026-09-18)

- C1 [auto] v2 is built one subsystem at a time, in this order: body/image model → copy-edit
  → reconcile sweep → export compiler. Views, the CloudKit schema and the audio/hardware
  paths are not rewritten. || check: no v2 file under `Features/`, `Shared/Model/*@Model`,
  or `Services/Recording/`. — decisions:14-15
- C2 [auto] v2 lives beside v1 in `Shared/`; the app calls v1 until the subsystem's gate is
  green and Tuur has read its corpus output; v1 is deleted in its own commit after a git tag
  `v1-<subsystem>`. || check: tag exists before the deletion commit. — decisions:16
- C3 [auto] Size budget: v2 ≤ 40% of v1's lines for that subsystem, else the commit message
  says why. Baselines (code-core §C): body/image 7,940 · copy-edit 2,674 · reconcile 5,297 ·
  export 2,734. || check: `wc -l` of the v2 files vs the inventory table. — code-core §C
- C4 [auto] The corpus is synthetic, never his notes: `test-fixtures/corpus/` (106 notes,
  fictional roster), seeded on both apps with `-corpus <path>`. || check:
  `CorpusSeedTests` on both apps. — decisions:260
- C5 [auto] v1 is the change detector, never the judge: every corpus output is classed
  identical / expected-different / unexplained; a pre-registered bug where v2 matches v1
  FAILS. || check: the harness exits non-zero on any unexplained or matched-bug row.
  — decisions:17
- C6 [auto] Invariants the harness checks without v1: markers in = markers out; paragraph
  count never drops unless the shrink guard fired; editor round-trip returns the identical
  string; every transform is idempotent; no rated live memo without a Mac row; `names.json`
  re-encodes to the same bytes on both apps. || check: harness invariant suite (54 listed
  in code-core §B). — code-core §B
- C7 [auto] Recorded model outputs are keyed by the exact prompt text and input; a miss runs
  the model live, never fails silently. || check: harness cache key = sha256(prompt+input).
- C8 [tuur] He reads the corpus output for each subsystem before the swap.
- C9 [auto] Per-subsystem end-to-end scenarios (rate→row style) run on the seeded Dev
  store, not on unit fixtures. || check: one `-corpus`-driven scenario per swap.

### Body/image model (rewrite target 1)

- C10 [auto] A picture is its own paragraph, always: the stored body has `\n\n[[img_NNN]]\n\n`
  between paragraphs, never inside a sentence. Enforced where a body is WRITTEN (capture,
  share, edit, import); old notes normalised once on read. || check: corpus notes
  `pic-*` — no marker inside a sentence in any stored/exported body. ⚠ needs-verdict D1
  — B:694-702
- C11 [auto] A timed picture lands after the sentence being spoken at `offsetSeconds`
  (sentence end, not nearest word). || check: `pic-mid-sentence` → marker after "…the
  glaze." — B:679, decisions:450
- C12 [auto] A picture with no moment (shared, editor-inserted, video frame) goes to the TOP
  of the note as its own paragraph. || check: `cap-image-voice-ramble`, `pic-shared-no-
  timestamp` → body starts with the marker. ⚠ needs-verdict D2 — B:695
- C13 [auto] Two pictures in the same second are two consecutive picture paragraphs in
  manifest order; none merged, none dropped. || check: `pic-two-same-second`.
- C14 [auto] The marker is `[[img_NNN]]`, `%03d`, 1-based into `imageManifest`; deleting a
  picture removes the marker, never the manifest entry (no renumbering). || check:
  `MemoDisplay` thumbnail rule; corpus `pic-missing-file`. — ledgers:17-18
- C15 [auto] Marker width: every reader accepts `\d+`, every writer emits `%03d`. || check:
  one shared regex; no `\d{3}`-only matcher remains. — code-core (needs-verdict, marker width)
- C16 [auto] The photo's true moment is `imageManifest.offsetSeconds`; body position is
  derived. Drag-to-reposition (later) moves the paragraph and rewrites `offsetSeconds`.
  || check: reposition test once built. — B:677
- C17 [auto] With C10 the render-time snap (`snapImages`, `SnapResult`), the display-only
  `imageBreaks`, and the export-time snap are deleted; the three stacked offset remaps
  collapse to one (marker → one glyph). || check: files gone; name-span offsets computed
  once. — B:698-702, code-core §C remaps table
- C18 [auto] `BodyTransform` stays the ONE raw ⇄ display transform: `[[img_N]]`,
  `[[memo:UUID|Title]]`, line-start `- [ ]`/`- [x]` each collapse to one glyph; text passes
  verbatim; reconstruct is byte-exact. || check: `NoteBodyTests` round-trip; corpus
  `typed-tasks`, `typed-memo-links`. — ledgers:27
- C19 [auto] Whitespace normalisation is ONE rule applied at write: horizontal runs inside a
  line → one space; ≥3 line breaks → one blank line; CRLF → LF; ends trimmed. || check:
  corpus `typed-crlf-tabs-nbsp`, `voice-en-triple-blank-lines`. — B:727
- C20 [auto] Paragraphing from speech: break before a word when the previous word ends a
  sentence AND (pause ≥ gap OR 4 sentences reached); text that already has a newline is
  untouched. ONE gap constant on every device. || check: `Paragrapher` tests; ⚠
  needs-verdict D5 (0.65 s phone vs 2.0 s Mac today). — code-core Paragraphs
- C21 [auto] An editor commit sets `transcriptUserEdited = true` and `editedAt`; a capture
  commit keeps the raw quote block as an exact prefix. || check: `NoteBodyTests:49-136`.
- C22 [auto] The leading `> ` block is the quote (not gated on book metadata); the ramble is
  everything after the blank line; round-trip byte-exact; an emptied ramble leaves the quote.
  || check: `CaptureQuote` tests; corpus `quote-*`, `typed-blockquote-ordinary`.
  — ledgers:31, decisions:44
- C23 [auto] A conversation = ≥2 line-anchored `**Name:**` headers with ≥2 distinct names;
  `**Pros:**` mid-body is not one. || check: corpus `applenote-headings-checklist` renders
  as prose, `conv-*` as turns. — ledgers:34
- C24 [auto] Headings `^#{1,6} ` and inline `#tags` are recognised from text; marks stay
  dim-visible; characters verbatim. || check: `BodyMarkdown` tests. — ledgers:38-39
- C25 [auto] Title ladder, ONE for both apps: user title → suggested title → first body
  line (markers stripped) → share title → "Note"/"Voice note"; derived titles clip at 80
  chars on a word boundary. || check: corpus `typed-title-*`, `voice-en-raw-title`.
  ⚠ needs-verdict D6 — code-core Title
- C26 [auto] Karaoke: raw body word N = timing N; polished body aligned via `AlignmentCore`;
  a body that doesn't match its audio degrades to a proportional sweep. || check:
  `Karaoke` tests. — ledgers, code-core Karaoke
- C27 [tuur] The picture layout on the iPhone 13 and the Mac reads the same as today
  (photos already render as blocks) — no mock needed for the body v2. — B:702

### Copy-edit (rewrite target 2)

- C28 [auto] ONE model everywhere: `mlx-community/gemma-4-e4b-it-8bit`, revision pinned in
  `PolishPrompts`; temperature 0; one verb per call: copy-edit / title (64 tok) / summary
  (256 tok). || check: `PolishPrompts.swift` constants; iPad and Mac produce byte-identical
  output for the same input. — ledgers:50-52, decisions:42
- C29 [auto] The model sees prose only: memo-links escrowed to plain titles, picture
  paragraphs stripped, quote block held back; the ramble alone is edited. || check:
  `PolishEscrow`/`EnhancementService` parity test; corpus `typed-memo-links`, `quote-*`.
  — ledgers:60-61
- C30 [auto] Reinsert pictures by paragraph index (count picture paragraphs before, place
  after the same-index paragraph of the output); the 6-word anchor machinery is deleted.
  || check: corpus `pic-wall`, `pic-three-spread`; no `extractAnchors`. — B:699
- C31 [auto] A lost memo-link or a changed quote byte = the WHOLE body ships unedited.
  || check: `IPadPolishTests:62-73`, `QuoteProtectionTests`. — ledgers:60-61
- C32 [auto] Token budget = min(8192, max(1024, chars/4 × 1.5)); output at ≥95% of the cap
  = truncated → unedited. || check: `PolishPrompts` tests. — ledgers:53
- C33 [auto] Shrink guard: input > 40 words and output < 55% of input words → unedited body
  + a logged line. || check: `lostTooMuch` tests. — ledgers:54
- C34 [auto] Paragraph count of the shipped body ≥ paragraph count of the input, unless the
  shrink guard fired; a wall (> 600 chars, < 2 breaks, > 4 sentences) is broken
  deterministically at 4 sentences / 600 chars. || check: corpus `voice-en-asr-wall`,
  `typed-wall-7k`; the paragraph ledger `in N → model N → shipped N`. — B:730, B:739
- C35 [auto] Fillers (um/uh/eh) and repeated words go; decisions, numbers, names and both
  languages stay; nothing translated. || check: corpus `voice-en-pricing-ramble`,
  `voice-mix-code-switch` read by Tuur (C8). ⚠ needs-verdict D8 on Dutch. — decisions:299
- C36 [auto] Summary only when ≥ 75 words (manual Redo forces it); title always; a capture
  gets title + summary + tags on its annotation, no copy-edit; a conversation gets no
  copy-edit (turns are the diarization). || check: `BatchRunnerTests`; corpus
  `voice-en-three-words`, `cap-*`, `conv-*`. — ledgers:62-63, 73
- C37 [auto] Every pass writes ONE `MemoEnhancement` with `processedAt`, even when the model
  had nothing to say; `isProcessed` = `processedAt != nil` or all three parts present.
  || check: corpus `voice-en-processed-no-content`, `cap-image-no-words`. — decisions:43
- C38 [auto] The Mac processes only `enhanceStatus != .done`; a phone edit to a polished
  note re-links and recompiles, never re-polishes; an edit during a run discards the run.
  || check: `BatchRunner` guards. — ledgers:64, 76
- C39 [auto] The prompt is ONE source (`PolishPrompts` + synced override blob); a stale local
  override is migrated or surfaced, never silently wins. || check: no second prompt string
  in `user_settings.json` after migration. ⚠ needs-verdict D9 — B:941
- C40 [auto] Pressing Process on an unrated note floors it to 0.1 (a judgment); the Mac
  never auto-re-polishes. || check: `PolishCenter` tests. — ledgers:72

### Reconcile sweep (rewrite target 3)

- C41 [auto] After any sweep: every rated, live memo has exactly one Mac row (id = memo id);
  no unrated or trashed memo has one; a second sweep changes nothing. || check:
  `CorpusSeedTests.testEveryRatedNoteGetsAMacRow…`, `MemoCloudReconcilerTests`. — B:969
- C42 [auto] Trust: the phone's transcript is adopted iff `userEdited || confidence ≥ 0.7`;
  otherwise the Mac re-transcribes from the audio. || check: corpus `voice-en-untrusted*`.
  — CLAUDE.md
- C43 [auto] Kinds are the caller's decision, never sniffed: audio memo (waits for its audio
  blob, never becomes text) · capture (`sharedContent` present) · typed note (no audio, no
  sharedContent). || check: `MemoCloudIngest.isTextOnly` tests; corpus `typed-*`, `cap-*`.
  — decisions:60
- C44 [auto] v2 maps `Memo` + assets → `PipelineFile` directly (no fake multipart); the
  resulting row is field-identical to v1's on the corpus. || check: golden diff of every
  row. — B:6138
- C45 [auto] Late assets (photos, word timings, diarization) heal on the next sweep; a heal
  never overwrites Mac-made data; unchanged rows are skipped without faulting blobs.
  || check: `MemoCloudReconcilerTests:205-296`; sweep reads metadata only. — B:2151, AUDIT
- C46 [auto] The Mac's polish goes back as `MemoEnhancement`, LWW by `enhancedAt`; a fresh
  row adopts an enhancement this Mac wrote; an existing row never echoes its own.
  || check: corpus `voice-en-with-mac-polish`. — decisions:59
- C47 [auto] Phone → Mac reflect is content-based per field (tags, rating, trash with its
  watermark, lock, reminder, title adopt, OCR, metadata bytes); Mac → phone writes tags /
  rating / title / destination / trash onto the Memo, echo-guarded; clearing a rating is an
  event, never inferred from nil. || check: `MemoCloudUpdateTests`, `MacCloudMetaSync`.
  — ledgers:101-103
- C48 [auto] Duplicates: same-id clones resolve to one keeper (alive > most content > latest
  edit); differing content is left alone. || check: corpus `voice-en-duplicate-*` are two
  memos, untouched. — ledgers:105
- C49 [auto] A Mac import floors to 0.1; a Mac recording stays unrated; the row's
  `isLocalRecording` is stamped at construction. || check: `MacMemoAuthor` tests. — ledgers:97
- C50 [auto] `names.json`: atomic write, actor-guarded, decode failure never yields an empty
  roster, merge never shrinks it (LWW per person, voiceprints union). || check: D1 test
  (torn file → previous roster). ⚠ required difference — BUGS D1
- C51 [auto] Re-transcribe clears nothing until the new transcript exists; a missing audio
  file is an error on the row. || check: D2 test. ⚠ required difference — BUGS D2
- C52 [auto] The sweep runs at launch, activation and CloudKit import (coalesced), through a
  fresh context; no heartbeat timers. || check: `MemoCloudReconciler+Wiring`. — ledgers:91-92

### Export compiler (rewrite target 4)

- C53 [auto] The picked folder IS the destination (resolving to the Skrift-owned folder if
  the pick is its parent); no forced subfolders; identity lives in the file stamp
  (`skriftID`, `skriftHash`, `lastTouched`), never in a remembered path. || check:
  `VaultLayout`/`VaultStamp` tests. — ledgers:119-121
- C54 [auto] Never write over anything not provably ours and untouched: foreign →
  `<stem> <id8>.md`; pre-stamp legacy → refused, no twin; edited in the vault → backed off
  for good; moved → `movedAway`, never respawned; deleted → writable again. || check:
  `VaultWriteTests`. — ledgers:122, 125
- C55 [auto] Unchanged content writes nothing; writes are atomic and file-coordinated;
  frontmatter key order is stable. || check: `VaultWriteTests:56-63`, `VaultStamp:199`.
- C56 [auto] The compiler is pure: same input → same string; frontmatter = title · date ·
  author · source · people · book/bookAuthor/chapter · url · location · weather · pressure ·
  dayPeriod · daylight · steps · tags · significance · summary · stamp trio; `people:` = the
  distinct linked canonicals of the body, reading order. || check: `CompilerTests`; corpus
  `voice-en-full-context`. ⚠ needs-verdict D12 on the "to add" keys — ledgers:134-137
- C57 [auto] Images: `[[img_NNN]]` → `![[<note stem>_NNN.ext]]` (vault) or `![](file)`
  (archive); names keyed by the unique note stem, never the title. || check: corpus
  `typed-same-title-a/b` produce distinct files. ⚠ required difference — BUGS §2
- C58 [auto] Attachments go through the same ownership rule as the note; no attachment lane
  removes a file it doesn't own. || check: D3 test. ⚠ required difference — BUGS D3
- C59 [auto] Memo-links export as `[[<stem>|Title]]` when resolvable, else `[[Title]]`; the
  raw syntax never reaches the vault. || check: corpus `typed-memo-links`. — ledgers:138
- C60 [auto] Audiobook quote: italic quote block + `— [[Author]], *Book*, ch. N` written at
  export only; a named chapter as-is; no attribution without book metadata. || check:
  corpus `quote-*`. — ledgers:139
- C61 [auto] Export needs a PROCESSED, rated, unlocked, live note; the phone does not export;
  nothing on iOS auto-publishes. || check: `PublishCoordinatorTests`; corpus
  `typed-locked`, `applenote-dutch` never appear in the vault. — ledgers:128-131
- C62 [auto] Four destinations, one per note: Personal → vault; Made → `_inbox/`; Idea →
  `_ideas/`; Inspiration → `_inspiration/` with `needs: - credit`; the archive keeps
  `[[names]]`, drops places, weather, significance, `author`, `type`, `source`; flat, named,
  media beside the note. || check: `ArchiveExportTests`; corpus `dest-*`. — ledgers:144-155
- C63 [auto] Video is never exported; a video note exports markdown + audio + the frame.
  || check: corpus `video-*`. — ledgers:153
- C64 [auto] `date:` is computed the same way on every device (ONE timezone rule).
  || check: phone and Mac export of one corpus note at 23:30 agree. ⚠ needs-verdict D13
  — code-core needs-verdict 5
- C65 [auto] Export stops transforming the body (no snap) once C10 holds. || check: exporter
  has no `snappedImageBody` call. — B:700

### Ingress (share / import) — every door, from the code (ingress.md: 30 paths)

- C66 [auto] Every share jumps to its note on the next app-open; every share offers the
  rating; audio shares carry no annotation field. || check: `CaptureInboxDrainer` tests.
  — ledgers:167-168
- C67 [auto] Attachments from ALL extension items enter the dispatcher (WhatsApp ships a
  multi-select as several items; today only the first is read). || check: a 3-item share
  yields 3 clips. ⚠ required difference — ingress P1, B:5215
- C68 [auto] N voice notes → chooser "One note" (default: clips merged in chat order, one
  transcription pass) or "N notes"; N photos → always one note; a mixed bundle (clips +
  photos + text) → one note with the pictures per C12 and the chat text as the body's
  annotation. || check: `share-ingest-wave1` tests; ingress fixtures P1/P3. — ledgers:169-172
- C69 [auto] Audio outranks the URL representation (a WhatsApp voice note is audio); odd
  UTIs (Signal `.aac`, Telegram `.ogg`) reroute by extension; a text share that is a URL
  becomes a link capture. || check: ingress P1/P2/P7 fixtures. ⚠ needs-verdict D16 on the
  text-URL case — ingress P7
- C70 [auto] `recordedAt` = the content's true date: embedded date → date in the filename
  (WhatsApp / Signal / Telegram / recorder patterns, Mac parity) → file date → now;
  `createdAt` = when it entered Skrift; default sort "Recently added". || check: ingress
  P1/P12 fixtures dated from the filename. ⚠ required difference (phone never parses the
  filename today) — ingress P1, ledgers:205-206
- C71 [auto] Video: audio stripped to m4a, one frame as the first picture (C12), original
  discarded on the phone (kept as `source.<ext>` on the Mac, never synced), `recordedAt` =
  filming date, `sourceType = "video"` read by the list glyph. || check: corpus `video-*`;
  ingress P8. ⚠ required difference (glyph key drift `sourceType` vs `mediaSource`) — ingress P8
- C72 [auto] URL capture: title/description/thumbnail fetched ONCE on drain (one GET, no JS,
  local thumbnail, article text search-only); no title → the host as title, never the raw
  URL. || check: ingress P5 fixtures replayed from the recording; corpus `cap-url-no-title`.
  ⚠ needs-verdict D14/D15 on YouTube / Instagram — ledgers:186-187
- C73 [auto] PDF link → downloaded file capture (magic-byte check) with extracted text;
  `.txt/.md` share → the note body; PDF/doc share → file capture, the document syncs as an
  asset, its text is searchable. || check: ingress P5.1/P10/P11; corpus `cap-file-*`.
  — ledgers:188-189
- C74 [auto] Image share: downsampled ≤ 2048 px, EXIF date → `recordedAt` (earliest of a
  multi-share), OCR on the next sweep; PNG stays PNG, GIF keeps its first frame honestly.
  || check: ingress P9. ⚠ needs-verdict D17 — ledgers:176, 215
- C75 [auto] A share with an empty payload never saves a husk; failures are honest
  ("Skrift can't import this"). || check: `ShareSheetView` tests. — ledgers:183
- C76 [auto] Apple Notes export (`.md` + `Attachments/`): title from the first heading,
  attachments copied and relinked, `sourceType .note` (glyph "Apple Note"). || check:
  ingress M4 fixture. ⚠ needs-verdict D18 on the date — ingress M4
- C77 [auto] The Mac refuses honestly what it cannot import (PDF, image, URL, ePub, `.flac`
  today are silently dropped). || check: ingress M1-M3 with an unsupported file shows a
  message. ⚠ required difference; needs-verdict D19 on growing the types — ingress M
- C78 [auto] A capture is a memo without audio plus `sharedContent` (C3 contract, camelCase
  field names pinned; unknown type → nil); `SourceTaxonomy` is the one glyph+label map.
  || check: `SharedContentParityTests` both apps. — ledgers:198, 210
- C79 [auto] Audio ≥ 1 h offers Books; `.skriftbook` imports a book keyed on `bookID`;
  podcasts are a separate lane (not v2). || check: ingress P4/P18. — ledgers:185, 196

### Names & sanitise (referenced by targets 2 and 4; not rewritten)

- C80 [auto] Known-roster only, deterministic, no LLM/NER: a full or distinctive first name
  auto-links at first mention (`[[Canonical|spoken]]`), later mentions stay plain; a
  stoplisted or shared first name is a dotted suggestion; ≤ 2-char names suggest; strict
  whole-word + capitalisation. || check: corpus `voice-en-names-all-tiers`,
  `edge-quote-in-name-roster-word`. — ledgers:219-225
- C81 [auto] The phone keeps the transcript RAW and re-derives tiers on demand against
  `nameResolutionsData`; the Mac links with the same shared `Sanitiser` and the synced
  roster; the export from either device carries the same links. || check: corpus export
  diff phone vs Mac. ⚠ needs-verdict D20 (today the Mac ignores the phone's picks)
  — code-core needs-verdict 2
- C82 [auto] Names inside a quote block, code, YAML or a memo-link title are never linked.
  || check: corpus `quote-with-names`. ⚠ needs-verdict D21 on mid-body quotes — ledgers:6
- C83 [auto] A person added on the phone gets `aliases = [name]`; alias-less people are
  backfilled once. || check: corpus roster; BUGS §2 test. ⚠ required difference — BUGS §2
- C84 [auto] Conversation headers: first turn `**[[Canonical]]:**`, later turns plain short;
  consecutive same-speaker turns merge; speaker hue = first-appearance order of the
  resolved identity. || check: corpus `conv-*`. — ledgers:15-16 (names)
- C85 [auto] `names.json` is byte-compatible across apps (one encoder, sorted keys); sync =
  per-person LWW with voiceprint union. || check: `NamesTests`. — CLAUDE.md
- C86 [auto] Audiobook authors never enter the roster. || check: corpus `quote-*` add no person.

### Consent, rating, lifecycle (not rewritten; every target reads it)

- C87 [auto] The rating is consent: 0 = unrated → no processing, no export, no Connections,
  fades; playable, searchable, editable like any note. ONE predicate (`NoteConsent.isRated`)
  for both apps. || check: `NoteConsentTests`; corpus `voice-en-unrated-*`. — decisions:143
- C88 [auto] Rating is a one-way door on a synced pipelined note (un-rating keeps the row);
  Mac-local takes are two-way. Decided as-is. || check: `WayOutRules` tests. — decisions:146
- C89 [auto] ONE clock: `clockStart = max(recordedAt, keptAt)`; touch restarts 30 days;
  fading at 30, Recently Deleted at 60, gone 14 seen-days later; rated / locked / reminder /
  backlinked notes never fade; final doors move only at an app-open. || check:
  `MemoLifecycle` tests; corpus `voice-en-unrated-old`, `voice-en-unrated-kept`,
  `edge-old-rated-never-exported`. — decisions:138, 142
- C90 [auto] Trash is soft everywhere, synced via `deletedAt`, purge clock = `trashSeenAt`;
  trash is not searchable, fading is. || check: `TrashTests`; corpus `typed-trashed`.
- C91 [auto] Locked notes sync, never export, show title + 🔒 only, unlock per session.
  || check: corpus `typed-locked`. ⚠ needs-verdict D22 (does a locked note get polished?)
- C92 [auto] Reminders are synced data; each device derives its own alarm. || check: corpus
  `typed-reminder`. ⚠ unverified: Mac reconciler owed — ledgers:53 (lifecycle)
- C93 [auto] Tags: split on comma/newline, need a letter or digit (`[]` refused), `#`
  stripped once, case kept; destination words are accepted as tags and `inspiration` raises
  `needs: - credit`. || check: corpus `typed-bracket-tag-bug`, `typed-tags-with-spaces`,
  `typed-reserved-word-tags`. ⚠ needs-verdict D23 on case-variant duplicates — Memo.swift
- C94 [tuur] Importance control: 10 circles today; i23 proposes 3 (or 4) buttons — mock
  first. ⚠ needs-verdict D24 — mocks-roadmap i23

### Sync contract (stays as is)

- C95 [auto] The phone carries the RAW transcript + confidence / userEdited / markers /
  metadata / optional title; never `sanitised`. The Mac writes polish as `MemoEnhancement`,
  never into `Memo.transcript`. || check: `MemoCloudIngest`, `MacCloudWriteBack` tests.
  — CLAUDE.md
- C96 [auto] Every synced field is additive with a default; `MemoAsset.blob` is plain Data;
  local-only derived fields are stripped from every sent blob; unknown keys are ignored by
  old decoders; `hPa` stays Int on the wire. || check: `MemoMetadata` decode tests. — ledgers
- C97 [auto] A receiver never re-transcribes another device's in-flight memo. || check:
  corpus `voice-en-other-device-transcribing`. — ledgers:67 (sync)
- C98 [tuur] Offline conflict = per-record last-writer-wins; a same-note edit on two devices
  can lose one side. Accept or design a merge. ⚠ needs-verdict D25 — decisions:463

### Recording & audio (out of the rewrite; listed so nothing is lost)

- C99 [auto] A recording is never lost when the app dies: audio is persisted in segments
  during the take and a launch sweep rebuilds the note and says so. || check: kill the
  process mid-take on the sim → note present after relaunch. ⚠ required difference (D4,
  issue #14); needs-verdict D26 on the exact mechanism — BUGS D4
- C100 [auto] Instant record on every entry; with Bluetooth present the whole memo records on
  the built-in mic; every recording lands unrated; transcription is capture, not processing.
  || check: `RecordingCore` tests; device round owed. — ledgers:85-87, 94
- C101 [auto] Live caption seeds the note; the stop-pass file transcription is the truth;
  the ASR tail order is one shared `ASRPostProcess.finish` (phantom guard → BPE merge →
  vocab rescore → timings → markers). || check: `ASRPostProcessTests`. — ledgers:90, 98
- C102 [auto] Diarization is opt-in per note; a diarized note is `transcriptUserEdited`;
  voice identity = embedding cosine at 0.5. || check: `SpeakerFusion` tests. — ledgers:103, 114
- C103 [auto] Custom vocabulary syncs whole-list LWW; the booster pre-warms at launch; a
  boost is dropped when every replacement is a distant guess. || check: `VocabTests`.

### Audiobooks (out of the rewrite)

- C104 [auto] Skrift is the player; one memo per quote capture (quote block + ramble + book
  metadata; quote audio = the memo audio; `bookID` + `bookPosition`). || check: corpus
  `quote-*`; `BookCaptureTests`. — ledgers:118-119
- C105 [auto] Chapter precedence ePub TOC > transcript-detected > embedded; "better no
  information than bad": incomplete chapter data degrades to book-level jump points.
  || check: `ChapterDetector` tests. — decisions:205-206
- C106 [auto] Whole-book transcription: 180 s chunks via sample-accurate frame reads (never
  `AVAssetExportSession`), resumable, pauses only below 20% on battery. || check:
  `-chunksim` harness. — ledgers:124-125
- C107 [auto] Book sharing = one `.skriftbook` with audio + ePub + sidecars, never position /
  bookmarks / notes; import keyed on `bookID`. || check: `BookBundle` tests. ⚠ unverified:
  two-device round owed; branch status D27 — decisions:212
- C108 [tuur] Player, reading mode, bookmarks and the Text sheet match their signed mocks on
  the iPhone 13; remainder = reading themes (light/sepia/dark). ⚠ unverified — mocks #5

### Search & Connections (out of the rewrite)

- C109 [auto] Embedder = EmbeddingGemma-300M via CoreML-LLM, per-device index, never synced;
  only rated live notes join; floors: related 0.45, search 0.25; no similarity numbers on
  the phone. || check: `EmbeddingIndex` tests; `joinsConnectionsIndex`. — mocks-roadmap Search
- C110 [auto] A query either returns hits above the floor or the UI says the engine isn't
  ready (never a silent empty). || check: cold-load test. ⚠ required difference (BUGS §3
  semantic search) — BUGS §3
- C111 [auto] Search covers title, transcript, summary, photo OCR, PDF and article text;
  Mac search jumps to the hit like the phone. || check: corpus `pic-ocr-text` found by
  "GREY BODY". ⚠ required difference (Mac jump) — BUGS §4

### Editor, note UI, quick capture

- C112 [tuur] Quick note: a New Note action in the app, on the Lock Screen / Control Center
  widget and via Siri opens an empty note with the keyboard up, in under a second. Mock
  first. NEW 2026-09-21 — this spec
- C113 [tuur] The editor feels like Apple Notes: no lag while typing, paragraphs stay where
  he put them, a picture is a block he can move. Rebuilt on the body v2 (C10), never
  before it. Mock first. NEW 2026-09-21
- C114 [tuur] What the app opens into (last note / the list / a new note) — his call.
  ⚠ needs-verdict D28
- C115 [auto] ONE shared `NoteCardView` on both lists; ONE `BodyTransform`; ONE
  `Paragrapher`; ONE `NoteConsent`; anything living on both apps is single-sourced in
  `Shared/` in the same change. || check: no twin of a Shared type under either app.
  — decisions:277
- C116 [auto] Markdown marks stay dim-visible; bodies stay plain Markdown prose + tasks (no
  tables, no rich-text styles). || check: mocks accessory-bar-v2. — ledgers:39
- C117 [tuur] Mock-first for every new screen; a signed mock IS the spec; current-app
  elements in a mock are drawn from source. — decisions:267, 278
- C118 [tuur] Built on main, his eyeball owed (⚠ unverified): the m2 note card on Mac +
  iPad (b155), the one-clock walkthrough on both apps, the shared export engine's first
  real-vault run, export destinations on phone + iPad, the Mac mid-take edit, the Mac
  live Record press, the read-along lead tune. — mocks-roadmap §C
- C119 [tuur] Approved mocks, nothing built — done-states with the mock as the clause:
  Mac PDF-inline first page (journal-desktop §3); Mac thumbnails + place/tags chips
  (mac-notes-list-rich); reading themes (audiobook-player-reading-mode); picture
  drag-reposition (no mock yet; after C10); vault-folder-model A/B (needs a pick, D11);
  standalone onboarding; commonplace book; the Obsidian plugin menu. — mocks-roadmap §B

### Privacy

- C120 [auto] No cloud AI, ever; the only network calls are weather at capture and the one
  URL fetch on drain, both stated in-app. || check: no other host in the network log of a
  corpus run. ⚠ needs-verdict D29 on stating them — decisions:539
- C121 [auto] Personal notes never land in a folder an AI reads; the destination is a stored
  field, one of four. || check: corpus `dest-personal` never under the archive root.
- C122 [auto] The corpus is synthetic; agents never read his vault; Dev and prod are separate
  containers and the Dev vault is the test vault. || check: `AppPaths` dev suffix;
  `-corpus` refuses a path under his real vault.

---

## Required differences (pre-registered bugs — v2 matching v1 here FAILS)

Full list with sources: `plan/extraction/bugs-preregistered.md`. The ones inside the four
rewrite targets, each with its corpus note and the expected output:

| # | v1 does | v2 must | corpus note | clause |
|---|---|---|---|---|
| R1 | shared picture lands after the first word | picture at the top, sentence whole | `cap-image-voice-ramble`, `pic-shared-no-timestamp` | C12 |
| R2 | timed picture splits its sentence in the stored body | own paragraph after that sentence | `pic-mid-sentence`, `pic-nl`, `pic-three-spread` | C10, C11 |
| R3 | wall + pictures re-paragraphed by the model | paragraphs as without pictures; pictures in place | `pic-wall` | C30, C34 |
| R4 | mixed WhatsApp share drops all but the first item | every clip, in chat order | ingress P1/P3 fixtures | C67 |
| R5 | shared voice note dated to share time | dated from the filename | ingress P1/P2/P12 | C70 |
| R6 | same-titled notes overwrite each other's images | images keyed by note stem | `typed-same-title-a/b` | C57 |
| R7 | attachment lane deletes a vault file it doesn't own | ownership rule on every write | D3 test | C58 |
| R8 | `names.json` non-atomic; torn read → empty roster | atomic, never empty, never shrinks | D1 test | C50 |
| R9 | re-transcribe clears the transcript before ASR runs | cleared only after success | D2 test | C51 |
| R10 | JS-rendered page → raw URL as title | host as title | `cap-url-no-title` | C72 |
| R11 | phone video glyph reads the wrong key | video glyph | `video-*` | C71 |
| R12 | phone-added person has no aliases, never links | alias seeded | roster | C83 |
| R13 | Mac silently drops PDF/image/URL/ePub/flac | honest refusal | ingress M | C77 |
| R14 | `ensureParagraphs` passes a 7k output with 2 stray breaks | judged per block | `voice-en-asr-wall` | C34 |
| R15 | `date:` differs phone vs Mac near midnight | one rule | export diff | C64 |

Outside the targets, fixed in v1 now, not waited on: D4 lost recording (C99), semantic
search silent empty (C110), Mac search jump (C111), audiobook edit-sync / seek-persist /
cover colour (BUGS §2).

Pre-registered as IDENTICAL (already fixed; a v2 change here is a regression): the twelve
items under "Already fixed" in `plan/extraction/bugs-preregistered.md`.

---

## Open decisions — the sitting (numbered; each with my proposed default)

Blocking the first rewrite target (body/image + copy-edit):

1. **D1 Picture = its own paragraph, enforced at write** (C10). Default: yes. The backlog
   calls it a proposal; nothing in your words confirms it.
2. **D2 A picture with no moment goes to the TOP** (C12). Default: top. Alternative: bottom.
   The backlog says "his verdict", the handoff says "my recommendation".
3. **D3 Where a picture goes inside a list item or a quote block** (`pic-in-task-list`,
   `pic-in-blockquote`, `conv-with-picture`). Default: after the item / after the quote
   block / after the turn's sentence.
4. **D4 Old notes**: normalise once on read (the existing snap, run once, then stored) and
   re-derive name offsets once. Default: yes, at first open on any device.
5. **D5 ONE paragraph gap** for speech on every device (0.65 s phone vs 2.0 s Mac today).
   Default: 2.0 s everywhere (a paragraph needs a deliberate stop). Or keep per-source.
6. **D6 ONE title ladder** for both apps (C25). Default: user title → suggested → first
   line. Today the Mac has no chosen-vs-suggested split on its row.
7. **D7 A typed note pasted as one wall** (`typed-wall-one-paragraph`): may the
   paragrapher break the author's own text? Default: no (typed text is his; only speech
   gets paragraphed).
8. **D8 Dutch copy-edit** near-echoes (removes nothing). Accept, or bench prompts? Default:
   accept for v2; paragraphs guaranteed by C34; revisit on the Mac bench later.
9. **D9 The prod prompt override** (764-char old prompt in `user_settings.json`). Default:
   migrate it away, one prompt source.
10. **D10 Locked notes and polish** (C91): today lock = "keep, don't polish"? Default: a
    locked note is never processed and never exported; sync continues.

Blocking targets 3 and 4 (reconcile + export):

11. **D11 Vault folder model** (mock `vault-folder-model`): A = the picked folder is the
    destination (doctrine) vs B = Skrift makes its own folder. Default: A. Also subfolder
    names and whether PDFs export.
12. **D12 Frontmatter keys still "to add"**: lat/lon, duration, createdAt/editedAt,
    remindAt. Default: add duration + createdAt; skip lat/lon and remindAt.
13. **D13 `date:` timezone rule**. Default: the recording's local day.
14. **D14 YouTube link**: link card with the fetched title (today), or fetch audio +
    transcribe on the Mac? Default: card only.
15. **D15 Instagram / TikTok**: caption as the body, or card only? Default: card + caption
    when the page gives one; never a login-walled fetch.
16. **D16 A URL shared as plain text** (chat apps): treat as a link capture? Default: yes.
17. **D17 Image shares**: PNG stays PNG, GIF first frame. Default: yes.
18. **D18 Apple Notes import date**: export time (only thing available) or a `Created:`
    line when present. Default: export time, `createdAt` = import time.
19. **D19 Mac drops of PDF / image / URL / ePub / flac**: refuse honestly, or grow the Mac's
    capture types to match the phone? Default: refuse honestly in v2; grow later.
20. **D20 Name links per device**: the Mac ignores the phone's per-note picks, so one note
    can export with different links from each device. Default: the phone's picks win
    everywhere (they sync already).
21. **D21 Mid-body blockquotes**: never link names inside any `> ` block? Default: yes.
22. **D22 A text-file share with no comment** (`cap-file-txt`): body = the file's text, or an
    attachment card? Default: body.
23. **D23 Case-variant duplicate tags** (`Glaze`/`glaze`). Default: fold to the first spelling.
24. **D24 Offline conflict**: per-record LWW stays (one side's edit can be lost). Default:
    stays, stated in the spec; no merge engine.
25. **D25 Shares default to rating 0** and never reach the Mac. Default: stays (the rating
    is consent); the goldens assume a rating.

Not blocking v2, but he asked for one sitting:

26. **D26 Recording durability** (D4, issue #14): roll segments on interruption + every 60 s,
    a sidecar marker + launch sweep that says "recovered a recording", and a
    `willTerminate` finalise. Default: all three; fixed in v1 now.
27. **D27 Book-sharing branch** (`claude/book-sharing-devices-rygara`, built, no device
    run, not on main): merge now or leave until the two-device round? Default: merge to
    main now; the round stays owed.
28. **D28 What the app opens into**: the list (today), the last note, or a new note.
    Default: the list, with the new-note action one tap away (C112).
29. **D29 State the two network calls** (weather, URL fetch) in-app / README. Default: yes.
30. **D30 Importance control**: 10 circles vs 3 (or 4) buttons (i23). Default: mock the
    3-button version; decide on the mock.
31. **D31 Multi-audio thread from WhatsApp**: chooser stays (one note default). Default: yes.
32. **D32 Adding a person**: re-link only the open note (today) or every note? Default:
    every note, once, deterministic.
33. **D33 Podcasts → Books** node is `inprogress` with nothing shipped. Default: demote to
    planned.
34. **D34 Rival documents**: after the spec, project state lives in SPEC.md + QUEUE.md +
    roadmap.yaml. `backlog.md` (8.7k lines), `FEATURES.md`, `BUGS.md`, `AUDIT_PLAN.md`,
    `SKRIFT_SOURCE_OF_TRUTH.md`, `STANDALONE_PLAN.md`, `SHARE_INGEST_SURVEY.md`,
    `NAMING_MODEL.md`, `TESTFLIGHT_INSTALL_HANDOFF.md` become history under `archive/`.
    Default: archive all but `FEATURES.md` and `BUGS.md` (kept as ledgers until v2 lands),
    and repoint `CLAUDE.md`.

Parked ideas that are NOT decisions today (listed so the sitting can skip them): ramble
modes, monthly digest, vault-read direction, tightness lens, Obsidian plugin bundle,
commonplace book, folders model, watched-folder ingest, substitutions list, Backlink
Weaver, dictate-anywhere, Apple Watch, voice search, re-ingest of the Electron-era notes.

---

## Not doing

- No rewrite of views, the CloudKit schema or the audio/hardware paths in v2; no real
  notes in the corpus; v1 is never the judge.
- No Python, Electron, React Native, Bonjour; CloudKit is the only transport; no
  iCloud-Drive file sync.
- No cloud AI; no AI or agent reads his vault; no analytics; no subscription, no IAP.
- No third app; the iPad is the iPhone target; the Mac stays a separate UI over shared code.
- No LLM in naming, tagging or importance; no NER; no auto "new person?"; no
  per-occurrence name resolver; no destination suggestion engine; never two destinations.
- No similarity slider; no stale Connections sidecar; no semantic linking while typing.
- No vision pipeline; no chat/ask; no export preview; no LLM narration of "how my
  thinking evolved" yet.
- No audio mark-in/out capture; no audio trim; no Review screen after recording; no
  Re-transcribe on the phone; no phone-side export; nothing auto-publishes on iOS.
- No video export; no bubble chrome on shared input; no 4-bit iPad model; no `Skrift/`
  prefix forced in the vault; no Flag verb.

## Decisions (dated, his words where recorded — the full list is `plan/extraction/decisions.md` §A)

- 2026-09-18 Rewrite the core as v2, one subsystem at a time, spec-first, judged by output
  diffs — "months of AI patches accreted weird bugs"; "will you copy over the bugs?" → v1
  is the change detector, never the judge.
- 2026-09-18 The corpus is synthetic — "the app is filled with my thoughts already… make a
  testing vault".
- 2026-09-18 Whole project in one sitting — "I don't like the start stop start stop".
- 2026-09-21 Quick note + Apple-Notes-grade editing go into this spec: "when I quickly
  wanna write something down I reach for Apple Notes… either record or just start a new
  note. simple smooth and fast." Entry path builds early; the editor rebuilds on body v2.
- 2026-09-21 Dev only during the rewrite; v2 beside v1; nothing lost (branch, tag before
  each swap, v1 deleted in its own commit).
- 2026-08-27 The archive keeps `[[names]]` — "credit where credit is due"; don't fix back.
- 2026-08-26 The destination is a privacy boundary, not a filing shelf; one of four; a
  stored field, never a tag; no suggestion engine — "I know what I'm recording".
- 2026-08-26 A pass that ran with nothing to say is still processed (`processedAt`).
- 2026-08-20 A waiting thing is never turned into a different thing (audio not synced ≠
  text note); a fresh row adopts this Mac's own enhancement.
- 2026-08-19 The shrink guard keeps the unedited body — "a raw note is honest, a bitten
  one is silent data loss".
- 2026-08-12 One model on every device, revision pinned — identical polish everywhere.
- 2026-08-11 The phone does not export; the picked folder is the consent; nothing on iOS
  auto-publishes.
- 2026-07-28 Transcription is capture, processing is gated by the rating; the Mac copies
  the phone when unsure.
- 2026-07-26 The rating is CONSENT — "until judged, Skrift spends nothing on a note and
  shows it nowhere but back to you"; an unrated note IS a normal note; rating is a one-way
  door on synced notes (decided as-is).
- 2026-07-26 One vault-write engine: the picked folder is the destination; the file stamp
  is identity; never write over what isn't provably ours; moved notes are never respawned.
- 2026-07-23 No note dies unseen: the final doors move only at an app-open.
- 2026-07-22 ONE clock: touch restarts 30 days; "Fading" is the word; rating IS the flag.
- 2026-07-21 Both devices are collectors; Mac-only files dissolve into synced memos.
- 2026-07-16 Shared code first; mock "as-is" elements drawn from source; markdown marks
  dim-visible, never vanishing.
- 2026-07-12 Shared inputs never get bubble chrome — "again — I keep telling you".
- 2026-07-10 Share-sheet dictation retired (iOS blocks it); every share jumps to its note.
- 2026-07-07 Photos are blocks in the editor; tasks, memo-links, accessory bar locked.
- 2026-06-16 Naming: opt-out, risk-tiered, known-roster only, no LLM — "never misses
  KNOWN people".
- 2026-06-15 Standalone: $0.69, no IAP, CloudKit sync, one-way publish, on-device polish
  as a gated spike; no invented polish modes.
- 2026-06-13 Text-first quote capture is the only capture flow; whole-book pre-transcribe.
- 2026-06-11 Audiobook authors never enter the names DB; `[[Author]]` at export only.
- 2026-06-04 Skrift feeds Obsidian, it does not replace it; north star "see how my
  thinking evolved".

## Gate — measured

- 2026-09-21 `./gate.sh` → GREEN: desktop unit suite 769 tests, 0 failures, 3.2 s of test
  time (build excluded). Phone corpus test green on the iPhone 17 sim; full Mac MLX build
  green (after the mlx-swift-lm pin bump for Xcode 27.0).
