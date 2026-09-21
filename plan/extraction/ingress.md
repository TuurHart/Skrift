# Ingress paths — derived from code (2026-09-21)

Scope: every door through which content enters Skrift, read from the source in this worktree
(`f150455a`). Line numbers are from that tree. Earlier surveys (`SHARE_INGEST_SURVEY.md`
2026-07-07/12, `Skrift_Native/CAPTURE_CONTRACT.md`) are cross-checked at the end.

Legend: 🐛 = jank found in code/ledgers, with the expected behaviour. ❓ = only Tuur can decide.
"unverified" = derived from code, not run on a device in this pass.

Paths that make a NOTE (memo) are the corpus targets. Paths that make a BOOK or only start a
recording are listed for completeness and marked as such.

---

## Phone — share extension (`Skrift_Native/SkriftMobile/SkriftShare/`)

Common to P1–P11:
- Activation rule (`SkriftShare/Info.plist`): per attachment, any of `public.url`,
  `public.plain-text`, `public.image`, `public.movie`, `public.audio`, `com.adobe.pdf`,
  `public.file-url`, `public.data`; every attachment must match; **1–10 attachments per
  extension item**. `public.data` makes Skrift appear for practically any file.
- 🐛 **Only `inputItems.first` is read** (`SharePayloadLoader.swift:77`). WhatsApp ships a
  multi-select as MULTIPLE `NSExtensionItem`s (backlog.md:5215–5226, devlog-proven
  2026-07-12: voice notes + photo + link + video → only the video landed). The "B3 round 2"
  kickoff (flatten attachments across all items) was written but never built; the code still
  reads `.first`. Expected: attachments from ALL items enter the dispatcher.
- Dispatch order (`load`, :82–160): audio → web URL (non-file) → movie → image(s) → plain
  text → document. First match wins; the rest of the item is DROPPED except in the audio
  branch (B3 collects images + text alongside) and the URL branch (A3 prefers text and keeps
  the url).
- No network in the extension (entitlements = App Group only). All fetches happen in the app
  on drain (E4).
- Extension writes `<AppGroup>/CaptureInbox/<uuid>/entry.json` (+ blobs); the app drains on
  launch/foreground (`CaptureInboxDrainer.drain`, :87), under a ~30 s background-task claim.
  Every drained share jumps to its note (`MemoOpenBridge`), except Books-routed audio.
- Sheet: significance circles (default 0) + typed annotation (not for audio). No title, no
  tags, no destination. Tags always `[]`; destination stays the model default
  (`Memo.destinationRaw = personal`).
- Source filename: the extension renames every blob to `shared_<uuid>.<ext>` immediately
  (`:183, :240, :283, :406`); the ORIGINAL NAME survives only as `fileDisplayName` for the
  document branch (P10). **No path on the phone parses a date out of a filename** (grep
  `dateFromFilename` on mobile: 0 hits; only the Mac has it, `IngestService.swift:208`).

### P1 — Audio share (WhatsApp / Voice Memos / Files / Telegram-with-audio-UTI)
- Entry: `SharePayloadLoader.load` :87 → `loadAudio` :227 → sheet → entry `type:"audio"` →
  `CaptureInboxDrainer.process` :175 → `MemoSaver.importAudioClips` :126 / `importAudio` :68.
- Accepts: any provider conforming to `public.audio`; 1–10 clips. Audio outranks everything
  (the i4 fix: a WhatsApp voice note also exposes a URL representation).
- Filename: not kept. Order key = provider file `modificationDate` read before the copy; sort
  via `CaptureInbox.stableClipOrder` :276 — any missing date, or all dates within 2 s → keep
  provider order (WhatsApp materialises every temp copy at share time, so dates tie).
- Note: `Memo(audioFilename: memo_<id>.<srcExt>, transcriptStatus: .transcribing,
  syncStatus: .waiting)`; no `metadata`, so `SourceKind = .voiceMemo`. `recordedAt` ladder =
  embedded asset `creationDate` → clip file modificationDate (from the entry) → now
  (`MemoSaver.swift:88–110`). Transcript = on-device Parakeet, paragraphed; failure → `.failed`,
  no title. Significance from sheet. Title nil.
- Multi-item: sheet chooser **"One note" (default) / "N notes"**. One note = clips merged in
  order via sample-accurate `AVAudioFile` reads into one `memo_<id>.m4a`, one transcript;
  all-unreadable → title "Couldn't read the shared audio", `.failed`. N notes = N entries, N
  memos, each dated to its own clip.
