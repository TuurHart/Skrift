# Data-loss sweep — merged

2026-09-22. Scope: `Skrift_Native/{SkriftMobile,SkriftDesktop,Shared}` end to end — every
Feature/Service/Pipeline file across mobile, desktop, and shared code, plus a dedicated
capture-path scenario probe (`plan/scenarios-capture.md`). Method: per-file destructive-operation
table on Sonnet (11 lane reports + the capture probe), each row tracing a `removeItem`/nil-out/
overwrite to its guard (or lack of one) and its trigger. Helpers: `aa7e6a5c` MemoDetailView,
`a245dffd` MemosListView+WayOutView, `a381c992` MemoDetail body/connections, `ac24e468` MemoDetail
sheets+Import+Onboarding, `a90a385a` Recording+Feedback, `a6ee1934` Settings+Names, `a5e06d3a`
Journal+Root, `a9edcbf4` Audiobooks UI A, `a679e2cf` Audiobooks UI B, `af2965fa`
Services/Audiobooks+Capture, `ad17c703` Desktop, `a479987` Shared, `a283505d` mobile
Services/Recording+misc.

Every row below cites a file:line a report actually read. "Already tracked" = an existing
`SPEC.md` R-row or `BUGS.md` bullet; those are not re-rowed here, see the bottom section.

## Ranked candidates (most silent + most permanent first)

