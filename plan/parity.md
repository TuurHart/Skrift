# Parity tables — sync + verb + ingress asymmetries (2026-09-22)

Scope: `f150455a` worktree. Cell = carrying function (`path:line`), `—` (candidate bug —
searched, found no writer), or `deliberately not (reason)`. iPad runs the same
`SkriftMobile` target as iPhone (universal app, `TARGETED_DEVICE_FAMILY: "1,2"`,
`project.yml:227`) — no separate iPad sync code exists, so iPad↔Mac cells cite the
identical phone↔Mac function unless a real divergence was found. phone↔iPad is native
SwiftData/CloudKit field sync of the shared `Memo`/`MemoAsset`/`MemoEnhancement` rows (no
carrier code needed) except where a device-local file (audio/photo/sidecar) needs
`AssetMaterializer` to write the synced blob to disk.

Confidence note: rows 26–29 (custom vocab, names roster, language mode, polish prompts)
are confirmed to exist on both apps via shared `Shared/Pipeline/*Core.swift` + per-app
sync files, but the exact writer line-numbers were not traced this pass — marked
"carried, not line-verified."

---

## TABLE A — data × origin → destination

| Data | phone→Mac | Mac→phone | iPad→Mac | Mac→iPad | phone↔iPad |
|---|---|---|---|---|---|
| transcript text | `MemoCloudIngest.buildParts` (transcript part) Pipeline/Ingest/MemoCloudIngest.swift:140-143; edits via `MemoCloudUpdate.apply` path 3, Pipeline/Ingest/MemoCloudUpdate.swift:99-103 | deliberately not, for a phone-owned memo (C95: Mac never writes `Memo.transcript`, only `MemoEnhancement`) — Mac's OWN recordings/imports: `MacMemoAuthor.markTranscribed` Pipeline/Ingest/MacMemoAuthor.swift:189-193, `reflectTranscripts` :111-131 | same as phone→Mac | same as Mac→phone | native `Memo.transcript` field sync |
| transcript status/confidence/userEdited | `MemoCloudIngest.metadataJSON` (dict keys) Pipeline/Ingest/MemoCloudIngest.swift:250-252, read by `UploadService`'s trust gate | deliberately not (own-authored only, `markTranscribed` :189) | same | same | native field sync |
| word timings | `AssetMaterializer.captureFile` (wt_&lt;id&gt;.json → `MemoAsset.Kind.wordTimings`) Services/AssetMaterializer.swift:112-113; `buildParts` wordTimings part Pipeline/Ingest/MemoCloudIngest.swift:146-149; late-heal `adoptLateWordTimings` :186-200 | **— (the seeded bug).** `MacMemoAuthor.author` attaches only the audio `MemoAsset` (Pipeline/Ingest/MacMemoAuthor.swift:90-93); `MacCloudWriteBack.upsert` only ever writes a `MemoEnhancement` (copyedit/title/summary), never a `MemoAsset` (Pipeline/Ingest/MacCloudWriteBack.swift:78-115) — so a Mac re-transcription's `pf.wordTimings` (`BatchRunner.swift:63`) is equally stranded, not just a Mac recording's | same as phone→Mac | — (same gap — no writer exists at all, so iPad inherits it too) | carried, `AssetMaterializer` both directions |
| diarization segments + slot names | `AssetMaterializer.captureFile` (diar_&lt;id&gt;.json) Services/AssetMaterializer.swift:114-115; `buildParts` diar part Pipeline/Ingest/MemoCloudIngest.swift:150-153; `adoptLateDiarization` :210-228 | **—.** Mac diarizes (`DiarizationService`, `BatchRunner.swift:75-83`) but no code path creates a `MemoAsset.Kind.diarization` for CloudKit — grepped `Kind.diarization` + `MemoAsset(` across `SkriftDesktop`, only the read side (`MemoCloudIngest`/`MemoCloudReconciler`) exists | same as phone→Mac | — (same gap) | carried, `AssetMaterializer` both directions |
| photos (files + manifest incl. OCR) | `AssetMaterializer.captureFile` per manifest entry Services/AssetMaterializer.swift:99-102; `buildParts` images parts Pipeline/Ingest/MemoCloudIngest.swift:156-161; late-heal `MemoPhotoMaterializer.materializeMissing` (called from `MemoCloudReconciler.swift:113`); OCR text via `MemoCloudIngest.ocrText` :88-93 | deliberately not — Mac has no camera; `MacMemoAuthor` never builds an `ImageManifestEntry` or photo `MemoAsset` (CLAUDE.md: "you cannot take a bare picture in Skrift — the camera lives inside a recording") | same as phone→Mac | deliberately not | carried, `AssetMaterializer` + native `imageManifest` field |
| document (PDF/file) | `AssetMaterializer.captureFile` for `sharedContent.filePath` Services/AssetMaterializer.swift:105-107; `buildParts` document part Pipeline/Ingest/MemoCloudIngest.swift:165-168 | deliberately not / structurally impossible — `SourceType` on the Mac has only `.audio .note .capture` (Models/PipelineFile.swift:19), no standalone document import exists to author one | same as phone→Mac | same as Mac→phone | carried, `AssetMaterializer` |
| audio | `buildParts` files part Pipeline/Ingest/MemoCloudIngest.swift:133-136 | `MacMemoAuthor.author` MemoAsset(Kind.audio) Pipeline/Ingest/MacMemoAuthor.swift:90-93 | same | same | native + `AssetMaterializer` |
| sharedContent | `metadataJSON` sharedContent passthrough Pipeline/Ingest/MemoCloudIngest.swift:261-264 | deliberately not — no Mac capture-equivalent writes `sharedContentData` | carried (iPad has the same share surface) | deliberately not | native field sync |
| annotation | `metadataJSON` "annotationText" Pipeline/Ingest/MemoCloudIngest.swift:258 | **—** — no Mac writer sets `memo.annotationText` found (grepped `annotationText` in SkriftDesktop: read-only in ingest/projection) | carried | — | native field sync |
| title (user) | adopt-only `MemoCloudUpdate.apply` path 2b Pipeline/Ingest/MemoCloudUpdate.swift:93-97; first-ingest `metadataJSON` "title" :253-255 | `MacCloudMetaSync.setTitle` (event-driven) App/MacCloudMetaSync.swift:96-112 | same | same | native `Memo.title` field |
| title (suggested) | N/A (phone never suggests) | `MacCloudWriteBack.upsert` → `enhancement.title` Pipeline/Ingest/MacCloudWriteBack.swift:88,106-107 | `PolishCenter.write` → `enhancement.title` Services/Polish/PolishCenter.swift:370-372 | same as Mac→phone | native `MemoEnhancement.title` |
| summary | N/A | `MacCloudWriteBack.upsert` :89,107 | `PolishCenter.write` :371 | same | native |
| copy-edit | phone edits `MemoEnhancement.copyedit` directly (shared CloudKit row, native field write) reflected by `MemoCloudUpdate.apply` phoneEnh branch Pipeline/Ingest/MemoCloudUpdate.swift:76-79 | `MacCloudWriteBack.upsert` :106; live edits debounced via `MacCloudEditSync.flush` App/MacCloudEditSync.swift:51-59 | same as phone→Mac (+ `PolishCenter.redo`) | same | native |
| tags | `MirroredNoteFields` "tags" pull+adopt Pipeline/MirroredNoteFields.swift:56-74 | `MirroredNoteFields` "tags" push :62-66 via `MacCloudMetaSync.mirror` App/MacCloudMetaSync.swift:39-52 | same code | same | native `Memo.tags` |
| rating | `MirroredNoteFields` "significance" pull Pipeline/MirroredNoteFields.swift:77-81 | event-only: `MacCloudMetaSync.setRating` App/MacCloudMetaSync.swift:61-68 (passive mirror deliberately skips nil, :82-92) | same (iPad edits `Memo.significance` directly; reaches Mac via the same sweep pull) | same as Mac→phone | native `Memo.significance` |
| destination | `MirroredNoteFields` "destination" pull Pipeline/MirroredNoteFields.swift:97-102 | event-only: `MacCloudMetaSync.setDestination` App/MacCloudMetaSync.swift:74-80 | same | same | native |
| lock | `MirroredNoteFields` "locked" pull :106-111 | deliberately not — comment at Pipeline/MirroredNoteFields.swift:104-105 ("the Mac has no control that writes either one"); confirmed no setter in `NoteProperties.swift` (display-only, line 86-area shows `remindAt`; no `locked =` assignment found in SkriftDesktop) | carried (iPad locks → syncs to Mac via same pull) | deliberately not | native |
| reminder | `MirroredNoteFields` "remindAt" pull :113-118 | deliberately not — same comment; `NoteProperties.swift:86` only reads `file.remindAt`, no setter found | carried | deliberately not | native (C92: each device derives its own local alarm) |
| trash (deletedAt/trashSeenAt) | `MemoCloudUpdate.apply` trash mirror, watermarked Pipeline/Ingest/MemoCloudUpdate.swift:46-57 | `MacCloudDeleteSync.mirror` App/MacCloudDeleteSync.swift:23-44 | same | same | native + `MemoLifecycle.stampTrashSightings` per-device |
| keptAt | deliberately not — no `MirroredNoteFields` entry; not read anywhere under `SkriftDesktop/Pipeline/Ingest` (grepped) | deliberately not — no Mac writer found | same | same | native `Memo.keptAt` (shared `MemoLifecycle.swift` runs identically on iPhone/iPad) |
| createdAt/editedAt | partial — `editedAt` drives the `syncedSourceEditedAt` watermark (`memo.lastEditedAt`) Pipeline/Ingest/MemoCloudUpdate.swift:141; `createdAt` is NOT mirrored onto `PipelineFile` (`uploadedAt` is set to ingest time, a different field) | deliberately not (C47: reflect is content-based, not date-authored, by the Mac) | same | same | native |
| name resolutions | deliberately not — doc comment, Shared/Model/Memo.swift:162-164 ("the Mac's CloudKit ingest ignores this field") | deliberately not (Mac keeps its own `unlinkedNames`/`namePicks` on `PipelineFile`) | same | same | native `nameResolutionsData` (same app both ends) |
| recordingDeviceID | carried natively — plain `Memo` field, visible to the Mac's `MemoCloudReconciler` sweep directly off the CloudKit row (not through the multipart shim) | `MacMemoAuthor.author` stamps `recordingDeviceID: DeviceID.current()` Pipeline/Ingest/MacMemoAuthor.swift:77 | same | same | native |
| sourceType/mediaSource | carried — `metadataJSON` passes `memo.metadataData` through verbatim Pipeline/Ingest/MemoCloudIngest.swift:241-244 | **partial —.** `MacMemoAuthor.author` never writes any `MemoMetadata` (Pipeline/Ingest/MacMemoAuthor.swift:59-97 has no `memo.metadata =`); only `MacLocationStamp.stamp` sets one, and only `.location` (see below). A Mac **video** import (`IngestService.ingestVideo`, Pipeline/Ingest/IngestService.swift:109) never gets `MemoMetadata.sourceType = .video` on its authored `Memo`, so it syncs to the phone as an ordinary voice memo — no video glyph | same as phone→Mac | same partial gap | native |
| location/weather metadata | carried — full `MemoMetadata` blob passthrough (location/weather/pressure/dayPeriod/daylight/steps) | **partial.** Location only, recordings only: `MacLocationStamp.stamp` Pipeline/Ingest/MacLocationStamp.swift:41-56, deliberately scoped ("RECORDINGS ONLY, never imports", doc :14-19). Weather/pressure/dayPeriod/daylight/steps are never stamped by the Mac at all — no writer found | same as phone→Mac | same partial gap | native |
| custom vocab | carried, not line-verified — `SkriftMobile/Services/VocabularyCloudSync.swift` ↔ `SkriftDesktop/App/VocabularyCloudSync.swift`, both over shared `Shared/Pipeline/VocabularySyncCore.swift` | carried, not line-verified (same files, whole-list LWW per C103) | same code | same | native (same `VocabularyRecord`) |
| names roster | carried, not line-verified — `Shared/Naming/NamesStore.swift` compiled into both apps, LWW merge per C50 | carried, not line-verified | same | same | native |
| language mode | carried, not line-verified — `Shared/Pipeline/LanguageSyncCore.swift` + `LanguageSyncCoreTests` (spec C217) | carried, not line-verified | same | same | native |
| polish prompts | carried, not line-verified — `PolishPrompts` shared source, referenced by both `EnhancementService.swift:36` (Mac) and the mobile polish engine; override-blob sync file not located this pass | carried, not line-verified | same | same | native |

