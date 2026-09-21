# Core extraction — rules, invariants, inventory, data flow (v1 as of 2026-09-21)

Source: `Skrift_Native/` on branch `claude/skrift-v2-core-rewrite-564928`, worktree `code-audit-report-4816f4`. Paths below are relative to `Skrift_Native/`. Line numbers are v1 line numbers at extraction time.

Tags: `mechanical` = format/contract, no judgement · `locked` = a dated decision in a comment or a pinned test, keep wording · `needs-verdict` = intent unclear, comment contradicts code, or a "don't fix back" whose reason has moved.

---

## A) RULES

### Body/image model

**Marker syntax and placement**

- [mechanical] Photo marker literal is `[[img_NNN]]`, NNN zero-padded `%03d`, 1-based, numbering ascends by `offsetSeconds` — src: Shared/Pipeline/ImageMarkers.swift:40-52; Shared/Pipeline/BodyTransform.swift:204
- [mechanical] Marker N resolves to `imageManifest[N-1].filename`; the manifest is never pruned when a marker is deleted from the body (pruning would renumber every later marker on both apps) — src: SkriftMobile/Models/MemoDisplay.swift:104-107, 109-124; SkriftDesktop/Features/Review/NoteBody.swift:185-196
- [mechanical] Capture-time insertion: for each manifest entry, pick the word whose `start` is nearest `offsetSeconds`; insert `"\n\n[[img_NNN]]\n\n"` at that word's char END; words are located by sequential substring search from the last hit, else estimated proportionally (`totalLen * start / totalDuration`); insertions applied back-to-front — src: Shared/Pipeline/ImageMarkers.swift:13-61 (UTF-16 offsets throughout)
- [mechanical] `offsetSeconds` is recording time with paused time excluded; the entry is written at persist, manifest order = capture order — src: Shared/Model/MemoMetadata.swift:151-161; SkriftMobile/Features/Recording/MemoSaver.swift:774-790
- [mechanical] Share-captured photos and editor-inserted photos get `offsetSeconds: 0` (no timeline) — src: SkriftMobile/Services/Capture/CaptureInboxDrainer.swift:261, 450; SkriftMobile/Features/MemoDetail/NoteBodyView.swift:734
- [mechanical] Editor-inserted photo: file `photo_<memoID>_<NNN>.jpg` in recordings dir, NNN = manifest.count+1, attachment inserted as its own paragraph (`\n` + glyph + `\n`) at the pending caret, then commit — src: SkriftMobile/Features/MemoDetail/NoteBodyView.swift:722-749
- [mechanical] Share image capture appends one marker per photo to the annotation, joined by `\n\n`, AFTER any typed text — src: SkriftMobile/Services/Capture/CaptureInboxDrainer.swift:496-510
- [mechanical] Video import: one representative frame (`min(1.0, duration/2)`s) → `photo_<id>_001.jpg` at offset 0 → `[[img_001]]` lands at transcript start (both apps) — src: SkriftMobile/Features/Recording/MemoSaver.swift:366-375, 460-476; SkriftDesktop/Pipeline/Ingest/IngestService.swift:140-146, 296-320
- [mechanical] Diarization rebuilds the body from words (dropping markers) then re-inserts markers by timestamp via `ImageMarkers.insert` — src: SkriftMobile/Features/Recording/MemoSaver.swift:940-946
- [mechanical] ASR tail order is load-bearing: phantom guard → BPE merge → vocab rescore (+re-align) → word timings → markers last — src: Shared/Pipeline/ASRPostProcess.swift:3-15, 35-65
- [mechanical] Phantom guard: drop when text empty, or RMS < 0.0075 AND ≤3 words; RMS only computed for ≤3-word transcripts — src: Shared/Pipeline/BPEMerge.swift:75-93
- [locked] `Memo.transcriptMarkersInjected` "tells the Mac not to re-inject" (doc) — src: Shared/Model/Memo.swift:87-89; Shared/Pipeline/ImageMarkers.swift:3-6
- [needs-verdict] No Mac code reads `transcriptMarkersInjected` (only forwarded into the metadata blob); the Mac only injects when it runs its own ASR, which only happens for untrusted transcripts — the flag is dead on the Mac and the doc is stale. Its only live reader is the phone thumbnail rule — src: SkriftDesktop/Pipeline/Ingest/MemoCloudIngest.swift:251; SkriftMobile/Models/MemoDisplay.swift:138
- [needs-verdict] Marker width: `ImageMarkerReinsert`, `VaultExporter.convertImageMarkers`, `ObsidianPublisher.convertPhotoMarkers` match `\d{3}` only; `BodyTransform`, `MemoDisplay`, `SpeakerTurnsView` match `\d+`. The phone editor once emitted `[[img_1]]` (fixed) — old bodies with 1-digit markers render but neither copy-edit-reinsert nor export convert them — src: Shared/Pipeline/ImageMarkerReinsert.swift:12; SkriftDesktop/Pipeline/Export/VaultExporter.swift:217; SkriftMobile/Services/Export/ObsidianPublisher.swift:234; Shared/Pipeline/BodyTransform.swift:33; SkriftMobile/Features/MemoDetail/NoteBodyView.swift:1269-1271

**Raw ⇄ display transform (BodyTransform)**