- Network: none.
- 🐛 WhatsApp date: ogg-opus carries no `creationDate`; the temp copy's modificationDate =
  share time → **the memo is dated to the share moment, not the voice note** (device round 1
  finding, `CaptureInbox.swift:53–57`, only partially fixed: the clip date IS the share-time
  copy). The Mac parses "WhatsApp Audio 2025-12-18 at 18.30.44" from the filename; the phone
  never sees the filename. Expected: date from the filename when the container has no date.
- 🐛 `.opus`/`.ogg` on-device transcription: `importAudio` comment :63–65 says an unsupported
  container "fails gracefully → synced as raw audio → the Mac transcribes"; `runTranscription`
  :836 just marks `.failed`. Whether FluidAudio reads ogg-opus is unverified. Expected: a
  transcript, on whichever device can decode it.
- Fixture: one LibriVox/Common Voice clip transcoded to **ogg-opus**, named
  `WhatsApp Audio 2025-12-18 at 18.30.44.opus`; one `.m4a` from Voice Memos naming
  (`New Recording 22.m4a`, with embedded creationDate); one `.mp3`, `.wav`, `.flac` via
  Files. Golden: memo JSON (audioFilename ext, recordedAt, transcript, status, significance)
  + the merged m4a duration for the multi-clip case.

### P2 — Audio by extension fallthrough (Signal / Telegram voice notes with non-audio UTIs)
- Entry: `loadFile` :171 → D7 reroute :198–207 when the copied file's extension is in
  `m4a mp3 wav aac caf aiff aif opus ogg oga flac` → same `isAudio` payload as P1 (single clip).
- Accepts: only ONE provider reaches `loadFile` (`.first` at :154) → a multi-select of Signal
  notes yields ONE clip (the rest dropped, silently). 🐛 Expected: all clips, chooser as P1.
- Filename/date: modificationDate of the provider temp (= share time). Signal's
  `signal-2026-04-13-18-15-24-552.aac` date is lost on the phone (see P1).
- Fixture: Common Voice clip → `.aac`, named `signal-2026-04-13-18-15-24-552.aac`; a Telegram
  `.ogg` (`audio_2026-04-13_18-15-24.ogg`). Golden as P1.

### P3 — Mixed bundle: voice notes + photo(s) + chat text (B3)
- Entry: audio branch :89–108 collects images (non-audio providers conforming to
  `public.image`) and the first text-only provider. Sheet title spells it out; the 1-or-N
  chooser hides — ALWAYS one note.
- Note: as P1 plus `metadata.imageManifest = photos (offsetSeconds 0)` set BEFORE the
  transcript lands, `annotationText = chat text`. Photos saved as
  `photo_<memo>_00N.jpg` (:257–270). Marker insertion is the shared `ImageMarkers.insert`:
  each `[[img_NNN]]` goes after the word whose start is closest to `offsetSeconds` = 0 →
  **after the first word of the transcript** (`ImageMarkers.swift:42–52`).
- 🐛 "Share-import placed the picture wrong" (backlog.md:891–898, 675–690; still open: the
  2026-08-20 whitespace fix was not enough). ❓ Expected placement is a verdict (top of note
  vs bottom vs "first picture before the text").
- Fixture: 3 opus clips + 1 JPEG with EXIF + one text line, one entry. Golden: transcript
  with marker position, manifest, annotation.

### P4 — Long audio → Books (E2)
- Entry: `ShareSheetView.hasLongClip` :35 (any clip ≥ 3600 s) → chooser defaults to
  **Audiobook**; entry `routeToBooks: true` → drainer :224–235 →
  `AudiobookImporter.importBook(from: temps)` → `AudiobookLibraryStore.add`. Failure falls
  back to the memo import.
- Makes a BOOK, not a note; no jump. Multi-clip = file-per-chapter book, parts sorted by
  the TEMP filename (`shared_import_<entry>_<i>`) — i.e. clip order.
- Fixture: a 61-min LibriVox chapter `.m4a`. Golden: `Audiobook` record (title/author from
  tags or filename fallback, chapters, duration).

### P5 — Web URL (Safari/Chrome/any app that hands a `public.url`)
- Entry: `load` :114–136 (excludes `public.file-url`) → `loadURL` :312 → entry `type:"url"`
  → drainer :291–350.
