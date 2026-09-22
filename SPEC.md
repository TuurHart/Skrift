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
(or types one, or shares a link, picture, PDF, video, or an audiobook quote); it is
transcribed on the device with nothing sent anywhere. At the note he sorts it into one of
two pipelines. **Personal** thoughts go, once rated and cleaned up by his Mac or iPad with a
local model, as one Markdown file into his private Obsidian vault, which no AI ever reads.
**Ideas, things he made and things that inspired him** go to his public archive repo, the
space he deliberately lets AI read so he can explore them further with it. The sort is a
privacy boundary, decided by him in one tap, never guessed. Obsidian is home; Skrift is the
front door. One user, fully offline, sold flat, no cloud AI. The long game is decades of
notes he can look back through.

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
The v2 diff harness joins the gate when the first subsystem lands (C5–C7).

---

## Clauses

### The v2 method (Tuur 2026-09-18)

- C1 [auto] v2 is built one subsystem at a time, in this order: body/image model → copy-edit
  → reconcile sweep → export compiler. Views, the CloudKit schema and the audio/hardware
  paths are not rewritten — except the editor rebuild of C113, which follows target 1.
  || check: no v2 file under `Shared/Model/*@Model` or `Services/Recording/`. — decisions:14-15
- C2 [auto] v2 lives beside v1 in `Shared/`; the app calls v1 until the subsystem's gate is
  green and Tuur has read its corpus output; v1 is deleted in its own commit after a git tag
  `v1-<subsystem>`. || check: tag exists before the deletion commit. — decisions:16
- C3 [auto] Size budget: v2 ≤ 40% of v1's lines for that subsystem, else the commit message
  says why. Baselines (code-core §C): body/image 7,940 · copy-edit 2,674 · reconcile 5,297 ·
  export 2,734. || check: `wc -l` of the v2 files vs the inventory table. — code-core §C
- C4 [auto] The corpus is synthetic, never his notes: `test-fixtures/corpus/` (109 notes,
  fictional roster), seeded on both apps with `-corpus <path>`. || check:
  `CorpusSeedTests` on both apps. — decisions:260
- C5 [auto] v1 is the change detector, never the judge: every corpus output is classed
  identical / expected-different / unexplained; a pre-registered bug where v2 matches v1
  FAILS. || check: the harness exits non-zero on any unexplained or matched-bug row.
  — decisions:17
- C6 [auto] Invariants the harness checks without v1: markers in = markers out; paragraph
  count never drops unless the shrink guard fired; editor round-trip returns the identical
  string; every transform is idempotent; no rated live memo without a Mac row; `names.json`
  re-encodes to the same bytes on both apps; the pieces of a body cover it exactly; an
  identity generator round-trips the escrow byte-exact; a quote-only capture never calls the
  generator; Mac words reach only an empty, Mac-recorded memo from a `.done` row; a retitle
  keeps the export path and a fresh ledger re-adopts by stamp; the lifecycle spine assigns one
  station with its three strings byte-pinned; and, replacing the three snap invariants that
  die with C17: no `[[img_` inside a sentence in any stored body. || check: harness invariant
  suite (code-core §B, 54 items, 9 of them stronger in the tests than in these clauses).
  — code-core §B, spec-coverage §E