- [mechanical] ONE regex tokenizes the raw body into pieces: `[[img_N]]` anywhere; `[[memo:UUID|Title]]` anywhere (36-char UUID, title has no `]`/`|`/newline); `- [ ]`/`- [x]`/`- [X]` only at line start, optional indent (indent stays text), must be followed by whitespace or EOL — src: Shared/Pipeline/BodyTransform.swift:28-69
- [mechanical] Every non-text piece collapses to exactly ONE display glyph (U+FFFC); text passes verbatim — src: Shared/Pipeline/BodyTransform.swift:12-13, 91-97
- [locked] (signed 2026-07-07, `mocks/accessory-bar-v2.html` §#11) Photos render as their own BLOCK: display-only `\n` before when the marker doesn't start a line, after when text continues on the line; these breaks exist only in display and are skipped on reconstruct — src: Shared/Pipeline/BodyTransform.swift:74-89; SkriftMobile/Features/MemoDetail/NoteBodyView.swift:251-254, 1276-1277
- [mechanical] `displayRange(forRaw:)`: subtract `(rawLength − displayLength)` for every piece ending before the range; nil when the range straddles a piece; batch form `displayRanges` shares one scan — src: Shared/Pipeline/BodyTransform.swift:99-146
- [mechanical] Raw task syntax reconstructs as `- [x]` / `- [ ]` exactly — src: Shared/Pipeline/BodyTransform.swift:72
- [mechanical] Phone reconstruct: a marker/task/chip attribute only emits syntax when the run IS the U+FFFC char; a display-only tag on typed text emits the text minus `\n`; an untagged attachment is dropped — src: SkriftMobile/Features/MemoDetail/NoteBodyView.swift:1255-1283
- [mechanical] Mac reconstruct (`modelString`): image attachment → `[[img_%03d]]`; memo chip → its stored literal; speaker gutter → the `**Name:**` literal verbatim; task box → raw task; else the text run — src: SkriftDesktop/Features/Review/BodyTextView.swift:1017-1036
- [mechanical] Mac attachment shifts for offset mapping: image = 11 chars → 1 (shift 10); memo chip = literal length − 1; gutter = literal length − 1; task box = 5 → 1 (shift 4) — src: SkriftDesktop/Features/Review/BodyTextView.swift:869-891
- [mechanical] Phone typing attributes strip the four custom keys on every caret move, so typed text never inherits marker/task/link/display-only tags — src: SkriftMobile/Features/MemoDetail/NoteBodyView.swift:770-809
- [mechanical] Phone commit is debounced (~1 s idle, end-editing, play, app-resign, teardown); the commit target (raw vs polished binding) is pinned at the FIRST dirty edit of a burst (P0 2026-07-10: a raw-born draft flushed into an arriving polish binding) — src: SkriftMobile/Features/MemoDetail/NoteBodyView.swift:201-220, 1041-1054, 1163-1194
- [mechanical] Every editor commit (phone) sets `transcriptUserEdited = true` and `transcriptStatus = .done` (non-empty), or `transcript = nil` when the body was cleared — src: SkriftMobile/Features/MemoDetail/NoteBodyView.swift:1182-1191
- [mechanical] Mac body edit writes into `sanitised` if non-nil, else `enhancedCopyedit` if non-nil, else `transcript`; then debounced Part-B write-back (1.5 s) — src: SkriftDesktop/Features/Review/NoteBody.swift:206-217; SkriftDesktop/App/MacCloudEditSync.swift:21, 35-60
- [mechanical] Mac re-render guard: re-render only when `modelString(tv) != text && modelString(tv) != snappedImageBody(text)` — src: SkriftDesktop/Features/Review/BodyTextView.swift:159-172
- [mechanical] Phone rebuild guard: skip when `t == loaded`, or first-responder/dirty; skip when `snapped(display) == reconstruct(attributedText)`; carry (clamped) selection across rebuilds — src: SkriftMobile/Features/MemoDetail/NoteBodyView.swift:317-346

**Photo snap (image-at-sentence-end)**

- [mechanical] `snapImages`: sentence terminators are `. ! ? …` and `\n`; a mid-sentence marker is deferred and flushed as `\n\n[[img_NNN]]\n\n` right after the first terminator of the sentence it interrupts; a marker already at a boundary (nothing before, or last non-ws char is a terminator, or immediately after another photo block) normalizes in place; trailing whitespace before a block is trimmed; the marker's wrapping newlines are healed; a marker glued between two word chars gets one space at the seam; task/memo-link tokens are opaque and copied — src: Shared/Pipeline/BodyTransform.swift:198-363
- [mechanical] Snap is idempotent; a no-image body returns unchanged; returns a segment map (`copy`/`insert`) so any raw location not inside a marker maps to the snapped text — src: Shared/Pipeline/BodyTransform.swift:156-197, 215-219; SkriftMobileTests/NoteBodyTests.swift:260-268, 291-307
- [locked] (2026-07-16, `PhotoBlockDisplayTests`) Both renderers AND the Obsidian export apply the snap so screen and vault agree; the stored raw keeps the marker at its recorded moment until a user edit — src: Shared/Pipeline/BodyTransform.swift:206-214; SkriftDesktop/Features/Review/BodyTextView.swift:430-438; SkriftDesktop/Pipeline/Export/VaultExporter.swift:123-132; SkriftMobile/Services/Export/ObsidianPublisher.swift:186-191
- [needs-verdict] An EDIT on the phone commits the SNAPPED form back into `Memo.transcript` (test pins `reconstruct == "…walked.\n\n[[img_001]]\n\n"`), so the marker's recorded position is lost on first edit; the doc says "edited/trusted notes carry it harmlessly" and the moment lives only in `offsetSeconds`. v2 question: make the snapped form the canonical stored body (then the snap remap + the snap-stable re-render guards disappear) — src: SkriftMobileTests/NoteBodyTests.swift:820-849; SkriftMobile/Features/MemoDetail/NoteBodyView.swift:326-331
- [mechanical] Three stacked offset remaps for name spans on a body with photos: (1) capture: `offsetSeconds` → char position (ImageMarkers.insert); (2) snap: raw offset → snapped offset (`SnapResult.snapped(rawRange:)`); (3) attachment collapse: snapped offset → storage offset (`displayRanges` on phone, `attachmentModelLocs` on Mac). Phone order: nameSpans over RAW → snap → displayRanges. Mac order: `ambiguousNames` offsets over `sanitised` → snap → attachment shift — src: SkriftMobile/Features/MemoDetail/NoteBodyView.swift:548-563; SkriftDesktop/Features/Review/BodyTextView.swift:842-867
- [mechanical] Stale-offset guard (Mac): a suggested span is dropped unless the storage text at the mapped range still starts with the alias (case-insensitive) — src: SkriftDesktop/Features/Review/BodyTextView.swift:860-864

**Paragraphs**

- [mechanical] `Paragrapher.paragraphed(transcript:words:)`: only `\n\n` is inserted; tokens preserved; `[[`-prefixed tokens pass through without consuming a timing; break before word i when the previous word ends a sentence (`. ? !`, tolerating closers `" ” ' ’ ) ] »`) AND (gap ≥ threshold OR paragraph already has `maxSentences`=4); text already containing `\n` passes through untouched; no timings → trimmed input — src: Shared/Pipeline/Paragrapher.swift:44-116, 135-140
- [locked] (Tuur ROUND 10/11, 2026-07-28) Phone default gap 0.65 s; Mac uses `longFormGap` 2.0 s for both the live join and the file pass — src: Shared/Pipeline/Paragrapher.swift:20-32; SkriftDesktop/Pipeline/BatchManager/BatchRunner.swift:51-62; SkriftMobile/Features/Recording/MemoSaver.swift:816-820
- [needs-verdict] Header says "a note paragraphs identically wherever it was transcribed", but the threshold differs by device (0.65 vs 2.0). v2: one constant, or a per-source constant carried on the memo?
- [mechanical] Filler strip (opt-in, default OFF, voice memos only, never captures/live caption): fixed EN/NL stoplist; drops text token + timing in lockstep; carries a dropped filler's terminator onto the previous word; all-filler transcript unchanged — src: SkriftMobile/Models/FillerFilter.swift:10-80

**Quote block (C1)**

- [mechanical] C1 shape: leading `> ` lines, blank line, ramble. `QuoteProtection.splitLeadingQuote` requires `>` at offset 0; the quote is byte-exact (no trailing newline); ramble = rest with leading blank lines dropped; `reassemble` = quote + `\n\n` + ramble (quote alone when ramble empty) — src: Shared/Naming/QuoteProtection.swift:26-41
- [mechanical] `CaptureQuote.split` (presentation) tolerates leading blanks/indent/bare `>`; `rawBlock` is byte-exact so `body(withRamble:)` round-trips; an emptied ramble leaves the quote (never an empty body) — src: Shared/Model/CaptureQuote.swift:72-108
- [locked] (2026-07-27) Quote styling is NOT gated on book metadata — the text alone makes a quote; only the attribution caption needs `bookTitle` — src: Shared/Model/CaptureQuote.swift:15-21; SkriftMobile/Models/MemoDisplay.swift:222-230
- [mechanical] Phone editor holds ONLY the ramble for a capture; commit re-prepends `rawBlock` verbatim — src: SkriftMobile/Features/MemoDetail/NoteBodyView.swift:275, 1176-1181
- [mechanical] Quote capture memo: `transcript = blockquote(quote)`, `transcriptStatus = .done`, `transcriptUserEdited = true` (Mac must not re-ASR), no location capture, phone writes no `[[..]]` and no attribution — src: SkriftMobile/Features/Recording/MemoSaver.swift:480-543

**Memo links, tasks, markdown**

- [mechanical] Raw memo-link syntax `[[memo:<UUID>|<title>]]`; title snapshot has `|` → space and `[[`/`]]` stripped, empty → `Untitled` — src: Shared/Model/MemoLinkSyntax.swift:14-26
- [mechanical] Backlinked notes = distinct ids in `[[memo:…]]` occurrences across live memos' `transcript` (phone also scans enhancement copyedits for the detail backlink list) — src: Shared/Pipeline/MemoLifecycle.swift:85-95; SkriftMobile/Features/MemoDetail/MemoDetailView.swift:1459-1482
- [mechanical] Chips show the target's LIVE title when a non-empty one resolves, else the snapshot; the raw payload always keeps the snapshot — src: SkriftMobile/Features/MemoDetail/NoteBodyView.swift:66-69, 1086-1099; SkriftDesktop/Features/Review/BodyTextView.swift:566-575
- [mechanical] Headings = `^#{1,6} .+$`; inline tags = `#[\p{L}\p{N}_][\p{L}\p{N}_\-/]*` after start/whitespace; characters stay verbatim — src: Shared/Pipeline/BodyMarkdown.swift:24-30
- [mechanical] Speaker turn header = `(?m)^[ \t]*\*\*([^*\n]+?):\*\*[ \t]*`; a conversation = ≥2 headers AND ≥2 distinct names; header `[[ ]]` stripped on parse — src: Shared/Pipeline/SpeakerTranscript.swift:34-55, 94-100
- [mechanical] Karaoke: raw body → word N is timing N (attachment glyphs are not words); polished body → `Karaoke.wordTimes` (AlignmentCore, `anchorN: 1`), rejected alignment → time-proportional sweep; a capture ramble's timings start at `spokenWordCount` of the quote — src: Shared/Pipeline/Karaoke.swift:17-38, 72-106; SkriftMobile/Features/MemoDetail/NoteBodyView.swift:405-437, 505-518; SkriftMobile/Features/MemoDetail/KaraokeMap.swift:11-59

**Title / display derivations**

- [mechanical] Derived title clip: 80 chars on a word boundary + `…`; NOT used for filenames — src: Shared/Model/NoteTitle.swift:18-35
- [mechanical] Phone display title: `title` → enhancement.title (clipped) → first non-empty transcript line with markers stripped → share-capture title → "Note"/"Voice note" — src: SkriftMobile/Models/MemoDisplay.swift:9-45
- [mechanical] Mac display title: `enhancedTitle` → first body line (img + memo markers stripped) → cleaned filename — src: SkriftDesktop/Features/Review/ReviewHelpers.swift:9-31
- [needs-verdict] The two title ladders differ (Mac has no chosen-vs-suggested split on the row; `MemoCloudUpdate` adopts a chosen `Memo.title` INTO `pf.enhancedTitle`, adopt-only). v2: one ladder over `memo.title` (chosen) + `enhancement.title` (suggested)? — src: SkriftDesktop/Pipeline/Ingest/MemoCloudUpdate.swift:82-97
- [mechanical] Row thumbnail = first marker in BODY order that resolves; markers injected but none survive → none; marker-less body: share capture → manifest[0]; empty body → manifest[0]; typed body → none — src: SkriftMobile/Models/MemoDisplay.swift:109-142

### Copy-edit (Mac polish)

**Model + prompts**

- [locked] (2026-08-12) Model `mlx-community/gemma-4-e4b-it-8bit` pinned to revision `4255b21bd9a9d3fc807ef7abd80373f5e3a52a73`; any other repo tracks `main`; requires mlx-swift-lm ≥ `e6e3de75` — src: Shared/Pipeline/PolishPrompts.swift:12-46
- [mechanical] Generation = one instruct turn `prompt + "\n\n" + text`, temperature 0, output trimmed; title cap 64 tokens, summary cap 256 — src: SkriftDesktop/Engines/EnhancementService.swift:129-150; SkriftMobile/Services/Polish/Engine/MLXPolishEngine.swift:129-133, 154-159, 222-230
- [mechanical] Copy-edit token budget = `min(8192, max(1024, estimatedTokens×3/2))`, `estimatedTokens = max(1, chars/4)` — src: Shared/Pipeline/PolishPrompts.swift:64-72
- [locked] (2026-08-18 "restored") The fixed 1024 cap cut long notes; budget is sized per input — src: Shared/Pipeline/PolishPrompts.swift:48-63
- [mechanical] Prompts are one LWW blob (copyEdit+summary+title) synced by `modifiedAt`; a fresh device with all-default + no stamp never mints a carrier; duplicate carriers collapse to newest; Mac settings overrides win locally — src: Shared/Pipeline/PolishPromptsSyncCore.swift:8-66; SkriftDesktop/Models/AppSettings.swift:120-132
- [mechanical] Prompt text (verbatim, contract): copy-edit "Clean up this transcript…Output only the cleaned text."; summary "1–3 sentences (30–60 words)…SAME language"; title "5–15 words…Return ONLY the title" — src: Shared/Pipeline/PolishPrompts.swift:138-171

**Escrow order and guards (both engines, must match byte-for-byte)**

- [mechanical] `copyEdit(transcript)`: if leading C1 quote → quote-only (empty ramble) returns transcript untouched WITHOUT calling the model; else edit ramble only, reassemble, byte-assert `leadingQuoteIntact`, any mismatch → return the whole unedited transcript — src: SkriftDesktop/Engines/EnhancementService.swift:63-79; SkriftMobile/Services/Polish/Engine/PolishEscrow.swift:19-34
- [mechanical] `editProse`: (1) memo-link escrow → plain titles; (2) image markers → anchors (≤6 words before, ≤6 after); model input = link-stripped text when no images, else marker-stripped; (3) run; (4) Mac only: `looksTruncated` → return unedited; `lostTooMuch` → return unedited; `ensureParagraphs`; (5) reinsert markers; (6) reattach links, nil → return unedited — src: SkriftDesktop/Engines/EnhancementService.swift:85-120; SkriftMobile/Services/Polish/Engine/PolishEscrow.swift:40-52; SkriftMobile/Services/Polish/Engine/MLXPolishEngine.swift:103-116
- [needs-verdict] On the iPad, truncation/shrink fallback returns `input` (the marker-stripped text) into the escrow, so markers are then re-inserted by anchors and links re-attached — on the Mac the fallback returns `text` (pre-escrow) directly. Same doctrine, different path; the iPad path can still lose a link if `reattach` fails on the raw input (it cannot — titles are intact — but the two are not identical code) — src: SkriftMobile/Services/Polish/Engine/MLXPolishEngine.swift:106-113 vs SkriftDesktop/Engines/EnhancementService.swift:94-101
- [mechanical] `looksTruncated`: `estimatedTokens(output) ≥ 95% of cap` — src: Shared/Pipeline/PolishPrompts.swift:130-136
- [mechanical] Shrink guard `lostTooMuch`: input > 40 words AND output words < 55% of input words — src: Shared/Pipeline/PolishPrompts.swift:117-128
- [locked] (2026-08-19, fx5 + Tuur's note at 53%) "Callers keep the unedited body — a raw note is honest, a bitten one is silent data loss" — src: Shared/Pipeline/PolishPrompts.swift:117-122
- [locked] (2026-08-19) `ensureParagraphs`: only when text > 600 chars AND fewer than 2 `\n`; split on `.!?` followed by space/end; needs > 4 sentences; group at 4 sentences or ≥600 chars; applied to model OUTPUT only, before marker reinsert; already-paragraphed text untouched — src: Shared/Pipeline/PolishPrompts.swift:74-115
- [locked] (Tuur 2026-08-20, "probably because there's a picture") `tidyWhitespace` must keep newlines: horizontal runs → one space, no spaces hugging a break, ≥3 breaks → one blank line, trim ends — src: Shared/Pipeline/ImageMarkerReinsert.swift:134-153; SkriftDesktopTests/ImageMarkerReinsertTests.swift:21-51
- [mechanical] Marker reinsert: per marker in order, try "before" anchor (longest suffix ≥4 chars, case-insensitive find from `minPos`, then jump to the next `[.!?]\s`), else "after" anchor (longest prefix, snap back to last `. `/`! `/`? `), else proportional `(i+1)/(n+1)·len` snapped back ≤80 chars to a `. `; positions monotonic (`minPos`); insert `\n\n[[img_NNN]]\n\n` back-to-front — src: Shared/Pipeline/ImageMarkerReinsert.swift:42-118
- [needs-verdict] After reinsert the display/export snap moves the marker to the sentence end anyway; anchors decide only WHICH sentence. v2 could reinsert by sentence index (count sentences before the marker in the input, place after the same-index sentence in the output) and drop the 6-word anchor machinery.
- [mechanical] Link reattach: each escrowed title is re-wrapped around its first case-insensitive occurrence after the previous link; the surface form is kept in the chip; a missing title → nil — src: Shared/Model/MemoLinkSyntax.swift:52-81
- [locked] "a lost link is worse than lost polish" — whole body falls back to unedited — src: Shared/Model/MemoLinkSyntax.swift:62-65; SkriftMobileTests/IPadPolishTests.swift:62-73
- [mechanical] Title + summary read the link-escrowed transcript (markers left in) — src: SkriftDesktop/Engines/EnhancementService.swift:129-139; SkriftMobile/Services/Polish/Engine/PolishEscrow.swift:56-58

**BatchRunner (Mac orchestration)**

- [mechanical] Captures (`sourceType == .capture`) never transcribe/diarize; enhancement-lite = title + summary + tags + name-link, NO copy-edit; empty annotation skips all LLM steps and titles from `urlTitle` → first 8 words of text (+`…`) → image filename → "Capture"; a preset title wins — src: SkriftDesktop/Pipeline/BatchManager/BatchRunner.swift:33-39, 214-265
- [mechanical] Transcribe only when `transcribeStatus != .done`; Mac ASR output is paragraphed with `longFormGap`; word timings persisted — src: SkriftDesktop/Pipeline/BatchManager/BatchRunner.swift:47-67
- [locked] (user 2026-06-15) Conversation mode default OFF; auto-diarize only when explicitly on, only for Mac-transcribed audio not already attributed, ≥2 speakers — src: SkriftDesktop/Models/AppSettings.swift:39-50; SkriftDesktop/Pipeline/BatchManager/BatchRunner.swift:69-96
- [mechanical] `stopAfterTranscribe` (a Mac RECORDING): return after transcription; `enhanceStatus` stays pending — src: SkriftDesktop/Pipeline/BatchManager/BatchRunner.swift:25-31, 99-101
- [mechanical] Empty transcript → `enhanceStatus = .done`, nothing else written — src: SkriftDesktop/Pipeline/BatchManager/BatchRunner.swift:103-107
- [mechanical] A speaker-attributed AUDIO transcript skips copy-edit (copyedit = transcript); notes/captures always take the monologue path — src: SkriftDesktop/Pipeline/BatchManager/BatchRunner.swift:124-137
- [mechanical] Outer quote byte-assert after the enhancer: mismatch → copyedit = transcript — src: SkriftDesktop/Pipeline/BatchManager/BatchRunner.swift:138-146
- [mechanical] Mid-run edit guard: snapshot `sanitised ?? enhancedCopyedit ?? transcript`; if it changed after copy-edit or after summary, discard the run and set `enhanceStatus = .pending` — src: SkriftDesktop/Pipeline/BatchManager/BatchRunner.swift:110-120, 147-155, 168-174
- [mechanical] `titleSuggested` = LLM title always; `enhancedTitle` filled only when empty (preset/phone title preserved) — src: SkriftDesktop/Pipeline/BatchManager/BatchRunner.swift:156-161
- [locked] (user 2026-06-15) Summary skipped when transcript word count < `summaryMinWords` (default 75); manual Redo ignores the threshold — src: SkriftDesktop/Pipeline/BatchManager/BatchRunner.swift:162-167; SkriftDesktop/Models/AppSettings.swift:52-55; SkriftMobile/Services/Polish/Engine/PolishEscrow.swift:60-67
- [mechanical] Deterministic steps run on `working = copyedit.isEmpty ? transcript : copyedit`: tags via `TagMatcher.suggest` (conversation: over flattened bodies), then name-link (conversation → `processConversation`, else `process`) with `unlinkedNames`/`namePicks`; `sanitised`, `ambiguousNames`, `enhanceStatus = .done`, `compiledText` — src: SkriftDesktop/Pipeline/BatchManager/BatchRunner.swift:177-206
- [mechanical] TagMatcher: whitelist tags matched with `minOccurrences` 2, max 10 matched + 5 spoken `#hashtags` — src: Shared/Pipeline/Tags/TagMatcher.swift:18-24
- [mechanical] Process queue = `deletedAt == nil && enhanceStatus != .done && !isUnratedLocalRecording`, oldest `uploadedAt` first, one run at a time; models unload after 60 s idle — src: SkriftDesktop/Pipeline/WayOutRules.swift:102-104; SkriftDesktop/Features/Shell/ProcessingCoordinator.swift:93-100, 42-43
- [mechanical] Interrupted runs (`.processing` at launch) reset to `.pending` — src: SkriftDesktop/Pipeline/BatchManager/RunReconciler.swift:9-20
- [mechanical] Redo title → adopt fresh title; redo copy-edit → re-link + recompile; redo summary; all recompile + write back — src: SkriftDesktop/Features/Shell/ProcessingCoordinator.swift:415-480
- [mechanical] Retranscribe clears transcript, timings, diarization (+sidecar), sanitised, ambiguousNames, copyedit, summary, titleSuggested, compiledText; keeps `enhancedTitle` — src: SkriftDesktop/Features/Shell/ProcessingCoordinator.swift:366-386

**iPad polish (PolishCenter)**

- [mechanical] Device gate: iPad only, ≥6 GB RAM, never simulator — src: SkriftMobile/Services/Polish/PolishCenter.swift:62-77
- [locked] (2026-08-14) ONE note polishes at a time device-wide (`busyMemoID`) — src: SkriftMobile/Services/Polish/PolishCenter.swift:149-159, 226-233
- [locked] "Pressing Polish IS a judgment": an unrated memo is floored to 0.1 before the run — src: SkriftMobile/Services/Polish/PolishCenter.swift:163-175
- [mechanical] Write = reuse the memo's enhancement row or create one; set copyedit/title/summary, `enhancedByDeviceID`, `enhancedAt = now`, `processedAt = now` — src: SkriftMobile/Services/Polish/PolishCenter.swift:361-380
- [mechanical] Redo writes only the one part and re-stamps device/enhancedAt; refused when the row vanished — src: SkriftMobile/Services/Polish/PolishCenter.swift:182-222
- [locked] (Tuur 2026-07-23) No auto-polish on open; the iPad polishes only on the visible verb — src: SkriftMobile/Services/Polish/PolishCenter.swift:300-302
- [mechanical] Canonical polished content for display/export: `hasContent` = any of the three non-blank; `isProcessed` = `processedAt != nil` OR all three non-blank — src: Shared/Model/MemoEnhancement.swift:55-82
- [locked] (2026-08-26) "Processed is processed, whichever device ran it"; a pass that produced nothing still records a row (`passRan`) — src: Shared/Pipeline/NoteWorkState.swift:3-14; SkriftDesktop/Pipeline/Ingest/MacCloudWriteBack.swift:73-77, 92, 111
- [mechanical] Phone body/karaoke/linking act on `enhancement.copyedit` when `hasContent`, only for a monologue non-capture (captures keep the quote block, conversations route to turns) — src: SkriftMobile/Features/MemoDetail/MemoDetailView.swift:1721-1733
- [mechanical] Phone edit of a polished body writes `enhancement.copyedit` and re-stamps `enhancedByDeviceID`/`enhancedAt` — src: SkriftMobile/Features/MemoDetail/MemoDetailView.swift:1735-1748

### Reconcile sweep

**Triggers and scope**

- [mechanical] Sweep runs on Mac launch, app-active, and after a successful CloudKit import event, coalesced 1 s; reads memos through a FRESH `ModelContext` (mainContext returns stale rows) — src: SkriftDesktop/App/MemoCloudReconciler+Wiring.swift:33-71, 97-103
- [locked] (2026-07-26) `cloudKitMacSyncEnabled` defaults ON (nil → true); an explicit false is honoured; nine subsystems gate on it — src: SkriftDesktop/Models/AppSettings.swift:99-106
- [mechanical] Order per reconcile: names sync → vocab sync → prompts sync → memo sweep → post notification → save + re-export updated rows → `MacMemoAuthor.backfill` → `reflectTranscripts` → connections index sweep — src: SkriftDesktop/App/MemoCloudReconciler+Wiring.swift:78-153
- [mechanical] Sweep collapses same-id rows to the keeper first (`MemoDuplicates.canonicalRows`); one local fetch + one enhancement fetch up front; asset rows fetched lazily per memo only when needed — src: SkriftDesktop/Pipeline/Ingest/MemoCloudReconciler.swift:53-87
- [mechanical] Keeper rule (shared): alive beats trashed → most content (`transcript+annotation+title` length) → latest `lastEditedAt` → first — src: Shared/Pipeline/MemoDuplicates.swift:13-41
- [locked] (P0 lesson, 2026-07-12) Content-diverging same-id rows are never auto-healed; only exact clones (same transcript/annotation/title/audioFilename, recordedAt within 1 s) are trashed by the phone, blob refs detached first — src: Shared/Pipeline/MemoDuplicates.swift:3-26; SkriftMobile/Services/MemoDeduper.swift:3-40
- [mechanical] Row match = local row by memo-UUID id, else by `audioFilename` — but the filename arm may not claim a row already owned by another memo (audiobook capture inheriting the source memo's filename) — src: SkriftDesktop/Pipeline/Ingest/MemoCloudReconciler.swift:73-101; MemoCloudIngest.swift:110-120

**Ingest (first contact)**

- [mechanical] Skip when `deletedAt != nil`; skip when unrated unless `processEverything`; skip when already ingested — src: SkriftDesktop/Pipeline/Ingest/MemoCloudIngest.swift:36-45
- [mechanical] Ingest synthesizes the phone's multipart parts (metadata JSON, audio, transcript when `.done` and non-empty, wordTimings, diar, images sorted by filename, document) and runs `UploadService.ingest` with `memoID = memo.id`; `syncedSourceEditedAt` baselined to `memo.lastEditedAt`; OCR text mirrored; `MirroredNoteFields.adopt` for tags/significance/destination/locked/remindAt — src: SkriftDesktop/Pipeline/Ingest/MemoCloudIngest.swift:47-63, 125-171
- [mechanical] Metadata JSON = raw `metadataData` overlaid with `source:"mobile"`, `tags`, `recordedAt` (ISO), `duration` (seconds number), `transcriptUserEdited`, `transcriptMarkersInjected`, `transcriptConfidence`, `title` (non-empty), `significance` (>0 only), `annotationText`, nested `sharedContent`; `.sortedKeys` for byte determinism — src: SkriftDesktop/Pipeline/Ingest/MemoCloudIngest.swift:239-270
- [mechanical] Trust gate: `transcriptUserEdited || confidence ≥ 0.7`; untrusted → transcript dropped, `transcribeStatus = .pending` (Mac re-ASRs); sidecars honoured only when trusted — src: Shared/Model/Memo.swift:340-350; SkriftDesktop/Pipeline/Ingest/UploadService.swift:76, 179-197, 324-329
- [mechanical] Branching in `prepare`: audio parts → `.audio` rows (video container → audio extracted); no audio + `sharedContent` → `.capture` (annotation = transcript, `.done`, `capture_<id>` folder, images under `images/`, document under `files/`); no audio + `textOnly` + memoID → `.note` row (`<id>_note/original.md`, `mediaSource` from blob); else nothing — src: SkriftDesktop/Pipeline/Ingest/UploadService.swift:70-123, 203-293
- [locked] (2026-08-19 rate→row hole) `textOnly` is the caller's answer, never sniffed from parts: a voice memo whose audio blob hasn't synced must NOT become a text row (it would strand its audio forever) — src: SkriftDesktop/Pipeline/Ingest/UploadService.swift:94-113; MemoCloudIngest.swift:66-84
- [mechanical] `PipelineFile.uploadedAt` = phone `recordedAt` (content date), not ingest time — src: SkriftDesktop/Pipeline/Ingest/UploadService.swift:155-160
- [mechanical] Capture folder = `pf.path`; audio/note working folder = parent of `pf.path`; `images/` + `image_manifest.json` live there — src: SkriftDesktop/Models/PipelineFile.swift:366-374; UploadService.swift:331-344
- [mechanical] Stranded = rated, live memo with no row after a sweep; counted + logged as an error, must be 0 — src: SkriftDesktop/Pipeline/Ingest/MemoCloudReconciler.swift:27-36, 157-166; WayOutRules.swift:47-71

**Update (phone → Mac, existing row)**

- [locked] (user call) A phone edit re-links + recompiles only — NO LLM re-run — src: SkriftDesktop/Pipeline/Ingest/MemoCloudUpdate.swift:9-11
- [mechanical] Decisions are CONTENT-compared, never timestamp-gated; `syncedSourceEditedAt` is informational only — src: SkriftDesktop/Pipeline/Ingest/MemoCloudUpdate.swift:17-23, 67-71
- [mechanical] Trash mirror: reflect `memo.deletedAt` onto the row only when it differs from `syncedSourceDeletedAt` (watermark); a trashed memo mirrors trash and returns (no text reflect) — src: SkriftDesktop/Pipeline/Ingest/MemoCloudUpdate.swift:40-57
- [mechanical] Echo guard: an enhancement authored by THIS device is ignored, EXCEPT on a fresh row (`isFreshRow`) where it is the only copy of the polish — src: SkriftDesktop/Pipeline/Ingest/MemoCloudUpdate.swift:30-36, 59-65; MemoCloudReconciler.swift:139-150
- [mechanical] Path 2: adopt phone enhancement copyedit (always), title/summary (non-empty only); Path 2b: adopt a non-empty `Memo.title` into `enhancedTitle`, never clear on nil/blank; Path 3: adopt `memo.transcript` when different; metadata blob refresh on byte change; mirrored fields via `MirroredNoteFields.pull`; OCR text — src: SkriftDesktop/Pipeline/Ingest/MemoCloudUpdate.swift:76-128
- [mechanical] Recompile (re-link over `enhancedCopyedit ?? transcript`, sanitiseStatus done, compiledText) only when a `recompiles` field or content changed; lock/reminder/OCR never recompile — src: SkriftDesktop/Pipeline/Ingest/MemoCloudUpdate.swift:130-163; MirroredNoteFields.swift:26-31, 104-118
- [mechanical] Mirrored fields: tags (pull/push/adopt-nonempty, recompiles), significance (pull; push only when non-nil; recompiles), destination (pull only, event push, recompiles), locked (pull), remindAt (pull) — src: SkriftDesktop/Pipeline/MirroredNoteFields.swift:55-119
- [locked] (2026-07-26 "did not go grey again") Un-rating is an EVENT (`setRating` writes 0); the passive mirror skips nil — src: SkriftDesktop/App/MacCloudMetaSync.swift:54-68; MirroredNoteFields.swift:82-92
- [mechanical] Late-asset heals (idempotent, guarded so the steady sweep faults no blobs): photos missing from `images/` + manifest filenames differ → write + rewrite manifest; wordTimings only when row has none and is `.done` with text; diarization likewise (+ `diar_<id>.json`) — src: SkriftDesktop/Pipeline/Ingest/MemoPhotoMaterializer.swift:23-70; MemoCloudIngest.swift:186-228
- [mechanical] Rows changed by a sweep are re-exported only if `exportStatus == .done && !locked && deletedAt == nil`; refusals are logged, not errors — src: SkriftDesktop/App/MemoCloudReconciler+Wiring.swift:158-188

**Write-back (Mac → phone)**

- [mechanical] Enhancement upsert: resolve the memo against the store (try `memoID(for:)`, filename UUID, row UUID); skip when nothing to write unless `passRan`; refuse to clobber a STRICTLY newer other-device row (`enhancedAt > now`); own earlier writes always updated; sets device/`enhancedAt`; `processedAt = now` only when `passRan` — src: SkriftDesktop/Pipeline/Ingest/MacCloudWriteBack.swift:43-53, 78-115
- [locked] (2026-07-28) A Mac RECORDING's filename UUID is the recorder's, not the memo's — `memoID(for:)` inverts the order for `isLocalRecording`; every writer should use `resolve` — src: SkriftDesktop/Pipeline/Ingest/MacCloudWriteBack.swift:15-42
- [needs-verdict] The naming heuristic exists only because a Mac recording's file UUID ≠ memo UUID. v2: mint the memo id first and name the file `memo_<memoID>` so `resolve` collapses to one lookup.
- [mechanical] Live edit write-back is debounced 1.5 s, sends `unlinkToSpoken(bestBodyText)` as `bodyOverride`, never `passRan`; a projection (no modelContext) never goes through this carrier — src: SkriftDesktop/App/MacCloudEditSync.swift:21-60
- [mechanical] Post-process write-back requires `enhanceStatus == .done`, sync enabled, container; passes `passRan: true` — src: SkriftDesktop/Features/Shell/ProcessingCoordinator.swift:274-291
- [mechanical] Meta mirror pushes tags + (non-nil) significance passively; rating/destination/title are event writes; no `lastEditedAt` bump on any Mac→phone meta write (echo-quiet) — src: SkriftDesktop/App/MacCloudMetaSync.swift:17-112
- [mechanical] Delete mirror: `memo.deletedAt = pf.deletedAt`; on a trash, `trashSeenAt = deletedAt`; permanent removal is device-local — src: SkriftDesktop/App/MacCloudDeleteSync.swift:5-44
- [mechanical] Mac authoring: a local UUID-id row with a real `path` and no memo gets a Memo (id = row id, `recordedAt = uploadedAt`, significance floor 0.1 unless `isLocalRecording`, audio asset when readable, Mac transcript `.done` with confidence 1.0); idempotent; `reflectTranscripts` fills an empty memo transcript only for this device's own memos and only from `.done` rows — src: SkriftDesktop/Pipeline/Ingest/MacMemoAuthor.swift:59-131, 148-157
- [locked] (Tuur 2026-07-28 "it shouldn't be. Because it's an unrated note") A Mac RECORDING stays unrated; an IMPORT floors to 0.1; `isLocalRecording` is stamped at construction because the sweep races arrival — src: SkriftDesktop/Pipeline/Ingest/MacMemoAuthor.swift:43-57; IngestService.swift:16-25; ArrivalPath.swift:66-71, 84-87
- [needs-verdict] `Memo.recordedAt ← pf.uploadedAt` and `pf.uploadedAt ← phone recordedAt`: `uploadedAt` is the content date on both paths. v2 should rename the field.
- [mechanical] Unrated notes are never `PipelineFile`s in the store; the Mac renders them through a transient projection (id = memo UUID, `significance = nil` when 0, transcribe `.done` iff memo `.done`, media materialised into Caches) and writes edits straight onto the Memo (title, transcript+`transcriptUserEdited`, tags, significance; content edits call `markEdited`) — src: SkriftDesktop/Pipeline/Ingest/MemoNoteProjection.swift:28-215
- [needs-verdict] Projection header says it "inherits the duration bug on purpose", but `PipelineFile.durationSeconds` now parses numeric seconds — the comment is stale — src: SkriftDesktop/Pipeline/Ingest/MemoNoteProjection.swift:20-27 vs SkriftDesktop/Models/PipelineFile.swift:325-364

**Phone-side sweeps that pair with the Mac sweep**

- [mechanical] `AssetMaterializer.run` on launch/foreground: write any asset blob whose file is missing (never overwrite), then capture assets for every memo incl. trashed (audio, manifest photos, `.file` document, `wt_<id>.json`, `diar_<id>.json`), refreshing when byte size differs — src: SkriftMobile/Services/AssetMaterializer.swift:28-136
- [mechanical] Recording device owns stuck-transcription recovery (`recordingDeviceID == current || nil`) — src: SkriftMobile/Features/Recording/MemoSaver.swift:856-880
- [mechanical] Sidecar filenames: `wt_<UUID>.json`, `diar_<UUID>.json`; photos `photo_<UUID>_NNN.jpg`; audio `memo_<UUID>.<ext>`; capture docs `file_<UUID>.<ext>`; dictation `dictation_<UUID>.m4a` — src: SkriftMobile/Services/WordTimingsStore.swift:11; SkriftMobile/Features/Recording/MemoSaver.swift:71, 779; CaptureInboxDrainer.swift:387, 434; CaptureDictation.swift:31

### Export compiler

**Body and frontmatter**

- [mechanical] Body precedence: `sanitised` → `enhancedCopyedit` → `transcript` (first non-blank); memo links rewritten to `[[stem|Title]]` when the resolver knows the stem (and it differs from the title), else `[[Title]]`; raw `[[memo:` never reaches the vault — src: Shared/Export/Compiler.swift:19-24; Shared/Model/MemoLinkSyntax.swift:83-102
- [mechanical] Frontmatter order (Obsidian profile): `---`, `title` (always double-quoted, `\`/`"` escaped), `date` (YYYY-MM-DD), `author`, `source`, [`book`, `bookAuthor`, `chapter`], [`url` for url captures], `summary` (quoted or bare key), `tags:` list, `people:` list, `significance` (`%.1f` or bare key), `location` (quoted placeName or bare key), `weather` `"cond, N°C"`, `pressure`, `pressureTrend`, `dayPeriod`, `daylight:{sunrise,sunset,hoursOfLight}`, `steps`, `lastTouched:` (blank, filled by the stamp), `---`, blank line — src: Shared/Export/Compiler.swift:69-182
- [locked] (Tuur 2026-08-14 "in a more sensible order") Frontmatter is grouped what-you-read / what-it's-about / where-you-were / Skrift bookkeeping last and together — src: Shared/Export/Compiler.swift:69-78
- [mechanical] `source:` values: `Audiobook-quote` (bookTitle present) → `Video` (`mediaSource == "video"`) → `Apple-Note` / `Voice-memo` / `capture-url|text|image|file|capture` — src: Shared/Export/Compiler.swift:46-67
- [mechanical] `people:` = distinct canonical link targets in reading order, alias-display resolved to the target, `[[img_NNN]]` excluded, `![[embeds]]` excluded, filtered to live known persons when `knownPeople` is supplied (nil = no filter) — src: Shared/Export/Compiler.swift:140-145, 273-289
- [mechanical] Numbers print without `.0` when whole (`fmtNum`) — src: Shared/Export/Compiler.swift:337-340
- [mechanical] Capture: shared block pinned above the body — url → `**title**` + url line; text → `> ` blockquote per line; image → `![[fileName]]` UNLESS the body already has `[[img_` markers — src: Shared/Export/Compiler.swift:184-187, 227-258
- [mechanical] Audiobook body (bookTitle present + leading C1 quote): each quote line → `> *text*` (no double-wrap), then `>` and `> — [[Author]], *Book*, ch. N` (author/chapter omitted when absent), blank line, ramble; the `[[Author]]` wikilink is written ONLY here — src: Shared/Export/Compiler.swift:189-223
- [mechanical] `date:` = `overrideDate` ?? first 10 chars of the metadata `recordedAt` ISO string (UTC) ?? "" — src: Shared/Export/Compiler.swift:35-38
- [needs-verdict] The phone passes `date:` from a LOCAL `yyyy-MM-dd` formatter; the Mac takes the UTC prefix of the ISO string. The same note exported near midnight from two devices carries a different `date:` line, which the stamp then reads as changed content (an `updated` write, not a refusal, but churn) — src: SkriftMobile/Services/Export/MemoExporter.swift:165-172, 33 vs Shared/Export/Compiler.swift:38

**Archive profile**

- [locked] (Tuur 2026-08-26) The destination is a PRIVACY BOUNDARY: one of four, never two; `idea`+`inspiration` meaningless; a stored field, not a tag; unknown raw → `.personal` — src: Shared/Model/NoteDestination.swift:3-26, 65-70; Shared/Model/Memo.swift:293-298
- [locked] (reversed 2026-08-27) Destination words ARE accepted as tags; an `inspiration` tag raises `needs: - credit` like the folder does — src: Shared/Model/Memo.swift:267-291; Shared/Export/Compiler.swift:123-133
- [locked] (Tuur 2026-08-26, "deliberate reversal of my privacy advice") Archive keeps PEOPLE links, plainifies places and memo links (alias-display keeps the spoken form; `![[embeds]]` untouched) — src: Shared/Export/ExportProfile.swift:47-52; Shared/Export/Compiler.swift:25-30, 291-316
- [locked] (2026-08-27) Archive drops `author:`, writes `capture:` instead of `source:`, never writes `type:` (the archive's category key), writes `voice: written|cleaned|raw`, `needs: - credit` only for inspiration (destination or tag), keeps `location:`, drops weather/pressure/dayPeriod/daylight/steps/significance — src: Shared/Export/Compiler.swift:85-134, 146-173; Shared/Export/ExportProfile.swift:43-45
- [mechanical] `voice` is set by each app, never derived in the Compiler: Mac `sourceType != .audio || path.isEmpty → written`, else copyedit blank → raw else cleaned; phone `audioFilename.isEmpty → written`, else enhancement with content → cleaned else raw — src: Shared/Export/CompilerInput.swift:90-94; SkriftDesktop/Pipeline/Export/CompilerBridge.swift:72-74; SkriftMobile/Services/Export/MemoExporter.swift:89-91
- [locked] (Tuur 2026-08-28 "we dont need the month either", "just the name is fine") Archive filename = slug of the title (ASCII-folded, lowercased, hyphenated, cap 120 cut at a word boundary unless the stub ≤12), fallback `yyyy-MM-dd-HHmmss` LOCAL; flat inside `_inbox|_ideas|_inspiration`; media BESIDE the note with the same basename; images as `![](name)` — src: Shared/Export/ExportProfile.swift:20-113; Shared/Export/VaultWrite.swift:338-356
- [mechanical] Archive disambiguation suffix `-<id8 lowercased>`; vault suffix ` <ID8>` — src: Shared/Export/VaultWrite.swift:139-144

**Vault layout, naming, stamp, write engine**

- [locked] (2026-08-14, `mocks/vault-folder-model.html`) Folder names are not configurable: home `Skrift/`, `Recordings/`, `Images/`, `Documents/`; home resolution: pick named `Skrift` → as-is; pick holds a `skriftID`-stamped `.md` → as-is; pick contains `Skrift/` → that; else `<pick>/Skrift` (created on first write only); archive profile returns the pick unchanged — src: Shared/Export/VaultLayout.swift:13-84
- [mechanical] Vault stem: title else filename stem; `/` `\` → `-`; strip `* " < > : | ? # ^ [ ]`; collapse double spaces; trim ` .`; empty → `note`; cap 120 — src: Shared/Export/VaultWrite.swift:104-130
- [locked] (2026-07-26, roadmap i14 — PUBLIC CONTRACT) Stamp keys `skriftID`, `skriftHash`, `lastTouched` (ISO internet datetime); hash = SHA-256 over every line except the `skriftHash` line; `apply` order: touched → id → empty hash → hash of result; only text starting with `---` is stamped; upsert replaces in place else inserts before the closing `---` — src: Shared/Export/VaultStamp.swift:1-83, 103-111, 199-215
- [mechanical] Standing: nil → absent; no readable stamp → foreign; hash matches → untouched; else userEdited; legacy tell = `lastTouched` key present with no `skriftID` — src: Shared/Export/VaultStamp.swift:56-68, 96-101, 156-159
- [mechanical] `contentEquivalent` ignores only the `skriftHash` and `lastTouched` lines — src: Shared/Export/VaultStamp.swift:113-124
- [mechanical] `assess`: ledger path exists → judge it; ledger path missing → `locate(id)` anywhere under root → `movedAway`, else drop the ledger entry and start over; then try `stem.md`, then the disambiguated stem: absent → proceed(create); ours untouched → proceed(update); ours edited → `backedOffUserEdited`; legacy → `blockedLegacy` (no suffix sidestep); foreign → try next; both taken → `blockedForeign` — src: Shared/Export/VaultWrite.swift:231-307
- [locked] (2026-08-28, Tuur deleted his test exports) MOVED ≠ DELETED: the stamp scan tells them apart; a deleted note is writable again — src: Shared/Export/VaultWrite.swift:242-252; Shared/Export/VaultStamp.swift:131-154
- [mechanical] `commit`: stamp → if `contentEquivalent` with the existing file → `unchanged` (no file, no assets, no ledger touch); else atomic + `NSFileCoordinator` write, ledger set, then assets (attachments → images folder, documents → documents folder, audio → audio folder; archive: beside the note); asset failures counted never fatal — src: Shared/Export/VaultWrite.swift:320-361, 369-413
- [mechanical] Ledger is per picked folder (`VaultIdentity.uuid(path)`), local-only, dumb (losing it costs convenience, never safety) — src: Shared/Export/VaultWrite.swift:27-100
- [locked] (Tuur 2026-08-28) Outcome copy is shared; refusals are sticky, `unchanged` never says "Exported" — src: Shared/Export/ExportOutcomeCopy.swift:1-69

**Mac exporter**

- [mechanical] Locked notes throw `lockedNote` before anything; no vault → `noVault`; profile/root follow the row's destination; id = row UUID or `VaultIdentity.uuid(pf.id)` for demo rows — src: SkriftDesktop/Pipeline/Export/VaultExporter.swift:74-98
- [mechanical] Order: assess → compile (people filtered to live roster, memo-link stems from the ledger first, else derived stem) → `snappedImageBody` → markers→`![[<stem>_NNN.ext]]` (files copied from `images/`) or legacy capture copy under original names → Apple-Note `(Attachments/x)` refs → `![[x]]` — audio when `includeAudioInExport && .audio && path exists` → archive-only source movie as a document — commit — src: SkriftDesktop/Pipeline/Export/VaultExporter.swift:99-189
- [needs-verdict] Mac marker→file resolution reads the `images/` DIRECTORY (`_NNN.` / `img_NNN` prefix / NNN-th sorted file), NOT `image_manifest.json`; the review body and the phone exporter resolve through the manifest. A twin that can disagree when filenames don't embed NNN — src: SkriftDesktop/Pipeline/Export/VaultExporter.swift:212-242 vs NoteBody.swift:188-196; SkriftMobile/Services/Export/ObsidianPublisher.swift:231-260
- [locked] (2026-08-28, Tuur "I may send a video… that is gold") The source movie is kept beside `original.m4a` (local disk, never a MemoAsset) and only the ARCHIVE export copies it — src: SkriftDesktop/Pipeline/Ingest/IngestService.swift:117-137; VaultExporter.swift:171-181
- [mechanical] Export success marks `exported`, `exportStatus = .done`, `lastActivityAt` only on created/updated/unchanged — src: SkriftDesktop/Features/Shell/ProcessingCoordinator.swift:321-344

**Phone exporter**

- [mechanical] `CompilerInput` mapping: body = enhancement copyedit (when `hasContent` and non-blank) else annotation (share capture) else transcript; re-linked on-device into `sanitised`; `transcript` keeps the base; title = enhancement title else `exportTitle`; summary from enhancement; `sourceType` capture/audio; `mediaSource` video; `voice` per rule above — src: SkriftMobile/Services/Export/MemoExporter.swift:63-93
- [mechanical] `exportTitle` = title → first non-empty line of the flattened linked body, hard `prefix(80)` (NOT `NoteTitle.clip`) → "Untitled Memo" — src: SkriftMobile/Services/Export/MemoExporter.swift:100-109; Shared/Model/NoteTitle.swift:15-17
- [mechanical] Publish order: profile/root by destination → security scope on the bookmarked root → `VaultLayout.home` → assess → memo-link stems (ledger first, else derived stem of the target's export title) → compile → snap → markers→embeds via the MANIFEST (dangling markers dropped, never printed) → cheap `contentEquivalent` pre-check before any blob fetch → commit with photo blobs + audio blob (`<stem>.<ext>` in Recordings) — src: SkriftMobile/Services/Export/ObsidianPublisher.swift:131-224
- [locked] (Tuur 2026-08-18) The picked folder IS the consent — no on/off switch; the old `skrift.publish.obsidianEnabled` key is deliberately unread — src: SkriftMobile/Services/Export/PublishCoordinator.swift:6-10, 56-59
- [locked] (Tuur 2026-07-26 "cant export either") Policy is RATED-ONLY, hard-coded; the stored `skrift.publish.policy` key is deliberately unread — src: SkriftMobile/Services/Export/PublishCoordinator.swift:62-67
- [locked] (Tuur 2026-08-11; 2026-08-26 `isProcessed` not `hasContent`) A vault note is a PROCESSED note: gate = folder configured (per destination) → not trashed → not locked → (paired rule) → rated → has body or title → `enhancement.isProcessed` — src: SkriftMobile/Services/Export/PublishCoordinator.swift:72-99
- [mechanical] `exportRefusal` mirrors `shouldPublish` gate-for-gate with user-facing text; nil iff it would publish — src: SkriftMobile/Services/Export/PublishCoordinator.swift:101-126
- [needs-verdict] `isMacPaired` is hard-wired false, `publishWhenPaired` reads a dead key, `.all` policy "survives only for the gate's tests" — three dead legs in the gate. Delete in v2?
- [needs-verdict] The phone exporter re-links names on-device (`MemoLinking` → shared Sanitiser, no per-note `nameResolutions` passed), while the phone's in-app tiers DO use `nameResolutions`; the Mac ignores `nameResolutionsData` entirely and links with its own `unlinkedNames`/`namePicks`. The same note can export with different links from each device — src: SkriftMobile/Services/Export/MemoLinking.swift:21-29; Shared/Model/Memo.swift:156-165; grep shows no Mac reader of `nameResolutionsData`

### Names & sanitise

- [mechanical] `names.json` schema (byte-compatible both apps): `{lastModifiedAt, people:[{canonical "[[Name]]", aliases[], short (always written, null when empty), voiceEmbeddings (omitted when empty), lastModifiedAt, deleted (only when true)}]}`; tolerant decode of legacy files without timestamps; pretty-printed + sorted keys on disk; sync carrier encodes sorted keys, unpretty — src: Shared/Naming/NamesData.swift:13-109; NamesStore.swift:20-53; NamesSyncCore.swift:32-36
- [mechanical] Merge = per-canonical LWW on `lastModifiedAt` string compare (ties → remote, empty local → remote), voiceEmbeddings UNIONED (dedup by vector) regardless of winner; tombstones win when newer; prune tombstones > 90 days — src: Shared/Naming/NamesData.swift:138-184; NamesStore.swift:227-245
- [mechanical] Smart bumps: an unchanged entry keeps its timestamp; removed live entries tombstone; voiceEmbeddings carried when the writer omits them — src: Shared/Naming/NamesStore.swift:55-107
- [locked] (NAMING_MODEL.md decision 4, opt-out + risk-tiered) First mention of a SAFE alias → `[[Canonical]]`(+possessive outside), later unambiguous mentions → short name (short override, else first word of canonical); FP-prone single tokens (stoplist or < 3 chars) and ambiguous aliases (2+ owners) are suggested, not linked; lowercase common words are not even suggested — src: Shared/Naming/Sanitiser.swift:3-26, 144-204, 492-538; NameStoplist.swift:16-53
- [mechanical] Existing `[[Name]]` or `[[Name|x]]` counts as the first mention; later existing links demote to the short; `[[img_NNN]]` and unknown links untouched — src: Shared/Naming/Sanitiser.swift:161-171, 563-574
- [mechanical] Non-prose skip: leading YAML block, leading C1 quote block, fenced/inline code, memo-link tokens — src: Shared/Naming/Sanitiser.swift:691-726
- [mechanical] `namePicks[alias] = "[[Canonical]]"` force-links (bypasses FP/ambiguity/prune); `""` silences; `neverLink` prunes a person (auto-link off, still suggested, dropped from ambiguity) — src: Shared/Naming/Sanitiser.swift:131-143, 42-129
- [mechanical] Conversation linking: merge consecutive same-speaker turns; first header → `[[Canonical]]`, later → short; inline first mention → `[[Canonical|short]]` (bare when short == canonical), rest → short; preamble preserved — src: Shared/Naming/Sanitiser.swift:328-490
- [mechanical] `unlinkToSpoken` → `process` round-trips (Mac live edits are sent un-linked to the spoken word) — src: Shared/Naming/Sanitiser.swift:656-679; SkriftDesktopTests/SanitiserTests.swift:28-35
- [mechanical] Compiled regexes are cached per alias; all offsets UTF-16 — src: Shared/Naming/Sanitiser.swift:743-756
- [mechanical] Roster seeding from `People/` note titles: full title + first token as aliases; idempotent; titles only, no body read — src: Shared/Naming/NamesStore.swift:181-215
- [locked] (NamingGoldenTests) The mock's tiering is pinned to exact output: two distinctive links, `jack` ambiguous (2 candidates), `rose` common-word (1 candidate), lowercase `will` nothing — src: SkriftDesktopTests/NamingGoldenTests.swift:20-45

### Consent / rating / lifecycle

- [locked] (2026-07-26, "the rating is CONSENT") Unrated changes exactly five things: fades, renders quiet, never processes, never exports, joins no connections; reading back (play, photos, karaoke, copy, search, edit) is normal — src: Shared/Pipeline/NoteConsent.swift:3-29
- [mechanical] Rated ⇔ `SignificanceScale.litCount(value) > 0`; nil and 0 unrated; grid 0/0.1…1.0 rounded; non-finite → 0; tiers `Passing`<4, `Useful`<7, `Important`≥7; refine wall step 8 — src: Shared/Model/SignificanceScale.swift:16-56; Shared/Pipeline/NoteConsent.swift:35-42
- [mechanical] File-channel nil: projection (no modelContext) → unrated; local recording → unrated; inserted import/legacy row → rated (0.1-floor authored) — src: SkriftDesktop/Pipeline/NoteConsent+PipelineFile.swift:23-27
- [needs-verdict] Three meanings of `PipelineFile.significance == nil` are resolved by inspecting `modelContext` and `isLocalRecording`. v2 could make the row's significance non-optional (0 = unrated) once the authored floor is written back to the row, removing the adapter.
- [needs-verdict] `Memo.significance` doc still says "Gates sync (flag-to-send): 0 = the memo STAYS on the phone" — contradicted by `SignificanceScale` (2026-07-20: CloudKit syncs everything; the rating gates pickup) — src: Shared/Model/Memo.swift:91-95 vs Shared/Model/SignificanceScale.swift:5-9, 70-75
- [mechanical] Doors out of unrated: circles, Polish (0.1 floor), Mac import (0.1 floor); a Mac recording stays unrated — src: Shared/Pipeline/NoteConsent.swift:26-29
- [mechanical] `ProcessPile.isWaiting` = rated, live, unlocked, non-blank transcript, no `isProcessed` enhancement; `unrated` = unrated, live, unlocked — src: Shared/Pipeline/ProcessPile.swift:20-33
- [mechanical] `NoteWorkState`: no polish → needsProcessing (label "Process"); polish, not exported → "Export to Obsidian"/"Export to archive"; exported → "Re-export" — src: Shared/Pipeline/NoteWorkState.swift:15-47
- [locked] (v2 one clock, signed 2026-07-22; v3 2026-07-23 "no note dies unseen") clock start = max(recordedAt, keptAt); fade at 30 d, sweep to trash at 60 d; held off the clock: rated, locked, reminder, backlinked; sweeps only at human open; purge clock starts at `trashSeenAt ≥ deletedAt`, retention 14 d inclusive; unseen trashed notes never purge — src: Shared/Pipeline/MemoLifecycle.swift:4-151; Shared/Model/Memo.swift:18-25
- [mechanical] `markEdited` = `editedAt` + `keptAt` (a content edit is a touch); never called for sync-status/significance changes — src: Shared/Model/Memo.swift:245-252
- [mechanical] Spine chain: deleted → active track (rated or Mac-local file: toProcess/processing/stuck/ready/exported) → held → clock (new/fading; still transcribing = new); copy trio pinned verbatim — src: Shared/Pipeline/MemoSpine.swift:107-165
- [mechanical] Typed note = unrated Memo, `transcriptStatus .done`, `metadataData = {"mediaSource":"typed"}`, `recordedAt = now` — src: Shared/Model/Memo.swift:352-374
- [mechanical] Locked notes never export (both apps), keep processing, `LockGate` gates UI — src: Shared/Model/Memo.swift:135-141; SkriftDesktop/Pipeline/Export/VaultExporter.swift:75-78; SkriftMobile/Services/Export/PublishCoordinator.swift:78-81
- [mechanical] Tag input: split on `,`/newline, strip `#`, trim, must contain a letter or digit — src: Shared/Model/Memo.swift:254-291

### Sync contract

- [mechanical] `Memo.id` is the spine: audio filename embeds it, the Mac row id equals it; never regenerated; no `@Attribute(.unique)` (CloudKit) — src: Shared/Model/Memo.swift:43-53
- [mechanical] Every `@Model` attribute has a default, no unique constraints, no external storage; blobs > ~1 MB become CKAssets; `MemoAsset` rows are loose-keyed by `memoID` and `kind` strings (`audio|photo|wordTimings|diarization|document`) — src: Shared/Model/MemoAsset.swift:9-73; MemoEnhancement.swift:17-19
- [mechanical] Phone carries the RAW transcript only, never `sanitised`; the Mac writes polish as a `MemoEnhancement` sidecar (pieces, not compiled markdown); LWW by `enhancedAt`; one row per memo (newest wins on read) — src: Shared/Model/MemoEnhancement.swift:4-15; SkriftMobile/Services/NotesRepository.swift:141-146
- [mechanical] `MemoMetadata` is the wire schema: field names never renamed; timestamps stay strings; `PressureInfo.hPa` stays `Int` (2026-07-26 audit: widening breaks older decoders); unknown `sourceType` strings decode — src: Shared/Model/MemoMetadata.swift:3-12, 108-113, 43-51
- [mechanical] `SharedContent` C3 wire struct: `type url|image|text|file`, camelCase only; nested under `sharedContent` in the Mac's metadata blob; unknown type → nil — src: Shared/Model/SharedContent.swift:3-45
- [mechanical] Capture discriminator (phone): `audioFilename.isEmpty && sharedContent != nil`; text-only memo (typed): no audio, no sharedContent — src: SkriftMobile/Models/MemoDisplay.swift:251-253; SkriftDesktop/Pipeline/Ingest/MemoCloudIngest.swift:74-84
- [mechanical] Vocab, language mode, prompts, names each sync as one carrier row with LWW stamps; carriers collapse to one; a fresh device never pushes an unchosen default — src: Shared/Model/VocabularyRecord.swift; Shared/Pipeline/PolishPromptsSyncCore.swift:36-48; Shared/Naming/NamesSyncCore.swift:41-68
- [mechanical] `recordingDeviceID` = the install that recorded; a receiver never re-transcribes another device's `.transcribing` memo — src: Shared/Model/Memo.swift:167-172
- [needs-verdict] `Memo.syncStatus` (`waiting|synced`, RN heritage) is written at insert and read only by a list filter (`unsyncedOnly`); nothing ever sets `.synced` under CloudKit — dead field — src: Shared/Model/Memo.swift:4-8, 73; SkriftMobile/Features/MemosList/MemosListView.swift:1240
- [needs-verdict] `AppSettings.processAllSyncedMemos` is documented DEAD (2026-07-21) but `processEverything` is still threaded through ingest/sweep and pinned by tests — src: SkriftDesktop/Models/AppSettings.swift:108-113; MemoCloudReconcilerTests.swift:74-83

### Other

- [mechanical] Source taxonomy: audiobook quote (bookTitle) → video (`mediaSource == "video"`) → typed (`mediaSource == "typed"`) → capture subtype → Apple Note (no audio) / voice memo; glyphs + labels single-sourced — src: Shared/Pipeline/SourceTaxonomy.swift:8-73
- [mechanical] Mac `PipelineFile.durationSeconds` reads both a numeric-seconds blob and legacy `HH:MM:SS` strings — src: SkriftDesktop/Models/PipelineFile.swift:325-364
- [mechanical] Share drain: entries deleted only after the memo is saved; video/audio entries delete first (they mint their own ids); PDF-URLs download on drain; text files become the body; image captures date to earliest EXIF; dictation audio kept until its text lands — src: SkriftMobile/Services/Capture/CaptureInboxDrainer.swift:17-25, 133-536; CaptureDictation.swift:5-16
- [mechanical] Append recording: memo shows `.transcribing`; audio merged first (sample-accurate); text appended with `\n\n`; timings shifted by the precise base duration; `transcriptUserEdited = true`; failures keep the clip and set `.failed` — src: SkriftMobile/Features/Recording/MemoSaver.swift:564-671
- [mechanical] Mac live take: settled text is the user's, wet tail the engine's; an EDITED take's words are `settled + finalTail` and set `transcriptUserEdited`; an unedited take waits for the file pass — src: SkriftDesktop/Pipeline/Recording/LiveRecordingDraft.swift:6-44; LiveRecordingFinalize.swift:6-18; SkriftDesktop/Features/Shell/LiveRecordingSession.swift:137-163
- [locked] (2026-07-12) "Better no info than bad info": incomplete derived data must not imply completeness (quoted in `looksTruncated`, `strandedLine`) — src: Shared/Pipeline/PolishPrompts.swift:131-133; SkriftDesktop/Pipeline/WayOutRules.swift:63-71

---

## B) INVARIANTS the harness can check without v1

Body/image model
1. `pieces(raw)` covers the raw string exactly: concatenating piece raw ranges in order reproduces `raw` (BodyTransform.swift:37-69).
2. Display glyph count == number of non-text pieces; display length == raw length − Σ(pieceLen − 1) − (image breaks) (BodyTransform.swift:91-97).
3. `reconstruct(attributed(from: raw)) == raw` for any raw already in snapped form; for unsnapped raw it equals `snapImages(raw).text` (NoteBodyTests.swift:141-146, 820-857; BodyTransformTests checklist/memo-link round trips).
4. `snapImages` is idempotent; on a body without `[[img_` it is the identity (NoteBodyTests.swift:260-283).
5. Markers in == markers out, same set and order, for: snap, paragraphing, filler strip, copy-edit escrow, reinsert, name-linking (`process`/`processConversation`), `unlinkToSpoken`, Mac `modelString`, phone `reconstruct` (ImageMarkerReinsertTests:64-73; ParagrapherTests:97-107; FillerFilterTests; SanitiserTests:135-140; IPadPolishTests:21-35).
6. Snap only relocates markers and whitespace around them: the non-whitespace, non-marker character sequence is unchanged and in order (BodyTransform.swift:156-160, 285-289).
7. `snapped(rawRange:)` maps any name span outside a marker to a range whose text equals the raw span text (NoteBodyTests.swift:291-307).
8. Paragraphing inserts only `\n\n`; token multiset unchanged; input containing `\n` returns unchanged (Paragrapher.swift:69-85).
9. Memo-link literal round-trips through both editors byte-exact; `link(id:title:)` never contains `|` or `[[`/`]]` inside the title (NoteBodyTests.swift:315-320, 349-359).
10. Marker N always resolves through `imageManifest[N-1]`; deleting a marker never changes the manifest; manifest count is monotonic non-decreasing per memo (MemoDisplay.swift:109-124).
11. Every editor commit sets `transcriptUserEdited = true`; a capture commit keeps `rawBlock` as an exact prefix (NoteBodyTests.swift:49-59, 116-136).
12. Karaoke aligned times are monotonic non-decreasing, one per displayed word (Karaoke.swift:41-48, 94-105).

Copy-edit
13. Escrow round trip with an identity generator returns the input except whitespace tidy: quote byte-identical prefix, every `[[memo:…]]` literal present, every `[[img_NNN]]` present in order (IPadPolishTests.swift:21-35).
14. A generator that drops a link title or mutates the quote yields the ORIGINAL body unchanged (IPadPolishTests.swift:62-73; QuoteProtectionTests.swift:131-142).
15. A quote-only capture never calls the generator (IPadPolishTests.swift:49-60).
16. Paragraph count of the model INPUT ≥ paragraph count of the raw body (marker strip preserves blank lines) (ImageMarkerReinsertTests.swift:26-51).
17. Output paragraph count never drops below 1 for text > 600 chars with > 4 sentences (ensureParagraphs); `ensureParagraphs(x).replacing("\n\n"," ") == x` for a wall; already-paragraphed text is identity (IPadPolishTests.swift:113-121).
18. If `lostTooMuch(input, out)` or `looksTruncated(out, cap)` then shipped body == unedited body (EnhancementService.swift:94-101).
19. Budget: `1024 ≤ cap ≤ 8192`, monotonic in input length (IPadPolishTests.swift:90-98).
20. Title always non-empty after a pass on non-empty text; summary empty iff word count < 75 (except manual redo) (BatchRunnerTests.swift:108-116).
21. A conversation (`isAttributed`) is never copy-edited: copyedit == transcript (BatchRunner.swift:134-137).
22. Same transcript + same prompts + same model revision ⇒ byte-identical result on Mac and iPad (temperature 0, revision pinned; `PolishEscrow` mirrors `EnhancementService`) — cross-device check.
23. Every polish pass writes exactly one `MemoEnhancement` per memo with `processedAt != nil`; `isProcessed` ⇒ export gate passes (MacCloudWriteBackTests.swift:111-126; PublishCoordinatorTests.swift:58-65).

Reconcile sweep
24. After any sweep: no rated, live memo lacks a PipelineFile (`stranded == 0`); unrated memos have no row (MemoCloudReconcilerTests.swift:332-344).
25. Sweep is idempotent: a second sweep on unchanged stores yields `created == 0` and `updatedIDs == []` (MemoCloudReconcilerTests.swift:63-72, 106-125, 151-174).
26. One PipelineFile per memo id regardless of duplicate rows or shared filenames; a legacy non-UUID row is still claimed by filename (MemoCloudReconcilerTests.swift:106-198).
27. The keeper of same-id rows is the same on both apps (`MemoDuplicates.keeper`); the phone trashes only exact clones (MemoDuplicatesTests; MemoDeduperTests).
28. `MemoCloudUpdate.apply` is content-idempotent: `apply` twice on the same inputs returns false the second time (MemoCloudUpdateTests.swift:87-98, 355-368).
29. The Mac never re-reflects its own enhancement onto an existing row; a fresh row adopts it (MemoCloudReconcilerTests.swift:350-387).
30. A nil/blank `Memo.title` never clears `pf.enhancedTitle`; an empty phone tag list never clears tags at first contact but does on a live edit (MemoCloudUpdateTests.swift:375-385; MirroredNoteFieldsTests.swift:60-70).
31. A phone trash/restore reaches the row; a Mac-local trash is never clobbered by an unchanged active memo (MemoCloudUpdateTests.swift:276-333).
32. Write-back never clobbers a strictly newer other-device enhancement; own writes always update in place; row count per memo stays 1 (MacCloudWriteBackTests.swift:70-84, 171-201).
33. Trust: transcript adopted iff `userEdited || confidence ≥ 0.7`; otherwise `transcribeStatus == .pending` and transcript nil (UploadTests.swift:78-98).
34. Ingest via CloudKit and via multipart produce field-identical rows except `id` (MemoCloudIngestTests.swift:32-94).
35. Late assets heal only holes: existing Mac timings/segments are never overwritten; a garbage blob is ignored (MemoCloudReconcilerTests.swift:205-296).
36. A Mac recording authors an unrated memo; an import authors a 0.1-floored memo; an explicit rating is never overwritten (MacMemoAuthorSignificanceTests; ArrivalPathTests).
37. `reflectTranscripts` writes only `.done` rows into EMPTY memos this device recorded (MacMemoAuthorTests.swift:188-264).
38. `names.json` written by either app decodes identically on the other and re-encodes to the same bytes (sorted keys); merge is commutative for LWW+union (NamesTests; NamesSyncCore.swift:24-30).

Export compiler
39. Compile is pure: same `CompilerInput` ⇒ same string; the stamp makes re-stamping at the same time idempotent (VaultStampTests.swift:42-46).
40. `standing(apply(md))` is `.untouched`; any single-character change outside the hash line yields `.userEdited`; a text without frontmatter is never stamped and reads `.foreign` (VaultStampTests.swift:56-127).
41. Re-export of unchanged content writes nothing (no mtime churn, no assets, no blob fetch) (VaultWriteTests.swift:56-63, 266-276; ObsidianPublisherTests.swift:188-196).
42. Never overwrite a foreign or legacy or user-edited file; foreign collision → deterministic `<stem> <ID8>`; legacy → refuse without a twin; edited → back off (VaultWriteTests.swift:82-126).
43. Moved (stamp found under root) → `movedAway`; deleted (no stamp anywhere) → writable again (VaultWriteTests.swift:133-166).
44. A retitle keeps the file path (sticky ledger); a fresh ledger adopts its own stamped file (VaultWriteTests.swift:73-78, 215-237).
45. Same memo exported by phone and Mac lands at the same relative path and the same stem/embed names (`VaultName.stem`, `<stem>_NNN.ext`) (ObsidianPublisher.swift:58-71; VaultExporter.swift:112-115).
46. No `[[img_NNN]]`, no `[[memo:` and no `> ` unstyled quote line (for a book capture) survive into the vault; the number of `![[…]]`/`![](…)` embeds == number of resolvable markers (ObsidianPublisherTests.swift:165-178; VaultExporterTests.swift:143-237).
47. Archive profile: no `type:`, `author:`, `source:`, weather/pressure/dayPeriod/daylight/steps/significance; has `capture:`, `voice:`, `location:`; `needs: - credit` iff inspiration (destination or tag); only person links keep brackets (ArchiveExportTests.swift:91-161, 285-307).
48. `people:` lists each canonical once, in reading order, persons only (CompilerTests.swift:35-62).
49. Locked memos produce zero writes on both apps (VaultExporterTests.swift:271-291; PublishCoordinatorTests.swift:101-108).
50. Unrated memos never export; unprocessed memos never export from the phone (PublishCoordinatorTests.swift:47-99, 135-141).
51. Frontmatter key order is stable across re-exports (upsert in place) so a diff shows only value changes (VaultStamp.swift:199-215).

Cross-cutting
52. `NoteConsent.isRated` agrees with `SignificanceScale.litCount > 0` for every value incl. nil/0/noise/NaN (NoteConsentTests.swift:12-25).
53. The MemoSpine chain assigns exactly one station; the copy trio strings are byte-pinned (MemoSpineTests).
54. Fade/sweep/purge never move while apps are closed: `purgeDue` is false whenever `trashSeenAt < deletedAt` or nil (TrashTests.swift:94-133).

---

## C) V1 FILE INVENTORY per rewrite target

Kind: **S** shared · **M** Mac-only · **P** phone-only · **T** twin (same logic both sides).

### 1 · Body/image model — 7,940 lines (S 1,527 · M 2,330 · P 4,083)

| file | lines | does | kind |
|---|---:|---|---|
| Shared/Pipeline/BodyTransform.swift | 363 | pieces, displayRange, imageBreaks, snapImages | S |
| Shared/Pipeline/ImageMarkers.swift | 63 | capture-time marker insertion by word time | S |
| Shared/Pipeline/ImageMarkerReinsert.swift | 154 | strip/anchor/reinsert markers around copy-edit | S |
| Shared/Pipeline/BodyMarkdown.swift | 42 | heading + inline-tag ranges | S |
| Shared/Model/MemoLinkSyntax.swift | 103 | memo-link syntax, escrow, export rewrite | S |
| Shared/Model/CaptureQuote.swift | 131 | presentation split of leading quote | S |
| Shared/Naming/QuoteProtection.swift | 54 | copy-edit split + byte assert of quote | S |
| Shared/Model/MemoMetadata.swift | 161 | wire schema incl. `ImageManifestEntry` | S |
| Shared/Pipeline/Paragrapher.swift | 152 | pause-based paragraphing, marker passthrough | S |
| Shared/Pipeline/Karaoke.swift | 125 | word-time alignment for read-along | S |
| Shared/Model/WordTiming.swift | 13 | timing sidecar element | S |
| Shared/Pipeline/SpeakerTranscript.swift | 166 | turn header parse/merge/relabel | S |
| SkriftDesktop/Features/Review/BodyTextView.swift | 1,566 | NSTextView editor: attachments, snap, remaps, popovers | M |
| SkriftDesktop/Features/Review/NoteBody.swift | 318 | body precedence, imageURL via manifest, karaoke | M |
| SkriftDesktop/Features/Review/ReviewHelpers.swift | 54 | `bestBodyText`, display title | M |
| SkriftDesktop/Pipeline/Ingest/MemoPhotoMaterializer.swift | 71 | write late photos + manifest to working folder | M |
| SkriftDesktop/Features/Journal/UnpipelinedMemoSheet.swift | 321 | quiet-row body render from pieces | M |
| SkriftMobile/Features/MemoDetail/NoteBodyView.swift | 1,485 | UITextView editor: attributed/reconstruct, debounce, karaoke | P |
| SkriftMobile/Features/MemoDetail/KaraokeMap.swift | 61 | display word ranges vs timings | P |
| SkriftMobile/Features/MemoDetail/SpeakerTurnsView.swift | 217 | turn render with inline photos | P |
| SkriftMobile/Models/MemoDisplay.swift | 409 | display title, thumbnail rule, imageURL | P |
| SkriftMobile/Services/Recording/PhotoCaptureService.swift | 191 | timestamped photo capture | P |
| SkriftMobile/Services/PhotoTextIndexer.swift | 91 | OCR into manifest `text` | P |
| SkriftMobile/Services/MemoImageLoader.swift | 34 | mtime-keyed thumbnail cache | P |
| SkriftMobile/Models/FillerFilter.swift | 91 | opt-in filler strip, markers pass | P |
| SkriftMobile/Features/Recording/MemoSaver.swift | 966 | persist, movePhotos, paragraph, append, video, diarize | P |
| SkriftMobile/Services/Capture/CaptureInboxDrainer.swift | 538 | share ingress; appends markers to annotation | P |

Three stacked photo offset remaps, where each lives:

| remap | what | shared | Mac | phone |
|---|---|---|---|---|
| capture | `offsetSeconds` → char position at nearest word | ImageMarkers.insert (63) | fed via `image_manifest.json` in ProcessingCoordinator.swift:296-302; BatchRunner transcribe | MemoSaver.runTranscription:797-799; diarize re-insert:943-946 |
| snap | raw marker position → sentence end (`SnapResult.snapped`) | BodyTransform.snapImages (198-363) | BodyTextView.render:438, suggestedRanges:852-856; VaultExporter:132 | NoteBodyView.load:331, applyTierStyling:551-554; ObsidianPublisher:190 |
| attachment collapse | snapped text offset → storage offset (glyph = 1 char) | BodyTransform.displayRange(s) (99-146) | BodyTextView.attachmentModelLocs:869-891 (Mac twin, not the shared fn) | NoteBodyView.applyTierStyling:555-557 (shared fn) |

Twins inside target 1: Mac `attachmentModelLocs` ⇄ shared `displayRanges`; Mac `modelString` ⇄ phone `reconstruct`; Mac `wordRanges` ⇄ phone `KaraokeMap.wordRanges`; Mac `NoteBody.imageURL` ⇄ phone `Memo.imageURL`.

### 2 · Copy-edit pipeline — 2,674 lines (S 464 · M 1,348 · iPad 862) + 311 shared escrow helpers counted under target 1

| file | lines | does | kind |
|---|---:|---|---|
| Shared/Pipeline/PolishPrompts.swift | 172 | model pin, prompts, budget, wall cure, shrink/trunc guards | S |
| Shared/Pipeline/PolishPromptsSyncCore.swift | 66 | prompt blob LWW | S |
| Shared/Model/PolishPromptsRecord.swift | 29 | prompt carrier row | S |
| Shared/Model/MemoEnhancement.swift | 83 | polish sidecar, `hasContent`/`isProcessed` | S |
| Shared/Pipeline/NoteWorkState.swift | 52 | Process/Export/Re-export state | S |
| Shared/Pipeline/ProcessPile.swift | 62 | waiting/done/unrated piles | S |
| SkriftDesktop/Engines/EnhancementService.swift | 151 | MLX engine + escrow (copyEdit/editProse) | T (⇄ PolishEscrow+MLXPolishEngine) |
| SkriftDesktop/Pipeline/Enhancement/Enhancing.swift | 9 | engine protocol | M |
| SkriftDesktop/Pipeline/BatchManager/BatchRunner.swift | 266 | transcribe→enhance→tag→link→compile orchestration | M |
| SkriftDesktop/Features/Shell/ProcessingCoordinator.swift | 519 | queue run, redo, retranscribe, export, write-back | M |
| SkriftDesktop/Models/AppSettings.swift | 177 | prompts override, thresholds, flags | M |
| Shared/Pipeline/Tags/TagMatcher.swift | 82 | deterministic tag candidates (Mac-only caller) | S |
| SkriftDesktop/Pipeline/BatchManager/RunReconciler.swift | 21 | reset interrupted steps | M |
| SkriftDesktop/Pipeline/Sanitisation/RosterAudit.swift | 50 | collision re-scan | M |
| SkriftDesktop/Pipeline/Sanitisation/PeopleFolderScanner.swift | 38 | roster seed from vault titles | M |
| SkriftDesktop/Features/Shell/StubEngines.swift | 35 | UI-piloting stubs | M |
| SkriftMobile/Services/Polish/PolishCenter.swift | 381 | on-demand polish, pile, write | P (iPad) |
| SkriftMobile/Services/Polish/Engine/MLXPolishEngine.swift | 231 | MLX engine 1:1 port | T |
| SkriftMobile/Services/Polish/Engine/PolishEscrow.swift | 68 | escrow 1:1 port | T |
| SkriftMobile/Services/Polish/PolishPromptsStore.swift | 115 | prompt overrides + stamp | P |
| SkriftMobile/Services/Polish/PolishBootstrap.swift | 67 | engine install at launch | P |

### 3 · Reconcile sweep — 5,297 lines (S 1,197 · M 3,540 · P 560)

| file | lines | does | kind |
|---|---:|---|---|
| Shared/Model/Memo.swift | 375 | the synced note, trust gate, typed note | S |
| Shared/Model/MemoAsset.swift | 74 | media blob rows | S |
| Shared/Model/SharedContent.swift | 45 | C3 wire struct | S |
| Shared/Pipeline/MemoDuplicates.swift | 55 | keeper rule | S |
| Shared/Pipeline/NoteConsent.swift | 43 | rated predicate | S |
| Shared/Pipeline/MemoLifecycle.swift | 196 | fade/sweep/purge clocks | S |
| Shared/Pipeline/MemoSpine.swift | 244 | one-status chain + copy | S |
| Shared/Pipeline/SourceTaxonomy.swift | 74 | source kind | S |
| Shared/Model/SignificanceScale.swift | 91 | rating grid | S |
| SkriftDesktop/Pipeline/Ingest/MemoCloudIngest.swift | 271 | memo → parts → row, metadata JSON, late-asset heals | M |
| SkriftDesktop/Pipeline/Ingest/MemoCloudReconciler.swift | 187 | the pure sweep | M |
| SkriftDesktop/App/MemoCloudReconciler+Wiring.swift | 217 | triggers, order, re-export, author/reflect | M |
| SkriftDesktop/Pipeline/Ingest/MemoCloudUpdate.swift | 164 | phone→Mac reflect | M |
| SkriftDesktop/Pipeline/Ingest/MacCloudWriteBack.swift | 116 | enhancement upsert, memo resolve | M |
| SkriftDesktop/App/MacCloudEditSync.swift | 61 | debounced live-edit push | M |
| SkriftDesktop/App/MacCloudMetaSync.swift | 113 | tags/rating/destination/title push | M |
| SkriftDesktop/App/MacCloudDeleteSync.swift | 45 | trash push | M |
| SkriftDesktop/Pipeline/MirroredNoteFields.swift | 123 | the mirror declaration | M |
| SkriftDesktop/Pipeline/NoteConsent+PipelineFile.swift | 40 | nil-significance adapter | M |
| SkriftDesktop/Pipeline/Ingest/MemoNoteProjection.swift | 216 | unrated memo as transient row | M |
| SkriftDesktop/Pipeline/Ingest/MacMemoAuthor.swift | 207 | Mac authors memos, reflects transcripts | M |
| SkriftDesktop/Pipeline/Ingest/MacLocationStamp.swift | 57 | place on Mac recordings | M |
| SkriftDesktop/Pipeline/Ingest/ArrivalPath.swift | 104 | one door for drop/import/record | M |
| SkriftDesktop/Pipeline/Ingest/IngestService.swift | 448 | local file/video/note ingest | M |
| SkriftDesktop/Pipeline/Ingest/UploadService.swift | 345 | multipart → working folder + row | M |
| SkriftDesktop/Pipeline/Ingest/MultipartPart.swift | 13 | part struct | M |
| SkriftDesktop/Pipeline/WayOutRules.swift | 198 | quiet rows, stranded, needsProcessing | M |
| SkriftDesktop/Pipeline/DesktopTrash.swift | 64 | Mac trash/purge | M |
| SkriftDesktop/Models/PipelineFile.swift | 375 | the Mac row | M |
| SkriftDesktop/Pipeline/BatchManager/DiarizationSidecar.swift | 83 | `diar_<id>.json` | M |
| SkriftDesktop/Features/Shell/LifecycleSweepScheduler.swift | 93 | Mac at-open sweep (not read) | M |
| SkriftMobile/Services/AssetMaterializer.swift | 141 | blob ⇄ file sweep | P (⇄ MemoPhotoMaterializer) |
| SkriftMobile/Services/MemoDeduper.swift | 46 | clone heal | P |
| SkriftMobile/Services/NotesRepository.swift | 269 | store, trash, purge | P |
| SkriftMobile/Services/FadingSweep.swift | 44 | phone at-open sweep | P |
| SkriftMobile/Services/WordTimingsStore.swift | 31 | `wt_<id>.json` | P |
| SkriftMobile/Services/Diarization/DiarizationStore.swift | 29 | `diar_<id>.json` | P |

### 4 · Export compiler — 2,734 lines (S 1,485 · M 432 · P 817)

| file | lines | does | kind |
|---|---:|---|---|
| Shared/Export/Compiler.swift | 341 | frontmatter + body, capture block, audiobook body, people, plainify | S |
| Shared/Export/CompilerInput.swift | 95 | neutral DTO, `NoteVoice` | S |
| Shared/Export/ExportProfile.swift | 114 | obsidian vs archive layout, slug | S |
| Shared/Export/VaultLayout.swift | 85 | home-folder resolution | S |
| Shared/Export/VaultStamp.swift | 216 | skriftID/skriftHash/lastTouched | S |
| Shared/Export/VaultWrite.swift | 414 | ledger, naming, assess, commit, atomic IO | S |
| Shared/Export/ExportOutcomeCopy.swift | 69 | outcome copy + stickiness | S |
| Shared/Model/NoteDestination.swift | 115 | four destinations, settings switch | S |
| Shared/Model/NoteTitle.swift | 36 | derived-title clip | S |
| SkriftDesktop/Pipeline/Export/CompilerBridge.swift | 128 | `PipelineFile → CompilerInput`, memo-link stems | T (⇄ MemoExporter.compilerInput) |
| SkriftDesktop/Pipeline/Export/VaultExporter.swift | 304 | Mac asset sourcing, marker→embed, attachments | T (⇄ ObsidianPublisher) |
| SkriftMobile/Services/Export/MemoExporter.swift | 286 | `Memo → CompilerInput`, plain text, PDF, card | T |
| SkriftMobile/Services/Export/ObsidianPublisher.swift | 261 | phone asset sourcing, marker→embed | T |
| SkriftMobile/Services/Export/PublishCoordinator.swift | 174 | gate + refusals | P |
| SkriftMobile/Services/Export/MemoLinking.swift | 36 | on-device re-link | P |
| SkriftMobile/Services/Export/ArchiveVault.swift | 60 | archive root bookmark | P |

Names & sanitise (referenced by 2 and 4, not a rewrite target): Sanitiser 781, NameStoplist 54, NameMatch 61, NamesData 185, NamesStore 269, NamesSyncCore 69, PersonEditCore 66, NamesRecord 30 — 1,515 lines, all shared.

Grand total of the four targets: **18,645 lines** (with the 311 escrow helpers counted once). A 40% budget ≈ 7,460 lines.

---

## D) DATA FLOW per rewrite target

### 1 · Body/image model
1. Enters: a raw transcript string (ASR output or typed/annotation), an `imageManifest` (`filename`, `offsetSeconds`, `text?`) on `Memo.metadataData`, word timings (`wt_<id>.json` / `wordTimingsJSON`), optional `MemoEnhancement.copyedit`.
2. Capture: `ASRPostProcess.finish` → `ImageMarkers.insert` puts `\n\n[[img_NNN]]\n\n` at the nearest word (phone MemoSaver / Mac BatchRunner); phone then `Paragrapher.paragraphed(transcript:words:)` (0.65 s) and optional `FillerFilter`; Mac paragraphs with 2.0 s. Stored: `Memo.transcript` (RAW, markers in place), `transcriptConfidence`, `transcriptMarkersInjected`; Mac `PipelineFile.transcript` + `wordTimingsJSON`.
3. Display: body text = polished copyedit when present (monologue, non-capture) else raw; capture → ramble only; `BodyTransform.snapImages` → `pieces` → attributed string with one U+FFFC per piece, display-only `\n` around photos (phone) / paragraph styles (Mac); thumbnails resolved via manifest index N → `recordings/<filename>` (phone) or `<workingFolder>/images/<manifest[N-1]>` (Mac).
4. Name tiers: `Sanitiser.nameSpans(inRaw:)` over the RAW body (phone) → `snapped(rawRange:)` → `displayRanges`; Mac uses `ambiguousNames` offsets over `sanitised` → snap → attachment shifts.
5. Edit: keystrokes mutate storage; phone commit (debounced) → `reconstruct` → `Memo.transcript` or `enhancement.copyedit` (pinned target), `transcriptUserEdited = true`, `markEdited`; Mac keystroke → `modelString` → `sanitised`/`copyedit`/`transcript` → `MacCloudEditSync` (1.5 s) → `MacCloudWriteBack.upsert(bodyOverride: unlinkToSpoken)`.
6. Photo insert: file `photo_<id>_NNN.jpg`, manifest append (`offsetSeconds 0`), attachment in text, commit, `AssetMaterializer.capture`, `PhotoTextIndexer.run`.
7. Leaves: the raw body (to the copy-edit pipeline and export), the manifest (to sync/export), word timings (to karaoke/export not at all).

### 2 · Copy-edit pipeline
1. Enters: `pf.transcript` (Mac) or `memo.transcript` (iPad) — always the RAW body with markers/links/quote; prompts (settings override else `PolishPrompts`); `summaryMinWords` 75; the pinned model.
2. Gate: Mac `needsProcessing` (live, `enhanceStatus != .done`, not an unrated Mac take); captures take enhancement-lite; conversations skip copy-edit; empty transcript → done with nothing. iPad: `canPolish` (engine, transcript, unlocked, one at a time) and floors significance to 0.1.
3. Copy-edit: quote split → link escrow → marker strip (+anchors, newline-preserving tidy) → generate (budget from input) → Mac: truncation/shrink guards → `ensureParagraphs` → marker reinsert (anchors) → link reattach (nil ⇒ unedited) → quote reassemble + byte-assert (mismatch ⇒ unedited). BatchRunner re-asserts the quote and the mid-run edit guard.
4. Title: LLM over link-escrowed transcript (64 tokens) → `titleSuggested`; `enhancedTitle` filled only if empty. Summary: only when ≥75 words (256 tokens).
5. Mac deterministic tail: `TagMatcher.suggest` on `copyedit ?? transcript` → `tagSuggestions`; `Sanitiser.process`/`processConversation` with `unlinkedNames`/`namePicks` → `sanitised`, `ambiguousNames`; `enhanceStatus = .done`; `compiledText = Compiler.compile(file:)`.
6. Stored: Mac `PipelineFile.enhancedCopyedit/enhancedTitle/titleSuggested/enhancedSummary/tagSuggestions/sanitised/ambiguousNamesJSON/compiledText`; then `MacCloudWriteBack.upsert(passRan: true)` → `MemoEnhancement{copyedit(raw names), title, summary, enhancedByDeviceID, enhancedAt, processedAt}`. iPad writes the same `MemoEnhancement` directly.
7. Leaves: `MemoEnhancement` over CloudKit (phone prefers it for display/export); `sanitised`/`compiledText` to the Mac review body and exporter.

### 3 · Reconcile sweep
1. Enters (Mac): every `Memo` + `MemoEnhancement` in the CloudKit mirror store (fresh context), local `PipelineFile`s, live roster, author name, device id; assets fetched lazily.
2. Per memo (after `canonicalRows` keeper collapse): find row by id, else by filename not owned by another memo.
   - Existing row → `MemoCloudUpdate.apply` (trash mirror → phone enhancement unless own echo → chosen title adopt → transcript adopt → metadata blob byte-compare → mirrored fields pull → OCR) → re-link + recompile when content changed → `lastActivityAt`; then heals: photos/manifest, late timings, late diarization.
   - No row → `MemoCloudIngest.ingest`: skip trashed/unrated; build parts; `UploadService.prepare/commit` (audio/capture/text-only branch, trust gate, sidecars only when trusted, images + `image_manifest.json`); baseline `syncedSourceEditedAt`; OCR; `MirroredNoteFields.adopt`; then `apply(isFreshRow: true)` so an existing cloud enhancement (even this device's) lands on the new row. Rated live memo still without a row → `stranded` log.
3. After the loop: post `cloudMemosDidChangeFromSync`; save; re-export updated rows already `.done`/unlocked/untrashed; `MacMemoAuthor.backfill` (local UUID rows with a path and no memo → Memo + audio asset, 0.1 floor unless recording); `reflectTranscripts` (Mac words → empty memo transcript, own memos only, `.done` only); connections index sweep.
4. Mac → phone at other times: `writeBackEnhancement` after each processed file (`passRan`), `MacCloudEditSync` on body edits (`unlinkToSpoken` body), `MacCloudMetaSync` (tags/rating passive; rating/destination/title events), `MacCloudDeleteSync` (trash + `trashSeenAt`).
5. Phone side of the same loop: `AssetMaterializer.run` (blobs ⇄ files, sidecars), `MemoDeduper.run` (exact clones → trash), `FadingSweep.run` (stamp sightings, sweep due → soft delete), `purgeExpiredTrash`, `recoverStuckTranscriptions/Diarizations` (own memos only), `PhotoTextIndexer.run`.
6. Stored: `PipelineFile` (all mirrored fields + watermarks), working folder files, `MemoEnhancement` rows, `Memo` fields written by the Mac (title, tags, significance, destination, deletedAt, trashSeenAt, transcript for Mac-authored memos, metadata for Mac recordings).
7. Leaves: rows for the Process queue and the exporter; enhancements for the phone/iPad; trash/rating/title/destination convergence across devices.

### 4 · Export compiler
1. Enters: Mac `PipelineFile` (`sanitised ?? enhancedCopyedit ?? transcript`, titles, summary, tags, significance, `audioMetadataJSON` → `PhoneMetadata`, `SharedContent`, destination, `mediaSource`) or phone `Memo` + `MemoEnhancement` + live roster (body re-linked on-device into `sanitised`); the picked folder (vault bookmark / `noteFolder`) or archive root; the per-folder `ExportLedger`.
2. Gate: Mac — locked throws, no folder throws; phone — `PublishCoordinator.shouldPublish` (folder per destination, live, unlocked, rated, has content, `isProcessed`).
3. `VaultLayout.home(forPicked:profile:)` → `VaultWriter.assess(id, title, filenameFallback, recordedAt)` → relative path or a refusal (nothing else touched).
4. `Compiler.compile(input, author, date, knownPeople, profile)`: memo-link rewrite (stems from ledger then derived), archive plainify, frontmatter (profile-dependent keys/order), body (capture block / audiobook italics+attribution / plain).
5. `BodyTransform.snappedImageBody` → markers → `![[<stem>_NNN.ext]]` (vault) or `![](…)` (archive) with image copies (Mac from `images/` dir, phone from `MemoAsset` blobs via the manifest); Mac also Apple-Note attachments and the archive-only source movie.
6. `VaultWriter.commit`: `VaultStamp.apply` (lastTouched, skriftID, skriftHash) → `contentEquivalent` short-circuit → atomic coordinated write → ledger → assets (`Images/`, `Documents/`, `Recordings/` or beside the note).
7. Stored: the `.md` + media in the user's folder (the only state outside Skrift); ledger JSON in Application Support; Mac `pf.exported`, `exportStatus = .done`. Phone reads `hasPublished` from the ledger.
8. Leaves: `VaultWriteOutcome` → shared `ExportOutcomeCopy` (sticky for refusals) on both UIs.