- Title in the extension = `item.attributedContentText` else `attributedTitle` (Safari/Chrome
  supply the page title; other apps supply nothing → the card shows the domain).
- Drain sub-branches, in order:
  1. **PDF link (C5)** — `.pdf` extension, or http(s) HEAD sniff `Content-Type:
     application/pdf` (10 s) → `downloadPDF` (20 s, `%PDF` magic-byte check) →
     `SharedContent(type:.file, filePath: file_<memo>.pdf, fileName: lastPathComponent)` +
     `PDFTextExtract` into `sharedContent.text`. Failure → plain link card.
  2. **Maps link (D6)** — `PlaceLink.parse` (Apple `ll=`/`coordinate=`, Google `/place/…/@lat,lng`
     or `?q=lat,lng`; short `maps.app.goo.gl` = plain card) → `metadata.location`, urlTitle =
     place name if the app gave none. No enrichment fetch.
  3. **Everything else** — `LinkEnrichment.enrich` :20: ONE GET, 12 s timeout, requires 2xx +
     `Content-Type` containing `html`, parses the first 2 MB: title = `og:title` →
     `twitter:title` → `<title>`; description = `og:description` → `twitter:description` →
     `description`; `og:image`/`twitter:image` → downloaded, ImageIO-downsampled ≤640 px →
     `linkthumb_<memo>.jpg`; article text = `<p>` blocks (≥40 chars each) inside `<article>`
     else `<body>` minus nav/header/footer/aside/form/figure; needs ≥3 paragraphs and ≥400
     chars, capped at 60 000 → `sharedContent.text` (search-only, never rendered). Regex
     parsing, no JS execution. Sheet title (if any) wins over the fetched title.
- Note: `Memo(audioFilename: "", transcriptStatus: .done, sharedContent{url, urlTitle,
  urlDescription, urlThumbnailUrl, text}, annotationText: typed thought,
  recordedAt: sharedAt)`; `SourceKind = .captureURL`.
- Offline / JS-rendered: enrich returns nil (offline) or whatever the server-side HTML says
  (JS apps: title from `<title>`/og tags if present, article nil). Nothing retries later —
  enrichment is once, at drain.
- YouTube / Instagram / TikTok: **no source-specific code anywhere** (grep youtube|instagram|
  tiktok|oembed in Swift: only embedding-test fixtures). A YouTube link = P5.3 with whatever
  og tags YouTube serves; Instagram = the login-wall HTML unless og tags come through.
- 🐛 A link shared from a messenger as TEXT (many chat apps hand a `public.plain-text`
  containing the URL, no `public.url`) lands as P7 text capture: no card, no enrichment
  (unverified per app; from the dispatch order).
- Fixture: a Wikipedia article URL (og tags + ≥3 `<p>`), an arxiv `/pdf/…` extensionless
  PDF URL, an `maps.apple.com/?ll=38.72,-9.13&q=Café` URL, one public YouTube URL, one public
  Instagram post URL. Golden: sharedContent (title/description/thumb name/text length),
  location, filePath. Record the HTTP responses once and replay.

### P6 — Selected text + page URL (Safari "share selection", A3)
- Entry: `load` :123–134 — text provider present alongside the URL → `type:"text"` with
  `url`/`urlTitle` riding along.
- Note: `SharedContent(type:.text, text: selection, url, urlTitle)`; `.captureText`. No
  enrichment (only `.url` type is enriched, :335). Compiler exports the `url:` key.
- Fixture: a Wikipedia paragraph selected in Safari. Golden: sharedContent.

### P7 — Plain text (String)
- Entry: `load` :148 → `loadText` :393 (String or UTF-8 Data) → `type:"text"`.
- Note: `.captureText`, text = shared string, annotation = typed thought, recordedAt =
  sharedAt. Empty/whitespace → the "unsupported" feedback state (A16), no husk.
- 🐛 Image + caption (WhatsApp photo with text): image branch (:143) runs before text and
  never collects the text → caption dropped (unverified on device; from :137–150).
- Fixture: a 2-paragraph text; a text containing a bare URL. Golden: sharedContent.

### P8 — Video share (Photos / Files)
- Entry: `load` :139 → `loadVideo` :274 (first `public.movie` provider only; a 2nd video is
  dropped) → slim sheet (thought + circles) → entry `type:"video"` → drainer :112–172 →
  `MemoSaver.importVideo` :283 → `processVideo` :316.