---

## TABLE B — verbs × device

| Verb | iPhone | iPad | Mac |
|---|---|---|---|
| record | `MemoSaver.save` Features/Recording/MemoSaver.swift:39 | same (universal target) | `MacMemoAuthor.author` (from the Record button / `LiveRecordingSession`) Pipeline/Ingest/MacMemoAuthor.swift:59; ingress M7 |
| append | `MemoSaver.appendRecording`/`appendRecordingAsync` Features/Recording/MemoSaver.swift:560-671 | same | **—** no "add a follow-up recording" verb found on the Mac (grepped `append` in SkriftDesktop Features — none) |
| import audio | `MemoSaver.importAudio` :68, `importAudioClips` :126 (share P1/P2, in-app P13) | same | `IngestService.ingestAudio` Pipeline/Ingest/IngestService.swift:79 (M6) |
| import video | `MemoSaver.importVideo` :283 / `processVideo` :316 | same | `IngestService.ingestVideo` :109 (M5, keeps source video per ingress.md) |
| import photo | `CaptureInboxDrainer` image branch Services/Capture/CaptureInboxDrainer.swift:426-452 (P9) | same | **—** ingress.md's own matrix marks a photo dropped on the Mac "ignored 🐛" |
| import PDF/file | `CaptureInboxDrainer` file branch :383-403 (P10) | same | **—** ingress.md matrix: "ignored 🐛" for Mac +Add/drop of a PDF/document |
| import URL | `CaptureInboxDrainer` url branch :292-355 (P5) | same | — (no Mac URL-import surface; plausible/deliberate — desktop apps don't receive share-sheet URLs — but no clause cites it) |
| import text/.md | `CaptureInboxDrainer` text-file branch :357-377 (D4/P11) | same | `IngestService.ingestNote` Pipeline/Ingest/IngestService.swift:169 (M4, .md only) |
| import Apple Notes folder | — (no equivalent) | — | `IngestService.ingestFolder` :431 + `ingestNote` :169 (M3+M4) |
| import audiobook | `AudiobookImporter.importBook` (via `CaptureInboxDrainer` :229, or Books tab Add / ePub attach, P16/P17) | same | deliberately not — audiobooks are phone-player-only (C104 "Skrift is the player"); no Mac audiobook import found |
| typed note | `Memo.newTyped` Shared/Model/Memo.swift:362 (✎) | same | `MacMemoAuthor.typedNote` Pipeline/Ingest/MacMemoAuthor.swift:166-168 (⌘N) |
| rate | native `Memo.significance` write (circles UI) | same | `MacCloudMetaSync.setRating` App/MacCloudMetaSync.swift:61-68 |
| lock | native `Memo.locked` toggle | same | **—** Mac only displays lock state (`SidebarView`, `Features/Shell/Snapshot.swift`); no setter found — flagged, no cited reason |
| remind | native `Memo.remindAt` setter | same | **—** `NoteProperties.swift:86` display-only; no setter found |
| trash | native `Memo.deletedAt = now` | same | `DesktopTrash` → mirrored by `MacCloudDeleteSync.mirror` App/MacCloudDeleteSync.swift:23-44 |
| restore | native `Memo.deletedAt = nil` | same | same `DesktopTrash`/`MacCloudDeleteSync` path |
| purge | device-local 14-day sweep, `TrashPolicy.retentionDays` (Shared/Model/Memo.swift:21-25) | same | device-local purge — "permanent removal stays device-local", doc comment App/MacCloudDeleteSync.swift:13-16 |
| process/polish | deliberately not — `PolishGate.isSupported` explicitly excludes iPhone, Services/Polish/PolishCenter.swift:58-76 ("the iPhone never polishes") | `PolishCenter.polishNow` :163-175 (≥6GB RAM gate) | `ProcessingCoordinator.process` Features/Shell/ProcessingCoordinator.swift:93 |
| redo | — (no PolishCenter) | `PolishCenter.redo`/`runRedo` :182-222 | `ProcessingCoordinator.redo` :415 |
| re-transcribe | **—** no user-facing re-transcribe found (only automatic recovery of orphaned `.transcribing` memos, `recoverStuckTranscriptions`) | same as iPhone — **—** | `ProcessingCoordinator.retranscribe` :366 |
| split speakers / flatten | `MemoSaver.diarizeExisting` (split only, no flatten) Features/Recording/MemoSaver.swift:886 | same | automatic diarization during Process (`ProcessingCoordinator` diarizer :64, `BatchRunner.swift:75-83`) + `ProcessingCoordinator.flattenToMonologue` :393 (flatten only — no separate manual re-split verb beyond re-transcribe) |
| name link/unlink/add person | per-note `nameResolutionsData` (`namePicks`/`unlinkedNames`), `Sanitiser.nameSpans`, phone-display-only per Shared/Model/Memo.swift:155-164 | same | `pf.unlinkedNames`/`namePicks` read by `MemoCloudUpdate.resanitiseAndCompile` Pipeline/Ingest/MemoCloudUpdate.swift:150-163; roster add via shared `NamesStore` |
| export to vault | `ObsidianPublisher.publish` Services/Export/ObsidianPublisher.swift:131, gated by `PublishCoordinator` (opt-in + processed-only) | same | `VaultExporter.export` Pipeline/Export/VaultExporter.swift:74 |
| export to archive | `ArchiveVault.folder(for:)` Services/Export/ArchiveVault.swift:40 (exact publish call not fully traced this pass) | same | `VaultExporter.archiveFolder` Pipeline/Export/VaultExporter.swift:40 (same `export` fn, destination-branched) |
| re-export | `PublishCoordinator` re-runs per policy each launch/foreground; content-hash idempotent (`ObsidianPublisher` doc) | same | auto re-export after a sweep, vault-only notes — `App/MemoCloudReconciler+Wiring.swift:167` calling `VaultExporter.export` (C189) |
| share out | `BookBundle`/`BookBundleManifest` (Services/Audiobooks/) — book-sharing feature | same | deliberately not — Mac isn't the audiobook player; no Mac equivalent found |
| fix quote | not located precisely — inferred to be an ordinary transcript edit inside the blockquote lines in `MemoDetailView`'s editor (no dedicated "Fix quote" function found by name); `QuoteProtection` (Shared/Naming/QuoteProtection.swift) only PROTECTS the quote during LLM copy-edit, it isn't the fix UI | same, unverified | **—** no Mac UI to correct a captured quote's text found |

---

## TABLE C — ingress types × door × device (asymmetries only)

Full door-by-door detail already lives in `plan/extraction/ingress.md` (matrix at line
388). Reusing it, flagging only the asymmetric rows:

| Media type | Phone (share/open-in/in-app) | Mac (+Add/drop/folder) | Asymmetry |
|---|---|---|---|
| Photo(s) | P9 → one memo | **ignored 🐛** | Mac drop of a photo makes nothing |
| PDF / other document | P10 → file capture + text | **ignored 🐛** | Mac drop of a document makes nothing |
| Web URL / Maps / YouTube-etc URL | P5/P5.1/P5.2/P5.3 → link capture | ignored | No Mac URL-import surface (plausible-but-uncited) |
| `.ogg`/`.oga` | P2 (extension-routed) → memo | ignored | Mac audio import doesn't recognize ogg by extension |
| `.flac` | recognized (P1/P2/P13) | **M6 explicitly excludes `.flac`** | cited in the matrix itself |
| `.skriftbook` | P18 (Open-in) works; share-sheet path unverified — conforms to `public.zip-archive`→`public.data`, so it may land as a dead P10 file card | n/a | Same-device asymmetry, not phone/Mac — flagged in ingress.md itself |
| Voice notes + photos + text bundle (P3) | one memo, marker after 1st word (jank, not a gap) | n/a | Mac has no share surface at all — not comparable |
| N voice notes (multi-select) | P1 chooser only reads `inputItems.first` — WhatsApp multi-select loses all but one item (🐛, ingress.md P1) | M6 → N rows (no such loss) | Share-extension-only bug, phone-side |

---

## EMPTY CELLS — bug candidates

Table A:
1. **Word timings, Mac→phone/iPad — real bug (the seeded one + broader than reported).** `MacMemoAuthor.author` (Pipeline/Ingest/MacMemoAuthor.swift:90-93) attaches only the audio `MemoAsset` for a Mac recording. But the gap is bigger: `MacCloudWriteBack.upsert` (Pipeline/Ingest/MacCloudWriteBack.swift) writes only `MemoEnhancement`, never a `MemoAsset` — so even a Mac **re-transcription of an untrusted phone memo** (`BatchRunner.swift:63` sets `pf.wordTimings`) never reaches the phone either. Expected: a writer that pushes `pf.wordTimings` as a `MemoAsset.Kind.wordTimings` back to CloudKit, on both authoring and re-transcription. Fix point: new function alongside `MacCloudWriteBack.upsert`, called from `MacMemoAuthor.author`/`reflectTranscripts` and from `ProcessingCoordinator` after a re-ASR.
2. **Diarization segments + slot names, Mac→phone/iPad — same shape as #1.** Mac diarizes (`BatchRunner.swift:75-83`, `DiarizationService`) but no code creates a `MemoAsset.Kind.diarization` for CloudKit. Expected: a phone-diarized OR Mac-diarized conversation should karaoke/show turns on every device; today only phone-authored diarization crosses. Fix point: same new writer as #1, keyed off `pf.diarizationSegments`.
3. **Mac video import → sourceType never reaches the phone.** `MacMemoAuthor.author` sets no `MemoMetadata` at all (Pipeline/Ingest/MacMemoAuthor.swift:59-97); `IngestService.ingestVideo` (:109) never gets its `.video` marker relayed onto the authored `Memo`. Expected: a Mac video import shows the video glyph everywhere, same as a phone video import. Fix point: `MacMemoAuthor.author`, set `memo.metadata = MemoMetadata(sourceType: .video)` when `pf.sourceType == .audio && pf.mediaSource == "video"`.
4. **Weather/pressure/daypart/daylight/steps never stamped by the Mac.** `MacLocationStamp` (Pipeline/Ingest/MacLocationStamp.swift) deliberately scopes to `location` only, per its own doc — likely a real, small, unfinished slice of the 2026-08-27 parity ask ("Mac should also have location, same as the phone and iPad") rather than an oversight, but the doc never says weather was deferred on purpose. Worth a verdict from Tuur.
5. **Photo / PDF import via Mac +Add or drag-drop — ingested nowhere.** Confirmed by `ingress.md`'s own matrix (both marked 🐛). Not traced further this pass (no `SourceType.document`/`.photo` case exists on `PipelineFile` at all — `enum SourceType { case audio, note, capture }`, Models/PipelineFile.swift:19).
6. **Lock and reminder, Mac→phone — no setter exists.** `NoteProperties.swift` only displays `remindAt`/`locked`; `MirroredNoteFields` explicitly documents both as phone-authored only (Pipeline/MirroredNoteFields.swift:104-105) but doesn't say why a reviewer on the Mac can't lock/remind a note they're looking at. Candidate UX gap, not obviously a bug.
7. **Annotation, Mac→phone — no writer found.** Grepped `annotationText` across `SkriftDesktop`: read-only. Low-impact (annotation is a phone-capture-sheet concept the Mac has no equivalent UI for), but nothing documents the omission as deliberate.

Table B:
8. **Append recording — Mac has no verb.** No "add a follow-up recording to an existing note" found anywhere under `SkriftDesktop/Features`. A Mac-side note can only be re-recorded from scratch or edited as text.
9. **Re-transcribe — phone/iPad have no verb.** Only automatic orphan-recovery (`recoverStuckTranscriptions`) exists; the Mac's `ProcessingCoordinator.retranscribe` (:366) has no mobile counterpart. Plausibly deliberate (phone transcribes once, on-device, at capture; Mac re-transcribes only when the phone's transcript is untrusted) but the row is worth a citation in SPEC if it isn't already.
10. **Import photo / import PDF on the Mac — no entry point**, matching Table A finding #5.
11. **Share out (book bundle) — Mac has none.** Consistent with "Skrift is the player" (C104) but never stated for the export/share verb specifically.
12. **Fix quote — Mac has no equivalent**, and the phone-side function wasn't precisely located (inferred, not confirmed) — worth a direct look before trusting this row.