| # | path:line | what is lost | why silent | trigger | tracked? |
|---|---|---|---|---|---|
| 1 | `RecordView.swift:502-505` → `LiveRecordingService.cancel()` + `PhotoCaptureService.discardAll()` | the whole in-progress recording + every captured photo | zero confirm dialog on a single tap of the X | tap X while recording | NEW |
| 2 | `MemoSaver.swift:573-671` (`appendRecordingAsync`) races `MemoSaver.swift:792-837` (`runTranscription`) | the appended text, if the original pass's `save()` lands second — its source clip is already deleted | `MemoDetailView.swift:92` "Add recording" has no gate on `transcriptStatus`; both writers unordered | append started while original still transcribing | NEW |
| 3 | `MemoSaver.swift:602` merge failure in the same append path | the appended audio (text is kept) | no log line, unlike every sibling failure in the file | audio merge throws mid-append | NEW |
| 4 | `Shared/Export/VaultWrite.swift:391-407` `writeAsset` `.file` branch | an existing attachment in the user's Obsidian vault | unconditional `removeItem` then `copyItem`, no ownership/stamp check — inside the SHARED engine both apps trust | any re-export where markdown text changed (assets loop isn't skipped) | NEW (same shape as D3, different file — D3 is Desktop-only `VaultExporter.swift`) |
| 5 | `Skrift_Native/SkriftMobile/Services/Audiobooks/Audiobook.swift:500-504,556-601` | the ENTIRE audiobook library index | corrupt `library.json` decodes to `[]`, kept in memory, then `persist()` writes it back over the real file on the next import | any new book import after `library.json` was ever corrupted | NEW (same shape as D1/R59, new file) |
| 6 | `SkriftDesktop/Models/AppSettings.swift:150-176` | ALL Desktop settings (`customVocabulary`, `archiveRoot`, `noteFolder`, `prompts`) | non-atomic write + decode-failure silently returns `freshDefault`, which the very next autosave (`VocabularyCloudSync`/`PolishPromptsCloudSync`) writes back over the real file | crash/power-loss mid-`settings.json` write, then any background sync tick | NEW (same shape as D1/R59, new file) |
| 7 | `NoteBodyView.swift:1182-1190` (raw) + `:1173-1175` (polished) `commitDraft` | the raw transcript (nilled) or the Mac's polished copy-edit (blanked to `""`, no guard at all) | debounce-commits on any edit that nets to empty; no confirm | select-all + delete in the editor | NEW |
| 8 | `MemoDetailView.swift:1738-1748` `polishedBinding` setter | same target as #7, from the write side | unconditional `e.copyedit = newValue`, no empty/no-op guard, unlike every transcript setter in the same file | a render race or the #7 commit path | NEW (same bug as #7, two vantage points) |
| 9 | `MarkupQuickLook.swift:77-80` `.updateContents` | the original (pre-markup) photo file | writes markup edits into the same file at `url`, no copy taken first | annotate a photo with Markup, dismiss | NEW |
| 10 | `MemoSaver.swift:864-880` `recoverStuckTranscriptions` | a diarized/hand-edited transcript's turn structure | no `transcriptUserEdited` check before blindly re-running plain transcription | app killed mid-append on an already-diarized note, next launch | NEW |
| 11 | `Skrift_Native/SkriftMobile/Services/Audiobooks/CaptureInboxDrainer.swift:150` (video), `:221` (audio), `:383-403,531` (file) | a shared item's audio/video/document | inbox entry deleted BEFORE the import call is confirmed to succeed; on failure the copy lands in plain `temporaryDirectory`, never revisited | any shared import whose `importVideo`/`importAudioClips`/copy fails after the delete | NEW |
| 12 | `PersonEditorView.swift:218-223`, `PersonDetailView.swift:116-120` (iOS); `PersonEditor.swift:102-109`→`SettingsView.swift:55-59` (Mac) | a person's voice enrollment (`voiceEmbeddings`) | tombstone built in `writeWithSmartBumps` never carries `voiceEmbeddings` forward (contradicts C259's "voiceprints go with the tombstone"); zero confirmation on any of the 4 entry points | one click "Delete person" | NEW |
| 13 | `CustomWordsView.swift:39-43,63` (mobile UI) + `Shared/Pipeline/VocabularySyncCore.swift:43-48` (sync) | a word added on a second device while the first was offline | whole-list LWW overwrite from a load-time snapshot, no merge, only the empty-list edge case is guarded | two devices each add a different word offline, then sync | NEW |
| 14 | `SyncedAudiobooksView.swift:66-67` "Remove download" | the only copy of a not-yet-uploaded audiobook's audio | no upload-in-progress check (unlike `AudiobookSyncSheet` which does track `transfer`); no confirm | tap "Remove download" right after enabling sync | NEW |
| 15 | `AudiobookPlayerView.swift:467-483` `toggleBookmark` + `ChaptersBookmarksSheet.swift:95-98` (swipe) + `:266-268` (iPad long-press) | one or more audiobook bookmarks | fold-gutter tap can remove every bookmark within ±0.5s of the tap with one ambiguous "Unfolded" toast; swipe/long-press delete has no confirm on either surface | tap the fold gutter, or swipe/long-press a bookmark row | NEW |
| 16 | `BookImportSheet.swift:118-144` `unpack()` | a concurrently-synced copy of the same book | `alreadyHave` checked once at offer time, never re-verified/hash-checked at unpack time | the same shared book lands via CloudKit sync between offer and tap | NEW |
| 17 | `MemosListView.swift:483-488,516-518,1089-1091` (delete) + `WayOutView.swift:18-19,169,329,375-401,407-434` (fading/trash render) | not loss — exposure: a locked note's full title/transcript/photos render with no auth once trashed; `copyTranscript`/`copyableText` also bypass the lock | no `memo.locked` check on any delete entry point or on the fading-shelf row/peek | lock a note, delete it, open the Fading shelf | NEW — violates existing C161 |
| 18 | `CaptureVoiceAnnotate.swift:176` | a voice-annotation recording | deleted unconditionally after transcription, even when both live caption and the full ASR pass returned empty text; success haptic fires anyway | quiet/unintelligible voice annotation | NEW |
| 19 | `WallPrinter.swift:79-84` `printCard()` | the note's "already printed" ledger stamp | cleared BEFORE `tryDrain()` confirms the reprint reached the printer | manual reprint, printer unreachable | NEW |
| 20 | `Shared/Pipeline/ImageMarkers.swift:40-60` `insert` | marker order (not the picture itself) | stable-sort-by-descending-position reverses two markers that tie on the same nearest-word offset | two photos in one pause, or a fast burst | NEW — violates existing C13 |
| 21 | `MemoSaver.swift:860-862` + `Shared/Model/DeviceID.swift` | a `.transcribing` memo orphaned when its owning device is gone | recovery sweep only adopts a memo whose `recordingDeviceID` is nil or THIS device; a wiped/replaced phone can never adopt it | app killed mid-transcribe, phone later replaced | NEW |
| 22 | `SkriftApp.swift` (`RootView.needsOnboarding`) vs `RecordingIntentBridge` | a widget/Siri "Record" tap | no `RecordView` exists yet to consume the pending-start flag on a never-opened install; no expiry on the flag | Control Center tap before first app open | NEW — violates existing C100 |
| 23 | `MemoSaver.swift:171-172` `importAudioClipsAsync` | one clip's content out of a multi-clip merge | deletes ALL source clips after merge, even ones `mergeAudioSync` silently skipped as unreadable | 1 of N shared clips is corrupt/unreadable | NEW (minor) |
| 24 | `MemoSaver.swift:573-577` `appendRecordingAsync` | a freshly recorded append clip | deleted outright if the target memo vanished (race) between stop and append landing | memo deleted/purged mid-append | NEW (rare race) |
| 25 | `MemoSaver.swift:776-790` `movePhotos` | one captured photo | move failure is caught and skipped, no user-facing error, memo silently ends up one photo short | photo move fails during save | NEW (minor) |
| 26 | `NotesRepository.swift:259-268` `save()` | any single mutation (rating, delete, restore, name link, Mac polish write) | second consecutive SwiftData save failure only `DevLog`s, never reaches the UI | disk full / store corruption / CloudKit conflict | NEW — extends existing C168 |
| 27 | `FeedbackCaptureView.swift:95,69` | a fully transcribed feedback item (transcript + screenshot) | `interactiveDismissDisabled` only covers `.recording`/`.transcribing`, not `.review`; swipe-down during review discards silently | swipe-dismiss the feedback sheet after transcription lands | NEW (minor — his own feedback notes) |
| 28 | `MemoSaver.swift:740-755` `persist()` | a first-time recording, orphaned | already partially hardened (comment names the failure mode): if BOTH move and copy fail, the audio survives at `tempURL` but nothing links it back to the inserted `.failed` Memo | rare same-volume move+copy failure | NEW (minor, mostly mitigated) |
| 29 | `MemosListView.swift:1031-1035,1044-1051` bulk delete | N selected notes | no "Delete N notes?" confirm before bulk soft-delete | stray tap while multiple notes selected | NEW (minor — reversible, soft delete only) |
| 30 | `WordTimingsStore.swift:20`, `DiarizationStore.swift:23` | one memo's karaoke timings / diarization sidecar | non-atomic write (`try?`, no `.atomic`); degrades gracefully to "no timings" on decode failure | crash/kill mid-write | NEW (minor — graceful degradation) |
| 31 | `SkriftDesktop/Features/Shell/RunFile.swift:339-373` `-voiceloop` | the Dev container's entire `names.json` | in-memory-only backup, restore not wrapped in `defer` | crash during `-voiceloop <a> <b>` DEBUG dev harness | NEW (DEBUG-only, low likelihood) |
| 32 | `NotesRepository.swift` every `(try? … .fetch(...)) ?? []` | nothing real — UI-perceived: notes list/asset list/carriers all read as empty on a fetch fault | no distinction between "genuinely empty" and "read failed" | transient SwiftData fetch error | NEW (minor, not real loss) |