- Handling: placeholder memo inserted at once (`.transcribing`), then off-main: embedded
  `creationDate` → `recordedAt` (else the entry's `sharedAt`? no — `importVideo(from:)` is
  called WITHOUT a date, so fallback = now), audio track → `memo_<id>.m4a`
  (`AVAssetExportPresetAppleM4A`), ONE frame at ~1 s → `photo_<id>_001.jpg`,
  `imageManifest [{offsetSeconds 0}]` → `[[img_001]]` after the first word,
  `metadata.sourceType = "video"`, then transcribe. **Original video is NOT kept on the phone**
  (the Mac keeps `source.<ext>` since 2026-08-28, `IngestService.swift:117–137`).
- Failure titles: "Video had no audio track" / "Video format not supported"
  (`.avi/.mpg` accepted by extension, unreadable by AVFoundation).
- 🐛 Row glyph: `MemosListView.swift:1444` uses `SourceKind.of(memo)`, which reads the JSON key
  `mediaSource` (`SourceTaxonomy.swift:58`); the phone writes `metadata.sourceType`
  (`MemoSaver.swift:388`). Net: a phone video import classifies as `.voiceMemo` (mic glyph)
  in the list; only the exporter maps it (`MemoExporter.swift:84`). Unverified on device.
- Fixture: a short archive.org public-domain `.mp4` with speech and a `creation_time`, plus a
  `.mov` re-wrapped from Photos. Golden: memo (recordedAt = embedded date, transcript, manifest,
  sourceType, annotation, significance).

### P9 — Image(s) share (1..N, B2)
- Entry: `load` :143 → `loadImages` :345 (ImageIO thumbnail decode ≤2048 px, EXIF orientation
  baked, JPEG 0.85; EXIF date read from the ORIGINAL bytes) → `type:"image"` → drainer
  :415–447.
- Note: `.captureImage`; `photo_<memo>_00N.jpg` in provider order; `imageManifest` all
  `offsetSeconds 0`; annotation = typed thought + `[[img_001]]…[[img_00N]]` appended (one per
  line, :503–508); `recordedAt` = EARLIEST EXIF date else sharedAt (A4). `PhotoTextIndexer`
  OCRs them on the next sweep → `imageManifest[].text` (search).
- Multi: always ONE note, never a chooser. GIF flattened to a JPEG frame; PNG re-encoded lossy.
- Fixture: 3 JPEGs with distinct EXIF dates + 1 screenshot (no EXIF). Golden: manifest order,
  recordedAt = min EXIF, annotation markers.

### P10 — Document (PDF or any other file, incl. Files "share" of anything)
- Entry: `load` :154 → `loadFile` :171 (first provider conforming to pdf/data/file-url;
  copies the FILE, keeps `fileName` = original name, page count for PDFs, byte size) → slim
  sheet → `type:"file"` → drainer :378–413.
- Note: `.captureFile`; blob → `file_<memo>.<ext>` in recordings; `SharedContent(type:.file,
  filePath, fileName: original display name, mimeType)`; PDFs get `PDFTextExtract` into
  `sharedContent.text` (search only; scanned PDFs yield nothing). recordedAt = sharedAt.
- Fixture: an archive.org public-domain PDF (text layer) + one image-only scanned PDF + one
  `.docx`. Golden: sharedContent (fileName, mimeType, text length).

### P11 — `.txt` / `.md` file → note body (D4)
- Entry: either `loadText` receiving a URL :401–412 (Files hands a text file as a file URL)
  or `loadFile`; drainer :353–375: display name ends in `.md/.markdown/.txt`, ≤512 000 bytes,
  UTF-8 → the text becomes the annotation BODY (below any typed thought), no blob kept,
  `SharedContent(type:.text, fileName: display name)`.
- Oversized or non-UTF-8 → stays P10 file card.
- Fixture: an Apple-Notes-exported `.md` (heading + `Attachments/` refs). Golden: annotation
  body verbatim, `[[img]]`/`(Attachments/…)` refs untouched (the phone does NOT import the
  attachments folder — only the Mac does, M4).

---

## Phone — main app doors

### P12 — Open-in / AirDrop / Files "Open with" (`CFBundleDocumentTypes` → `.onOpenURL`)
- Entry: `SkriftApp.swift:79` → `AppURLHandler.handle` :16. Declared types
  (`project.yml:162–200`): audio (`public.audio, mp3, mpeg-4-audio, wav, aiff, aac-audio,
  m4a-audio, org.xiph.opus, public.mpeg-4`), video (`public.movie, public.video,
  public.mpeg-4, quicktime-movie`), Skrift Book (owner rank). `LSHandlerRank: Alternate`.