---

## Summary

- **Path:** `plan/parity.md`
- **Table A:** 29 data rows × 5 columns. Empty/one-way cells: **12** (word timings Mac→phone/iPad ×2, diarization Mac→phone/iPad ×2, sourceType-on-video-import ×2, weather/pressure/etc ×2, photo Mac→phone/iPad ×2, document Mac→phone/iPad ×2, lock Mac→phone ×1, reminder Mac→phone ×1, annotation Mac→phone ×1 — several rows recur across the iPad column since iPad shares the same gap).
- **Table B:** 27 verb rows × 3 columns. Empty cells: **9** (append/Mac, import photo/Mac, import PDF/Mac, import URL/Mac, re-transcribe/phone+iPad ×2, lock/Mac, remind/Mac, share-out/Mac, fix-quote/Mac).
- **Table C:** reused `plan/extraction/ingress.md`'s matrix; **4** asymmetric rows beyond what it already flags as jank.

### The 8 most consequential findings
1. Word timings never reach the phone/iPad for ANY Mac-produced transcript (own recordings AND Mac re-transcriptions of untrusted phone memos) — `MacCloudWriteBack` has no asset writer at all.
2. Diarization has the identical gap — a Mac-diarized conversation never shows speaker turns on the phone/iPad.
3. Mac video imports lose their video glyph on every other device — `MacMemoAuthor.author` writes no `MemoMetadata`.
4. Dropping a photo or a PDF/document on the Mac (+Add / drag-drop) silently does nothing — no `SourceType` case exists for either.
5. Weather/pressure/daypart/daylight/steps are never captured for a Mac recording, only location — needs a verdict on whether that's the intended scope of the 2026-08-27 fix.
6. Nothing lets you append a follow-up recording to an existing note on the Mac.
7. Lock and Reminder are one-way (phone/iPad → Mac only) with no stated reason a Mac reviewer can't set either.
8. Sharing a book (`.skriftbook`) out has no Mac equivalent, consistent with "Mac isn't the player" but never stated for this verb specifically.