- C7 [auto] (drafter's harness design) Recorded model outputs are keyed by the exact prompt text and input; a miss runs
  the model live, never fails silently. || check: harness cache key = sha256(prompt+input).
- C8 [tuur] He reads the corpus output for each subsystem before the swap.
- C9 [auto] (drafter's proposal) Per-subsystem end-to-end scenarios (rate→row style) run on the seeded Dev
  store, not on unit fixtures. || check: one `-corpus`-driven scenario per swap.

### Body/image model (rewrite target 1)

- C10 [auto] A picture is its own paragraph, always: the stored body has `\n\n[[img_NNN]]\n\n`
  between paragraphs, never inside a sentence. Enforced where a body is WRITTEN (capture,
  share, edit, import); old notes normalised once on read. || check: corpus notes
  `pic-*` — no marker inside a sentence in any stored/exported body. ⚠ needs-verdict D1
  (supersedes the 2026-07-16 rule "stored raw keeps the marker at its moment, renderers snap")
  — B:694-702
- C11 [auto] A timed picture lands after the sentence being spoken at `offsetSeconds`
  (sentence end, not nearest word). || check: `pic-mid-sentence` → marker after "…the
  glaze." — B:679, decisions:450
- C12 [auto] A picture with no moment of its own keeps its PLACE IN THE SEQUENCE it arrived
  in: in a multi-item share it lands between the clips or texts it sat between (share order);
  a picture inserted in the editor lands at the caret; a lone shared picture, a video frame,
  or a picture with nothing around it goes to the TOP of the note. || check: ingress P3
  fixture (5 clips + 1 picture between clip 3 and 4 → picture paragraph between transcript
  3 and 4); `cap-image-voice-ramble`, `video-*` → body starts with the marker. ⚠ needs-verdict
  D2 — B:695, Tuur 2026-09-21 (the WhatsApp probe)
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
- C19 [auto] (drafter's proposal; v1 tidies only inside copy-edit) Whitespace normalisation
  is ONE rule applied at write: horizontal runs inside a
  line → one space; ≥3 line breaks → one blank line; CRLF → LF; ends trimmed. || check:
  corpus `typed-crlf-tabs-nbsp`, `voice-en-triple-blank-lines`. — B:727
- C20 [auto] Paragraphing from speech: break before a word when the previous word ends a
  sentence AND (pause ≥ gap OR 4 sentences reached); text that already has a newline is
  untouched; the gap is 2.0 s on every device (Tuur 2026-09-22, reversing the phone's 0.65 s);
  typed text is never paragraphed by any rule (no word times; the copy-edit fallback skips
  typed notes). || check: `Paragrapher` tests; corpus `typed-wall-one-paragraph` unchanged.
  — code-core Paragraphs, D5, D7
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
  chars on a word boundary for DISPLAY only (the vault filename keeps its own rule, C165); a
  share capture with an empty annotation titles from urlTitle → first 8 words → image
  filename → "Capture". || check: corpus `typed-title-*`, `voice-en-raw-title`.
  ⚠ needs-verdict D6 — code-core Title
- C26 [auto] Karaoke: raw body word N = timing N; polished body aligned via `AlignmentCore`;
  a body that doesn't match its audio degrades to a proportional sweep. || check:
  `Karaoke` tests. — ledgers, code-core Karaoke
- C27 [tuur] (drafter's assumption) The picture layout on the iPhone 13 and the Mac reads the same as today
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
- C36 [auto] Summary only when ≥ 75 words (manual Redo forces it); title always; a SHARE
  capture (url/text/image/file) gets title + summary + tags on its annotation, no copy-edit (a
  QUOTE capture's ramble IS copy-edited, C29); a conversation gets no
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
- C42 [auto] Trust: a `.done` phone transcript is adopted iff `userEdited || confidence ≥ 0.7`;
  otherwise the Mac re-transcribes from the audio (an in-flight `.transcribing` memo is never
  touched, C97); sidecars (timings, diarization) are honoured only with a trusted transcript. || check: corpus `voice-en-untrusted*`.
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
  author · source · book/bookAuthor/chapter · url · [archive: voice, needs] · summary · tags ·
  people · significance · location · weather · pressure · pressureTrend · dayPeriod · daylight ·
  steps · stamp trio — the code's grouped order (`Compiler.swift:60-175`), title always quoted;
  `people:` = the distinct linked canonicals of the body, reading order. || check: `CompilerTests`; corpus
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
- C61 [auto] Export needs a PROCESSED, rated, unlocked, live note; the iPHONE does not export,
  the iPad and the Mac do (through the one shared engine, photos + audio included); nothing on
  iOS auto-publishes; bookmarks never export. || check: `PublishCoordinatorTests`; corpus
  `typed-locked` and `applenote-dutch` (both locked) never appear in the vault. — ledgers:128-131,
  L C13, L:367
- C62 [auto] Four destinations, one per note: Personal → vault; Made → `_inbox/`; Idea →
  `_ideas/`; Inspiration → `_inspiration/` with `needs: - credit`; Made lands in `_inbox/Skrift/`
  (Tuur 2026-09-22; v1 writes flat `_inbox/` — required difference); the archive keeps
  `[[names]]` and `location:`, plainifies place LINKS, drops weather, significance, `author`,
  `type`, `source`; writes `capture:` and `voice:` (set by each app, never derived); flat,
  named, media beside the note; the whole feature sits behind ONE Settings switch, off by
  default; a destination is a per-device folder bookmark, one archive root. || check:
  `ArchiveExportTests`; corpus `dest-*`. — ledgers:144-155
- C63 [auto] No video goes to the Obsidian vault: a video note exports markdown + audio + the
  frame there. The ARCHIVE export copies the Mac-kept source movie when the Mac exports
  (Tuur 2026-08-28, "that is gold"; the phone discards the movie, see D44). || check: corpus
  `video-*`; `video-made-archive`. — ledgers:153, code-core K:248
- C64 [auto] `date:` is computed the same way on every device (ONE timezone rule).
  || check: phone and Mac export of one corpus note at 23:30 agree. ⚠ needs-verdict D13
  — code-core needs-verdict 5
- C65 [auto] Export stops transforming the body (no snap) once C10 holds. || check: exporter
  has no `snappedImageBody` call. — B:700

### Ingress (share / import) — every door, from the code (ingress.md: 30 paths)

- C66 [auto] Every share jumps to its note on the next app-open; every share offers the
  rating; audio shares carry no annotation field. || check: `CaptureInboxDrainer` tests.
  — ledgers:167-168
- C67 [auto] Attachments from ALL extension items AND all providers of an item enter the
  dispatcher, the extension-fallthrough audio branch included (WhatsApp ships a multi-select
  as several items; Signal as several providers; today only the first is read). || check: a
  3-item WhatsApp share → 3 clips; 4 Signal notes → 4 clips. ⚠ required difference — ingress
  P1/P2, B:5215, scenarios #1 #13
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
- C72 [auto] URL capture: title/description/thumbnail fetched on drain (one GET, no JS, local
  thumbnail, article text search-only); a failed fetch (metro, offline) is retried at the next
  foreground with network, at most three times; no title → the host as title, never the raw
  URL. || check: ingress P5 fixtures replayed from the recording, incl. a failed first GET;
  corpus `cap-url-no-title`. ⚠ needs-verdict D14/D15 on YouTube / Instagram; D42 on the
  retry — ledgers:186-187, scenarios #10
- C73 [auto] PDF link → downloaded file capture (magic-byte check) with extracted text;
  `.txt/.md` share → the note body; PDF/doc share → file capture, the document syncs as an
  asset, its text is searchable. || check: ingress P5.1/P10/P11; corpus `cap-file-*`.
  ⚠ needs-verdict D22 (a text FILE with no comment: body or card) — ledgers:188-189
- C74 [auto] Image share: downsampled ≤ 2048 px, EXIF date → `recordedAt` (earliest of a
  multi-share), OCR on the next sweep; PNG stays PNG; a GIF is kept as a GIF (Obsidian
  animates it; the app shows the first frame); no re-encode to JPEG. || check: ingress P9.
  ⚠ required difference — ledgers:176, 215, D17
- C75 [auto] A share with an empty payload never saves a husk; failures are honest
  ("Skrift can't import this"). || check: `ShareSheetView` tests. — ledgers:183
- C76 [auto] Apple Notes export (`.md` + `Attachments/`): title from the first heading,
  attachments copied and relinked, `sourceType .note` (glyph "Apple Note"); dated by the
  note's own creation date when the export carries one, else marked date-unknown — never
  silently the import time. || check: ingress M4 fixture. — ingress M4, D18
- C77 [auto] The Mac imports everything the phone imports (PDF, image, URL, ePub, `.flac`,
  `.ogg`, …) through the ONE shared import layer of C238, and refuses honestly anything
  outside it. || check: ingress M1-M3 with every phone-accepted type produces the same note
  shape as the phone. ⚠ required difference — ingress M, D19
- C78 [auto] A capture is a memo without audio plus `sharedContent` (C3 contract, camelCase
  field names pinned; unknown type → nil); `SourceTaxonomy` is the one glyph+label map.
  || check: `SharedContentParityTests` both apps. — ledgers:198, 210
- C79 [auto] Audio ≥ 1 h offers Books; `.skriftbook` imports a book keyed on `bookID`;
  podcasts are a separate lane (not v2). || check: ingress P4/P18. — ledgers:185, 196

### Names & sanitise (referenced by targets 2 and 4; not rewritten)

- C80 [auto] Known-roster only, deterministic, no LLM/NER: a full or distinctive first name
  auto-links at first mention — the stored literal is bare `[[Canonical]]` (possessive
  outside) in a monologue, `[[Canonical|short]]` inline in a conversation (the phone's
  "spoken" form is DISPLAY, not storage — `Sanitiser.swift:1-30`); later mentions plain; a
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
  fades; playable, searchable, editable like any note. CloudKit syncs EVERY memo regardless
  (flag-to-PROCESS, never flag-to-send). ONE predicate (`NoteConsent.isRated`) for both apps;
  `PipelineFile.significance == nil` resolves once (projection = unrated, local recording =
  unrated, import/legacy = rated). || check: `NoteConsentTests`; corpus `voice-en-unrated-*`. — decisions:143
- C88 [auto] Rating is a one-way door on a synced pipelined note: un-rating keeps the ROW but
  drops it from the process queue and stops every export; a pending pass on an unrated row
  never runs. Mac-local takes are two-way. || check: corpus `voice-en-rated-then-unrated`.
  ⚠ required difference (today `needsProcessing` ignores the rating, `WayOutRules.swift:102`,
  so the Mac polishes an unrated note — C87 and the old C88 contradicted each other)
  — decisions:146, scenarios #31
- C89 [auto] ONE clock: `clockStart = max(recordedAt, keptAt)`; touch restarts 30 days;
  fading at 30, Recently Deleted at 60, gone 14 seen-days later; rated / locked / reminder /
  backlinked notes never fade (a backlink from ANY live memo counts, D-B33); final doors move
  only at an app-open. A TOUCH = edit / title / tags / lock / reminder / annotation / keep /
  bring-back (`markEdited` is the tracepoint); photos, bare captures, rating changes and
  Mac→phone meta writes are NOT touches. Fading is derived, never stored; sweeps run from
  install with no arming gate. || check:
  `MemoLifecycle` tests; corpus `voice-en-unrated-old`, `voice-en-unrated-kept`,
  `edge-old-rated-never-exported`. — decisions:138, 142
- C90 [auto] Trash is soft everywhere, synced via `deletedAt`, purge clock = `trashSeenAt`;
  trash is not searchable, fading is. || check: `TrashTests`; corpus `typed-trashed`.
- C91 [auto] Locked notes sync, never export, show title + 🔒 only, unlock per session.
  || check: corpus `typed-locked`. Processing continues on a locked note (Tuur 2026-09-22:
  "no one should see it" — lock is about eyes, not the pipeline) — D10 decided as today.
- C92 [auto] Reminders are synced data; each device derives its own alarm. || check: corpus
  `typed-reminder`. ⚠ unverified: Mac reconciler owed — ledgers:53 (lifecycle)
- C93 [auto] Tags: split on comma/newline, need a letter or digit (`[]` refused), `#`
  stripped once, case kept; all four destination words are accepted as tags (code 2026-08-27;
  the ledger's "reserved" line is stale) and `inspiration` raises `needs: - credit`; inline
  `#tag` grammar = `TagComplete` (no spaces, `_-/`). || check: corpus `typed-bracket-tag-bug`, `typed-tags-with-spaces`,
  `typed-reserved-word-tags`. ⚠ needs-verdict D23 on case-variant duplicates — Memo.swift
- C94 [tuur] Importance control: 10 circles today; i23 proposes 3 (or 4) buttons — mock
  first. ⚠ needs-verdict D30 — mocks-roadmap i23

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
- C98 [auto] A same-note edit on two devices that meet after being apart is a CONFLICT, never a
  silent overwrite: the note shows it, he picks the version to keep, the other stays
  recoverable (C242). New notes never conflict. || check: two in-memory stores with diverging
  edits → the merge yields a conflict record, not a loss. — D24

### Recording & audio (out of the rewrite; listed so nothing is lost)

- C99 [auto] A recording is NEVER lost, whatever happens mid-take: a phone call, Siri, an
  alarm, a kill, a dead battery. Audio is persisted in segments during the take (on every
  interruption and every 60 s), a marker plus a launch sweep rebuilds the note and says so, and
  a force-quit finalises. || check: a simulated call and a process kill mid-take on the sim →
  the note is present after relaunch with all audio up to the event; the iPhone 13 call test.
  ⚠ required difference (D4, issue #14) — BUGS D4; Tuur 2026-09-22 "never ever ever"
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
  widget and via Siri opens an empty note with the keyboard up, in under a second. Independent
  of the rewrite (views + intents), so it goes near the front of the queue. Mock first.
  CONFIRMED 2026-09-21 ("either record or just start a new note. simple smooth and fast")
- C113 [tuur] The editor feels like Apple Notes: no lag while typing, paragraphs stay where
  he put them, a picture is a block he can move. Today it is "quite slow and clunky" (Tuur
  2026-09-21). Rebuilt on the body v2 (C10), never before it; profile the editor first (the
  slowness may be the list scans and sweeps in BUGS §3, not the text view). Mock first.
  CONFIRMED 2026-09-21
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
- C122 [auto] The corpus is synthetic; agents never read his vault and never screenshot the live
  app at a real note; Dev and prod are separate containers and the Dev vault is the test vault;
  tests run on temp dirs, never the Dev container. The privacy rule targets cloud AI: Skrift's
  OWN code may read its exports and the vault (titles for the roster, tag names). || check:
  `AppPaths` dev suffix; a `-corpus` path guard under his vault (new rule, drafter's).

### Messenger shares — added 2026-09-21 after Tuur's WhatsApp probe

- C123 [auto] A share from a messenger can carry the SENDER: a name field on the share sheet
  (optional, remembered per chat when the share carries a hint), editable later in the note;
  the name is a person mention like any other (links if on the roster, else plain) and
  exports into `people:` when linked. || check: ingress P1/P3 fixtures with a sender set.
  — Tuur 2026-09-21 ("can just be filled in on the share screen or later in the note")
- C124 [auto] A merged multi-clip note keeps its message boundaries: each clip starts a new
  paragraph; the note is dated to the FIRST message (filename date, C70) and each clip's
  own time is kept in the manifest. || check: ingress P1 5-clip fixture → 5 paragraphs.
  ⚠ needs-verdict D35 (show the per-message time in the body or not)
- C125 [auto] Several text messages in one share keep their order among the clips and
  pictures; none is dropped. || check: ingress P3 fixture with 2 texts. ⚠ required difference
  (today only the first text survives)
- C126 [auto] A Voice Memo shared with its own name ("kiln idea.m4a") keeps that name as the
  note's title; a messenger filename is never a title. || check: ingress P1 named-memo
  fixture. ⚠ required difference (the extension renames every blob before the app sees it)
- C127 [auto] Sharing the same file twice yields one note (same bytes → same note), with a
  "already in Skrift" notice. || check: share the WhatsApp fixture twice. ⚠ needs-verdict D36
- C128 [auto] The WhatsApp / Signal chat-export zip is NOT an ingress path in v2 (parked;
  it is the only carrier of sender names and exact order). || check: `.zip` shares refuse
  honestly. ⚠ needs-verdict D37

### The archive contract — Skrift ↔ the portfolio repo (`~/Hackerman/Tiurihartog.com`)

The archive's own rules (its `portfolio/README.md`, `.claude/rules/portfolio.md`, `_ideas/`
and `_inbox/` READMEs, `docs/SKRIFT-REQUEST.md`, roadmap ideas i14/i16/i29/i43/i50) read
2026-09-21. Skrift is the CAPTURE pipeline; the archive is where captured ideas LIVE
("I need a place to capture them and a place to put the ones I have captured", 2026-08-26).
The interview loop, sorting into item folders, links and layers happen on the archive side,
never in Skrift ("then you can't have immediate AI back and forth" — rejected).

- C129 [auto] What Skrift writes for Made / Idea / Inspiration is exactly what the archive
  stores: one flat markdown file, media beside it sharing its basename, no folder per entry;
  `![](file)` relative embeds only, never `![[…]]`. || check: `ArchiveExportTests`; corpus
  `dest-*`. — portfolio/README, _ideas/README
- C130 [auto] Archive frontmatter is flat YAML: one line per value, no `: ` inside a plain
  value (reword, never quote), block lists never `[a, b]`; keys Skrift may write: `title`
  (only when HE gave one), `added`, `capture`, `voice`, `tags`, `people`, `location`,
  `credit` (shape `- <who> — <what they did>[, <url>]`), `needs`, the stamp trio. Skrift never
  writes `type`, `source`, `author`, `summary`, `confidence`, `status`, `layer`, `shortlist`.
  || check: every corpus `dest-*` export parses with the archive's own parser
  (`capture/tools/vault_index.py`). ⚠ required difference (v1 writes `summary:` into every
  profile — `Shared/Export/Compiler.swift:128`; the archive dropped the key 2026-08-26)
  — portfolio/README, rules:496-498
- C131 [auto] THE AUTHORSHIP LINE: everything above the closing `---` is the machine's,
  everything below is HIS. An archive-bound body is never a generated text: no LLM title in
  the body, no summary, no invented words; `voice: raw` = the transcript verbatim,
  `voice: cleaned` = grammar and punctuation only, his words in his order, diffable against
  the raw — DECIDED 2026-09-22: Skrift's copy-edit (fillers and repeats removed, nothing
  rephrased, nothing added) IS `cleaned`; the archive's grammar-only wording is to be loosened
  to match; `voice: written` = typed, untouchable. NO GLUE. || check: for every archive-bound
  corpus note, no word of the cleaned body is absent from the raw body (removals only).
  — rules:192-223, D38
- C132 [auto] An archive entry is named by the note's title, typed or generated; the timestamp
  (`2026-08-26-142312.md`) only when there is no title at all. Tuur 2026-09-22: a generated
  title is as good a name as a typed one. = v1 (`VaultWrite.swift:112-115`); the archive's
  own docs are to be relaxed to match. || check: `dest-idea` → slug of its title. — D39
- C133 [auto] Destination is one of four, single-select; "Personal" never reaches the
  archive; Made → `_inbox/`, Idea → `_ideas/`, Inspiration → `_inspiration/`; anything else
  that is also true rides as an ordinary tag. The line between Idea and Inspiration is
  INTENT: a want of his in the entry makes it an idea even when the object is someone
  else's. || check: corpus `dest-*`. — _inbox/README, rules:537-547
- C134 [auto] Credit is captured as a PHOTOGRAPH, not typed: an extra picture of the label
  travels with the entry; an Inspiration, or an Idea tagged `inspiration`, carries
  `needs: - credit` so a later archive pass fills `credit:` or keeps the need. Skrift never
  guesses a maker. || check: `dest-inspiration-credit`, `typed-reserved-word-tags`.
  — rules:549-569
- C135 [auto] Empty body is a valid, common archive state (a bare picture); Skrift exports
  it without inventing a sentence. || check: `cap-image-no-words` with destination idea.
- C136 [auto] The archive-bound export carries the ORIGINAL audio beside the note (he
  reuses audio in videos) and never a video file. || check: `dest-made` export folder.
- C137 [auto] `people:` and `[[names]]` stay in archive exports (public site, credit his
  friends); places do not. — Tuur 2026-08-27, don't fix back
- C138 [tuur] The reverse direction — ideas coming BACK into Skrift to explore them with AI,
  or Skrift attaching a capture to an existing archive item — is undecided (i43, i14).
  ⚠ needs-verdict D40
- C139 [tuur] "AI reads this" is a statement about the archive repo only; what reads it
  (the teleprompter sessions, Claude in that repo) is the archive's contract, not Skrift's.

### From the 50-scenario probe (plan/extraction/scenarios.md, 2026-09-21) — proposed, unconfirmed

Ingress:
- C140 [auto] A Live Photo is a picture: the still is taken, the paired movie ignored. || check:
  ingress P9-live-photo. — scenarios #4
- C141 [auto] An image share with a text provider keeps the text as the annotation above the
  pictures (WhatsApp photo + caption); no branch drops another provider's text. || check:
  ingress P9-photo-with-caption. ⚠ required difference — scenarios #5
- C142 [auto] An email share (`.eml` / Mail) is a text capture: title = Subject, body = the plain
  text, `recordedAt` = the Date header, sender per C123, attachments as files. || check:
  ingress P10-email. ⚠ needs-verdict D43 — scenarios #6
- C143 [auto] A Notes-app share (text + images) is one note: text as the body, pictures per C12.
  || check: ingress P7-apple-note-share. — scenarios #7
- C144 [auto] Selected text + page URL is a text capture carrying the url and title, no fetch;
  a Maps link is a link capture with the place as location and title, no fetch. || check:
  ingress P6, P5.2. — scenarios #8 #9
- C145 [auto] Open-in and AirDrop show the same slim sheet (rating + sender) before the jump
  and date from the filename (C70); the in-app Files importer offers the One-note / N-notes
  chooser for several audio files. || check: AirDropped Signal `.aac`; three m4a via Files.
  ⚠ required difference — scenarios #11 #12
- C146 [auto] A `.skriftbook` arriving through the share sheet goes to the book importer, never
  a file card. || check: ingress P18-via-share. — scenarios #14
- C147 [auto] A share entry is deleted only after its memo is saved, for every type; a re-drain
  is idempotent (memo id from the entry). || check: drainer test that throws after the delete.
  ⚠ required difference (a kill in that window loses the clips today) — scenarios #19
- C148 [tuur] A video filed Made / Idea / Inspiration keeps the source movie as a synced asset so
  the archive gets it; Personal videos keep discarding it. ⚠ needs-verdict D44 — scenarios #18

Recording and copy-edit:
- C149 [auto] An interruption (call, Siri, alarm) is a pause: the recording clock stops and photo
  offsets read that clock, so a picture taken after the call lands where it was taken. || check:
  corpus `pic-after-interruption`. ⚠ required difference (offsets are wall-clock today,
  `RecordView.swift:453`) — scenarios #21
- C150 [auto] A long note is never shipped unedited because it is long: over half the token cap,
  copy-edit runs per block — split only at paragraph boundaries, up to ~1,500 words, a longer
  paragraph is its own block — each block under C31–C34, re-joined in order. DECIDED
  2026-09-22. || check: corpus `voice-en-forty-minutes`. — scenarios #22, D45
- C151 [auto] A transcript carries the ASR language mode it was made with, and a per-note
  "Transcribe again in Dutch / English" verb exists; the global setting is only the default.
  || check: corpus `voice-nl-recorded-in-english-mode`. ⚠ needs-verdict D46 — scenarios #23
- C152 [auto] Text appended to a polished note (append recording, capture ramble) appears in the
  body he sees and sends the note back for a pass that polishes only the new block. || check:
  corpus `voice-en-append-after-polish`. ⚠ required difference (today the append writes only
  the raw transcript, `MemoSaver.swift:657`, while every screen shows the polished body: the
  new words are invisible) — scenarios #27

Sync and lifecycle:
- C153 [auto] A raw edit newer than the row's `enhancedAt` sends the row back to pending; the
  phone shows the edit until the next pass. || check: `MemoCloudUpdateTests` post-run race.
  — scenarios #28
- C154 [auto] Another device's `.transcribing` memo is taken over after 30 minutes when its audio
  is present and the recorder has gone quiet. || check: aged corpus note. ⚠ needs-verdict D47
  — scenarios #30
- C155 [auto] Sync health is visible: a CloudKit quota or sign-in failure shows on the list within
  a minute and on the note as "not synced yet". || check: injected quota error. ⚠ needs-verdict
  D48 — scenarios #34
- C156 [tuur] Trashing an exported note leaves the vault file and says so; Delete Now offers to
  remove the file when it is ours and untouched. ⚠ needs-verdict D49 (was D-parked "should
  trashing delete the .md") — scenarios #35
- C157 [auto] A purge deletes the note's polish row and every asset; a Mac row whose memo is gone
  is trashed on the next sweep, never its vault file. || check: purge test; orphan-row sweep test.
  ⚠ required difference (`NotesRepository.swift:112-126` keeps the enhancement) — scenarios #36
- C158 [auto] A picture removed from the body is removed from the vault on the next export when
  the file is ours and untouched; the manifest entry stays (C14). || check: corpus
  `pic-deleted-after-export`. — scenarios #39

Names:
- C159 [auto] A roster change (add, alias, rename) re-derives links for every processed row on the
  Mac once, deterministically, and re-exports the untouched vault files we own; a rename rewrites
  `[[Old]]` → `[[New]]` and `people:` there; edited or foreign files are never touched. || check:
  corpus `voice-en-bruno-before-roster` ×3; rename golden. ⚠ required difference (today only the
  open note re-scans; phone and Mac exports diverge after a rename) resolves D32 — scenarios #40 #41

Audiobooks, locks, reminders, export:
- C160 [auto] A captured quote can be corrected ("Fix quote" on the phone); the corrected block is
  the escrowed quote everywhere; attribution unchanged. || check: edited-quote golden.
  ⚠ needs-verdict D50 — scenarios #45
- C161 [auto] Locking hides: a locked note keeps processing but is never exported or shown
  without auth; locking an exported note says the plaintext file still exists and offers to
  remove it when ours and untouched. || check: corpus `typed-locked` + a ledger entry.
  — scenarios #46, D10
- C162 [tuur] A reminder set on any device rings on the device he is holding; the first
  acknowledgement clears the others. ⚠ needs-verdict D51 — scenarios #47
- C163 [auto] Changing an exported note's destination removes the old file when ours and
  untouched, then writes the new one; if the old file was edited or moved, the change is refused
  with the file named. A Personal note never remains in the archive. DECIDED 2026-09-22.
  || check: corpus `dest-idea` re-filed Personal. ⚠ required difference (per-folder ledgers
  leave the old file today, `VaultWrite.swift:27-100`) — scenarios #48
- C164 [auto] A retitle never renames the exported file ("rename just has to be done in
  Obsidian" — Tuur 2026-09-22); switching the vault folder never moves old exports (new notes go
  to the new folder; Settings says so). || check: `VaultWriteTests` retitle, two-root. — scenarios #49 #50

### Shared code across the three apps — Tuur 2026-09-22

- C238 [auto] ONE import layer in `Shared/`: the accepted types, the dispatch (audio / URL /
  movie / image / text / document / book), the filename-date ladder and the resulting note
  shape are the same code on iPhone, iPad and Mac; a Mac drop, a phone share and an iPad
  Files pick of the same file yield the same note. || check: ingress fixtures run on both
  apps produce identical `note.json`; no per-app accept list remains. — D19
- C239 [auto] Twin audit before v2 target 3: every place the Mac and the phone carry their own
  copy of one rule is listed (known: export engines, polish escrow, body reconstruct, speaker
  parsing, Connections panel, thumbnail rule, title ladder) and each is folded into `Shared/`
  or marked as a deliberate platform difference with the reason. || check: the list in
  `plan/twins.md` has no unmarked row. — Tuur: "check to see we share as much code between
  them to prevent drift"
- C240 [tuur] UI is shared where the platform allows: the note card pattern (one shared view +
  a per-app style struct) is the model; a short research pass on how other multiplatform
  SwiftUI apps share screens precedes the twin audit. — Tuur: "more UI also if possible, see
  how other apps do this"

### From sitting round 5 — Tuur 2026-09-22

- C241 [tuur] The tag UI is redesigned: "the tags need to be revamped, the UI is annoying to use".
  Mock first; the rules (C93) stay. — D23
- C242 [tuur] Conflict handling: when one note carries two diverging edits from two devices, the
  app shows a conflict on that note and lets him keep this device's version, the other's, or
  both as two notes; the version not kept stays in version history for the trash window.
  Modelled on Shapr3D's "Version Conflict Detected" dialog, whose own support recommends
  "keep both" as the safe choice (discourse.shapr3d.com/t/version-conflict-detected/21886);
  mock first. — D24

### Rules recovered by the coverage audit (plan/extraction/spec-coverage.md §A) — for confirmation

Method and gate:
- C165 [auto] The vault filename stem derives from the title by ONE rule: title else filename
  stem; `/ \` → `-`; strip `* " < > : | ? # ^ [ ]`; collapse spaces; cap 120; the exporter's
  hard 80-char slice stays because it feeds the filename. || check: `VaultName` tests. — A53
- C166 [auto] Mac corpus goldens come from `-ingestfile` → `-processfile -exportafter` on the Dev
  store (GUI quit first); simulator runs use the seeded engines. || check: harness script. — A1
- C167 [auto] Every engine and the model are revision-pinned; a pin bump is its own commit and
  owes a device round (this session: mlx-swift-lm → #544 for Xcode 27). || check: no
  `branch:` refs in project.yml. — A2
- C168 [auto] No swallowed error on any write surface (vault, store, sync); every refusal reaches
  the UI as text; an engine fault throws onto the row, the app never dies on a bad model load.
  || check: `try?` count in Shared/Export, Shared/Naming, Pipeline/Ingest = 0; MLX faults wrapped.
  — A3, A5

Body/image model:
- C169 [auto] `offsetSeconds` excludes paused time; manifest order = capture order; marker N =
  manifest index; splitting speakers keeps every picture as its own paragraph after the turn
  sentence it was spoken in (D3). || check: `MemoSaver` persist tests; corpus `conv-with-picture`.
  — A6, A7
- C170 [auto] List thumbnail = first marker in BODY order that resolves; all markers deleted →
  none; marker-less share capture → first manifest photo; typed body → none.
  `transcriptMarkersInjected` stays on the wire and is read only by this rule. || check:
  `MemoDisplay` tests. — A9, A10
- C171 [auto] Filler strip is opt-in (default off), voice memos only (never quotes or live
  caption), drops token + timing together; an all-filler input is unchanged. || check:
  `FillerFilterTests`. — A12
- C172 [auto] ONE quote splitter for display, copy-edit and export (indent tolerance decided
  once); the quote block of a capture is read-only in the editor, only the ramble edits; a
  quote capture is born `transcriptUserEdited` with no location. || check: no second splitter.
  — A13, A14, A15
- C173 [auto] The edit target is pinned at the first keystroke of a burst; an arriving polish
  never receives a raw-born draft (P0 2026-07-10). || check: `NoteBodyTests` markDraftDirty. — A17
- C174 [auto] Conversation detection is gated on an audio source; an Apple Note with two bold
  headings is prose. || check: corpus `applenote-headings-checklist`. — A18
- C175 [tuur] Mac turns = right gutter + spine (E1, signed 2026-07-27); the phone KEEPS its turn
  cards with the shared hues; turn spacing stays looser than the mock. — A19
- C176 [auto] Capture-image markers in an annotation convert and copy like memo photos; the
  pinned embed is skipped when the body carries markers; legacy marker-less captures keep the
  old path. || check: `VaultExporterTests` capture rows. — A20

Copy-edit:
- C177 [auto] Post-conditions on every model output: no proper noun absent from the input; the
  language never flips; length bounded; a failed gate ships the unedited text. Prompts carry
  the text only, never place / weather / people. Prompt rewording is not the cure for the
  Dutch near-echo (A/B refuted 2026-08-19); the paragrapher is. || check: gate tests on the
  corpus; the prompt builder has one text input. — A21, A22, A23
- C178 [auto] After generation the deterministic tail runs in this order: tags → name-link
  (last) → compile; no `[[ ]]` reaches the model. Tag suggestions are deterministic (vault tag
  NAMES from frontmatter only, lemma ≥ 2×, max 10 + 5 spoken `#hashtags`); the user accepts.
  || check: `BatchRunner` order test; `TagMatcher` tests. — A24, A25
- C179 [auto] Redo (title / copy-edit / summary) rewrites one part in place through the same
  escrow, LWW-stamped; never a second enhancement row; offered only where polished + engine +
  unlocked; conversations keep verbatim. || check: `PolishCenter` redo tests. — A27
- C180 [auto] The Mac is the automatic, unattended batch polisher; the iPad polishes ONLY on
  the visible verb (no polish-on-open, Tuur 2026-07-23), one note at a time, iPad only (≥ 6 GB,
  never the simulator); the iPhone never polishes. || check: `PolishCenter` gate tests. — A28
- C181 [tuur] The phone shows the polish as the ONE editable body (no raw/polished toggle);
  an edit lands in the enhancement, stamped; title chooser Suggested / recording / own;
  "Polished on your Mac" provenance. — A29
- C182 [auto] Interrupted runs reset to pending at launch; the queue = live ∧ not done ∧ not an
  unrated Mac take, oldest first, one at a time; models unload after 60 s idle; re-transcribe
  also clears diarization + its sidecar and keeps the chosen title; "Flatten to monologue"
  drops headers, clears diarization, re-polishes as monologue, no re-ASR. || check:
  `RunReconciler`, `ProcessingCoordinator` tests. — A30, A34, A35
- C183 [tuur] The refine pass at ≥ 0.8: keep or drop in v2 — decides D30's fourth button.
  ⚠ needs-verdict D52 — A26
- C184 [auto] The verb is "Process" on every device; "memo" → "note" in every user string. — A33

Reconcile sweep:
- C185 [auto] Names and vocab reconcile BEFORE the memo sweep so linking sees the fresh
  roster; then notify → save + re-export → Mac author backfill → transcript reflect →
  connections index. || check: wiring order test. — A37
- C186 [auto] Every Mac → phone writer resolves the memo through the STORE, never by filename
  alone; a Mac recording rides the Import door (`ArrivalPath`), no second path. || check:
  `MacCloudWriteBackTests` resolve. — A40, A41
- C187 [auto] An unrated note has NO row: the Mac renders it through a transient projection and
  edits it on the `Memo` itself, never as an enhancement; the Journal reads the cloud store
  read-only. || check: `MemoNoteProjection.writeBack` tests. — A42
- C188 [auto] Row match = memo id, else `audioFilename` — but never a row already owned by
  another memo (quote captures inherit the source filename); the row's content date is the
  phone's `recordedAt`, never ingest time; a nil or blank phone title never clears the Mac
  title; lock / reminder / OCR changes never recompile; Mac → phone meta writes never bump
  `lastEditedAt`; a Mac-initiated trash stamps `trashSeenAt`. || check: reconciler +
  update tests. — A39, A46, A47, A48
- C189 [auto] Auto re-export after a sweep happens only for notes already in the vault
  (unlocked, live); the first export is always the verb; refusals are logged, not raised.
  || check: wiring re-export test. — A49
- C190 [auto] Asset materialisation never overwrites a file and refreshes on byte count only;
  stuck `.transcribing` / diarizing memos are recovered once per launch by the recording
  device only; permanent delete stays device-local, the phone owns the purge, a Mac soft-delete
  keeps the working folder. || check: `AssetMaterializerTests`. — A50, A51, A52
- C191 [auto] `cloudKitMacSync` defaults ON (an explicit false is honoured); silent push is
  registered on both apps so sync lands in seconds even backgrounded. — A44, A105

Export:
- C192 [auto] `VaultLayout.home`: a pick named Skrift, or holding a stamped `.md`, or containing
  a `Skrift/` folder, is used as-is; otherwise `<pick>/Skrift` is created on first write; media
  subfolders `Recordings/ Images/ Documents/` are fixed; the archive returns the pick
  unchanged. || check: `VaultLayoutTests`. ⚠ needs-verdict D11 (the created-`Skrift/` case)
  — A54
- C193 [auto] The stamp hash spans the frontmatter (an Obsidian tag edit is a user edit) and
  every line but its own; only text starting `---` is stamped; the stamp keys are a public
  contract for the plugin, never renamed. Losing the ledger costs nothing: the next export
  re-adopts by stamp; a retitle never moves the file. Skrift never deletes a vault file;
  locking an exported note shows "already in your vault". || check: `VaultWriteTests`,
  `VaultStampTests`. — A55, A56, A57
- C194 [auto] Outcome copy is ONE shared table: a refusal stays until dismissed; `unchanged`
  never says "Exported"; the refusal names the first failing gate; the primary verb is ONE
  three-state rule Process → Export → Re-export. || check: `ExportOutcomeCopy`,
  `NoteWorkState` tests. — A58, A65
- C195 [auto] Include audio in export = a per-note switch, default on, file named by the stem
  under `Recordings/`; the flag is Mac-only and does not sync (D-B15). || check:
  `VaultExporterTests` audio. — A59
- C196 [auto] Body precedence on export: sanitised → copyedit → transcript; a dangling marker is
  dropped, never printed; assets are written after the note, failures counted, never fatal.
  || check: `VaultExporterTests`. — A63
- C197 [tuur] Full-exportability doctrine (2026-07-18: the vault is a complete mirror of rated
  notes; timings, embeddings, sync state stay internal) is superseded in part by C61
  (processed-only, verb-driven). Confirm the narrowing. — A66

Ingress:
- C198 [auto] Share dispatch order: audio → web URL → movie → image(s) → plain text → document;
  first match wins; the audio branch keeps images + text, the URL branch keeps selected text
  (text beats URL, URL rides along); a share carries rating + annotation only (no title, no
  tags, destination Personal); a Maps link → location + place chip, no fetch;
  `maps.app.goo.gl` short links stay plain cards by design. || check: `SharePayloadLoader`
  fixtures. — A67, A68, A69
- C199 [auto] Open-in accepts what the share sheet accepts (`.ogg/.oga/.m4b/.pdf` are silently
  ignored today); in-app Import has three doors (Files, Video from Photos, Scan); an
  audio-only `.mp4` is probed for a video track (D-B26). || check: `AppURLHandler` tests.
  ⚠ required difference — A70
- C200 [auto] Whether FluidAudio decodes ogg-opus on device is UNVERIFIED (the doc promises a
  Mac fallback, the code marks `.failed`). || check: ingress P1 opus fixture on the sim. — A71
- C201 [auto] Inbox entries that cannot be deleted are tombstoned (cap 200) so nothing
  re-imports on every open; the drain is off-main with a re-entrancy guard; feedback copy is
  fixed ("Saved ✓ … Skrift opens on it next time" / error + Try again / "Skrift can't import
  this"). || check: `CaptureInbox` tests. — A72, A77
- C202 [auto] Captures get no location or weather; the Mac stamps `location:` for RECORDINGS
  only, never imports; silent video → a `.failed` note "Video had no audio track" (identical).
  — A73, A74
- C203 [tuur] Legacy shapes that do NOT migrate under D4: old test image-captures stay broken
  (2026-07-10), pre-build-76 PDF captures stay text-only. Confirm the list. — A76

Names:
- C204 [auto] Canonical = the `People/` note title; Skrift writes links and `people:`, never the
  person page; roster seeding reads filenames only (title + first token as aliases),
  idempotent, no contents, no AI. || check: `PeopleFolderScanner` reads no body. — A78, A79
- C205 [auto] Normalisation ≠ linking: registered aliases fix a misheard KNOWN name everywhere
  (dotted when unlinked, one-click revertible); only the first mention links; genuine
  nicknames are not preserved unless registered as aliases (D-B37). || check: `SanitiserTests`.
  — A80
- C206 [auto] Two unlink scopes, note-local (this mention / all mentions in this note),
  persisted in the note's resolutions; the roster is never edited from a note; no "never link
  anywhere". || check: name-unlink tests. — A82
- C207 [auto] A roster collision re-derives every processed memo that auto-linked the name
  (dotted suggestion + count flash) in-app only; duplicate aliases across people are legal
  (that IS the two-Jacks ambiguity); a stoplisted frequent person stays dotted in every memo
  (no per-person override); sentence-initial "Will you…" noise is accepted. || check:
  `RosterAudit` tests. — A83, A84
- C208 [auto] `names.json` merge: per-person LWW on the stamp, tombstones win when newer,
  pruned after 90 days; alias defaults to the name; case-insensitive de-dupe; rename carries
  voiceprints; delete tombstones without them. || check: `NamesMerge` tests. ⚠ needs-verdict
  D-B12 (tie rule) — A85
- C209 [auto] Voice identity: true cosine, ≥ 2 s of speech, max over the stored list, audio
  discarded after embedding; naming a speaker enrols the voice; attribution gated on trust;
  unnamed stays unnamed ("a wrong attribution is worse than none"); "Split speakers" is
  post-transcript with Auto/2–5, forcing N merges the most similar; fusion byte-identical on
  both apps. || check: `SpeakerFusion`, `VoiceMatch` tests. — A86, A87

Consent, rating, lifecycle:
- C210 [auto] The rating grid: 10 stops 0.1…1.0; tiers Passing 0.1–0.3 / Useful 0.4–0.6 /
  Important 0.7–1.0; refine wall ≥ 0.8; tap the Nth → 0.N, re-tap → Not rated; user-facing
  word "Importance"; ties broken by date. || check: `SignificanceScaleTests`. — A89
- C211 [auto] The three lifecycle strings are byte-pinned in the spine ("starts fading <date>" ·
  "moves to Recently Deleted in Nd" · "gone for good in ~Nd"). || check: `MemoSpineTests`. — A92
- C212 [tuur] Lifecycle IA as signed (lifecycle-ia-explorations + triage-peek m6): one conveyor
  named "Fading", one verb "Bring back", one Recently Deleted in Review, delete soft everywhere
  with no confirm on the Mac, lock a background verb, phone placement B; one counting surface
  per station; the Mac list is the deciding room and the phone list the notebook — deliberately
  not twins; pills Mac always / iPad in-flight + error only. — A93, A94, A95
- C213 [auto] Lock = hidden, not encrypted, stated in-app; the player never loads a locked memo;
  Copy is gated behind auth. || check: lock tests. — A96
- C214 [tuur] Retention doctrine: the permanent corpus is the rated notes; nothing is pruned
  without a review he approves; audio before text. — A97
- C215 [auto] `ProcessPile.waiting` = rated ∧ live ∧ unlocked ∧ real transcript ∧ not processed;
  unrated Mac takes are out of "Process N"; `canSummon` = rated ∧ !locked. — A98

Sync contract:
- C216 [auto] `Memo.id` is the spine: never regenerated, embedded in the audio filename, equal
  to the Mac row id; asset kinds audio | photo | wordTimings | diarization | document with
  fixed filenames (`memo_<id>.<ext>`, `photo_<id>_NNN.jpg`, `wt_<id>.json`, `diar_<id>.json`,
  `file_<id>.<ext>`); one enhancement row per memo, newest wins on read; once-only UI flags
  live in UserDefaults, never in a synced record. — A100, A101, A104
- C217 [auto] Language mode (English = mel on / Multilingual = mel off) syncs both ways with
  its own LWW stamp; a default nobody chose never pushes; adopting a remote value reloads the
  ASR. || check: `LanguageSyncCoreTests`. — A102
- C218 [auto] Audiobook sync contract (out of the rewrite, kept so nothing is lost): per-book
  opt-in, raw CloudKit records `ab_<bookID>_<i>` / `_cover` / `_t<i>` / `_al<n>`, Wi-Fi only,
  position + rate LWW, bookmarks whole-list LWW, transcript sidecars re-stamped on arrival,
  alignment applied only once the transcript matches, an applied-marker records what it
  produced, unshare keeps local audio. — A103
- C219 [auto] The schema is additive-only; a synced `@Model` is never renamed or dropped (dead
  `AudiobookAsset` stays); Dev may add fields; prod needs "Deploy Schema Changes" at promotion.
  Minimum iOS 26; `Shared/` is a source folder, not a package; the Mac row's duration reads
  numeric seconds and legacy HMS, v2 writes one representation. — A106, A107, A108

Recording and audio (out of the rewrite):
- C220 [auto] Mac live transcription: the note pane IS the draft; settled text is the user's
  (editable mid-take, the engine only appends), the wet tail is the engine's; settle = TEXT
  STABILITY (two identical tail decodes); the RMS/VAD lane is DEAD on his mic — never re-tune
  levels, extend stability; Mac rotates at 7 s, the phone keeps its 25 s; an edited take lands
  `transcriptUserEdited`. || check: `LiveRecordingDraft/Finalize` tests. — A109
- C221 [auto] The recorder survives every route change and interruption: the tap is reinstalled
  in the current hardware input format (validated with inputFormat, never outputFormat), never
  a permanent give-up; `.ended` + foreground re-arm; a 2 s watchdog rebuilds a dead engine.
  || check: `RecordingCore` route tests; device round. — A110
- C222 [auto] Live captions auto-stop after 60 s (Never / 30 s / 1 / 2 min), transient; the
  toggle is sticky and works mid-recording; one-shot transcribe for files, streaming only on
  the live screen; gain `.default`; a < 0.4 s take is discarded ("Nothing recorded"); the
  camera is an on-demand sheet; intents stay plain `AppIntent` with no haptic before the
  session is ours. — A111, A113, A114
- C223 [auto] Append never lands empty: audio merged sample-accurate, text appended with a blank
  line, timings shifted by the precise base duration, `transcriptUserEdited` set; failure
  shows and retries. || check: `MemoSaver` append tests. — A112
- C224 [auto] Mac recorder = `AVCaptureSession` → `AVAudioFile`, avoids Bluetooth input, no
  buffer in 1.5 s → named-device alert, TCC denial → typed refusal + Open Settings, writer
  queue drained on stop. || check: `-recordcheck`. — A115
- C225 [auto] Memo playback and the book session are mutually exclusive; ducking only on Play;
  the book resumes only its own interruption pause, never over a live recording; book chunks
  skip the custom-vocab pass. — A116, A117

Audiobooks (out of the rewrite):
- C226 [auto] Capture always records voice (a bail discards the quote-only memo); build-your-
  quote is bounded (~90 s before + 8 lines after, 4 un-chunked); the last sentence ended
  before the playhead is pre-selected. — A118
- C227 [auto] ePub alignment: unique n-gram anchors → LIS → banded DP, exact per-word times,
  verdict aligned / partial / rejected on the monotonic gate; `.epub` primary, `.txt` freebie,
  `.mobi` skipped; "ePub TOC wins" scoped to aligned files; attach during transcribe is
  deferred; read-along display is a UNION (book text > bridged > ASR splice > gap fill ≥ 3),
  nothing deleted, collisions contested between texts only. || check: `EPubAlign` tests,
  `-readalongcheck`. — A119
- C228 [auto] `detectedChapters`: `[]` = ran and found nothing, nil = not yet; sidecars are
  file-local; a quote span never crosses a file boundary; a cancelled chunk redoes the same
  frontier; the speed estimate comes only from the measured per-device RTF. — A120
- C229 [tuur] Tab IA = Notes · Books · Review · Settings (Highlights cut, Library → Books,
  "Journal" → "Review"); Notes-tab book presence = card-at-rest / pill-when-live; the iPad
  shelf grid stays; ONE player at every width. — A121

Search and Connections (out of the rewrite):
- C230 [auto] Index grain = one gist vector (title + summary + place + people + tags) plus body
  chunks every ~150–200 words at sentence boundaries, turn headers stripped; relevance = max
  over vectors; trashed excluded, captures included, book sidecars out; a stale-model vector
  is never scored; the vault is NEVER indexed in v1; juxtapose, don't judge (no sentiment,
  stance or mood). || check: `EmbeddingIndex` tests. — A123, A124
- C231 [auto] Review surfaces: search "Related" only when the query has ≥ 2 words or exact hits
  < 3 (top 8 above floor); Then-vs-Now (last ~2 weeks vs ≥ 6 months older); "Important lately"
  = ≥ 0.8 in ~30 days; Looking back = 1 w / 1 / 3 / 6 / 12 months, highest importance per
  window, "On this day". || check: `ThenVsNow`, `LookingBack` tests. — A125
- C232 [tuur] Connections chrome matches related-panel v3 + chrome-belongs v2: summoned by the
  WORD (no glyph, no count), Mac = floating inspector that stays open, iPad = per-note visitor
  sheet, thread retired on iPad/Mac and kept on the phone card; the embedder yields the ANE
  while transcribing. — A126
- C233 [auto] Print-to-wall fires once per note on crossing INTO ≥ 0.8, to the saved printer,
  offline-queued; the map on every device has an owned camera, dive-down only, and is a MODE of
  the column. || check: `WallPrinter` tests. — A127, A128

Editor and UI:
- C234 [tuur] The editor rebuild (C113) must not break: inline pictures, capture-quote
  protection, the speaker-turn view, `transcriptUserEdited`, save-now, polished-body editing,
  paging; swipe-between-notes stays OFF on the phone; the desktop note view is an EDITOR,
  WYSIWYG to the exported markdown. — A129, A131
- C235 [tuur] Built UI matches the signed-and-built rows of mocks-roadmap §B (editor, accessory
  bar, player pill, tag chips, photo viewer + markup, share-out, funnel filter, iPad header and
  chrome, Mac note header, ⋯ menu single-sourced); any deviation is a defect. — A130
- C236 [auto] Phone search = title, transcript, tags, place name, summary, OCR, PDF and article
  text; OCR hits match in LIST search only. — A132
- C237 [auto] Weather comes from OpenWeatherMap with his own key (D29 states the call). — A134

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
| R10 | (withdrawn: v1 already shows the domain for a title-less page — pre-register IDENTICAL; the only difference here is whatever D14/D15 decide) | — | `cap-url-no-title` | C72 |
| R11 | phone video glyph reads the wrong key (`mediaSource` vs `sourceType`) | the READER moves: one key, `SourceTaxonomy` reads what the phone writes | `video-*` | C71 |
| R12 | phone-added person has no aliases, never links | alias seeded | roster | C83 |
| R13 | Mac silently drops PDF/image/URL/ePub/flac | honest refusal | ingress M | C77 |
| R14 | `ensureParagraphs` passes a 7k output with 2 stray breaks | judged per block | `voice-en-asr-wall` | C34 |
| R15 | `date:` differs phone vs Mac near midnight | one rule | export diff | C64 |
| R16 | append to a polished note is invisible (writes raw only) | appended text shown + re-polished | `voice-en-append-after-polish` | C152 |
| R17 | un-rated note still polished by the Mac | queue drops it, exports stop | `voice-en-rated-then-unrated` | C88 |
| R18 | purge leaves the polish row; Mac keeps an orphan row | row + assets gone; orphan row trashed | purge test | C157 |
| R19 | photo offsets after a call pile at the end | offsets follow the recording clock | `pic-after-interruption` | C149 |
| R20 | re-filing Idea → Personal leaves the file in the archive | old file removed when ours | `dest-idea` re-filed | C163 |
| R21 | rename a person: Mac rows and vault files keep `[[Old]]` | rewritten everywhere we own | rename golden | C159 |
| R22 | only the first text of a mixed share survives; caption dropped on photo+caption | all texts, in order | ingress P3, P9-caption | C125, C141 |
| R23 | a kill during the share drain loses the clips | entry deleted only after save | drainer kill test | C147 |
| R24 | AirDrop / Files import skip the sheet and the filename date | same sheet, same date ladder | AirDropped Signal `.aac` | C145 |
| R25 | stale name offsets after the one-time body normalisation | re-sanitised once | migrated corpus notes | C10, D4 |
| R26 | the prod prompt override shadows the shipped prompt | one prompt source | prompt-source test | C39 |
| R27 | the paragraph ledger on a wall shows `shipped < in` | `shipped ≥ in` on every corpus wall | `typed-wall-7k`, `voice-en-asr-wall` | C34 |
| R28 | `names.json` millisecond tie always favours remote; write-back LWW has no skew tolerance | deterministic tie, ±5 s skew | merge tests | C208 |
| R29 | the sweep faults every blob on an unchanged store | 0 blob fetches on an unchanged corpus | sweep instrumentation | C45 |
| R30 | stale `**Name:**` turn markers baked into monologues; phone parser not pipe-aware; `*` in a speaker name breaks the Mac regex | a monologue never carries turn markers; one parser on both apps | `conv-*`, a `*`-named speaker fixture | C23, C115 |
| R31 | conversation-turn and annotation edits don't bump `editedAt` | every content edit is a touch | corpus edit scenarios | C89 |
| R32 | open-in ignores `.ogg/.oga/.m4b/.pdf` | same acceptance as the share sheet | ingress P12 | C199 |
| R33 | a mixed bundle's picture marker lands mid-transcript | own paragraph at the C12 spot | ingress P3 | C12 |
Pre-registered as IDENTICAL (unchanged on purpose): `goo.gl` plain card; silent video → `.failed` "no audio track"; purge before the first frame; the duration chip on synced notes; old PDF captures never sync their document; the domain as title on a title-less page (R10).

Outside the targets, fixed in v1 now, not waited on: D4 lost recording (C99), semantic
search silent empty (C110), Mac search jump (C111), audiobook edit-sync / seek-persist /
cover colour (BUGS §2).

Pre-registered as IDENTICAL (already fixed; a v2 change here is a regression): the twelve
items under "Already fixed" in `plan/extraction/bugs-preregistered.md`.

---

## Open decisions — the sitting (numbered; each with my proposed default)

Blocking the first rewrite target (body/image + copy-edit):

(The 50 traced scenarios behind the newer items: `plan/extraction/scenarios.md`; the
corpus and ingress fixtures they call for are listed at its end and are queue items, not
spec.)

1. **D1 Picture = its own paragraph, enforced at write** (C10). ✅ DECIDED 2026-09-22: yes.
2. **D2 A picture with no moment** (C12). ✅ DECIDED 2026-09-22: keeps its place in the share
   sequence; editor insert at the cursor; a lone picture or video frame at the TOP.
3. **D3 Where a picture goes inside a list item / quote / conversation turn.** ✅ DECIDED
   2026-09-22: after the item / after the quote block / after the sentence within the turn.
4. **D4 Old notes.** ✅ DECIDED 2026-09-22: normalised once at first open on any device, name
   offsets re-derived once; old test image-captures and pre-build-76 PDF captures stay as-is.
5. **D5 Paragraph gap for speech.** ✅ DECIDED 2026-09-22: 2.0 s on BOTH devices ("make them
   both 2s") — reverses the phone's 0.65 s from ROUND 10/11.
6. **D6 ONE title ladder** for both apps (C25). ✅ DECIDED 2026-09-22: user title → suggested →
   first line.
7. **D7 A typed note pasted as one wall.** ✅ DECIDED 2026-09-22: never re-paragraphed — the
   pause rule needs word times (speech only), and the copy-edit's sentence-count fallback
   stays off typed text. "how would typed text get paragraphed as there is no speech data?"
8. **D8 Dutch copy-edit** near-echoes. ✅ DECIDED 2026-09-22: accept for v2; paragraphs by C34;
   prompt bench later.
9. **D9 The prod prompt override.** ✅ DECIDED 2026-09-22: migrate it away, one prompt source.
10. **D10 Locked notes and polish.** ✅ DECIDED 2026-09-22: a locked note IS processed ("locked
    can be processed no? it's just that no one should see it"); never exported, never shown
    without auth; sync continues. = today's behaviour.

Blocking targets 3 and 4 (reconcile + export):

11. **D11 Vault folder model.** ✅ DECIDED 2026-09-22: keep `VaultLayout.home` as coded (C192);
    a pick not named Skrift and not containing one gets `<pick>/Skrift`; fixed media
    subfolders; his `0 Inbox/Skrift` never nests a second Skrift.
12. **D12 Frontmatter keys still "to add".** ✅ DECIDED 2026-09-22: add `duration` and the
    created date; skip lat/lon (raw coordinates) and the reminder.
13. **D13 `date:` timezone rule.** ✅ DECIDED 2026-09-22: the recording's local day everywhere.
14. **D14 YouTube link.** ✅ DECIDED 2026-09-22: card only. Fetching the audio is NOT built —
    it means scraping the player and breaks whenever YouTube changes ("broken features suck");
    the reliable route stays: download the audio yourself, drop the file on Skrift.
15. **D15 Instagram / TikTok.** ✅ DECIDED 2026-09-22: card + the caption as body when the page
    gives one; never a login-walled fetch.
16. **D16 A URL shared as plain text.** ✅ DECIDED 2026-09-22: a link capture.
17. **D17 Image shares.** ✅ DECIDED 2026-09-22: PNG stays PNG; a GIF is KEPT as a GIF (Obsidian
    animates it), the app shows its first frame; no re-encoding to JPEG.
18. **D18 Apple Notes import date.** ✅ DECIDED 2026-09-22: "it has to be the creation date" —
    taken from the note when the export carries one; otherwise the note is marked date-unknown
    (never silently the import time). Which exporter he uses is checked at build time.
19. **D19 Mac drops of PDF / image / URL / ePub / flac.** ✅ DECIDED 2026-09-22: "mac and phone
    and ipad should all be able to import the same things. make that a shared thing" — ONE
    shared import layer (C238); the Mac accepts everything the phone accepts.
20. **D20 Name links per device.** ✅ DECIDED 2026-09-22: "name sync everywhere" — the per-note
    picks are honoured on every device; one note exports the same links from each.
21. **D21 Mid-body blockquotes.** ✅ DECIDED 2026-09-22: a name inside any quote block is never
    linked.
22. **D22 A text-file share with no comment.** ✅ DECIDED 2026-09-22: the file's text is the body.
23. **D23 Case-variant duplicate tags.** ✅ DECIDED 2026-09-22: fold to the first spelling. And:
    "the tags need to be revamped. the UI is annoying to use" → C241.
24. **D24 Offline conflict.** ✅ DECIDED 2026-09-22: NOT silent. When the same note was edited on
    two devices before they synced, the app shows a conflict and lets him choose which version
    to keep (Shapr3D's model — "look it up"); the version not chosen stays recoverable, never
    silently lost. New notes never conflict. → C242.
25. **D25 Shares default to rating 0.** ✅ DECIDED 2026-09-22: stays; the rating is consent.

Not blocking v2, but he asked for one sitting:

26. **D26 Recording durability** (D4, issue #14). ✅ DECIDED 2026-09-22: all three, fixed in v1
    now — and the bar is absolute: "when I get a phone call the recording is lost. I want to
    never ever ever lose a recording mid recording." A phone call is the first test case.
27. **D27 Book-sharing branch.** ✅ DECIDED 2026-09-22: merge to main now; the two-device round
    stays owed.
28. **D28 What the app opens into.** ✅ DECIDED 2026-09-22: the list, the new-note action one
    tap away (C112).
29. **D29 State the two network calls** (weather, URL fetch) in-app / README. ✅ DECIDED
    2026-09-22: "yes, say so for sure".
30. **D30 Importance control.** ✅ DECIDED 2026-09-22: three balls (0.3 / 0.6 / 1.0), old values
    still bucket, no fourth button (the refine gate is gone). Mock first.
31. **D31 Multi-audio thread from WhatsApp.** ✅ DECIDED 2026-09-22: chooser stays, one note default.
32. **D32 Adding a person.** ✅ DECIDED 2026-09-22: A — automatic, all notes, once ("it would
    have to scan them all anyways"). Same tiers as normal linking; every link one tap to undo.
33. **D33 Podcasts → Books** node. ✅ DECIDED 2026-09-22: demote to planned — "we need to add
    that" — and see D90 on the Books tab itself.
34. **D34 Rival documents.** ✅ DECIDED 2026-09-22: `backlog.md`, `SKRIFT_SOURCE_OF_TRUTH.md`,
    `STANDALONE_PLAN.md`, `SHARE_INGEST_SURVEY.md`, `NAMING_MODEL.md`, `AUDIT_PLAN.md`,
    `AUDIT_FIX_TESTLIST.md`, `TESTFLIGHT_INSTALL_HANDOFF.md`, `JOURNAL_RETRIEVAL_PLAN.md` →
    `archive/`; `FEATURES.md` + `BUGS.md` stay until v2 lands; `CLAUDE.md` + README repointed.
    Done at the end of the sitting, readers grepped first.

35. **D35 Per-message times in a merged messenger note.** ✅ DECIDED 2026-09-22: hidden (kept
    in the manifest); the note's date = the first message's sent time.
36. **D36 Same file shared twice.** ✅ DECIDED 2026-09-22: one note + an "already in Skrift" notice.
37. **D37 Chat-export zip import** (WhatsApp/Signal "Export chat"): the only way to get sender
    names and exact order automatically. Default: parked; the share-sheet name field (C123)
    covers the common case.
38. **D38 Is Skrift's copy-edit "cleaned" by the archive's rule?** ✅ DECIDED 2026-09-22: YES —
    "the way the copy edit does it is the right one. removing fillers and shit is good". Archive
    notes get the normal copy-edit as `voice: cleaned`; the archive README's grammar-only
    definition is to be loosened over there.
39. **D39 Archive filenames.** ✅ DECIDED 2026-09-22 (revised the same sitting): the note's title
    names the file, typed OR generated ("weird distinction — both should be allowed to be a
    title"); the timestamp only when there is no title at all. = today's behaviour; the
    archive docs' "title only once he said it" is to be relaxed over there.
40. **D40 Ideas back into Skrift** (i43). ✅ DECIDED 2026-09-22: not in v2; the archive reads
    Skrift's files, never the reverse.
41. **D41 `_inbox/Skrift/` or flat `_inbox/`.** ✅ DECIDED 2026-09-22: `_inbox/Skrift/` ("the
    readme is correct"); Skrift changes to write there — a required difference.

42. **D42 Retry a failed link fetch.** ✅ DECIDED 2026-09-22: retry, up to three times.
43. **D43 Email shares.** ✅ DECIDED 2026-09-22: yes.
44. **D44 Video for the archive.** ✅ DECIDED 2026-09-22: yes — the movie is a synced asset for
    Made/Idea/Inspiration notes only (cap ~200 MB); Personal videos stay discarded.
45. **D45 Long notes.** ✅ DECIDED 2026-09-22: copy-edit in blocks — split only at paragraph
    boundaries, up to ~1,500 words per block, a longer paragraph is its own block, each block
    under the same guards, re-joined in order.
46. **D46 Per-note transcription language.** ✅ DECIDED 2026-09-22: yes (it is a recognition
    MODE, English vs multilingual — Parakeet never translates); the note records its mode.
47. **D47 Take over another device's stuck transcription** after 30 min. ✅ DECIDED 2026-09-22: yes.
48. **D48 Sync health surface.** ✅ DECIDED 2026-09-22: yes.
49. **D49 Trash and the vault file.** ✅ DECIDED 2026-09-22: leave it and say so; Delete Now
    offers removal when ours and untouched.
50. **D50 Fix a word inside a captured quote.** ✅ DECIDED 2026-09-22: yes — for a misheard
    word in the quote's transcription.
51. **D51 Reminders on several devices.** ✅ DECIDED 2026-09-22: first acknowledgement clears the rest.

From the coverage audit (spec-coverage.md §B) — smaller, mostly engineering, defaults proposed:

52. **D52 The refine pass** at ≥ 0.8. ✅ DECIDED 2026-09-22: DROPPED. It was never a model pass —
    "it is me going over it before I am allowed to export, to force me to pay attention. But
    let's remove that friction." The spec's earlier description was wrong.
53. **D53 Truncation fallback path**: iPad returns the marker-stripped input into the escrow, the
    Mac returns the original body. Default: the original body on both.
54. **D54 Picture reinsert by paragraph index** (C30) or by sentence index. Default: paragraph.
55. **D55 Mac export resolves images via the images directory, the phone via the manifest.**
    Default: manifest only, both apps.
56. **D56 `PipelineFile.significance` non-optional** (0 = unrated) once the floor is written back.
    Default: yes, in target 3.
57. **D57 Delete the dead `processEverything` toggle and the dead publish-gate legs.** Default: yes.
58. **D58 Mint the memo id first for Mac recordings** so the filename id equals the memo id.
    Default: yes.
59. **D59 Collapse the lenient desktop decoders** into one shared decoder with goldens first.
    Default: yes, target 3.
60. **D60 `names.json` tie rule**: deterministic by device id; write-back LWW tolerates ±5 s skew.
    Default: yes.
61. **D61 Does a PDF's extracted text go into the exported body?** Default: no, embed + ramble;
    text is search-only.
62. **D62 The share-out verbs** (markdown / PDF / plain / quote card) and batch export: keep
    outside the compiler rewrite. Default: keep; batch export owes a device look.
63. **D63 Split-note hybrid and per-book quote aggregation** are out of the v2 compiler. Default: out.
64. **D64 Auto-publish after Process on iPad/Mac.** Default: no; the Mac re-export sweep stays.
65. **D65 Obsidian profile keeps `source: capture-url` while the archive uses `capture:`.**
    Default: leave.
66. **D66 One-time adopt-by-content for pre-stamp legacy exports.** Default: no; re-export by hand.
67. **D67 Prod CloudKit schema deploy + Release App-ID capabilities**: at prod promotion after
    v2; Dev only until then. Default: yes.
68. **D68 Drop `Memo.syncStatus` and the Unsynced filter** (dead under CloudKit). Default: keep
    the field, remove the filter.
69. **D69 Video + link inside a multi-item WhatsApp bundle**: video = its own note, the link
    rides the note as a card. Default: yes.
70. **D70 Audio-only `.mp4` on the phone**: probe for a video track (Mac parity). Default: yes.
71. **D71 In-app voice-annotate on captures** (dictation model, unverified): captures only; the
    Mac maps the asset in target 3. Default: yes.
72. **D72 Video share keeps the typed thought.** Default: yes (built).
73. **D73 Capture-as-note** (annotation folded into the body, file/PDF as a body block): after
    body v2, mock first; body v2 leaves room for a file block. Default: yes.
74. **D74 On-device iPhone polish**: parked for v2 now the iPad polishes. Default: parked.
75. **D75 A memo-link FROM an unrated note holds a note off the fade clock.** Default: yes.
76. **D76 Auto-prune of unrated notes (i2)** is dead, absorbed by fading. Default: dead.
77. **D77 The phone's "People in this note" chip bar** while the Mac killed it: keep the
    asymmetry. Default: keep, stated.
78. **D78 Nicknames**: normalise to registered aliases only. Default: yes.
79. **D79 Re-export after a roster collision**: no; the next content change re-exports; log the
    count. Default: no.
80. **D80 Tag normalisation** ("filosofaties") out of scope. Default: out.
81. **D81 Five throwaway Dutch rambles recorded in Skrift Dev** for the corpus (synthetic
    content, real voice). Default: yes.
82. **D82 Summary prompt quality / context hints**: prompts frozen in v2, no sensor context.
    Default: frozen.
83. **D83 `BookBundle` packs a rejected alignment sidecar**: fix in v1 now. Default: yes.
84. **D84 Always-warm ASR engine**: intentional; measure battery once. Default: keep, measure.
85. **D85 Retire the XCUITest suite** (17 iOS-26 failures; the unit suite is the gate).
    Default: retire.
86. **D86 "AI READS THIS" also licenses a future in-app agent over `_ideas/`.** Default: yes.
87. **D87 Frontmatter migration is per-note** (old key order stays until re-exported): state
    it, or add a bulk re-export verb. Default: stated, no bulk verb.
88. **D88 Voice-enrolment floor**: the reports disagree (≥ 3 s / 32k samples = 2 s / ≥ 2 s).
    Default: 2 s (32,000 samples at 16 kHz); state one number.
89. **D89 Read-along `lead`**: 0.1 s (ledgers) vs 0.3 s (decisions). Default: whatever the
    device tune settles; state one number.

90. **D90 The Books tab.** Tuur 2026-09-22, with Hendri: "books is a weird tab, feels bolted on,
    which it is in a way. But there is a way to make it make sense." The app is an information
    capture tool; the player exists so quotes can be captured from what he listens to. Proposed
    frame: the tab is the things he captures FROM (books now, podcasts next), the player the
    means, not the point; rename accordingly; possibly fold into Notes as a source. Mock first.
    Open.

Parked ideas that are NOT decisions today (listed so the sitting can skip them): ramble
modes, monthly digest, vault-read direction, tightness lens, Obsidian plugin bundle,
commonplace book, folders model, watched-folder ingest, substitutions list, Backlink
Weaver, dictate-anywhere, Apple Watch, voice search, re-ingest of the Electron-era notes,
per-book quotes page (i16), ePub images in the reader, per-book language, cross-chapter
quotes, player polish P9b, unlinked-mention mining (i21), names → vocab auto-boost,
place-triggered resurfacing, query expansion / themes (i18), people pages (P7), Mac Names
parity (i6), scan-into-this-note, lasso multi-select, the wall-card design round, Mac
in-place linking, a `SkriftDesignKit` package, the Mac name-a-speaker review UI (owed after v2).

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
- No vCard → Names, no `.ics` meeting scaffold; Apple Books / Kindle quote shares parked.
- No video export to the vault; no bubble chrome on shared input; no 4-bit iPad model; no `Skrift/`
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
- 2026-09-22 Sitting round 7: adding a person re-links all notes automatically; failed link
  fetches retry; email shares; long notes copy-edited in paragraph blocks; per-note recognition
  mode; stuck transcriptions taken over; sync health shown; "Fix quote"; reminders clear on
  first acknowledgement; the two network calls stated openly.
- 2026-09-22 Sitting round 6 (partial): opens into the list; WhatsApp chooser stays; Podcasts
  node demoted, to be built; old state docs to archive/; same file twice = one note. The Books
  tab "feels bolted on" (Hendri) — reframe as the things he captures from, mock first (D90).
- 2026-09-22 Sitting round 5: archive files named by ANY title (generated too), timestamp only
  without one; name picks honoured on every device; no links inside quotes; a text file is
  the body; case-variant tags fold, and the tag UI gets a revamp; offline edit conflicts are
  SHOWN and chosen, never silent; shares stay unrated; a recording is never lost ("never ever
  ever"); book-sharing branch merges.
- 2026-09-22 Sitting round 4: archive files named by his title or a timestamp, never a model
  title; the refine pass (his own forced read-through) dropped — three importance balls, no
  fourth; YouTube = card only, no scraping ("broken features suck"); Instagram card + caption;
  a text URL is a link; GIFs kept as GIFs; Apple Notes dated by creation date or marked
  unknown; ALL THREE APPS IMPORT THE SAME THINGS through one shared layer, plus a twin audit
  and shared UI where possible.
- 2026-09-22 Sitting round 3: vault folder model as coded; `duration` + created date added to
  frontmatter, no coordinates; `date:` = local day everywhere; trash leaves the vault file;
  re-filing removes the old archive file when ours; renames happen in Obsidian. "I could
  actually make a second Obsidian vault for my projects" — yes: point Obsidian at the
  portfolio folder; it is Obsidian-openable by design, nothing to build.
- 2026-09-22 Sitting round 2: prompt override migrated; a locked note keeps processing ("it's
  just that no one should see it"); Skrift's copy-edit IS the archive's "cleaned" ("removing
  fillers and shit is good"); `_inbox/Skrift/` stands; no ideas back into Skrift in v2; the
  movie syncs for archive notes.
- 2026-09-22 Sitting round 1 (D1–D8): all defaults, except the paragraph pause is 2.0 s on
  both devices and typed text is never auto-paragraphed ("no speech data, no 2s rule").
- 2026-09-21 Quick note builds early, mock first; the editor rebuilds after the body v2 —
  "the note writing itself should be better. it's quite slow and clunky atm". Confirmed.
- 2026-09-21 Sender name on a messenger share: "can just be filled in on the share screen or
  later in the note itself" — a field, not a fetch.
- 2026-09-21 The archive contract is part of this spec: "Skrift and that one are growing
  towards each other here, so there is a tricky grey area" — the grey area is written down
  as C129–C139 and D38–D41, not guessed.
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
- 2026-08-11 The phone does not export (only processing devices do); 2026-08-18 the picked
  folder is the consent (Settings toggle + "Export now" deleted, b151); nothing on iOS
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