- Dispatch by EXTENSION: `.skriftbook(dev)` → P18; `mov mp4 m4v qt avi mpg mpeg 3gp 3g2` →
  `importVideo` (video-track probe is NOT done on the phone — an audio-only `.mp4` goes the
  video route and fails "no audio track"); `m4a mp3 wav aac caf aiff aif opus flac` →
  `importAudio`; anything else (`.ogg`, `.oga`, `.m4b`, `.pdf`) → silently ignored.
- Note: as P1/P8 but `recordedAt` = embedded date → **now** (no clip-date seed, no filename
  parse) and significance 0 (unrated). Jumps to the note.
- 🐛 Filename date lost: an AirDropped `signal-2026-04-13-18-15-24-552.aac` is dated to the
  import moment. Expected: filename date (Mac parity, `IngestService.dateFromFilename`).
- 🐛 `.ogg` accepted by the share extension (P2) but not by open-in; `.m4b` opens nowhere as a
  book (Books tab picker only).
- Fixture: same files as P1/P2 delivered via Files "Share → Skrift" (Open-in) and AirDrop.
  Golden as P1; note the recordedAt difference.

### P13 — In-app Import → "Audio or video from Files"
- Entry: `MemosListView.swift:327–333` `.fileImporter(allowedContentTypes: [.audio, .movie],
  allowsMultipleSelection: true)` → `AppURLHandler.handle` per URL (P12 rules).
- Multi: N files → N memos, **no combine chooser**, no ordering beyond the picker's return
  order, each jumps (last wins).
- Fixture: pick 3 clips at once. Golden: 3 memos, dates = embedded/now.

### P14 — In-app Import → "Video from Photos"
- Entry: `VideoImportPicker.swift:27` (PHPicker, `.videos`, limit 1, `.current`
  representation) → `MemoSaver.importVideo(from:creationDate: PHAsset.creationDate)` (only
  when Photos access is already granted; never prompts).
- Note: as P8 with the library date as fallback. Fixture: the P8 mp4 added to the sim Photos
  library. Golden as P8.

### P15 — In-app Import → "Scan a document" (device only)
- Entry: `DocScanView` (VisionKit) → `DocScanner.save` :49 → renders a PDF
  `file_<memo>.pdf`, Vision OCR → `sharedContent.text`, `fileName: "Scan d MMM yyyy, HH.mm.pdf"`,
  `mimeType: application/pdf`, significance 0, `.captureFile`. Not a corpus target (camera).

### P16 — Books tab → Add (audiobook files)
- Entry: `AudiobookLibraryView.swift:87` `.fileImporter([.audio, m4b], multi)` →
  `AudiobookImporter.importBook` :78.
- Single file: `book.<ext>`, tags via AVAsset (title/artist/album, iTunes keyspace fallback),
  cover → `cover.jpg`, embedded chapter track; missing title/author → confirm sheet
  pre-filled from the filename (`_`→space). Multi: files sorted `localizedStandardCompare`
  (2 before 10) → `NNN_<name>` parts, one chapter per file, title = first part's ALBUM tag
  else folder name; unreadable parts skipped and reported. Cloud placeholders materialised
  via `NSFileCoordinator`. Makes a BOOK.
- Fixture: one LibriVox `.m4b` with chapters; a folder of 3 `.mp3` parts with ID3 album tag.
  Golden: `Audiobook` JSON.

### P17 — Books → "Text…" → attach ePub / .txt
- Entry: `BookTextFlow.attachTypes` (`epub`, `.plainText`) → book text alignment. Attaches to
  a BOOK, no note. Fixture: the Gutenberg ePub of the P16 book. Golden: alignment verdict.

### P18 — `.skriftbook` arrival (AirDrop / Files / Messages)
- Entry: P12 → `BookBundle.isBookBundle` (extension `.skriftbook` prod / `.skriftbookdev`
  Debug) → `BookImportBridge.offer` (reads the manifest only) → `BookImportSheet` "Add to my
  books" → `BookBundle.unpack`. Makes a BOOK. Not a corpus target unless a second device is in
  the loop (device round still owed per memory).