## Already tracked — re-confirmed present, not re-rowed above

- **D1** (`Shared/Naming/NamesStore.swift:50,28-33` — non-atomic write, empty-roster-on-decode) — re-confirmed by `a479987`, `a6ee1934`.
- **D2** (`SkriftDesktop/.../ProcessingCoordinator.swift:368-380` + `BatchRunner.swift:47-66,103-107` — re-transcribe clears before confirming) — re-confirmed by `ad17c703`; `a283505d` confirms the mobile `TranscriptionService.swift` does NOT reproduce this shape (D2 stays Desktop-only).
- **D3** (`SkriftDesktop/.../VaultExporter.swift:233-234,268-269,294-295` — attachment lane deletes a file it doesn't own) — re-confirmed by `ad17c703`, now THREE lanes in that file (was two).
- **D4** (`LiveRecordingService.swift:433` — recording lost if app dies mid-take) — re-confirmed by `a283505d`.
- **R42/R59** (corrupt bookmark blob / `bookmarks.json` wipes bookmarks; `receiveTranscripts` unverified) — re-confirmed end-to-end by `af2965fa`, traced through to the exact `adoptSynced`/LWW-stamp mechanism.
- **The AddPersonView `aliases: []` bug** (BUGS §2 "A person added on the phone can never be linked", `NamesListView.swift:202`) — `a6ee1934` re-confirms the same line, and additionally traces a WORSE reading: if the typed name collides with an EXISTING person's canonical, that person's real aliases get wiped (not just "new person has none"). Same fix, sharper stakes — worth a note when this bug is finally scheduled.
- **C163** (destination-change leaves the old exported file behind) — `ad17c703` confirms `MacCloudMetaSync.setDestination` still only flips the field, no cleanup.

## SAFE, reference-quality — patterns v2 should copy

- `MemoSaver.swift:691-724` `appendAudio` — atomic replace (`FileManager.replaceItemAt`) of a fully-built temp file; the file's own comment: "a failed swap or a kill mid-move can NEVER leave the memo with no audio file."
- `Shared/Retrieval/EmbeddingIndex.swift:107` — explicit `if snapshots.isEmpty, !existing.isEmpty { return }` guard so a failed fetch can never read as "library empty" and mass-purge the index.
- `Shared/Naming/NamesData.swift:154-184` `NamesMerge.mergeByCanonical` — additive fallback (`if local == nil { winner = remote! }`); a corrupted-empty local roster can't propagate as a deletion through the merge itself.
- `Skrift_Native/SkriftMobile/Services/AssetMaterializer.swift:44-57` — `guard !fileExists else { continue }` before every write; never overwrites an existing asset.
- `Skrift_Native/SkriftMobile/Services/MemoDeduper.swift:30-36` — detaches file references from a CloudKit-materialized clone BEFORE trashing it, so the eventual purge can never touch the keeper's blobs.
- `Skrift_Native/SkriftMobile/Services/Audiobooks/AudiobookImporter.swift:184-216` — multi-part import explicitly reports `skippedParts` instead of silently dropping a chapter.
- `Skrift_Native/SkriftMobile/Services/Audiobooks/BookTranscriptStore.swift:94-103` `load()` — decode failure returns `nil`, never writes anything back (contrast with `Bookmark.swift`/`Audiobook.swift`, which do the wrong thing).
- `Shared/ModelDownload/ResumableModelDownloader.swift:95-96,126-131` — size-verifies against the manifest BEFORE any removal; never deletes a different model revision's directory.
- `Skrift_Native/SkriftMobile/Services/DocScanner.swift:55` — real `try` (not `try?`); a failed PDF write returns `nil` and never inserts a memo pointing at a missing file.
- `Skrift_Native/SkriftMobile/Services/Audiobooks/BookAlignment.swift:914-948` `reconcileChapters` — preserves existing on-disk chapter marks rather than letting a partial local re-align wipe another device's chapters.

## Not reached

- **`AudiobookSession.endSession()` body** — flagged by `a9edcbf4` as destructive-styled (red menu text, no confirm) but its actual effect (playback teardown only, vs. resetting persisted position) was never read; no report covers `AudiobookSession.swift` beyond player-state teardown.
- **The caller-side speaker-merge logic** that actually rewrites turn/word-timing data when a speaker is reassigned — `a381c992` confirms `SpeakerAssignSheet.swift` itself only fires closures; the real mutation lives in `SpeakerTranscript`, never read by any of the 13 reports.
- **`NoteBodyView`'s bound `UIViewRepresentable` text host** — whether it can round-trip a spurious empty commit during a render race is the open question behind candidates #7/#8; `NoteBodyView.swift`'s `commitDraft` was read, but the UIKit text-view wrapper that calls it was not.
- **`WeatherClient.fetch`** — `ac24e468` notes `MetadataService.swift`'s "any failure yields nil" claim is inferred from a doc comment, not verified by reading `WeatherClient.swift` itself.
- **`a283505df2a919c55`** (mobile Services/Recording + misc) was flagged as possibly-still-running; its output file was complete with a finished candidates table at read time — included above, not listed as incomplete.