### P19 — Native recording (Record button, Control Center, Lock Screen widget, Siri, `skrift://record`)
- Entry: `RecordControlWidget` / `RecordWidget.widgetURL(skrift://record)` /
  `StartRecordingIntent` → `RecordingIntentBridge` → recorder → `MemoSaver.save` :39
  (audio + photos taken DURING the recording, live caption as provisional transcript,
  location/weather metadata). Not an ingress of external content; listed so the matrix is
  complete. `StopRecordingIntent`, `ResumeAudiobookIntent` are controls, not ingress.

### P20 — Audiobook quote capture
- Entry: player capture → `MemoSaver.saveQuoteCapture` :496: memo with the quote audio,
  transcript = `QuoteFormatting.blockquote(quote)` (+ ramble appended later),
  `transcriptUserEdited: true` (Mac must not re-ASR), `bookTitle/Author/Chapter` metadata,
  `SourceKind = .audiobookQuote`. Corpus: derived from P16's book; golden = memo transcript.

### P21 — Typed note (✎ on phone/iPad, ⌘N on Mac)
- Entry: `Memo.newTyped` (`Memo.swift:362`): empty unrated memo, `transcriptStatus .done`,
  `metadataData {"mediaSource":"typed"}`, `recordedAt = now`. The ONE place the `mediaSource`
  key is written on the phone. Corpus: seed text via the editor; golden = memo body.

### (dead) Capture dictation
- `dictationFileName` on the entry is always nil now (`ShareSheetView.swift:770`); iOS blocks
  mic in extensions. `CaptureDictation.resumePending` only drains legacy entries.

---

## Mac — local doors (`Skrift_Native/SkriftDesktop/`)

Common to M1–M6: `SidebarView.ingest` :143 → `ArrivalPath.run` :57 → `IngestService.ingest`
:43 → one `PipelineFile` per file in `<audioOutputDirectory>/<id>_<filename>/original.<ext>`;
then the reconcile sweep's `MacMemoAuthor.backfill` authors the synced `Memo` (significance
floored to 0.1 for imports — an import is consent; audio blob attached as `MemoAsset`);
`ArrivalPath` backfills `uploadedAt` from `AudioMetadata.recordingDate` (embedded
`creationDate`). Unsupported extensions return nil SILENTLY (`ingestFile` :76) — no error, no
row: 🐛 dropping a PDF, image, ePub, `.flac`, `.ogg`, `.m4b`, `.webm`-audio or a URL on the Mac
does nothing visible. Expected: at least an honest "can't import <name>".

### M1 — "+ Add" panel
- `SidebarView.openUploadPanel` :132 — `NSOpenPanel`, files AND directories, multi.
  Message: "Add voice memos, audio files, or an Apple Notes folder".

### M2 — Drag-drop onto the sidebar
- `.dropDestination(for: URL.self)` :112 for Finder URL drags; `FilePromiseDropCatcher` :117
  for promised files (Photos, Mail, Safari) → temp folder, delivered sorted by
  `localizedStandardCompare`, then removed.

### M3 — Folder import
- `ingestFolder` :424: top-level only, sorted numerically, keeps `md/markdown` + supportedAudio
  (`m4a wav mp3 mp4 mov opus aac aiff caf`) + supportedVideo (`mov mp4 m4v qt avi mpg mpeg
  3gp 3g2 webm mkv`). Subfolders (an Apple Notes `Attachments/`) skipped as items.

### M4 — Apple Notes export (`.md` + `Attachments/`)
- `ingestNote` :169: copy → `original.md`; title = first `# ` heading (trailing dots trimmed)
  else filename stem; `importAttachments` :339 copies `<note dir>/Attachments/*` into the row's
  `Attachments/` as `"<safeTitle> - N.<ext>"` (HEIC/HEIF → JPEG via ImageIO), rewrites
  `(Attachments/<orig>)` refs (plain + percent-encoded); `transcript = body`,
  `transcribeStatus .done`, `enhancedTitle = title`, `sourceType .note` → `SourceKind
  .appleNote` on sync (no `mediaSource`). No date parse: `uploadedAt` = default (ingest time).
  🐛 Expected: the note's own date (Apple Notes exports carry none in the file; the export
  folder's file dates are all export-time — ❓ verdict needed on what date an Apple Note gets).
- Fixture: a synthetic Apple-Notes-shaped export folder: `Note A.md` (`# Title`, two
  paragraphs, `![](Attachments/IMG_0001.heic)`), `Attachments/IMG_0001.heic`. Golden:
  rewritten `original.md`, attachment names, title, transcript.

### M5 — Video file
- `ingestVideo` :109 (only if `hasVideoTrack`; audio-only `.mp4/.mov` → M6): audio →
  `original.m4a` (AVAssetExportSession), **source movie kept** as `source.<ext>` in the working
  folder (local only, never synced), frame at ~1 s → `images/img_001.jpg` +
  `image_manifest.json` (offset 0), `uploadedAt` = embedded date → filename date → file
  creation date → now, `mediaSource = "video"`, `sourceType .audio`, filename = the video's.
- Fixture: the P8 mp4. Golden: PipelineFile + folder listing + Memo (via backfill).

### M6 — Audio file
- `ingestAudio` :79: copy as `original.<ext>`; `uploadedAt` = `dateFromFilename` :208
  (`YYYY-MM-DD` + optional `HH.MM.SS`/`HH-MM-SS`, "at" allowed; noon when no time; covers
  WhatsApp, Signal, `AUDIO-2026-03-07-19-30-08`) → file `creationDate` → now; then embedded
  `creationDate` overrides in `ArrivalPath` :78–83. Filename KEPT as `PipelineFile.filename`
  (row title). Significance 0.1 floor on the authored Memo.
- Fixture: the P1/P2 files dropped on the Mac. Golden: `uploadedAt` per file (this is the
  reference behaviour the phone lacks), Memo recordedAt/significance.

### M7 — Mac Record button
- `ArrivalPath.run(asRecording: true)` :57: same ingest, `isLocalRecording` stamped at
  construction, Memo authored UNRATED before the sweep, location stamped, transcribed at once.
  Not external content.

### M8 — Headless harnesses (DEBUG, `Features/Shell/RunFile.swift`)
- `-runfile <audio> [-transcript <txt>] [-vocab "…"] [-vault <path>]` :508 — full pipeline on
  one file, PipelineFile id `runfile`, no store row.
- `-ingestfile <path>` :677 — `IngestService.ingest` + embedded-date backfill, prints
  `INGESTED id= filename= source=`. **This is the corpus driver for M4–M6.**
- `-recordingest <audio>` :720 — the Record-button path on an existing file.
- `-processfile <id> [-exportafter]` :996 — process (+export) an ingested row; prints the
  compiled text. Corpus: `-ingestfile` then `-processfile` = golden generator.
- Quit the GUI app first (shared store race).

### M9 — CloudKit ingest of phone notes (`MemoCloudIngest.ingest` :31)
- Not a door for external files, but the second half of every phone path: rated memos only
  (`NoteConsent.isRated`, or "process everything"); `buildParts` re-synthesises the phone's
  multipart → `UploadService`: audio memo → `.audio` row (trusted transcript skips ASR;
  `sourceType` key read for video); `sharedContent` present → `.capture` row
  (`prepareCapture`, annotation = transcript, images saved); no audio + no sharedContent →
  `.note` row (`prepareText`, `mediaSource "typed"` keeps the "Note" glyph). Photos added
  later are healed by `MemoPhotoMaterializer`. Unrated shares (significance 0 — the sheet's
  default) never reach the Mac queue.
- Corpus implication: every phone golden needs a rating > 0 or the Mac half never runs.

---

## Matrix — path × media type

| Media type | Share ext | Open-in / AirDrop | In-app Files/Photos | Mac +Add / drop / folder | Result |
|---|---|---|---|---|---|
| Voice note `.m4a/.mp3/.wav/.aac/.caf/.aiff/.flac` | P1 (audio UTI) / P2 (ext) | P12 | P13 | M6 (no `.flac`) | transcribed memo |
| `.opus` | P1/P2 | P12 | P13 | M6 | memo; on-device decode unverified |
| `.ogg/.oga` | P2 | ignored | ignored | ignored | memo (ext only) |
| N voice notes | P1 chooser 1/N (one item only) | n/a | P13 → N memos | M6 → N rows | see P1 🐛 multi-item |
| ≥1 h audio | P4 → Book | P12 → memo | P13 → memo | M6 → row | Book only via share |
| Voice notes + photos + text | P3 → one memo | n/a | n/a | n/a | marker after 1st word 🐛 |
| Video `.mov/.mp4/…` | P8 | P12 | P13 / P14 | M5 (keeps source) | memo, audio + 1 frame |
| Photo(s) | P9 → one memo | n/a | n/a | ignored 🐛 | image capture |
| Web URL | P5 (enriched on drain) | n/a | n/a | ignored | link capture |
| URL → PDF | P5.1 | n/a | n/a | ignored | file capture + text |
| Maps URL | P5.2 | n/a | n/a | ignored | link + location |
| YouTube / Instagram / TikTok URL | P5.3 generic | n/a | n/a | ignored | link card, no special case |
| Selected text + URL | P6 | n/a | n/a | n/a | text capture + url |
| Plain text | P7 | n/a | n/a | n/a | text capture |
| PDF / other document | P10 | ignored | n/a | ignored 🐛 | file capture (+PDF text) |
| `.txt/.md` file | P11 → body | n/a | n/a | M4 (`.md` only) | text note |
| Apple Notes folder | n/a | n/a | n/a | M3+M4 | `.note` rows |
| Audiobook `.m4b/.mp3` parts | P4 (≥1 h) | n/a | P16 | ignored | Book |
| ePub | ignored (P10 file card) | n/a | P17 | ignored | book text |
| `.skriftbook` | n/a (zip → P10 card 🐛?) | P18 | n/a | n/a | Book |
| Scan | n/a | n/a | P15 | n/a | file capture + OCR |
| Typed | n/a | n/a | P21 | M9/⌘N | typed note |

(`.skriftbook` via the share sheet is unverified: it conforms to `public.zip-archive` →
`public.data`, so the extension would offer Skrift and save a dead file card.)

---

## Where the earlier surveys are out of date

- `SHARE_INGEST_SURVEY.md` A5/A13: video and documents "silent import, no sheet" — retired
  2026-07-12; both get the slim sheet (`ShareViewController.swift:56–67`). A7/A8/A9/A11/A12/
  A14/A16, B1/B2/B3, C4/C5, D4/D6/D7/D8, E1/E2/E3 are built as described above.
- Survey never listed: P2 (extension-fallthrough audio was folded into D7 but only for ONE
  clip), P11 arrival via `loadText` URL, P13's "N files → N memos, no chooser", P15 doc scan,
  P16/P17/P18 book doors, P20/P21, the Mac harnesses (M8), M9 rating gate, Mac video
  source-keep (2026-08-28). The survey's B3-round-2 multi-item finding is still open in code.
- `CAPTURE_CONTRACT.md`: wire shape says `POST /api/files/upload` multipart — Bonjour is
  retired; the same parts are now SYNTHESISED from the synced Memo (`MemoCloudIngest.buildParts`).
  `sharedContent` gained `urlDescription`/`urlThumbnailUrl` population (C4) and a `text` use
  for PDFs/articles; `imageManifest` may have N entries; the "title ABSENT" rule holds; the
  "significance present and > 0" invariant is now the rating gate on the Mac side.
- Backlog ingress plan (backlog.md:618–637) says "the jank is the title/page-text fetch on
  JS-rendered pages" — true, plus the four code-level items above (multi-item `.first`, share
  time as date, image caption drop, video glyph key drift).

---

## Needs verdict (only Tuur)

1. YouTube URL → link card with the fetched title/thumbnail (today), or fetch audio + local
   transcribe (desktop only per C1)? Same answer for a YouTube link shared as text.
2. Instagram/TikTok URL → link card with og title/description (caption) as the note body, or
   just the card?
3. A shared picture with no timestamp in a mixed bundle: marker at the TOP of the note, the
   BOTTOM, or at the start of the clip it was selected next to?
4. Multi-audio WhatsApp thread: keep the chooser (one note default) — and when WhatsApp ships
   them as multiple extension items, same chooser once flattened?
5. Date for a shared/AirDropped voice note whose container has no date: parse the filename
   (WhatsApp/Signal/Telegram patterns, Mac parity) or keep share time?
6. Date for an Apple Notes `.md` import (file has none): export time, or a `Created:` line if
   the export ever carries one?
7. Mac drop of a PDF / image / URL / ePub / `.flac`: honest refusal, or should the Mac grow the
   phone's capture types?
8. A WhatsApp photo shared WITH a caption: caption → annotation (like B3 text), or ignore?
9. An audio-only `.mp4` opened on the phone: probe for a video track (Mac behaviour) instead
   of failing "no audio track"?
10. Unrated shares (sheet default 0) never reach the Mac: should the corpus goldens assume a
    rating, or should a share default to 0.1 like a Mac import?
